program LzNexCli;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils,
  LzNex,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Cli,

  LzNex.Client.MySQL,
  LzNex.Client.Postgres,
  LzNex.Client.Firebird,
  LzNex.Client.SQLite,
  Migrations.All;

function ConfigPath: string;
var
  Env: string;
begin
  Env := GetEnvironmentVariable('LZNEX_CONFIG');
  if Env <> '' then
    Exit(Env);
  Result := 'database/lznex.json';
end;

var
  Db: ILzNex;
  Cli: TLzNexCli;
  Code: Integer;
begin
  Code := 1;
  try
    if FileExists(ConfigPath) then
      Db := ConnectFromFile(ConfigPath, GetEnvironmentVariable('LZNEX_ENV'))
    else

      Db := Connect(NewConfig);

    Cli := TLzNexCli.Create(Db);
    try
      Code := Cli.RunFromCommandLine;
    finally
      Cli.Free;
    end;

    Db.Shutdown;
    Db := nil;
  except
    on E: ELzNexConfig do
    begin
      Writeln('configuration error: ', E.Message);
      Writeln('Provide it through ', ConfigPath, ' or the LZNEX_HOST, ',
        'LZNEX_DATABASE, LZNEX_USER, LZNEX_PASSWORD.');
      Code := 2;
    end;
    on E: Exception do
    begin
      Writeln('error (', E.ClassName, '): ', E.Message);
      Code := 1;
    end;
  end;

  Flush(Output);
  ExitCode := Code;
end.
