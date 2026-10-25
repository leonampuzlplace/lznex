unit Test.Postgres;

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
  LzNex.Client.Postgres;

type

  TPostgresTestCase = class(TTestCase)
  protected
    FPg: ILzNexClient;
    FMy: ILzNexClient;
    FAst: TLzNexAst;

    procedure SetUp; override;
    procedure TearDown; override;

    function PgQuery: ILzNexQuery;
    function MyQuery: ILzNexQuery;
    function PgSchema: ILzNexSchema;
    function MySchema: ILzNexSchema;

    procedure FreshAst(const ATable: string);

    function AstSQL(const AClient: ILzNexClient): TLzNexFragment;

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertSQL(const AExpected: string; const AQuery: ILzNexQuery);
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
    procedure AssertAst(const AExpectedSQL, AExpectedBinds: string;
      const AClient: ILzNexClient);

    procedure AssertAstRaises(const AClient: ILzNexClient;
      const AMessagePart: string);
  end;

  TPostgresDialectTest = class(TPostgresTestCase)
  published
    procedure DialectIsRegisteredUnderBothNames;
    procedure DialectNameIsPostgresql;
    procedure ZeosProtocolIsPostgresql;
    procedure DdlIsTransactionalUnlikeMySQL;
    procedure SupportsReturningUnlikeMySQL;
    procedure SupportsNullsOrderingUnlikeMySQL;
    procedure SupportsDistinctOnUnlikeMySQL;
    procedure SupportsOnConflictWhereUnlikeMySQL;
    procedure SupportsSavepoints;
  end;

  TPostgresIdentifierTest = class(TPostgresTestCase)
  published
    procedure IdentifierUsesDoubleQuotes;
    procedure DoubleQuoteInsideNameIsDoubled;
    procedure QualifiedNameQuotesEverySegment;
    procedure AliasIsQuotedToo;
    procedure StarIsNotQuoted;
  end;

  TPostgresPagingTest = class(TPostgresTestCase)
  published
    procedure LimitAndOffsetAreAnsi;
    procedure OffsetAloneNeedsNoLimitWorkaround;
    procedure MySQLStillNeedsTheLimitWorkaround;
    procedure LimitInDeleteRaises;
    procedure MySQLAcceptsLimitInDelete;
  end;

  TPostgresReturningTest = class(TPostgresTestCase)
  published
    procedure InsertReturning;
    procedure UpdateReturning;
    procedure DeleteReturning;
    procedure ReturningOnMySQLRaises;
    procedure BuilderRefusesReturningOnMySQL;
  end;

  TPostgresUpsertTest = class(TPostgresTestCase)
  published
    procedure ConflictIgnoreWithTarget;
    procedure ConflictIgnoreWithoutTarget;
    procedure MySQLUsesInsertIgnoreInstead;
    procedure ConflictMergeUsesExcluded;
    procedure MySQLUsesOnDuplicateKeyUpdateInstead;
    procedure ConflictMergeWithExplicitValueBinds;
    procedure ConflictMergeWithoutTargetRaises;
  end;

  TPostgresDistinctTest = class(TPostgresTestCase)
  published
    procedure DistinctOnIsEmitted;
    procedure DistinctOnMySQLRaises;
    procedure PlainDistinctWorksOnBoth;
  end;

  TPostgresOrderTest = class(TPostgresTestCase)
  published
    procedure NullsLastIsNative;
    procedure NullsFirstIsNative;
    procedure NullsFirstWithDescending;
    procedure MySQLEmulatesNullsOrdering;
  end;

  TPostgresTruncateTest = class(TPostgresTestCase)
  published
    procedure TruncateRestartsIdentity;
    procedure MySQLTruncateHasNoRestartIdentity;
    procedure SchemaTruncateAlsoRestartsIdentity;
  end;

  TPostgresSchemaTest = class(TPostgresTestCase)
  published
    procedure IncrementsIsSerialPrimaryKey;
    procedure BigIncrementsIsBigserial;
    procedure BinaryIsBytea;
    procedure DoubleIsDoublePrecision;
    procedure BooleanIsBoolean;
    procedure TinyIntCollapsesToSmallint;
    procedure TextVariantsCollapseToText;
    procedure UuidIsNativeType;
    procedure JsonbIsItsOwnType;
    procedure EnumBecomesTextWithCheck;
    procedure ModifierOrderIsNullableCollateThenDefault;
    procedure UnsignedIsIgnored;
    procedure MySQLStillEmitsUnsigned;
    procedure ColumnCommentIsASeparateStatement;
    procedure MySQLKeepsColumnCommentInline;
    procedure AlterUsesAddColumn;
    procedure AlterUsesAlterColumn;
    procedure ChangeEmitsOneActionPerAspect;
    procedure MySQLChangeStaysOneAction;
    procedure BooleanDefaultIsTrueOrFalse;
    procedure MySQLBooleanDefaultIsOneOrZero;
    procedure AlterUsesDropColumn;
    procedure MySQLAlterUsesShortPrefixes;
    procedure RenameTableKeepsAlterTableForm;
    procedure HasTableFallsBackToCurrentSchema;
    procedure HasTableWithExplicitSchemaBinds;
    procedure HasColumnFallsBackToCurrentSchema;
  end;

  TPostgresAbstractionTest = class(TPostgresTestCase)
  published
    procedure SameQueryCompilesDifferentlyPerDialect;
    procedure SameTableCompilesDifferentlyPerDialect;
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

