program ProbeMigration;

{ Sonda de configuracao, migrations e seeds.

  Roda SEM banco: a facade ILzNex e a camada de conexao sao de outro agente.
  O que depende de conexao (Latest, Rollback, Status com linhas) fica de fora;
  o que e logica pura (config, registry, fonte .sql, splitter, ordem das seeds)
  e todo exercitado aqui.

  Para a parte que precisa de uma ILzNex so para existir, ha o TStubDb no fim
  deste arquivo: devolve a config e levanta em tudo que exigiria conexao.

  A sobrescrita por variavel de ambiente nao da para testar no proprio
  processo: no Unix o FPC le o envp capturado no exec, e setenv() da libc nao
  mexe nele. Entao o teste reexecuta ESTE binario com as LZNEX_* no ambiente
  (modo 'envchild') e confere o exit code do filho. }

{$MODE DELPHI}{$H+}

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Exceptions,
  LzNex.Intf,
  LzNex.Config,
  LzNex.Migration,
  LzNex.Migration.Source.Code,
  LzNex.Migration.Source.Sql,
  LzNex.Migrator,
  LzNex.Seed;

var
  GChecks: Integer = 0;
  GSeedLog: string = '';

procedure Check(const AWhat: string; ACond: Boolean);
begin
  Inc(GChecks);
  if ACond then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    ExitCode := 1;
  end;
end;

// ============================================================
//  Migrations de teste
// ============================================================

type
  TMigB = class(TLzNexMigration)
  public
    class function MigrationName: string; override;
    procedure Up(const ADb: ILzNex); override;
    procedure Down(const ADb: ILzNex); override;
  end;

  TMigA = class(TLzNexMigration)
  public
    class function MigrationName: string; override;
    procedure Up(const ADb: ILzNex); override;
    procedure Down(const ADb: ILzNex); override;
  end;

  TMigC = class(TLzNexMigration)
  public
    class function MigrationName: string; override;
    function UseTransaction: Boolean; override;
    procedure Up(const ADb: ILzNex); override;
    procedure Down(const ADb: ILzNex); override;
  end;

  // Mesmo Id de TMigA: o registry tem que recusar.
  TMigDup = class(TLzNexMigration)
  public
    class function MigrationName: string; override;
    procedure Up(const ADb: ILzNex); override;
    procedure Down(const ADb: ILzNex); override;
  end;

class function TMigB.MigrationName: string;
begin
  Result := '20240202120000_create_posts';
end;

procedure TMigB.Up(const ADb: ILzNex);
begin
end;

procedure TMigB.Down(const ADb: ILzNex);
begin
end;

class function TMigA.MigrationName: string;
begin
  Result := '20240101090000_create_users';
end;

procedure TMigA.Up(const ADb: ILzNex);
begin
end;

procedure TMigA.Down(const ADb: ILzNex);
begin
end;

class function TMigC.MigrationName: string;
begin
  Result := '20240303150000_add_index';
end;

function TMigC.UseTransaction: Boolean;
begin
  Result := False;
end;

procedure TMigC.Up(const ADb: ILzNex);
begin
end;

procedure TMigC.Down(const ADb: ILzNex);
begin
end;

class function TMigDup.MigrationName: string;
begin
  Result := '20240101090000_outra_coisa';
end;

procedure TMigDup.Up(const ADb: ILzNex);
begin
end;

procedure TMigDup.Down(const ADb: ILzNex);
begin
end;

// ============================================================
//  Seeds de teste
// ============================================================

type
  TSeedPosts = class(TLzNexSeed)
  public
    class function SeedName: string; override;
    procedure Run(const ADb: ILzNex); override;
  end;

  TSeedUsers = class(TLzNexSeed)
  public
    class function SeedName: string; override;
    procedure Run(const ADb: ILzNex); override;
  end;

  TSeedBoom = class(TLzNexSeed)
  public
    class function SeedName: string; override;
    procedure Run(const ADb: ILzNex); override;
  end;

class function TSeedPosts.SeedName: string;
begin
  Result := '02_posts';
end;

procedure TSeedPosts.Run(const ADb: ILzNex);
begin
  GSeedLog := GSeedLog + 'posts;';
end;

class function TSeedUsers.SeedName: string;
begin
  Result := '01_users';
end;

procedure TSeedUsers.Run(const ADb: ILzNex);
begin
  GSeedLog := GSeedLog + 'users;';
end;

class function TSeedBoom.SeedName: string;
begin
  Result := '99_boom';
end;

procedure TSeedBoom.Run(const ADb: ILzNex);
begin
  raise Exception.Create('coluna email nao existe');
end;

// ============================================================
//  Stub da facade
// ============================================================

type
  { So Config responde de verdade. Serve para construir o Migrator e o Seeder
    e exercitar o que nao toca no banco. }
  TStubDb = class(TInterfacedObject, ILzNex)
  private
    FConfig: ILzNexConfig;
    procedure NotImpl(const AWhat: string);
  public
    constructor Create(const AConfig: ILzNexConfig);

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

