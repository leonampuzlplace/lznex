unit LzNex.Pool;

{ Pool de conexoes proprio, seguro para uso concorrente.

  Por que um pool proprio e nao o do Zeos: o provider FPC do Horse cria uma
  thread por conexao HTTP, e IZConnection nao pode ser compartilhado entre
  threads. O pool precisa, entao, de duas garantias que o Zeos nao da:

  1) Emprestimo exclusivo com devolucao AUTOMATICA. Acquire devolve um wrapper
     cujo destrutor chama Release. Nao existe "esquecer de devolver", porque nao
     existe chamada de devolucao para esquecer.

  2) Teto respeitado com espera limitada. Estourar o max e esperar mais que o
     timeout levanta ELzNexPool dizendo o tamanho e quantas estao em uso -- que
     e exatamente a informacao que falta quando a aplicacao trava sem explicacao.

  Sobre ciclo de refcount: o wrapper segura o pool por INTERFACE de proposito.
  Isso nao fecha ciclo porque o pool guarda as conexoes INTERNAS, nunca os
  wrappers. O ganho e que o pool nao pode morrer antes do ultimo emprestimo
  (ponteiro de classe pendurado seria a alternativa, e bem pior). }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  SyncObjs,
  LzNex.Types,
  LzNex.Value,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Connection,
  LzNex.Exceptions;

const
  // Espera entre tentativas quando o pool esta cheio.
  LZNEX_POOL_WAIT_STEP_MS = 5;
  LZNEX_POOL_DEFAULT_TIMEOUT_MS = 10000;

type
  TLzNexPool = class;

  // Cursor que segura o emprestimo do pool enquanto existir.
  //
  // Sem isto, `Pool.Acquire.Query(f)` devolveria a conexao ao pool antes de o
  // cursor ser consumido, e o IZResultSet ficaria pendurado num
  // IZPreparedStatement que outra thread poderia estar reexecutando. Com isto o
  // emprestimo acaba no fim da vida do RESULTADO, nao da conexao.
  TLzNexLeasedResult = class(TInterfacedObject, ILzNexResult)
  private
    FLease: ILzNexConnection;
    FInner: ILzNexResult;
    function NeedInner: ILzNexResult;
  public
    constructor Create(const ALease: ILzNexConnection; const AInner: ILzNexResult);
    destructor Destroy; override;

    function Next: Boolean;
    function Field(const AName: string): TLzNexValue;
    function FieldAt(const AIndex: Integer): TLzNexValue;
    function FieldCount: Integer;
    function FieldName(const AIndex: Integer): string;
    function CurrentRow: ILzNexRow;
    function ToRows: TLzNexRowArray;
    function ToJSON: string;
    procedure Close;
  end;

  // Conexao emprestada. Delega tudo para a conexao real e, no
  // destrutor, devolve ao pool.
  TLzNexPooledConnection = class(TInterfacedObject, ILzNexConnection)
  private
    FPool: ILzNexPool;            // mantem o pool vivo; nao fecha ciclo
    FOwner: TLzNexPool;           // acesso direto ao Release, sem cast
    FInner: ILzNexConnection;
    function NeedInner: ILzNexConnection;
  public
    constructor Create(const APool: TLzNexPool; const AInner: ILzNexConnection);
    destructor Destroy; override;

    function Execute(const AFragment: TLzNexFragment): Int64;
    function Query(const AFragment: TLzNexFragment): ILzNexResult;
    function ExecuteScript(const ASQL: string): Int64;
    function LastInsertId: Int64;
    function StartTransaction: Integer;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function TransactionLevel: Integer;
    function Ping: Boolean;
    function IsClosed: Boolean;
    procedure Close;
    function Native: IInterface;
    function Client: ILzNexClient;
  end;

  TLzNexPool = class(TInterfacedObject, ILzNexPool)
  private
    FLock: TCriticalSection;
    FClient: ILzNexClient;
    FParams: TLzNexConnectionParams;
    FIdle: array of ILzNexConnection;
    FIdleCount: Integer;
    FInUse: Integer;
    FMin: Integer;
    FMax: Integer;
    FTimeoutMs: Integer;
    FShutdown: Boolean;
    procedure PushIdle(const AConn: ILzNexConnection);
    function PopIdle: ILzNexConnection;
    function OpenNew: ILzNexConnection;
    // Embrulha a conexao no wrapper de emprestimo. Se a construcao
    // falhar, devolve a conexao em vez de perder o emprestimo.
    function Lend(const AConn: ILzNexConnection): ILzNexConnection;
  public
    constructor Create(const AClient: ILzNexClient;
      const AParams: TLzNexConnectionParams;
      const AMin, AMax, ATimeoutMs: Integer);
    destructor Destroy; override;

    function Acquire: ILzNexConnection;
    function Size: Integer;
    function InUse: Integer;
    procedure Shutdown;

    // Devolve a conexao emprestada. Chamado pelo destrutor do
    // wrapper -- nao e API de usuario final.
    procedure Release(const AConn: ILzNexConnection);
    // Conexoes ociosas no momento. Existe para o teste provar que
    // acquire/release repetidos nao abrem conexao nova toda vez.
    function IdleCount: Integer;
  end;

