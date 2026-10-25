unit Test.Firebird;

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
  LzNex.Schema.Firebird,
  LzNex.Client.MySQL,
  LzNex.Client.Firebird;

type

  TFirebirdTestCase = class(TTestCase)
  protected
    FFb: ILzNexClient;
    FMy: ILzNexClient;
    FAst: TLzNexAst;

    procedure SetUp; override;
    procedure TearDown; override;

    function FbQuery: ILzNexQuery;
    function FbSchema: ILzNexSchema;

    procedure FreshAst(const ATable: string);

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertSQL(const AExpected: string; const AQuery: ILzNexQuery);
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
    procedure AssertAst(const AExpectedSQL, AExpectedBinds: string);

    procedure AssertAstRaises(const AMessagePart: string);
  end;

  TFirebirdDialectTest = class(TFirebirdTestCase)
  published
    procedure DialectIsRegistered;
    procedure DialectNameAndProtocol;
    procedure SupportsReturningLikePostgres;
    procedure SupportsNullsOrdering;
    procedure DoesNotSupportDistinctOn;
    procedure DdlIsTransactional;
    procedure StartsInReadCommittedUnlikeTheOthers;
    procedure IdentifierUsesDoubleQuotes;
  end;

  TFirebirdPagingTest = class(TFirebirdTestCase)
  published
    procedure LimitBecomesFetchNext;
    procedure OffsetBecomesOffsetRows;
    procedure OffsetComesBeforeFetch;
    procedure FirstFetchesOneRow;
    procedure LimitInDeleteRaises;
    procedure LimitInUpdateRaises;
    procedure JoinInDeleteRaises;
  end;

  TFirebirdLockTest = class(TFirebirdTestCase)
  published
    procedure ForUpdateBecomesWithLock;
    procedure SkipLockedIsFirebird5Syntax;
    procedure NoWaitRaises;
    procedure ForShareRaises;
  end;

  TFirebirdWriteTest = class(TFirebirdTestCase)
  published
    procedure InsertReturning;
    procedure MergeBecomesUpdateOrInsert;
    procedure MergeWithoutTargetMatchesThePrimaryKey;
    procedure IgnoreRaisesWithAWayOut;
    procedure MergeOfManyRowsRaises;
    procedure MergeWithExplicitValuesRaises;
    procedure TruncateBecomesDelete;
  end;

  TFirebirdExpressionTest = class(TFirebirdTestCase)
  published
    procedure ILikeBecomesUpperOnBothSides;
    procedure LikeStaysLike;
    procedure IntersectRaises;
    procedure ExceptRaises;
    procedure NullsOrderingIsNative;
  end;

  TFirebirdSchemaTest = class(TFirebirdTestCase)
  published
    procedure IncrementsIsIdentity;
    procedure BigIncrementsIsBigintIdentity;
    procedure BooleanIsNative;
    procedure TextVariantsBecomeBlobSubTypeText;
    procedure BinaryWithLengthBecomesOctets;
    procedure BlobIsBinarySubType;
    procedure UuidIsChar36;
    procedure EnumBecomesVarcharWithCheck;
    procedure DefaultComesBeforeNotNull;
    procedure NullableEmitsNothing;
    procedure CollateIsAnIdentifierNotALiteral;
    procedure AlterUsesAddWithoutColumn;
    procedure ChangeEmitsOneActionPerAspect;
    procedure DropColumnHasNoColumnKeyword;
    procedure RenameColumnUsesAlterColumnTo;
    procedure RenameTableRaises;
    procedure DropTableIfExistsUsesExecuteBlock;
    procedure DropTableWithoutIfExistsIsPlain;
    procedure TruncateIsADelete;
    procedure HasTableReadsTheFirebirdCatalog;
    procedure HasColumnReadsTheFirebirdCatalog;
    procedure CommentIsASeparateStatement;
    procedure LongIndexNameIsShortenedToThirtyOne;
    procedure ShortIndexNameIsUntouched;
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

procedure TFirebirdTestCase.SetUp;
begin
  inherited SetUp;
  FFb := CreateClient('firebird');
  FMy := CreateClient('mysql');
  FAst := nil;
end;

procedure TFirebirdTestCase.TearDown;
begin
  FreeAndNil(FAst);
  FMy := nil;
  FFb := nil;
  inherited TearDown;
end;

