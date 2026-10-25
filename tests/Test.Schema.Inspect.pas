unit Test.Schema.Inspect;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Client,
  LzNex.Schema,
  LzNex.Client.MySQL,
  LzNex.Client.Postgres,
  LzNex.Client.SQLite,
  LzNex.Client.Firebird;

type

  { SQL de inspecao e DDL de full text, por dialeto, sem banco. Cada teste
    compara o texto gerado e as bindings, igual aos testes de HasTableSQL
    e HasColumnSQL que ja existiam. }
  TSchemaInspectTestCase = class(TTestCase)
  protected
    function BindsOf(const AFragment: TLzNexFragment): string;
    function Cols(const ANames: array of string): TLzNexValues;
  end;

  TMySQLInspectTest = class(TSchemaInspectTestCase)
  protected
    FClient: ILzNexClient;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TablesSQLScopesToCurrentDatabase;
    procedure TablesSQLAcceptsAnExplicitSchema;
    procedure ColumnsSQLOrdersByDeclarationPosition;
    procedure HasIndexSQLUsesInformationSchemaStatistics;
    procedure FullTextIndexIsAnAlterTableAddFulltextIndex;
  end;

  TPostgresInspectTest = class(TSchemaInspectTestCase)
  protected
    FClient: ILzNexClient;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TablesSQLDefaultsToPublicSchema;
    procedure ColumnsSQLAcceptsAnExplicitSchema;
    procedure HasIndexSQLUsesPgCatalog;
    procedure FullTextIndexIsAGinOnToTsvector;
  end;

  TSQLiteInspectTest = class(TSchemaInspectTestCase)
  protected
    FClient: ILzNexClient;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TablesSQLReadsSqliteMasterExcludingInternalTables;
    procedure ColumnsSQLUsesPragmaTableInfo;
    procedure HasIndexSQLUsesPragmaIndexListAndInfo;
  end;

  TFirebirdInspectTest = class(TSchemaInspectTestCase)
  protected
    FClient: ILzNexClient;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TablesSQLExcludesSystemTablesAndViews;
    procedure ColumnsSQLOrdersByFieldPosition;
    procedure HasIndexSQLUsesRdbIndices;
  end;

implementation

function TSchemaInspectTestCase.BindsOf(const AFragment: TLzNexFragment): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to AFragment.Bindings.Count - 1 do
  begin
    if I > 0 then
      Result := Result + '|';
    Result := Result + AFragment.Bindings.Items(I).AsString;
  end;
end;

function TSchemaInspectTestCase.Cols(const ANames: array of string): TLzNexValues;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ANames));
  for I := 0 to High(ANames) do
    Result[I] := TLzNexValue.Identifier(ANames[I]);
end;

procedure TMySQLInspectTest.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('mysql');
end;

procedure TMySQLInspectTest.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

procedure TMySQLInspectTest.TablesSQLScopesToCurrentDatabase;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.TablesSQL('');
  AssertEquals(
    'select table_name from information_schema.tables where table_type = ''BASE TABLE'' ' +
    'and table_schema = database() order by table_name', F.Text);
  AssertEquals('bindings', '', BindsOf(F));
end;

procedure TMySQLInspectTest.TablesSQLAcceptsAnExplicitSchema;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.TablesSQL('other_db');
  AssertEquals(
    'select table_name from information_schema.tables where table_type = ''BASE TABLE'' ' +
    'and table_schema = ? order by table_name', F.Text);
  AssertEquals('bindings', 'other_db', BindsOf(F));
end;

procedure TMySQLInspectTest.ColumnsSQLOrdersByDeclarationPosition;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.ColumnsSQL('users', '');
  AssertEquals(
    'select column_name from information_schema.columns where table_name = ? ' +
    'and table_schema = database() order by ordinal_position', F.Text);
  AssertEquals('bindings', 'users', BindsOf(F));
end;

procedure TMySQLInspectTest.HasIndexSQLUsesInformationSchemaStatistics;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.HasIndexSQL('users', Cols(['email']), '');
  AssertEquals(
    'select count(*) from (select i.indexname from (' +
    'select s.index_name as indexname, s.column_name from information_schema.statistics s ' +
    'where s.table_name = ? and s.table_schema = database()) i group by i.indexname ' +
    'having sum(case when i.column_name in (?) then 1 else 0 end) = ? and count(*) = ?) m',
    F.Text);
  AssertEquals('bindings', 'users|email|1|1', BindsOf(F));
end;

procedure TMySQLInspectTest.FullTextIndexIsAnAlterTableAddFulltextIndex;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  T := NewSchema(nil, FClient).CreateTable('articles');
  T.Increments;
  T.Text('body');
  T.FullText(['body']);
  P := T.ToSQL;
  AssertEquals('post statement count', 1, Length(P.Post));
  AssertEquals(
    'alter table `articles` add fulltext index `articles_body_fulltext`(`body`)',
    P.Post[0].Text);
end;

procedure TPostgresInspectTest.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('postgres');
end;

procedure TPostgresInspectTest.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

procedure TPostgresInspectTest.TablesSQLDefaultsToPublicSchema;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.TablesSQL('');
  AssertEquals(
    'select table_name from information_schema.tables where table_type = ''BASE TABLE'' ' +
    'and table_schema = ? order by table_name', F.Text);
  AssertEquals('bindings', 'public', BindsOf(F));
end;

