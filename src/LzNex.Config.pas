unit LzNex.Config;

{ Configuracao fluente do LzNex (o equivalente do knexfile) mais um logger de
  console.

  Tres caminhos de entrada, do mais explicito ao mais automatico:
    1. TLzNexConfig.New.Client('mysql').Host(...)...   -- codigo
    2. LoadConfigFile('lznex.json', 'development')     -- arquivo, por ambiente
    3. ApplyEnvOverrides(Cfg)                          -- LZNEX_* do ambiente

  Os tres compoem: o arquivo ja aplica as LZNEX_* por cima, que e o que faz a
  mesma imagem de container servir para dev, CI e producao. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  { GetJSON esta declarado em fpjson, mas quem registra o parser concreto e a
    unit jsonparser. Sem ela no uses compila e falha SO EM RUNTIME. }
  fpjson,
  jsonparser,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Exceptions,
  LzNex.Intf;

const
  LZNEX_DEFAULT_PORT            = 3306;
  LZNEX_DEFAULT_CHARSET         = 'utf8mb4';
  LZNEX_DEFAULT_POOL_MIN        = 2;
  LZNEX_DEFAULT_POOL_MAX        = 10;
  LZNEX_DEFAULT_ACQUIRE_TIMEOUT = 30000;
  LZNEX_DEFAULT_MIGRATIONS_DIR  = 'database/migrations';
  LZNEX_DEFAULT_SEEDS_DIR       = 'database/seeds';

  // Ambiente usado quando nem o chamador nem LZNEX_ENV informam qual e.
  LZNEX_DEFAULT_ENV = 'development';

  // Prefixo das variaveis de ambiente reconhecidas.
  LZNEX_ENV_PREFIX = 'LZNEX_';

type
  TLzNexConfig = class(TInterfacedObject, ILzNexConfig)
  private
    FClient: string;
    FHost: string;
    FPort: Integer;
    FDatabase: string;
    FUser: string;
    FPassword: string;
    FLibraryLocation: string;
    FCharset: string;
    FPoolMin: Integer;
    FPoolMax: Integer;
    FAcquireTimeout: Integer;
    FMigrationsTable: string;
    FMigrationsDir: string;
    FSeedsDir: string;
    FProps: TLzNexNamedValues;
    FLogger: ILzNexLogger;
  public
    constructor Create;

    // Ponto de partida da cadeia fluente.
    class function New: ILzNexConfig;

    function Client(const AName: string): ILzNexConfig;
    function Host(const AValue: string): ILzNexConfig;
    function Port(const AValue: Integer): ILzNexConfig;
    function Database(const AValue: string): ILzNexConfig;
    function User(const AValue: string): ILzNexConfig;
    function Password(const AValue: string): ILzNexConfig;
    function LibraryLocation(const AValue: string): ILzNexConfig;
    function Charset(const AValue: string): ILzNexConfig;
    function Pool(const AMin, AMax: Integer): ILzNexConfig;
    function AcquireTimeout(const AMilliseconds: Integer): ILzNexConfig;
    function MigrationsTable(const AValue: string): ILzNexConfig;
    function MigrationsDir(const AValue: string): ILzNexConfig;
    function SeedsDir(const AValue: string): ILzNexConfig;
    function Prop(const AName, AValue: string): ILzNexConfig;
    function Logger(const AValue: ILzNexLogger): ILzNexConfig;

    function GetClient: string;
    function GetHost: string;
    function GetPort: Integer;
    function GetDatabase: string;
    function GetUser: string;
    function GetPassword: string;
    function GetLibraryLocation: string;
    function GetCharset: string;
    function GetPoolMin: Integer;
    function GetPoolMax: Integer;
    function GetAcquireTimeout: Integer;
    function GetMigrationsTable: string;
    function GetMigrationsDir: string;
    function GetSeedsDir: string;
    function GetProps: TLzNexNamedValues;
    function GetLogger: ILzNexLogger;
    procedure Validate;
  end;

  { Escreve no stdout com Flush. O Flush nao e detalhe: stdout redirecionado
    (container, pipe, CI) e bufferizado, e sem flush o log do processo que
    morre no meio simplesmente desaparece. }
  TLzNexConsoleLogger = class(TInterfacedObject, ILzNexLogger)
  private
    FLogQueries: Boolean;
    procedure Emit(const ATag, AText: string);
  public
    // ALogQueries False silencia so o LogQuery; aviso e erro sempre saem.
    constructor Create(const ALogQueries: Boolean = True);
    class function New(const ALogQueries: Boolean = True): ILzNexLogger;

    procedure LogQuery(const ASQL: string; const ABindings: TLzNexBindings;
      const AElapsedMs: Int64);
    procedure LogError(const ASQL: string; const AError: string);
    procedure LogWarning(const AMessage: string);
    procedure LogInfo(const AMessage: string);
  end;

// Le um arquivo JSON de configuracao e devolve o ambiente pedido, com as
// LZNEX_* aplicadas por cima. AEnv vazio usa LZNEX_ENV, ou 'development'.
function LoadConfigFile(const APath, AEnv: string): ILzNexConfig;

// Igual ao LoadConfigFile mas a partir do texto JSON ja em memoria.
function LoadConfigJSON(const AJSON, AEnv: string): ILzNexConfig;

// Aplica pares nome/valor como sobrescrita. Aceita 'LZNEX_HOST' ou 'host'.
// Existe separado do ambiente para dar para testar sem mexer no processo.
function ApplyOverrides(const AConfig: ILzNexConfig;
  const AValues: TLzNexNamedValues): ILzNexConfig;

// Le as LZNEX_* do ambiente do processo e aplica. Valor ausente nao mexe
// no que ja estava: sobrescrita e sempre aditiva.
function ApplyEnvOverrides(const AConfig: ILzNexConfig): ILzNexConfig;

// Os nomes de variavel de ambiente reconhecidos, para mensagem de ajuda.
function EnvOverrideNames: TLzNexStringArray;

implementation

{ TLzNexConfig }

constructor TLzNexConfig.Create;
begin
  inherited Create;
  FPort := LZNEX_DEFAULT_PORT;
  FCharset := LZNEX_DEFAULT_CHARSET;
  FPoolMin := LZNEX_DEFAULT_POOL_MIN;
  FPoolMax := LZNEX_DEFAULT_POOL_MAX;
  FAcquireTimeout := LZNEX_DEFAULT_ACQUIRE_TIMEOUT;
  FMigrationsTable := LZNEX_MIGRATIONS_TABLE;
  FMigrationsDir := LZNEX_DEFAULT_MIGRATIONS_DIR;
  FSeedsDir := LZNEX_DEFAULT_SEEDS_DIR;
  FProps := nil;
end;

class function TLzNexConfig.New: ILzNexConfig;
begin
  Result := TLzNexConfig.Create;
end;

function TLzNexConfig.Client(const AName: string): ILzNexConfig;
begin
  FClient := AName;
  Result := Self;
end;

function TLzNexConfig.Host(const AValue: string): ILzNexConfig;
begin
  FHost := AValue;
  Result := Self;
end;

function TLzNexConfig.Port(const AValue: Integer): ILzNexConfig;
begin
  FPort := AValue;
  Result := Self;
end;

function TLzNexConfig.Database(const AValue: string): ILzNexConfig;
begin
  FDatabase := AValue;
  Result := Self;
end;

function TLzNexConfig.User(const AValue: string): ILzNexConfig;
begin
  FUser := AValue;
  Result := Self;
end;

function TLzNexConfig.Password(const AValue: string): ILzNexConfig;
begin
  FPassword := AValue;
  Result := Self;
end;

function TLzNexConfig.LibraryLocation(const AValue: string): ILzNexConfig;
begin
  FLibraryLocation := AValue;
  Result := Self;
end;

function TLzNexConfig.Charset(const AValue: string): ILzNexConfig;
begin
  FCharset := AValue;
  Result := Self;
end;

function TLzNexConfig.Pool(const AMin, AMax: Integer): ILzNexConfig;
begin
  if AMin < 0 then
    raise ELzNexConfig.CreateFmt('Pool minimum cannot be negative (%d).', [AMin]);
  if AMax < 1 then
    raise ELzNexConfig.CreateFmt('Pool maximum must be at least 1 (%d).', [AMax]);
  if AMin > AMax then
    raise ELzNexConfig.CreateFmt('Pool minimum (%d) greater than the maximum (%d).', [AMin, AMax]);
  FPoolMin := AMin;
  FPoolMax := AMax;
  Result := Self;
end;

function TLzNexConfig.AcquireTimeout(const AMilliseconds: Integer): ILzNexConfig;
begin
  FAcquireTimeout := AMilliseconds;
  Result := Self;
end;

function TLzNexConfig.MigrationsTable(const AValue: string): ILzNexConfig;
begin
  FMigrationsTable := AValue;
  Result := Self;
end;

function TLzNexConfig.MigrationsDir(const AValue: string): ILzNexConfig;
begin
  FMigrationsDir := AValue;
  Result := Self;
end;

function TLzNexConfig.SeedsDir(const AValue: string): ILzNexConfig;
begin
  FSeedsDir := AValue;
  Result := Self;
end;

function TLzNexConfig.Prop(const AName, AValue: string): ILzNexConfig;
var
  I, N: Integer;
begin
  Result := Self;
  for I := 0 to High(FProps) do
    if SameText(FProps[I].Name, AName) then
    begin
      FProps[I].Value := TLzNexValue.FromString(AValue);
      Exit;
    end;
  N := Length(FProps);
  SetLength(FProps, N + 1);
  FProps[N].Name := AName;
  FProps[N].Value := TLzNexValue.FromString(AValue);
end;

function TLzNexConfig.Logger(const AValue: ILzNexLogger): ILzNexConfig;
begin
  FLogger := AValue;
  Result := Self;
end;

function TLzNexConfig.GetClient: string;
begin
  Result := FClient;
end;

function TLzNexConfig.GetHost: string;
begin
  Result := FHost;
end;

function TLzNexConfig.GetPort: Integer;
begin
  Result := FPort;
end;

function TLzNexConfig.GetDatabase: string;
begin
  Result := FDatabase;
end;

function TLzNexConfig.GetUser: string;
begin
  Result := FUser;
end;

function TLzNexConfig.GetPassword: string;
begin
  Result := FPassword;
end;

function TLzNexConfig.GetLibraryLocation: string;
begin
  Result := FLibraryLocation;
end;

function TLzNexConfig.GetCharset: string;
begin
  Result := FCharset;
end;

function TLzNexConfig.GetPoolMin: Integer;
begin
  Result := FPoolMin;
end;

function TLzNexConfig.GetPoolMax: Integer;
begin
  Result := FPoolMax;
end;

function TLzNexConfig.GetAcquireTimeout: Integer;
begin
  Result := FAcquireTimeout;
end;

function TLzNexConfig.GetMigrationsTable: string;
begin
  Result := FMigrationsTable;
end;

function TLzNexConfig.GetMigrationsDir: string;
begin
  Result := FMigrationsDir;
end;

function TLzNexConfig.GetSeedsDir: string;
begin
  Result := FSeedsDir;
end;

function TLzNexConfig.GetProps: TLzNexNamedValues;
var
  I: Integer;
begin
  { Copia: o chamador nao mexe no estado interno por acidente. }
  Result := nil;
  SetLength(Result, Length(FProps));
  for I := 0 to High(FProps) do
    Result[I] := FProps[I];
end;

function TLzNexConfig.GetLogger: ILzNexLogger;
begin
  Result := FLogger;
end;

procedure TLzNexConfig.Validate;
var
  Missing: string;
begin
  Missing := '';
  if Trim(FClient) = '' then
    Missing := Missing + ' client';
  if Trim(FHost) = '' then
    Missing := Missing + ' host';
  if Trim(FDatabase) = '' then
    Missing := Missing + ' database';

  if Missing <> '' then
    raise ELzNexConfig.Create(
      'Incomplete configuration. Missing:' + Missing + '.' + sLineBreak +
      'Provide it in code (TLzNexConfig.New.Client(''mysql'').Host(...)), ' +
      'by JSON file (LoadConfigFile) or by environment variable ' +
      '(LZNEX_HOST, LZNEX_DATABASE, ...).');

  if FPort <= 0 then
    raise ELzNexConfig.CreateFmt('Invalid port (%d).', [FPort]);
  if FPoolMax < 1 then
    raise ELzNexConfig.CreateFmt('Invalid pool maximum (%d).', [FPoolMax]);
  if FPoolMin > FPoolMax then
    raise ELzNexConfig.CreateFmt('Pool minimum (%d) greater than the maximum (%d).',
      [FPoolMin, FPoolMax]);
  if FAcquireTimeout < 0 then
    raise ELzNexConfig.CreateFmt('Invalid acquire timeout (%d).',
      [FAcquireTimeout]);
end;

{ TLzNexConsoleLogger }

constructor TLzNexConsoleLogger.Create(const ALogQueries: Boolean);
begin
  inherited Create;
  FLogQueries := ALogQueries;
end;

class function TLzNexConsoleLogger.New(const ALogQueries: Boolean): ILzNexLogger;
begin
  Result := TLzNexConsoleLogger.Create(ALogQueries);
end;

procedure TLzNexConsoleLogger.Emit(const ATag, AText: string);
begin
  Writeln(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), ' [lznex] ', ATag, ' ', AText);
  { Sem isso o log nao aparece em stdout redirecionado. }
  Flush(Output);
