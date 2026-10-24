unit LzNex.Migrator;

{ O runner de migrations. Semantica copiada do knex: batch, lock por UPDATE
  condicional, comparacao por NOME (sem checksum) e rollback do ultimo batch.

  Duas tabelas de controle, com nome vindo da config:
    <migrations>        id auto, name varchar(255), batch int, migration_time
    <migrations>_lock   index auto PK, is_locked int   (uma unica linha)

  LOCK: "update <lock> set is_locked = 1 where is_locked = 0" e conferir que
  afetou EXATAMENTE 1 linha. Zero linhas significa que outro processo pegou
  primeiro. E portavel (nao usa advisory lock de dialeto nenhum) e atomico
  porque o proprio UPDATE serializa no banco.

  Quem falha ao PEGAR o lock nao pode libera-lo: o lock e do outro processo.
  Qualquer outra falha libera, senao o lock fica preso para sempre. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Exceptions,
  LzNex.Intf,
  LzNex.Migration,
  LzNex.Migration.Source.Code,
  LzNex.Migration.Source.Sql;

type
  // Uma migration mais a fonte de onde veio.
  TLzNexMigrationEntry = record
    Migration: ILzNexMigration;
    Source: string;
  end;
  TLzNexMigrationEntries = array of TLzNexMigrationEntry;

  // Uma linha da tabela de controle.
  TLzNexAppliedRow = record
    Name: string;
    Batch: Integer;
    AppliedAt: TDateTime;
  end;
  TLzNexAppliedRows = array of TLzNexAppliedRow;

  TLzNexMigrator = class(TInterfacedObject, ILzNexMigrator)
  private
    { Referencia FORTE, e seguro: a facade cria um migrator novo a cada acesso
      a Db.Migrator e NAO guarda a instancia, entao nao ha ciclo de refcount.
      Se algum dia a facade passar a cachear, isto tem que virar weak. }
    FDb: ILzNex;
    FSources: array of ILzNexMigrationSource;
    FSourceCount: Integer;
    FTable: string;
    FLockTable: string;
    FTablesChecked: Boolean;

    function Db: ILzNex;
    function Log: ILzNexLogger;

    // Todas as migrations de todas as fontes, ordenadas por Id.
    function AllEntries: TLzNexMigrationEntries;
    function AppliedRows: TLzNexAppliedRows;
    function IsApplied(const ARows: TLzNexAppliedRows; const AName: string): Boolean;
    function NextBatch: Integer;
    function MaxBatch: Integer;

    // Linha na tabela sem migration correspondente em nenhuma fonte.
    procedure CheckCorruption(const AEntries: TLzNexMigrationEntries;
      const ARows: TLzNexAppliedRows);

    procedure Lock;
    procedure WarnIfDdlNotTransactional;
    procedure RunOne(const AMigration: ILzNexMigration;
      const ADirection: TLzNexMigrationDirection; const ABatch: Integer);
    procedure RecordApplied(const ADb: ILzNex; const AName: string;
      const ABatch: Integer);
    procedure RecordRemoved(const ADb: ILzNex; const AName: string);
    function IndexOfEntry(const AEntries: TLzNexMigrationEntries;
      const AName: string): Integer;
  public
    constructor Create(const ADb: ILzNex);
    class function New(const ADb: ILzNex): ILzNexMigrator;

    function AddSource(const ASource: ILzNexMigrationSource): ILzNexMigrator;
    function Latest: Integer;
    function Rollback: Integer;
    function RollbackAll: Integer;
    function Up(const AName: string = ''): Integer;
    function Down(const AName: string = ''): Integer;
    function MigrateTo(const AName: string): Integer;
    function Status: TLzNexMigrationStatusList;
    function Pending: TLzNexMigrationArray;
    function CurrentVersion: string;
    procedure Unlock;
    procedure EnsureTables;

    // Os nomes resolvidos das tabelas de controle.
    function TableName: string;
    function LockTableName: string;
    // Quantas fontes estao registradas.
    function SourceCount: Integer;
  end;

const
  // Devolvido por CurrentVersion quando nada foi aplicado.
  LZNEX_VERSION_NONE = 'none';

// O migrator pronto para uso: le a config da facade e ja registra as duas
// fontes (codigo e .sql no diretorio da config). Construtor barato de
// proposito -- nada aqui vai ao banco; quem vai e EnsureTables.
function NewMigrator(const ADb: ILzNex): ILzNexMigrator;

implementation

{ TLzNexMigrator }

constructor TLzNexMigrator.Create(const ADb: ILzNex);
var
  Cfg: ILzNexConfig;
begin
  inherited Create;
  if ADb = nil then
    raise ELzNexMigration.Create('Migrator created without a facade.');
  FDb := ADb;

  Cfg := ADb.Config;
  if Cfg = nil then
    FTable := LZNEX_MIGRATIONS_TABLE
  else
    FTable := Cfg.GetMigrationsTable;
  if Trim(FTable) = '' then
    FTable := LZNEX_MIGRATIONS_TABLE;
  FLockTable := FTable + LZNEX_MIGRATIONS_LOCK_SUFFIX;

  FSourceCount := 0;
  FTablesChecked := False;
end;

class function TLzNexMigrator.New(const ADb: ILzNex): ILzNexMigrator;
begin
  Result := TLzNexMigrator.Create(ADb);
end;

function TLzNexMigrator.Db: ILzNex;
begin
  Result := FDb;
end;

function TLzNexMigrator.Log: ILzNexLogger;
var
  Cfg: ILzNexConfig;
begin
  Result := nil;
  Cfg := Db.Config;
  if Cfg <> nil then
    Result := Cfg.GetLogger;
end;

function TLzNexMigrator.TableName: string;
begin
  Result := FTable;
end;

function TLzNexMigrator.LockTableName: string;
begin
  Result := FLockTable;
end;

function TLzNexMigrator.SourceCount: Integer;
begin
  Result := FSourceCount;
end;

function TLzNexMigrator.AddSource(const ASource: ILzNexMigrationSource): ILzNexMigrator;
begin
  if ASource = nil then
    raise ELzNexMigration.Create('AddSource received nil.');
  if FSourceCount >= Length(FSources) then
  begin
    if Length(FSources) = 0 then
      SetLength(FSources, 4)
    else
      SetLength(FSources, Length(FSources) * 2);
  end;
  FSources[FSourceCount] := ASource;
  Inc(FSourceCount);
  Result := Self;
end;

function TLzNexMigrator.AllEntries: TLzNexMigrationEntries;
var
  S, I, J, N, Slot: Integer;
  Items: TLzNexMigrationArray;
  Entry: TLzNexMigrationEntry;
begin
  Result := nil;
  if FSourceCount = 0 then
    raise ELzNexMigration.Create(
      'No migration source registered. Call AddSource with ' +
      'TLzNexCodeMigrationSource.New or TLzNexSqlMigrationSource.New(dir).');

  N := 0;
  for S := 0 to FSourceCount - 1 do
  begin
    Items := FSources[S].All;
    for I := 0 to High(Items) do
    begin
      Entry.Migration := Items[I];
      Entry.Source := FSources[S].SourceName;

      { Ordenacao final e por Id ENTRE TODAS as fontes, nao por fonte.
        Checagem antes de crescer o array: nada fica meio montado se levantar. }
      Slot := N;
      for J := 0 to N - 1 do
      begin
        if Result[J].Migration.Id = Entry.Migration.Id then
          raise ELzNexMigration.Create(
            'Duplicate migration id across sources: "' + Entry.Migration.Id +
            '".' + sLineBreak +
            '  ' + Result[J].Source + ': ' + Result[J].Migration.Name +
            sLineBreak +
            '  ' + Entry.Source + ': ' + Entry.Migration.Name);
        if Result[J].Migration.Id > Entry.Migration.Id then
        begin
          Slot := J;
          Break;
        end;
      end;

      SetLength(Result, N + 1);
      for J := N downto Slot + 1 do
        Result[J] := Result[J - 1];
      Result[Slot] := Entry;
      Inc(N);
    end;
  end;
end;

function TLzNexMigrator.AppliedRows: TLzNexAppliedRows;
var
  Res: ILzNexResult;
  N: Integer;
  V: TLzNexValue;
begin
  Result := nil;
  EnsureTables;
  Res := Db.Table(FTable)
    .Select(['name', 'batch', 'migration_time'])
    .OrderBy('id')
    .Get;
  N := 0;
  while Res.Next do
  begin
    SetLength(Result, N + 1);
    Result[N].Name := Res.Field('name').AsString;

    V := Res.Field('batch');
    if V.IsNull then
      Result[N].Batch := 0
    else
      Result[N].Batch := Integer(V.AsInt64);

    V := Res.Field('migration_time');
    if V.IsNull then
      Result[N].AppliedAt := 0
    else
      Result[N].AppliedAt := V.AsDateTime;

    Inc(N);
  end;
  Res.Close;
end;

function TLzNexMigrator.IsApplied(const ARows: TLzNexAppliedRows;
  const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(ARows) do
    if ARows[I].Name = AName then
      Exit(True);
end;

function TLzNexMigrator.IndexOfEntry(const AEntries: TLzNexMigrationEntries;
  const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(AEntries) do
    if AEntries[I].Migration.Name = AName then
      Exit(I);
end;

function TLzNexMigrator.MaxBatch: Integer;
var
  V: TLzNexValue;
begin
  V := Db.Table(FTable).Aggregate(agMax, 'batch');
  if V.IsNull or V.IsUnset then
    Result := 0
  else
    Result := Integer(V.AsInt64);
end;

function TLzNexMigrator.NextBatch: Integer;
begin
  Result := MaxBatch + 1;
end;

procedure TLzNexMigrator.CheckCorruption(const AEntries: TLzNexMigrationEntries;
  const ARows: TLzNexAppliedRows);
var
  I: Integer;
  Missing: string;
  Count: Integer;
begin
  Missing := '';
  Count := 0;
  for I := 0 to High(ARows) do
    if IndexOfEntry(AEntries, ARows[I].Name) < 0 then
    begin
      Missing := Missing + sLineBreak + '  - ' + ARows[I].Name +
        ' (batch ' + IntToStr(ARows[I].Batch) + ')';
      Inc(Count);
    end;

  if Count > 0 then
    raise ELzNexMigration.Create(
      Format('Table %s has %d applied migration(s) that do not exist in ' +
        'any source:', [FTable, Count]) + Missing + sLineBreak +
      'The comparison is by name. This happens when a file is renamed or ' +
      'deleted after being applied, or when the migration unit was dropped ' +
      'from the aggregator uses clause and was not linked. Restore the ' +
      'migration or delete the control table row by hand.');
end;

procedure TLzNexMigrator.EnsureTables;
var
  D: ILzNex;
begin
  if FTablesChecked then
    Exit;
  D := Db;

  if not D.Schema.HasTable(FTable) then
    D.Schema.CreateTable(FTable)
      .Increments('id')
      .Str('name', 255)
      .Int('batch')
      .Timestamp('migration_time')
      .Execute;

  if not D.Schema.HasTable(FLockTable) then
  begin
    D.Schema.CreateTable(FLockTable)
      .Increments('index')
      .Int('is_locked')
      .Execute;
    { A linha unica de lock: o UPDATE condicional precisa de uma linha
      existente para poder afetar exatamente uma. }
    D.Table(FLockTable).Insert(Vals(['is_locked', 0]));
  end
  else if not D.Table(FLockTable).Exists then
    D.Table(FLockTable).Insert(Vals(['is_locked', 0]));

  FTablesChecked := True;
end;

procedure TLzNexMigrator.Lock;
var
  Affected: Int64;
begin
  EnsureTables;
  Affected := Db.Table(FLockTable)
    .Where('is_locked', 0)
    .Update(Vals(['is_locked', 1]));

  if Affected <> 1 then
    raise ELzNexMigrationLock.Create(
      Format('The migrations table is already locked (%s affected %d rows, ' +
        'expected 1).', [FLockTable, Affected]) + sLineBreak +
      'Another process is migrating right now, or a previous process died ' +
      'holding the lock. If you are sure no migration is running, ' +
      'run "migrate:unlock".');
end;

procedure TLzNexMigrator.Unlock;
begin
  EnsureTables;
  Db.Table(FLockTable).Update(Vals(['is_locked', 0]));
end;

procedure TLzNexMigrator.WarnIfDdlNotTransactional;
var
  L: ILzNexLogger;
begin
  if Db.Client.DdlIsTransactional then
    Exit;
  L := Log;
  if L = nil then
    Exit;
  { Nao finge atomicidade: em MySQL o DDL faz COMMIT IMPLICITO e o rollback
    nao desfaz CREATE/ALTER/DROP, so o DML da mesma transacao. }
  L.LogWarning(
    'The ' + Db.Client.DialectName + ' dialect commits implicitly on DDL: ' +
    'if the migration fails midway, the rollback will NOT undo ' +
    'CREATE/ALTER/DROP already executed. Keep one migration per structural ' +
    'change so the damage stays small.');
end;

procedure TLzNexMigrator.RecordApplied(const ADb: ILzNex; const AName: string;
  const ABatch: Integer);
var
  V: TLzNexNamedValues;
begin
  { `array of const` nao transporta record, logo o TDateTime entra na mao. }
  V := Vals(['name', AName, 'batch', ABatch]);
  SetLength(V, 3);
  V[2].Name := 'migration_time';
  V[2].Value := TLzNexValue.FromDateTime(Now);
  ADb.Table(FTable).Insert(V);
end;

procedure TLzNexMigrator.RecordRemoved(const ADb: ILzNex; const AName: string);
begin
  ADb.Table(FTable).Where('name', AName).Delete;
end;

procedure TLzNexMigrator.RunOne(const AMigration: ILzNexMigration;
  const ADirection: TLzNexMigrationDirection; const ABatch: Integer);
var
  Trx: ILzNexTransaction;
  L: ILzNexLogger;
begin
  L := Log;
  if L <> nil then
  begin
    if ADirection = mdUp then
      L.LogInfo('migrate up   ' + AMigration.Name)
    else
      L.LogInfo('migrate down ' + AMigration.Name);
  end;

  if not AMigration.UseTransaction then
  begin
    { Sem transacao: a migration assumiu a responsabilidade. }
    if ADirection = mdUp then
    begin
      AMigration.Up(Db);
      RecordApplied(Db, AMigration.Name, ABatch);
    end
    else
    begin
      AMigration.Down(Db);
      RecordRemoved(Db, AMigration.Name);
    end;
    Exit;
  end;

  WarnIfDdlNotTransactional;

  Trx := Db.Transaction;
  try
    if ADirection = mdUp then
    begin
      AMigration.Up(Trx);
      RecordApplied(Trx, AMigration.Name, ABatch);
    end
    else
    begin
      AMigration.Down(Trx);
      RecordRemoved(Trx, AMigration.Name);
    end;
    Trx.Commit;
  except
    on E: Exception do
    begin
      if not Trx.IsCompleted then
        Trx.Rollback;
      raise ELzNexMigration.Create(
        'Migration ' + AMigration.Name + ' failed: ' + E.Message);
    end;
  end;
end;

function TLzNexMigrator.Latest: Integer;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  Batch, I: Integer;
begin
  Result := 0;
  Lock;
  try
    Entries := AllEntries;
    Rows := AppliedRows;
    CheckCorruption(Entries, Rows);
    Batch := NextBatch;
    for I := 0 to High(Entries) do
      if not IsApplied(Rows, Entries[I].Migration.Name) then
      begin
        RunOne(Entries[I].Migration, mdUp, Batch);
        Inc(Result);
      end;
  except
    { Qualquer falha que NAO seja a de pegar o lock libera o lock. A de pegar
      levanta antes do try e nunca chega aqui -- liberar ali seria liberar o
      lock do outro processo. }
    Unlock;
    raise;
  end;
  Unlock;
end;

function TLzNexMigrator.MigrateTo(const AName: string): Integer;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  Batch, I, Target: Integer;
begin
  Result := 0;
  Lock;
  try
    Entries := AllEntries;
    Rows := AppliedRows;
    CheckCorruption(Entries, Rows);

    Target := IndexOfEntry(Entries, AName);
    if Target < 0 then
      raise ELzNexMigration.Create(
        'Migration "' + AName + '" does not exist in any source.');

    Batch := NextBatch;
    for I := 0 to Target do
      if not IsApplied(Rows, Entries[I].Migration.Name) then
      begin
        RunOne(Entries[I].Migration, mdUp, Batch);
        Inc(Result);
      end;
  except
    Unlock;
    raise;
  end;
  Unlock;
end;

function TLzNexMigrator.Up(const AName: string): Integer;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  I, Target, Batch: Integer;
begin
  Result := 0;
  Lock;
  try
    Entries := AllEntries;
    Rows := AppliedRows;
    CheckCorruption(Entries, Rows);

    Target := -1;
    if AName = '' then
    begin
      for I := 0 to High(Entries) do
        if not IsApplied(Rows, Entries[I].Migration.Name) then
        begin
          Target := I;
          Break;
        end;
    end
    else
    begin
      Target := IndexOfEntry(Entries, AName);
      if Target < 0 then
        raise ELzNexMigration.Create(
          'Migration "' + AName + '" does not exist in any source.');
      if IsApplied(Rows, AName) then
        raise ELzNexMigration.Create(
          'Migration "' + AName + '" is already applied.');
    end;

    if Target >= 0 then
    begin
      Batch := NextBatch;
      RunOne(Entries[Target].Migration, mdUp, Batch);
      Result := 1;
    end;
  except
    Unlock;
    raise;
  end;
  Unlock;
end;

function TLzNexMigrator.Down(const AName: string): Integer;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  Target: Integer;
  Victim: string;
begin
  Result := 0;
  Lock;
  try
    Entries := AllEntries;
    Rows := AppliedRows;
    CheckCorruption(Entries, Rows);

    if AName = '' then
    begin
      if Length(Rows) = 0 then
        Victim := ''
      else
        Victim := Rows[High(Rows)].Name;
    end
    else
    begin
      if not IsApplied(Rows, AName) then
        raise ELzNexMigration.Create(
          'Migration "' + AName + '" is not applied.');
      Victim := AName;
    end;

    if Victim <> '' then
    begin
      Target := IndexOfEntry(Entries, Victim);
      RunOne(Entries[Target].Migration, mdDown, 0);
      Result := 1;
    end;
  except
    Unlock;
    raise;
  end;
  Unlock;
end;

function TLzNexMigrator.Rollback: Integer;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  Batch, I, Target: Integer;
begin
  Result := 0;
  Lock;
  try
    Entries := AllEntries;
    Rows := AppliedRows;
    CheckCorruption(Entries, Rows);

    Batch := MaxBatch;
    if Batch > 0 then
      { Ordem inversa da aplicacao: a ultima aplicada volta primeiro. }
      for I := High(Rows) downto 0 do
        if Rows[I].Batch = Batch then
        begin
          Target := IndexOfEntry(Entries, Rows[I].Name);
          RunOne(Entries[Target].Migration, mdDown, 0);
          Inc(Result);
        end;
  except
    Unlock;
    raise;
  end;
  Unlock;
end;

function TLzNexMigrator.RollbackAll: Integer;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  I, Target: Integer;
begin
  Result := 0;
  Lock;
  try
    Entries := AllEntries;
    Rows := AppliedRows;
    CheckCorruption(Entries, Rows);

    for I := High(Rows) downto 0 do
    begin
      Target := IndexOfEntry(Entries, Rows[I].Name);
      RunOne(Entries[Target].Migration, mdDown, 0);
      Inc(Result);
    end;
  except
    Unlock;
    raise;
  end;
  Unlock;
end;

function TLzNexMigrator.Status: TLzNexMigrationStatusList;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  I, J: Integer;
begin
  Result := nil;
  Entries := AllEntries;
  Rows := AppliedRows;
  CheckCorruption(Entries, Rows);

  SetLength(Result, Length(Entries));
  for I := 0 to High(Entries) do
  begin
    Result[I].Name := Entries[I].Migration.Name;
    Result[I].Source := Entries[I].Source;
    Result[I].Applied := False;
    Result[I].Batch := 0;
    Result[I].AppliedAt := 0;
    for J := 0 to High(Rows) do
      if Rows[J].Name = Result[I].Name then
      begin
        Result[I].Applied := True;
        Result[I].Batch := Rows[J].Batch;
        Result[I].AppliedAt := Rows[J].AppliedAt;
        Break;
      end;
  end;
end;

function TLzNexMigrator.Pending: TLzNexMigrationArray;
var
  Entries: TLzNexMigrationEntries;
  Rows: TLzNexAppliedRows;
  I, N: Integer;
begin
  Result := nil;
  Entries := AllEntries;
  Rows := AppliedRows;
  CheckCorruption(Entries, Rows);

  SetLength(Result, Length(Entries));
  N := 0;
  for I := 0 to High(Entries) do
    if not IsApplied(Rows, Entries[I].Migration.Name) then
    begin
      Result[N] := Entries[I].Migration;
      Inc(N);
    end;
  SetLength(Result, N);
end;

function TLzNexMigrator.CurrentVersion: string;
var
  Rows: TLzNexAppliedRows;
  I: Integer;
  Id: string;
begin
  Result := LZNEX_VERSION_NONE;
  Rows := AppliedRows;
  for I := 0 to High(Rows) do
  begin
    Id := MigrationIdOf(Rows[I].Name);
    { Maior Id, nao a ultima linha: aplicar fora de ordem (migrate:up de uma
      antiga) nao pode fazer a versao andar para tras. }
    if (Result = LZNEX_VERSION_NONE) or (Id > Result) then
      Result := Id;
  end;
end;

function NewMigrator(const ADb: ILzNex): ILzNexMigrator;
var
  Dir: string;
  Cfg: ILzNexConfig;
begin
  Result := TLzNexMigrator.New(ADb);
  Result.AddSource(TLzNexCodeMigrationSource.New);

  Cfg := ADb.Config;
  if Cfg <> nil then
    Dir := Cfg.GetMigrationsDir
  else
    Dir := '';
  { Opcional: projeto que so tem migration em Pascal nao tem o diretorio e
    nao pode quebrar por isso. }
  if Trim(Dir) <> '' then
    Result.AddSource(TLzNexSqlMigrationSource.NewOptional(Dir));
end;

end.
