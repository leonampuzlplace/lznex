unit LzNex.Cli;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  DateUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Exceptions;

type
  TLzNexCli = class
  private
    FDb: ILzNex;
    FArgs: TStringList;
    FQuiet: Boolean;
    function Arg(const AIndex: Integer): string;
    function HasFlag(const AName: string): Boolean;
    function FlagValue(const AName, ADefault: string): string;
    procedure Say(const AText: string);
    procedure SayFmt(const AFormat: string; const AArgs: array of const);

    function CmdMigrateLatest: Integer;
    function CmdMigrateRollback: Integer;
    function CmdMigrateUp: Integer;
    function CmdMigrateDown: Integer;
    function CmdMigrateTo: Integer;
    function CmdMigrateStatus: Integer;
    function CmdMigrateUnlock: Integer;
    function CmdMigrateVersion: Integer;
    function CmdMigrateMake: Integer;
    function CmdSeedRun: Integer;
    function CmdSeedMake: Integer;
    function CmdHelp: Integer;
  public
    constructor Create(const ADb: ILzNex);
    destructor Destroy; override;

    function Run(const ACommand: string; const AArgs: array of string): Integer;

    function RunFromCommandLine: Integer;
  end;

function MigrationTimestamp: string;

function MigrationFileName(const ADescription: string; const ASql: Boolean): string;

function Slugify(const AText: string): string;

implementation

const
  HELP_TEXT =
    'lznex -- migrations and seeds for Lazarus/FPC' + sLineBreak +
    sLineBreak +
    'Usage: lznex <command> [arguments] [--flags]' + sLineBreak +
    sLineBreak +
    'Migrations:' + sLineBreak +
    '  migrate:latest              run every pending migration in a new batch' + sLineBreak +
    '  migrate:rollback [--all]    undo the last batch (or everything with --all)' + sLineBreak +
    '  migrate:up [name]           run the next pending migration, or the given one' + sLineBreak +
    '  migrate:down [name]         undo the last applied migration, or the given one' + sLineBreak +
    '  migrate:to <name>           run pending migrations up to the given one' + sLineBreak +
    '  migrate:status              list applied and pending migrations' + sLineBreak +
    '  migrate:version             show the current version' + sLineBreak +
    '  migrate:unlock              release a lock left behind by a dead process' + sLineBreak +
    '  migrate:make <desc> [--sql] create a migration (Pascal, or a .sql pair)' + sLineBreak +
    sLineBreak +
    'Seeds:' + sLineBreak +
    '  seed:run [--only=name]      run the seeds' + sLineBreak +
    '  seed:make <desc>            create a seed' + sLineBreak +
    sLineBreak +
    'General flags:' + sLineBreak +
    '  --quiet                     only errors on output' + sLineBreak +
    '  --help                      this help';

  MIGRATION_STUB =
    'unit %0:s;' + sLineBreak +
    sLineBreak +
    '{$MODE DELPHI}{$H+}' + sLineBreak +
    sLineBreak +
    'interface' + sLineBreak +
    sLineBreak +
    'uses' + sLineBreak +
    '  LzNex.Intf,' + sLineBreak +
    '  LzNex.Migration;' + sLineBreak +
    sLineBreak +
    'type' + sLineBreak +
    '  T%1:s = class(TLzNexMigration)' + sLineBreak +
    '  public' + sLineBreak +
    '    class function Id: string; override;' + sLineBreak +
    '    class function MigrationName: string; override;' + sLineBreak +
    '    procedure Up(const ADb: ILzNex); override;' + sLineBreak +
    '    procedure Down(const ADb: ILzNex); override;' + sLineBreak +
    '  end;' + sLineBreak +
    sLineBreak +
    'implementation' + sLineBreak +
    sLineBreak +
    'class function T%1:s.Id: string;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := ''%2:s'';' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'class function T%1:s.MigrationName: string;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := ''%3:s'';' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'procedure T%1:s.Up(const ADb: ILzNex);' + sLineBreak +
    'begin' + sLineBreak +
    '  // ADb.Schema.CreateTable(''example'')' + sLineBreak +
    '  //   .Increments(''id'')' + sLineBreak +
    '  //   .Str(''name'', 120).NotNull' + sLineBreak +
    '  //   .Timestamps' + sLineBreak +
    '  //   .Execute;' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'procedure T%1:s.Down(const ADb: ILzNex);' + sLineBreak +
    'begin' + sLineBreak +
    '  // ADb.Schema.DropTableIfExists(''example'');' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'initialization' + sLineBreak +
    '  RegisterMigration(T%1:s);' + sLineBreak +
    sLineBreak +
    'end.' + sLineBreak;