end;

procedure TLzNexConsoleLogger.LogQuery(const ASQL: string;
  const ABindings: TLzNexBindings; const AElapsedMs: Int64);
var
  B: TLzNexBindings;
  Suffix: string;
begin
  if not FLogQueries then
    Exit;
  B := ABindings;
  if B.Count > 0 then
    Suffix := '  binds=' + B.Describe
  else
    Suffix := '';
  Emit('query', Format('(%dms) %s%s', [AElapsedMs, ASQL, Suffix]));
end;

procedure TLzNexConsoleLogger.LogError(const ASQL: string; const AError: string);
begin
  if ASQL <> '' then
    Emit('error', AError + sLineBreak + '  sql: ' + ASQL)
  else
    Emit('error', AError);
end;

procedure TLzNexConsoleLogger.LogWarning(const AMessage: string);
begin
  Emit('warn ', AMessage);
end;

procedure TLzNexConsoleLogger.LogInfo(const AMessage: string);
begin
  Emit('info ', AMessage);
end;

{ ------------------------------------------------------------------
  Leitura de JSON
  ------------------------------------------------------------------ }

// O objeto filho, ou nil se nao existir / nao for objeto.
function JChildObject(const AObj: TJSONObject; const AName: string): TJSONObject;
var
  D: TJSONData;