function TFirebirdTestCase.FbQuery: ILzNexQuery;
begin
  Result := NewQuery(FFb);
end;

function TFirebirdTestCase.FbSchema: ILzNexSchema;
begin
  Result := NewSchema(nil, FFb);
end;

procedure TFirebirdTestCase.FreshAst(const ATable: string);
begin
  FreeAndNil(FAst);
  FAst := TLzNexAst.Create;
  if ATable <> '' then
    FAst.Single.Table := TLzNexValue.Identifier(ATable);
end;

function TFirebirdTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TFirebirdTestCase.AssertSQL(const AExpected: string;
  const AQuery: ILzNexQuery);
begin
  AssertEquals('generated SQL', AExpected, AQuery.ToSQL.Text);
end;

procedure TFirebirdTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TFirebirdTestCase.AssertAst(const AExpectedSQL, AExpectedBinds: string);
var
  Fragment: TLzNexFragment;
begin
  Fragment := FFb.NewCompiler.Compile(FAst);
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TFirebirdTestCase.AssertAstRaises(const AMessagePart: string);
var
  Fragment: TLzNexFragment;
begin
  try
    Fragment := FFb.NewCompiler.Compile(FAst);
    Fail('expected ELzNexCompile, got [' + Fragment.Text + ']');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "' + AMessagePart + '", got: ' + E.Message,
        Pos(AMessagePart, E.Message) > 0);
  end;
end;

procedure TFirebirdDialectTest.DialectIsRegistered;
begin
  AssertTrue('firebird', IsClientRegistered('firebird'));
end;

procedure TFirebirdDialectTest.DialectNameAndProtocol;
begin
  AssertEquals('firebird', FFb.DialectName);

  AssertEquals('firebird', FFb.ZeosProtocol);
end;

procedure TFirebirdDialectTest.SupportsReturningLikePostgres;
begin
  AssertTrue('firebird', FFb.SupportsReturning);
  AssertFalse('mysql', FMy.SupportsReturning);
end;

procedure TFirebirdDialectTest.SupportsNullsOrdering;
begin
  AssertTrue(FFb.SupportsNullsOrdering);
end;

procedure TFirebirdDialectTest.DoesNotSupportDistinctOn;
begin
  AssertFalse(FFb.SupportsDistinctOn);
end;

procedure TFirebirdDialectTest.DdlIsTransactional;
begin

  AssertTrue('firebird', FFb.DdlIsTransactional);
  AssertFalse('mysql', FMy.DdlIsTransactional);
end;

procedure TFirebirdDialectTest.StartsInReadCommittedUnlikeTheOthers;
begin
  { O default do servidor e snapshot, que num pool aparece como leitura velha. }
  AssertTrue('firebird', FFb.DefaultIsolation = ilReadCommitted);
  AssertTrue('mysql', FMy.DefaultIsolation = ilDefault);
end;

procedure TFirebirdDialectTest.IdentifierUsesDoubleQuotes;
begin
  AssertSQL('select * from "users"', FbQuery.Table('users'));
  AssertEquals('"we""ird"', FFb.WrapIdentifier('we"ird'));
end;

procedure TFirebirdPagingTest.LimitBecomesFetchNext;
begin
  AssertQuery('select * from "t" fetch next ? rows only', '10',
    FbQuery.Table('t').Limit(10));
end;

procedure TFirebirdPagingTest.OffsetBecomesOffsetRows;
begin

  AssertQuery('select * from "t" offset ? rows', '20',
    FbQuery.Table('t').Offset(20));
end;

procedure TFirebirdPagingTest.OffsetComesBeforeFetch;
begin
  AssertQuery(
    'select * from "t" order by "id" asc offset ? rows fetch next ? rows only',
    '20|10', FbQuery.Table('t').OrderBy('id').Limit(10).Offset(20));
end;

procedure TFirebirdPagingTest.FirstFetchesOneRow;
begin
  FreshAst('t');
  FAst.Single.Method := qmFirst;
  AssertAst('select * from "t" fetch next ? rows only', '1');
end;

procedure TFirebirdPagingTest.LimitInDeleteRaises;
begin
  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Single.LimitValue := 5;
  AssertAstRaises('limit');
end;

procedure TFirebirdPagingTest.LimitInUpdateRaises;
begin

  FreshAst('users');
  FAst.Single.Method := qmUpdate;
  FAst.Single.UpdateValues := Vals(['name', 'x']);
  FAst.Single.LimitValue := 5;
  AssertAstRaises('limit');