// Cria o pool e aquece com AMin conexoes.
function NewPool(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams;
  const AMin, AMax, ATimeoutMs: Integer): ILzNexPool; overload;

// Idem, lendo min/max/timeout e os dados de conexao da config.
// E a porta de entrada que a facade usa.
function NewPool(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexPool; overload;

implementation

{ TLzNexLeasedResult }

constructor TLzNexLeasedResult.Create(const ALease: ILzNexConnection;
  const AInner: ILzNexResult);
begin
  inherited Create;
  if AInner = nil then
    raise ELzNexQuery.CreateFmt('Nil cursor while binding the pool lease', '');
  FLease := ALease;
  FInner := AInner;
end;

destructor TLzNexLeasedResult.Destroy;
begin
  // Ordem importa: fecha o cursor ANTES de a conexao voltar ao pool, senao
  // outra thread poderia receber a conexao com o resultset ainda aberto.
  FInner := nil;
  FLease := nil;
  inherited Destroy;
end;

function TLzNexLeasedResult.NeedInner: ILzNexResult;
begin
  if FInner = nil then
    raise ELzNexQuery.CreateFmt('Cursor already released', '');
  Result := FInner;
end;

function TLzNexLeasedResult.Next: Boolean;
begin
  Result := (FInner <> nil) and FInner.Next;
end;

function TLzNexLeasedResult.Field(const AName: string): TLzNexValue;
begin
  Result := NeedInner.Field(AName);
end;

function TLzNexLeasedResult.FieldAt(const AIndex: Integer): TLzNexValue;
begin
  Result := NeedInner.FieldAt(AIndex);
end;

function TLzNexLeasedResult.FieldCount: Integer;
begin
  Result := NeedInner.FieldCount;
end;

function TLzNexLeasedResult.FieldName(const AIndex: Integer): string;
begin
  Result := NeedInner.FieldName(AIndex);
end;

function TLzNexLeasedResult.CurrentRow: ILzNexRow;
begin
  Result := NeedInner.CurrentRow;
end;

function TLzNexLeasedResult.ToRows: TLzNexRowArray;
begin
  Result := NeedInner.ToRows;
end;

function TLzNexLeasedResult.ToJSON: string;
begin
  Result := NeedInner.ToJSON;
end;

procedure TLzNexLeasedResult.Close;
begin
  if FInner <> nil then
    FInner.Close;
end;

{ TLzNexPooledConnection }

constructor TLzNexPooledConnection.Create(const APool: TLzNexPool;
  const AInner: ILzNexConnection);
begin
  inherited Create;
  FOwner := APool;
  FPool := APool as ILzNexPool;
  FInner := AInner;
end;

destructor TLzNexPooledConnection.Destroy;
var
  Inner: ILzNexConnection;
begin
  Inner := FInner;
  FInner := nil;
  if (FOwner <> nil) and (Inner <> nil) then
  begin
    try
      FOwner.Release(Inner);
    except
      // Destrutor nunca levanta: perder uma conexao e ruim, derrubar a
      // aplicacao durante a limpeza e pior.
    end;
  end;
  FPool := nil;
  FOwner := nil;
  inherited Destroy;
end;

function TLzNexPooledConnection.NeedInner: ILzNexConnection;
begin
  if FInner = nil then
    raise ELzNexConnection.Create(
      'This leased connection was already returned to the pool and cannot be used anymore');
  Result := FInner;
end;

function TLzNexPooledConnection.Execute(const AFragment: TLzNexFragment): Int64;
begin
  Result := NeedInner.Execute(AFragment);
end;

function TLzNexPooledConnection.Query(const AFragment: TLzNexFragment): ILzNexResult;
var
  Inner: ILzNexResult;
begin
  Inner := NeedInner.Query(AFragment);
  try
    // Self vai no cursor: assim `Pool.Acquire.Query(f)` nao devolve a conexao
    // antes de alguem ler o resultado.
    Result := TLzNexLeasedResult.Create(Self as ILzNexConnection, Inner)
      as ILzNexResult;
  except
    // Nada de cursor orfao com a conexao presa: fecha antes de propagar.
    Inner.Close;
    raise;
  end;
end;

function TLzNexPooledConnection.ExecuteScript(const ASQL: string): Int64;
begin
  Result := NeedInner.ExecuteScript(ASQL);
end;

function TLzNexPooledConnection.LastInsertId: Int64;
begin
  Result := NeedInner.LastInsertId;
end;

function TLzNexPooledConnection.StartTransaction: Integer;
begin
  Result := NeedInner.StartTransaction;
end;

procedure TLzNexPooledConnection.Commit;
begin
  NeedInner.Commit;
end;

procedure TLzNexPooledConnection.Rollback;
begin
  NeedInner.Rollback;
end;

function TLzNexPooledConnection.InTransaction: Boolean;
begin
  Result := (FInner <> nil) and FInner.InTransaction;
end;

function TLzNexPooledConnection.TransactionLevel: Integer;
begin
  if FInner = nil then
    Exit(0);
  Result := FInner.TransactionLevel;
end;

function TLzNexPooledConnection.Ping: Boolean;
begin
  Result := (FInner <> nil) and FInner.Ping;
end;

function TLzNexPooledConnection.IsClosed: Boolean;
begin
  Result := (FInner = nil) or FInner.IsClosed;
end;

procedure TLzNexPooledConnection.Close;
begin
  // Fecha de verdade: o pool detecta na devolucao e descarta em vez de
  // recolocar uma conexao fechada na lista de ociosas.
  if FInner <> nil then
    FInner.Close;
end;

function TLzNexPooledConnection.Native: IInterface;
begin
  Result := NeedInner.Native;
end;

function TLzNexPooledConnection.Client: ILzNexClient;
begin
  Result := NeedInner.Client;
end;

{ TLzNexPool }

constructor TLzNexPool.Create(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams; const AMin, AMax, ATimeoutMs: Integer);
var
  I: Integer;
begin
  inherited Create;
  // O lock nasce antes de qualquer validacao: uma excecao no construtor faz o
  // compilador chamar o destrutor, e o destrutor precisa do lock.
  FLock := TCriticalSection.Create;

  if AMax < 1 then
    raise ELzNexConfig.CreateFmt('Invalid pool max: %d (must be >= 1)', [AMax]);
  if AMin < 0 then
    raise ELzNexConfig.CreateFmt('Invalid pool min: %d', [AMin]);
  if AMin > AMax then
    raise ELzNexConfig.CreateFmt('Pool min (%d) is greater than max (%d)', [AMin, AMax]);

  FClient := AClient;
  FParams := AParams;
  FMin := AMin;
  FMax := AMax;
  if ATimeoutMs < 0 then
    FTimeoutMs := 0
  else
    FTimeoutMs := ATimeoutMs;
  FIdleCount := 0;
  FInUse := 0;
  FShutdown := False;

  // Aquece: falhar aqui e melhor que falhar na primeira requisicao HTTP.
  for I := 1 to FMin do
    PushIdle(OpenNew);
end;

destructor TLzNexPool.Destroy;
begin
  Shutdown;
  FLock.Free;
  inherited Destroy;
end;

function TLzNexPool.OpenNew: ILzNexConnection;
begin
  Result := NewConnection(FClient, FParams);
end;

function TLzNexPool.Lend(const AConn: ILzNexConnection): ILzNexConnection;
begin
  Result := nil;
  try
    Result := TLzNexPooledConnection.Create(Self, AConn) as ILzNexConnection;
  except
    // Falhar aqui sem devolver vazaria a conexao E a vaga: FInUse ja foi
    // incrementado. O construtor do wrapper so pendura FInner no fim, entao
    // nunca ha dono duplo e Release nao desconta duas vezes.
    Release(AConn);
    raise;
  end;
end;

procedure TLzNexPool.PushIdle(const AConn: ILzNexConnection);
begin
  if FIdleCount >= Length(FIdle) then
    SetLength(FIdle, FIdleCount + 4);
  FIdle[FIdleCount] := AConn;
  Inc(FIdleCount);
end;

function TLzNexPool.PopIdle: ILzNexConnection;
begin
  Result := nil;
  if FIdleCount = 0 then
    Exit;
  Dec(FIdleCount);
  Result := FIdle[FIdleCount];
  FIdle[FIdleCount] := nil;
end;

function TLzNexPool.Acquire: ILzNexConnection;
var
  Conn: ILzNexConnection;
  Deadline: QWord;
  Reserved: Boolean;
begin
  Result := nil;
  Deadline := GetTickCount64 + QWord(FTimeoutMs);

  while True do
  begin
    Conn := nil;
    Reserved := False;

    FLock.Acquire;
    try
      if FShutdown then
        raise ELzNexPool.Create('Pool already shut down: Acquire after Shutdown');

      // Pega a primeira ociosa que responder ao Ping. As mortas saem da lista
      // aqui mesmo: validar na entrega e o que evita entregar conexao zumbi
      // depois de o banco reiniciar.
      while FIdleCount > 0 do
      begin
        Conn := PopIdle;
        if Conn.Ping then
        begin
          Inc(FInUse);
          Break;
        end;
        Conn.Close;
        Conn := nil;
      end;

      if (Conn = nil) and (FInUse + FIdleCount < FMax) then
      begin
        // Reserva a vaga antes de abrir: abrir dentro do lock bloquearia
        // todas as outras threads pelo tempo do handshake com o banco.
        Inc(FInUse);
        Reserved := True;
      end;
    finally
      FLock.Release;
    end;

    if Conn <> nil then
      Exit(Lend(Conn));

    if Reserved then
    begin
      try
        Conn := OpenNew;
      except
        // Abrir falhou: a vaga reservada tem que ser liberada, senao uma base
        // fora do ar esgota o pool em contagem sem ter nenhuma conexao viva.
        FLock.Acquire;
        try
          Dec(FInUse);
        finally
          FLock.Release;
        end;
        raise;
      end;
      Exit(Lend(Conn));
    end;

    if GetTickCount64 >= Deadline then
      raise ELzNexPool.CreateFmt(
        'Pool exhausted: %d connections in total (max %d), %d in use. ' +
        'Waited %d ms and none was returned. Either max is too low, or some ' +
        'ILzNexConnection is being kept alive beyond the request scope.',
        [Size, FMax, InUse, FTimeoutMs]);

    Sleep(LZNEX_POOL_WAIT_STEP_MS);
  end;
end;

procedure TLzNexPool.Release(const AConn: ILzNexConnection);
var
  Keep: Boolean;
  Dead: ILzNexConnection;
begin
  if AConn = nil then
    Exit;

  Dead := nil;
  FLock.Acquire;
  try
    if FInUse > 0 then
      Dec(FInUse);

    // Transacao aberta na devolucao significa que o chamador saiu de escopo sem
    // fechar. Desfaz antes de reciclar, senao a proxima requisicao herdaria
    // tabelas travadas.
    Keep := not FShutdown;
    if Keep then
    begin
      try
        if AConn.IsClosed then
          Keep := False
        else if AConn.InTransaction then
          AConn.Rollback;
      except
        // Qualquer duvida sobre o estado da conexao: descarta. Reciclar uma
        // conexao em estado desconhecido contamina a proxima requisicao.
        Keep := False;
      end;
    end;

    if Keep and (FIdleCount >= FMax) then
      Keep := False;

    if Keep then
      PushIdle(AConn)
    else
      Dead := AConn;
  finally
    FLock.Release;
  end;

  // Fechar fora do lock: fechar faz I/O e nao precisa de exclusao.
  if Dead <> nil then
  begin
    try
      Dead.Close;
    except
    end;
  end;
end;

function TLzNexPool.Size: Integer;
begin
  FLock.Acquire;
  try
    Result := FIdleCount + FInUse;
  finally
    FLock.Release;
  end;
end;

function TLzNexPool.InUse: Integer;
begin
  FLock.Acquire;
  try
    Result := FInUse;
  finally
    FLock.Release;
  end;
end;

function TLzNexPool.IdleCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FIdleCount;
  finally
    FLock.Release;
  end;
end;

procedure TLzNexPool.Shutdown;
var
  Doomed: array of ILzNexConnection;
  I, N: Integer;
begin
  Doomed := nil;
  if FLock = nil then
    Exit;
  // Idempotente: a segunda chamada so encontra a lista vazia e sai.
  FLock.Acquire;
  try
    FShutdown := True;
    N := FIdleCount;
    SetLength(Doomed, N);
    for I := 0 to N - 1 do
    begin
      Doomed[I] := FIdle[I];
      FIdle[I] := nil;
    end;
    FIdleCount := 0;
  finally
    FLock.Release;
  end;

  for I := 0 to N - 1 do
  begin
    try
      Doomed[I].Close;
    except
    end;
    Doomed[I] := nil;
  end;
  SetLength(Doomed, 0);
end;

function NewPool(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams;
  const AMin, AMax, ATimeoutMs: Integer): ILzNexPool;
begin
  Result := TLzNexPool.Create(AClient, AParams, AMin, AMax, ATimeoutMs) as ILzNexPool;
end;

function NewPool(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexPool;
var
  P: TLzNexConnectionParams;
  Min_, Max_, Timeout_: Integer;
begin
  if AConfig = nil then
    raise ELzNexConfig.Create('Nil config while creating the pool');

  P := ParamsFromConfig(AConfig);
  if AClient <> nil then
    P.Protocol := AClient.ZeosProtocol;

  Max_ := AConfig.GetPoolMax;
  if Max_ < 1 then
    Max_ := 10;
  Min_ := AConfig.GetPoolMin;
  if Min_ < 0 then
    Min_ := 0;
  if Min_ > Max_ then
    Min_ := Max_;
  Timeout_ := AConfig.GetAcquireTimeout;
  if Timeout_ <= 0 then
    Timeout_ := LZNEX_POOL_DEFAULT_TIMEOUT_MS;

  Result := TLzNexPool.Create(AClient, P, Min_, Max_, Timeout_) as ILzNexPool;
end;

end.