begin
  Result := nil;
  if AObj = nil then
    Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType = jtObject) then
    Result := TJSONObject(D);
end;

// Primeiro texto encontrado em ANested.AName, depois em ARoot.AName.
function JStr(const ANested, ARoot: TJSONObject;
  const AName, ADefault: string): string;
var
  D: TJSONData;
begin
  Result := ADefault;
  if ANested <> nil then
  begin
    D := ANested.Find(AName);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Exit(D.AsString);
  end;
  if ARoot <> nil then
  begin
    D := ARoot.Find(AName);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Exit(D.AsString);
  end;
end;

function JInt(const ANested, ARoot: TJSONObject; const AName: string;
  const ADefault: Integer): Integer;
var
  D: TJSONData;
begin
  Result := ADefault;
  if ANested <> nil then
  begin
    D := ANested.Find(AName);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Exit(D.AsInteger);
  end;
  if ARoot <> nil then
  begin
    D := ARoot.Find(AName);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Exit(D.AsInteger);
  end;
end;

// Os nomes de primeiro nivel, para a mensagem de "ambiente nao existe".
function JKeyList(const AObj: TJSONObject): string;
var
  I: Integer;
begin
  Result := '';
  if AObj = nil then
    Exit;
  for I := 0 to AObj.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + AObj.Names[I];
  end;