function BasicWhere(const AColumn, AOp: string;
  const AValue: TLzNexValue): TLzNexBasicStmt;
begin
  Result := TLzNexBasicStmt.Create(sgWhere, TLzNexValue.Identifier(AColumn),
    AOp, AValue);
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

procedure TPostgresTestCase.SetUp;
begin
  inherited SetUp;
  FPg := CreateClient('postgresql');
  FMy := CreateClient('mysql');
  FAst := nil;
end;

procedure TPostgresTestCase.TearDown;
begin
  FreeAndNil(FAst);
  FMy := nil;
  FPg := nil;
  inherited TearDown;
end;

function TPostgresTestCase.PgQuery: ILzNexQuery;
begin
  Result := NewQuery(FPg);
end;

function TPostgresTestCase.MyQuery: ILzNexQuery;
begin
  Result := NewQuery(FMy);
end;

function TPostgresTestCase.PgSchema: ILzNexSchema;
begin
  Result := NewSchema(nil, FPg);
end;

function TPostgresTestCase.MySchema: ILzNexSchema;
begin
  Result := NewSchema(nil, FMy);
end;

procedure TPostgresTestCase.FreshAst(const ATable: string);
begin
  FreeAndNil(FAst);
  FAst := TLzNexAst.Create;
  if ATable <> '' then
    FAst.Single.Table := TLzNexValue.Identifier(ATable);
end;

function TPostgresTestCase.AstSQL(const AClient: ILzNexClient): TLzNexFragment;
begin
  Result := AClient.NewCompiler.Compile(FAst);
end;

function TPostgresTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TPostgresTestCase.AssertSQL(const AExpected: string;
  const AQuery: ILzNexQuery);
begin
  AssertEquals('generated SQL', AExpected, AQuery.ToSQL.Text);
end;

procedure TPostgresTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TPostgresTestCase.AssertAst(const AExpectedSQL, AExpectedBinds: string;
  const AClient: ILzNexClient);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AstSQL(AClient);
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TPostgresTestCase.AssertAstRaises(const AClient: ILzNexClient;
  const AMessagePart: string);
var
  Fragment: TLzNexFragment;
begin
  try
    Fragment := AstSQL(AClient);
    Fail('expected ELzNexCompile, got [' + Fragment.Text + ']');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "' + AMessagePart + '", got: ' + E.Message,
        Pos(AMessagePart, E.Message) > 0);
  end;
end;

procedure TPostgresDialectTest.DialectIsRegisteredUnderBothNames;
begin
  AssertTrue('postgresql', IsClientRegistered('postgresql'));
  AssertTrue('postgres', IsClientRegistered('postgres'));
end;

procedure TPostgresDialectTest.DialectNameIsPostgresql;
begin

  AssertEquals('postgresql', CreateClient('postgres').DialectName);
end;

procedure TPostgresDialectTest.ZeosProtocolIsPostgresql;
begin
  AssertEquals('postgresql', FPg.ZeosProtocol);
end;

