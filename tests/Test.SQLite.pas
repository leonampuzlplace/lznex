unit Test.SQLite;

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
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Client,
  LzNex.Query,
  LzNex.Schema,
  LzNex.Client.MySQL,
  LzNex.Client.SQLite;

type

  TSQLiteTestCase = class(TTestCase)
  protected
    FLite: ILzNexClient;
    FMy: ILzNexClient;
    FAst: TLzNexAst;

    procedure SetUp; override;
    procedure TearDown; override;

    function LiteQuery: ILzNexQuery;
    function LiteSchema: ILzNexSchema;

    procedure FreshAst(const ATable: string);

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertSQL(const AExpected: string; const AQuery: ILzNexQuery);
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
    procedure AssertAst(const AExpectedSQL, AExpectedBinds: string);

    procedure AssertSchemaRaises(const ATable: ILzNexTable;
      const AMessagePart: string);
  end;

  TSQLiteDialectTest = class(TSQLiteTestCase)
  published
    procedure DialectIsRegisteredUnderBothNames;
    procedure DialectNameAndProtocol;
    procedure HasNoReturning;
    procedure SupportsUpsertWithWhere;
    procedure SupportsNullsOrdering;
    procedure DoesNotSupportDistinctOn;
    procedure DdlIsTransactional;
    procedure IdentifierUsesDoubleQuotes;
  end;

  TSQLitePagingTest = class(TSQLiteTestCase)
  published
    procedure LimitAndOffsetAreAnsi;
    procedure OffsetAloneNeedsTheNoLimitTrick;
    procedure LimitInDeleteRaises;
    procedure JoinInUpdateRaises;
  end;

  TSQLiteWriteTest = class(TSQLiteTestCase)
  published
    procedure ConflictIgnoreIsAnsi;
    procedure ConflictMergeUsesExcluded;
    procedure ReturningIsRefusedByTheBuilder;
    procedure TruncateBecomesDelete;
    procedure LockRaises;
    procedure ILikeFallsBackToLike;
  end;

  TSQLiteSchemaTest = class(TSQLiteTestCase)
  published
    procedure IncrementsIsRowidAlias;
    procedure BigIncrementsIsTheSameRowidAlias;
    procedure NullableEmitsNothing;
    procedure CollateIsAnIdentifierNotALiteral;
    procedure EnumBecomesVarcharWithCheck;
    procedure TimestampAndDateTimeKeepTheirNames;
    procedure UniqueGoesInsideCreateTable;
    procedure ForeignKeyGoesInsideCreateTable;
    procedure PlainIndexIsASeparateStatement;
    procedure CommentIsDropped;
    procedure AlterEmitsOneStatementPerAction;
    procedure AddNotNullWithoutDefaultRaises;
    procedure AddNotNullWithDefaultIsFine;
    procedure ChangeColumnRaises;
    procedure UniqueOnExistingTableBecomesAnIndex;
    procedure PrimaryOnExistingTableRaises;
    procedure ForeignOnExistingTableRaises;
    procedure DropIndexWorksForUniqueToo;
    procedure RenameColumnIsAnsi;
    procedure RenameTableIsAnsi;
    procedure DropTableIfExistsIsNative;
    procedure TruncateIsADelete;
    procedure HasTableReadsSqliteMaster;
    procedure HasColumnReadsPragmaTableInfo;
  end;

implementation

function Idents(const ANames: array of string): TLzNexValues;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ANames));
  for I := 0 to High(ANames) do
    Result[I] := TLzNexValue.Identifier(ANames[I]);
end;

function Stmt(const APlan: TLzNexDdlPlan; const AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(APlan.Statements)) then
    Result := '<no statement ' + IntToStr(AIndex) + '>'
  else
    Result := APlan.Statements[AIndex].Text;
end;

function Post(const APlan: TLzNexDdlPlan; const AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(APlan.Post)) then
    Result := '<no post ' + IntToStr(AIndex) + '>'
  else
    Result := APlan.Post[AIndex].Text;
end;

procedure TSQLiteTestCase.SetUp;
begin
  inherited SetUp;
  FLite := CreateClient('sqlite');
  FMy := CreateClient('mysql');
  FAst := nil;
end;

procedure TSQLiteTestCase.TearDown;
begin
  FreeAndNil(FAst);
  FMy := nil;
  FLite := nil;
  inherited TearDown;
end;

function TSQLiteTestCase.LiteQuery: ILzNexQuery;
begin
  Result := NewQuery(FLite);