end;

procedure TFirebirdPagingTest.JoinInDeleteRaises;
begin

  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Add(TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('logs'), ''));
  AssertAstRaises('join');
end;

procedure TFirebirdLockTest.ForUpdateBecomesWithLock;
begin
  AssertSQL('select * from "t" with lock', FbQuery.Table('t').ForUpdate);
end;

procedure TFirebirdLockTest.SkipLockedIsFirebird5Syntax;
begin

  AssertSQL('select * from "t" with lock skip locked',
    FbQuery.Table('t').ForUpdate.SkipLocked);
end;

procedure TFirebirdLockTest.NoWaitRaises;
begin
  try
    FbQuery.Table('t').ForUpdate.NoWait.ToSQL;
    Fail('expected ELzNexCompile for NoWait on firebird');
  except
    on E: ELzNexCompile do
      AssertTrue('message should point at the transaction, got: ' + E.Message,
        Pos('transaction', E.Message) > 0);
  end;
end;

procedure TFirebirdLockTest.ForShareRaises;
begin
  try
    FbQuery.Table('t').ForShare.ToSQL;
    Fail('expected ELzNexCompile for ForShare on firebird');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TFirebirdWriteTest.InsertReturning;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Returning := Idents(['id']);
  AssertAst('insert into "users" ("name") values (?) returning "id"', 'ana');
end;

procedure TFirebirdWriteTest.MergeBecomesUpdateOrInsert;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana', 'email', 'a@b.c']);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['email']);
  AssertAst('update or insert into "users" ("name", "email") values (?, ?) ' +
    'matching ("email")', 'ana|a@b.c');
end;

procedure TFirebirdWriteTest.MergeWithoutTargetMatchesThePrimaryKey;
begin
  { No PostgreSQL isso levanta, porque o ON CONFLICT exige a coluna. O
    UPDATE OR INSERT sem MATCHING casa pela chave primaria. }
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['id', 1, 'name', 'ana']);
  FAst.Single.Conflict := caMerge;
  AssertAst('update or insert into "users" ("id", "name") values (?, ?)',
    '1|ana');
end;

procedure TFirebirdWriteTest.IgnoreRaisesWithAWayOut;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caIgnore;
  AssertAstRaises('Merge');
end;

procedure TFirebirdWriteTest.MergeOfManyRowsRaises;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 2);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.InsertRows[1] := Vals(['name', 'bia']);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['name']);
  AssertAstRaises('single row');
end;

procedure TFirebirdWriteTest.MergeWithExplicitValuesRaises;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['email']);
  FAst.Single.ConflictMerge := Vals(['name', 'fixed']);
  AssertAstRaises('every column');
end;

procedure TFirebirdWriteTest.TruncateBecomesDelete;
begin

  FreshAst('users');
  FAst.Single.Method := qmTruncate;
  AssertAst('delete from "users"', '');
  AssertEquals('delete from "users"',
    FFb.NewSchemaCompiler.TruncateTableSQL('users').Text);
end;

procedure TFirebirdExpressionTest.ILikeBecomesUpperOnBothSides;
begin

  AssertQuery('select * from "t" where upper("name") like upper(?)', 'ana%',
    FbQuery.Table('t').WhereILike('name', 'ana%'));
end;

procedure TFirebirdExpressionTest.LikeStaysLike;
begin
  AssertQuery('select * from "t" where "name" like ?', 'ana%',
    FbQuery.Table('t').WhereLike('name', 'ana%'));
  AssertQuery('select * from "t" where "name" not like ?', 'ana%',
    FbQuery.Table('t').WhereNotLike('name', 'ana%'));
end;

procedure TFirebirdExpressionTest.IntersectRaises;
begin
  try
    FbQuery.Table('a').Intersect(FbQuery.Table('b')).ToSQL;
    Fail('expected ELzNexCompile for INTERSECT on firebird');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TFirebirdExpressionTest.ExceptRaises;
begin
  try
    FbQuery.Table('a').Except_(FbQuery.Table('b')).ToSQL;
    Fail('expected ELzNexCompile for EXCEPT on firebird');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TFirebirdExpressionTest.NullsOrderingIsNative;
begin
  AssertSQL('select * from "t" order by "name" asc nulls last',
    FbQuery.Table('t').OrderBy('name', odAsc, nlLast));
