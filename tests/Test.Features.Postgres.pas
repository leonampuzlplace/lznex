unit Test.Features.Postgres;

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
  LzNex.Client.Postgres;

type

  TPostgresFeatureTestCase = class(TTestCase)
  protected
    FPg: ILzNexClient;

    procedure SetUp; override;
    procedure TearDown; override;

    function PgQuery: ILzNexQuery;

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
  end;

  TPostgresDatePartTest = class(TPostgresFeatureTestCase)
  published
    procedure WhereDateUsesCastAsDate;
    procedure WhereTimeUsesCastAsTime;
    procedure WhereYearUsesExtract;
    procedure WhereMonthUsesExtract;
    procedure WhereDayUsesExtract;
    procedure WhereHourUsesExtract;
    procedure WhereMinuteUsesExtract;
    procedure WhereSecondUsesExtract;
  end;

  TPostgresJsonTest = class(TPostgresFeatureTestCase)
  published
    procedure JsonPathUsesArrowArrow;
    procedure JsonContainsWithoutPath;
    procedure JsonContainsWithPath;
    procedure JsonContainsWithScalarValueUsesToJsonb;
    procedure JsonLengthWithoutPath;
    procedure JsonLengthWithPath;
    procedure NegatedJsonIsWrappedInNot;
    procedure InvalidJsonPathRaises;
  end;

  TPostgresFullTextTest = class(TPostgresFeatureTestCase)
  published
    procedure NaturalModeUsesPlaintoTsQuery;
    procedure BooleanModeUsesWebsearchToTsQuery;
  end;

  TPostgresMiscTest = class(TPostgresFeatureTestCase)
  published
    procedure InRandomOrderUsesRandom;
  end;

implementation

procedure TPostgresFeatureTestCase.SetUp;
begin
  inherited SetUp;
  FPg := CreateClient('postgres');
end;

procedure TPostgresFeatureTestCase.TearDown;
begin
  FPg := nil;
  inherited TearDown;
end;

function TPostgresFeatureTestCase.PgQuery: ILzNexQuery;
begin
  Result := NewQuery(FPg);
end;

function TPostgresFeatureTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TPostgresFeatureTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TPostgresDatePartTest.WhereDateUsesCastAsDate;
begin
  AssertQuery('select * from "t" where cast("seen_at" as date) = ?', '2024-01-02',
    PgQuery.Table('t').WhereDate('seen_at', TLzNexValue.FromString('2024-01-02')));
end;

procedure TPostgresDatePartTest.WhereTimeUsesCastAsTime;
begin
  AssertQuery('select * from "t" where cast("seen_at" as time) = ?', '10:00:00',
    PgQuery.Table('t').WhereTime('seen_at', TLzNexValue.FromString('10:00:00')));
end;

procedure TPostgresDatePartTest.WhereYearUsesExtract;
begin
  AssertQuery('select * from "t" where extract(year from "seen_at") = ?', '2024',
    PgQuery.Table('t').WhereYear('seen_at', 2024));
end;

procedure TPostgresDatePartTest.WhereMonthUsesExtract;
begin
  AssertQuery('select * from "t" where extract(month from "seen_at") = ?', '1',
    PgQuery.Table('t').WhereMonth('seen_at', 1));
end;

procedure TPostgresDatePartTest.WhereDayUsesExtract;
begin
  AssertQuery('select * from "t" where extract(day from "seen_at") = ?', '2',
    PgQuery.Table('t').WhereDay('seen_at', 2));
end;

procedure TPostgresDatePartTest.WhereHourUsesExtract;
begin
  AssertQuery('select * from "t" where extract(hour from "seen_at") = ?', '10',
    PgQuery.Table('t').WhereHour('seen_at', 10));
end;

procedure TPostgresDatePartTest.WhereMinuteUsesExtract;
begin
  AssertQuery('select * from "t" where extract(minute from "seen_at") = ?', '30',
    PgQuery.Table('t').WhereDatePart('seen_at', dpMinute, '=', TLzNexValue.FromInteger(30)));
end;

