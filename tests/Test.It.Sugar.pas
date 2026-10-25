unit Test.It.Sugar;

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

  { FirstOrFail, Sole, DoesntExist, Upsert, UpdateOrInsert e WithCount contra
    banco de verdade, nos cinco dialetos. }
  TSugarFeatureTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
    procedure Seed;
  published
    procedure FirstOrFailReturnsTheRowWhenItExists;
    procedure FirstOrFailRaisesWhenNothingMatches;
    procedure SoleReturnsTheSingleMatch;
    procedure SoleRaisesWhenNothingMatches;
    procedure SoleRaisesWhenMoreThanOneMatches;
    procedure DoesntExistIsTheOppositeOfExists;
    procedure UpdateOrInsertInsertsWhenTheKeyIsAbsent;
    procedure UpdateOrInsertUpdatesWhenTheKeyExists;
    procedure UpdateOrInsertDoesNotDuplicateTheRow;
    procedure UpdateOrInsertStillReportsAnUpdateWhenTheValueDoesNotChange;
    procedure UpsertInsertsAndUpdatesInOneCall;
    procedure UpsertOnFirebirdRejectsMoreThanOneRow;
    procedure WithCountCountsRealChildren;
  end;

implementation

const
  TABLE = 'it_sugar';
  CHILD_TABLE = 'it_sugar_child';

var
  GTableReady: Boolean = False;

function TSugarFeatureTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: sugar test skipped');
end;

procedure TSugarFeatureTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin
    FDb.Schema.DropTableIfExists(CHILD_TABLE);
    FDb.Schema.DropTableIfExists(TABLE);
    FDb.Schema.CreateTable(TABLE)
      .Increments('id')
      .Str('tag', 60).NotNull.Unique
      .Int('score').Nullable
      .Execute;
    // "parent_tag" e uma FK logica para it_sugar.tag -- sem constraint de
    // verdade, so para o WithCount ter o que contar.
    FDb.Schema.CreateTable(CHILD_TABLE)
      .Increments('id')
      .Str('parent_tag', 60).NotNull
      .Int('note').Nullable
      .Execute;
    GTableReady := True;
  end;
end;

procedure TSugarFeatureTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TSugarFeatureTest.Seed;
begin
  FDb.Table(CHILD_TABLE).Truncate;
  FDb.Table(TABLE).Truncate;
  FDb.Table(TABLE).Insert(Vals(['tag', 'aaa', 'score', 10]));
  FDb.Table(TABLE).Insert(Vals(['tag', 'bbb', 'score', 20]));
  FDb.Table(TABLE).Insert(Vals(['tag', 'ccc', 'score', 30]));
end;

procedure TSugarFeatureTest.FirstOrFailReturnsTheRowWhenItExists;
var
  Row: ILzNexRow;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Row := FDb.Table(TABLE).Where('tag', 'bbb').FirstOrFail;
  AssertEquals('found the row by tag', Int64(20), Row.Field('score').AsInt64);
end;

procedure TSugarFeatureTest.FirstOrFailRaisesWhenNothingMatches;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  try
    FDb.Table(TABLE).Where('tag', 'nope').FirstOrFail;
    Fail('expected ELzNexQuery when nothing matches');
  except
    on E: ELzNexQuery do ;
  end;
end;

procedure TSugarFeatureTest.SoleReturnsTheSingleMatch;
var
  Row: ILzNexRow;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Row := FDb.Table(TABLE).Where('tag', 'ccc').Sole;
  AssertEquals('found the single matching row', Int64(30), Row.Field('score').AsInt64);
end;

procedure TSugarFeatureTest.SoleRaisesWhenNothingMatches;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  try
    FDb.Table(TABLE).Where('tag', 'nope').Sole;
    Fail('expected ELzNexQuery when nothing matches');
  except
    on E: ELzNexQuery do ;
  end;
end;

procedure TSugarFeatureTest.SoleRaisesWhenMoreThanOneMatches;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  try
    // sem Where, as tres linhas semeadas casam todas
    FDb.Table(TABLE).Sole;
    Fail('expected ELzNexQuery when more than one row matches');
  except
    on E: ELzNexQuery do ;
  end;
end;

procedure TSugarFeatureTest.DoesntExistIsTheOppositeOfExists;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  AssertTrue('existing tag exists', FDb.Table(TABLE).Where('tag', 'aaa').Exists);
  AssertFalse('existing tag is not absent',
    FDb.Table(TABLE).Where('tag', 'aaa').DoesntExist);
  AssertFalse('missing tag does not exist',
    FDb.Table(TABLE).Where('tag', 'nope').Exists);
  AssertTrue('missing tag is absent',
    FDb.Table(TABLE).Where('tag', 'nope').DoesntExist);
end;

procedure TSugarFeatureTest.UpdateOrInsertInsertsWhenTheKeyIsAbsent;
var
  Inserted: Boolean;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Inserted := FDb.Table(TABLE).UpdateOrInsert(
    Vals(['tag', 'eee']), Vals(['score', 50]));

  AssertTrue('reported an insert', Inserted);
  AssertEquals('the new row carries the value',
    Int64(50), FDb.Table(TABLE).Where('tag', 'eee').Value('score').AsInt64);
  AssertEquals('row count went from three to four',
    Int64(4), FDb.Table(TABLE).Count);
