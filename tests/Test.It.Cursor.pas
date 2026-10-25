unit Test.It.Cursor;

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
  Test.It.Config;

type

  TCursorSharingTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
  published
    procedure TwoCursorsWithTheSameSqlKeepTheirOwnRows;
    procedure AnOpenCursorSurvivesCacheEviction;
    procedure NestedLoopOverTheSameSqlSeesEveryRow;
  end;

  TAggregateGroupingTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
  published
    procedure CountWithGroupByCountsGroups;
    procedure CountWithDistinctCountsDistinctRows;
    procedure CountWithHavingCountsSurvivingGroups;
  end;

  TTransactionSchemaTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
    procedure CreateThenRollback;
  published
    procedure SchemaInsideATransactionIsRolledBack;
  end;

implementation

const
  CUR_TABLE = 'it_cursor';
  AGG_TABLE = 'it_agg';
  TRX_DDL_TABLE = 'it_trx_ddl';

var
  GCursorReady: Boolean = False;
  GAggReady: Boolean = False;

procedure TCursorSharingTest.SetUp;
var
  I: Integer;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));
  if not GCursorReady then
  begin
    FDb.Schema.DropTableIfExists(CUR_TABLE);
    FDb.Schema.CreateTable(CUR_TABLE)
      .Increments('id')
      .Int('tenant').NotNull
      .Execute;
    for I := 1 to 40 do
      FDb.Table(CUR_TABLE).Insert(Vals(['tenant', (I mod 2) * 89 + 10]));
    GCursorReady := True;
  end;
end;

procedure TCursorSharingTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

function TCursorSharingTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: integration test skipped');
end;

procedure TCursorSharingTest.TwoCursorsWithTheSameSqlKeepTheirOwnRows;
var
  Trx: ILzNexTransaction;
  First, Second: ILzNexResult;
  SeenFirst: Integer;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  try

    First := Trx.Table(CUR_TABLE).Where('tenant', 10).OrderBy('id').Get;
    Second := Trx.Table(CUR_TABLE).Where('tenant', 99).OrderBy('id').Get;

    SeenFirst := 0;
    while First.Next do
    begin
      AssertEquals('the first cursor must keep its own bind', Int64(10),
        First.Field('tenant').AsInt64);
      Inc(SeenFirst);
    end;
    AssertEquals('the first cursor must still see its rows', 20, SeenFirst);

    First := nil;
    Second := nil;
    Trx.Rollback;
  finally
    Trx := nil;
  end;
end;

procedure TCursorSharingTest.AnOpenCursorSurvivesCacheEviction;
var
  Trx: ILzNexTransaction;
  Cursor, Filler: ILzNexResult;
  Tbl, Col: string;
  I, Seen: Integer;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  try
    Cursor := Trx.Table(CUR_TABLE).OrderBy('id').Get;
    Seen := 0;
    if Cursor.Next then
      Inc(Seen);

    Tbl := FDb.Client.WrapQualified(CUR_TABLE);
    Col := FDb.Client.WrapIdentifier('id');
    for I := 1 to 70 do
    begin
      Filler := Trx.Fetch(
        Format('select %s from %s where %s > %d', [Col, Tbl, Col, I]), []);
      Filler.Next;
      Filler.Close;
      Filler := nil;
    end;

    while Cursor.Next do
      Inc(Seen);
    AssertEquals('cache eviction must not truncate an open cursor', 40, Seen);

    Cursor := nil;
    Trx.Rollback;
  finally
    Trx := nil;
  end;
end;

procedure TCursorSharingTest.NestedLoopOverTheSameSqlSeesEveryRow;
var
  Trx: ILzNexTransaction;
  Outer, Inner: ILzNexResult;
  Outers, Inners: Integer;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  try
    Outers := 0;
    Inners := 0;
    Outer := Trx.Table(CUR_TABLE).Where('tenant', 10).OrderBy('id').Get;
    while Outer.Next do
    begin
      Inc(Outers);
      Inner := Trx.Table(CUR_TABLE).Where('tenant', 10).OrderBy('id').Get;
      while Inner.Next do
        Inc(Inners);
      Inner.Close;
      Inner := nil;
    end;
    Outer := nil;

    AssertEquals('the outer loop must run over every row', 20, Outers);
    AssertEquals('each pass of the inner loop must see every row', 400, Inners);
    Trx.Rollback;
  finally
    Trx := nil;
  end;
