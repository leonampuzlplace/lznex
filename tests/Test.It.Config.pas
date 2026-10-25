unit Test.It.Config;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex,
  LzNex.Intf,
  LzNex.Client.MySQL,
  LzNex.Client.Postgres;

// Se a suite de integracao deve rodar. Sem LZNEX_IT nao ha banco por perto.
function ItEnabled: Boolean;

// O dialeto da rodada: LZNEX_CLIENT, default 'mysql'.
function ItClient: string;

// Config apontando para o banco da rodada. Host, porta e biblioteca tem
// default por dialeto; qualquer um deles pode vir do ambiente.
function ItConfig(const APoolMax: Integer = 8): ILzNexConfig;

implementation

function EnvOr(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

function ItEnabled: Boolean;
begin
  Result := GetEnvironmentVariable('LZNEX_IT') <> '';
end;

function ItClient: string;
begin
  Result := LowerCase(EnvOr('LZNEX_CLIENT', 'mysql'));
end;

function IsPostgres: Boolean;
var
  C: string;
begin
  C := ItClient;
  Result := (C = 'postgresql') or (C = 'postgres');
end;

function DefaultHost: string;
begin
  if IsPostgres then
    Result := 'postgres'
  else
    Result := 'mysql';
end;

function DefaultPort: Integer;
begin
  if IsPostgres then
    Result := 5432
  else
    Result := 3306;
end;

function DefaultLibrary: string;
begin
  { Em nenhum dos dois o auto-load do Zeos acerta sozinho no Ubuntu: o MySQL so
    tem libmariadb e a libpq vem com sufixo de versao. }
  if IsPostgres then
    Result := '/usr/lib/x86_64-linux-gnu/libpq.so.5'
  else
    Result := '/usr/lib/x86_64-linux-gnu/libmariadb.so.3';
end;

function DefaultUser: string;
begin
  if IsPostgres then
    Result := 'postgres'
  else
    Result := 'root';
end;

function ItConfig(const APoolMax: Integer): ILzNexConfig;
begin
  Result := NewConfig
    .Client(ItClient)
    .Host(EnvOr('DB_HOST', DefaultHost))
    .Port(StrToIntDef(EnvOr('DB_PORT', IntToStr(DefaultPort)), DefaultPort))
    .Database(EnvOr('DB_NAME', 'lznex'))
    .User(EnvOr('DB_USER', DefaultUser))
    .Password(EnvOr('DB_PASS', 'secret'))
    .LibraryLocation(EnvOr('DB_LIB', DefaultLibrary))
    .Pool(2, APoolMax);
end;

end.
