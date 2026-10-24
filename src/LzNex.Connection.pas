unit LzNex.Connection;

{ ILzNexConnection sobre IZConnection (camada DBC do Zeos).

  Duas decisoes que valem explicacao:

  1) Cache de prepared statement por conexao. Preparar custa um round-trip; numa
     API fluente o mesmo SQL sai centenas de vezes por segundo com binds
     diferentes. O cache e FIFO com teto fixo, porque LRU exigiria comparador
     customizado (que o FPC 3.2.2 nao digere bem) e porque o padrao de uso real
     e um conjunto pequeno e estavel de statements.

     Consequencia que o chamador precisa saber: um IZPreparedStatement so tem UM
     cursor aberto por vez. Reexecutar o mesmo SQL antes de consumir o
     ILzNexResult anterior invalida o anterior. Isso nao e um problema no uso
     normal porque conexao NAO e compartilhada entre threads (o pool entrega uma
     por requisicao) e porque o resultado e consumido antes da proxima query.

  2) Os parametros de conexao vem num record, nao em ILzNexConfig. Assim esta
     unit nao depende da implementacao da config (que mora em outra unit) e da
     para abrir conexao em teste sem montar a facade inteira. ParamsFromConfig
     faz a ponte quando a config existe. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  ZDbcIntfs,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Result,
  LzNex.Exceptions;

const
  // Teto do cache de prepared statements por conexao.
  LZNEX_STMT_CACHE_MAX = 64;

type
  // Dados de conexao sem depender de ILzNexConfig.
  TLzNexConnectionParams = record
    Protocol: string;      // 'mysql', 'postgresql'...
    Host: string;
    Port: Integer;
    Database: string;
    User: string;
    Password: string;
    // Caminho da lib cliente. No Ubuntu 26.04 o auto-load do Zeos falha,
    // entao informar isso explicitamente e praticamente obrigatorio.
    LibLocation: string;
    Charset: string;       // vira a propriedade 'codepage' do Zeos
    Props: TLzNexNamedValues;
    class function Empty: TLzNexConnectionParams; static;
    // A URL que o DriverManager do Zeos espera.
    function BuildURL: string;
  end;

  // Entrada do cache: SQL e o statement ja preparado.
  TLzNexCachedStmt = record
    SQL: string;
    Stmt: IZPreparedStatement;
  end;

  TLzNexConnection = class(TInterfacedObject, ILzNexConnection)
  private
    FClient: ILzNexClient;
    FZConn: IZConnection;
    FCache: array of TLzNexCachedStmt;
    FCacheCount: Integer;
    FTxLevel: Integer;
    // Devolve o statement do cache, preparando e guardando se faltar.
    function PrepareCached(const ASQL: string): IZPreparedStatement;
    // Tira o SQL do cache: usado quando a execucao falhou e o
    // statement pode ter ficado num estado que nao da para reaproveitar.
    procedure DropCached(const ASQL: string);
    procedure ClearCache;
    procedure BindAll(const AStmt: IZPreparedStatement;
      const ABindings: TLzNexBindings; const ASQL: string);
    function NeedZ: IZConnection;
  public
    constructor Create(const AClient: ILzNexClient; const AZConn: IZConnection);
    destructor Destroy; override;

    function Execute(const AFragment: TLzNexFragment): Int64;
    function Query(const AFragment: TLzNexFragment): ILzNexResult;
    function ExecuteScript(const ASQL: string): Int64;
    function LastInsertId: Int64;
    function StartTransaction: Integer;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function TransactionLevel: Integer;
    function Ping: Boolean;
    function IsClosed: Boolean;
    procedure Close;
    function Native: IInterface;
    function Client: ILzNexClient;

    // Quantos statements estao no cache. Existe para o teste provar
    // que o cache nao cresce sem limite.
    function CachedStatementCount: Integer;
  end;

// Abre uma conexao nova e a envolve.
function NewConnection(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams): ILzNexConnection; overload;

