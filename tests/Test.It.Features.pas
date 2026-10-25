unit Test.It.Features;

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

  { O que cada dialeto escreve de forma diferente, provado contra o banco de
    verdade: paginacao, ordem de nulos, like sem caixa, upsert e truncate.
    A mesma suite roda nos cinco bancos; quem decide o caminho e a capacidade
    declarada pelo dialeto, nao um if por nome de banco. }
  TPortableFeatureTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
    procedure Seed;
  published
    procedure PagingTakesAWindowInTheMiddle;
    procedure PagingWithOffsetAloneSkipsTheHead;
    procedure NullsLastPutsTheNullAtTheEnd;
    procedure NullsFirstPutsTheNullAtTheHead;
    procedure CaseInsensitiveLikeFindsTheRow;
    procedure UpsertInsertsWhenTheKeyIsAbsent;
    procedure UpsertUpdatesWhenTheKeyExists;
    procedure TruncateEmptiesTheTable;
  end;

implementation

const
  FEATURE_TABLE = 'it_features';

var
  GTableReady: Boolean = False;

function TPortableFeatureTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: feature test skipped');
end;

procedure TPortableFeatureTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin
    { "tag" e unica porque o upsert precisa de uma chave de conflito: sem ela o
      ON CONFLICT do PostgreSQL e do SQLite nao tem o que casar. }
    FDb.Schema.DropTableIfExists(FEATURE_TABLE);
    FDb.Schema.CreateTable(FEATURE_TABLE)
      .Increments('id')
      .Str('tag', 60).NotNull.Unique
      .Int('score').Nullable
      .Execute;
    GTableReady := True;
  end;
end;

procedure TPortableFeatureTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TPortableFeatureTest.Seed;
begin
  FDb.Table(FEATURE_TABLE).Truncate;
  FDb.Table(FEATURE_TABLE).Insert(Vals(['tag', 'aaa', 'score', 10]));
  FDb.Table(FEATURE_TABLE).Insert(Vals(['tag', 'bbb', 'score', 20]));
  FDb.Table(FEATURE_TABLE).Insert(Vals(['tag', 'ccc', 'score', 30]));
  FDb.Table(FEATURE_TABLE).Insert(Vals(['tag', 'ddd']));
end;

procedure TPortableFeatureTest.PagingTakesAWindowInTheMiddle;
var
  Tags: TLzNexValues;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { No Firebird isso sai como OFFSET ... ROWS FETCH NEXT ... ROWS ONLY; nos
    outros, como LIMIT/OFFSET. O resultado tem de ser o mesmo. }
  Tags := FDb.Table(FEATURE_TABLE).OrderBy('tag').Limit(2).Offset(1).Pluck('tag');

  AssertEquals('window size', 2, Length(Tags));
  AssertEquals('first of the window', 'bbb', Tags[0].AsString);
  AssertEquals('second of the window', 'ccc', Tags[1].AsString);
end;

procedure TPortableFeatureTest.PagingWithOffsetAloneSkipsTheHead;
var
  Tags: TLzNexValues;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { Offset sem limit: o MySQL e o SQLite precisam de um limite artificial para
    aceitar a clausula, e isso nao pode mudar o resultado. }
  Tags := FDb.Table(FEATURE_TABLE).OrderBy('tag').Offset(2).Pluck('tag');

  AssertEquals('rows after the offset', 2, Length(Tags));
  AssertEquals('first after the offset', 'ccc', Tags[0].AsString);
  AssertEquals('last after the offset', 'ddd', Tags[1].AsString);
end;

procedure TPortableFeatureTest.NullsLastPutsTheNullAtTheEnd;
var
  Rows: TLzNexValues;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { PostgreSQL, Firebird e SQLite tem NULLS LAST; o MySQL emula com uma coluna
    extra de ordenacao. }
  Rows := FDb.Table(FEATURE_TABLE)
    .OrderBy('score', odAsc, nlLast)
    .Pluck('tag');

  AssertEquals('row count', 4, Length(Rows));
  AssertEquals('smallest score first', 'aaa', Rows[0].AsString);
  AssertEquals('null at the end', 'ddd', Rows[3].AsString);
end;

procedure TPortableFeatureTest.NullsFirstPutsTheNullAtTheHead;
var
  Rows: TLzNexValues;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Rows := FDb.Table(FEATURE_TABLE)
    .OrderBy('score', odAsc, nlFirst)
    .Pluck('tag');

  AssertEquals('row count', 4, Length(Rows));
  AssertEquals('null at the head', 'ddd', Rows[0].AsString);
  AssertEquals('smallest score next', 'aaa', Rows[1].AsString);
end;

procedure TPortableFeatureTest.CaseInsensitiveLikeFindsTheRow;
var
  Found: Int64;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { O PostgreSQL tem ILIKE, o Firebird vira upper() nos dois lados, o MySQL e o
    SQLite ja ignoram caixa no LIKE. }
  Found := FDb.Table(FEATURE_TABLE).WhereILike('tag', 'BB%').Count;
  AssertEquals('found the lowercase row with an uppercase pattern', Int64(1), Found);
end;

procedure TPortableFeatureTest.UpsertInsertsWhenTheKeyIsAbsent;
var
  Score: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { Firebird: UPDATE OR INSERT ... MATCHING. MySQL: ON DUPLICATE KEY UPDATE.
    PostgreSQL e SQLite: ON CONFLICT ... DO UPDATE. }
  FDb.Table(FEATURE_TABLE).OnConflict(['tag']).Merge
    .Insert(Vals(['tag', 'eee', 'score', 50]));

  Score := FDb.Table(FEATURE_TABLE).Where('tag', 'eee').Value('score');
  AssertEquals('the absent key was inserted', Int64(50), Score.AsInt64);
  AssertEquals('and nothing else was touched', Int64(5),
    FDb.Table(FEATURE_TABLE).Count);
end;

procedure TPortableFeatureTest.UpsertUpdatesWhenTheKeyExists;
var
  Score: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  FDb.Table(FEATURE_TABLE).OnConflict(['tag']).Merge
    .Insert(Vals(['tag', 'bbb', 'score', 99]));

  Score := FDb.Table(FEATURE_TABLE).Where('tag', 'bbb').Value('score');
  AssertEquals('the existing row was updated', Int64(99), Score.AsInt64);
  AssertEquals('no row was duplicated', Int64(4),
    FDb.Table(FEATURE_TABLE).Count);
end;

procedure TPortableFeatureTest.TruncateEmptiesTheTable;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { Firebird e SQLite nao tem TRUNCATE: viram DELETE sem WHERE. }
  FDb.Table(FEATURE_TABLE).Truncate;
  AssertEquals('table is empty', Int64(0), FDb.Table(FEATURE_TABLE).Count);
end;

initialization
  RegisterTest('integration', TPortableFeatureTest);

end.