procedure TPostgresDialectTest.DdlIsTransactionalUnlikeMySQL;
begin

  AssertTrue('postgres', FPg.DdlIsTransactional);
  AssertFalse('mysql', FMy.DdlIsTransactional);
end;

procedure TPostgresDialectTest.SupportsReturningUnlikeMySQL;
begin
  AssertTrue('postgres', FPg.SupportsReturning);
  AssertFalse('mysql', FMy.SupportsReturning);
end;

procedure TPostgresDialectTest.SupportsNullsOrderingUnlikeMySQL;
begin
  AssertTrue('postgres', FPg.SupportsNullsOrdering);
  AssertFalse('mysql', FMy.SupportsNullsOrdering);
end;

procedure TPostgresDialectTest.SupportsDistinctOnUnlikeMySQL;
begin
  AssertTrue('postgres', FPg.SupportsDistinctOn);
  AssertFalse('mysql', FMy.SupportsDistinctOn);
end;

procedure TPostgresDialectTest.SupportsOnConflictWhereUnlikeMySQL;
begin
  AssertTrue('postgres', FPg.SupportsOnConflictWhere);
  AssertFalse('mysql', FMy.SupportsOnConflictWhere);
end;

procedure TPostgresDialectTest.SupportsSavepoints;
begin
  AssertTrue(FPg.SupportsSavepoints);
end;

procedure TPostgresIdentifierTest.IdentifierUsesDoubleQuotes;
begin
  AssertSQL('select * from "users"', PgQuery.Table('users'));
  AssertSQL('select * from `users`', MyQuery.Table('users'));
end;

procedure TPostgresIdentifierTest.DoubleQuoteInsideNameIsDoubled;
begin

  AssertEquals('"we""ird"', FPg.WrapIdentifier('we"ird'));
  AssertSQL('select "we""ird" from "t"',
    PgQuery.Table('t').Select(['we"ird']));
end;

procedure TPostgresIdentifierTest.QualifiedNameQuotesEverySegment;
begin
  AssertSQL('select "users"."id" from "users"',
    PgQuery.Table('users').Select(['users.id']));
end;

procedure TPostgresIdentifierTest.AliasIsQuotedToo;
begin
  AssertSQL('select "name" as "nick" from "users"',
    PgQuery.Table('users').Select(['name as nick']));
end;

procedure TPostgresIdentifierTest.StarIsNotQuoted;
begin
  AssertEquals('*', FPg.WrapIdentifier('*'));
end;

procedure TPostgresPagingTest.LimitAndOffsetAreAnsi;
begin
  AssertQuery('select * from "t" limit ? offset ?', '10|20',
    PgQuery.Table('t').Limit(10).Offset(20));
end;

procedure TPostgresPagingTest.OffsetAloneNeedsNoLimitWorkaround;
begin

  AssertQuery('select * from "t" offset ?', '20',
    PgQuery.Table('t').Offset(20));
end;

procedure TPostgresPagingTest.MySQLStillNeedsTheLimitWorkaround;
begin
  AssertSQL('select * from `t` limit 18446744073709551615 offset ?',
    MyQuery.Table('t').Offset(20));
end;

procedure TPostgresPagingTest.LimitInDeleteRaises;
begin
  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Single.LimitValue := 5;
  AssertAstRaises(FPg, 'limit');
end;

procedure TPostgresPagingTest.MySQLAcceptsLimitInDelete;
begin
  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Single.LimitValue := 5;
  AssertAst('delete from `users` limit ?', '5', FMy);
end;

procedure TPostgresReturningTest.InsertReturning;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Returning := Idents(['id', 'created_at']);
  AssertAst('insert into "users" ("name") values (?) ' +
    'returning "id", "created_at"', 'ana', FPg);
end;

procedure TPostgresReturningTest.UpdateReturning;
begin
  FreshAst('users');
  FAst.Single.Method := qmUpdate;
  FAst.Single.UpdateValues := Vals(['name', 'x']);
  FAst.Add(BasicWhere('id', '=', 7));
  FAst.Single.Returning := Idents(['id']);
  AssertAst('update "users" set "name" = ? where "id" = ? returning "id"',
    'x|7', FPg);
end;

