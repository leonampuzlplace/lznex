unit Test.Features.MySQL;

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
  LzNex.Client.MySQL;

type

  TMySQLFeatureTestCase = class(TTestCase)
  protected
    FMy: ILzNexClient;

    procedure SetUp; override;
    procedure TearDown; override;

    function MyQuery: ILzNexQuery;

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
  end;

  TMySQLDatePartTest = class(TMySQLFeatureTestCase)
  published
    procedure WhereDateUsesDateFunction;
    procedure WhereTimeUsesTimeFunction;
    procedure WhereYearUsesYearFunction;
    procedure WhereMonthUsesMonthFunction;
    procedure WhereDayUsesDayFunction;
    procedure WhereHourUsesHourFunction;
    procedure WhereMinuteUsesMinuteFunction;
    procedure WhereSecondUsesSecondFunction;
  end;

  TMySQLJsonTest = class(TMySQLFeatureTestCase)
  published
    procedure JsonPathUsesJsonUnquoteExtract;
    procedure JsonContainsWithoutPath;
    procedure JsonContainsWithPath;
    procedure JsonLengthWithoutPath;
    procedure JsonLengthWithPath;
    procedure NegatedJsonIsWrappedInNot;
    procedure InvalidJsonPathRaises;
  end;

  TMySQLFullTextTest = class(TMySQLFeatureTestCase)
  published
    procedure NaturalModeIsTheDefault;
    procedure BooleanModeUsesInBooleanMode;
  end;

  TMySQLMiscTest = class(TMySQLFeatureTestCase)
  published
    procedure InRandomOrderUsesRand;
  end;

implementation

procedure TMySQLFeatureTestCase.SetUp;
begin
  inherited SetUp;
  FMy := CreateClient('mysql');
end;

procedure TMySQLFeatureTestCase.TearDown;
begin
  FMy := nil;
  inherited TearDown;
end;

function TMySQLFeatureTestCase.MyQuery: ILzNexQuery;
begin
  Result := NewQuery(FMy);
end;

function TMySQLFeatureTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TMySQLFeatureTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TMySQLDatePartTest.WhereDateUsesDateFunction;
begin
  AssertQuery('select * from `t` where date(`seen_at`) = ?', '2024-01-02',
    MyQuery.Table('t').WhereDate('seen_at', TLzNexValue.FromString('2024-01-02')));
end;

procedure TMySQLDatePartTest.WhereTimeUsesTimeFunction;
begin
  AssertQuery('select * from `t` where time(`seen_at`) = ?', '10:00:00',
    MyQuery.Table('t').WhereTime('seen_at', TLzNexValue.FromString('10:00:00')));
end;

procedure TMySQLDatePartTest.WhereYearUsesYearFunction;
begin
  AssertQuery('select * from `t` where year(`seen_at`) = ?', '2024',
    MyQuery.Table('t').WhereYear('seen_at', 2024));
end;

procedure TMySQLDatePartTest.WhereMonthUsesMonthFunction;
begin
  AssertQuery('select * from `t` where month(`seen_at`) = ?', '1',
    MyQuery.Table('t').WhereMonth('seen_at', 1));
end;

procedure TMySQLDatePartTest.WhereDayUsesDayFunction;
begin
  AssertQuery('select * from `t` where day(`seen_at`) = ?', '2',
    MyQuery.Table('t').WhereDay('seen_at', 2));
end;

procedure TMySQLDatePartTest.WhereHourUsesHourFunction;
begin
  AssertQuery('select * from `t` where hour(`seen_at`) = ?', '10',
    MyQuery.Table('t').WhereHour('seen_at', 10));
end;

procedure TMySQLDatePartTest.WhereMinuteUsesMinuteFunction;
begin
  AssertQuery('select * from `t` where minute(`seen_at`) = ?', '30',
    MyQuery.Table('t').WhereDatePart('seen_at', dpMinute, '=', TLzNexValue.FromInteger(30)));
end;