constructor TStubDb.Create(const AConfig: ILzNexConfig);
begin
  inherited Create;
  FConfig := AConfig;
end;

procedure TStubDb.NotImpl(const AWhat: string);
begin
  raise ELzNex.Create('TStubDb nao implementa ' + AWhat +
    ' (a camada de conexao e de outro agente).');
end;

function TStubDb.Table(const AName: string): ILzNexQuery;
begin
  Result := nil;
  NotImpl('Table');
end;

function TStubDb.From(const AName: string): ILzNexQuery;
begin
  Result := nil;
  NotImpl('From');
end;

function TStubDb.Query: ILzNexQuery;
begin
  Result := nil;
  NotImpl('Query');
end;

function TStubDb.Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
begin
  Result := nil;
  NotImpl('Raw');
end;

function TStubDb.Schema: ILzNexSchema;
begin
  Result := nil;
  NotImpl('Schema');
end;

function TStubDb.Transaction: ILzNexTransaction;
begin
  Result := nil;
  NotImpl('Transaction');
end;

function TStubDb.Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction;
begin
  Result := nil;
  NotImpl('Transaction(isolation)');
end;

function TStubDb.Migrator: ILzNexMigrator;
begin
  Result := NewMigrator(Self);
end;

function TStubDb.Seeder: ILzNexSeeder;
begin
  Result := NewSeeder(Self);
end;

function TStubDb.Execute(const ASQL: string; const AArgs: array of const): Int64;
begin
  Result := 0;
  NotImpl('Execute');
end;

function TStubDb.Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
begin
  Result := nil;
  NotImpl('Fetch');
end;

function TStubDb.Client: ILzNexClient;
begin
  { nil de proposito: nenhum dialeto concreto esta registrado nesta sonda. }
  Result := nil;
end;

function TStubDb.Config: ILzNexConfig;
begin
  Result := FConfig;
end;

function TStubDb.Pool: ILzNexPool;
begin
  Result := nil;
  NotImpl('Pool');
end;

function TStubDb.Connection: ILzNexConnection;
begin
  Result := nil;
  NotImpl('Connection');
end;

function TStubDb.IsTransaction: Boolean;
begin
  Result := False;
end;

procedure TStubDb.Shutdown;
begin
end;

// ============================================================
//  Helpers
// ============================================================

procedure WriteTextFile(const APath, AContent: string);
var
  F: TextFile;
begin
  AssignFile(F, APath);
  Rewrite(F);
  try
    Write(F, AContent);
  finally
    CloseFile(F);
  end;
end;

const
  CONFIG_JSON =
    '{' + sLineBreak +
    '  "development": {' + sLineBreak +
    '    "client": "mysql",' + sLineBreak +
    '    "connection": {' + sLineBreak +
    '      "host": "localhost", "port": 3307, "database": "lznex_dev",' + sLineBreak +
    '      "user": "root", "password": "secret"' + sLineBreak +
    '    },' + sLineBreak +
    '    "pool": { "min": 1, "max": 5, "acquireTimeout": 9000 },' + sLineBreak +
    '    "migrations": { "table": "mig_ctl", "directory": "db/mig" },' + sLineBreak +
    '    "seeds": { "directory": "db/seeds" },' + sLineBreak +
    '    "props": { "timezone": "UTC" }' + sLineBreak +
    '  },' + sLineBreak +
    '  "production": {' + sLineBreak +
    '    "client": "mysql",' + sLineBreak +
    '    "connection": { "host": "db.prod", "database": "lznex" }' + sLineBreak +
    '  }' + sLineBreak +
    '}';

  SQL_MULTI =
    '-- cria a tabela; com ponto e virgula no comentario' + sLineBreak +
    'create table a (' + sLineBreak +
    '  id int,' + sLineBreak +
    '  nota varchar(50) default ''ponto; e virgula''' + sLineBreak +
    ');' + sLineBreak +
    sLineBreak +
    '/* bloco; com ; dentro */' + sLineBreak +
    'insert into a (id, nota) values (1, ''a;b'');' + sLineBreak +
    '# comentario de cerquilha;' + sLineBreak +
    'update a set nota = ''c'' where id = 1;' + sLineBreak +
    ';' + sLineBreak;

// ============================================================
//  Modo filho: so a sobrescrita por variavel de ambiente
// ============================================================

procedure RunEnvChild;
var
  Cfg: ILzNexConfig;
