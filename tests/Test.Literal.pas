unit Test.Literal;

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

  TLiteralTestCase = class(TTestCase)
  protected
    FClient: ILzNexClient;
    function CreateDdl(const ABuild: string): string;
    function StrDefaultDdl(const AValue: string): string;
  end;

  TMySQLLiteralTest = class(TLiteralTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure BackslashInDefaultIsEscaped;
    procedure TrailingBackslashCannotCloseTheLiteral;
    procedure QuoteInDefaultIsDoubled;
    procedure BackslashInCommentIsEscaped;
    procedure BackslashInEnumItemIsEscaped;
  end;

  TAnsiLiteralTest = class(TLiteralTestCase)
  published
    procedure PostgresKeepsBackslashVerbatim;
    procedure SQLiteKeepsBackslashVerbatim;
    procedure FirebirdKeepsBackslashVerbatim;
    procedure PostgresBooleanDefaultIsKeyword;
    procedure FirebirdBooleanDefaultIsKeyword;
  end;

  TByteDefaultTest = class(TLiteralTestCase)
  published
    procedure ByteArrayDefaultRaisesInsteadOfEmittingText;
  end;

implementation

function TLiteralTestCase.CreateDdl(const ABuild: string): string;
begin
  Result := ABuild;
end;

function TLiteralTestCase.StrDefaultDdl(const AValue: string): string;
var
  Sch: ILzNexSchema;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  Sch := NewSchema(nil, FClient);
  T := Sch.CreateTable('t');
  T.Str('a', 50).Default_(TLzNexValue.FromString(AValue));
  Plan := FClient.NewSchemaCompiler.CompileTable(T);
  Result := Plan.Statements[0].Text;
end;

procedure TMySQLLiteralTest.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('mysql');
end;

procedure TMySQLLiteralTest.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

procedure TMySQLLiteralTest.BackslashInDefaultIsEscaped;
begin
  AssertEquals('create table `t` (`a` varchar(50) null default ''a\\b'')',
    StrDefaultDdl('a\b'));
end;

procedure TMySQLLiteralTest.TrailingBackslashCannotCloseTheLiteral;
begin

  AssertEquals('create table `t` (`a` varchar(50) null ' +
    'default ''x\\'''', y int default ''''z'')',
    StrDefaultDdl('x\'', y int default ''z'));
end;

procedure TMySQLLiteralTest.QuoteInDefaultIsDoubled;
begin
  AssertEquals('create table `t` (`a` varchar(50) null default ''O''''Brien'')',
    StrDefaultDdl('O''Brien'));
end;

procedure TMySQLLiteralTest.BackslashInCommentIsEscaped;
var
  Sch: ILzNexSchema;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  Sch := NewSchema(nil, FClient);
  T := Sch.CreateTable('t');
  T.Str('a', 50).Comment('a\b');
  Plan := FClient.NewSchemaCompiler.CompileTable(T);
  AssertEquals('create table `t` (`a` varchar(50) null comment ''a\\b'')',
    Plan.Statements[0].Text);
end;

procedure TMySQLLiteralTest.BackslashInEnumItemIsEscaped;
var
  Sch: ILzNexSchema;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  Sch := NewSchema(nil, FClient);
  T := Sch.CreateTable('t');
  T.Enum('a', ['a\b', 'c']);
  Plan := FClient.NewSchemaCompiler.CompileTable(T);
  AssertTrue('o item do enum escapa a barra',
    Pos('''a\\b''', Plan.Statements[0].Text) > 0);
end;

procedure TAnsiLiteralTest.PostgresKeepsBackslashVerbatim;
begin
  FClient := CreateClient('postgresql');
  AssertEquals('create table "t" ("a" varchar(50) null default ''a\b'')',
    StrDefaultDdl('a\b'));
end;

procedure TAnsiLiteralTest.SQLiteKeepsBackslashVerbatim;
begin
  FClient := CreateClient('sqlite');
  AssertTrue('sqlite nao escapa barra',
    Pos('default ''a\b''', StrDefaultDdl('a\b')) > 0);
end;

procedure TAnsiLiteralTest.FirebirdKeepsBackslashVerbatim;
begin
  FClient := CreateClient('firebird');
  AssertTrue('firebird nao escapa barra',
    Pos('default ''a\b''', StrDefaultDdl('a\b')) > 0);
end;

procedure TAnsiLiteralTest.PostgresBooleanDefaultIsKeyword;
var
  Sch: ILzNexSchema;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  FClient := CreateClient('postgresql');
  Sch := NewSchema(nil, FClient);
  T := Sch.CreateTable('t');
  T.Bool('a').Default_(TLzNexValue.FromBoolean(True));
  Plan := FClient.NewSchemaCompiler.CompileTable(T);
  AssertTrue('default true', Pos('default true', Plan.Statements[0].Text) > 0);
end;

procedure TAnsiLiteralTest.FirebirdBooleanDefaultIsKeyword;
var
  Sch: ILzNexSchema;
  T: ILzNexTable;
  Plan: TLzNexDdlPlan;
begin
  FClient := CreateClient('firebird');
  Sch := NewSchema(nil, FClient);
  T := Sch.CreateTable('t');
  T.Bool('a').Default_(TLzNexValue.FromBoolean(False));
  Plan := FClient.NewSchemaCompiler.CompileTable(T);
  AssertTrue('default false', Pos('default false', Plan.Statements[0].Text) > 0);
end;

procedure TByteDefaultTest.ByteArrayDefaultRaisesInsteadOfEmittingText;
var
  Sch: ILzNexSchema;
  T: ILzNexTable;
  Blob: TBytes;
  Raised: Boolean;
begin
  FClient := CreateClient('mysql');
  SetLength(Blob, 2);
  Blob[0] := 1;
  Blob[1] := 2;

  Sch := NewSchema(nil, FClient);
  T := Sch.CreateTable('t');
  T.Str('a', 50).Default_(TLzNexValue.FromBytes(Blob));

  Raised := False;
  try
    FClient.NewSchemaCompiler.CompileTable(T);
  except
    on E: ELzNexCompile do
      Raised := True;
  end;
  AssertTrue('binario sem literal levanta em vez de emitir "<N bytes>"', Raised);
end;

initialization
  RegisterTest('literal', TMySQLLiteralTest);
  RegisterTest('literal', TAnsiLiteralTest);
  RegisterTest('literal', TByteDefaultTest);

end.
