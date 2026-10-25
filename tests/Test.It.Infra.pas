unit Test.It.Infra;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  LzNex,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Intf,
  LzNex.Exceptions,
  Test.It.Config;

type

  { Prova contra banco de verdade das tres pecas de infra mais novas: o log de
    query (LogQuery/LogError via Config.Logger), o retry de transacao
    (ILzNex.Transact) e o roteamento leitura/escrita (Config.ReadReplica). }
  TInfraTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
  published
    procedure LoggerRecordsInsertAndSelectWithPlaceholders;
    procedure LoggerRecordsTheFailureAndStillRaises;
    procedure WithoutALoggerNothingBreaks;

    procedure TransactCommitsAndCostsOneAttempt;
    procedure TransactDoesNotRetryAPermanentErrorAndRollsBack;
    procedure TransactRetriesATransientErrorUpToTheLimit;
    procedure TransactClampsAttemptsBelowOneToOne;
    procedure TransactInsideATransactionRaises;
    procedure TransactWithoutAWorkRaises;

    procedure WithoutAReplicaReadConnectionIsThePrimary;
    procedure PlainSelectUsesTheReadPoolWhenThereIsAReplica;
    procedure ForUpdateUsesThePrimaryEvenForASelect;
    procedure UsePrimaryForcesTheWriteConnection;
    procedure InsideATransactionReadUsesTheTransactionConnection;
    procedure WritesAlwaysUseThePrimaryConnection;
    procedure ReadReplicaPointingAtItselfRaises;
  end;

implementation

const
  INFRA_TABLE = 'it_infra';

var
  GTableReady: Boolean = False;

type

  { Logger espiao: TInterfacedObject por tras de ILzNexLogger, igual ao campo
    que a config guarda. So conta e guarda a ultima chamada de cada tipo. }
  TLzNexSpyLogger = class(TInterfacedObject, ILzNexLogger)
  private
    FQueryCount: Integer;
    FErrorCount: Integer;
    FWarningCount: Integer;
    FInfoCount: Integer;
    FLastSQL: string;
    FLastBindingCount: Integer;
    FLastElapsedMs: Int64;
    FLastErrorSQL: string;
    FLastError: string;
  public
    procedure LogQuery(const ASQL: string; const ABindings: TLzNexBindings;
      const AElapsedMs: Int64);
    procedure LogError(const ASQL: string; const AError: string);
    procedure LogWarning(const AMessage: string);
    procedure LogInfo(const AMessage: string);
    procedure Reset;
    property QueryCount: Integer read FQueryCount;
    property ErrorCount: Integer read FErrorCount;
    property LastSQL: string read FLastSQL;
    property LastBindingCount: Integer read FLastBindingCount;
    property LastElapsedMs: Int64 read FLastElapsedMs;
    property LastErrorSQL: string read FLastErrorSQL;
    property LastError: string read FLastError;
  end;

  { Bloco de trabalho do Transact: cada chamada insere uma linha marcada com o
    numero da tentativa e, enquanto nao passar de FFailCount, falha -- de
    forma transitoria ou definitiva, conforme FRetryable. Isso prova retry,
    contagem de tentativas e rollback das tentativas perdidas ao mesmo tempo. }
  TLzNexSpyWork = class(TInterfacedObject, ILzNexWork)
  private
    FTable: string;
    FFailCount: Integer;
    FRetryable: Boolean;
    FExecCount: Integer;
  public
    constructor Create(const ATable: string; const AFailCount: Integer;
      const ARetryable: Boolean);
    procedure Execute(const ADb: ILzNex);
    property ExecCount: Integer read FExecCount;
  end;

procedure TLzNexSpyLogger.LogQuery(const ASQL: string;
  const ABindings: TLzNexBindings; const AElapsedMs: Int64);
begin
  Inc(FQueryCount);
  FLastSQL := ASQL;
  FLastBindingCount := ABindings.Count;
  FLastElapsedMs := AElapsedMs;
end;

procedure TLzNexSpyLogger.LogError(const ASQL: string; const AError: string);
begin
  Inc(FErrorCount);
  FLastErrorSQL := ASQL;
  FLastError := AError;
end;

procedure TLzNexSpyLogger.LogWarning(const AMessage: string);
begin
  Inc(FWarningCount);
end;

procedure TLzNexSpyLogger.LogInfo(const AMessage: string);
begin
  Inc(FInfoCount);
end;

procedure TLzNexSpyLogger.Reset;
begin
  FQueryCount := 0;
  FErrorCount := 0;
  FWarningCount := 0;
  FInfoCount := 0;
  FLastSQL := '';
  FLastBindingCount := 0;
  FLastElapsedMs := -1;
  FLastErrorSQL := '';
  FLastError := '';
