unit LzNex.Fragment;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings;

type
  TLzNexFragment = record
  private
    FText: string;
    FBindings: TLzNexBindings;
  public

    class function Empty: TLzNexFragment; static;

    class function Lit(const AText: string): TLzNexFragment; static;

    class function Param(const AValue: TLzNexValue): TLzNexFragment; static;

    class function Make(const AText: string; const ABindings: TLzNexBindings): TLzNexFragment; static;

    function Text: string;

    function Bindings: TLzNexBindings;

    function IsEmpty: Boolean;

    function Concat(const AOther: TLzNexFragment; const ASep: string = ' '): TLzNexFragment;

    function Wrap(const ABefore, AAfter: string): TLzNexFragment;

    function Prefix(const APrefix: string): TLzNexFragment;
  end;

  TLzNexFragments = array of TLzNexFragment;

function JoinFragments(const AItems: TLzNexFragments; const ASep: string = ' '): TLzNexFragment;

function PlaceholderList(const AValues: TLzNexValues): TLzNexFragment;

implementation

class function TLzNexFragment.Empty: TLzNexFragment;
begin
  Result := Default(TLzNexFragment);
  Result.FText := '';
  Result.FBindings := TLzNexBindings.Empty;
end;

class function TLzNexFragment.Lit(const AText: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Empty;
  Result.FText := AText;
end;

class function TLzNexFragment.Param(const AValue: TLzNexValue): TLzNexFragment;
begin
  Result := TLzNexFragment.Empty;
  Result.FText := LZNEX_PLACEHOLDER;
  Result.FBindings.Add(AValue);
end;

class function TLzNexFragment.Make(const AText: string;
  const ABindings: TLzNexBindings): TLzNexFragment;
begin
  Result := Default(TLzNexFragment);
  Result.FText := AText;
  Result.FBindings := ABindings;
end;

function TLzNexFragment.Text: string;
begin
  Result := FText;
end;

function TLzNexFragment.Bindings: TLzNexBindings;
begin
  Result := FBindings;
end;

function TLzNexFragment.IsEmpty: Boolean;
begin
  Result := FText = '';
end;

function TLzNexFragment.Concat(const AOther: TLzNexFragment;
  const ASep: string): TLzNexFragment;
begin
  if AOther.IsEmpty then
    Exit(Self);
  if IsEmpty then
    Exit(AOther);

  Result := TLzNexFragment.Empty;
  Result.FText := FText + ASep + AOther.FText;
  Result.FBindings := TLzNexBindings.Empty;
  Result.FBindings.Append(FBindings);
  Result.FBindings.Append(AOther.FBindings);
end;

function TLzNexFragment.Wrap(const ABefore, AAfter: string): TLzNexFragment;
begin
  if IsEmpty then
    Exit(Self);
  Result := TLzNexFragment.Make(ABefore + FText + AAfter, FBindings);
end;

function TLzNexFragment.Prefix(const APrefix: string): TLzNexFragment;
begin
  if IsEmpty then
    Exit(Self);
  Result := TLzNexFragment.Make(APrefix + FText, FBindings);
end;

function JoinFragments(const AItems: TLzNexFragments; const ASep: string): TLzNexFragment;
var
  I: Integer;
  SB: TStringBuilder;
  First: Boolean;
begin
  Result := TLzNexFragment.Empty;
  SB := TStringBuilder.Create;
  try
    First := True;
    for I := 0 to High(AItems) do
    begin
      if AItems[I].IsEmpty then
        Continue;
      if not First then
        SB.Append(ASep);
      SB.Append(AItems[I].Text);
      Result.FBindings.Append(AItems[I].Bindings);
      First := False;
    end;
    Result.FText := SB.ToString;
  finally
    SB.Free;
  end;
end;

function PlaceholderList(const AValues: TLzNexValues): TLzNexFragment;
var
  I: Integer;
  SB: TStringBuilder;
begin
  Result := TLzNexFragment.Empty;
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(AValues) do
    begin
      if I > 0 then
        SB.Append(', ');
      SB.Append(LZNEX_PLACEHOLDER);
      Result.FBindings.Add(AValues[I]);
    end;
    Result.FText := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
