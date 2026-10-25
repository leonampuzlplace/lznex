unit Test.Features.SQLite;

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
  LzNex.Client.SQLite;

type

  TSQLiteFeaturesTestCase = class(TTestCase)
  protected
    FLite: ILzNexClient;
    FAst: TLzNexAst;

    procedure SetUp; override;
    procedure TearDown; override;

    function LiteQuery: ILzNexQuery;

    procedure FreshAst(const ATable: string);

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
    procedure AssertAst(const AExpectedSQL, AExpectedBinds: string);
    procedure AssertAstRaises(const AMessagePart: string);
  end;

  TSQLiteDatePartTest = class(TSQLiteFeaturesTestCase)
  published
    procedure WhereDateUsesDateFunction;
    procedure WhereTimeUsesTimeFunction;
    procedure WhereYearCastsStrftimeToInteger;
    procedure WhereMonthCastsStrftimeToInteger;
    procedure WhereDayCastsStrftimeToInteger;
    procedure WhereHourCastsStrftimeToInteger;
    procedure WhereMinuteCastsStrftimeToInteger;
    procedure WhereSecondCastsStrftimeToInteger;
  end;

  TSQLiteJsonTest = class(TSQLiteFeaturesTestCase)
  published
    procedure JsonPathUsesJsonExtract;
    procedure JsonContainsWithPathUsesJsonEach;
    procedure JsonContainsWithoutPathChecksWholeDocument;
    procedure JsonLengthWithPathUsesJsonArrayLength;
    procedure JsonLengthWithoutPathUsesJsonArrayLength;
    procedure NegatedJsonContainsWrapsInNot;
    procedure JsonContainsWithADocumentCandidateRaises;
  end;

  TSQLiteRandomAndFullTextTest = class(TSQLiteFeaturesTestCase)
  published
    procedure InRandomOrderUsesRandomFunction;
    procedure FullTextIsRefusedByTheBuilder;
    procedure FullTextSafetyNetMentionsFts5;
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

procedure TSQLiteFeaturesTestCase.SetUp;
begin
  inherited SetUp;
  FLite := CreateClient('sqlite');
  FAst := nil;
end;

procedure TSQLiteFeaturesTestCase.TearDown;
begin
  FreeAndNil(FAst);
  FLite := nil;
  inherited TearDown;
end;

function TSQLiteFeaturesTestCase.LiteQuery: ILzNexQuery;
begin
  Result := NewQuery(FLite);
end;

procedure TSQLiteFeaturesTestCase.FreshAst(const ATable: string);
begin
  FreeAndNil(FAst);
  FAst := TLzNexAst.Create;
  if ATable <> '' then
    FAst.Single.Table := TLzNexValue.Identifier(ATable);
end;

function TSQLiteFeaturesTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TSQLiteFeaturesTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TSQLiteFeaturesTestCase.AssertAst(const AExpectedSQL, AExpectedBinds: string);
var
  Fragment: TLzNexFragment;
begin
  Fragment := FLite.NewCompiler.Compile(FAst);
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TSQLiteFeaturesTestCase.AssertAstRaises(const AMessagePart: string);
var
  Fragment: TLzNexFragment;
begin
  try
    Fragment := FLite.NewCompiler.Compile(FAst);
    Fail('expected ELzNexCompile, got [' + Fragment.Text + ']');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "' + AMessagePart + '", got: ' + E.Message,
        Pos(AMessagePart, E.Message) > 0);
  end;
end;

procedure TSQLiteDatePartTest.WhereDateUsesDateFunction;
begin
  AssertQuery('select * from "t" where date("created_at") = ?', '2024-01-02',
    LiteQuery.Table('t').WhereDate('created_at', TLzNexValue.FromString('2024-01-02')));
end;

procedure TSQLiteDatePartTest.WhereTimeUsesTimeFunction;
begin
  AssertQuery('select * from "t" where time("created_at") = ?', '10:00:00',
    LiteQuery.Table('t').WhereTime('created_at', TLzNexValue.FromString('10:00:00')));
end;

procedure TSQLiteDatePartTest.WhereYearCastsStrftimeToInteger;
begin
  { strftime devolve texto; sem o cast "2024" nunca bate com o inteiro 2024. }
  AssertQuery(
    'select * from "t" where cast(strftime(''%Y'', "created_at") as integer) = ?',
    '2024', LiteQuery.Table('t').WhereYear('created_at', 2024));
end;

procedure TSQLiteDatePartTest.WhereMonthCastsStrftimeToInteger;
begin
  AssertQuery(
    'select * from "t" where cast(strftime(''%m'', "created_at") as integer) = ?',
    '7', LiteQuery.Table('t').WhereMonth('created_at', 7));
end;

procedure TSQLiteDatePartTest.WhereDayCastsStrftimeToInteger;
begin
  AssertQuery(
    'select * from "t" where cast(strftime(''%d'', "created_at") as integer) = ?',
    '15', LiteQuery.Table('t').WhereDay('created_at', 15));
end;

procedure TSQLiteDatePartTest.WhereHourCastsStrftimeToInteger;
begin
  AssertQuery(
    'select * from "t" where cast(strftime(''%H'', "created_at") as integer) = ?',
    '9', LiteQuery.Table('t').WhereHour('created_at', 9));
