unit LzNex.Connection;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  ZDbcIntfs,
  ZExceptions,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Result,
  LzNex.Exceptions;

const

  LZNEX_STMT_CACHE_MAX = 64;

type

  TLzNexConnectionParams = record
    Protocol: string;
    Host: string;
    Port: Integer;
    Database: string;
    User: string;
    Password: string;

    LibLocation: string;
    Charset: string;
    Props: TLzNexNamedValues;
    class function Empty: TLzNexConnectionParams; static;

    function BuildURL: string;
  end;

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
    FLogger: ILzNexLogger;

    { Loga a execucao concluida. O tempo medido e o da ida ao banco, nao o da
      leitura das linhas: num Query, o cursor volta antes de o resultado ser
      consumido. Excecao do logger nunca derruba a query. }
    procedure LogDone(const ASQL: string; const ABindings: TLzNexBindings;
      const AStartTick: QWord);
    procedure LogFailed(const ASQL, AError: string);

    // Converte o erro do driver guardando codigo e SQLSTATE, que o retry usa.
    function DbError(const AMessage, ASQL: string;
      const AError: Exception): ELzNexQuery;

    function PrepareCached(const ASQL: string): IZPreparedStatement;

    procedure DropCached(const ASQL: string);
    procedure ClearCache;
    procedure BindAll(const AStmt: IZPreparedStatement;
      const ABindings: TLzNexBindings; const ASQL: string);
    function NeedZ: IZConnection;
  public
    constructor Create(const AClient: ILzNexClient; const AZConn: IZConnection;
      const ALogger: ILzNexLogger = nil);
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

    function CachedStatementCount: Integer;
  end;

function NewConnection(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams;
  const ALogger: ILzNexLogger = nil): ILzNexConnection; overload;