end;

// Resolve qual no do JSON descreve o ambiente pedido.
function PickEnvNode(const ARoot: TJSONObject; const AEnv: string;
  const AWhere: string): TJSONObject;
var
  D: TJSONData;
begin
  D := ARoot.Find(AEnv);
  if (D <> nil) and (D.JSONType = jtObject) then
    Exit(TJSONObject(D));

  { Arquivo sem ambientes: a raiz E a configuracao. }
  if (ARoot.Find('client') <> nil) or (ARoot.Find('connection') <> nil) then
    Exit(ARoot);

  raise ELzNexConfig.Create(
    'Environment "' + AEnv + '" does not exist in ' + AWhere + '.' + sLineBreak +
    'Top-level keys: ' + JKeyList(ARoot) + '.');
end;

// Precedencia: o que o chamador pediu, depois LZNEX_ENV, depois a chave
// "default" do proprio arquivo, e por fim 'development'.
function ResolveEnvName(const AEnv: string; const ARoot: TJSONObject): string;
var
  D: TJSONData;
begin
  Result := Trim(AEnv);
  if Result = '' then
    Result := Trim(GetEnvironmentVariable(LZNEX_ENV_PREFIX + 'ENV'));
  if (Result = '') and (ARoot <> nil) then
  begin
    D := ARoot.Find('default');
    if (D <> nil) and (D.JSONType = jtString) then
      Result := Trim(D.AsString);
  end;
  if Result = '' then
    Result := LZNEX_DEFAULT_ENV;