end;

procedure TSQLiteDatePartTest.WhereMinuteCastsStrftimeToInteger;
begin
  AssertQuery(
    'select * from "t" where cast(strftime(''%M'', "created_at") as integer) = ?',
    '30', LiteQuery.Table('t').WhereDatePart('created_at', dpMinute, '=',
      TLzNexValue.FromInteger(30)));
end;

procedure TSQLiteDatePartTest.WhereSecondCastsStrftimeToInteger;
begin
  AssertQuery(
    'select * from "t" where cast(strftime(''%S'', "created_at") as integer) = ?',
    '45', LiteQuery.Table('t').WhereDatePart('created_at', dpSecond, '=',
      TLzNexValue.FromInteger(45)));
end;

procedure TSQLiteJsonTest.JsonPathUsesJsonExtract;
begin
  { cast(... as text): json_extract devolve o tipo nativo do JSON, e o bind
    chega como texto nos outros dialetos tambem (json_unquote/#>>). }
  AssertQuery(
    'select * from "t" where cast(json_extract("data", ''$.a.b'') as text) = ?',
    'x', LiteQuery.Table('t').WhereJsonPath('data', '$.a.b', '=', TLzNexValue.FromString('x')));
end;

procedure TSQLiteJsonTest.JsonContainsWithPathUsesJsonEach;
begin
  { Nao ha json_contains no SQLite: pergunta se algum elemento do array no
    path bate com o valor. }
  AssertQuery(
    'select * from "t" where exists (select 1 from json_each("data", ''$.tags'') ' +
    'where value = ?)', 'vip',
    LiteQuery.Table('t').WhereJsonContains('data', '$.tags', TLzNexValue.FromString('vip')));
end;

procedure TSQLiteJsonTest.JsonContainsWithoutPathChecksWholeDocument;
begin
  AssertQuery(
    'select * from "t" where exists (select 1 from json_each("data") ' +
    'where value = ?)', 'vip',
    LiteQuery.Table('t').WhereJsonContains('data', '', TLzNexValue.FromString('vip')));
end;

procedure TSQLiteJsonTest.JsonLengthWithPathUsesJsonArrayLength;
begin
  AssertQuery(
    'select * from "t" where json_array_length("data", ''$.tags'') > ?', '2',
    LiteQuery.Table('t').WhereJsonLength('data', '$.tags', '>', 2));
end;

procedure TSQLiteJsonTest.JsonLengthWithoutPathUsesJsonArrayLength;
begin
  AssertQuery(
    'select * from "t" where json_array_length("data") = ?', '3',
    LiteQuery.Table('t').WhereJsonLength('data', '', '=', 3));
end;

procedure TSQLiteJsonTest.NegatedJsonContainsWrapsInNot;
var
  J: TLzNexJsonStmt;
begin
  FreshAst('t');
  J := TLzNexJsonStmt.Create(sgWhere, TLzNexValue.Identifier('data'), '',
    joContains, '=', TLzNexValue.FromString('x'));
  J.Negated := True;
  FAst.Add(J);
  AssertAst(
    'select * from "t" where not (exists (select 1 from json_each("data") ' +
    'where value = ?))', 'x');
end;

procedure TSQLiteJsonTest.JsonContainsWithADocumentCandidateRaises;
begin
  { json_each(col) so compara contra escalares; um candidato que e ele mesmo
    um documento precisa de WhereJsonPath apontando a chave. }
  try
    LiteQuery.Table('t').WhereJsonContains('data', '',
      TLzNexValue.FromString('{"a":{"b":42}}')).ToSQL;
    Fail('expected ELzNexCompile for a document candidate without a path');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "WhereJsonPath", got: ' + E.Message,
        Pos('WhereJsonPath', E.Message) > 0);
  end;
end;

procedure TSQLiteRandomAndFullTextTest.InRandomOrderUsesRandomFunction;
begin
  AssertQuery('select * from "t" order by random()', '',
    LiteQuery.Table('t').InRandomOrder);
end;

procedure TSQLiteRandomAndFullTextTest.FullTextIsRefusedByTheBuilder;
begin
  { O builder ja barra pela capacidade do dialeto antes de chegar no
    compilador: SupportsFullText e False por default no SQLite. }
  try
    LiteQuery.Table('t').WhereFullText(['body'], 'hello');
    Fail('expected ELzNexCompile for WhereFullText on sqlite');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "WhereLike", got: ' + E.Message,
        Pos('WhereLike', E.Message) > 0);
  end;
end;

procedure TSQLiteRandomAndFullTextTest.FullTextSafetyNetMentionsFts5;
begin
  { Rede de seguranca do compilador, so alcancavel contornando o builder. }
  FreshAst('t');
  FAst.Add(TLzNexFullTextStmt.Create(sgWhere, Idents(['body']),
    TLzNexValue.FromString('hello'), ftNatural));
  AssertAstRaises('FTS5');
end;

initialization
  RegisterTest('sqlite', TSQLiteDatePartTest);
  RegisterTest('sqlite', TSQLiteJsonTest);
  RegisterTest('sqlite', TSQLiteRandomAndFullTextTest);

end.