procedure TPostgresDatePartTest.WhereSecondUsesExtract;
begin
  AssertQuery('select * from "t" where extract(second from "seen_at") = ?', '0',
    PgQuery.Table('t').WhereDatePart('seen_at', dpSecond, '=', TLzNexValue.FromInteger(0)));
end;

procedure TPostgresJsonTest.JsonPathUsesArrowArrow;
begin
  AssertQuery(
    'select * from "t" where "meta" #>> ''{a,b}'' = ?',
    'x',
    PgQuery.Table('t').WhereJsonPath('meta', 'a.b', '=', TLzNexValue.FromString('x')));
end;

procedure TPostgresJsonTest.JsonContainsWithoutPath;
begin
  AssertQuery(
    'select * from "t" where "meta"::jsonb @> ?::jsonb',
    '{"a":1}',
    PgQuery.Table('t').WhereJsonContains('meta', '', TLzNexValue.FromString('{"a":1}')));
end;

procedure TPostgresJsonTest.JsonContainsWithPath;
begin
  AssertQuery(
    'select * from "t" where ("meta" #> ''{a,b}'')::jsonb @> ?::jsonb',
    '1',
    PgQuery.Table('t').WhereJsonContains('meta', 'a.b', TLzNexValue.FromString('1')));
end;

procedure TPostgresJsonTest.JsonContainsWithScalarValueUsesToJsonb;
begin

  AssertQuery(
    'select * from "t" where ("meta" #> ''{tags}'')::jsonb @> to_jsonb(?)',
    '2',
    PgQuery.Table('t').WhereJsonContains('meta', 'tags', TLzNexValue.FromInteger(2)));
end;

procedure TPostgresJsonTest.JsonLengthWithoutPath;
begin
  AssertQuery(
    'select * from "t" where jsonb_array_length("meta"::jsonb) > ?',
    '0',
    PgQuery.Table('t').WhereJsonLength('meta', '', '>', 0));
end;

procedure TPostgresJsonTest.JsonLengthWithPath;
begin
  AssertQuery(
    'select * from "t" where jsonb_array_length(("meta" #> ''{a,b}'')::jsonb) > ?',
    '0',
    PgQuery.Table('t').WhereJsonLength('meta', 'a.b', '>', 0));
end;

procedure TPostgresJsonTest.NegatedJsonIsWrappedInNot;
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
    Frag := FPg.NewCompiler.Compile(Ast);
    AssertEquals('generated SQL',
      'select * from "t" where not (jsonb_array_length("meta"::jsonb) > ?)', Frag.Text);
    AssertEquals('bindings', '0', BindsOf(Frag));
  finally
    Ast.Free;
  end;
end;

procedure TPostgresJsonTest.InvalidJsonPathRaises;
begin
  try
    PgQuery.Table('t').WhereJsonPath('meta', 'a; drop table t', '=',
      TLzNexValue.FromString('x'));
    Fail('expected ELzNexBuilder for an invalid JSON path');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPostgresFullTextTest.NaturalModeUsesPlaintoTsQuery;
begin
  AssertQuery(
    'select * from "t" where to_tsvector(''simple'', coalesce("title", '''') || '' '' ' +
    '|| coalesce("body", '''')) @@ plainto_tsquery(''simple'', ?)',
    'free pascal',
    PgQuery.Table('t').WhereFullText(['title', 'body'], 'free pascal'));
end;

procedure TPostgresFullTextTest.BooleanModeUsesWebsearchToTsQuery;
begin
  AssertQuery(
    'select * from "t" where to_tsvector(''simple'', coalesce("title", '''') || '' '' ' +
    '|| coalesce("body", '''')) @@ websearch_to_tsquery(''simple'', ?)',
    '+pascal -delphi',
    PgQuery.Table('t').WhereFullText(['title', 'body'], '+pascal -delphi', ftBoolean));
end;

procedure TPostgresMiscTest.InRandomOrderUsesRandom;
begin
  AssertQuery('select * from "t" order by random()', '',
    PgQuery.Table('t').InRandomOrder);
end;

initialization
  RegisterTest('postgres', TPostgresDatePartTest);
  RegisterTest('postgres', TPostgresJsonTest);
  RegisterTest('postgres', TPostgresFullTextTest);
  RegisterTest('postgres', TPostgresMiscTest);

end.
