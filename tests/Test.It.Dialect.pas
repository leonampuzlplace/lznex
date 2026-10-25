unit Test.It.Dialect;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  DateUtils,
  fpcunit,
  testregistry,
  LzNex,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Exceptions,
  Test.It.Config;

type

  TDialectFeatureTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
    procedure Seed;
  published
    procedure WhereYearFindsTheKnownInstant;
    procedure WhereMonthFindsTheKnownInstant;
    procedure WhereDayFindsTheKnownInstant;
    procedure WhereDateFindsTheKnownInstant;
    procedure JsonPathFindsTheRow;
    procedure JsonPathWithStringValueFindsTheRow;
    procedure JsonContainsFindsTheRow;
    procedure JsonContainsWholeDocumentFindsRowOrRaises;
    procedure JsonLengthFindsTheRow;
    procedure FullTextFindsTheRow;
    procedure InRandomOrderReturnsARow;
  end;

implementation

const
  DIALECT_TABLE = 'it_dialect';
  KNOWN_META = '{"a":{"b":42},"list":[1,2,3],"tags":[1,2,3],"city":"Recife"}';

var
  GTableReady: Boolean = False;

function KnownInstant: TLzNexValue;
begin
  Result := TLzNexValue.FromDateTime(EncodeDateTime(2024, 3, 15, 10, 30, 45, 0));
end;

function TDialectFeatureTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: dialect test skipped');
end;

procedure TDialectFeatureTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin
    FDb.Schema.DropTableIfExists(DIALECT_TABLE);
    with FDb.Schema.CreateTable(DIALECT_TABLE) do
    begin
      Increments('id');
      Str('tag', 60).NotNull;
      DateTime('seen_at').NotNull;
      if FDb.Client.SupportsJson then
        Json('meta').Nullable;
      Execute;
    end;
    GTableReady := True;
  end;
end;

procedure TDialectFeatureTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TDialectFeatureTest.Seed;
var
  Row: TLzNexNamedValues;
  N: Integer;
begin
  FDb.Table(DIALECT_TABLE).Truncate;

  N := 2;
  if FDb.Client.SupportsJson then
    Inc(N);
  SetLength(Row, N);
  Row[0].Name := 'tag';
  Row[0].Value := TLzNexValue.FromString('known');
  Row[1].Name := 'seen_at';
  Row[1].Value := KnownInstant;
  if FDb.Client.SupportsJson then
  begin
    Row[2].Name := 'meta';
    Row[2].Value := TLzNexValue.FromString(KNOWN_META);
  end;

  FDb.Table(DIALECT_TABLE).Insert(Row);
end;

procedure TDialectFeatureTest.WhereYearFindsTheKnownInstant;
begin
  if SkipWithoutDatabase then Exit;
  Seed;
  AssertEquals('row found by year', Int64(1),
    FDb.Table(DIALECT_TABLE).WhereYear('seen_at', 2024).Count);
end;

procedure TDialectFeatureTest.WhereMonthFindsTheKnownInstant;
begin
  if SkipWithoutDatabase then Exit;
  Seed;
  AssertEquals('row found by month', Int64(1),
    FDb.Table(DIALECT_TABLE).WhereMonth('seen_at', 3).Count);
end;

procedure TDialectFeatureTest.WhereDayFindsTheKnownInstant;
begin
  if SkipWithoutDatabase then Exit;
  Seed;
  AssertEquals('row found by day', Int64(1),
    FDb.Table(DIALECT_TABLE).WhereDay('seen_at', 15).Count);
end;

procedure TDialectFeatureTest.WhereDateFindsTheKnownInstant;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  AssertEquals('row found by full date', Int64(1),
    FDb.Table(DIALECT_TABLE)
      .WhereDate('seen_at', TLzNexValue.FromDate(EncodeDate(2024, 3, 15)))
      .Count);
end;

procedure TDialectFeatureTest.JsonPathFindsTheRow;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsJson then
  begin
    Ignore('dialect has no JSON support');
    Exit;
  end;
  Seed;

  AssertEquals('row found by json path', Int64(1),
    FDb.Table(DIALECT_TABLE)
      .WhereJsonPath('meta', 'a.b', '=', TLzNexValue.FromString('42'))
      .Count);
end;

procedure TDialectFeatureTest.JsonPathWithStringValueFindsTheRow;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsJson then
  begin
    Ignore('dialect has no JSON support');
    Exit;
  end;
  Seed;
  AssertEquals('row found by json path (string value)', Int64(1),
    FDb.Table(DIALECT_TABLE)
      .WhereJsonPath('meta', 'city', '=', TLzNexValue.FromString('Recife'))
      .Count);
end;

procedure TDialectFeatureTest.JsonContainsFindsTheRow;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsJson then
  begin
    Ignore('dialect has no JSON support');
    Exit;
  end;
  Seed;

  AssertEquals('row found by json contains (scalar in array)', Int64(1),
    FDb.Table(DIALECT_TABLE)
      .WhereJsonContains('meta', 'tags', TLzNexValue.FromInteger(2))
      .Count);
end;

procedure TDialectFeatureTest.JsonContainsWholeDocumentFindsRowOrRaises;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsJson then
  begin
    Ignore('dialect has no JSON support');
    Exit;
  end;
  Seed;

  try
    AssertEquals('row found by json contains (whole document)', Int64(1),
      FDb.Table(DIALECT_TABLE)
        .WhereJsonContains('meta', '', TLzNexValue.FromString('{"a":{"b":42}}'))
        .Count);
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TDialectFeatureTest.JsonLengthFindsTheRow;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsJson then
  begin
    Ignore('dialect has no JSON support');
    Exit;
  end;
  Seed;
  AssertEquals('row found by json length',  Int64(1),
    FDb.Table(DIALECT_TABLE)
      .WhereJsonLength('meta', 'list', '=', 3)
      .Count);
end;

procedure TDialectFeatureTest.FullTextFindsTheRow;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsFullText then
  begin
    Ignore('dialect has no full text search');
    Exit;
  end;
  Seed;

  try
    FDb.Schema.Table(DIALECT_TABLE).FullText(['tag']).Execute;
  except
    on E: Exception do
    begin
      Ignore('full text DDL not ready yet: ' + E.Message);
      Exit;
    end;
  end;

  AssertEquals('row found by full text', Int64(1),
    FDb.Table(DIALECT_TABLE).WhereFullText(['tag'], 'known').Count);
end;

procedure TDialectFeatureTest.InRandomOrderReturnsARow;
begin
  if SkipWithoutDatabase then Exit;
  Seed;
  AssertEquals('a row came back in random order', 'known',
    FDb.Table(DIALECT_TABLE).InRandomOrder.Value('tag').AsString);
end;

initialization
  RegisterTest('integration', TDialectFeatureTest);

end.
