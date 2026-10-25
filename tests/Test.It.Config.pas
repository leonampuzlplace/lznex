unit Test.It.Config;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex,
  LzNex.Intf,
  LzNex.Client.MySQL,
  LzNex.Client.Postgres,
  LzNex.Client.Firebird,
  LzNex.Client.SQLite;

function ItEnabled: Boolean;

function ItClient: string;

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

function IsFirebird: Boolean;
begin
  Result := ItClient = 'firebird';
end;

function IsSQLite: Boolean;
var
  C: string;
begin
  C := ItClient;
  Result := (C = 'sqlite') or (C = 'sqlite3');
end;

function DefaultHost: string;
begin
  if IsSQLite then
    Result := ''
  else if IsPostgres then
    Result := 'postgres'
  else if IsFirebird then
    Result := 'firebird'
  else
    Result := 'mysql';
end;

function DefaultPort: Integer;
begin
  if IsPostgres then
    Result := 5432
  else if IsFirebird then
    Result := 3050
  else
    Result := 3306;
end;

function DefaultLibrary: string;
begin

  if IsSQLite then
    Result := '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0'
  else if IsPostgres then
    Result := '/usr/lib/x86_64-linux-gnu/libpq.so.5'
  else if IsFirebird then
    Result := '/usr/lib/x86_64-linux-gnu/libfbclient.so.2'
  else
    Result := '/usr/lib/x86_64-linux-gnu/libmariadb.so.3';
end;

function DefaultUser: string;
begin
  if IsSQLite then
    Result := ''
  else if IsPostgres then
    Result := 'postgres'
  else if IsFirebird then
    Result := 'SYSDBA'
  else
    Result := 'root';
end;

function DefaultDatabase: string;
begin
  if IsSQLite then
    Result := '/tmp/lznex-it.sqlite'
  else if IsFirebird then
    Result := '/var/lib/firebird/data/lznex.fdb'
  else
    Result := 'lznex';
end;

function DefaultCharset: string;
begin
  if IsFirebird then
    Result := 'UTF8'
  else if IsSQLite then
    Result := 'UTF-8'
  else
    Result := 'utf8mb4';
end;

function ItConfig(const APoolMax: Integer): ILzNexConfig;
begin
  Result := NewConfig
    .Client(ItClient)
    .Host(EnvOr('DB_HOST', DefaultHost))
    .Port(StrToIntDef(EnvOr('DB_PORT', IntToStr(DefaultPort)), DefaultPort))
    .Database(EnvOr('DB_NAME', DefaultDatabase))
    .User(EnvOr('DB_USER', DefaultUser))
    .Password(EnvOr('DB_PASS', 'secret'))
    .LibraryLocation(EnvOr('DB_LIB', DefaultLibrary))
    .Charset(EnvOr('DB_CHARSET', DefaultCharset))
    .Pool(2, APoolMax);
end;

end.
