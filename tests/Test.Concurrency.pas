unit Test.Concurrency;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  SyncObjs,
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
  TConcurrencyTestCase = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
    procedure RecreateTable(const ADb: ILzNex);
  end;

  TParallelLoadTest = class(TConcurrencyTestCase)
  published
    procedure MixedOperationsDoNotInterleave;
    procedure PoolReleasesEveryConnection;
    procedure ParallelTransactionsAreIsolated;
  end;

  TPoolLimitTest = class(TConcurrencyTestCase)
  published
    procedure MoreThreadsThanConnectionsStillWorks;
    procedure OpenCursorHoldsItsLease;
  end;

implementation

const
  LOAD_TABLE = 'ct_load';

function EnvOr(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

function ConnectWithPoolSize(const AMaxConnections: Integer): ILzNex;
begin
  Result := Connect(ItConfig(AMaxConnections));
end;

function TConcurrencyTestCase.SkipWithoutDatabase: Boolean;
begin
  Result := GetEnvironmentVariable('LZNEX_IT') = '';
  if Result then
    Ignore('LZNEX_IT not set: concurrency test skipped');
end;

procedure TConcurrencyTestCase.SetUp;
begin
  inherited SetUp;
  if GetEnvironmentVariable('LZNEX_IT') = '' then
    Exit;
  FDb := ConnectWithPoolSize(8);
end;

procedure TConcurrencyTestCase.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TConcurrencyTestCase.RecreateTable(const ADb: ILzNex);
begin
  { Schema builder em vez de DDL cru: a mesma chamada serve aos dois dialetos. }
  ADb.Schema.DropTableIfExists(LOAD_TABLE);
  ADb.Schema.CreateTable(LOAD_TABLE)
    .Increments('id')
    .Int('worker').NotNull
    .Str('tag', 60).NotNull
    .Int('score').Nullable
    .Index(['worker'])
    .Execute;
end;

type

  TLoadWorker = class(TThread)
  private
    FDb: ILzNex;
    FIndex: Integer;
    FRounds: Integer;
    FErrorMessage: string;
    FMatchingIds: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADb: ILzNex; const AIndex, ARounds: Integer);
    property ErrorMessage: string read FErrorMessage;
    property MatchingIds: Integer read FMatchingIds;
  end;

constructor TLoadWorker.Create(const ADb: ILzNex; const AIndex, ARounds: Integer);
begin
  FDb := ADb;
  FIndex := AIndex;
  FRounds := ARounds;
  FErrorMessage := '';
  FMatchingIds := 0;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TLoadWorker.Execute;
var
  Round_: Integer;
  NewId: Int64;
  Tag: string;
  StoredTag: TLzNexValue;
  Trx: ILzNexTransaction;
begin
  try
    for Round_ := 1 to FRounds do
    begin
      Tag := Format('w%d-r%d', [FIndex, Round_]);

      NewId := FDb.Table(LOAD_TABLE).InsertGetId(Vals(['worker', FIndex, 'tag', Tag]));
      StoredTag := FDb.Table(LOAD_TABLE).Where('id', NewId).Value('tag');
      if StoredTag.AsString = Tag then
        Inc(FMatchingIds);

      FDb.Table(LOAD_TABLE).Where('id', NewId)
        .Update(Vals(['score', FIndex * 100 + Round_]));
      FDb.Table(LOAD_TABLE).Where('worker', FIndex).Count;

      Trx := FDb.Transaction;
      try
        Trx.Table(LOAD_TABLE).Insert(
          Vals(['worker', FIndex, 'tag', 'trx-' + IntToStr(Round_)]));
        if (Round_ mod 3) = 0 then
          Trx.Commit
        else
          Trx.Rollback;
      finally
        Trx := nil;
      end;
    end;
  except
    on E: Exception do
      FErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TParallelLoadTest.MixedOperationsDoNotInterleave;
const
  WORKER_COUNT = 8;
  ROUNDS = 15;
var
  Workers: array[0..WORKER_COUNT - 1] of TLoadWorker;
  I: Integer;
  CommittedPerWorker, TotalRows, WorkerRows: Int64;
begin
  if SkipWithoutDatabase then Exit;

  RecreateTable(FDb);

  for I := 0 to WORKER_COUNT - 1 do
    Workers[I] := TLoadWorker.Create(FDb, I, ROUNDS);
  try
    for I := 0 to WORKER_COUNT - 1 do
      Workers[I].WaitFor;

    for I := 0 to WORKER_COUNT - 1 do
    begin
      AssertEquals('worker ' + IntToStr(I) + ' failed', '', Workers[I].ErrorMessage);
      AssertEquals('every id of worker ' + IntToStr(I) + ' points to its own row',
        ROUNDS, Workers[I].MatchingIds);
    end;
  finally
    for I := 0 to WORKER_COUNT - 1 do
      Workers[I].Free;
  end;

  CommittedPerWorker := ROUNDS div 3;
  TotalRows := FDb.Table(LOAD_TABLE).Count;
  AssertEquals('exact row count',
    Int64(WORKER_COUNT) * (ROUNDS + CommittedPerWorker), TotalRows);

  for I := 0 to WORKER_COUNT - 1 do
  begin
    WorkerRows := FDb.Table(LOAD_TABLE).Where('worker', I).Count;
    AssertEquals('rows of worker ' + IntToStr(I),
      Int64(ROUNDS + CommittedPerWorker), WorkerRows);
  end;
end;

procedure TParallelLoadTest.PoolReleasesEveryConnection;
const
  WORKER_COUNT = 6;
var
  Workers: array[0..WORKER_COUNT - 1] of TLoadWorker;
  I: Integer;
