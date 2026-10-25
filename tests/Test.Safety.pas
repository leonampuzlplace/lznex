unit Test.Safety;

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
  LzNex.Raw,
  LzNex.Query,
  LzNex.Client.MySQL,
  LzNex.Client.Postgres,
  LzNex.Client.SQLite,
  LzNex.Client.Firebird;

type

  TSchemaOptionTest = class(TTestCase)
  protected
    procedure AssertRejects(const AWhat: string; const ABuild: TProcedure);
  published
    procedure OrderByRawKeepsItsOwnDirection;
    procedure PostgresEmitsCollateAsAQuotedIdentifier;
    procedure IncrementWithoutAColumnRaises;
    procedure CollateWithPunctuationIsRejected;
    procedure EngineWithPunctuationIsRejected;
    procedure CharsetWithPunctuationIsRejected;
    procedure PlainNamesStillPass;
  end;

  TEnumChangeTest = class(TTestCase)
  protected
    function ChangeRaises(const ADialect: string): Boolean;
  published
    procedure PostgresRefusesEnumChange;
    procedure FirebirdRefusesEnumChange;
    procedure MySQLStillChangesEnumNatively;
  end;

  TRawScannerTest = class(TTestCase)
  protected
    FClient: ILzNexClient;
    procedure SetUp; override;
    procedure TearDown; override;
    function TextOf(const ASQL: string; const AArgs: array of const): string;
    function BindCountOf(const ASQL: string; const AArgs: array of const): Integer;
  published
    procedure DumpDoesNotEatAQuestionMarkInsideAnIdentifier;
    procedure ColonInsideATextLiteralIsNotAParameter;
    procedure TimeLiteralIsNotAParameter;
    procedure QuestionMarkInsideATextLiteralIsNotAPlaceholder;
    procedure QuestionMarkInsideACommentIsNotAPlaceholder;
    procedure EscapedQuestionMarkInsideALiteralStillWorks;
    procedure EscapedQuestionMarkOutsideALiteralIsRejected;
    procedure PostgresCastStillWorks;
    procedure QuotedIdentifierPlaceholderStillWorks;
  end;

implementation

procedure TSchemaOptionTest.AssertRejects(const AWhat: string;
  const ABuild: TProcedure);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    ABuild;
  except
    on E: ELzNexSchema do
      Raised := True;
  end;
  AssertTrue(AWhat + ' must be rejected before it reaches the DDL', Raised);
end;

const
  INJECTED = 'BINARY, b integer references secret(id)';

procedure BuildCollate;
begin
  NewSchema(nil, CreateClient('sqlite')).CreateTable('t')
    .Str('a', 50).Collate(INJECTED);
end;

procedure BuildEngine;
begin
  NewSchema(nil, CreateClient('mysql')).CreateTable('t')
    .Increments('id').Engine('InnoDB, add column pwned int');
end;

procedure BuildCharset;
begin
  NewSchema(nil, CreateClient('mysql')).CreateTable('t')
    .Increments('id').Charset('utf8mb4, add column pwned int');
end;

procedure TSchemaOptionTest.OrderByRawKeepsItsOwnDirection;
begin
  AssertEquals('select * from `t` order by id desc',
    NewQuery(CreateClient('mysql')).Table('t')
      .OrderByRaw('id desc', []).ToSQL.Text);
end;

procedure TSchemaOptionTest.PostgresEmitsCollateAsAQuotedIdentifier;
var
  Cli: ILzNexClient;
  T: ILzNexTable;
begin
  Cli := CreateClient('postgresql');
  T := NewSchema(nil, Cli).CreateTable('t');
  T.Str('a', 50).Collate('C');
  AssertTrue('collation must survive, quoted',
    Pos('collate "C"', Cli.NewSchemaCompiler.CompileTable(T).Statements[0].Text) > 0);
end;

procedure TSchemaOptionTest.IncrementWithoutAColumnRaises;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    NewQuery(CreateClient('mysql')).Table('t').Increment('', 1);
  except
    on E: ELzNexBuilder do
      Raised := True;
  end;
  AssertTrue('an empty column would emit "set  =  + ?"', Raised);
end;

procedure TSchemaOptionTest.CollateWithPunctuationIsRejected;
begin
  AssertRejects('collation carrying punctuation', BuildCollate);
end;

procedure TSchemaOptionTest.EngineWithPunctuationIsRejected;
begin
  AssertRejects('engine carrying punctuation', BuildEngine);
end;

procedure TSchemaOptionTest.CharsetWithPunctuationIsRejected;
begin
  AssertRejects('charset carrying punctuation', BuildCharset);
end;

procedure TSchemaOptionTest.PlainNamesStillPass;
var
  Cli: ILzNexClient;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  Cli := CreateClient('mysql');
  T := NewSchema(nil, Cli).CreateTable('t');
  T.Increments('id').Engine('InnoDB').Charset('utf8mb4');
  T.Str('a', 50).Collate('utf8mb4_0900_ai_ci');
  Plan := Cli.NewSchemaCompiler.CompileTable(T);
  AssertTrue('engine survives', Pos('engine = InnoDB', Plan.Statements[0].Text) > 0);
  AssertTrue('charset survives',
    Pos('character set utf8mb4', Plan.Statements[0].Text) > 0);
  AssertTrue('collation survives',
    Pos('utf8mb4_0900_ai_ci', Plan.Statements[0].Text) > 0);