procedure TPostgresInspectTest.ColumnsSQLAcceptsAnExplicitSchema;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.ColumnsSQL('users', 'reporting');
  AssertEquals(
    'select column_name from information_schema.columns ' +
    'where table_name = ? and table_schema = ? order by ordinal_position', F.Text);
  AssertEquals('bindings', 'users|reporting', BindsOf(F));
end;

procedure TPostgresInspectTest.HasIndexSQLUsesPgCatalog;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.HasIndexSQL('users', Cols(['email']), '');
  AssertEquals(
    'select count(*) from (select i.indexname from (' +
    'select ci.relname as indexname, a.attname as column_name from pg_index pi ' +
    'join pg_class ct on ct.oid = pi.indrelid ' +
    'join pg_class ci on ci.oid = pi.indexrelid ' +
    'join pg_namespace ns on ns.oid = ct.relnamespace ' +
    'join pg_attribute a on a.attrelid = pi.indrelid and a.attnum = any(pi.indkey) ' +
    'where ct.relname = ? and ns.nspname = ?) i group by i.indexname ' +
    'having sum(case when i.column_name in (?) then 1 else 0 end) = ? and count(*) = ?) m',
    F.Text);
  AssertEquals('bindings', 'users|public|email|1|1', BindsOf(F));
end;

procedure TPostgresInspectTest.FullTextIndexIsAGinOnToTsvector;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  { A expressao precisa ser igual, token a token, a que o WhereFullText gera
    no compilador de queries, senao o indice nasce e nunca e usado. }
  T := NewSchema(nil, FClient).CreateTable('articles');
  T.Increments;
  T.Text('title');
  T.Text('body');
  T.FullText(['title', 'body']);
  P := T.ToSQL;
  AssertEquals('post statement count', 1, Length(P.Post));
  AssertEquals(
    'create index "articles_title_body_fulltext" on "articles" using gin ' +
    '(to_tsvector(''simple'', coalesce("title",'''') || '' '' || coalesce("body",'''')))',
    P.Post[0].Text);
end;

procedure TSQLiteInspectTest.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('sqlite');
end;

procedure TSQLiteInspectTest.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

procedure TSQLiteInspectTest.TablesSQLReadsSqliteMasterExcludingInternalTables;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.TablesSQL('');
  AssertEquals(
    'select name from sqlite_master where type = ''table'' and ' +
    'name not like ''sqlite\_%'' escape ''\'' order by name', F.Text);
  AssertEquals('bindings', '', BindsOf(F));
end;

procedure TSQLiteInspectTest.ColumnsSQLUsesPragmaTableInfo;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.ColumnsSQL('users', '');
  AssertEquals('select name from pragma_table_info(?) order by cid', F.Text);
  AssertEquals('bindings', 'users', BindsOf(F));
end;

procedure TSQLiteInspectTest.HasIndexSQLUsesPragmaIndexListAndInfo;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.HasIndexSQL('users', Cols(['email']), '');
  AssertEquals(
    'select count(*) from (select i.indexname from (' +
    'select il.name as indexname, ii.name as column_name ' +
    'from pragma_index_list(?) il, pragma_index_info(il.name) ii) i group by i.indexname ' +
    'having sum(case when i.column_name in (?) then 1 else 0 end) = ? and count(*) = ?) m',
    F.Text);
  AssertEquals('bindings', 'users|email|1|1', BindsOf(F));
end;

procedure TFirebirdInspectTest.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('firebird');
end;

procedure TFirebirdInspectTest.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

procedure TFirebirdInspectTest.TablesSQLExcludesSystemTablesAndViews;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.TablesSQL('');
  AssertEquals(
    'select trim(rdb$relation_name) as table_name from rdb$relations ' +
    'where rdb$system_flag = 0 and rdb$view_blr is null order by rdb$relation_name',
    F.Text);
  AssertEquals('bindings', '', BindsOf(F));
end;

procedure TFirebirdInspectTest.ColumnsSQLOrdersByFieldPosition;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.ColumnsSQL('users', '');
  AssertEquals(
    'select trim(rdb$field_name) as column_name from rdb$relation_fields ' +
    'where trim(rdb$relation_name) = ? order by rdb$field_position', F.Text);
  AssertEquals('bindings', 'users', BindsOf(F));
end;

procedure TFirebirdInspectTest.HasIndexSQLUsesRdbIndices;
var
  F: TLzNexFragment;
begin
  F := FClient.NewSchemaCompiler.HasIndexSQL('users', Cols(['email']), '');
  AssertEquals(
    'select count(*) from (select i.indexname from (' +
    'select trim(ix.rdb$index_name) as indexname, trim(seg.rdb$field_name) as column_name ' +
    'from rdb$indices ix join rdb$index_segments seg ' +
    'on seg.rdb$index_name = ix.rdb$index_name where trim(ix.rdb$relation_name) = ?) ' +
    'i group by i.indexname having sum(case when i.column_name in (?) then 1 else 0 end) = ? ' +
    'and count(*) = ?) m',
    F.Text);
  AssertEquals('bindings', 'users|email|1|1', BindsOf(F));
end;

initialization
  RegisterTest('schema', TMySQLInspectTest);
  RegisterTest('schema', TPostgresInspectTest);
  RegisterTest('schema', TSQLiteInspectTest);
  RegisterTest('schema', TFirebirdInspectTest);

end.