end;

constructor TLzNexSpyWork.Create(const ATable: string;
  const AFailCount: Integer; const ARetryable: Boolean);
begin
  inherited Create;
  FTable := ATable;
  FFailCount := AFailCount;
  FRetryable := ARetryable;
  FExecCount := 0;
end;

procedure TLzNexSpyWork.Execute(const ADb: ILzNex);
begin
  Inc(FExecCount);
  ADb.Table(FTable).Insert(Vals(['tag', 'attempt-' + IntToStr(FExecCount)]));
  if FExecCount <= FFailCount then
  begin
    if FRetryable then
      // SQLSTATE 40001 (falha de serializacao) e transitorio na classe base
      // de todo dialeto -- nao precisa de um deadlock de verdade para provar.
      raise ELzNexQuery.CreateDb('synthetic transient failure', 'SYNTHETIC', 1213, '40001')
    else
      raise Exception.Create('synthetic permanent failure');
  end;
end;

function TInfraTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: infra test skipped');
end;

procedure TInfraTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin
    FDb.Schema.DropTableIfExists(INFRA_TABLE);
    FDb.Schema.CreateTable(INFRA_TABLE)
      .Increments('id')
      .Str('tag', 60).NotNull.Unique
      .Int('score').Nullable
      .Execute;
    GTableReady := True;
  end;
end;

procedure TInfraTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TInfraTest.LoggerRecordsInsertAndSelectWithPlaceholders;
var
  Spy: TLzNexSpyLogger;
  SpyIntf: ILzNexLogger;
  Db: ILzNex;
  Cursor: ILzNexResult;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  Spy := TLzNexSpyLogger.Create;
  SpyIntf := Spy;
  Db := Connect(ItConfig(4).Logger(SpyIntf));
  try
    Db.Table(INFRA_TABLE).Insert(Vals(['tag', 'aaa', 'score', 10]));
    AssertEquals('the insert produced one logged query', 1, Spy.QueryCount);
    AssertTrue('the logged SQL keeps the placeholder, not the value',
      Pos('?', Spy.LastSQL) > 0);
    AssertTrue('the bound value never leaks into the logged SQL',
      Pos('aaa', Spy.LastSQL) = 0);
    AssertEquals('both bound columns reached the logger', 2, Spy.LastBindingCount);
    AssertTrue('elapsed time was measured', Spy.LastElapsedMs >= 0);

    Spy.Reset;
    Cursor := Db.Table(INFRA_TABLE).Where('tag', 'aaa').Get;
    try
      AssertEquals('the select produced one logged query', 1, Spy.QueryCount);
      AssertTrue('the select SQL also keeps the placeholder',
        Pos('?', Spy.LastSQL) > 0);
      AssertEquals('one bound value reached the logger', 1, Spy.LastBindingCount);
    finally
      Cursor.Close;
    end;
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.LoggerRecordsTheFailureAndStillRaises;
var
  Spy: TLzNexSpyLogger;
  SpyIntf: ILzNexLogger;
  Db: ILzNex;
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;
  FDb.Table(INFRA_TABLE).Insert(Vals(['tag', 'dup']));

  Spy := TLzNexSpyLogger.Create;
  SpyIntf := Spy;
  Db := Connect(ItConfig(4).Logger(SpyIntf));
  try
    Raised := False;
    try
      { Chave unica duplicada: falha so na execucao, nao no prepare -- por
        isso passa pelo trecho que loga o erro antes de relancar. Um SQL
        quebrado no prepare NAO passa por ali, veja o relato no final. }
      Db.Table(INFRA_TABLE).Insert(Vals(['tag', 'dup']));
    except
      on E: Exception do
        Raised := True;
    end;
    AssertTrue('a duplicate key still raises', Raised);
    AssertEquals('the failure was logged exactly once', 1, Spy.ErrorCount);
    AssertTrue('the error message reached the logger', Spy.LastError <> '');
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.WithoutALoggerNothingBreaks;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  // FDb nasceu sem Config.Logger(): nem Execute nem Query podem quebrar por isso.
  FDb.Table(INFRA_TABLE).Insert(Vals(['tag', 'nologger']));
  AssertEquals('insert worked with no logger configured', Int64(1),
    FDb.Table(INFRA_TABLE).Count);
end;

procedure TInfraTest.TransactCommitsAndCostsOneAttempt;
var
  Spy: TLzNexSpyWork;
  Work: ILzNexWork;
  Attempts: Integer;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  Spy := TLzNexSpyWork.Create(INFRA_TABLE, 0, False);
  Work := Spy;
  Attempts := FDb.Transact(Work, 3);

  AssertEquals('a clean block costs exactly one attempt', 1, Attempts);
  AssertEquals('the work ran once', 1, Spy.ExecCount);
  AssertEquals('the insert was committed', Int64(1),
    FDb.Table(INFRA_TABLE).Where('tag', 'attempt-1').Count);
