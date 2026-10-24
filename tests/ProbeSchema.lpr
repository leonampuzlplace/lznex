program ProbeSchema;

{$MODE DELPHI}{$H+}

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Client,
  LzNex.Exceptions,
  LzNex.Schema,
  LzNex.Schema.Compiler,
  LzNex.Schema.MySQL;

type
  TProbeMySQLClient = class(TLzNexClientBase)
  protected
    function QuoteChar: string; override;
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;
    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

function TProbeMySQLClient.QuoteChar: string;
begin
  Result := '`';
end;

function TProbeMySQLClient.DialectName: string;
begin
  Result := 'mysql';
end;

function TProbeMySQLClient.ZeosProtocol: string;
begin
  Result := 'mysql';
end;

function TProbeMySQLClient.NewCompiler: ILzNexCompiler;
begin
  Result := nil;
end;

function TProbeMySQLClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := NewMySQLSchemaCompiler(Self);
end;

var
  GChecks: Integer = 0;

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

procedure CheckEq(const AWhat, AExpected, AActual: string);
begin
  Inc(GChecks);
  if AExpected = AActual then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    Writeln('        esperado: ', AExpected);
    Writeln('        obtido  : ', AActual);
    ExitCode := 1;
  end;
end;

function Has(const AHay, ANeedle: string): Boolean;
begin
  Result := Pos(ANeedle, AHay) > 0;
end;

function Stmt(const APlan: TLzNexDdlPlan; const AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(APlan.Statements)) then
    Result := '<sem statement ' + IntToStr(AIndex) + '>'
  else
    Result := APlan.Statements[AIndex].Text;
end;

function Post(const APlan: TLzNexDdlPlan; const AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(APlan.Post)) then
    Result := '<sem post ' + IntToStr(AIndex) + '>'
  else
    Result := APlan.Post[AIndex].Text;
end;

const

  LOOPS = 200;

var
  Cli: ILzNexClient;
  Sch: ILzNexSchema;
  Cmp: ILzNexSchemaCompiler;
  T, T2: ILzNexTable;
  P, P2: TLzNexDdlPlan;
  S: string;
  F: TLzNexFragment;
  Ok: Boolean;
  I, N: Integer;
