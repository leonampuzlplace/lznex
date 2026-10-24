unit Test.Helper;

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
  LzNex.Client,
  LzNex.Query,
  LzNex.Client.MySQL;

type
  TLzNexTestCase = class(TTestCase)
  protected
    FClient: ILzNexClient;
    procedure SetUp; override;
    procedure TearDown; override;

    function NewTestQuery: ILzNexQuery;
    procedure AssertSQL(const AExpected: string; const AQuery: ILzNexQuery);
    procedure AssertBindings(const AExpected: string; const AQuery: ILzNexQuery);
    procedure AssertQuery(const AExpectedSQL, AExpectedBindings: string;
      const AQuery: ILzNexQuery);

    function BindingsOf(const AFragment: TLzNexFragment): string;
  end;

implementation

procedure TLzNexTestCase.SetUp;
begin
  inherited SetUp;
  FClient := CreateClient('mysql');
end;

procedure TLzNexTestCase.TearDown;
begin
  FClient := nil;
  inherited TearDown;
end;

function TLzNexTestCase.NewTestQuery: ILzNexQuery;
begin
  Result := NewQuery(FClient);
end;

function TLzNexTestCase.BindingsOf(const AFragment: TLzNexFragment): string;
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

procedure TLzNexTestCase.AssertSQL(const AExpected: string; const AQuery: ILzNexQuery);
begin
  AssertEquals('generated SQL', AExpected, AQuery.ToSQL.Text);
end;

procedure TLzNexTestCase.AssertBindings(const AExpected: string;
  const AQuery: ILzNexQuery);
begin
  AssertEquals('bindings', AExpected, BindingsOf(AQuery.ToSQL));
end;

procedure TLzNexTestCase.AssertQuery(const AExpectedSQL, AExpectedBindings: string;
  const AQuery: ILzNexQuery);
var
  Fragment: TLzNexFragment;
begin
  Fragment := AQuery.ToSQL;
  AssertEquals('generated SQL', AExpectedSQL, Fragment.Text);
  AssertEquals('bindings', AExpectedBindings, BindingsOf(Fragment));
end;

end.