begin
  Writeln('--- filho: sobrescrita por variavel de ambiente ---');

  Cfg := TLzNexConfig.New
    .Client('mysql')
    .Host('do-json')
    .Port(3306)
    .Database('do-json-db')
    .User('do-json-user')
    .Password('do-json-pass');

  ApplyEnvOverrides(Cfg);

  Check('LZNEX_HOST sobrescreve', Cfg.GetHost = 'envhost');
  Check('LZNEX_PORT sobrescreve', Cfg.GetPort = 3310);
  Check('LZNEX_DATABASE sobrescreve', Cfg.GetDatabase = 'envdb');
  Check('LZNEX_USER sobrescreve', Cfg.GetUser = 'envuser');
  Check('LZNEX_PASSWORD sobrescreve', Cfg.GetPassword = 'envpass');
  Check('o que o ambiente nao informa continua', Cfg.GetClient = 'mysql');
  Check('LZNEX_MIGRATIONS_TABLE sobrescreve', Cfg.GetMigrationsTable = 'envmig');

  Writeln('  (filho: ', GChecks, ' assercoes)');
  Flush(Output);
end;

// ============================================================
//  Principal
//
//  Corpo numa procedure, nao no bloco do programa: a saida pelo caminho do
//  filho usava Halt, e Halt pula a finalizacao dos temporarios do bloco
//  principal -- o temporario de ParamStr vazava 33 bytes, visto pelo heaptrc.
//  Saindo normalmente de uma procedure, tudo e finalizado.
// ============================================================

procedure RunProbe;
var
  Cfg: ILzNexConfig;
  Raised: Boolean;
  Msg: string;
  Pairs: TLzNexNamedValues;
  Dir, JsonPath: string;
  Src: ILzNexMigrationSource;
  CodeSrc: ILzNexMigrationSource;
  Items: TLzNexMigrationArray;
  Parts: TLzNexStringArray;
  Logger: ILzNexLogger;
  Stub: ILzNex;
  Mig: ILzNexMigrator;
  MigObj: TLzNexMigrator;
  Seeder: ILzNexSeeder;
  ChildExit: Integer;
  Props: TLzNexNamedValues;
  I: Integer;
  Stub2: ILzNex;
  Loop, Fails: Integer;