procedure TMySQLDatePartTest.WhereSecondUsesSecondFunction;
begin
  AssertQuery('select * from `t` where second(`seen_at`) = ?', '0',
    MyQuery.Table('t').WhereDatePart('seen_at', dpSecond, '=', TLzNexValue.FromInteger(0)));
end;

procedure TMySQLJsonTest.JsonPathUsesJsonUnquoteExtract;
begin
  AssertQuery(
    'select * from `t` where json_unquote(json_extract(`meta`, ''$.a.b'')) = ?',
    'x',
    MyQuery.Table('t').WhereJsonPath('meta', 'a.b', '=', TLzNexValue.FromString('x')));
end;

procedure TMySQLJsonTest.JsonContainsWithoutPath;
begin
  AssertQuery(
    'select * from `t` where json_contains(`meta`, cast(? as json))',
    '{"a":1}',
    MyQuery.Table('t').WhereJsonContains('meta', '', TLzNexValue.FromString('{"a":1}')));
end;

procedure TMySQLJsonTest.JsonContainsWithPath;
begin
  AssertQuery(
    'select * from `t` where json_contains(`meta`, cast(? as json), ''$.a.b'')',
    '1',
    MyQuery.Table('t').WhereJsonContains('meta', 'a.b', TLzNexValue.FromInteger(1)));
end;

procedure TMySQLJsonTest.JsonLengthWithoutPath;
begin
  AssertQuery(
    'select * from `t` where json_length(`meta`) > ?',
    '0',
    MyQuery.Table('t').WhereJsonLength('meta', '', '>', 0));
end;

procedure TMySQLJsonTest.JsonLengthWithPath;
begin
  AssertQuery(
    'select * from `t` where json_length(`meta`, ''$.a.b'') > ?',
    '0',
    MyQuery.Table('t').WhereJsonLength('meta', 'a.b', '>', 0));
end;

procedure TMySQLJsonTest.NegatedJsonIsWrappedInNot;
var
  Ast: TLzNexAst;
  Stmt: TLzNexJsonStmt;
  Frag: TLzNexFragment;
begin

  Ast := TLzNexAst.Create;
  try
    Ast.Single.Table := TLzNexValue.Identifier('t');
    Stmt := TLzNexJsonStmt.Create(sgWhere, TLzNexValue.Identifier('meta'), '',
      joLength, '>', TLzNexValue.FromInteger(0));
    Stmt.Negated := True;
    Ast.Add(Stmt);
    Frag := FMy.NewCompiler.Compile(Ast);
    AssertEquals('generated SQL', 'select * from `t` where not (json_length(`meta`) > ?)',
      Frag.Text);
    AssertEquals('bindings', '0', BindsOf(Frag));
  finally
    Ast.Free;
  end;
end;

procedure TMySQLJsonTest.InvalidJsonPathRaises;
begin
  try
    MyQuery.Table('t').WhereJsonPath('meta', 'a; drop table t', '=',
      TLzNexValue.FromString('x'));
    Fail('expected ELzNexBuilder for an invalid JSON path');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TMySQLFullTextTest.NaturalModeIsTheDefault;
begin
  AssertQuery(
    'select * from `t` where match (`title`, `body`) against (? in natural language mode)',
    'free pascal',
    MyQuery.Table('t').WhereFullText(['title', 'body'], 'free pascal'));
end;

procedure TMySQLFullTextTest.BooleanModeUsesInBooleanMode;
begin
  AssertQuery(
    'select * from `t` where match (`title`, `body`) against (? in boolean mode)',
    '+pascal -delphi',
    MyQuery.Table('t').WhereFullText(['title', 'body'], '+pascal -delphi', ftBoolean));
end;

procedure TMySQLMiscTest.InRandomOrderUsesRand;
begin
  AssertQuery('select * from `t` order by rand()', '',
    MyQuery.Table('t').InRandomOrder);
end;

initialization
  RegisterTest('mysql', TMySQLDatePartTest);
  RegisterTest('mysql', TMySQLJsonTest);
  RegisterTest('mysql', TMySQLFullTextTest);
  RegisterTest('mysql', TMySQLMiscTest);

end.