end;

function BuildFromNode(const ANode: TJSONObject; const AEnv: string): ILzNexConfig;
var
  Conn, PoolNode, MigNode, SeedNode, PropsNode: TJSONObject;
  I: Integer;
  Timeout: Integer;
begin
  Conn := JChildObject(ANode, 'connection');
  PoolNode := JChildObject(ANode, 'pool');
  MigNode := JChildObject(ANode, 'migrations');
  SeedNode := JChildObject(ANode, 'seeds');
  PropsNode := JChildObject(ANode, 'props');

  Result := TLzNexConfig.New;
  Result
    .Client(JStr(ANode, nil, 'client', ''))
    .Host(JStr(Conn, ANode, 'host', ''))
    .Port(JInt(Conn, ANode, 'port', LZNEX_DEFAULT_PORT))
    .Database(JStr(Conn, ANode, 'database', ''))
    .User(JStr(Conn, ANode, 'user', ''))
    .Password(JStr(Conn, ANode, 'password', ''))
    .Charset(JStr(Conn, ANode, 'charset', LZNEX_DEFAULT_CHARSET))
    .LibraryLocation(JStr(Conn, ANode, 'libraryLocation', ''))
    .MigrationsTable(JStr(MigNode, nil, 'table', LZNEX_MIGRATIONS_TABLE))
    .MigrationsDir(JStr(MigNode, nil, 'directory', LZNEX_DEFAULT_MIGRATIONS_DIR))
    .SeedsDir(JStr(SeedNode, nil, 'directory', LZNEX_DEFAULT_SEEDS_DIR));

  { Pool depois dos outros: o setter valida min <= max e aborta a cadeia. }
  Result.Pool(JInt(PoolNode, nil, 'min', LZNEX_DEFAULT_POOL_MIN),
              JInt(PoolNode, nil, 'max', LZNEX_DEFAULT_POOL_MAX));

  Timeout := JInt(PoolNode, ANode, 'acquireTimeout', LZNEX_DEFAULT_ACQUIRE_TIMEOUT);
  Result.AcquireTimeout(Timeout);

  Result.Prop('env', AEnv);
  if PropsNode <> nil then
    for I := 0 to PropsNode.Count - 1 do
      Result.Prop(PropsNode.Names[I], PropsNode.Items[I].AsString);