end;

function TEnumChangeTest.ChangeRaises(const ADialect: string): Boolean;
var
  Cli: ILzNexClient;
  T: ILzNexTable;
begin
  Result := False;
  Cli := CreateClient(ADialect);
  T := NewSchema(nil, Cli).Table('users');
  T.Enum('status', ['active', 'banned']).Change;
  try
    Cli.NewSchemaCompiler.CompileTable(T);
  except
    on E: ELzNexSchema do
      Result := True;
  end;
end;

procedure TEnumChangeTest.PostgresRefusesEnumChange;
begin
  AssertTrue('an enum Change that would silently drop the CHECK must raise',
    ChangeRaises('postgresql'));
end;

procedure TEnumChangeTest.FirebirdRefusesEnumChange;
begin
  AssertTrue('an enum Change that would silently drop the CHECK must raise',
    ChangeRaises('firebird'));
end;

procedure TEnumChangeTest.MySQLStillChangesEnumNatively;
var
  Cli: ILzNexClient;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  Cli := CreateClient('mysql');
  T := NewSchema(nil, Cli).Table('users');
  T.Enum('status', ['active', 'banned']).Change;
  Plan := Cli.NewSchemaCompiler.CompileTable(T);
  AssertTrue('MySQL has a native enum and needs no CHECK',
    Pos('enum(''active'', ''banned'')', Plan.Statements[0].Text) > 0);
end;

procedure TRawScannerTest.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('mysql');
end;

procedure TRawScannerTest.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

function TRawScannerTest.TextOf(const ASQL: string;
  const AArgs: array of const): string;
begin
  Result := LzNexRaw(ASQL, AArgs).Build(FClient).Text;
end;

function TRawScannerTest.BindCountOf(const ASQL: string;
  const AArgs: array of const): Integer;
begin
  Result := LzNexRaw(ASQL, AArgs).Build(FClient).Bindings.Count;
end;

procedure TRawScannerTest.DumpDoesNotEatAQuestionMarkInsideAnIdentifier;
begin
  AssertEquals(
    'select * from `t` where `a?b` = ''x'' and `c` = ''y''',
    NewQuery(FClient).Table('t').Where('a?b', 'x').Where('c', 'y').ToSQLString);
end;

procedure TRawScannerTest.ColonInsideATextLiteralIsNotAParameter;
const
  SQL = 'insert into t (meta) values (''' + '{"a":1}' + ''')';
begin
  AssertEquals(SQL, TextOf(SQL, []));
  AssertEquals('no binding comes out of a literal', 0, BindCountOf(SQL, []));
end;

procedure TRawScannerTest.TimeLiteralIsNotAParameter;
const
  SQL = 'select ''10:30:00'' as t';
begin
  AssertEquals(SQL, TextOf(SQL, []));
end;

procedure TRawScannerTest.QuestionMarkInsideATextLiteralIsNotAPlaceholder;
const
  SQL = 'select ''a?b'' as a, ? as b';
begin
  AssertEquals(SQL, TextOf(SQL, ['v']));
  AssertEquals('only the real placeholder binds', 1, BindCountOf(SQL, ['v']));
end;

procedure TRawScannerTest.QuestionMarkInsideACommentIsNotAPlaceholder;
const
  SQL = 'select 1 -- why ? here' + #10 + ' , ? as b';
begin
  AssertEquals('only the real placeholder binds', 1, BindCountOf(SQL, ['v']));
end;

procedure TRawScannerTest.EscapedQuestionMarkInsideALiteralStillWorks;
begin
  AssertEquals('json_extract(d, ''$.a?b'') = ?',
    TextOf('json_extract(d, ''$.a\?b'') = ?', ['v']));
end;

procedure TRawScannerTest.EscapedQuestionMarkOutsideALiteralIsRejected;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TextOf('select \? as a, ? as b', ['v']);
  except
    on E: ELzNexBuilder do
      Raised := True;
  end;
  AssertTrue('a bare "?" would be counted as a marker and shift the bindings',
    Raised);
end;

procedure TRawScannerTest.PostgresCastStillWorks;
const
  SQL = 'select a::int from t where b = ?';
begin
  AssertEquals(SQL, TextOf(SQL, ['v']));
end;

procedure TRawScannerTest.QuotedIdentifierPlaceholderStillWorks;
begin
  AssertEquals('select `c` from t where a = ?',
    TextOf('select ?? from t where a = ?', ['c', 'v']));
end;

initialization
  RegisterTest('safety', TSchemaOptionTest);
  RegisterTest('safety', TEnumChangeTest);
  RegisterTest('safety', TRawScannerTest);

end.