begin
  Writeln('=== sonda do schema builder do LzNex ===');

  Cli := TProbeMySQLClient.Create;
  Sch := NewSchema(nil, Cli);
  Cmp := NewMySQLSchemaCompiler(Cli);

  T := Sch.CreateTable('all_types');
  T.TinyInt('c_tiny');
  T.SmallInt('c_small');
  T.Int('c_int');
  T.BigInt('c_big');
  T.Bool('c_bool');
  T.Decimal('c_dec', 10, 4);
  T.Float('c_float');
  T.Double('c_double');
  T.Char_('c_char', 10);
  T.Str('c_str', 191);
  T.Text('c_text');
  T.MediumText('c_mtext');
  T.LongText('c_ltext');
  T.Binary('c_bin', 16);
  T.Binary('c_bin0');
  T.Blob('c_blob');
  T.Date('c_date');
  T.Time('c_time');
  T.DateTime('c_dt');
  T.Timestamp('c_ts');
  T.Json('c_json');
  T.Uuid('c_uuid');
  T.Enum('c_enum', ['a', 'b']);
  T.Specific('c_spec', 'geometry');
  S := Stmt(T.ToSQL, 0);

  Check('create table abre com o nome quotado',
    Copy(S, 1, 26) = 'create table `all_types` (');
  Check('tinyint', Has(S, '`c_tiny` tinyint null'));
  Check('smallint', Has(S, '`c_small` smallint null'));
  Check('int', Has(S, '`c_int` int null'));
  Check('bigint', Has(S, '`c_big` bigint null'));
  Check('boolean vira tinyint(1)', Has(S, '`c_bool` tinyint(1) null'));
  Check('decimal com precisao e escala', Has(S, '`c_dec` decimal(10, 4) null'));
  Check('float', Has(S, '`c_float` float null'));
  Check('double', Has(S, '`c_double` double null'));
  Check('char(n)', Has(S, '`c_char` char(10) null'));
  Check('string vira varchar(n)', Has(S, '`c_str` varchar(191) null'));
  Check('text', Has(S, '`c_text` text null'));
  Check('mediumtext', Has(S, '`c_mtext` mediumtext null'));
  Check('longtext', Has(S, '`c_ltext` longtext null'));
  Check('binary(n) vira varbinary(n)', Has(S, '`c_bin` varbinary(16) null'));
  Check('binary sem tamanho vira blob', Has(S, '`c_bin0` blob null'));
  Check('blob', Has(S, '`c_blob` blob null'));
  Check('date', Has(S, '`c_date` date null'));
  Check('time', Has(S, '`c_time` time null'));
  Check('datetime', Has(S, '`c_dt` datetime null'));
  Check('timestamp', Has(S, '`c_ts` timestamp null'));
  Check('json', Has(S, '`c_json` json null'));
  Check('uuid vira char(36)', Has(S, '`c_uuid` char(36) null'));
  Check('enum lista os itens', Has(S, '`c_enum` enum(''a'', ''b'') null'));
  Check('specific passa o tipo cru', Has(S, '`c_spec` geometry null'));

  T := Sch.CreateTable('inc');
  T.Increments;
  CheckEq('increments vira PK auto_increment',
    'create table `inc` (`id` int unsigned not null auto_increment primary key)',
    Stmt(T.ToSQL, 0));
  Check('increments nao gera comando extra', T.ToSQL.Count = 1);

  T := Sch.CreateTable('binc');
  T.BigIncrements('uid');
  CheckEq('bigIncrements usa bigint unsigned',
    'create table `binc` (`uid` bigint unsigned not null auto_increment primary key)',
    Stmt(T.ToSQL, 0));

  T := Sch.CreateTable('mods');
  T.Int('n').Default_(7).Unsigned.NotNull.Comment('qtd').Collate('utf8mb4_bin').After('id');
  CheckEq('ordem dos modificadores e a do dialeto, nao a de chamada',
    'create table `mods` (`n` int unsigned not null default 7 comment ''qtd'' ' +
    'collate ''utf8mb4_bin'' after `id`)',
    Stmt(T.ToSQL, 0));

  T2 := Sch.CreateTable('mods');
  T2.Int('n').After('id').Collate('utf8mb4_bin').Comment('qtd').NotNull.Unsigned.Default_(7);
  CheckEq('chamar os modificadores invertidos da o MESMO DDL',
    Stmt(T.ToSQL, 0), Stmt(T2.ToSQL, 0));

  T := Sch.CreateTable('nul');
  T.Int('a').Nullable;
  T.Int('b').NotNull;
  CheckEq('nullable/not null sempre explicitos',
    'create table `nul` (`a` int null, `b` int not null)', Stmt(T.ToSQL, 0));

  T := Sch.CreateTable('def');
  T.Str('s', 10).Default_('abc');
  T.Bool('b').Default_(TLzNexValue.FromBoolean(True));
  T.Timestamp('ts').DefaultRaw('CURRENT_TIMESTAMP');
  S := Stmt(T.ToSQL, 0);
  Check('default de string e interpolado e escapado',
    Has(S, '`s` varchar(10) null default ''abc'''));
  Check('default booleano vira 1', Has(S, '`b` tinyint(1) null default 1'));
  Check('defaultRaw entra cru', Has(S, '`ts` timestamp null default CURRENT_TIMESTAMP'));
  Check('DEFAULT nao gera bind nenhum em DDL',
    T.ToSQL.Statements[0].Bindings.Count = 0);

  T := Sch.CreateTable('txt');
  T.Text('t').Default_('x');
  CheckEq('DEFAULT em TEXT e omitido no MySQL',
    'create table `txt` (`t` text null)', Stmt(T.ToSQL, 0));

  T := Sch.CreateTable('ts1');
  T.Timestamps;
  CheckEq('Timestamps usa TIMESTAMP (nao DATETIME) com default',
    'create table `ts1` (`created_at` timestamp not null default CURRENT_TIMESTAMP, ' +
    '`updated_at` timestamp not null default CURRENT_TIMESTAMP)',
    Stmt(T.ToSQL, 0));

  T := Sch.CreateTable('ts2');
  T.Timestamps(False);
  CheckEq('Timestamps(False) sai sem default',
    'create table `ts2` (`created_at` timestamp null, `updated_at` timestamp null)',
    Stmt(T.ToSQL, 0));

  T := Sch.CreateTable('users');
  T.Increments('id');
  T.Str('email', 191).NotNull.Unique;
  T.Str('name').Index;
  P := T.ToSQL;
  CheckEq('create gera um unico create table',
    'create table `users` (`id` int unsigned not null auto_increment primary key, ' +
    '`email` varchar(191) not null, `name` varchar(255) null)',
    Stmt(P, 0));
  Check('create tem exatamente 1 statement', Length(P.Statements) = 1);
  Check('indices vao no Post, um por comando', Length(P.Post) = 2);
  CheckEq('nome automatico do unique',
    'alter table `users` add unique `users_email_unique`(`email`)', Post(P, 0));
  CheckEq('nome automatico do index',
    'alter table `users` add index `users_name_index`(`name`)', Post(P, 1));
  Check('plano total = 3 comandos', P.Count = 3);

  T := Sch.CreateTable('comp');
  T.Int('a').NotNull;
  T.Int('b').NotNull;
  T.Unique(['a', 'b']);
  P := T.ToSQL;
  CheckEq('unique composto une as colunas no nome',
    'alter table `comp` add unique `comp_a_b_unique`(`a`, `b`)', Post(P, 0));

  T := Sch.CreateTable('pk1');
  T.Int('a').NotNull;
  T.Int('b').NotNull;
  T.Primary(['a', 'b']);
  P := T.ToSQL;
  CheckEq('primary key composta vai inline no create',
    'create table `pk1` (`a` int not null, `b` int not null, primary key (`a`, `b`))',
    Stmt(P, 0));
  Check('primary inline nao gera comando extra', Length(P.Post) = 0);

  T := Sch.CreateTable('pk2');
  T.Int('a').NotNull.Primary;
  T.Int('b').NotNull.Primary;
  CheckEq('Primary em duas colunas monta PK composta',
    'create table `pk2` (`a` int not null, `b` int not null, primary key (`a`, `b`))',
    Stmt(T.ToSQL, 0));

  T := Sch.CreateTable('posts');
  T.Increments('id');
  T.Int('user_id').Unsigned.NotNull
    .References('id').InTable('users').OnDelete('cascade').OnUpdate('RESTRICT');
  P := T.ToSQL;
  Check('coluna da FK sai normal no create',
    Has(Stmt(P, 0), '`user_id` int unsigned not null'));
  CheckEq('FK com onDelete/onUpdate e nome automatico',
    'alter table `posts` add constraint `posts_user_id_foreign` foreign key ' +
    '(`user_id`) references `users` (`id`) on delete cascade on update restrict',
    Post(P, 0));

  T := Sch.CreateTable('posts');
  T.Int('user_id').NotNull.References('users.id');
  CheckEq('References aceita tabela.coluna',
    'alter table `posts` add constraint `posts_user_id_foreign` foreign key ' +
    '(`user_id`) references `users` (`id`)', Post(T.ToSQL, 0));

  T := Sch.CreateTable('posts');
  T.Int('user_id').NotNull.References('users.id').ConstraintName('fk_posts_user');
  Check('ConstraintName sobrepoe o nome automatico',
    Has(Post(T.ToSQL, 0), 'add constraint `fk_posts_user` foreign key'));

  T := Sch.CreateTable('opt');
  T.Increments;
  T.Engine('InnoDB').Charset('utf8mb4').TableCollate('utf8mb4_bin').TableComment('oi');
  Check('engine/charset/collate/comment na clausula do create',
    Has(Stmt(T.ToSQL, 0),
      ') engine = InnoDB default character set utf8mb4 collate utf8mb4_bin comment = ''oi'''));

  Sch.WithSchema('outro');
  T := Sch.CreateTable('q');
  T.Int('a');
  Check('WithSchema qualifica a tabela',
    Has(Stmt(T.ToSQL, 0), 'create table `outro`.`q` ('));
  Sch.WithSchema('');

  T := Sch.Table('users');
  T.Str('nick', 50);
  T.Int('age').NotNull;
  T.Text('bio').Change;
  T.DropColumn('old1');
  T.DropColumn('old2');
  T.RenameColumn('a', 'b');
  T.Index(['nick']);
  T.DropIndex(['age']);
  P := T.ToSQL;
  CheckEq('alter agrega TODAS as adicoes num comando',
    'alter table `users` add `nick` varchar(50) null, add `age` int not null',
    Stmt(P, 0));
  CheckEq('alter agrega as alteracoes com modify',
    'alter table `users` modify `bio` text null', Stmt(P, 1));
  CheckEq('alter agrega TODOS os drops num comando',
    'alter table `users` drop `old1`, drop `old2`', Stmt(P, 2));
  CheckEq('rename de coluna fica em comando separado',
    'alter table `users` rename column `a` to `b`', Stmt(P, 3));
  Check('alter tem 4 statements', Length(P.Statements) = 4);
  CheckEq('index do alter vai no Post',
    'alter table `users` add index `users_nick_index`(`nick`)', Post(P, 0));
  CheckEq('drop de index usa drop index no MySQL',
    'alter table `users` drop index `users_age_index`', Post(P, 1));

  T := Sch.Table('users');
  T.DropPrimary;
  T.DropForeign(['user_id']);
  T.DropUnique(['email']);
  P := T.ToSQL;
  CheckEq('drop primary key', 'alter table `users` drop primary key', Post(P, 0));
  CheckEq('drop foreign key usa a sintaxe propria do MySQL',
    'alter table `users` drop foreign key `users_user_id_foreign`', Post(P, 1));
  CheckEq('drop unique cai em drop index',
    'alter table `users` drop index `users_email_unique`', Post(P, 2));
  Check('alter so de indices nao gera statement', Length(P.Statements) = 0);

  T := Sch.Table('users');
  T.Int('n').Comment('contador');
  Check('comentario de coluna e inline no MySQL',
    Has(Stmt(T.ToSQL, 0), 'add `n` int null comment ''contador'''));

  CheckEq('drop table', 'drop table `users`', Cmp.DropTableSQL('users', False).Text);
  CheckEq('drop table if exists', 'drop table if exists `users`',
    Cmp.DropTableSQL('users', True).Text);
  CheckEq('rename table (sintaxe do MySQL)', 'rename table `a` to `b`',
    Cmp.RenameTableSQL('a', 'b').Text);
  CheckEq('truncate', 'truncate `users`', Cmp.TruncateTableSQL('users').Text);

  F := Cmp.HasTableSQL('users', '');
  CheckEq('hasTable sem schema usa database()',
    'select count(*) from information_schema.tables where table_name = ? ' +
    'and table_schema = database()', F.Text);
  Check('hasTable sem schema tem 1 bind', F.Bindings.Count = 1);

  F := Cmp.HasTableSQL('users', 'lznex');
  Check('hasTable com schema binda o schema',
    Has(F.Text, 'and table_schema = ?') and (F.Bindings.Count = 2));

  F := Cmp.HasColumnSQL('users', 'email', '');
  Check('hasColumn consulta information_schema.columns com 2 binds',
    Has(F.Text, 'information_schema.columns') and
    Has(F.Text, 'column_name = ?') and (F.Bindings.Count = 2));

  CheckEq('nome automatico troca . e - por _ e baixa a caixa',
    'my_tbl_a_b_index',
    Cmp.IndexName('My.Tbl', StringsToValues(['A-B']), ixIndex));
  CheckEq('sufixo do nome por tipo', 't_c_unique',
    Cmp.IndexName('t', StringsToValues(['c']), ixUnique));

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.DropColumn('y');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('DropColumn em create levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.Int('a').Change;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('Change em create levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.DropIndex(['a']);
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('DropIndex em create levanta', Ok);

  Ok := False;
  try
    T := Sch.Table('x');
    T.Engine('InnoDB');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('Engine em alter levanta', Ok);

  Ok := False;
  try
    T := Sch.Table('x');
    T.Charset('utf8mb4');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('Charset em alter levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.NotNull;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('modificador sem coluna anterior levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.Unique;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('Unique sem coluna anterior levanta', Ok);

  Ok := False;
  try
    T := Sch.Table('x');
    T.Int('a');
    T.DropColumn('a');
    T.NotNull;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('DropColumn zera a ultima coluna: modificador depois dele levanta', Ok);

  Ok := False;
  try
    T := Sch.Table('x');
    T.RenameColumn('a', 'b');
    T.Nullable;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('RenameColumn zera a ultima coluna', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.InTable('y');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('InTable sem References levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.Int('a').References('id').InTable('y').OnDelete('drop table');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('acao de FK fora da lista levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.Int('a').References('id');
    P2 := T.ToSQL;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('FK sem InTable levanta na compilacao', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    T.Increments;
    T.Execute;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('Execute sem ILzNex levanta (ToSQL continua valendo)', Ok);

  Ok := False;
  try
    Sch.HasTable('x');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('HasTable sem ILzNex levanta', Ok);

  Ok := False;
  try
    Sch.DropTable('x');
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('DropTable sem ILzNex levanta', Ok);

  Ok := False;
  try
    T := Sch.CreateTable('x');
    P2 := T.ToSQL;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('create table sem coluna levanta', Ok);

  Ok := False;
  try
    T := Sch.Table('x');
    P2 := T.ToSQL;
  except
    on E: ELzNexSchema do Ok := True;
  end;
  Check('alter sem nenhuma operacao levanta', Ok);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.References('id');
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('References sem coluna: levanta sem deixar FK orfa', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.DefaultRaw('CURRENT_TIMESTAMP');
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('DefaultRaw sem coluna: levanta sem deixar o raw orfao', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.Unique;
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('Unique sem coluna: levanta sem deixar o indice orfao', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.Int('a').References('id').InTable('y').OnDelete('drop table');
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('acao de FK invalida: levanta com a FK ja no dono', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.Int('a');
      T.Enum('e', []);
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('Enum sem itens: levanta antes de alocar a coluna', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.Int('a').Default_(TLzNexValue.Unset);
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('Default_ com vkUnset: levanta sem sujar a coluna', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.Specific('a', '');
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('Specific sem tipo: levanta antes de alocar a coluna', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.Int('user_id').NotNull.References('id');
      P2 := T.ToSQL;
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('create aborta no Post: plano parcial e descartado inteiro', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.Table('x');
      T.Int('user_id').NotNull.References('id');
      P2 := T.ToSQL;
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('alter aborta depois dos builders: nenhum StringBuilder vaza', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      P2 := T.ToSQL;
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('create sem coluna: levanta dentro do create table', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.CreateTable('x');
      T.DropColumn('y');
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('metodo de alter em create: levanta antes de alocar', N = LOOPS);

  N := 0;
  for I := 1 to LOOPS do
    try
      T := Sch.Table('x');
      T.Engine('InnoDB');
    except
      on E: ELzNexSchema do Inc(N);
    end;
  Check('opcao de tabela em alter: levanta antes de alocar', N = LOOPS);

  for I := 1 to LOOPS do
  begin
    T := Sch.CreateTable('dangling');
    T.Increments('id');
    T.Str('email', 191).NotNull.Unique;
    T.Int('user_id').References('id').InTable('users').OnDelete('cascade');
    T.Timestamps;
    T.Index(['email']);
  end;
  T := nil;
  Check('tabela montada e descartada sem ToSQL nao vaza nada', True);

  Writeln;
  Writeln('asercoes: ', GChecks);
  if ExitCode = 0 then
    Writeln('=== SCHEMA OK ===')
  else
    Writeln('=== SCHEMA COM FALHA ===');
  Flush(Output);
end.