end;

function TSQLiteTestCase.LiteSchema: ILzNexSchema;
begin
  Result := NewSchema(nil, FLite);
end;

procedure TSQLiteTestCase.FreshAst(const ATable: string);
begin
  FreeAndNil(FAst);
  FAst := TLzNexAst.Create;
  if ATable <> '' then
    FAst.Single.Table := TLzNexValue.Identifier(ATable);
end;

function TSQLiteTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TSQLiteTestCase.AssertSQL(const AExpected: string;
  const AQuery: ILzNexQuery);
begin
  AssertEquals('generated SQL', AExpected, AQuery.ToSQL.Text);
end;

procedure TSQLiteTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TSQLiteTestCase.AssertAst(const AExpectedSQL, AExpectedBinds: string);
var
  Fragment: TLzNexFragment;
begin
  Fragment := FLite.NewCompiler.Compile(FAst);
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TSQLiteTestCase.AssertSchemaRaises(const ATable: ILzNexTable;
  const AMessagePart: string);
var
  Plan: TLzNexDdlPlan;
begin
  try
    Plan := ATable.ToSQL;
    Fail('expected ELzNexSchema, got [' + Stmt(Plan, 0) + ']');
  except
    on E: ELzNexSchema do
      AssertTrue('message should mention "' + AMessagePart + '", got: ' + E.Message,
        Pos(AMessagePart, E.Message) > 0);
  end;
end;

procedure TSQLiteDialectTest.DialectIsRegisteredUnderBothNames;
begin
  AssertTrue('sqlite', IsClientRegistered('sqlite'));
  AssertTrue('sqlite3', IsClientRegistered('sqlite3'));
end;

procedure TSQLiteDialectTest.DialectNameAndProtocol;
begin

  AssertEquals('sqlite', CreateClient('sqlite3').DialectName);
  AssertEquals('sqlite', FLite.ZeosProtocol);
end;

procedure TSQLiteDialectTest.HasNoReturning;
begin

  AssertFalse(FLite.SupportsReturning);
end;

procedure TSQLiteDialectTest.SupportsUpsertWithWhere;
begin
  AssertTrue('sqlite', FLite.SupportsOnConflictWhere);
  AssertFalse('mysql', FMy.SupportsOnConflictWhere);
end;

procedure TSQLiteDialectTest.SupportsNullsOrdering;
begin

  AssertTrue(FLite.SupportsNullsOrdering);
end;

procedure TSQLiteDialectTest.DoesNotSupportDistinctOn;
begin
  AssertFalse(FLite.SupportsDistinctOn);
end;

procedure TSQLiteDialectTest.DdlIsTransactional;
begin
  AssertTrue('sqlite', FLite.DdlIsTransactional);
  AssertFalse('mysql', FMy.DdlIsTransactional);
end;

procedure TSQLiteDialectTest.IdentifierUsesDoubleQuotes;
begin
  AssertSQL('select * from "users"', LiteQuery.Table('users'));
end;

procedure TSQLitePagingTest.LimitAndOffsetAreAnsi;
begin
  AssertQuery('select * from "t" limit ? offset ?', '10|20',
    LiteQuery.Table('t').Limit(10).Offset(20));
end;

procedure TSQLitePagingTest.OffsetAloneNeedsTheNoLimitTrick;
begin

  AssertQuery('select * from "t" limit -1 offset ?', '20',
    LiteQuery.Table('t').Offset(20));
end;

procedure TSQLitePagingTest.LimitInDeleteRaises;
begin
  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Single.LimitValue := 5;
  try
    FLite.NewCompiler.Compile(FAst);
    Fail('expected ELzNexCompile for limit in delete');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TSQLitePagingTest.JoinInUpdateRaises;
begin

  FreshAst('users');
  FAst.Single.Method := qmUpdate;
  FAst.Single.UpdateValues := Vals(['name', 'x']);
  FAst.Add(TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('logs'), ''));
  try
    FLite.NewCompiler.Compile(FAst);
    Fail('expected ELzNexCompile for join in update');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TSQLiteWriteTest.ConflictIgnoreIsAnsi;
begin

  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caIgnore;
  FAst.Single.ConflictTargets := Idents(['email']);
  AssertAst('insert into "users" ("name") values (?) ' +
    'on conflict ("email") do nothing', 'ana');
end;

procedure TSQLiteWriteTest.ConflictMergeUsesExcluded;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['email']);
  AssertAst('insert into "users" ("name", "age") values (?, ?) ' +
    'on conflict ("email") do update set "name" = excluded."name", ' +
    '"age" = excluded."age"', 'ana|30');
