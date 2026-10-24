unit LzNex.Transaction;

{ ILzNexTransaction: facade com a conexao fixada, igual ao trx do knex.

  ILzNexTransaction herda ILzNex, entao a transacao tem que responder a API
  inteira da facade. O que depende de fabrica (Table, From, Query, Raw, Schema,
  Migrator, Seeder) e DELEGADO para a facade pai, recebida no construtor; o que
  depende da conexao (Execute, Fetch, Connection) roda na conexao fixada.

  Nas queries a delegacao vem seguida de Transacting(Self): sem isso a query
  sairia executando numa conexao qualquer do pool, e o INSERT ficaria fora da
  transacao -- que e o bug mais caro possivel nessa camada.

  GARANTIA CENTRAL: o destrutor faz ROLLBACK se nao houve commit. Com isso nunca
  sobra transacao aberta nem conexao emprestada. O destrutor nunca levanta.

  CICLO DE VIDA DO EMPRESTIMO: Commit e Rollback soltam a conexao na hora, nao
  no destrutor. Uma transacao concluida nao tem motivo para continuar segurando
  uma conexao do pool, e esperar o destrutor nao funciona na pratica: no FPC
  3.2.2 o temporario de interface do resultado de Db.Transaction so e liberado
  no fim do PROCEDIMENTO, entao `Trx := nil` NAO destroi o objeto. Com N threads
  e pool max N isso prendia uma conexao por thread e travava tudo ate o timeout
  do Acquire. Soltando no Commit/Rollback, a devolucao deixa de depender da hora
  em que o objeto morre.

  Consequencia: depois de concluida, a transacao nao tem mais conexao. Qualquer
  operacao que precise dela (Table/From/Query/Execute/Fetch/Connection) levanta
  ELzNexTransaction em vez de, calada, pegar outra conexao do pool -- o que
  executaria FORA da transacao sem ninguem perceber.

  Num savepoint quem solta o emprestimo continua sendo a transacao RAIZ: o
  savepoint tambem larga a propria referencia ao concluir, mas a raiz segue
  segurando a conexao, logo o emprestimo so volta ao pool quando a raiz conclui.
  Completar a raiz com savepoint ainda aberto e erro de uso e levanta.

  SOBRE CICLO: a transacao guarda a facade (ILzNex) por interface. A facade NAO
  pode guardar a transacao, senao o refcount nunca zera. Um savepoint guarda o
  pai por interface tambem, e de proposito: forca o filho a morrer antes do pai,
  que e a ordem LIFO que o savepoint do banco exige. O pai nao guarda o filho. }

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
    FDb: ILzNex;                  // facade pai; a facade nao guarda isto de volta
    FParent: ILzNexTransaction;   // so em savepoint; garante destruicao LIFO
    FConn: ILzNexConnection;
    FLevel: Integer;
    FCompleted: Boolean;
    function NeedDb: ILzNex;
    function NeedConn: ILzNexConnection;
    procedure NeedOpen(const AWhat: string);
    // Recusa concluir enquanto houver savepoint aberto por baixo. O nivel vem
    // da conexao (unica fonte que o pai e o filho compartilham), entao nao
    // preciso guardar referencia ao filho -- o que fecharia ciclo.
    procedure NeedNoOpenSavepoint(const AWhat: string);
    // Marca concluida e solta o emprestimo da conexao.
    procedure Finish;
    procedure ApplyIsolation(const AIsolation: TLzNexIsolation);
    function Logger: ILzNexLogger;
    // Monta o fragmento de um SQL cru usando a fabrica Raw da facade pai.
    function RawFragment(const ASQL: string; const AArgs: array of const): TLzNexFragment;
  public
    constructor Create(const ADb: ILzNex; const AConn: ILzNexConnection;
      const AIsolation: TLzNexIsolation; const AParent: ILzNexTransaction);
    destructor Destroy; override;

    // --- ILzNexTransaction ---
    procedure Commit;
    procedure Rollback;
    function Savepoint: ILzNexTransaction;
    function IsCompleted: Boolean;
    function Level: Integer;

    // --- ILzNex: delegado para a facade, mas amarrado a esta transacao ---
    function Table(const AName: string): ILzNexQuery;
    function From(const AName: string): ILzNexQuery;
    function Query: ILzNexQuery;
    function Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
    function Schema: ILzNexSchema;
    function Transaction: ILzNexTransaction; overload;
    function Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction; overload;
    function Migrator: ILzNexMigrator;
    function Seeder: ILzNexSeeder;
    function Execute(const ASQL: string; const AArgs: array of const): Int64;
    function Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
    function Client: ILzNexClient;
    function Config: ILzNexConfig;
    function Pool: ILzNexPool;
    function Connection: ILzNexConnection;
    function IsTransaction: Boolean;
    procedure Shutdown;
  end;