end;

procedure TFirebirdSchemaTest.IncrementsIsIdentity;
var
  T: ILzNexTable;
begin
  T := FbSchema.CreateTable('users');
  T.Increments;
  AssertEquals(
    'create table "users" ("id" integer generated by default as identity ' +
    'primary key)', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.BigIncrementsIsBigintIdentity;
var
  T: ILzNexTable;
begin
  T := FbSchema.CreateTable('events');
  T.BigIncrements('uid');
  AssertEquals(
    'create table "events" ("uid" bigint generated by default as identity ' +
    'primary key)', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.BooleanIsNative;
var
  T: ILzNexTable;
begin

  T := FbSchema.CreateTable('f');
  T.Bool('active').Default_(True);
  AssertEquals('create table "f" ("active" boolean default true)',
    Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.TextVariantsBecomeBlobSubTypeText;
var
  T: ILzNexTable;
begin
  T := FbSchema.CreateTable('d');
  T.Text('a');
  T.LongText('b');
  T.Json('c');
  AssertEquals(
    'create table "d" ("a" blob sub_type text, "b" blob sub_type text, ' +
    '"c" blob sub_type text)', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.BinaryWithLengthBecomesOctets;
var
  T: ILzNexTable;
begin

  T := FbSchema.CreateTable('files');
  T.Binary('sig', 16);
  AssertEquals(
    'create table "files" ("sig" varchar(16) character set octets)',
    Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.BlobIsBinarySubType;
var
  T: ILzNexTable;
begin
  T := FbSchema.CreateTable('files');
  T.Blob('payload');
  AssertEquals('create table "files" ("payload" blob sub_type binary)',
    Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.UuidIsChar36;
var
  T: ILzNexTable;
begin
  T := FbSchema.CreateTable('k');
  T.Uuid('id');
  AssertEquals('create table "k" ("id" char(36))', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.EnumBecomesVarcharWithCheck;
var
  T: ILzNexTable;
begin
  T := FbSchema.CreateTable('o');
  T.Enum('status', ['new', 'done']);
  AssertEquals(
    'create table "o" ("status" varchar(255) ' +
    'check ("status" in (''new'', ''done'')))', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.DefaultComesBeforeNotNull;
var
  T: ILzNexTable;
begin
  { No Firebird a ordem e obrigatoria: "not null default 0" e erro de sintaxe. }
  T := FbSchema.CreateTable('c');
  T.Int('hits').NotNull.Default_(0);
  AssertEquals('create table "c" ("hits" integer default 0 not null)',
    Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.NullableEmitsNothing;
var
  T: ILzNexTable;
begin

  T := FbSchema.CreateTable('c');
  T.Int('hits').Nullable;
  AssertEquals('create table "c" ("hits" integer)', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.CollateIsAnIdentifierNotALiteral;
var
  T: ILzNexTable;
begin

  T := FbSchema.CreateTable('c');
  T.Str('name', 50).NotNull.Collate('UNICODE_CI');
  AssertEquals(
    'create table "c" ("name" varchar(50) not null collate UNICODE_CI)',
    Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.AlterUsesAddWithoutColumn;
var
  T: ILzNexTable;
begin

  T := FbSchema.Table('users');
  T.Str('nick', 50);
  T.Int('age').NotNull.Default_(0);
  AssertEquals(
    'alter table "users" add "nick" varchar(50), ' +
    'add "age" integer default 0 not null', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.ChangeEmitsOneActionPerAspect;
var
  T: ILzNexTable;
begin
  T := FbSchema.Table('users');
  T.Int('hits').Nullable.Default_(0).Change;
  AssertEquals(
    'alter table "users" alter column "hits" type integer, ' +
    'alter column "hits" drop not null, alter column "hits" set default 0',
    Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.DropColumnHasNoColumnKeyword;
var
  T: ILzNexTable;
begin
  T := FbSchema.Table('users');
  T.DropColumn('legacy');
  AssertEquals('alter table "users" drop "legacy"', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.RenameColumnUsesAlterColumnTo;
var
  T: ILzNexTable;
begin
  T := FbSchema.Table('users');
  T.RenameColumn('nick', 'nickname');
  AssertEquals(
    'alter table "users" alter column "nick" to "nickname"', Stmt(T.ToSQL, 0));
end;

procedure TFirebirdSchemaTest.RenameTableRaises;
begin

  try
    FFb.NewSchemaCompiler.RenameTableSQL('a', 'b');
    Fail('expected ELzNexSchema for rename table on firebird');
  except
    on E: ELzNexSchema do
      AssertTrue('message should say it has to be recreated, got: ' + E.Message,
        Pos('recreated', E.Message) > 0);
  end;
end;

procedure TFirebirdSchemaTest.DropTableIfExistsUsesExecuteBlock;
begin
  { Nao ha DROP TABLE IF EXISTS no 3 nem no 5, e o plano de DDL manda um
    statement so -- dai o EXECUTE BLOCK. }
  AssertEquals(
    'execute block as begin ' +
    'if (exists(select 1 from rdb$relations where trim(rdb$relation_name) = ' +
    '''users'')) then execute statement ''drop table "users"''; end',
    FFb.NewSchemaCompiler.DropTableSQL('users', True).Text);
end;

procedure TFirebirdSchemaTest.DropTableWithoutIfExistsIsPlain;
begin
  AssertEquals('drop table "users"',
    FFb.NewSchemaCompiler.DropTableSQL('users', False).Text);
end;

procedure TFirebirdSchemaTest.TruncateIsADelete;
begin
  AssertEquals('delete from "users"',
    FFb.NewSchemaCompiler.TruncateTableSQL('users').Text);
end;

procedure TFirebirdSchemaTest.HasTableReadsTheFirebirdCatalog;
var
  F: TLzNexFragment;
begin
  F := FFb.NewSchemaCompiler.HasTableSQL('users', '');
  AssertEquals(
    'select count(*) from rdb$relations where trim(rdb$relation_name) = ?',
    F.Text);
  AssertEquals('bindings', 'users', BindsOf(F));
end;

procedure TFirebirdSchemaTest.HasColumnReadsTheFirebirdCatalog;
var
  F: TLzNexFragment;
begin
  F := FFb.NewSchemaCompiler.HasColumnSQL('users', 'email', '');
  AssertEquals(
    'select count(*) from rdb$relation_fields ' +
    'where trim(rdb$relation_name) = ? and trim(rdb$field_name) = ?', F.Text);
  AssertEquals('bindings', 'users|email', BindsOf(F));
end;

procedure TFirebirdSchemaTest.CommentIsASeparateStatement;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  T := FbSchema.CreateTable('users');
  T.Str('email', 191).NotNull.Comment('login of the user');
  P := T.ToSQL;
  AssertEquals('create table "users" ("email" varchar(191) not null)', Stmt(P, 0));
  AssertEquals('comment on column "users"."email" is ''login of the user''',
    Post(P, 0));
end;

procedure TFirebirdSchemaTest.LongIndexNameIsShortenedToThirtyOne;
var
  First, Second, Again: string;
begin
  { O Firebird 3 para em 31 bytes. O corte leva um hash do nome inteiro no fim,
    para que duas colunas diferentes nao desaguem no mesmo indice. }
  First := FFb.NewSchemaCompiler.IndexName('subscription_invoices',
    Idents(['customer_identifier']), ixIndex);
  Second := FFb.NewSchemaCompiler.IndexName('subscription_invoices',
    Idents(['customer_identification']), ixIndex);
  Again := FFb.NewSchemaCompiler.IndexName('subscription_invoices',
    Idents(['customer_identifier']), ixIndex);

  AssertEquals('cut to the firebird limit', LZNEX_FIREBIRD_MAX_IDENTIFIER,
    Length(First));
  AssertEquals('same input, same name', First, Again);
  AssertFalse('different column, different name: ' + First, First = Second);
  AssertEquals('keeps the readable head', 'subscription_invoices',
    Copy(First, 1, 21));
end;

procedure TFirebirdSchemaTest.ShortIndexNameIsUntouched;
begin
  AssertEquals('users_email_index',
    FFb.NewSchemaCompiler.IndexName('users', Idents(['email']), ixIndex));
end;

initialization
  RegisterTest('firebird', TFirebirdDialectTest);
  RegisterTest('firebird', TFirebirdPagingTest);
  RegisterTest('firebird', TFirebirdLockTest);
  RegisterTest('firebird', TFirebirdWriteTest);
  RegisterTest('firebird', TFirebirdExpressionTest);
  RegisterTest('firebird', TFirebirdSchemaTest);

end.