end;

procedure TSQLiteWriteTest.ReturningIsRefusedByTheBuilder;
begin
  try
    LiteQuery.Table('t').Returning(['id']);
    Fail('expected ELzNexCompile for Returning on sqlite');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TSQLiteWriteTest.TruncateBecomesDelete;
begin

  FreshAst('users');
  FAst.Single.Method := qmTruncate;
  AssertAst('delete from "users"', '');
  AssertEquals('delete from "users"',
    FLite.NewSchemaCompiler.TruncateTableSQL('users').Text);
end;

procedure TSQLiteWriteTest.LockRaises;
begin
  try
    LiteQuery.Table('t').ForUpdate.ToSQL;
    Fail('expected ELzNexCompile for ForUpdate on sqlite');
  except
    on E: ELzNexCompile do
      AssertTrue('message should explain the whole-database lock, got: ' + E.Message,
        Pos('whole database', E.Message) > 0);
  end;
end;

procedure TSQLiteWriteTest.ILikeFallsBackToLike;
begin
  AssertQuery('select * from "t" where "name" like ?', 'ana%',
    LiteQuery.Table('t').WhereILike('name', 'ana%'));
end;

procedure TSQLiteSchemaTest.IncrementsIsRowidAlias;
var
  T: ILzNexTable;
