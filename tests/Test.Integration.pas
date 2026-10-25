unit Test.Integration;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpcunit,
  testregistry,
  LzNex,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Client.MySQL,
  Test.It.Config;

type
  TIntegrationTestCase = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
  end;

  TInsertGetIdTest = class(TIntegrationTestCase)
  published
    procedure ReturnsGeneratedId;
    procedure IdsAreIncreasing;
    procedure ReturnsOwnIdUnderConcurrency;
    procedure InsideCommittedTransaction;
    procedure InsideRolledBackTransaction;
    procedure WithoutColumnsRaises;
  end;

  TCrudTest = class(TIntegrationTestCase)
  published
    procedure InsertUpdateDelete;
    procedure SelectWithBoundWhere;
    procedure Utf8RoundTrip;
  end;

implementation

const
  TEST_TABLE = 'it_users';

var
  GTableReady: Boolean = False;

function EnvOr(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

function TIntegrationTestCase.SkipWithoutDatabase: Boolean;
begin
  Result := GetEnvironmentVariable('LZNEX_IT') = '';
  if Result then
    Ignore('LZNEX_IT not set: integration test skipped');
end;

procedure TIntegrationTestCase.SetUp;
begin
  inherited SetUp;
  if GetEnvironmentVariable('LZNEX_IT') = '' then
    Exit;

  FDb := Connect(ItConfig(8));

  if not GTableReady then
  begin

    FDb.Schema.DropTableIfExists(TEST_TABLE);
    FDb.Schema.CreateTable(TEST_TABLE)
      .Increments('id')
      .Str('tag', 80).NotNull
      .Int('score').Nullable
      .Execute;
    GTableReady := True;
  end;
end;

procedure TIntegrationTestCase.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TInsertGetIdTest.ReturnsGeneratedId;
var
  NewId: Int64;
  StoredTag: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;

  NewId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'first']));
  AssertTrue('generated id must be positive', NewId > 0);

  StoredTag := FDb.Table(TEST_TABLE).Where('id', NewId).Value('tag');
  AssertEquals('id points to the row just inserted', 'first', StoredTag.AsString);
end;

procedure TInsertGetIdTest.IdsAreIncreasing;
var
  FirstId, SecondId: Int64;
begin
  if SkipWithoutDatabase then Exit;

  FirstId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'seq-a']));
  SecondId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'seq-b']));
  AssertTrue('second id is greater', SecondId > FirstId);
end;

type

  TInsertWorker = class(TThread)
  private
    FDb: ILzNex;
    FTag: string;
    FInsertedId: Int64;
    FErrorMessage: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADb: ILzNex; const ATag: string);
    property InsertedId: Int64 read FInsertedId;
    property Tag: string read FTag;
    property ErrorMessage: string read FErrorMessage;
  end;

constructor TInsertWorker.Create(const ADb: ILzNex; const ATag: string);
begin
  FDb := ADb;
  FTag := ATag;
  FInsertedId := -1;
  FErrorMessage := '';
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TInsertWorker.Execute;
begin
  try
    FInsertedId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', FTag]));
  except
    on E: Exception do
      FErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TInsertGetIdTest.ReturnsOwnIdUnderConcurrency;
const
  WORKER_COUNT = 8;
var
  Workers: array[0..WORKER_COUNT - 1] of TInsertWorker;
  I: Integer;
  StoredTag: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;

  for I := 0 to WORKER_COUNT - 1 do
    Workers[I] := TInsertWorker.Create(FDb, 'conc-' + IntToStr(I));
  try
    for I := 0 to WORKER_COUNT - 1 do
      Workers[I].WaitFor;

    for I := 0 to WORKER_COUNT - 1 do
    begin
      AssertEquals('worker ' + IntToStr(I) + ' failed', '', Workers[I].ErrorMessage);
      AssertTrue('worker ' + IntToStr(I) + ' got a valid id', Workers[I].InsertedId > 0);

      StoredTag := FDb.Table(TEST_TABLE).Where('id', Workers[I].InsertedId).Value('tag');
      AssertEquals('id returned to worker ' + IntToStr(I) + ' points to its own row',
        Workers[I].Tag, StoredTag.AsString);
    end;
  finally
    for I := 0 to WORKER_COUNT - 1 do
      Workers[I].Free;
  end;
end;

procedure TInsertGetIdTest.InsideCommittedTransaction;
var
  Trx: ILzNexTransaction;
  NewId: Int64;
  StoredTag: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  NewId := Trx.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'trx-commit']));
  AssertTrue('id inside transaction', NewId > 0);
  Trx.Commit;
  Trx := nil;

  StoredTag := FDb.Table(TEST_TABLE).Where('id', NewId).Value('tag');
  AssertEquals('persisted after commit', 'trx-commit', StoredTag.AsString);
end;

procedure TInsertGetIdTest.InsideRolledBackTransaction;
var
  Trx: ILzNexTransaction;
  NewId: Int64;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  NewId := Trx.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'trx-rollback']));
  AssertTrue('id generated even though it will be undone', NewId > 0);
  Trx.Rollback;
  Trx := nil;

  AssertFalse('row must not survive the rollback',
    FDb.Table(TEST_TABLE).Where('id', NewId).Exists);
end;

procedure TInsertGetIdTest.WithoutColumnsRaises;
var
  NoColumns: TLzNexNamedValues;
begin
  if SkipWithoutDatabase then Exit;

  NoColumns := nil;
  try
    FDb.Table(TEST_TABLE).InsertGetId(NoColumns);
    Fail('expected ELzNexBuilder when inserting without columns');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TCrudTest.InsertUpdateDelete;
var
  NewId, Affected: Int64;
  Score: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;

  NewId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'crud', 'score', 10]));

  Affected := FDb.Table(TEST_TABLE).Where('id', NewId).Update(Vals(['score', 20]));
  AssertEquals('one row updated', 1, Affected);

  Score := FDb.Table(TEST_TABLE).Where('id', NewId).Value('score');
  AssertEquals('updated value', 20, Score.AsInt64);

  Affected := FDb.Table(TEST_TABLE).Where('id', NewId).Delete;
  AssertEquals('one row deleted', 1, Affected);
  AssertFalse('row is gone', FDb.Table(TEST_TABLE).Where('id', NewId).Exists);
end;

procedure TCrudTest.SelectWithBoundWhere;
var
  NewId: Int64;
  Cursor: ILzNexResult;
  Found: Boolean;
begin
  if SkipWithoutDatabase then Exit;

  NewId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', 'lookup', 'score', 77]));
  Cursor := FDb.Table(TEST_TABLE).Select(['id', 'tag']).Where('score', 77).Get;
  Found := False;
  while Cursor.Next do
    if Cursor.Field('id').AsInt64 = NewId then
      Found := True;
  AssertTrue('row found through the bound parameter', Found);
end;

procedure TCrudTest.Utf8RoundTrip;
var
  NewId: Int64;
  Original: string;
  Stored: TLzNexValue;
begin
  if SkipWithoutDatabase then Exit;

  Original := 'acentua' + #$C3#$A7 + #$C3#$A3 + 'o ' + #$E2#$9C#$85;
  NewId := FDb.Table(TEST_TABLE).InsertGetId(Vals(['tag', Original]));
  Stored := FDb.Table(TEST_TABLE).Where('id', NewId).Value('tag');
  AssertEquals('utf8 preserved round trip', Original, Stored.AsString);
end;

initialization
  RegisterTest('integration', TInsertGetIdTest);
  RegisterTest('integration', TCrudTest);

end.
