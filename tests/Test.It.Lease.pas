unit Test.It.Lease;

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

  { Conexao emprestada tem de voltar ao pool em todo caminho de saida -- e o
    caminho que mais escapa da atencao e o de erro. Estes testes nao olham
    memoria: olham InUse, que e observavel e diz a mesma coisa. }
  TLeaseTest = class(TTestCase)
  protected
    FDb: ILzNex;
    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;

    { O insert fica num metodo proprio de proposito: a query que sai de
      Trx.Table(...) guarda a transacao, e o FPC so descarta esse temporario
      no fim do bloco onde ele nasceu. Medir InUse no mesmo bloco mediria o
      temporario, nao o destrutor da transacao. }
    procedure InsertAndAbandon;
  published
    procedure CommitReturnsTheConnection;
    procedure RollbackReturnsTheConnection;
    procedure AbandonedTransactionReturnsTheConnection;
    procedure QueryInsideTransactionDoesNotHoldTheLease;
    procedure TransactReturnsTheConnectionOnCommit;
    procedure TransactReturnsTheConnectionOnRollback;
    procedure TransactReturnsTheConnectionOnEveryRetry;
  end;

  // Falha nas primeiras ATentativas execucoes; o resto comita.
  TLeaseWork = class(TInterfacedObject, ILzNexWork)
  private
    FTable: string;
    FFailFirst: Integer;
    FRetryable: Boolean;
    FRuns: Integer;
  public
    constructor Create(const ATable: string; const AFailFirst: Integer;
      const ARetryable: Boolean);
    procedure Execute(const ADb: ILzNex);
    property Runs: Integer read FRuns;
  end;

implementation

const
  LEASE_TABLE = 'it_lease';

var
  GTableReady: Boolean = False;

constructor TLeaseWork.Create(const ATable: string; const AFailFirst: Integer;
  const ARetryable: Boolean);
begin
  inherited Create;
  FTable := ATable;
  FFailFirst := AFailFirst;
  FRetryable := ARetryable;
  FRuns := 0;
end;

procedure TLeaseWork.Execute(const ADb: ILzNex);
begin
  Inc(FRuns);
  ADb.Table(FTable).Insert(Vals(['tag', 'run-' + IntToStr(FRuns)]));

  if FRuns > FFailFirst then
    Exit;

  if FRetryable then
    // SQLSTATE 40001 e transitorio na base de todo dialeto: nao e preciso
    // provocar um deadlock de verdade para exercitar o retry.
    raise ELzNexQuery.CreateDb('synthetic transient failure', 'SYNTHETIC',
      1213, '40001');
  raise Exception.Create('synthetic permanent failure');
end;

function TLeaseTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: lease test skipped');
end;

procedure TLeaseTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin
    FDb.Schema.DropTableIfExists(LEASE_TABLE);
    FDb.Schema.CreateTable(LEASE_TABLE)
      .Increments('id')
      .Str('tag', 60).NotNull
      .Execute;
    GTableReady := True;
  end;
  FDb.Table(LEASE_TABLE).Truncate;
end;

procedure TLeaseTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TLeaseTest.CommitReturnsTheConnection;
var
  Trx: ILzNexTransaction;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  Trx.Table(LEASE_TABLE).Insert(Vals(['tag', 'committed']));
  Trx.Commit;
  Trx := nil;

  AssertEquals('no connection still in use after commit', 0, FDb.Pool.InUse);
end;

procedure TLeaseTest.RollbackReturnsTheConnection;
var
  Trx: ILzNexTransaction;
begin
  if SkipWithoutDatabase then Exit;

  Trx := FDb.Transaction;
  Trx.Table(LEASE_TABLE).Insert(Vals(['tag', 'rolled-back']));
  Trx.Rollback;
  Trx := nil;

  AssertEquals('no connection still in use after rollback', 0, FDb.Pool.InUse);
  AssertEquals('the insert was undone', Int64(0),
    FDb.Table(LEASE_TABLE).Count);
end;

procedure TLeaseTest.InsertAndAbandon;
var
  Trx: ILzNexTransaction;
begin
  Trx := FDb.Transaction;
  Trx.Table(LEASE_TABLE).Insert(Vals(['tag', 'abandoned']));
  // Sai sem Commit nem Rollback: quem desfaz e solta a conexao e o destrutor.
end;

procedure TLeaseTest.AbandonedTransactionReturnsTheConnection;
begin
  if SkipWithoutDatabase then Exit;

  InsertAndAbandon;

  AssertEquals('no connection still in use after the destructor', 0,
    FDb.Pool.InUse);
  AssertEquals('the insert was undone', Int64(0),
    FDb.Table(LEASE_TABLE).Count);
end;

procedure TLeaseTest.QueryInsideTransactionDoesNotHoldTheLease;
var
  Trx: ILzNexTransaction;
  Q: ILzNexQuery;
begin
  if SkipWithoutDatabase then Exit;

  { A query guarda a transacao (e a transacao, a conexao). Manter a query viva
    depois do Commit nao pode segurar a vaga do pool. }
  Trx := FDb.Transaction;
  Q := Trx.Table(LEASE_TABLE);
  Q.Insert(Vals(['tag', 'with-query']));
  Trx.Commit;
  Trx := nil;

  AssertEquals('the surviving query does not hold the lease', 0, FDb.Pool.InUse);
  Q := nil;
end;

procedure TLeaseTest.TransactReturnsTheConnectionOnCommit;
var
  Work: ILzNexWork;
  Spy: TLeaseWork;
begin
  if SkipWithoutDatabase then Exit;

  Spy := TLeaseWork.Create(LEASE_TABLE, 0, False);
  Work := Spy;

  AssertEquals('a clean block costs one attempt', 1, FDb.Transact(Work, 3));
  AssertEquals('no connection still in use', 0, FDb.Pool.InUse);
end;

procedure TLeaseTest.TransactReturnsTheConnectionOnRollback;
var
  Work: ILzNexWork;
  Spy: TLeaseWork;
  Raised: Boolean;
begin
  if SkipWithoutDatabase then Exit;

  Spy := TLeaseWork.Create(LEASE_TABLE, 1, False);
  Work := Spy;

  Raised := False;
  try
    FDb.Transact(Work, 3);
  except
    on E: Exception do
      Raised := True;
  end;

  AssertTrue('a permanent error propagates', Raised);
  AssertEquals('a permanent error does not retry', 1, Spy.Runs);
  AssertEquals('no connection still in use after the rollback', 0,
    FDb.Pool.InUse);
  AssertEquals('the failed attempt was undone', Int64(0),
    FDb.Table(LEASE_TABLE).Count);
end;

procedure TLeaseTest.TransactReturnsTheConnectionOnEveryRetry;
var
  Work: ILzNexWork;
  Spy: TLeaseWork;
begin
  if SkipWithoutDatabase then Exit;

  // Falha duas vezes, comita na terceira: tres leases, tres devolucoes.
  Spy := TLeaseWork.Create(LEASE_TABLE, 2, True);
  Work := Spy;

  AssertEquals('it took three attempts', 3, FDb.Transact(Work, 3));
  AssertEquals('the block ran three times', 3, Spy.Runs);
  AssertEquals('no connection still in use after the retries', 0,
    FDb.Pool.InUse);
  AssertEquals('only the committed attempt survived', Int64(1),
    FDb.Table(LEASE_TABLE).Count);
end;

initialization
  RegisterTest('integration', TLeaseTest);

end.