begin
  T := LiteSchema.CreateTable('users');
  T.Increments;
  AssertEquals(
    'create table "users" ("id" integer primary key autoincrement)',
    Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.BigIncrementsIsTheSameRowidAlias;
var
  T: ILzNexTable;
begin

  T := LiteSchema.CreateTable('events');
  T.BigIncrements('uid');
  AssertEquals(
    'create table "events" ("uid" integer primary key autoincrement)',
    Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.NullableEmitsNothing;
var
  T: ILzNexTable;
begin
  T := LiteSchema.CreateTable('c');
  T.Int('hits').Nullable;
  T.Int('shots').NotNull;
  AssertEquals(
    'create table "c" ("hits" integer, "shots" integer not null)',
    Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.CollateIsAnIdentifierNotALiteral;
var
  T: ILzNexTable;
begin

  T := LiteSchema.CreateTable('c');
  T.Str('name', 50).Collate('NOCASE');
  AssertEquals('create table "c" ("name" varchar(50) collate NOCASE)',
    Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.EnumBecomesVarcharWithCheck;
var
  T: ILzNexTable;
begin
  T := LiteSchema.CreateTable('o');
  T.Enum('status', ['new', 'done']);
  AssertEquals(
    'create table "o" ("status" varchar(255) ' +
    'check ("status" in (''new'', ''done'')))', Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.TimestampAndDateTimeKeepTheirNames;
var
  T: ILzNexTable;
begin

  T := LiteSchema.CreateTable('d');
  T.Timestamp('created_at');
  T.DateTime('seen_at');
  T.Date('birthday');
  T.Time('alarm');
  AssertEquals(
    'create table "d" ("created_at" timestamp, "seen_at" datetime, ' +
    '"birthday" date, "alarm" time)', Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.UniqueGoesInsideCreateTable;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin

  T := LiteSchema.CreateTable('users');
  T.Increments;
  T.Str('email', 191).NotNull.Unique;
  P := T.ToSQL;
  AssertEquals(
    'create table "users" ("id" integer primary key autoincrement, ' +
    '"email" varchar(191) not null, ' +
    'constraint "users_email_unique" unique ("email"))', Stmt(P, 0));
  AssertEquals('no post statement', 0, Length(P.Post));
end;

procedure TSQLiteSchemaTest.ForeignKeyGoesInsideCreateTable;
var
  T: ILzNexTable;
begin
  T := LiteSchema.CreateTable('posts');
  T.Increments;
  T.Int('user_id').NotNull.References('users.id').OnDelete('cascade');
  AssertEquals(
    'create table "posts" ("id" integer primary key autoincrement, ' +
    '"user_id" integer not null, ' +
    'constraint "posts_user_id_foreign" foreign key ("user_id") ' +
    'references "users" ("id") on delete cascade)', Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.PlainIndexIsASeparateStatement;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  T := LiteSchema.CreateTable('users');
  T.Increments;
  T.Int('age');
  T.Index(['age']);
  P := T.ToSQL;
  AssertEquals(
    'create table "users" ("id" integer primary key autoincrement, ' +
    '"age" integer)', Stmt(P, 0));
  AssertEquals('create index "users_age_index" on "users" ("age")', Post(P, 0));
end;

procedure TSQLiteSchemaTest.CommentIsDropped;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin

  T := LiteSchema.CreateTable('users');
  T.Str('email', 191).Comment('login of the user');
  P := T.ToSQL;
  AssertEquals('create table "users" ("email" varchar(191))', Stmt(P, 0));
  AssertEquals('no post statement', 0, Length(P.Post));
end;

procedure TSQLiteSchemaTest.AlterEmitsOneStatementPerAction;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  T := LiteSchema.Table('users');
  T.Str('nick', 50);
  T.Int('age').Nullable;
  T.DropColumn('legacy');
  P := T.ToSQL;
  AssertEquals('statement count', 3, Length(P.Statements));
  AssertEquals('alter table "users" add column "nick" varchar(50)', Stmt(P, 0));
  AssertEquals('alter table "users" add column "age" integer', Stmt(P, 1));
  AssertEquals('alter table "users" drop column "legacy"', Stmt(P, 2));
end;

procedure TSQLiteSchemaTest.AddNotNullWithoutDefaultRaises;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.Int('age').NotNull;
  AssertSchemaRaises(T, 'without a default');
end;

procedure TSQLiteSchemaTest.AddNotNullWithDefaultIsFine;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.Int('age').NotNull.Default_(0);
  AssertEquals(
    'alter table "users" add column "age" integer not null default 0',
    Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.ChangeColumnRaises;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.Int('age').NotNull.Change;
  AssertSchemaRaises(T, 'no ALTER COLUMN');
end;

procedure TSQLiteSchemaTest.UniqueOnExistingTableBecomesAnIndex;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.Unique(['email']);
  AssertEquals(
    'create unique index "users_email_unique" on "users" ("email")',
    Post(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.PrimaryOnExistingTableRaises;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.Primary(['id']);
  AssertSchemaRaises(T, 'ADD CONSTRAINT');
end;

procedure TSQLiteSchemaTest.ForeignOnExistingTableRaises;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('posts');
  T.Int('user_id').Nullable.References('users.id');
  AssertSchemaRaises(T, 'ADD CONSTRAINT');
end;

procedure TSQLiteSchemaTest.DropIndexWorksForUniqueToo;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.DropUnique(['email']);
  AssertEquals('drop index "users_email_unique"', Post(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.RenameColumnIsAnsi;
var
  T: ILzNexTable;
begin
  T := LiteSchema.Table('users');
  T.RenameColumn('nick', 'nickname');
  AssertEquals(
    'alter table "users" rename column "nick" to "nickname"', Stmt(T.ToSQL, 0));
end;

procedure TSQLiteSchemaTest.RenameTableIsAnsi;
begin
  AssertEquals('alter table "a" rename to "b"',
    FLite.NewSchemaCompiler.RenameTableSQL('a', 'b').Text);
end;

procedure TSQLiteSchemaTest.DropTableIfExistsIsNative;
begin
  AssertEquals('drop table if exists "users"',
    FLite.NewSchemaCompiler.DropTableSQL('users', True).Text);
end;

procedure TSQLiteSchemaTest.TruncateIsADelete;
begin
  AssertEquals('delete from "users"',
    FLite.NewSchemaCompiler.TruncateTableSQL('users').Text);
end;

procedure TSQLiteSchemaTest.HasTableReadsSqliteMaster;
var
  F: TLzNexFragment;
begin
  F := FLite.NewSchemaCompiler.HasTableSQL('users', '');
  AssertEquals(
    'select count(*) from sqlite_master ' +
    'where type in (''table'', ''view'') and name = ?', F.Text);
  AssertEquals('bindings', 'users', BindsOf(F));
end;

procedure TSQLiteSchemaTest.HasColumnReadsPragmaTableInfo;
var
  F: TLzNexFragment;
begin
  F := FLite.NewSchemaCompiler.HasColumnSQL('users', 'email', '');
  AssertEquals(
    'select count(*) from pragma_table_info(?) where name = ?', F.Text);
  AssertEquals('bindings', 'users|email', BindsOf(F));
end;

initialization
  RegisterTest('sqlite', TSQLiteDialectTest);
  RegisterTest('sqlite', TSQLitePagingTest);
  RegisterTest('sqlite', TSQLiteWriteTest);
  RegisterTest('sqlite', TSQLiteSchemaTest);

end.