end;

procedure TAggregateGroupingTest.SetUp;
var
  I: Integer;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));
  if not GAggReady then
  begin
    FDb.Schema.DropTableIfExists(AGG_TABLE);
    FDb.Schema.CreateTable(AGG_TABLE)
      .Increments('id')
      .Str('grp', 10).NotNull
      .Execute;
    for I := 1 to 5 do FDb.Table(AGG_TABLE).Insert(Vals(['grp', 'a']));
    for I := 1 to 3 do FDb.Table(AGG_TABLE).Insert(Vals(['grp', 'b']));
    FDb.Table(AGG_TABLE).Insert(Vals(['grp', 'c']));
    GAggReady := True;
  end;
end;

procedure TAggregateGroupingTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

function TAggregateGroupingTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: integration test skipped');
end;

procedure TAggregateGroupingTest.CountWithGroupByCountsGroups;
begin
  if SkipWithoutDatabase then Exit;

  AssertEquals('count must answer how many groups, not the biggest group',
    Int64(3), FDb.Table(AGG_TABLE).Select(['grp']).GroupBy(['grp']).Count);
  AssertEquals('count and Paginate.Total must agree', Int64(3),
    FDb.Table(AGG_TABLE).Select(['grp']).GroupBy(['grp']).Paginate(1, 10).Total);
end;

procedure TAggregateGroupingTest.CountWithDistinctCountsDistinctRows;
begin
  if SkipWithoutDatabase then Exit;

  AssertEquals('count must keep the distinct', Int64(3),
    FDb.Table(AGG_TABLE).Select(['grp']).Distinct.Count);
  AssertEquals('count and Paginate.Total must agree', Int64(3),
    FDb.Table(AGG_TABLE).Select(['grp']).Distinct.Paginate(1, 10).Total);
end;

procedure TAggregateGroupingTest.CountWithHavingCountsSurvivingGroups;
begin
  if SkipWithoutDatabase then Exit;

  AssertEquals('only the groups that survive the having count', Int64(2),
    FDb.Table(AGG_TABLE).Select(['grp']).GroupBy(['grp'])
      .Having('grp', '>', 'a').Count);
end;

procedure TTransactionSchemaTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;
  FDb := Connect(ItConfig(4));
  FDb.Schema.DropTableIfExists(TRX_DDL_TABLE);
end;

procedure TTransactionSchemaTest.TearDown;
begin
  if FDb <> nil then
  begin
    try
      FDb.Schema.DropTableIfExists(TRX_DDL_TABLE);
    except
    end;
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

function TTransactionSchemaTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: integration test skipped');
end;

procedure TTransactionSchemaTest.CreateThenRollback;
var
  Trx: ILzNexTransaction;
begin
  Trx := FDb.Transaction;
  try
    Trx.Schema.CreateTable(TRX_DDL_TABLE).Increments('id').Execute;
    Trx.Rollback;
  finally
    Trx := nil;
  end;
end;

procedure TTransactionSchemaTest.SchemaInsideATransactionIsRolledBack;
begin
  if SkipWithoutDatabase then Exit;

  if not FDb.Client.DdlIsTransactional then
  begin
    Ignore('dialect commits DDL implicitly: nothing to roll back');
    Exit;
  end;

  CreateThenRollback;
  AssertFalse('DDL asked inside a transaction must be undone by the Rollback',
    FDb.Schema.HasTable(TRX_DDL_TABLE));
end;

initialization
  RegisterTest('integration', TCursorSharingTest);
  RegisterTest('integration', TAggregateGroupingTest);
  RegisterTest('integration', TTransactionSchemaTest);

end.