end;

procedure TInfraTest.TransactDoesNotRetryAPermanentErrorAndRollsBack;
var
  Spy: TLzNexSpyWork;
  Work: ILzNexWork;
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  Spy := TLzNexSpyWork.Create(INFRA_TABLE, 99, False);
  Work := Spy;
  Raised := False;
  try
    FDb.Transact(Work, 5);
  except
    on E: Exception do
      Raised := True;
  end;

  AssertTrue('a permanent error propagates', Raised);
  AssertEquals('a permanent error is never retried', 1, Spy.ExecCount);
  AssertEquals('the rollback undid the insert', Int64(0),
    FDb.Table(INFRA_TABLE).Where('tag', 'attempt-1').Count);
end;

procedure TInfraTest.TransactRetriesATransientErrorUpToTheLimit;
var
  Spy: TLzNexSpyWork;
  Work: ILzNexWork;
  Attempts: Integer;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  Spy := TLzNexSpyWork.Create(INFRA_TABLE, 2, True);
  Work := Spy;
  Attempts := FDb.Transact(Work, 3);

  AssertEquals('it took all three attempts to succeed', 3, Attempts);
  AssertEquals('the work ran three times', 3, Spy.ExecCount);
  AssertEquals('only the successful attempt is visible', Int64(1),
    FDb.Table(INFRA_TABLE).Count);
  AssertEquals('and it is the last one', Int64(1),
    FDb.Table(INFRA_TABLE).Where('tag', 'attempt-3').Count);
end;

procedure TInfraTest.TransactClampsAttemptsBelowOneToOne;
var
  Spy: TLzNexSpyWork;
  Work: ILzNexWork;
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  { Falharia so na primeira tentativa e teria sucesso na segunda -- mas com
    AAttempts = 0 (tratado como 1) nao ha segunda tentativa. }
  Spy := TLzNexSpyWork.Create(INFRA_TABLE, 1, True);
  Work := Spy;
  Raised := False;
  try
    FDb.Transact(Work, 0);
  except
    on E: Exception do
      Raised := True;
  end;

  AssertTrue('a transient error still propagates when attempts is clamped to one', Raised);
  AssertEquals('exactly one attempt happened', 1, Spy.ExecCount);
end;

procedure TInfraTest.TransactInsideATransactionRaises;
var
  Trx: ILzNexTransaction;
  Spy: TLzNexSpyWork;
  Work: ILzNexWork;
  Raised: Boolean;
  Msg: string;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  Spy := TLzNexSpyWork.Create(INFRA_TABLE, 0, False);
  Work := Spy;
  Trx := FDb.Transaction;
  Raised := False;
  Msg := '';
  try
    try
      Trx.Transact(Work, 3);
    except
      on E: ELzNexTransaction do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
  finally
    if not Trx.IsCompleted then
      Trx.Rollback;
  end;

  AssertTrue('Transact inside a transaction must raise', Raised);
  AssertTrue('the message explains the retry must own the transaction',
    Pos('own', LowerCase(Msg)) > 0);
end;

procedure TInfraTest.TransactWithoutAWorkRaises;
var
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;

  Raised := False;
  try
    FDb.Transact(nil, 3);
  except
    on E: ELzNexTransaction do
      Raised := True;
  end;
  AssertTrue('Transact with a nil work raises', Raised);
end;

procedure TInfraTest.WithoutAReplicaReadConnectionIsThePrimary;
var
  Db: ILzNex;
  Conn: ILzNexConnection;
begin
  if SkipWithoutDatabase then Exit;

  Db := Connect(ItConfig(4).Pool(0, 4));
  try
    AssertEquals('fresh pool, nothing acquired yet', 0, Db.Pool.InUse);
    Conn := Db.ReadConnection;
    AssertEquals('without a replica, ReadConnection draws from the primary pool',
      1, Db.Pool.InUse);
    Conn := nil;
    AssertEquals('releasing it frees the primary pool again', 0, Db.Pool.InUse);
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.PlainSelectUsesTheReadPoolWhenThereIsAReplica;
var
  Db: ILzNex;
  Cursor: ILzNexResult;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;
  FDb.Table(INFRA_TABLE).Insert(Vals(['tag', 'split-a']));

  { Pool(0, N): o primario nasce sem nenhuma conexao fisica. Size (ao
    contrario de InUse) nao volta a zero so por devolver a conexao, entao
    continua provando depois do cursor fechado que o primario nunca foi
    tocado -- nao precisa de thread nem de segurar o cursor aberto. }
  Db := Connect(ItConfig(4).Pool(0, 4).ReadReplica(ItConfig(4)));
  try
    AssertEquals('fresh primary pool has no physical connection yet', 0, Db.Pool.Size);

    Cursor := Db.Table(INFRA_TABLE).Where('tag', 'split-a').Get;
    try
      Cursor.Next;
    finally
      Cursor.Close;
    end;

    AssertEquals('a plain select never touched the primary pool', 0, Db.Pool.Size);
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.ForUpdateUsesThePrimaryEvenForASelect;
var
  Db: ILzNex;
  Cursor: ILzNexResult;