begin
  if SkipWithoutDatabase then Exit;

  RecreateTable(FDb);

  for I := 0 to WORKER_COUNT - 1 do
    Workers[I] := TLoadWorker.Create(FDb, I, 8);
  try
    for I := 0 to WORKER_COUNT - 1 do
      Workers[I].WaitFor;
  finally
    for I := 0 to WORKER_COUNT - 1 do
      Workers[I].Free;
  end;

  AssertEquals('no connection still leased after the load', 0, FDb.Pool.InUse);
  AssertTrue('pool stayed within its maximum', FDb.Pool.Size <= 8);
end;

type

  TPendingTransactionWorker = class(TThread)
  private
    FDb: ILzNex;
    FReleaseSignal: TEvent;
    FReadySignal: TEvent;
    FErrorMessage: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADb: ILzNex; const AReleaseSignal, AReadySignal: TEvent);
    property ErrorMessage: string read FErrorMessage;
  end;

constructor TPendingTransactionWorker.Create(const ADb: ILzNex;
  const AReleaseSignal, AReadySignal: TEvent);
begin
  FDb := ADb;
  FReleaseSignal := AReleaseSignal;
  FReadySignal := AReadySignal;
  FErrorMessage := '';
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TPendingTransactionWorker.Execute;
var
  Trx: ILzNexTransaction;
begin
  try
    Trx := FDb.Transaction;
    try
      Trx.Table(LOAD_TABLE).Insert(Vals(['worker', 99, 'tag', 'uncommitted']));
      FReadySignal.SetEvent;
      FReleaseSignal.WaitFor(10000);
      Trx.Rollback;
    finally
      Trx := nil;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := E.ClassName + ': ' + E.Message;
      FReadySignal.SetEvent;
    end;
  end;
end;

procedure TParallelLoadTest.ParallelTransactionsAreIsolated;
var
  Worker: TPendingTransactionWorker;
  ReleaseSignal, ReadySignal: TEvent;
  VisibleFromOutside: Int64;
begin
  if SkipWithoutDatabase then Exit;

  RecreateTable(FDb);

  ReleaseSignal := TEvent.Create(nil, True, False, '');
  ReadySignal := TEvent.Create(nil, True, False, '');
  try
    Worker := TPendingTransactionWorker.Create(FDb, ReleaseSignal, ReadySignal);
    try
      AssertTrue('the other thread opened its transaction',
        ReadySignal.WaitFor(10000) = wrSignaled);
      AssertEquals('transaction worker failed', '', Worker.ErrorMessage);

      VisibleFromOutside :=
        FDb.Table(LOAD_TABLE).Where('tag', 'uncommitted').Count;
      AssertEquals('uncommitted data must not leak to another connection',
        Int64(0), VisibleFromOutside);

      ReleaseSignal.SetEvent;
      Worker.WaitFor;
      AssertEquals('transaction worker failed after rollback', '', Worker.ErrorMessage);
    finally
      Worker.Free;
    end;

    AssertEquals('still invisible after rollback', Int64(0),
      FDb.Table(LOAD_TABLE).Where('tag', 'uncommitted').Count);
  finally
    ReleaseSignal.Free;
    ReadySignal.Free;
  end;
end;

procedure TPoolLimitTest.MoreThreadsThanConnectionsStillWorks;
const
  WORKER_COUNT = 12;
var
  Db: ILzNex;
  Workers: array[0..WORKER_COUNT - 1] of TLoadWorker;
  I: Integer;
begin
  if SkipWithoutDatabase then Exit;

  Db := ConnectWithPoolSize(3);
  try
    RecreateTable(Db);

    for I := 0 to WORKER_COUNT - 1 do
      Workers[I] := TLoadWorker.Create(Db, I, 5);
    try
      for I := 0 to WORKER_COUNT - 1 do
        Workers[I].WaitFor;
      for I := 0 to WORKER_COUNT - 1 do
      begin
        AssertEquals('worker ' + IntToStr(I) + ' failed with a small pool',
          '', Workers[I].ErrorMessage);
        AssertEquals('ids still correct with a small pool', 5, Workers[I].MatchingIds);
      end;
    finally
      for I := 0 to WORKER_COUNT - 1 do
        Workers[I].Free;
    end;

    AssertEquals('no connection stuck', 0, Db.Pool.InUse);
    AssertTrue('pool respected its maximum', Db.Pool.Size <= 3);
  finally
    Db.Shutdown;
  end;
end;

procedure TPoolLimitTest.OpenCursorHoldsItsLease;
var
  Db: ILzNex;
  FirstCursor, SecondCursor: ILzNexResult;
begin
  if SkipWithoutDatabase then Exit;

  Db := ConnectWithPoolSize(4);
  try
    RecreateTable(Db);
    Db.Table(LOAD_TABLE).Insert(Vals(['worker', 1, 'tag', 'a']));

    AssertEquals('pool idle at the start', 0, Db.Pool.InUse);

    FirstCursor := Db.Table(LOAD_TABLE).Get;
    AssertEquals('an open cursor holds one connection', 1, Db.Pool.InUse);

    SecondCursor := Db.Table(LOAD_TABLE).Get;
    AssertEquals('two cursors hold two connections', 2, Db.Pool.InUse);

    FirstCursor := nil;
    AssertEquals('releasing the cursor returns the connection', 1, Db.Pool.InUse);
    SecondCursor := nil;
    AssertEquals('pool back to idle', 0, Db.Pool.InUse);
  finally
    Db.Shutdown;
  end;
end;

initialization
  RegisterTest('concurrency', TParallelLoadTest);
  RegisterTest('concurrency', TPoolLimitTest);

end.
