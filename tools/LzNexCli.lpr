program LzNexCli;

{ Binario `lznex`: migrations e seeds pela linha de comando.

  A config sai de database/lznex.json (ou do caminho em LZNEX_CONFIG), com
  sobrescrita por variavel de ambiente -- que e o caminho usado em container. }

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
  LzNex.Client.MySQL,      // registra 'mysql' e 'mariadb' no registry
  Migrations.All;          // puxa as units de migration para o binario

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
      // Sem arquivo: vale so o ambiente. E o modo normal dentro do container.
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

  Flush(Output);   // stdout nao-tty e bufferizado
  ExitCode := Code;
end.
