unit Test.It.Migrator;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  LzNex,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Migration,
  LzNex.Migrator,
  Test.It.Config;

type

  TItCreateThings = class(TLzNexMigration)
  public
    class function MigrationName: string; override;
    procedure Up(const ADb: ILzNex); override;
    procedure Down(const ADb: ILzNex); override;
  end;

  TMigratorTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
  published
    procedure LatestCreatesTheControlTablesAndApplies;
    procedure LatestIsIdempotent;
    procedure RollbackUndoesTheMigration;
    procedure StatusAndPendingFollowTheRun;
    procedure LockRefusesASecondRunAndUnlockFreesIt;
  end;

implementation

const
  MIG_TABLE  = 'it_migrations';
  LOCK_TABLE = 'it_migrations_lock';
  THINGS     = 'it_mig_things';
  MIG_NAME   = '20261026101500_create_things';

class function TItCreateThings.MigrationName: string;
begin
  Result := MIG_NAME;
end;

procedure TItCreateThings.Up(const ADb: ILzNex);
begin
  ADb.Schema.CreateTable(THINGS)
    .Increments('id')
    .Str('label', 80).NotNull
    .Bool('active').Default_(True)
    .Timestamp('created_at')
    .Execute;
end;

procedure TItCreateThings.Down(const ADb: ILzNex);
begin
  ADb.Schema.DropTableIfExists(THINGS);
end;

function TMigratorTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: migrator test skipped');
end;

procedure TMigratorTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4)
    .MigrationsTable(MIG_TABLE)
    .MigrationsDir(''));

  FDb.Schema.DropTableIfExists(THINGS);
  FDb.Schema.DropTableIfExists(LOCK_TABLE);
  FDb.Schema.DropTableIfExists(MIG_TABLE);
end;

procedure TMigratorTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TMigratorTest.LatestCreatesTheControlTablesAndApplies;
var
  Applied: Integer;
begin
  if SkipWithoutDatabase then Exit;

  Applied := FDb.Migrator.Latest;

  AssertEquals('one migration applied', 1, Applied);
  AssertTrue('control table was created', FDb.Schema.HasTable(MIG_TABLE));
  AssertTrue('lock table was created', FDb.Schema.HasTable(LOCK_TABLE));
  AssertTrue('the migration ran', FDb.Schema.HasTable(THINGS));
  AssertTrue('and its columns exist',
    FDb.Schema.HasColumn(THINGS, 'label'));
end;

procedure TMigratorTest.LatestIsIdempotent;
begin
  if SkipWithoutDatabase then Exit;

  AssertEquals('first run applies', 1, FDb.Migrator.Latest);

  AssertEquals('second run has nothing to do', 0, FDb.Migrator.Latest);
end;

procedure TMigratorTest.RollbackUndoesTheMigration;
begin
  if SkipWithoutDatabase then Exit;

  FDb.Migrator.Latest;
  AssertEquals('one migration reverted', 1, FDb.Migrator.Rollback);

  AssertFalse('the table is gone', FDb.Schema.HasTable(THINGS));
  AssertEquals('and nothing is applied anymore', LZNEX_VERSION_NONE,
    FDb.Migrator.CurrentVersion);
end;

procedure TMigratorTest.StatusAndPendingFollowTheRun;
var
  Status: TLzNexMigrationStatusList;
  Pending: TLzNexMigrationArray;
begin
  if SkipWithoutDatabase then Exit;

  Pending := FDb.Migrator.Pending;
  AssertEquals('pending before the run', 1, Length(Pending));

  FDb.Migrator.Latest;

  Status := FDb.Migrator.Status;
  AssertEquals('status lists the migration', 1, Length(Status));
  AssertEquals('by name', MIG_NAME, Status[0].Name);
  AssertTrue('marked as applied', Status[0].Applied);
  AssertEquals('in the first batch', 1, Status[0].Batch);
  AssertEquals('nothing pending after the run', 0,
    Length(FDb.Migrator.Pending));
  AssertEquals('current version', '20261026101500',
    FDb.Migrator.CurrentVersion);
end;

procedure TMigratorTest.LockRefusesASecondRunAndUnlockFreesIt;
var
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;

  FDb.Migrator.EnsureTables;

  AssertEquals('the lock was taken', Int64(1),
    FDb.Table(LOCK_TABLE).Update(Vals(['is_locked', 1])));

  Raised := False;
  try
    FDb.Migrator.Latest;
  except
    on E: ELzNexMigrationLock do
      Raised := True;
  end;
  AssertTrue('a locked table refuses the run', Raised);

  FDb.Migrator.Unlock;
  AssertEquals('and after unlock it runs', 1, FDb.Migrator.Latest);
end;

initialization
  RegisterMigration(TItCreateThings);
  RegisterTest('integration', TMigratorTest);

end.