constructor TLzNexCli.Create(const ADb: ILzNex);
begin
  inherited Create;
  FDb := ADb;
  FArgs := TStringList.Create;
end;

destructor TLzNexCli.Destroy;
begin
  FArgs.Free;
  inherited Destroy;
end;

function TLzNexCli.Arg(const AIndex: Integer): string;
var
  I, N: Integer;
begin

  Result := '';
  N := 0;
  for I := 0 to FArgs.Count - 1 do
  begin
    if Copy(FArgs[I], 1, 2) = '--' then
      Continue;
    if N = AIndex then
      Exit(FArgs[I]);
    Inc(N);
  end;
end;

function TLzNexCli.HasFlag(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FArgs.Count - 1 do
    if (FArgs[I] = '--' + AName) or (Copy(FArgs[I], 1, Length(AName) + 3) = '--' + AName + '=') then
      Exit(True);
end;

function TLzNexCli.FlagValue(const AName, ADefault: string): string;
var
  I, P: Integer;
  Prefix: string;
begin
  Result := ADefault;
  Prefix := '--' + AName + '=';
  for I := 0 to FArgs.Count - 1 do
    if Copy(FArgs[I], 1, Length(Prefix)) = Prefix then
    begin
      P := Length(Prefix);
      Exit(Copy(FArgs[I], P + 1, Length(FArgs[I])));
    end;
end;

procedure TLzNexCli.Say(const AText: string);
begin
  if FQuiet then
    Exit;
  Writeln(AText);
  Flush(Output);
end;

procedure TLzNexCli.SayFmt(const AFormat: string; const AArgs: array of const);
begin
  Say(Format(AFormat, AArgs));
end;

function TLzNexCli.CmdMigrateLatest: Integer;
var
  N: Integer;
begin
  FDb.Migrator.EnsureTables;
  N := FDb.Migrator.Latest;
  if N = 0 then
    Say('nothing to run: already at the latest version')
  else
    SayFmt('%d migration(s) applied', [N]);
  Result := 0;
end;

function TLzNexCli.CmdMigrateRollback: Integer;
var
  N: Integer;
begin
  FDb.Migrator.EnsureTables;
  if HasFlag('all') then
    N := FDb.Migrator.RollbackAll
  else
    N := FDb.Migrator.Rollback;
  if N = 0 then
    Say('nothing to undo')
  else
    SayFmt('%d migration(s) reverted', [N]);
  Result := 0;
end;

function TLzNexCli.CmdMigrateUp: Integer;
begin
  FDb.Migrator.EnsureTables;
  SayFmt('%d migration(s) applied', [FDb.Migrator.Up(Arg(0))]);
  Result := 0;
end;

function TLzNexCli.CmdMigrateDown: Integer;
begin
  FDb.Migrator.EnsureTables;
  SayFmt('%d migration(s) reverted', [FDb.Migrator.Down(Arg(0))]);
  Result := 0;
end;

function TLzNexCli.CmdMigrateTo: Integer;
begin
  if Arg(0) = '' then
  begin
    Writeln('error: migrate:to requires the target migration name');
    Flush(Output);
    Exit(2);
  end;
  FDb.Migrator.EnsureTables;
  SayFmt('%d migration(s) applied', [FDb.Migrator.MigrateTo(Arg(0))]);
  Result := 0;
end;

function TLzNexCli.CmdMigrateStatus: Integer;
var
  List: TLzNexMigrationStatusList;
  I, AppliedCount, PendingCount: Integer;
  StateLabel, BatchLabel: string;
begin
  FDb.Migrator.EnsureTables;
  List := FDb.Migrator.Status;
  AppliedCount := 0;
  PendingCount := 0;

  Say('  state    batch source migration');
  Say('  -------  ----- ------ ---------');
  for I := 0 to High(List) do
  begin
    if List[I].Applied then
    begin
      StateLabel := '  ok   ';
      BatchLabel := Format('%4d', [List[I].Batch]);
      Inc(AppliedCount);
    end
    else
    begin
      StateLabel := 'pending ';
      BatchLabel := '   -';
      Inc(PendingCount);
    end;
    SayFmt('  %-7s  %s  %-5s  %s', [StateLabel, BatchLabel, List[I].Source, List[I].Name]);
  end;

  Say('');
  SayFmt('%d applied, %d pending. Current version: %s',
    [AppliedCount, PendingCount, FDb.Migrator.CurrentVersion]);
  Result := 0;
end;

function TLzNexCli.CmdMigrateUnlock: Integer;
begin
  FDb.Migrator.Unlock;
  Say('lock released');
  Result := 0;
end;

function TLzNexCli.CmdMigrateVersion: Integer;
begin
  FDb.Migrator.EnsureTables;
  Say(FDb.Migrator.CurrentVersion);
  Result := 0;
end;

function TLzNexCli.CmdMigrateMake: Integer;
var
  Desc, Stamp, Slug, Dir, Base, UnitName, ClassIdent: string;
  F: TStringList;
begin
  Desc := Arg(0);
  if Desc = '' then
  begin
    Writeln('error: migrate:make requires a description. Example: lznex migrate:make create_users');
    Flush(Output);
    Exit(2);
  end;

  Stamp := MigrationTimestamp;
  Slug := Slugify(Desc);
  Dir := FDb.Config.GetMigrationsDir;
  ForceDirectories(Dir);

  F := TStringList.Create;
  try
    if HasFlag('sql') then
    begin
      Base := IncludeTrailingPathDelimiter(Dir) + Stamp + '_' + Slug;
      F.Text := '-- up: ' + Desc + sLineBreak;
      F.SaveToFile(Base + '.up.sql');
      F.Text := '-- down: revert ' + Desc + sLineBreak;
      F.SaveToFile(Base + '.down.sql');
      SayFmt('created: %s.up.sql', [Base]);
      SayFmt('created: %s.down.sql', [Base]);
      Say('.sql migrations are read at runtime: no rebuild needed.');
    end
    else
    begin
      UnitName := 'M' + Stamp + '_' + Slug;
      ClassIdent := Slug;
      if ClassIdent <> '' then
        ClassIdent[1] := UpCase(ClassIdent[1]);
      F.Text := Format(MIGRATION_STUB,
        [UnitName, ClassIdent, Stamp, Stamp + '_' + Slug]);
      F.SaveToFile(IncludeTrailingPathDelimiter(Dir) + UnitName + '.pas');
      SayFmt('created: %s', [IncludeTrailingPathDelimiter(Dir) + UnitName + '.pas']);
      Say('');
      SayFmt('WARNING: add "%s" to the `uses` clause of the migrations aggregator.', [UnitName]);
      Say('A unit nobody references is not linked by FPC, so its initialization');
      Say('never runs and the migration never registers itself.');
    end;
  finally
    F.Free;
  end;
  Result := 0;
end;

function TLzNexCli.CmdSeedRun: Integer;
var
  Only: string;
  N: Integer;
begin
  Only := FlagValue('only', '');
  if Only <> '' then
    N := FDb.Seeder.RunOne(Only)
  else
    N := FDb.Seeder.Run;
  SayFmt('%d seed(s) executed', [N]);
  Result := 0;
end;

function TLzNexCli.CmdSeedMake: Integer;
var
  Desc, Dir, Path: string;
  F: TStringList;
begin
  Desc := Arg(0);
  if Desc = '' then
  begin
    Writeln('error: seed:make requires a description');
    Flush(Output);
    Exit(2);
  end;
  Dir := FDb.Config.GetSeedsDir;
  ForceDirectories(Dir);
  Path := IncludeTrailingPathDelimiter(Dir) + Slugify(Desc) + '.sql';
  F := TStringList.Create;
  try
    F.Text := '-- seed: ' + Desc + sLineBreak;
    F.SaveToFile(Path);
  finally
    F.Free;
  end;
  SayFmt('created: %s', [Path]);
  Result := 0;
end;

function TLzNexCli.CmdHelp: Integer;
begin
  Writeln(HELP_TEXT);
  Flush(Output);
  Result := 0;
end;

function TLzNexCli.Run(const ACommand: string; const AArgs: array of string): Integer;
var
  I: Integer;
  Cmd: string;
begin
  FArgs.Clear;
  for I := 0 to High(AArgs) do
    FArgs.Add(AArgs[I]);
  FQuiet := HasFlag('quiet');

  Cmd := LowerCase(Trim(ACommand));
  // "--help" e "-h" chegam como comando, nao como flag: HasFlag so olha os
  // argumentos depois do verbo.
  if (Cmd = '') or (Cmd = 'help') or (Cmd = '--help') or (Cmd = '-h') or
     HasFlag('help') then
    Exit(CmdHelp);

  try
    if Cmd = 'migrate:latest' then Result := CmdMigrateLatest
    else if Cmd = 'migrate:rollback' then Result := CmdMigrateRollback
    else if Cmd = 'migrate:up' then Result := CmdMigrateUp
    else if Cmd = 'migrate:down' then Result := CmdMigrateDown
    else if Cmd = 'migrate:to' then Result := CmdMigrateTo
    else if (Cmd = 'migrate:status') or (Cmd = 'migrate:list') then Result := CmdMigrateStatus
    else if Cmd = 'migrate:unlock' then Result := CmdMigrateUnlock
    else if (Cmd = 'migrate:version') or (Cmd = 'migrate:currentversion') then Result := CmdMigrateVersion
    else if Cmd = 'migrate:make' then Result := CmdMigrateMake
    else if Cmd = 'seed:run' then Result := CmdSeedRun
    else if Cmd = 'seed:make' then Result := CmdSeedMake
    else
    begin
      Writeln('unknown command: ', ACommand);
      Writeln;
      Writeln(HELP_TEXT);
      Flush(Output);
      Result := 2;
    end;
  except

    on E: ELzNexMigrationLock do
    begin
      Writeln('lock error: ', E.Message);
      Flush(Output);
      Result := 3;
    end;
    on E: ELzNex do
    begin
      Writeln('error: ', E.Message);
      Flush(Output);
      Result := 1;
    end;
    on E: Exception do
    begin
      Writeln('unexpected error (', E.ClassName, '): ', E.Message);
      Flush(Output);
      Result := 1;
    end;
  end;
end;

function TLzNexCli.RunFromCommandLine: Integer;
var
  I: Integer;
  Rest: array of string;
begin
  Rest := nil;
  SetLength(Rest, 0);
  if ParamCount >= 2 then
  begin
    SetLength(Rest, ParamCount - 1);
    for I := 2 to ParamCount do
      Rest[I - 2] := ParamStr(I);
  end;
  Result := Run(ParamStr(1), Rest);
end;

function MigrationTimestamp: string;
var
  Y, M, D, H, N, S, MS: Word;
  UTC: TDateTime;
begin
  UTC := LocalTimeToUniversal(Now);
  DecodeDate(UTC, Y, M, D);
  DecodeTime(UTC, H, N, S, MS);
  Result := Format('%.4d%.2d%.2d%.2d%.2d%.2d', [Y, M, D, H, N, S]);
end;

function Slugify(const AText: string): string;
var
  I: Integer;
  C: Char;
  LastUnderscore: Boolean;
begin
  Result := '';
  LastUnderscore := True;
  for I := 1 to Length(AText) do
  begin
    C := AText[I];
    if C in ['A'..'Z'] then
      C := Chr(Ord(C) + 32);
    if (C in ['a'..'z', '0'..'9']) then
    begin
      Result := Result + C;
      LastUnderscore := False;
    end
    else if not LastUnderscore then
    begin
      Result := Result + '_';
      LastUnderscore := True;
    end;
  end;

  while (Result <> '') and (Result[Length(Result)] = '_') do
    Delete(Result, Length(Result), 1);
  if Result = '' then
    Result := 'migration';
end;

function MigrationFileName(const ADescription: string; const ASql: Boolean): string;
begin
  Result := MigrationTimestamp + '_' + Slugify(ADescription);
  if ASql then
    Result := Result + '.up.sql'
  else
    Result := 'M' + Result + '.pas';
end;

end.