begin
  Writeln('=== sonda de config, migrations e seeds do LzNex ===');
  Writeln;
  Writeln('-- config: defaults --');

  Cfg := TLzNexConfig.New;
  Check('porta default 3306', Cfg.GetPort = 3306);
  Check('charset default utf8mb4', Cfg.GetCharset = 'utf8mb4');
  Check('pool default 2/10', (Cfg.GetPoolMin = 2) and (Cfg.GetPoolMax = 10));
  Check('timeout de aquisicao default 30000', Cfg.GetAcquireTimeout = 30000);
  Check('tabela de migrations default', Cfg.GetMigrationsTable = LZNEX_MIGRATIONS_TABLE);
  Check('diretorio de migrations default', Cfg.GetMigrationsDir = 'database/migrations');
  Check('diretorio de seeds default', Cfg.GetSeedsDir = 'database/seeds');
  Check('logger default nulo', Cfg.GetLogger = nil);

  Writeln;
  Writeln('-- config: cadeia fluente --');

  Cfg := TLzNexConfig.New
    .Client('mysql')
    .Host('127.0.0.1')
    .Port(3307)
    .Database('lznex')
    .User('root')
    .Password('secret')
    .Charset('utf8mb4')
    .LibraryLocation('/usr/lib/x86_64-linux-gnu/libmariadb.so.3')
    .Pool(1, 4)
    .AcquireTimeout(5000)
    .MigrationsTable('mig')
    .MigrationsDir('db/mig')
    .SeedsDir('db/seed')
    .Prop('timezone', 'UTC');

  Check('a cadeia devolve a mesma config', Cfg.GetClient = 'mysql');
  Check('host', Cfg.GetHost = '127.0.0.1');
  Check('porta', Cfg.GetPort = 3307);
  Check('database', Cfg.GetDatabase = 'lznex');
  Check('user', Cfg.GetUser = 'root');
  Check('password', Cfg.GetPassword = 'secret');
  Check('libraryLocation', Pos('libmariadb', Cfg.GetLibraryLocation) > 0);
  Check('pool 1/4', (Cfg.GetPoolMin = 1) and (Cfg.GetPoolMax = 4));
  Check('timeout 5000', Cfg.GetAcquireTimeout = 5000);
  Check('tabela de migrations', Cfg.GetMigrationsTable = 'mig');
  Props := Cfg.GetProps;
  Check('prop gravada', (Length(Props) = 1) and (Props[0].Name = 'timezone') and
    (Props[0].Value.AsString = 'UTC'));
  Cfg.Prop('timezone', 'America/Sao_Paulo');
  Props := Cfg.GetProps;
  Check('prop repetida sobrescreve em vez de duplicar',
    (Length(Props) = 1) and (Props[0].Value.AsString = 'America/Sao_Paulo'));
  Cfg.Validate;
  Check('Validate passa com client/host/database', True);

  Writeln;
  Writeln('-- config: Validate levanta --');

  Raised := False;
  Msg := '';
  try
    TLzNexConfig.New.Host('h').Database('d').Validate;
  except
    on E: ELzNexConfig do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('sem client levanta ELzNexConfig', Raised);
  Check('a mensagem diz o que faltou', Pos('client', Msg) > 0);

  Raised := False;
  try
    TLzNexConfig.New.Client('mysql').Database('d').Validate;
  except
    on E: ELzNexConfig do Raised := True;
  end;
  Check('sem host levanta', Raised);

  Raised := False;
  try
    TLzNexConfig.New.Client('mysql').Host('h').Validate;
  except
    on E: ELzNexConfig do Raised := True;
  end;
  Check('sem database levanta', Raised);

  Raised := False;
  try
    TLzNexConfig.New.Pool(5, 2);
  except
    on E: ELzNexConfig do Raised := True;
  end;
  Check('pool min > max levanta no setter', Raised);

  Writeln;
  Writeln('-- config: JSON com ambientes --');

  Dir := '/tmp/lznex-probe-mig-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  JsonPath := Dir + '/lznex.json';
  WriteTextFile(JsonPath, CONFIG_JSON);

  Cfg := LoadConfigFile(JsonPath, 'development');
  Check('json dev: client', Cfg.GetClient = 'mysql');
  Check('json dev: host', Cfg.GetHost = 'localhost');
  Check('json dev: porta', Cfg.GetPort = 3307);
  Check('json dev: database', Cfg.GetDatabase = 'lznex_dev');
  Check('json dev: user/password',
    (Cfg.GetUser = 'root') and (Cfg.GetPassword = 'secret'));
  Check('json dev: pool 1/5', (Cfg.GetPoolMin = 1) and (Cfg.GetPoolMax = 5));
  Check('json dev: acquireTimeout', Cfg.GetAcquireTimeout = 9000);
  Check('json dev: tabela de migrations', Cfg.GetMigrationsTable = 'mig_ctl');
  Check('json dev: diretorio de migrations', Cfg.GetMigrationsDir = 'db/mig');
  Check('json dev: diretorio de seeds', Cfg.GetSeedsDir = 'db/seeds');
  Props := Cfg.GetProps;
  Msg := '';
  for I := 0 to High(Props) do
    if Props[I].Name = 'timezone' then
      Msg := Props[I].Value.AsString;
  Check('json dev: props', Msg = 'UTC');
  Msg := '';
  for I := 0 to High(Props) do
    if Props[I].Name = 'env' then
      Msg := Props[I].Value.AsString;
  Check('json guarda o ambiente usado numa prop', Msg = 'development');

  Cfg := LoadConfigFile(JsonPath, 'production');
  Check('json prod: host', Cfg.GetHost = 'db.prod');
  Check('json prod: porta volta ao default', Cfg.GetPort = 3306);
  Check('json prod: charset volta ao default', Cfg.GetCharset = 'utf8mb4');
  Check('json prod: pool volta ao default',
    (Cfg.GetPoolMin = 2) and (Cfg.GetPoolMax = 10));
  Check('json prod: tabela de migrations volta ao default',
    Cfg.GetMigrationsTable = LZNEX_MIGRATIONS_TABLE);

  Raised := False;
  Msg := '';
  try
    LoadConfigFile(JsonPath, 'staging');
  except
    on E: ELzNexConfig do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('ambiente inexistente levanta', Raised);
  Check('a mensagem lista os ambientes disponiveis',
    (Pos('development', Msg) > 0) and (Pos('production', Msg) > 0));

  Raised := False;
  try
    LoadConfigFile(Dir + '/nao-existe.json', 'development');
  except
    on E: ELzNexConfig do Raised := True;
  end;
  Check('arquivo inexistente levanta', Raised);

  Raised := False;
  try
    LoadConfigJSON('{ nao e json', 'development');
  except
    on E: ELzNexConfig do Raised := True;
  end;
  Check('json invalido levanta ELzNexConfig (parser registrado)', Raised);

  { Arquivo sem ambientes: a raiz e a propria config. }
  Cfg := LoadConfigJSON('{"client":"mysql","connection":{"host":"h","database":"d"}}', '');
  Check('json sem ambientes usa a raiz',
    (Cfg.GetHost = 'h') and (Cfg.GetDatabase = 'd'));

  { A chave "default" escolhe o ambiente quando o chamador nao informa. }
  Cfg := LoadConfigJSON(
    '{"default":"test",' +
    '"development":{"client":"mysql","host":"dev","database":"d"},' +
    '"test":{"client":"mysql","host":"tst","database":"t"}}', '');
  Check('a chave "default" escolhe o ambiente', Cfg.GetHost = 'tst');
  Cfg := LoadConfigJSON(
    '{"default":"test",' +
    '"development":{"client":"mysql","host":"dev","database":"d"},' +
    '"test":{"client":"mysql","host":"tst","database":"t"}}', 'development');
  Check('o ambiente pedido vence a chave "default"', Cfg.GetHost = 'dev');

  { O knexfile real do projeto: campos de conexao achatados no ambiente. }
  Check('database/lznex.json existe', FileExists('/work/database/lznex.json'));
  if FileExists('/work/database/lznex.json') then
  begin
    Cfg := LoadConfigFile('/work/database/lznex.json', '');
    Check('lznex.json: "default" leva ao ambiente development',
      Cfg.GetDatabase = 'lznex');
    Check('lznex.json: conexao achatada no ambiente',
      (Cfg.GetHost = 'mysql') and (Cfg.GetUser = 'root'));
    Check('lznex.json: libraryLocation',
      Pos('libmariadb', Cfg.GetLibraryLocation) > 0);
    Check('lznex.json: pool aninhado',
      (Cfg.GetPoolMin = 2) and (Cfg.GetPoolMax = 10));
    Check('lznex.json: migrations aninhado',
      (Cfg.GetMigrationsTable = 'migrations') and
      (Cfg.GetMigrationsDir = 'database/migrations'));
    Check('lznex.json: seeds aninhado', Cfg.GetSeedsDir = 'database/seeds');
    Cfg := LoadConfigFile('/work/database/lznex.json', 'test');
    Check('lznex.json: ambiente test',
      (Cfg.GetDatabase = 'lznex_test') and (Cfg.GetPoolMax = 4));
    Cfg.Validate;
    Check('lznex.json passa no Validate', True);
  end;

  { As migrations .sql de exemplo do projeto. }
  Check('as migrations .sql de exemplo sao descobertas',
    Length(TLzNexSqlMigrationSource.NewOptional(
      '/work/database/migrations').All) >= 1);

  Writeln;
  Writeln('-- config: sobrescrita por pares --');

  Pairs := nil;
  SetLength(Pairs, 4);
  Pairs[0].Name := 'LZNEX_HOST';
  Pairs[0].Value := TLzNexValue.FromString('outro-host');
  Pairs[1].Name := 'LZNEX_PORT';
  Pairs[1].Value := TLzNexValue.FromString('3399');
  Pairs[2].Name := 'LZNEX_POOL_MAX';
  Pairs[2].Value := TLzNexValue.FromString('20');
  Pairs[3].Name := 'ssl_mode';
  Pairs[3].Value := TLzNexValue.FromString('REQUIRED');

  Cfg := TLzNexConfig.New.Client('mysql').Host('h').Database('d');
  ApplyOverrides(Cfg, Pairs);
  Check('sobrescrita de host', Cfg.GetHost = 'outro-host');
  Check('sobrescrita de porta converte para inteiro', Cfg.GetPort = 3399);
  Check('sobrescrita de pool max', Cfg.GetPoolMax = 20);
  Check('sobrescrita de pool preserva o min', Cfg.GetPoolMin = 2);
  Props := Cfg.GetProps;
  Check('chave desconhecida vira prop',
    (Length(Props) = 1) and (Props[0].Name = 'ssl_mode'));

  Raised := False;
  SetLength(Pairs, 1);
  Pairs[0].Name := 'LZNEX_PORT';
  Pairs[0].Value := TLzNexValue.FromString('nao-e-numero');
  try
    ApplyOverrides(TLzNexConfig.New, Pairs);
  except
    on E: ELzNexConfig do Raised := True;
  end;
  Check('porta nao numerica levanta em vez de virar zero', Raised);
  Check('EnvOverrideNames lista as LZNEX_*', Length(EnvOverrideNames) >= 10);

  Writeln;
  Writeln('-- logger de console --');

  Logger := TLzNexConsoleLogger.New;
  Logger.LogInfo('linha de info da sonda');
  Logger.LogWarning('linha de aviso da sonda');
  Logger.LogError('select 1', 'erro de exemplo');
  Logger.LogQuery('select * from t where id = ?', TLzNexBindings.One(7), 12);
  Check('o logger nao levanta', True);
  Check('a config aceita o logger',
    TLzNexConfig.New.Logger(Logger).GetLogger = Logger);
  Logger := TLzNexConsoleLogger.New(False);
  Logger.LogQuery('select 2', TLzNexBindings.Empty, 1);
  Check('logger com query desligada nao levanta', True);

  Writeln;
  Writeln('-- registry de migrations --');

  ClearMigrations;
  Check('registry comeca vazio', RegisteredMigrationCount = 0);

  { Registro fora de ordem de proposito: a ordem final e por Id. }
  RegisterMigration(TMigC);
  RegisterMigration(TMigA);
  RegisterMigration(TMigB);
  Check('tres registradas', RegisteredMigrationCount = 3);
  Check('ordenado por Id: 1', RegisteredMigrationAt(0).Id = '20240101090000');
  Check('ordenado por Id: 2', RegisteredMigrationAt(1).Id = '20240202120000');
  Check('ordenado por Id: 3', RegisteredMigrationAt(2).Id = '20240303150000');
  Check('Id derivado do nome', TMigA.Id = '20240101090000');
  Check('MigrationName completo', TMigA.MigrationName = '20240101090000_create_users');
  Check('MigrationIdOf', MigrationIdOf('20240101090000_create_users') = '20240101090000');
  Check('MigrationIdOf sem underscore', MigrationIdOf('semid') = 'semid');
  Check('FindMigrationClass acha',
    FindMigrationClass('20240202120000_create_posts') = TMigB);
  Check('FindMigrationClass devolve nil quando nao acha',
    FindMigrationClass('nao_existe') = nil);

  Raised := False;
  Msg := '';
  try
    RegisterMigration(TMigDup);
  except
    on E: ELzNexMigration do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('Id duplicado levanta ELzNexMigration', Raised);
  Check('a mensagem mostra as duas migrations envolvidas',
    (Pos('create_users', Msg) > 0) and (Pos('outra_coisa', Msg) > 0));
  Check('a duplicata nao entrou no registry', RegisteredMigrationCount = 3);

  Raised := False;
  try
    RegisteredMigrationAt(99);
  except
    on E: ELzNexMigration do Raised := True;
  end;
  Check('indice fora da faixa levanta', Raised);

  Writeln;
  Writeln('-- fonte de migrations em codigo --');

  CodeSrc := TLzNexCodeMigrationSource.New;
  Check('SourceName da fonte de codigo', CodeSrc.SourceName = 'code');
  Items := CodeSrc.All;
  Check('a fonte devolve as tres', Length(Items) = 3);
  Check('a fonte devolve ordenado por Id',
    (Items[0].Id = '20240101090000') and (Items[2].Id = '20240303150000'));
  Check('Name pela interface', Items[0].Name = '20240101090000_create_users');
  Check('UseTransaction default True', Items[0].UseTransaction);
  Check('UseTransaction sobrescrito para False', not Items[2].UseTransaction);

  Writeln;
  Writeln('-- splitter de SQL --');

  Parts := SplitSqlStatements(SQL_MULTI);
  Check('tres comandos', Length(Parts) = 3);
  Check('o primeiro e o create', Pos('create table a', Parts[0]) > 0);
  Check('ponto e virgula dentro de literal nao quebra',
    Pos('ponto; e virgula', Parts[0]) > 0);
  Check('o segundo e o insert', Pos('insert into a', Parts[1]) > 0);
  Check('literal do insert inteiro', Pos('a;b', Parts[1]) > 0);
  Check('comentario de cerquilha nao vira comando',
    Pos('update a set', Parts[2]) > 0);
  { O ';' solitario na ultima linha nao pode gerar um quarto comando. }
  Check('o separador nao fica no fim do comando',
    Parts[2][Length(Parts[2])] <> ';');
  Check('script vazio da lista vazia', Length(SplitSqlStatements('   ')) = 0);
  Check('script so com comentario da lista vazia',
    Length(SplitSqlStatements('-- nada aqui' + sLineBreak)) = 0);
  Check('comando unico sem ponto e virgula',
    Length(SplitSqlStatements('select 1')) = 1);
  Parts := SplitSqlStatements(
    '-- lznex:nosplit' + sLineBreak +
    'create procedure p() begin select 1; select 2; end');
  Check('a marca nosplit mantem o arquivo inteiro', Length(Parts) = 1);

  Raised := False;
  try
    SplitSqlStatements('select ''aberto');
  except
    on E: ELzNexMigration do Raised := True;
  end;
  Check('literal aberto levanta em vez de executar torto', Raised);

  Writeln;
  Writeln('-- fonte de migrations em .sql --');

  ForceDirectories(Dir + '/migrations');
  WriteTextFile(Dir + '/migrations/20240202120000_create_posts.up.sql',
    'create table posts (id int);');
  WriteTextFile(Dir + '/migrations/20240202120000_create_posts.down.sql',
    'drop table posts;');
  WriteTextFile(Dir + '/migrations/20240101090000_create_users.up.sql',
    'create table users (id int);');
  WriteTextFile(Dir + '/migrations/20240101090000_create_users.down.sql',
    'drop table users;');
  { Sem .down.sql: irreversivel. }
  WriteTextFile(Dir + '/migrations/20240303150000_drop_legacy.up.sql',
    'drop table legacy;');
  { Arquivo que nao e migration: a fonte tem que ignorar. }
  WriteTextFile(Dir + '/migrations/leiame.txt', 'nao sou migration');

  Src := TLzNexSqlMigrationSource.New(Dir + '/migrations');
  Check('SourceName da fonte sql', Src.SourceName = 'sql');
  Items := Src.All;
  Check('descobriu tres pares (ignorando o .txt)', Length(Items) = 3);
  Check('sql ordenado por Id: 1', Items[0].Id = '20240101090000');
  Check('sql ordenado por Id: 2', Items[1].Id = '20240202120000');
  Check('sql ordenado por Id: 3', Items[2].Id = '20240303150000');
  Check('Name sem as extensoes',
    Items[1].Name = '20240202120000_create_posts');
  Check('UseTransaction True na fonte sql', Items[0].UseTransaction);
  Check('par up/down resolvido',
    (Items[0] as TLzNexSqlMigration).IsReversible);
  Check('up aponta para o .up.sql',
    Pos('20240101090000_create_users.up.sql',
      (Items[0] as TLzNexSqlMigration).UpPath) > 0);
  Check('down aponta para o .down.sql',
    Pos('20240101090000_create_users.down.sql',
      (Items[0] as TLzNexSqlMigration).DownPath) > 0);
  Check('sem .down.sql a migration e irreversivel',
    not (Items[2] as TLzNexSqlMigration).IsReversible);

  Raised := False;
  Msg := '';
  try
    { ADb nil de proposito: o Down tem que recusar ANTES de tocar na conexao. }
    Items[2].Down(nil);
  except
    on E: ELzNexMigration do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('Down sem .down.sql levanta ELzNexMigration', Raised);
  Check('a mensagem diz que e irreversivel',
    Pos('irreversible', Msg) > 0);

  Raised := False;
  try
    TLzNexSqlMigrationSource.New(Dir + '/nao-existe').All;
  except
    on E: ELzNexMigration do Raised := True;
  end;
  Check('diretorio inexistente levanta', Raised);

  Check('ReadSqlFile le o conteudo',
    Trim(ReadSqlFile(Dir + '/migrations/20240101090000_create_users.up.sql')) =
      'create table users (id int);');

  Writeln;
  Writeln('-- migrator (sem banco) --');

  Stub := TStubDb.Create(TLzNexConfig.New
    .Client('mysql').Host('h').Database('d').MigrationsTable('mig_ctl'));
  Mig := TLzNexMigrator.New(Stub);
  MigObj := Mig as TLzNexMigrator;
  Check('tabela de controle vem da config', MigObj.TableName = 'mig_ctl');
  Check('tabela de lock e a de controle + sufixo',
    MigObj.LockTableName = 'mig_ctl' + LZNEX_MIGRATIONS_LOCK_SUFFIX);
  Check('AddSource devolve o proprio migrator',
    Mig.AddSource(CodeSrc) = Mig);

  Raised := False;
  Msg := '';
  try
    TLzNexMigrator.New(Stub).Status;
  except
    on E: ELzNexMigration do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('migrator sem fonte levanta', Raised);
  Check('a mensagem ensina a chamar AddSource', Pos('AddSource', Msg) > 0);

  Raised := False;
  try
    TLzNexMigrator.New(nil);
  except
    on E: ELzNexMigration do Raised := True;
  end;
  Check('migrator sem facade levanta', Raised);

  { Default da tabela quando a config nao informa. }
  Stub2 := TStubDb.Create(TLzNexConfig.New);
  Check('tabela de controle default',
    (TLzNexMigrator.New(Stub2) as TLzNexMigrator).TableName =
      LZNEX_MIGRATIONS_TABLE);
  Check('CurrentVersion sem linhas devolveria "none"',
    LZNEX_VERSION_NONE = 'none');

  { NewMigrator e o que a facade chama: ja vem com as duas fontes. }
  Mig := NewMigrator(Stub);
  Check('NewMigrator registra codigo + sql',
    (Mig as TLzNexMigrator).SourceCount = 2);
  Check('NewMigrator respeita a tabela da config',
    (Mig as TLzNexMigrator).TableName = 'mig_ctl');
  Stub2 := TStubDb.Create(TLzNexConfig.New.MigrationsDir(''));
  Mig := NewMigrator(Stub2);
  Check('sem diretorio de migrations fica so a fonte de codigo',
    (Mig as TLzNexMigrator).SourceCount = 1);
  { Diretorio inexistente registrado pela facade nao pode quebrar. }
  Check('a fonte sql opcional tolera diretorio ausente',
    Length(TLzNexSqlMigrationSource.NewOptional(Dir + '/nao-existe').All) = 0);

  Writeln;
  Writeln('-- seeds --');

  ClearSeeds;
  Check('registry de seeds comeca vazio', RegisteredSeedCount = 0);
  RegisterSeed(TSeedPosts);
  RegisterSeed(TSeedUsers);
  Check('duas seeds registradas', RegisteredSeedCount = 2);

  Seeder := NewSeeder(Stub);
  Check('NewSeeder devolve um seeder', Seeder <> nil);
  Parts := Seeder.Names;
  Check('ordem alfabetica, nao a de registro',
    (Length(Parts) = 2) and (Parts[0] = '01_users') and (Parts[1] = '02_posts'));

  GSeedLog := '';
  Check('Run devolve quantas rodaram', Seeder.Run = 2);
  Check('rodaram em ordem alfabetica', GSeedLog = 'users;posts;');

  GSeedLog := '';
  Check('RunOne roda uma', Seeder.RunOne('02_posts') = 1);
  Check('RunOne rodou a certa', GSeedLog = 'posts;');

  Raised := False;
  Msg := '';
  try
    Seeder.RunOne('nao_existe');
  except
    on E: ELzNex do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('RunOne de seed inexistente levanta', Raised);
  Check('a mensagem lista as registradas', Pos('01_users', Msg) > 0);

  Raised := False;
  Msg := '';
  RegisterSeed(TSeedBoom);
  try
    Seeder.RunOne('99_boom');
  except
    on E: ELzNex do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Check('seed que falha levanta ELzNex', Raised);
  Check('a mensagem diz QUAL seed falhou', Pos('99_boom', Msg) > 0);
  Check('a mensagem original e preservada',
    Pos('coluna email nao existe', Msg) > 0);

  Raised := False;
  try
    RegisterSeed(TSeedUsers);
  except
    on E: ELzNex do Raised := True;
  end;
  Check('nome de seed duplicado levanta', Raised);

  Writeln;
  Writeln('-- caminhos de erro em laco (caca a objeto orfao) --');

  { Cada iteracao percorre todos os caminhos que levantam. Objeto alocado e
    abandonado por excecao antes de ter dono aparece no heaptrc. }
  Fails := 0;
  for Loop := 1 to 25 do
  begin
    try
      LoadConfigJSON('{ isso nao e json }', '');
    except
      on E: ELzNexConfig do Inc(Fails);
    end;
    try
      LoadConfigJSON('[1, 2, 3]', '');
    except
      on E: ELzNexConfig do Inc(Fails);
    end;
    try
      LoadConfigJSON('{"development":{"client":"mysql"}}', 'staging');
    except
      on E: ELzNexConfig do Inc(Fails);
    end;
    try
      { Pool invalido levanta no meio da montagem a partir do JSON. }
      LoadConfigJSON('{"client":"mysql","pool":{"min":9,"max":2}}', '');
    except
      on E: ELzNexConfig do Inc(Fails);
    end;
    try
      LoadConfigFile(Dir + '/nao-existe.json', '');
    except
      on E: ELzNexConfig do Inc(Fails);
    end;
    try
      TLzNexConfig.New.Validate;
    except
      on E: ELzNexConfig do Inc(Fails);
    end;
    try
      RegisterMigration(TMigDup);
    except
      on E: ELzNexMigration do Inc(Fails);
    end;
    try
      TLzNexSqlMigrationSource.New(Dir + '/nao-existe').All;
    except
      on E: ELzNexMigration do Inc(Fails);
    end;
    try
      SplitSqlStatements('insert into t values (''sem fechar');
    except
      on E: ELzNexMigration do Inc(Fails);
    end;
    try
      SplitSqlStatements('select 1 /* bloco sem fechar');
    except
      on E: ELzNexMigration do Inc(Fails);
    end;
    try
      TLzNexSqlMigrationSource.New(Dir + '/migrations').All[2].Down(nil);
    except
      on E: ELzNexMigration do Inc(Fails);
    end;
    try
      TLzNexMigrator.New(Stub).Status;
    except
      on E: ELzNexMigration do Inc(Fails);
    end;
    try
      NewSeeder(Stub).RunOne('99_boom');
    except
      on E: ELzNex do Inc(Fails);
    end;
    try
      NewSeeder(Stub).RunOne('inexistente');
    except
      on E: ELzNex do Inc(Fails);
    end;
    try
      Stub.Schema;
    except
      on E: ELzNex do Inc(Fails);
    end;
  end;
  Check('todos os caminhos de erro levantaram as 375 vezes', Fails = 375);

  Writeln;
  Writeln('-- sobrescrita por ambiente (processo filho) --');

  { Log de heaptrc proprio para o filho: pai e filho escrevendo no mesmo
    arquivo se sobrepoem e o dump de um esconde o do outro. }
  ChildExit := ExecuteProcess('/bin/sh', ['-c',
    'HEAPTRC="haltonnotreleased log=/tmp/lznex-ht-child.log" ' +
    'LZNEX_HOST=envhost LZNEX_PORT=3310 LZNEX_DATABASE=envdb ' +
    'LZNEX_USER=envuser LZNEX_PASSWORD=envpass ' +
    'LZNEX_MIGRATIONS_TABLE=envmig ' + ParamStr(0) + ' envchild']);
  { Com -gh o filho tambem sai != 0 se vazar, entao isto cobre os dois. }
  Check('o filho com LZNEX_* no ambiente passou', ChildExit = 0);

  Writeln;
  Writeln('assercoes: ', GChecks);
  if ExitCode = 0 then
    Writeln('=== CONFIG/MIGRATION/SEED OK ===')
  else
    Writeln('=== CONFIG/MIGRATION/SEED COM FALHA ===');
  Flush(Output);
end;

var
  GIsChild: Boolean;

begin
  GIsChild := (ParamCount >= 1) and (ParamStr(1) = 'envchild');
  if GIsChild then
    RunEnvChild
  else
    RunProbe;
  Flush(Output);
end.
