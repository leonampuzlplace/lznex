program ZeosSpike;

{ Spike da Etapa 0: prova que o Zeos 8 compila em FPC sem LCL e que conecta num
  MySQL 8 com caching_sha2_password usando a camada DBC (sem TDataset). }

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils,
  Classes,
  ZDbcIntfs,
  ZDbcMySql;  // registra o driver 'mysql'/'mariadb' no initialization

const
  LIB_CANDIDATES: array[0..3] of string = (
    '/usr/lib/x86_64-linux-gnu/libmariadb.so.3',
    '/usr/lib/x86_64-linux-gnu/libmariadb.so',
    '/usr/lib/x86_64-linux-gnu/libmysqlclient.so.24',
    ''  // vazio = deixa o Zeos tentar o auto-load
  );

// Env — le variavel de ambiente com valor default.
function Env(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

// BuildUrl — monta a TZURL do Zeos. ALib vazio deixa o auto-load decidir.
function BuildUrl(const ALib: string): TZURL;
begin
  Result := TZURL.Create;
  Result.Protocol := Env('DB_PROTOCOL', 'mysql');
  Result.HostName := Env('DB_HOST', 'mysql');
  Result.Port     := StrToIntDef(Env('DB_PORT', '3306'), 3306);
  Result.Database := Env('DB_NAME', 'lznex');
  Result.UserName := Env('DB_USER', 'root');
  Result.Password := Env('DB_PASS', 'secret');
  if ALib <> '' then
    Result.LibLocation := ALib;
  // utf8mb4 desde a conexao; sem isso emoji vira '?' silenciosamente.
  Result.Properties.Values['codepage'] := 'utf8mb4';
end;

// TryConnect — tenta conectar com uma lib especifica. Nao levanta: devolve nil e o erro.
function TryConnect(const ALib: string; out AError: string): IZConnection;
var
  Url: TZURL;
begin
  Result := nil;
  AError := '';
  Url := BuildUrl(ALib);
  try
    try
      Result := DriverManager.GetConnection(Url.URL);
      Result.Open;
    except
      on E: Exception do
      begin
        AError := E.ClassName + ': ' + E.Message;
        Result := nil;
      end;
    end;
  finally
    Url.Free;
  end;
end;

// Connect — percorre os candidatos de lib e devolve a primeira conexao que abrir.
function Connect: IZConnection;
var
  I: Integer;
  Lib, Err, Label_: string;
begin
  Result := nil;
  for I := Low(LIB_CANDIDATES) to High(LIB_CANDIDATES) do
  begin
    Lib := LIB_CANDIDATES[I];
    if Lib = '' then
      Label_ := '(auto-load do Zeos)'
    else
      Label_ := Lib;

    Write('  tentando ', Label_, ' ... ');
    Flush(Output);

    Result := TryConnect(Lib, Err);
    if Result <> nil then
    begin
      Writeln('OK');
      Writeln('  >> lib que funcionou: ', Label_);
      Exit;
    end;
    Writeln('FALHOU');
    Writeln('     ', Err);
  end;
end;

// Step — imprime o titulo de uma etapa do spike.
procedure Step(const ATitle: string);
begin
  Writeln;
  Writeln('--- ', ATitle);
  Flush(Output);
end;

// Exec — roda um comando sem resultset e devolve as linhas afetadas.
function Exec(const AConn: IZConnection; const ASQL: string): Integer;
var
  Stmt: IZStatement;
begin
  Stmt := AConn.CreateStatement;
  try
    Result := Stmt.ExecuteUpdate(ASQL);
  finally
    Stmt.Close;
  end;
end;

var
  Conn: IZConnection;
  Stmt: IZStatement;
  Prep: IZPreparedStatement;
  RS: IZResultSet;
  Affected, Level: Integer;
  Nome: string;
  Vazado: Pointer;
begin
  // LEAK=1 vaza de proposito: serve para provar que o -gh esta realmente ativo
  // neste binario (sem isso, "nenhum relatorio" seria ambiguo).
  if GetEnvironmentVariable('LEAK') = '1' then
  begin
    GetMem(Vazado, 4321);
    Writeln('(LEAK=1: vazei 4321 bytes de proposito)');
  end;

  Writeln('=== Spike LzNex / Etapa 0 ===');
  Writeln('FPC ', {$I %FPCVERSION%}, ' / target ', {$I %FPCTARGETCPU%}, '-', {$I %FPCTARGETOS%});
  Flush(Output);

  Step('1. conexao (descobrindo qual lib cliente funciona)');
  Conn := Connect;
  if Conn = nil then
  begin
    Writeln;
    Writeln('ERRO: nenhuma lib cliente serviu. O spike falhou no ponto de maior risco.');
    Flush(Output);
    Halt(1);
  end;

  Writeln('  server : ', Conn.GetServerProvider = spMySQL);
  Flush(Output);

  Step('2. versao do servidor (round-trip real)');
  Stmt := Conn.CreateStatement;
  RS := Stmt.ExecuteQuery('select version() as v, @@character_set_connection as cs');
  if RS.Next then
    Writeln('  version=', RS.GetStringByName('v'), '  charset=', RS.GetStringByName('cs'));
  RS.Close;
  Stmt.Close;
  Flush(Output);

  Step('3. DDL (confirma que DDL passa pela camada DBC)');
  Exec(Conn, 'drop table if exists spike_t');
  Exec(Conn, 'create table spike_t (' +
             '  id int unsigned not null auto_increment primary key,' +
             '  nome varchar(120) not null,' +
             '  criado_em timestamp not null default current_timestamp' +
             ') engine=InnoDB default charset=utf8mb4');
  Writeln('  tabela spike_t criada');
  Flush(Output);

  Step('4. prepared statement com parametro (o caminho que o LzNex vai usar)');
  Prep := Conn.PrepareStatement('insert into spike_t (nome) values (?)');
  try
    Prep.SetString(FirstDbcIndex, 'Leonam ✅ acentuação');
    Affected := Prep.ExecuteUpdatePrepared;
    Writeln('  linhas afetadas: ', Affected);
  finally
    Prep.Close;
  end;
  Flush(Output);

  Step('5. leitura de volta (prova UTF-8 ponta a ponta)');
  Prep := Conn.PrepareStatement('select nome from spike_t where id = ?');
  try
    Prep.SetInt(FirstDbcIndex, 1);
    RS := Prep.ExecuteQueryPrepared;
    if RS.Next then
    begin
      Nome := RS.GetStringByName('nome');
      Writeln('  nome lido: ', Nome);
      if Nome <> 'Leonam ✅ acentuação' then
        Writeln('  AVISO: round-trip de UTF-8 nao bateu com o que foi gravado');
    end;
    RS.Close;
  finally
    Prep.Close;
  end;
  Flush(Output);

  Step('6. transacao + nivel de aninhamento (savepoint nativo do Zeos)');
  Level := Conn.StartTransaction;
  Writeln('  StartTransaction devolveu nivel: ', Level);
  Exec(Conn, 'insert into spike_t (nome) values (''sera descartado'')');
  Level := Conn.StartTransaction;
  Writeln('  aninhado devolveu nivel: ', Level, '  (>1 confirma savepoint)');
  Conn.Rollback;
  Conn.Rollback;

  Stmt := Conn.CreateStatement;
  RS := Stmt.ExecuteQuery('select count(*) as n from spike_t');
  if RS.Next then
    Writeln('  linhas apos rollback: ', RS.GetStringByName('n'), '  (esperado: 1)');
  RS.Close;
  Stmt.Close;
  Flush(Output);

  Step('7. metadata (base do HasTable/HasColumn)');
  RS := Conn.GetMetadata.GetTables('', '', 'spike_t', nil);
  if RS.Next then
    Writeln('  GetTables encontrou spike_t')
  else
    Writeln('  AVISO: GetTables nao encontrou spike_t');
  RS.Close;

  RS := Conn.GetMetadata.GetColumns('', '', 'spike_t', 'nome');
  if RS.Next then
    Writeln('  GetColumns encontrou spike_t.nome')
  else
    Writeln('  AVISO: GetColumns nao encontrou spike_t.nome');
  RS.Close;
  Flush(Output);

  Exec(Conn, 'drop table if exists spike_t');
  Conn.Close;

  Writeln;
  Writeln('=== spike OK: Zeos DBC compila e conversa com MySQL 8 ===');
  Flush(Output);
end.
