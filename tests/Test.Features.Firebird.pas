unit Test.Features.Firebird;

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
  LzNex.Client.Firebird;

type

  TFirebirdFeaturesTestCase = class(TTestCase)
  protected
    FFb: ILzNexClient;
    FAst: TLzNexAst;

    procedure SetUp; override;
    procedure TearDown; override;

    function FbQuery: ILzNexQuery;

    procedure FreshAst(const ATable: string);

    function BindsOf(const AFragment: TLzNexFragment): string;
    procedure AssertQuery(const AExpectedSQL, AExpectedBinds: string;
      const AQuery: ILzNexQuery);
    procedure AssertAstRaises(const AMessagePart: string);
  end;

  TFirebirdDatePartTest = class(TFirebirdFeaturesTestCase)
  published
    procedure WhereDateUsesCastAsDate;
    procedure WhereTimeUsesCastAsTime;
    procedure WhereYearUsesExtract;
    procedure WhereMonthUsesExtract;
    procedure WhereDayUsesExtract;
    procedure WhereHourUsesExtract;
    procedure WhereMinuteUsesExtract;
    procedure WhereSecondCastsExtractToInteger;
  end;

  TFirebirdRandomAndCapabilityTest = class(TFirebirdFeaturesTestCase)
  published
    procedure InRandomOrderUsesRand;
    procedure JsonIsRefusedByTheBuilder;
    procedure FullTextIsRefusedByTheBuilder;
    procedure JsonSafetyNetMentionsTheDialect;
    procedure FullTextSafetyNetMentionsTheDialect;
    procedure DeadlockAndUpdateConflictAreRetryable;
    procedure OtherErrorCodesAreNotRetryableByCode;
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

procedure TFirebirdFeaturesTestCase.SetUp;
begin
  inherited SetUp;
  FFb := CreateClient('firebird');
  FAst := nil;
end;

procedure TFirebirdFeaturesTestCase.TearDown;
begin
  FreeAndNil(FAst);
  FFb := nil;
  inherited TearDown;
end;

function TFirebirdFeaturesTestCase.FbQuery: ILzNexQuery;
begin
  Result := NewQuery(FFb);
end;

procedure TFirebirdFeaturesTestCase.FreshAst(const ATable: string);
begin
  FreeAndNil(FAst);
  FAst := TLzNexAst.Create;
  if ATable <> '' then
    FAst.Single.Table := TLzNexValue.Identifier(ATable);
end;

function TFirebirdFeaturesTestCase.BindsOf(const AFragment: TLzNexFragment): string;
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

procedure TFirebirdFeaturesTestCase.AssertQuery(const AExpectedSQL, AExpectedBinds: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBinds, BindsOf(Fragment));
end;

procedure TFirebirdFeaturesTestCase.AssertAstRaises(const AMessagePart: string);
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

procedure TFirebirdDatePartTest.WhereDateUsesCastAsDate;
begin
  AssertQuery('select * from "t" where cast("created_at" as date) = ?', '2024-01-02',
    FbQuery.Table('t').WhereDate('created_at', TLzNexValue.FromString('2024-01-02')));
end;

procedure TFirebirdDatePartTest.WhereTimeUsesCastAsTime;
begin

  AssertQuery('select * from "t" where cast("created_at" as time) = ?', '10:00:00',
    FbQuery.Table('t').WhereTime('created_at', TLzNexValue.FromString('10:00:00')));
end;

procedure TFirebirdDatePartTest.WhereYearUsesExtract;
begin
  AssertQuery('select * from "t" where extract(year from "created_at") = ?', '2024',
    FbQuery.Table('t').WhereYear('created_at', 2024));
end;

procedure TFirebirdDatePartTest.WhereMonthUsesExtract;
begin
  AssertQuery('select * from "t" where extract(month from "created_at") = ?', '7',
    FbQuery.Table('t').WhereMonth('created_at', 7));
end;

procedure TFirebirdDatePartTest.WhereDayUsesExtract;
begin
  AssertQuery('select * from "t" where extract(day from "created_at") = ?', '15',
    FbQuery.Table('t').WhereDay('created_at', 15));
end;

procedure TFirebirdDatePartTest.WhereHourUsesExtract;
begin
  AssertQuery('select * from "t" where extract(hour from "created_at") = ?', '9',
    FbQuery.Table('t').WhereHour('created_at', 9));
end;

procedure TFirebirdDatePartTest.WhereMinuteUsesExtract;
begin
  AssertQuery('select * from "t" where extract(minute from "created_at") = ?', '30',
    FbQuery.Table('t').WhereDatePart('created_at', dpMinute, '=',
      TLzNexValue.FromInteger(30)));
end;

procedure TFirebirdDatePartTest.WhereSecondCastsExtractToInteger;
begin

  AssertQuery(
    'select * from "t" where cast(extract(second from "created_at") as integer) = ?',
    '45', FbQuery.Table('t').WhereDatePart('created_at', dpSecond, '=',
      TLzNexValue.FromInteger(45)));
end;

procedure TFirebirdRandomAndCapabilityTest.InRandomOrderUsesRand;
begin
  AssertQuery('select * from "t" order by rand()', '',
    FbQuery.Table('t').InRandomOrder);
end;

procedure TFirebirdRandomAndCapabilityTest.JsonIsRefusedByTheBuilder;
begin
  try
    FbQuery.Table('t').WhereJsonPath('data', '$.a', '=', TLzNexValue.FromString('x'));
    Fail('expected ELzNexCompile for WhereJsonPath on firebird');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "JSON", got: ' + E.Message,
        Pos('JSON', E.Message) > 0);
  end;
end;

procedure TFirebirdRandomAndCapabilityTest.FullTextIsRefusedByTheBuilder;
begin
  try
    FbQuery.Table('t').WhereFullText(['body'], 'hello');
    Fail('expected ELzNexCompile for WhereFullText on firebird');
  except
    on E: ELzNexCompile do
      AssertTrue('message should mention "full text", got: ' + E.Message,
        Pos('full text', E.Message) > 0);
  end;
end;

procedure TFirebirdRandomAndCapabilityTest.JsonSafetyNetMentionsTheDialect;
begin

  FreshAst('t');
  FAst.Add(TLzNexJsonStmt.Create(sgWhere, TLzNexValue.Identifier('data'), '$.a',
    joPath, '=', TLzNexValue.FromString('x')));
  AssertAstRaises('firebird');
end;

procedure TFirebirdRandomAndCapabilityTest.FullTextSafetyNetMentionsTheDialect;
begin
  FreshAst('t');
  FAst.Add(TLzNexFullTextStmt.Create(sgWhere, Idents(['body']),
    TLzNexValue.FromString('hello'), ftNatural));
  AssertAstRaises('firebird');
end;

procedure TFirebirdRandomAndCapabilityTest.DeadlockAndUpdateConflictAreRetryable;
begin

  AssertTrue('deadlock', FFb.IsRetryableError(335544336, ''));
  AssertTrue('update conflict', FFb.IsRetryableError(335544451, ''));
end;

procedure TFirebirdRandomAndCapabilityTest.OtherErrorCodesAreNotRetryableByCode;
begin
  AssertFalse(FFb.IsRetryableError(335544321, ''));
  AssertTrue('still retryable via SQLSTATE', FFb.IsRetryableError(0, '40001'));
end;

initialization
  RegisterTest('firebird', TFirebirdDatePartTest);
  RegisterTest('firebird', TFirebirdRandomAndCapabilityTest);

end.
