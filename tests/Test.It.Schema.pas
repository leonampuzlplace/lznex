unit Test.It.Schema;

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

  TSchemaInspectionTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
  published
    procedure TablesContainsTheCreatedTable;
    procedure ColumnsListsNamesInDeclarationOrder;
    procedure HasIndexFindsTheCompositeUniqueIndex;
    procedure HasIndexDoesNotFindAColumnSetWithoutAnIndex;
    procedure FullTextIndexCreationSucceedsWhenSupported;
  end;

implementation

const
  INSPECT_TABLE = 'it_inspect';
  FULLTEXT_TABLE = 'it_inspect_ft';

var
  GTableReady: Boolean = False;

function Contains(const AList: TLzNexStringArray; const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(AList) do
    if AList[I] = AName then
      Exit(True);
end;

function TSchemaInspectionTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: schema inspection test skipped');
end;

procedure TSchemaInspectionTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin

    FDb.Schema.DropTableIfExists(INSPECT_TABLE);
    FDb.Schema.CreateTable(INSPECT_TABLE)
      .Increments('id')
      .Str('email', 120).NotNull
      .Str('name', 80).NotNull
      .Unique(['email', 'name'])
      .Execute;
    GTableReady := True;
  end;
end;

procedure TSchemaInspectionTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TSchemaInspectionTest.TablesContainsTheCreatedTable;
begin
  if SkipWithoutDatabase then Exit;
  AssertTrue('table should be listed',
    Contains(FDb.Schema.Tables, INSPECT_TABLE));
end;

procedure TSchemaInspectionTest.ColumnsListsNamesInDeclarationOrder;
var
  Cols: TLzNexStringArray;
begin
  if SkipWithoutDatabase then Exit;
  Cols := FDb.Schema.Columns(INSPECT_TABLE);
  AssertEquals('column count', 3, Length(Cols));
  AssertEquals('first column', 'id', Cols[0]);
  AssertEquals('second column', 'email', Cols[1]);
  AssertEquals('third column', 'name', Cols[2]);
end;

procedure TSchemaInspectionTest.HasIndexFindsTheCompositeUniqueIndex;
begin
  if SkipWithoutDatabase then Exit;
  AssertTrue('the composite unique index should be found',
    FDb.Schema.HasIndex(INSPECT_TABLE, ['email', 'name']));
end;

procedure TSchemaInspectionTest.HasIndexDoesNotFindAColumnSetWithoutAnIndex;
begin
  if SkipWithoutDatabase then Exit;
  AssertFalse('a single column out of the composite index should not match',
    FDb.Schema.HasIndex(INSPECT_TABLE, ['name']));
end;

procedure TSchemaInspectionTest.FullTextIndexCreationSucceedsWhenSupported;
begin
  if SkipWithoutDatabase then Exit;
  if not FDb.Client.SupportsFullText then
  begin
    Ignore('dialect "' + FDb.Client.DialectName + '" has no full text index');
    Exit;
  end;

  FDb.Schema.DropTableIfExists(FULLTEXT_TABLE);
  FDb.Schema.CreateTable(FULLTEXT_TABLE)
    .Increments('id')
    .Text('body').NotNull
    .FullText(['body'])
    .Execute;

  FDb.Table(FULLTEXT_TABLE).Insert(Vals(['body', 'full text search works']));
  AssertEquals('the row survived the DDL and the insert', Int64(1),
    FDb.Table(FULLTEXT_TABLE).Count);
end;

initialization
  RegisterTest('integration', TSchemaInspectionTest);

end.