end;

function LoadConfigJSON(const AJSON, AEnv: string): ILzNexConfig;
var
  Data: TJSONData;
  Env: string;
begin
  Result := nil;
  try
    Data := GetJSON(AJSON);
  except
    on E: Exception do
      raise ELzNexConfig.Create('Invalid configuration JSON: ' + E.Message);
  end;
  if Data = nil then
    raise ELzNexConfig.Create('Empty configuration JSON.');
  { O TJSONData devolvido por GetJSON e DO CHAMADOR: sem este try/finally,
    qualquer validacao que levante abaixo vazaria a arvore inteira. }
  try
    if Data.JSONType <> jtObject then
      raise ELzNexConfig.Create(
        'Configuration JSON must be an object at the root.');
    Env := ResolveEnvName(AEnv, TJSONObject(Data));
    Result := BuildFromNode(PickEnvNode(TJSONObject(Data), Env, 'the JSON'), Env);
  finally
    Data.Free;
  end;
  ApplyEnvOverrides(Result);
end;

function LoadConfigFile(const APath, AEnv: string): ILzNexConfig;
var
  SL: TStringList;
  Text: string;
begin
  if not FileExists(APath) then
    raise ELzNexConfig.Create(
      'Configuration file not found: ' + APath + '.');
  SL := TStringList.Create;
  try
    SL.LoadFromFile(APath);
    Text := SL.Text;
  finally
    SL.Free;
  end;
  try
    Result := LoadConfigJSON(Text, AEnv);
  except
    on E: ELzNexConfig do
      { Reescreve so para o caminho do arquivo aparecer na mensagem. }
      raise ELzNexConfig.Create(E.Message + sLineBreak + 'File: ' + APath);
  end;
end;

{ ------------------------------------------------------------------
  Sobrescrita
  ------------------------------------------------------------------ }

function EnvOverrideNames: TLzNexStringArray;
begin
  Result := nil;
  SetLength(Result, 14);
  Result[0]  := LZNEX_ENV_PREFIX + 'CLIENT';
  Result[1]  := LZNEX_ENV_PREFIX + 'HOST';
  Result[2]  := LZNEX_ENV_PREFIX + 'PORT';
  Result[3]  := LZNEX_ENV_PREFIX + 'DATABASE';
  Result[4]  := LZNEX_ENV_PREFIX + 'USER';
  Result[5]  := LZNEX_ENV_PREFIX + 'PASSWORD';
  Result[6]  := LZNEX_ENV_PREFIX + 'CHARSET';
  Result[7]  := LZNEX_ENV_PREFIX + 'LIBRARY';
  Result[8]  := LZNEX_ENV_PREFIX + 'POOL_MIN';
  Result[9]  := LZNEX_ENV_PREFIX + 'POOL_MAX';
  Result[10] := LZNEX_ENV_PREFIX + 'ACQUIRE_TIMEOUT';
  Result[11] := LZNEX_ENV_PREFIX + 'MIGRATIONS_TABLE';
  Result[12] := LZNEX_ENV_PREFIX + 'MIGRATIONS_DIR';
  Result[13] := LZNEX_ENV_PREFIX + 'SEEDS_DIR';