procedure TPostgresReturningTest.DeleteReturning;
begin
  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Add(BasicWhere('id', '=', 7));
  FAst.Single.Returning := Idents(['id']);
  AssertAst('delete from "users" where "id" = ? returning "id"', '7', FPg);
end;

procedure TPostgresReturningTest.ReturningOnMySQLRaises;
begin
  FreshAst('users');
  FAst.Single.Method := qmDelete;
  FAst.Single.Returning := Idents(['id']);
  AssertAstRaises(FMy, 'RETURNING');
end;

procedure TPostgresReturningTest.BuilderRefusesReturningOnMySQL;
begin

  AssertSQL('select * from "t"', PgQuery.Table('t').Returning(['id']));
  try
    MyQuery.Table('t').Returning(['id']);
    Fail('expected ELzNexCompile for Returning on mysql');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TPostgresUpsertTest.ConflictIgnoreWithTarget;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caIgnore;
  FAst.Single.ConflictTargets := Idents(['email']);
  AssertAst('insert into "users" ("name") values (?) ' +
    'on conflict ("email") do nothing', 'ana', FPg);
end;

procedure TPostgresUpsertTest.ConflictIgnoreWithoutTarget;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caIgnore;
  AssertAst('insert into "users" ("name") values (?) on conflict do nothing',
    'ana', FPg);
end;

procedure TPostgresUpsertTest.MySQLUsesInsertIgnoreInstead;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caIgnore;
  FAst.Single.ConflictTargets := Idents(['email']);

  AssertAst('insert ignore into `users` (`name`) values (?)', 'ana', FMy);
end;

procedure TPostgresUpsertTest.ConflictMergeUsesExcluded;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['email']);
  AssertAst('insert into "users" ("name", "age") values (?, ?) ' +
    'on conflict ("email") do update set "name" = excluded."name", ' +
    '"age" = excluded."age"', 'ana|30', FPg);
end;

procedure TPostgresUpsertTest.MySQLUsesOnDuplicateKeyUpdateInstead;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['email']);
  AssertAst('insert into `users` (`name`, `age`) values (?, ?) ' +
    'on duplicate key update `name` = values(`name`), `age` = values(`age`)',
    'ana|30', FMy);
end;

procedure TPostgresUpsertTest.ConflictMergeWithExplicitValueBinds;
begin
  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictTargets := Idents(['email']);
  FAst.Single.ConflictMerge := Vals(['name', 'fixed']);
  AssertAst('insert into "users" ("name") values (?) ' +
    'on conflict ("email") do update set "name" = ?', 'ana|fixed', FPg);
end;

procedure TPostgresUpsertTest.ConflictMergeWithoutTargetRaises;
begin

  FreshAst('users');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Vals(['name', 'ana']);
  FAst.Single.Conflict := caMerge;
  AssertAstRaises(FPg, 'ON CONFLICT');
end;

procedure TPostgresDistinctTest.DistinctOnIsEmitted;
begin
  AssertSQL('select distinct on ("country") "country", "name" from "users"',
    PgQuery.Table('users').DistinctOn(['country']).Select(['country', 'name']));
end;

procedure TPostgresDistinctTest.DistinctOnMySQLRaises;
begin
  try
    MyQuery.Table('users').DistinctOn(['country']);
    Fail('expected ELzNexCompile for DistinctOn on mysql');
  except
    on E: ELzNexCompile do ;
  end;
end;

procedure TPostgresDistinctTest.PlainDistinctWorksOnBoth;
begin
  AssertSQL('select distinct "country" from "users"',
    PgQuery.Table('users').Distinct.Select(['country']));
  AssertSQL('select distinct `country` from `users`',
    MyQuery.Table('users').Distinct.Select(['country']));
end;

procedure TPostgresOrderTest.NullsLastIsNative;
begin
  AssertSQL('select * from "t" order by "name" asc nulls last',
    PgQuery.Table('t').OrderBy('name', odAsc, nlLast));
end;

procedure TPostgresOrderTest.NullsFirstIsNative;
begin
  AssertSQL('select * from "t" order by "name" asc nulls first',
    PgQuery.Table('t').OrderBy('name', odAsc, nlFirst));
end;

procedure TPostgresOrderTest.NullsFirstWithDescending;
begin
  AssertSQL('select * from "t" order by "name" desc nulls first',
    PgQuery.Table('t').OrderBy('name', odDesc, nlFirst));