// Idem, lendo os dados da config. E a porta de entrada que a facade usa.
function NewConnection(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexConnection; overload;

// Envolve um IZConnection que o chamador abriu.
function WrapConnection(const AClient: ILzNexClient;
  const AZConn: IZConnection): ILzNexConnection;

// Copia da config para o record de parametros.
function ParamsFromConfig(const AConfig: ILzNexConfig): TLzNexConnectionParams;

// Traducao do nivel de isolamento do LzNex para o do Zeos.
function ZeosIsolation(const AIsolation: TLzNexIsolation): TZTransactIsolationLevel;

implementation

{ TLzNexConnectionParams }

class function TLzNexConnectionParams.Empty: TLzNexConnectionParams;
begin
  Result := Default(TLzNexConnectionParams);
  Result.Protocol := 'mysql';
  Result.Host := 'localhost';
  Result.Port := 0;
  Result.Charset := 'utf8mb4';
end;

function TLzNexConnectionParams.BuildURL: string;
var
  Url: TZURL;
  I: Integer;
begin
  Url := TZURL.Create;
  try
    Url.Protocol := Protocol;
    Url.HostName := Host;
    if Port > 0 then
      Url.Port := Port;
    Url.Database := Database;
    Url.UserName := User;
    Url.Password := Password;
    if LibLocation <> '' then
      Url.LibLocation := LibLocation;
    if Charset <> '' then
      // Sem isso o emoji vira '?' silenciosamente no MySQL.
      Url.Properties.Values['codepage'] := Charset;

    // Sem esta propriedade o Zeos trata bit(1)/tinyint(1) como texto 'Y'/'N':
    // SetBoolean manda a letra, e o MySQL recusa com "Incorrect integer value".
    // Ligada, tinyint(1) vira stBoolean na leitura e 0/1 no bind.
    if (Pos('mysql', LowerCase(Protocol)) = 1) or
       (Pos('mariadb', LowerCase(Protocol)) = 1) then
      Url.Properties.Values['MySQL_FieldType_Bit_1_IsBoolean'] := 'True';

    // Props por ultimo: o que o chamador informou vence os defaults acima.
    for I := 0 to High(Props) do
      Url.Properties.Values[Props[I].Name] := Props[I].Value.AsString;
    Result := Url.URL;
  finally
    Url.Free;
  end;
end;

function ParamsFromConfig(const AConfig: ILzNexConfig): TLzNexConnectionParams;
begin
  Result := TLzNexConnectionParams.Empty;
  if AConfig = nil then
    raise ELzNexConfig.Create('Nil config while building the connection parameters');

  // Campo vazio na config NAO sobrescreve o default: zerar o codepage, por
  // exemplo, faria o emoji virar '?' sem nenhum erro aparecer.
  if AConfig.GetClient <> '' then
    Result.Protocol := AConfig.GetClient;
  if AConfig.GetHost <> '' then
    Result.Host := AConfig.GetHost;
  if AConfig.GetPort > 0 then
    Result.Port := AConfig.GetPort;
  if AConfig.GetCharset <> '' then
    Result.Charset := AConfig.GetCharset;

  Result.Database := AConfig.GetDatabase;
  Result.User := AConfig.GetUser;
  Result.Password := AConfig.GetPassword;
  Result.LibLocation := AConfig.GetLibraryLocation;
  Result.Props := AConfig.GetProps;
end;

function ZeosIsolation(const AIsolation: TLzNexIsolation): TZTransactIsolationLevel;
begin
  case AIsolation of
    ilReadUncommitted: Result := tiReadUncommitted;
    ilReadCommitted:   Result := tiReadCommitted;
    ilRepeatableRead:  Result := tiRepeatableRead;
    ilSerializable:    Result := tiSerializable;
  else
    Result := tiNone;
  end;
end;

{ TLzNexConnection }

constructor TLzNexConnection.Create(const AClient: ILzNexClient;
  const AZConn: IZConnection);
begin
  inherited Create;
  if AZConn = nil then
    raise ELzNexConnection.Create('Nil Zeos connection');
  FClient := AClient;
  FZConn := AZConn;
  FCacheCount := 0;
  FTxLevel := 0;
  SetLength(FCache, 0);
end;

destructor TLzNexConnection.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TLzNexConnection.NeedZ: IZConnection;
begin
  if FZConn = nil then
    raise ELzNexConnection.Create('Connection already closed');
  Result := FZConn;
end;

procedure TLzNexConnection.ClearCache;
var
  I: Integer;
begin
  for I := 0 to FCacheCount - 1 do
  begin
    if FCache[I].Stmt <> nil then
    begin
      try
        FCache[I].Stmt.Close;
      except
        // Conexao caida ja invalidou o statement; nada a recuperar.
      end;
      FCache[I].Stmt := nil;
    end;
    FCache[I].SQL := '';
  end;
  FCacheCount := 0;
  SetLength(FCache, 0);
end;

procedure TLzNexConnection.DropCached(const ASQL: string);
var
  I, J: Integer;
begin
  for I := 0 to FCacheCount - 1 do
    if FCache[I].SQL = ASQL then
    begin
      try
        FCache[I].Stmt.Close;
      except
      end;
      for J := I to FCacheCount - 2 do
        FCache[J] := FCache[J + 1];
      FCache[FCacheCount - 1].SQL := '';
      FCache[FCacheCount - 1].Stmt := nil;
      Dec(FCacheCount);
      Exit;
    end;
end;

function TLzNexConnection.PrepareCached(const ASQL: string): IZPreparedStatement;
var
  I, J, Len: Integer;
begin
  Result := nil;
  Len := Length(ASQL);
  // Compara tamanho antes do texto: a varredura linear sobre no maximo
  // LZNEX_STMT_CACHE_MAX entradas sai mais barata que um hash do SQL inteiro.
  for I := 0 to FCacheCount - 1 do
    if (Length(FCache[I].SQL) = Len) and (FCache[I].SQL = ASQL) then
      Exit(FCache[I].Stmt);

  try
    Result := NeedZ.PrepareStatement(ASQL);
  except
    on E: Exception do
      raise ELzNexQuery.CreateFmt('Failed to prepare: ' + E.Message, ASQL);
  end;

  if FCacheCount >= LZNEX_STMT_CACHE_MAX then
  begin
    // Descarta o mais antigo e desloca: acontece raramente, porque o conjunto
    // de SQL distinto de uma aplicacao e pequeno e estavel.
    try
      FCache[0].Stmt.Close;
    except
    end;
    for J := 0 to FCacheCount - 2 do
      FCache[J] := FCache[J + 1];
    Dec(FCacheCount);
  end;

  if FCacheCount >= Length(FCache) then
    SetLength(FCache, FCacheCount + 8);
  FCache[FCacheCount].SQL := ASQL;
  FCache[FCacheCount].Stmt := Result;
  Inc(FCacheCount);
end;

procedure TLzNexConnection.BindAll(const AStmt: IZPreparedStatement;
  const ABindings: TLzNexBindings; const ASQL: string);
var
  I, P: Integer;
  V: TLzNexValue;
begin
  for I := 0 to ABindings.Count - 1 do
  begin
    V := ABindings.Items(I);
    P := I + FirstDbcIndex;
    case V.Kind of
      vkNull:
        AStmt.SetNull(P, stUnknown);
      vkBoolean:
        AStmt.SetBoolean(P, V.AsBoolean);
      vkInteger:
        AStmt.SetInt(P, Integer(V.AsInt64));
      vkInt64:
        AStmt.SetLong(P, V.AsInt64);
      vkFloat:
        AStmt.SetDouble(P, V.AsFloat);
      vkCurrency:
        AStmt.SetCurrency(P, V.AsCurrency);
      vkString:
        AStmt.SetString(P, V.AsString);
      vkBytes:
        AStmt.SetBytes(P, V.AsBytes);
      vkDate:
        AStmt.SetDate(P, V.AsDateTime);
      vkTime:
        AStmt.SetTime(P, V.AsDateTime);
      vkDateTime:
        AStmt.SetTimestamp(P, V.AsDateTime);
    else
      // vkUnset, vkIdentifier, vkRaw e vkSubQuery nunca deveriam chegar aqui:
      // identificador vai quotado no texto e raw/subquery tem binds proprios.
      raise ELzNexQuery.CreateFmt(
        Format('Bind %d is not a bindable value: %s', [I + 1, V.Describe]), ASQL);
    end;
  end;
end;

function TLzNexConnection.Execute(const AFragment: TLzNexFragment): Int64;
var
  Prep: IZPreparedStatement;
  SQL: string;
begin
  Result := 0;
  SQL := AFragment.Text;
  if SQL = '' then
    raise ELzNexQuery.CreateFmt('Empty SQL in Execute', SQL);

  Prep := PrepareCached(SQL);
  try
    BindAll(Prep, AFragment.Bindings, SQL);
    Result := Prep.ExecuteUpdatePrepared;
  except
    on E: ELzNex do
    begin
      DropCached(SQL);
      raise;
    end;
    on E: Exception do
    begin
      DropCached(SQL);
      raise ELzNexQuery.CreateFmt('Failed to execute: ' + E.Message, SQL);
    end;
  end;
end;

function TLzNexConnection.Query(const AFragment: TLzNexFragment): ILzNexResult;
var
  Prep: IZPreparedStatement;
  RS: IZResultSet;
  SQL: string;
begin
  Result := nil;
  SQL := AFragment.Text;
  if SQL = '' then
    raise ELzNexQuery.CreateFmt('Empty SQL in Query', SQL);

  Prep := PrepareCached(SQL);
  try
    BindAll(Prep, AFragment.Bindings, SQL);
    RS := Prep.ExecuteQueryPrepared;
  except
    on E: ELzNex do
    begin
      DropCached(SQL);
      raise;
    end;
    on E: Exception do
    begin
      DropCached(SQL);
      raise ELzNexQuery.CreateFmt('Query failed: ' + E.Message, SQL);
    end;
  end;

  if RS = nil then
    raise ELzNexQuery.CreateFmt('The query did not return a resultset', SQL);
  // Prep vai como owner: o cursor fica invalido se o statement morrer.
  Result := NewResult(RS, Prep);
end;

function TLzNexConnection.ExecuteScript(const ASQL: string): Int64;
var
  Stmt: IZStatement;
begin
  Result := 0;
  if Trim(ASQL) = '' then
    raise ELzNexQuery.CreateFmt('Empty SQL in ExecuteScript', ASQL);

  // Statement simples, nao preparado: o MySQL recusa boa parte do DDL
  // pelo protocolo de prepared statement.
  Stmt := NeedZ.CreateStatement;
  try
    try
      Result := Stmt.ExecuteUpdate(ASQL);
    except
      on E: Exception do
        raise ELzNexQuery.CreateFmt('Statement failed: ' + E.Message, ASQL);
    end;
  finally
    Stmt.Close;
  end;
end;

function TLzNexConnection.LastInsertId: Int64;
var
  SQL: string;
  Stmt: IZStatement;
  RS: IZResultSet;
  Dialect: string;
begin
  Result := 0;
  Dialect := '';
  if FClient <> nil then
    Dialect := LowerCase(FClient.DialectName);

  // ILzNexClient nao expoe um hook para isso, entao o SQL vai escolhido pelo
  // nome do dialeto. Ver relatorio: e uma lacuna do contrato.
  if (Dialect = 'postgresql') or (Dialect = 'postgres') then
    SQL := 'select lastval()'
  else if Dialect = 'sqlite' then
    SQL := 'select last_insert_rowid()'
  else
    SQL := 'select last_insert_id()';

  Stmt := NeedZ.CreateStatement;
  try
    try
      RS := Stmt.ExecuteQuery(SQL);
      if (RS <> nil) and RS.Next then
        Result := RS.GetLong(FirstDbcIndex);
      if RS <> nil then
        RS.Close;
    except
      on E: Exception do
        raise ELzNexQuery.CreateFmt('Failed to read the last insert id: ' + E.Message, SQL);
    end;
  finally
    Stmt.Close;
  end;
end;

function TLzNexConnection.StartTransaction: Integer;
begin
  Result := 0;
  try
    // O Zeos devolve 1 na transacao raiz e >1 no savepoint aninhado.
    Result := NeedZ.StartTransaction;
  except
    on E: Exception do
      raise ELzNexTransaction.Create('Failed to start transaction: ' + E.Message);
  end;
  FTxLevel := Result;
end;

procedure TLzNexConnection.Commit;
begin
  try
    NeedZ.Commit;
  except
    on E: Exception do
      raise ELzNexTransaction.Create('Commit failed: ' + E.Message);
  end;
  if FTxLevel > 0 then
    Dec(FTxLevel);
end;

procedure TLzNexConnection.Rollback;
begin
  try
    NeedZ.Rollback;
  except
    on E: Exception do
      raise ELzNexTransaction.Create('Rollback failed: ' + E.Message);
  end;
  if FTxLevel > 0 then
    Dec(FTxLevel);
end;

function TLzNexConnection.InTransaction: Boolean;
begin
  // Estado real do servidor, nao o contador: autocommit desligado e a
  // definicao de "dentro de transacao" no Zeos.
  Result := (FZConn <> nil) and (not FZConn.IsClosed) and (not FZConn.GetAutoCommit);
end;

function TLzNexConnection.TransactionLevel: Integer;
begin
  Result := FTxLevel;
end;

function TLzNexConnection.Ping: Boolean;
begin
  Result := False;
  if (FZConn = nil) then
    Exit;
  try
    if FZConn.IsClosed then
      Exit;
    Result := FZConn.PingServer = 0;
  except
    // Conexao morta levanta aqui; Ping nunca propaga, so responde False.
    Result := False;
  end;
end;

function TLzNexConnection.IsClosed: Boolean;
begin
  Result := (FZConn = nil) or FZConn.IsClosed;
end;

procedure TLzNexConnection.Close;
begin
  ClearCache;
  if FZConn <> nil then
  begin
    try
      if not FZConn.IsClosed then
        FZConn.Close;
    except
      // Fechar e best effort: a conexao pode ja ter caido do outro lado.
    end;
    FZConn := nil;
  end;
  FTxLevel := 0;
end;

function TLzNexConnection.Native: IInterface;
begin
  Result := FZConn;
end;

function TLzNexConnection.Client: ILzNexClient;
begin
  Result := FClient;
end;

function TLzNexConnection.CachedStatementCount: Integer;
begin
  Result := FCacheCount;
end;

{ fabricas }

function WrapConnection(const AClient: ILzNexClient;
  const AZConn: IZConnection): ILzNexConnection;
begin
  Result := TLzNexConnection.Create(AClient, AZConn) as ILzNexConnection;
end;

function NewConnection(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams): ILzNexConnection;
var
  Z: IZConnection;
  Url: string;
begin
  Url := AParams.BuildURL;
  try
    Z := DriverManager.GetConnection(Url);
    Z.Open;
  except
    on E: Exception do
      raise ELzNexConnection.CreateFmt(
        'Could not open connection to %s:%d/%s: %s. ' +
        'If the error mentions a library, set LibraryLocation: on Ubuntu 26.04 ' +
        'only libmariadb.so.3 exists and the Zeos auto-load does not find it.',
        [AParams.Host, AParams.Port, AParams.Database, E.Message]);
  end;
  Result := TLzNexConnection.Create(AClient, Z) as ILzNexConnection;
end;

function NewConnection(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexConnection;
var
  P: TLzNexConnectionParams;
begin
  P := ParamsFromConfig(AConfig);
  // O dialeto manda no protocolo: GetClient e o nome do dialeto do LzNex, que
  // nao e necessariamente o Protocol do Zeos.
  if AClient <> nil then
    P.Protocol := AClient.ZeosProtocol;
  Result := NewConnection(AClient, P);
end;

end.