end;

procedure TSugarFeatureTest.UpdateOrInsertUpdatesWhenTheKeyExists;
var
  Inserted: Boolean;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Inserted := FDb.Table(TABLE).UpdateOrInsert(
    Vals(['tag', 'bbb']), Vals(['score', 99]));

  AssertFalse('reported an update, not an insert', Inserted);
  AssertEquals('the existing row was updated',
    Int64(99), FDb.Table(TABLE).Where('tag', 'bbb').Value('score').AsInt64);
end;

procedure TSugarFeatureTest.UpdateOrInsertDoesNotDuplicateTheRow;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  FDb.Table(TABLE).UpdateOrInsert(Vals(['tag', 'bbb']), Vals(['score', 77]));

  AssertEquals('still three rows, not four', Int64(3), FDb.Table(TABLE).Count);
end;

procedure TSugarFeatureTest.UpdateOrInsertStillReportsAnUpdateWhenTheValueDoesNotChange;
var
  Inserted: Boolean;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { O MySQL devolve zero linhas afetadas quando o UPDATE grava o mesmo valor
    que ja estava la. UpdateOrInsert tem de decidir pelo Exists antes do
    update, nao pelas linhas afetadas -- senao isso aqui viraria um insert
    duplicado. }
  Inserted := FDb.Table(TABLE).UpdateOrInsert(
    Vals(['tag', 'bbb']), Vals(['score', 20]));

  AssertFalse('reported an update even though the value on disk did not change',
    Inserted);
  AssertEquals('still three rows', Int64(3), FDb.Table(TABLE).Count);
end;

procedure TSugarFeatureTest.UpsertInsertsAndUpdatesInOneCall;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  if ItClient = 'firebird' then
  begin
    Ignore('Firebird so aceita upsert de uma linha; coberto em outro teste');
    Exit;
  end;

  FDb.Table(TABLE).Upsert(
    [Vals(['tag', 'bbb', 'score', 88]), Vals(['tag', 'fff', 'score', 5])],
    ['tag'], ['score']);

  AssertEquals('updated the colliding row',
    Int64(88), FDb.Table(TABLE).Where('tag', 'bbb').Value('score').AsInt64);
  AssertEquals('inserted the missing row',
    Int64(5), FDb.Table(TABLE).Where('tag', 'fff').Value('score').AsInt64);
  AssertEquals('row count went from three to four',
    Int64(4), FDb.Table(TABLE).Count);
end;

procedure TSugarFeatureTest.UpsertOnFirebirdRejectsMoreThanOneRow;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  if ItClient <> 'firebird' then
  begin
    Ignore('this test only applies to Firebird');
    Exit;
  end;

  // Uma linha so: o Firebird aceita via UPDATE OR INSERT.
  FDb.Table(TABLE).Upsert([Vals(['tag', 'bbb', 'score', 88])], ['tag'], []);
  AssertEquals('the single row was upserted',
    Int64(88), FDb.Table(TABLE).Where('tag', 'bbb').Value('score').AsInt64);

  // Duas linhas: recusa, porque o Firebird nao tem upsert de varias linhas.
  try
    FDb.Table(TABLE).Upsert(
      [Vals(['tag', 'ggg', 'score', 1]), Vals(['tag', 'hhh', 'score', 2])],
      ['tag'], []);
    Fail('expected ELzNexCompile for a multi-row upsert on Firebird');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TSugarFeatureTest.WithCountCountsRealChildren;
var
  Res: ILzNexResult;
  Tag: string;
  ChildCount: Int64;
  Seen: Integer;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  FDb.Table(CHILD_TABLE).Insert(Vals(['parent_tag', 'aaa', 'note', 1]));
  FDb.Table(CHILD_TABLE).Insert(Vals(['parent_tag', 'aaa', 'note', 2]));
  FDb.Table(CHILD_TABLE).Insert(Vals(['parent_tag', 'bbb', 'note', 3]));

  Res := FDb.Table(TABLE).Select(['tag'])
    .WithCount(
      FDb.Table(CHILD_TABLE).WhereColumn('parent_tag', '=', TABLE + '.tag'),
      'child_count')
    .OrderBy('tag')
    .Get;
  try
    Seen := 0;
    while Res.Next do
    begin
      Tag := Res.FieldAt(0).AsString;
      ChildCount := Res.FieldAt(1).AsInt64;
      if Tag = 'aaa' then
        AssertEquals('aaa has two children', Int64(2), ChildCount)
      else if Tag = 'bbb' then
        AssertEquals('bbb has one child', Int64(1), ChildCount)
      else if Tag = 'ccc' then
        AssertEquals('ccc has no children', Int64(0), ChildCount)
      else
        Fail('unexpected tag: ' + Tag);
      Inc(Seen);
    end;
    AssertEquals('all three rows came back', 3, Seen);
  finally
    Res.Close;
  end;
end;

initialization
  RegisterTest('integration', TSugarFeatureTest);

end.