end;

procedure TPostgresOrderTest.MySQLEmulatesNullsOrdering;
begin

  AssertSQL('select * from `t` order by (`name` is null) asc, `name` asc',
    MyQuery.Table('t').OrderBy('name', odAsc, nlLast));
end;

procedure TPostgresTruncateTest.TruncateRestartsIdentity;
begin
  FreshAst('users');
  FAst.Single.Method := qmTruncate;
  AssertAst('truncate "users" restart identity', '', FPg);
end;

procedure TPostgresTruncateTest.MySQLTruncateHasNoRestartIdentity;
begin
  FreshAst('users');
  FAst.Single.Method := qmTruncate;
  AssertAst('truncate `users`', '', FMy);
end;

procedure TPostgresTruncateTest.SchemaTruncateAlsoRestartsIdentity;
begin

  AssertEquals('truncate "users" restart identity',
    FPg.NewSchemaCompiler.TruncateTableSQL('users').Text);
  AssertEquals('truncate `users`',
    FMy.NewSchemaCompiler.TruncateTableSQL('users').Text);
end;

procedure TPostgresSchemaTest.IncrementsIsSerialPrimaryKey;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('users');
  T.Increments;
  AssertEquals('create table "users" ("id" serial primary key)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.BigIncrementsIsBigserial;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('events');
  T.BigIncrements('uid');
  AssertEquals('create table "events" ("uid" bigserial primary key)',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.BinaryIsBytea;
var
  T: ILzNexTable;
begin

  T := PgSchema.CreateTable('files');
  T.Binary('payload', 16);
  AssertEquals('create table "files" ("payload" bytea null)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.DoubleIsDoublePrecision;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('m');
  T.Double('d');
  T.Float('f');
  AssertEquals('create table "m" ("d" double precision null, "f" real null)',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.BooleanIsBoolean;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('f');
  T.Bool('active');
  AssertEquals('create table "f" ("active" boolean null)', Stmt(T.ToSQL, 0));

  T := MySchema.CreateTable('f');
  T.Bool('active');
  AssertEquals('create table `f` (`active` tinyint(1) null)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.TinyIntCollapsesToSmallint;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('n');
  T.TinyInt('a');
  T.SmallInt('b');
  AssertEquals('create table "n" ("a" smallint null, "b" smallint null)',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.TextVariantsCollapseToText;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('d');
  T.Text('a');
  T.MediumText('b');
  T.LongText('c');
  AssertEquals(
    'create table "d" ("a" text null, "b" text null, "c" text null)',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.UuidIsNativeType;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('k');
  T.Uuid('id');
  AssertEquals('create table "k" ("id" uuid null)', Stmt(T.ToSQL, 0));

  T := MySchema.CreateTable('k');
  T.Uuid('id');
  AssertEquals('create table `k` (`id` char(36) null)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.JsonbIsItsOwnType;
begin

  AssertEquals('jsonb',
    FPg.NewSchemaCompiler.ColumnTypeSQL(ctJsonb, 0, 0, nil));
  AssertEquals('json',
    FPg.NewSchemaCompiler.ColumnTypeSQL(ctJson, 0, 0, nil));
  AssertEquals('json',
    FMy.NewSchemaCompiler.ColumnTypeSQL(ctJsonb, 0, 0, nil));
end;

procedure TPostgresSchemaTest.EnumBecomesTextWithCheck;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('o');
  T.Enum('status', ['new', 'done']);
  AssertEquals(
    'create table "o" ("status" text null ' +
    'check ("status" in (''new'', ''done'')))',
    Stmt(T.ToSQL, 0));

  T := MySchema.CreateTable('o');
  T.Enum('status', ['new', 'done']);
  AssertEquals(
    'create table `o` (`status` enum(''new'', ''done'') null)',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.ModifierOrderIsNullableCollateThenDefault;
var
  Order: TLzNexColumnModifiers;
begin
  Order := FPg.NewSchemaCompiler.ModifierOrder;
  AssertEquals('modifier count', 3, Length(Order));
  AssertTrue('first is nullable', Order[0] = mdNullable);
  AssertTrue('second is collate', Order[1] = mdCollate);
  AssertTrue('third is default', Order[2] = mdDefault);
end;

procedure TPostgresSchemaTest.UnsignedIsIgnored;
var
  T: ILzNexTable;
begin

  T := PgSchema.CreateTable('u');
  T.Int('n').Unsigned.NotNull;
  AssertEquals('create table "u" ("n" integer not null)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.MySQLStillEmitsUnsigned;
var
  T: ILzNexTable;
begin
  T := MySchema.CreateTable('u');
  T.Int('n').Unsigned.NotNull;
  AssertEquals('create table `u` (`n` int unsigned not null)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.ColumnCommentIsASeparateStatement;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  T := PgSchema.CreateTable('users');
  T.Str('email', 191).Comment('login of the user');
  P := T.ToSQL;
  AssertEquals('create table "users" ("email" varchar(191) null)', Stmt(P, 0));
  AssertEquals('comment on column "users"."email" is ''login of the user''',
    Post(P, 0));
  AssertEquals('post count', 1, Length(P.Post));
end;

procedure TPostgresSchemaTest.MySQLKeepsColumnCommentInline;
var
  T: ILzNexTable;
  P: TLzNexDdlPlan;
begin
  T := MySchema.CreateTable('users');
  T.Str('email', 191).Comment('login of the user');
  P := T.ToSQL;
  AssertEquals(
    'create table `users` (`email` varchar(191) null ' +
    'comment ''login of the user'')', Stmt(P, 0));
  AssertEquals('post count', 0, Length(P.Post));
end;

procedure TPostgresSchemaTest.AlterUsesAddColumn;
var
  T: ILzNexTable;
begin
  T := PgSchema.Table('users');
  T.Str('nick', 50);
  T.Int('age').NotNull;
  AssertEquals(
    'alter table "users" add column "nick" varchar(50) null, ' +
    'add column "age" integer not null', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.AlterUsesAlterColumn;
var
  T: ILzNexTable;
begin
  T := PgSchema.Table('users');
  T.Int('age').NotNull.Change;
  AssertEquals('alter table "users" alter column "age" type integer, ' +
    'alter column "age" set not null', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.ChangeEmitsOneActionPerAspect;
var
  T: ILzNexTable;
begin
  T := PgSchema.Table('users');
  T.Int('hits').Nullable.Default_(0).Change;
  AssertEquals('alter table "users" alter column "hits" type integer, ' +
    'alter column "hits" drop not null, alter column "hits" set default 0',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.MySQLChangeStaysOneAction;
var
  T: ILzNexTable;
begin
  T := MySchema.Table('users');
  T.Int('hits').Nullable.Default_(0).Change;
  AssertEquals('alter table `users` modify `hits` int null default 0',
    Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.BooleanDefaultIsTrueOrFalse;
var
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('f');
  T.Bool('active').Default_(True);
  T.Bool('banned').Default_(False);
  AssertEquals('create table "f" ("active" boolean null default true, ' +
    '"banned" boolean null default false)', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.MySQLBooleanDefaultIsOneOrZero;
begin
  AssertEquals('1', FMy.EscapeForLog(TLzNexValue.FromBoolean(True)));
  AssertEquals('0', FMy.EscapeForLog(TLzNexValue.FromBoolean(False)));
  AssertEquals('true', FPg.EscapeForLog(TLzNexValue.FromBoolean(True)));
  AssertEquals('false', FPg.EscapeForLog(TLzNexValue.FromBoolean(False)));
end;

procedure TPostgresSchemaTest.AlterUsesDropColumn;
var
  T: ILzNexTable;
begin
  T := PgSchema.Table('users');
  T.DropColumn('legacy');
  AssertEquals('alter table "users" drop column "legacy"', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.MySQLAlterUsesShortPrefixes;
var
  T: ILzNexTable;
begin
  T := MySchema.Table('users');
  T.Str('nick', 50);
  AssertEquals('alter table `users` add `nick` varchar(50) null',
    Stmt(T.ToSQL, 0));

  T := MySchema.Table('users');
  T.Int('age').NotNull.Change;
  AssertEquals('alter table `users` modify `age` int not null',
    Stmt(T.ToSQL, 0));

  T := MySchema.Table('users');
  T.DropColumn('legacy');
  AssertEquals('alter table `users` drop `legacy`', Stmt(T.ToSQL, 0));
end;

procedure TPostgresSchemaTest.RenameTableKeepsAlterTableForm;
begin
  AssertEquals('alter table "a" rename to "b"',
    FPg.NewSchemaCompiler.RenameTableSQL('a', 'b').Text);
  AssertEquals('rename table `a` to `b`',
    FMy.NewSchemaCompiler.RenameTableSQL('a', 'b').Text);
end;

procedure TPostgresSchemaTest.HasTableFallsBackToCurrentSchema;
var
  F: TLzNexFragment;
begin
  F := FPg.NewSchemaCompiler.HasTableSQL('users', '');
  AssertEquals(
    'select count(*) from information_schema.tables where table_name = ? ' +
    'and table_schema = current_schema()', F.Text);
  AssertEquals('bindings', 'users', BindsOf(F));
end;

procedure TPostgresSchemaTest.HasTableWithExplicitSchemaBinds;
var
  F: TLzNexFragment;
begin
  F := FPg.NewSchemaCompiler.HasTableSQL('users', 'public');
  AssertEquals(
    'select count(*) from information_schema.tables where table_name = ? ' +
    'and table_schema = ?', F.Text);
  AssertEquals('bindings', 'users|public', BindsOf(F));
end;

procedure TPostgresSchemaTest.HasColumnFallsBackToCurrentSchema;
var
  F: TLzNexFragment;
begin
  F := FPg.NewSchemaCompiler.HasColumnSQL('users', 'email', '');
  AssertEquals(
    'select count(*) from information_schema.columns ' +
    'where table_name = ? and column_name = ? ' +
    'and table_schema = current_schema()', F.Text);
  AssertEquals('bindings', 'users|email', BindsOf(F));
end;

procedure TPostgresAbstractionTest.SameQueryCompilesDifferentlyPerDialect;
var
  PgSql, MySql: string;
begin

  PgSql := PgQuery.Table('users').Select(['id', 'name'])
    .Where('active', True).OrderBy('name', odAsc, nlLast).Offset(5).ToSQL.Text;
  MySql := MyQuery.Table('users').Select(['id', 'name'])
    .Where('active', True).OrderBy('name', odAsc, nlLast).Offset(5).ToSQL.Text;

  AssertEquals(
    'select "id", "name" from "users" where "active" = ? ' +
    'order by "name" asc nulls last offset ?', PgSql);
  AssertEquals(
    'select `id`, `name` from `users` where `active` = ? ' +
    'order by (`name` is null) asc, `name` asc ' +
    'limit 18446744073709551615 offset ?', MySql);
  AssertFalse('the two dialects must not produce the same text', PgSql = MySql);
end;

procedure TPostgresAbstractionTest.SameTableCompilesDifferentlyPerDialect;
var
  PgDdl, MyDdl: string;
  T: ILzNexTable;
begin
  T := PgSchema.CreateTable('users');
  T.Increments;
  T.Str('email', 191).NotNull;
  PgDdl := Stmt(T.ToSQL, 0);

  T := MySchema.CreateTable('users');
  T.Increments;
  T.Str('email', 191).NotNull;
  MyDdl := Stmt(T.ToSQL, 0);

  AssertEquals('create table "users" ("id" serial primary key, ' +
    '"email" varchar(191) not null)', PgDdl);
  AssertEquals('create table `users` (`id` int unsigned not null ' +
    'auto_increment primary key, `email` varchar(191) not null)', MyDdl);
  AssertFalse('the two dialects must not produce the same DDL', PgDdl = MyDdl);
end;

initialization
  RegisterTest('postgres', TPostgresDialectTest);
  RegisterTest('postgres', TPostgresIdentifierTest);
  RegisterTest('postgres', TPostgresPagingTest);
  RegisterTest('postgres', TPostgresReturningTest);
  RegisterTest('postgres', TPostgresUpsertTest);
  RegisterTest('postgres', TPostgresDistinctTest);
  RegisterTest('postgres', TPostgresOrderTest);
  RegisterTest('postgres', TPostgresTruncateTest);
  RegisterTest('postgres', TPostgresSchemaTest);
  RegisterTest('postgres', TPostgresAbstractionTest);

end.