function NewConnection(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexConnection; overload;

function WrapConnection(const AClient: ILzNexClient;
  const AZConn: IZConnection): ILzNexConnection;

function ParamsFromConfig(const AConfig: ILzNexConfig): TLzNexConnectionParams;

function ZeosIsolation(const AIsolation: TLzNexIsolation): TZTransactIsolationLevel;

implementation

const

  // Mesmo valor de LZNEX_DEFAULT_CHARSET, repetido para nao arrastar
  // LzNex.Config para dentro da camada de conexao.
  LZNEX_MYSQL_DEFAULT_CHARSET = 'utf8mb4';

function ProtocolIs(const AProtocol, AName: string): Boolean;
begin
  Result := Pos(AName, LowerCase(AProtocol)) = 1;
end;

function ResolveCharset(const AProtocol, ACharset: string): string;
begin
  { O default do pacote e o nome do MySQL, que nao existe nos outros bancos.
    Charset escolhido a mao passa intacto. }
  Result := ACharset;
  if not SameText(ACharset, LZNEX_MYSQL_DEFAULT_CHARSET) then
    Exit;

  if ProtocolIs(AProtocol, 'firebird') or ProtocolIs(AProtocol, 'interbase') then
    Result := 'UTF8'
  else if ProtocolIs(AProtocol, 'sqlite') then
    Result := 'UTF-8';
end;

procedure ApplyProtocolDefaults(const AProtocol: string; const AProps: TStrings);
begin
  if ProtocolIs(AProtocol, 'mysql') or ProtocolIs(AProtocol, 'mariadb') then
  begin
    // Faz o tinyint(1)/bit(1) voltar como booleano, e nao como inteiro.
    AProps.Values['MySQL_FieldType_Bit_1_IsBoolean'] := 'True';
    Exit;
  end;

  if ProtocolIs(AProtocol, 'firebird') or ProtocolIs(AProtocol, 'interbase') then
  begin
    { Sem isso o Zeos faz commit retendo a transacao: a conexao do pool
      continuaria na mesma foto e nao veria o commit das outras. }
    AProps.Values['hard_commit'] := 'True';
    Exit;
  end;

  if ProtocolIs(AProtocol, 'sqlite') then
  begin
    { Sem timeout, duas conexoes do pool escrevendo ao mesmo tempo levantam
      SQLITE_BUSY na hora em vez de esperar a vez. }
    AProps.Values['busytimeout'] := '5000';

    // No modo WAL o leitor nao espera o escritor; no journal padrao, espera.
    AProps.Values['journal_mode'] := 'wal';

    // O SQLite nasce com FK desligada; ligada, ele se comporta como os outros.
    AProps.Values['foreign_keys'] := 'on';
  end;
end;

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

      Url.Properties.Values['codepage'] := ResolveCharset(Protocol, Charset);

    ApplyProtocolDefaults(Protocol, Url.Properties);

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

constructor TLzNexConnection.Create(const AClient: ILzNexClient;
  const AZConn: IZConnection; const ALogger: ILzNexLogger);
begin
  inherited Create;
  if AZConn = nil then
    raise ELzNexConnection.Create('Nil Zeos connection');
  FClient := AClient;
  FZConn := AZConn;
  FLogger := ALogger;
  FCacheCount := 0;
  FTxLevel := 0;
  SetLength(FCache, 0);
end;

procedure TLzNexConnection.LogDone(const ASQL: string;
  const ABindings: TLzNexBindings; const AStartTick: QWord);
begin
  if FLogger = nil then
    Exit;
  try
    FLogger.LogQuery(ASQL, ABindings, Int64(GetTickCount64 - AStartTick));
  except
    // Log quebrado nao pode derrubar quem estava so executando uma query.
  end;
end;

procedure TLzNexConnection.LogFailed(const ASQL, AError: string);
begin
  if FLogger = nil then
    Exit;
  try
    FLogger.LogError(ASQL, AError);
  except
  end;
end;

function TLzNexConnection.DbError(const AMessage, ASQL: string;
  const AError: Exception): ELzNexQuery;
var
  Code: Integer;
  State: string;
begin
  Code := 0;
  State := '';
  if AError is EZSQLThrowable then
  begin
    Code := EZSQLThrowable(AError).ErrorCode;
    State := EZSQLThrowable(AError).StatusCode;
  end;
  Result := ELzNexQuery.CreateDb(AMessage + AError.Message, ASQL, Code, State);
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

      raise ELzNexQuery.CreateFmt(
        Format('Bind %d is not a bindable value: %s', [I + 1, V.Describe]), ASQL);
    end;
  end;
end;

function TLzNexConnection.Execute(const AFragment: TLzNexFragment): Int64;
var
  Prep: IZPreparedStatement;
  SQL: string;
  Start: QWord;
begin
  Result := 0;
  SQL := AFragment.Text;
  if SQL = '' then
    raise ELzNexQuery.CreateFmt('Empty SQL in Execute', SQL);

  Prep := PrepareCached(SQL);
  Start := GetTickCount64;
  try
    BindAll(Prep, AFragment.Bindings, SQL);
    Result := Prep.ExecuteUpdatePrepared;
  except
    on E: ELzNex do
    begin
      DropCached(SQL);
      LogFailed(SQL, E.Message);
      raise;
    end;
    on E: Exception do
    begin
      DropCached(SQL);
      LogFailed(SQL, E.Message);
      raise DbError('Failed to execute: ', SQL, E);
    end;
  end;
  LogDone(SQL, AFragment.Bindings, Start);
end;

function TLzNexConnection.Query(const AFragment: TLzNexFragment): ILzNexResult;
var
  Prep: IZPreparedStatement;
  RS: IZResultSet;
  SQL: string;
  Start: QWord;
begin
  Result := nil;
  SQL := AFragment.Text;
  if SQL = '' then
    raise ELzNexQuery.CreateFmt('Empty SQL in Query', SQL);

  Prep := PrepareCached(SQL);
  Start := GetTickCount64;
  try
    BindAll(Prep, AFragment.Bindings, SQL);
    RS := Prep.ExecuteQueryPrepared;
  except
    on E: ELzNex do
    begin
      DropCached(SQL);
      LogFailed(SQL, E.Message);
      raise;
    end;
    on E: Exception do
    begin
      DropCached(SQL);
      LogFailed(SQL, E.Message);
      raise DbError('Query failed: ', SQL, E);
    end;
  end;
  LogDone(SQL, AFragment.Bindings, Start);

  if RS = nil then
    raise ELzNexQuery.CreateFmt('The query did not return a resultset', SQL);

  Result := NewResult(RS, Prep);
end;

function TLzNexConnection.ExecuteScript(const ASQL: string): Int64;
var
  Stmt: IZStatement;
  Start: QWord;
begin
  Result := 0;
  if Trim(ASQL) = '' then
    raise ELzNexQuery.CreateFmt('Empty SQL in ExecuteScript', ASQL);

  Stmt := NeedZ.CreateStatement;
  Start := GetTickCount64;
  try
    try
      Result := Stmt.ExecuteUpdate(ASQL);
      LogDone(ASQL, TLzNexBindings.Empty, Start);
    except
      on E: Exception do
      begin
        LogFailed(ASQL, E.Message);
        raise DbError('Statement failed: ', ASQL, E);
      end;
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

  if (Dialect = 'postgresql') or (Dialect = 'postgres') then
    SQL := 'select lastval()'
  else if Dialect = 'sqlite' then
    SQL := 'select last_insert_rowid()'
  else if Dialect = 'firebird' then
    raise ELzNexQuery.CreateFmt(
      'Firebird has no "last id of the session": the generator is per table. ' +
      'Use InsertGetId, which reads the id from the INSERT ... RETURNING ' +
      'itself.', '')
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
    on E: EZUnsupportedException do
      { Nem todo driver tem ping -- o do SQLite nao tem. Ali nao ha servidor
        para morrer do outro lado: conexao aberta e conexao viva. }
      Result := not FZConn.IsClosed;
  else

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

function WrapConnection(const AClient: ILzNexClient;
  const AZConn: IZConnection): ILzNexConnection;
begin
  Result := TLzNexConnection.Create(AClient, AZConn) as ILzNexConnection;
end;

function NewConnection(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams;
  const ALogger: ILzNexLogger): ILzNexConnection;
var
  Z: IZConnection;
  Url: string;
begin
  Url := AParams.BuildURL;
  try
    Z := DriverManager.GetConnection(Url);
    Z.Open;

    // Onde o default do servidor nao serve ao pool, o dialeto diz qual e o seu.
    if (AClient <> nil) and (AClient.DefaultIsolation <> ilDefault) then
      Z.SetTransactionIsolation(ZeosIsolation(AClient.DefaultIsolation));
  except
    on E: Exception do
      raise ELzNexConnection.CreateFmt(
        'Could not open connection to %s:%d/%s: %s. ' +
        'If the error mentions a library, set LibraryLocation: on Ubuntu 26.04 ' +
        'only libmariadb.so.3 exists and the Zeos auto-load does not find it.',
        [AParams.Host, AParams.Port, AParams.Database, E.Message]);
  end;
  Result := TLzNexConnection.Create(AClient, Z, ALogger) as ILzNexConnection;
end;

function NewConnection(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexConnection;
var
  P: TLzNexConnectionParams;
  Log: ILzNexLogger;
begin
  P := ParamsFromConfig(AConfig);

  if AClient <> nil then
    P.Protocol := AClient.ZeosProtocol;

  Log := nil;
  if AConfig <> nil then
    Log := AConfig.GetLogger;
  Result := NewConnection(AClient, P, Log);
end;

end.
