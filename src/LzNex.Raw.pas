unit LzNex.Raw;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Exceptions;

type
  TLzNexRaw = class(TInterfacedObject, ILzNexRaw)
  private
    FSQL: string;
    FArgs: TLzNexValues;
    FNamed: TLzNexNamedValues;

    function TakeInert(var AI: Integer; const ASB: TStringBuilder): Boolean;

    function CountPositional: Integer;

    procedure EmitValue(const AClient: ILzNexClient; const AValue: TLzNexValue;
      const ASB: TStringBuilder; var ABinds: TLzNexBindings);
  public
    constructor Create(const ASQL: string; const AArgs: TLzNexValues;
      const ANamed: TLzNexNamedValues);
    function Build(const AClient: ILzNexClient): TLzNexFragment;
    function Template: string;
  end;

function LzNexRaw(const ASQL: string; const AArgs: array of const): ILzNexRaw;

function LzNexRawValues(const ASQL: string; const AValues: TLzNexValues): ILzNexRaw;

function LzNexRawNamed(const ASQL: string; const ANamed: TLzNexNamedValues): ILzNexRaw;

implementation

function IsNameChar(const AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or
            ((AChar >= 'A') and (AChar <= 'Z')) or
            ((AChar >= '0') and (AChar <= '9')) or
            (AChar = '_');
end;

constructor TLzNexRaw.Create(const ASQL: string; const AArgs: TLzNexValues;
  const ANamed: TLzNexNamedValues);
begin
  inherited Create;
  FSQL := ASQL;
  FArgs := Copy(AArgs);
  FNamed := Copy(ANamed);
end;

function TLzNexRaw.Template: string;
begin
  Result := FSQL;
end;

function TLzNexRaw.TakeInert(var AI: Integer; const ASB: TStringBuilder): Boolean;
var
  L: Integer;
  Ch, Closer: Char;

  procedure Put(const AChar: Char);
  begin
    if ASB <> nil then
      ASB.Append(AChar);
  end;

begin
  Result := False;
  L := Length(FSQL);
  Ch := FSQL[AI];

  if (Ch = '-') and (AI < L) and (FSQL[AI + 1] = '-') then
  begin
    while (AI <= L) and (FSQL[AI] <> #10) do
    begin
      Put(FSQL[AI]);
      Inc(AI);
    end;
    Exit(True);
  end;

  if (Ch = '/') and (AI < L) and (FSQL[AI + 1] = '*') then
  begin
    Put('/'); Put('*');
    Inc(AI, 2);
    while AI <= L do
    begin
      if (FSQL[AI] = '*') and (AI < L) and (FSQL[AI + 1] = '/') then
      begin
        Put('*'); Put('/');
        Inc(AI, 2);
        Exit(True);
      end;
      Put(FSQL[AI]);
      Inc(AI);
    end;
    Exit(True);
  end;

  if (Ch <> '''') and (Ch <> '"') and (Ch <> '`') then
    Exit;

  Closer := Ch;
  Put(Ch);
  Inc(AI);
  while AI <= L do
  begin

    if (FSQL[AI] = '\') and (AI < L) and
       ((FSQL[AI + 1] = '?') or (FSQL[AI + 1] = ':')) then
    begin
      Put(FSQL[AI + 1]);
      Inc(AI, 2);
      Continue;
    end;

    if (FSQL[AI] = Closer) and (AI < L) and (FSQL[AI + 1] = Closer) then
    begin
      Put(Closer); Put(Closer);
      Inc(AI, 2);
      Continue;
    end;

    if FSQL[AI] = Closer then
    begin
      Put(Closer);
      Inc(AI);
      Break;
    end;

    Put(FSQL[AI]);
    Inc(AI);
  end;
  Result := True;
end;

function TLzNexRaw.CountPositional: Integer;
var
  I, L: Integer;
begin
  Result := 0;
  L := Length(FSQL);
  I := 1;
  while I <= L do
  begin
    if TakeInert(I, nil) then
      Continue;

    if (FSQL[I] = '\') and (I < L) and ((FSQL[I + 1] = '?') or (FSQL[I + 1] = ':')) then
    begin
      Inc(I, 2);
      Continue;
    end;
    if FSQL[I] = '?' then
    begin
      Inc(Result);
      if (I < L) and (FSQL[I + 1] = '?') then
        Inc(I, 2)
      else
        Inc(I);
      Continue;
    end;
    Inc(I);
  end;
end;

procedure TLzNexRaw.EmitValue(const AClient: ILzNexClient; const AValue: TLzNexValue;
  const ASB: TStringBuilder; var ABinds: TLzNexBindings);
var
  Nested: ILzNexRaw;
  Sub: ILzNexQuery;
  Frag: TLzNexFragment;
begin
  case AValue.Kind of
    vkIdentifier:

      ASB.Append(AClient.WrapQualified(AValue.Text));
    vkRaw:
      begin
        Nested := nil;
        if (AValue.Ref = nil) or
           (AValue.Ref.QueryInterface(ILzNexRaw, Nested) <> 0) then
          raise ELzNexBuilder.Create(
            'Raw: the nested interface does not implement ILzNexRaw');
        Frag := Nested.Build(AClient);
        ASB.Append(Frag.Text);
        ABinds.Append(Frag.Bindings);
      end;
    vkSubQuery:
      begin
        Sub := nil;
        if (AValue.Ref = nil) or
           (AValue.Ref.QueryInterface(ILzNexQuery, Sub) <> 0) then
          raise ELzNexBuilder.Create(
            'Raw: the nested interface does not implement ILzNexQuery');
        Frag := Sub.ToSQL;
        ASB.Append('(');
        ASB.Append(Frag.Text);
        ASB.Append(')');
        ABinds.Append(Frag.Bindings);
      end;
  else

    ASB.Append(AClient.Placeholder(ABinds.Count + 1));
    ABinds.Add(AValue);
  end;
end;

function TLzNexRaw.Build(const AClient: ILzNexClient): TLzNexFragment;
var
  SB: TStringBuilder;
  Binds: TLzNexBindings;
  Used: array of Boolean;
  I, J, K, L, Expected, Taken: Integer;
  ParamName: string;
  Ch: Char;
  IsIdent, Found: Boolean;
  V: TLzNexValue;
begin
  if AClient = nil then
    raise ELzNexBuilder.Create('Raw.Build: dialect not given');

  Expected := CountPositional;
  if Expected <> Length(FArgs) then
    raise ELzNexBuilder.CreateFmt(
      'Raw: the template expected %d positional argument(s) and got %d. ' +
      'Remember that "\?" is a literal and does not consume an argument. SQL: %s',
      [Expected, Length(FArgs), FSQL]);

  Result := TLzNexFragment.Empty;
  Binds := TLzNexBindings.Empty;
  Used := nil;
  SetLength(Used, Length(FNamed));
  Taken := 0;
  L := Length(FSQL);

  SB := TStringBuilder.Create;
  try
    I := 1;
    while I <= L do
    begin
      if TakeInert(I, SB) then
        Continue;

      Ch := FSQL[I];

      if (Ch = '\') and (I < L) and (FSQL[I + 1] = '?') then
        raise ELzNexBuilder.CreateFmt(
          'Raw: "\?" outside a text literal is not possible. The driver counts ' +
          'every "?" in the SQL as a parameter marker, so a literal "?" here ' +
          'would shift all following bindings by one. For the PostgreSQL jsonb ' +
          'operators use the function form (jsonb_exists / jsonb_exists_any). ' +
          'SQL: %s', [FSQL]);

      if (Ch = '\') and (I < L) and (FSQL[I + 1] = ':') then
      begin
        SB.Append(FSQL[I + 1]);
        Inc(I, 2);
        Continue;
      end;

      if Ch = '?' then
      begin
        IsIdent := (I < L) and (FSQL[I + 1] = '?');
        V := FArgs[Taken];
        Inc(Taken);
        if IsIdent then
        begin
          SB.Append(AClient.WrapQualified(V.AsString));
          Inc(I, 2);
        end
        else
        begin
          EmitValue(AClient, V, SB, Binds);
          Inc(I);
        end;
        Continue;
      end;

      if (Ch = ':') and (I < L) and (FSQL[I + 1] = ':') then
      begin
        SB.Append('::');
        Inc(I, 2);
        Continue;
      end;

      if (Ch = ':') and (I < L) and IsNameChar(FSQL[I + 1]) then
      begin
        J := I + 1;
        while (J <= L) and IsNameChar(FSQL[J]) do
          Inc(J);
        ParamName := Copy(FSQL, I + 1, J - I - 1);
        IsIdent := (J <= L) and (FSQL[J] = ':');

        Found := False;
        V := TLzNexValue.Unset;
        for K := 0 to High(FNamed) do
          if SameText(FNamed[K].Name, ParamName) then
          begin
            V := FNamed[K].Value;
            Used[K] := True;
            Found := True;
            Break;
          end;
        if not Found then
          raise ELzNexBuilder.CreateFmt(
            'Raw: parameter ":%s" was not given (%d named value(s) received). SQL: %s',
            [ParamName, Length(FNamed), FSQL]);

        if IsIdent then
        begin
          SB.Append(AClient.WrapQualified(V.AsString));
          I := J + 1;
        end
        else
        begin
          EmitValue(AClient, V, SB, Binds);
          I := J;
        end;
        Continue;
      end;

      SB.Append(Ch);
      Inc(I);
    end;

    for K := 0 to High(FNamed) do
      if not Used[K] then
        raise ELzNexBuilder.CreateFmt(
          'Raw: named parameter ":%s" does not appear in the template. SQL: %s',
          [FNamed[K].Name, FSQL]);

    Result := TLzNexFragment.Make(SB.ToString, Binds);
  finally
    SB.Free;
  end;
end;

function LzNexRaw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
begin
  Result := TLzNexRaw.Create(ASQL, ValueList(AArgs), nil) as ILzNexRaw;
end;

function LzNexRawValues(const ASQL: string; const AValues: TLzNexValues): ILzNexRaw;
begin
  Result := TLzNexRaw.Create(ASQL, AValues, nil) as ILzNexRaw;
end;

function LzNexRawNamed(const ASQL: string; const ANamed: TLzNexNamedValues): ILzNexRaw;
begin
  Result := TLzNexRaw.Create(ASQL, nil, ANamed) as ILzNexRaw;
end;

end.
