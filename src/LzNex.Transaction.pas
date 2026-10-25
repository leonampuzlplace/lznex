unit LzNex.Transaction;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  ZDbcIntfs,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Connection,
  LzNex.Exceptions;

type
  TLzNexTransaction = class(TInterfacedObject, ILzNex, ILzNexTransaction)
  private
    FDb: ILzNex;
    FParent: ILzNexTransaction;
    FConn: ILzNexConnection;
    FLevel: Integer;
    FCompleted: Boolean;
    function NeedDb: ILzNex;
    function NeedConn: ILzNexConnection;
    procedure NeedOpen(const AWhat: string);

    procedure NeedNoOpenSavepoint(const AWhat: string);

    procedure Finish;
    procedure ApplyIsolation(const AIsolation: TLzNexIsolation);
    function Logger: ILzNexLogger;

    function RawFragment(const ASQL: string; const AArgs: array of const): TLzNexFragment;
  public
    constructor Create(const ADb: ILzNex; const AConn: ILzNexConnection;
      const AIsolation: TLzNexIsolation; const AParent: ILzNexTransaction);
    destructor Destroy; override;

    procedure Commit;
    procedure Rollback;
    function Savepoint: ILzNexTransaction;
    function IsCompleted: Boolean;
    function Level: Integer;

    function Table(const AName: string): ILzNexQuery;
    function From(const AName: string): ILzNexQuery;
    function Query: ILzNexQuery;
    function Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
    function Schema: ILzNexSchema;
    function Transaction: ILzNexTransaction; overload;
    function Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction; overload;
    function Transact(const AWork: ILzNexWork;
      const AAttempts: Integer = 1): Integer;
    function Migrator: ILzNexMigrator;
    function Seeder: ILzNexSeeder;
    function Execute(const ASQL: string; const AArgs: array of const): Int64;
    function Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
    function Client: ILzNexClient;
    function Config: ILzNexConfig;
    function Pool: ILzNexPool;
    function Connection: ILzNexConnection;
    function ReadConnection: ILzNexConnection;
    function IsTransaction: Boolean;
    procedure Shutdown;
  end;

function NewTransaction(const ADb: ILzNex; const AConn: ILzNexConnection;
  const AIsolation: TLzNexIsolation): ILzNexTransaction;

implementation

constructor TLzNexTransaction.Create(const ADb: ILzNex;
  const AConn: ILzNexConnection; const AIsolation: TLzNexIsolation;
  const AParent: ILzNexTransaction);
begin
  inherited Create;
  if AConn = nil then
    raise ELzNexTransaction.Create('Transaction without a connection');

  FDb := ADb;
  FParent := AParent;
  FConn := AConn;

  FCompleted := True;

  ApplyIsolation(AIsolation);

  FLevel := FConn.StartTransaction;
  FCompleted := False;
end;

destructor TLzNexTransaction.Destroy;
var
  Log: ILzNexLogger;
begin
  if (not FCompleted) and (FConn <> nil) then
  begin
    try
      FConn.Rollback;
      FCompleted := True;
    except
      on E: Exception do
      begin

        Log := nil;
        try
          Log := Logger;
        except
        end;
        if Log <> nil then
        begin
          try
            Log.LogError('automatic transaction rollback', E.Message);
          except
          end;
        end;
      end;
    end;
  end;

  FConn := nil;
  FParent := nil;
  FDb := nil;
  inherited Destroy;
end;

function TLzNexTransaction.NeedDb: ILzNex;
begin
  if FDb = nil then
    raise ELzNexTransaction.Create(
      'Transaction without a parent facade: Table/From/Query/Raw/Schema require it');
  Result := FDb;
end;

function TLzNexTransaction.NeedConn: ILzNexConnection;
begin
  if FConn = nil then
    raise ELzNexTransaction.Create('Transaction already released');
  Result := FConn;
end;

