unit LzNex.Raw;

{ TLzNexRaw: template de SQL cru resolvido contra um dialeto.

  Gramatica do template (copiada do knex):

    ?        valor         -> placeholder do dialeto + bind
    ??       identificador -> WrapQualified, sem bind
    \?       um '?' literal, nao consome argumento
    \:       um ':' literal
    :nome    valor nomeado         -> placeholder + bind
    :nome:   identificador nomeado -> WrapQualified

  Build devolve TLzNexFragment, logo texto e binds saem JUNTOS e na mesma ordem:
  nao existe a janela de erro do knex, onde o array de binds e separado do texto.

  A contagem e validada ANTES de montar nada: argumento sobrando ou faltando e
  erro de programacao, nunca um '?' sem bind chegando no banco. }

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
    // Conta os '?'/'??' do template, pulando os escapados.
    function CountPositional: Integer;
    // Escreve um valor: bind, identificador quotado, raw aninhado ou subquery.
    procedure EmitValue(const AClient: ILzNexClient; const AValue: TLzNexValue;
      const ASB: TStringBuilder; var ABinds: TLzNexBindings);
  public
    constructor Create(const ASQL: string; const AArgs: TLzNexValues;
      const ANamed: TLzNexNamedValues);
    function Build(const AClient: ILzNexClient): TLzNexFragment;
    function Template: string;
  end;

// Cria um raw com argumentos posicionais ('?' e '??').
function LzNexRaw(const ASQL: string; const AArgs: array of const): ILzNexRaw;

// Mesma coisa, com a lista de valores ja normalizada. Util para repassar
// valores que vieram de outro ponto da API sem voltar para array of const.
function LzNexRawValues(const ASQL: string; const AValues: TLzNexValues): ILzNexRaw;

// Cria um raw com argumentos nomeados (':nome' e ':nome:').
// Monte os pares com Vals(['nome', valor, ...]).
function LzNexRawNamed(const ASQL: string; const ANamed: TLzNexNamedValues): ILzNexRaw;

implementation

// Caractere aceito dentro de um nome de parametro nomeado.
function IsNameChar(const AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or
            ((AChar >= 'A') and (AChar <= 'Z')) or
            ((AChar >= '0') and (AChar <= '9')) or
            (AChar = '_');
end;

{ TLzNexRaw }

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

function TLzNexRaw.CountPositional: Integer;
var
  I, L: Integer;
begin
  Result := 0;
  L := Length(FSQL);
  I := 1;
  while I <= L do
  begin
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
      // Identificador entregue num '?': sai quotado, sem bind.
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
    // Placeholder recebe a posicao 1-based: dialeto com $n sabe se virar.
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
      Ch := FSQL[I];

      // '\?' e '\:' viram o caractere literal.
      if (Ch = '\') and (I < L) and ((FSQL[I + 1] = '?') or (FSQL[I + 1] = ':')) then
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

{ helpers de modulo }

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