begin
  if SkipWithoutDatabase then Exit;

  if (ItClient = 'sqlite') or (ItClient = 'sqlite3') then
  begin
    Ignore('SQLite has no row lock: ForUpdate raises at compile time, nothing to route');
    Exit;
  end;

  FDb.Table(INFRA_TABLE).Truncate;
  FDb.Table(INFRA_TABLE).Insert(Vals(['tag', 'split-b']));

  Db := Connect(ItConfig(4).Pool(0, 4).ReadReplica(ItConfig(4)));
  try
    AssertEquals('fresh primary pool has no physical connection yet', 0, Db.Pool.Size);

    Cursor := Db.Table(INFRA_TABLE).Where('tag', 'split-b').ForUpdate.Get;
    try
      Cursor.Next;
    finally
      Cursor.Close;
    end;

    AssertEquals('a FOR UPDATE select used the primary pool', 1, Db.Pool.Size);
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.UsePrimaryForcesTheWriteConnection;
var
  Db: ILzNex;
  Cursor: ILzNexResult;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;
  FDb.Table(INFRA_TABLE).Insert(Vals(['tag', 'split-c']));

  Db := Connect(ItConfig(4).Pool(0, 4).ReadReplica(ItConfig(4)));
  try
    AssertEquals('fresh primary pool has no physical connection yet', 0, Db.Pool.Size);

    Cursor := Db.Table(INFRA_TABLE).Where('tag', 'split-c').UsePrimary.Get;
    try
      Cursor.Next;
    finally
      Cursor.Close;
    end;

    AssertEquals('UsePrimary forced the select onto the primary pool', 1, Db.Pool.Size);
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.InsideATransactionReadUsesTheTransactionConnection;
var
  Db: ILzNex;
  Trx: ILzNexTransaction;
  Cursor: ILzNexResult;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;
  FDb.Table(INFRA_TABLE).Insert(Vals(['tag', 'split-d']));

  Db := Connect(ItConfig(4).Pool(0, 4).ReadReplica(ItConfig(4)));
  try
    AssertEquals('fresh primary pool has no physical connection yet', 0, Db.Pool.Size);

    Trx := Db.Transaction;
    try
      AssertEquals('opening the transaction already claimed the one primary connection',
        1, Db.Pool.Size);
      AssertTrue('ReadConnection inside a transaction is the transaction connection itself',
        Pointer(Trx.Connection) = Pointer(Trx.ReadConnection));

      Cursor := Trx.Table(INFRA_TABLE).Where('tag', 'split-d').Get;
      try
        Cursor.Next;
      finally
        Cursor.Close;
      end;

      AssertEquals('the read reused the transaction connection, not a second one',
        1, Db.Pool.Size);

      Trx.Commit;
    finally
      if not Trx.IsCompleted then
        Trx.Rollback;
    end;
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.WritesAlwaysUseThePrimaryConnection;
var
  Db: ILzNex;
begin
  if SkipWithoutDatabase then Exit;
  FDb.Table(INFRA_TABLE).Truncate;

  Db := Connect(ItConfig(4).Pool(0, 4).ReadReplica(ItConfig(4)));
  try
    AssertEquals('fresh primary pool has no physical connection yet', 0, Db.Pool.Size);

    Db.Table(INFRA_TABLE).Insert(Vals(['tag', 'split-e']));

    AssertEquals('the insert opened (and released back to idle) a primary connection',
      1, Db.Pool.Size);
  finally
    Db.Shutdown;
  end;
end;

procedure TInfraTest.ReadReplicaPointingAtItselfRaises;
var
  Cfg: ILzNexConfig;
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;

  Cfg := ItConfig(4);
  Raised := False;
  try
    Cfg.ReadReplica(Cfg);
  except
    on E: ELzNexConfig do
      Raised := True;
  end;
  AssertTrue('a replica pointing at its own config instance is rejected', Raised);
end;

initialization
  RegisterTest('integration', TInfraTest);

end.