procedure TLzNexTransaction.NeedOpen(const AWhat: string);
begin
  if FCompleted then
    raise ELzNexTransaction.CreateFmt(
      '%s on an already completed transaction (level %d). Commit and Rollback end ' +
      'the transaction; for another block open a new transaction or a Savepoint.',
      [AWhat, FLevel]);
  if FConn = nil then
    raise ELzNexTransaction.CreateFmt('%s on an already released transaction', [AWhat]);
end;

procedure TLzNexTransaction.NeedNoOpenSavepoint(const AWhat: string);
var
  Lvl: Integer;
begin
  if FConn = nil then
    Exit;
  Lvl := FConn.TransactionLevel;
  if Lvl > FLevel then
    raise ELzNexTransaction.CreateFmt(
      '%s with a savepoint still open: this transaction is at level %d but the ' +
      'connection is at level %d. Complete the inner Savepoint (Commit/Rollback) ' +
      'before completing the outer transaction -- savepoints must be closed in ' +
      'LIFO order.', [AWhat, FLevel, Lvl]);
end;

procedure TLzNexTransaction.Finish;
begin

  FCompleted := True;

  FConn := nil;
end;

procedure TLzNexTransaction.ApplyIsolation(const AIsolation: TLzNexIsolation);
var
  Z: IZConnection;
begin
  if AIsolation = ilDefault then
    Exit;

  if FParent <> nil then
    Exit;

  Z := FConn.Native as IZConnection;
  if Z = nil then
    Exit;
  try
    Z.SetTransactionIsolation(ZeosIsolation(AIsolation));
  except
    on E: Exception do
      raise ELzNexTransaction.Create(
        'The database did not accept the requested isolation level: ' + E.Message);
  end;
end;

function TLzNexTransaction.Logger: ILzNexLogger;
var
  Cfg: ILzNexConfig;
begin
  Result := nil;
  if FDb = nil then
    Exit;
  Cfg := FDb.Config;
  if Cfg <> nil then
    Result := Cfg.GetLogger;
end;

function TLzNexTransaction.RawFragment(const ASQL: string;
  const AArgs: array of const): TLzNexFragment;
var
  R: ILzNexRaw;
begin
  R := NeedDb.Raw(ASQL, AArgs);
  if R = nil then
    raise ELzNexTransaction.Create(
      'The parent facade did not produce an ILzNexRaw: Execute/Fetch with raw SQL ' +
      'depend on it to resolve the template');
  Result := R.Build(Client);
end;

procedure TLzNexTransaction.Commit;
begin
  NeedOpen('Commit');
  NeedNoOpenSavepoint('Commit');
  try
    FConn.Commit;
  finally

    Finish;
  end;
end;

procedure TLzNexTransaction.Rollback;
begin
  NeedOpen('Rollback');
  NeedNoOpenSavepoint('Rollback');
  try
    FConn.Rollback;
  finally
    Finish;
  end;
end;

function TLzNexTransaction.Savepoint: ILzNexTransaction;
begin
  NeedOpen('Savepoint');

  Result := TLzNexTransaction.Create(FDb, NeedConn, ilDefault,
    Self as ILzNexTransaction) as ILzNexTransaction;
end;

function TLzNexTransaction.IsCompleted: Boolean;
begin
  Result := FCompleted;
end;

function TLzNexTransaction.Level: Integer;
begin
  Result := FLevel;
end;

function TLzNexTransaction.Table(const AName: string): ILzNexQuery;
begin

  NeedOpen('Table');
  Result := NeedDb.Table(AName);
  if Result <> nil then
    Result := Result.Transacting(Self as ILzNexTransaction);
end;

function TLzNexTransaction.From(const AName: string): ILzNexQuery;
begin
  NeedOpen('From');
  Result := NeedDb.From(AName);
  if Result <> nil then
    Result := Result.Transacting(Self as ILzNexTransaction);
end;