end;

// 'LZNEX_POOL_MIN' e 'pool_min' chegam na mesma chave canonica.
function CanonicalKey(const AName: string): string;
begin
  Result := UpperCase(Trim(AName));
  if Pos(LZNEX_ENV_PREFIX, Result) = 1 then
    Delete(Result, 1, Length(LZNEX_ENV_PREFIX));
end;

// Falha alto: valor numerico torto em variavel de ambiente e erro de deploy,
// nao algo para silenciar com default.
function ParseIntStrict(const AText, AWhat: string): Integer;
begin
  if not TryStrToInt(Trim(AText), Result) then
    raise ELzNexConfig.Create(
      AWhat + ' expected an integer, got "' + AText + '".');
end;

function ApplyOverrides(const AConfig: ILzNexConfig;
  const AValues: TLzNexNamedValues): ILzNexConfig;
var
  I: Integer;
  Key, Val: string;
  PMin, PMax: Integer;
begin
  Result := AConfig;
  if Result = nil then
    raise ELzNexConfig.Create('Override applied to a nil config.');

  PMin := Result.GetPoolMin;
  PMax := Result.GetPoolMax;

  for I := 0 to High(AValues) do
  begin
    Key := CanonicalKey(AValues[I].Name);
    Val := AValues[I].Value.Text;
    if Val = '' then
      Continue;

    if Key = 'CLIENT' then
      Result.Client(Val)
    else if Key = 'HOST' then
      Result.Host(Val)
    else if Key = 'PORT' then
      Result.Port(ParseIntStrict(Val, 'Port'))
    else if Key = 'DATABASE' then
      Result.Database(Val)
    else if Key = 'USER' then
      Result.User(Val)
    else if Key = 'PASSWORD' then
      Result.Password(Val)
    else if Key = 'CHARSET' then
      Result.Charset(Val)
    else if (Key = 'LIBRARY') or (Key = 'LIBRARY_LOCATION') then
      Result.LibraryLocation(Val)
    else if Key = 'POOL_MIN' then
      PMin := ParseIntStrict(Val, 'Pool minimum')
    else if Key = 'POOL_MAX' then
      PMax := ParseIntStrict(Val, 'Pool maximum')
    else if Key = 'ACQUIRE_TIMEOUT' then
      Result.AcquireTimeout(ParseIntStrict(Val, 'Acquire timeout'))
    else if Key = 'MIGRATIONS_TABLE' then
      Result.MigrationsTable(Val)
    else if Key = 'MIGRATIONS_DIR' then
      Result.MigrationsDir(Val)
    else if Key = 'SEEDS_DIR' then
      Result.SeedsDir(Val)
    else
      { Chave desconhecida vira prop: permite passar coisa de dialeto
        (ssl, timezone) sem a config ter que conhecer cada uma. }
      Result.Prop(LowerCase(Key), Val);
  end;

  if (PMin <> Result.GetPoolMin) or (PMax <> Result.GetPoolMax) then
    Result.Pool(PMin, PMax);
end;

function ApplyEnvOverrides(const AConfig: ILzNexConfig): ILzNexConfig;
var
  Names: TLzNexStringArray;
  Pairs: TLzNexNamedValues;
  I, N: Integer;
  Val: string;
begin
  Names := EnvOverrideNames;
  Pairs := nil;
  N := 0;
  SetLength(Pairs, Length(Names));
  for I := 0 to High(Names) do
  begin
    Val := GetEnvironmentVariable(Names[I]);
    if Val = '' then
      Continue;
    Pairs[N].Name := Names[I];
    Pairs[N].Value := TLzNexValue.FromString(Val);
    Inc(N);
  end;
  SetLength(Pairs, N);
  Result := ApplyOverrides(AConfig, Pairs);
end;

end.