// Abre uma transacao na conexao informada. ADb e a facade pai, que
// atende o que a transacao nao sabe fazer sozinha.
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

  // Comeca marcada como concluida: se ApplyIsolation ou StartTransaction
  // levantarem, o destrutor (que o compilador chama quando o construtor
  // levanta) nao vai tentar desfazer uma transacao que nunca abriu. A conexao
  // ainda e soltada no destrutor, entao o emprestimo do pool volta igual.
  FCompleted := True;

  ApplyIsolation(AIsolation);
  // O Zeos devolve 1 na raiz e >1 quando abre savepoint aninhado.
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
        // Destrutor nao levanta nunca: quem esta saindo de escopo, muitas vezes
        // ja esta tratando outra excecao, e levantar aqui a substituiria.
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

  // Rede de seguranca: numa transacao concluida o Commit/Rollback ja soltou a
  // conexao, entao aqui FConn so ainda aponta para algo no caso abandonado.
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
  // A ordem importa: marcar antes de soltar, para o destrutor nao tentar
  // desfazer uma transacao que ja acabou.
  FCompleted := True;
  // E aqui que o emprestimo volta ao pool, sem esperar o destrutor. Num
  // savepoint isto solta apenas a referencia dele; a raiz continua com a sua,
  // entao a conexao so e devolvida de fato quando a raiz conclui.
  FConn := nil;
end;

procedure TLzNexTransaction.ApplyIsolation(const AIsolation: TLzNexIsolation);
var
  Z: IZConnection;
begin
  if AIsolation = ilDefault then
    Exit;
  // Savepoint nao tem isolamento proprio: quem manda e a transacao raiz.
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

{ ILzNexTransaction }

procedure TLzNexTransaction.Commit;
begin
  NeedOpen('Commit');
  NeedNoOpenSavepoint('Commit');
  try
    FConn.Commit;
  finally
    // Mesmo se o commit falhou: para esta facade a transacao acabou, e a
    // conexao tem que voltar ao pool em vez de ficar presa ate o fim da
    // rotina. O pool desfaz na devolucao o que tiver sobrado aberto.
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
  // O filho guarda este objeto por interface: assim o pai nao pode ser
  // destruido antes, e o savepoint do banco e desfeito na ordem certa.
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

{ ILzNex }

function TLzNexTransaction.Table(const AName: string): ILzNexQuery;
begin
  // Sem este guarda a query sairia do pool por conta propria e executaria FORA
  // da transacao, em silencio -- o bug mais caro possivel nesta camada.
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
  // DDL no MySQL faz commit implicito (Client.DdlIsTransactional = False), logo
  // nao ha o que amarrar a transacao: vai na facade mesmo.
  Result := NeedDb.Schema;
end;

function TLzNexTransaction.Transaction: ILzNexTransaction;
begin
  // Abrir transacao dentro de transacao e savepoint, igual ao knex.
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
  // Devolver nil aqui so adiaria o estouro para um access violation la na
  // frente; melhor dizer o que aconteceu.
  if FCompleted then
    raise ELzNexTransaction.Create(
      'Connection on a transaction already completed: Commit/Rollback returned ' +
      'the connection to the pool. Open a new transaction to keep working.');
  Result := NeedConn;
end;

function TLzNexTransaction.IsTransaction: Boolean;
begin
  Result := True;
end;

procedure TLzNexTransaction.Shutdown;
begin
  // Derrubar o pool a partir de uma transacao fecharia conexoes de outras
  // threads. Quem encerra a biblioteca e a facade, nunca um emprestimo dela.
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