function TLzNexTransaction.Query: ILzNexQuery;
begin
  NeedOpen('Query');
  Result := NeedDb.Query;
  if Result <> nil then
    Result := Result.Transacting(Self as ILzNexTransaction);
end;

function TLzNexTransaction.Raw(const ASQL: string;
  const AArgs: array of const): ILzNexRaw;
begin
  Result := NeedDb.Raw(ASQL, AArgs);
end;

function TLzNexTransaction.Schema: ILzNexSchema;
begin

  Result := NeedDb.Schema;
end;

function TLzNexTransaction.Transaction: ILzNexTransaction;
begin

  Result := Savepoint;
end;

function TLzNexTransaction.Transaction(
  const AIsolation: TLzNexIsolation): ILzNexTransaction;
begin
  if AIsolation <> ilDefault then
    raise ELzNexTransaction.Create(
      'A savepoint has no isolation level of its own: isolation belongs to the ' +
      'root transaction. Use Transaction without arguments.');
  Result := Savepoint;
end;

function TLzNexTransaction.Transact(const AWork: ILzNexWork;
  const AAttempts: Integer): Integer;
begin
  { Repetir aqui nao faria o que o nome promete: o bloco de fora continuaria
    valendo, e o savepoint sozinho nao desfaz o que ele ja escreveu. }
  raise ELzNexTransaction.Create(
    'Transact inside a transaction. The retry has to own the transaction to be ' +
    'able to run the block again -- call Transact on the facade, and inside ' +
    'the block use Savepoint if you need a nested scope.');
end;

function TLzNexTransaction.Migrator: ILzNexMigrator;
begin
  Result := NeedDb.Migrator;
end;

function TLzNexTransaction.Seeder: ILzNexSeeder;
begin
  Result := NeedDb.Seeder;
end;

function TLzNexTransaction.Execute(const ASQL: string;
  const AArgs: array of const): Int64;
begin
  NeedOpen('Execute');
  Result := NeedConn.Execute(RawFragment(ASQL, AArgs));
end;

function TLzNexTransaction.Fetch(const ASQL: string;
  const AArgs: array of const): ILzNexResult;
begin
  NeedOpen('Fetch');
  Result := NeedConn.Query(RawFragment(ASQL, AArgs));
end;

function TLzNexTransaction.Client: ILzNexClient;
begin
  Result := nil;
  if FConn <> nil then
    Result := FConn.Client;
  if (Result = nil) and (FDb <> nil) then
    Result := FDb.Client;
end;

function TLzNexTransaction.Config: ILzNexConfig;
begin
  Result := NeedDb.Config;
end;

function TLzNexTransaction.Pool: ILzNexPool;
begin
  Result := NeedDb.Pool;
end;

function TLzNexTransaction.Connection: ILzNexConnection;
begin

  if FCompleted then
    raise ELzNexTransaction.Create(
      'Connection on a transaction already completed: Commit/Rollback returned ' +
      'the connection to the pool. Open a new transaction to keep working.');
  Result := NeedConn;
end;

function TLzNexTransaction.ReadConnection: ILzNexConnection;
begin
  { Dentro de transacao nao existe leitura noutra conexao: a replica nao veria
    o que esta transacao ainda nao commitou. }
  Result := Connection;
end;

function TLzNexTransaction.IsTransaction: Boolean;
begin
  Result := True;
end;

procedure TLzNexTransaction.Shutdown;
begin

  raise ELzNexTransaction.Create(
    'Shutdown on a transaction. End the transaction (Commit/Rollback) and call ' +
    'Shutdown on the facade.');
end;

function NewTransaction(const ADb: ILzNex; const AConn: ILzNexConnection;
  const AIsolation: TLzNexIsolation): ILzNexTransaction;
begin
  Result := TLzNexTransaction.Create(ADb, AConn, AIsolation, nil)
    as ILzNexTransaction;
end;

end.
