unit LzNex.Pool;

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

  LZNEX_POOL_WAIT_STEP_MS = 5;
  LZNEX_POOL_DEFAULT_TIMEOUT_MS = 10000;

type
  TLzNexPool = class;

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

  TLzNexPooledConnection = class(TInterfacedObject, ILzNexConnection)
  private
    FPool: ILzNexPool;
    FOwner: TLzNexPool;
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

    // Repassado a cada conexao aberta: e lá que a query e cronometrada.
    FLogger: ILzNexLogger;
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

    function Lend(const AConn: ILzNexConnection): ILzNexConnection;
  public
    constructor Create(const AClient: ILzNexClient;
      const AParams: TLzNexConnectionParams;
      const AMin, AMax, ATimeoutMs: Integer;
      const ALogger: ILzNexLogger = nil);
    destructor Destroy; override;

    function Acquire: ILzNexConnection;
    function Size: Integer;
    function InUse: Integer;
    procedure Shutdown;

    procedure Release(const AConn: ILzNexConnection);

    function IdleCount: Integer;
  end;

function NewPool(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams;
  const AMin, AMax, ATimeoutMs: Integer;
  const ALogger: ILzNexLogger = nil): ILzNexPool; overload;

function NewPool(const AConfig: ILzNexConfig;
  const AClient: ILzNexClient): ILzNexPool; overload;

implementation

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

  { Solta o lease aqui, nao no destrutor: quem chamou Close espera a conexao de
    volta no pool na hora. Esperar o refcount morrer prenderia a conexao ate a
    variavel sair de escopo, e com pool pequeno a proxima query bateria em
    "Pool exhausted". }
  FLease := nil;
end;

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

    Result := TLzNexLeasedResult.Create(Self as ILzNexConnection, Inner)
      as ILzNexResult;
  except

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

constructor TLzNexPool.Create(const AClient: ILzNexClient;
  const AParams: TLzNexConnectionParams; const AMin, AMax, ATimeoutMs: Integer;
  const ALogger: ILzNexLogger);
var
  I: Integer;
begin
  inherited Create;

  FLock := TCriticalSection.Create;

  if AMax < 1 then
    raise ELzNexConfig.CreateFmt('Invalid pool max: %d (must be >= 1)', [AMax]);
  if AMin < 0 then
    raise ELzNexConfig.CreateFmt('Invalid pool min: %d', [AMin]);
  if AMin > AMax then
    raise ELzNexConfig.CreateFmt('Pool min (%d) is greater than max (%d)', [AMin, AMax]);

  FClient := AClient;
  FParams := AParams;
  FLogger := ALogger;
  FMin := AMin;
  FMax := AMax;
  if ATimeoutMs < 0 then
    FTimeoutMs := 0
  else
    FTimeoutMs := ATimeoutMs;
  FIdleCount := 0;
  FInUse := 0;
  FShutdown := False;

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
  Result := NewConnection(FClient, FParams, FLogger);
end;

function TLzNexPool.Lend(const AConn: ILzNexConnection): ILzNexConnection;
begin
  Result := nil;
  try
    Result := TLzNexPooledConnection.Create(Self, AConn) as ILzNexConnection;
  except

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

      Conn := PopIdle;
      if Conn <> nil then
        Inc(FInUse)
      else if FInUse + FIdleCount < FMax then
      begin

        Inc(FInUse);
        Reserved := True;
      end;
    finally
      FLock.Release;
    end;

    { Ping fora do lock: e ida ao servidor, e segurar o lock durante um timeout
      de rede pararia o Acquire de todas as outras threads. A conexao ja saiu
      do idle e conta em InUse, entao ninguem mais a pega enquanto isso. }
    if Conn <> nil then
    begin
      if Conn.Ping then
        Exit(Lend(Conn));

      // Morta do outro lado: fecha, devolve a vaga e procura outra.
      try
        Conn.Close;
      except
      end;
      Conn := nil;
      FLock.Acquire;
      try
        if FInUse > 0 then
          Dec(FInUse);
      finally
        FLock.Release;
      end;
      Continue;
    end;

    if Reserved then
    begin
      try
        Conn := OpenNew;
      except

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

  { Desfazer a transacao esquecida e ida ao servidor, e acontece fora do lock:
    uma devolucao lenta nao pode parar o Acquire das outras threads. A conexao
    ainda conta em InUse aqui, entao ninguem a pega no meio disso. }
  Keep := True;
  try
    if AConn.IsClosed then
      Keep := False
    else if AConn.InTransaction then
      AConn.Rollback;
  except

    Keep := False;
  end;

  Dead := nil;
  FLock.Acquire;
  try
    if FInUse > 0 then
      Dec(FInUse);

    if FShutdown or (FIdleCount >= FMax) then
      Keep := False;

    if Keep then
      PushIdle(AConn)
    else
      Dead := AConn;
  finally
    FLock.Release;
  end;

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
  const AMin, AMax, ATimeoutMs: Integer;
  const ALogger: ILzNexLogger): ILzNexPool;
begin
  Result := TLzNexPool.Create(AClient, AParams, AMin, AMax, ATimeoutMs, ALogger)
    as ILzNexPool;
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

  Result := TLzNexPool.Create(AClient, P, Min_, Max_, Timeout_,
    AConfig.GetLogger) as ILzNexPool;
end;

end.
