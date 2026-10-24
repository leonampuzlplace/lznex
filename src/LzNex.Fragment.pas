unit LzNex.Fragment;

{ TLzNexFragment: texto de SQL e seus binds ANDANDO JUNTOS.

  Essa e a correcao estrutural do knex. La os binds vao num array mutavel
  compartilhado, e a ordem de emissao textual tem que coincidir com a ordem de
  push -- o que obrigou o dialeto PostgreSQL a um comentario avisando do perigo
  de reordenar. Aqui nao ha como reordenar texto sem levar os binds junto. }

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
    // Fragmento vazio. Fragmento vazio e omitido na juncao.
    class function Empty: TLzNexFragment; static;
    // Texto sem nenhum bind (keyword, identificador ja quotado).
    class function Lit(const AText: string): TLzNexFragment; static;
    // Um placeholder '?' com o bind correspondente.
    class function Param(const AValue: TLzNexValue): TLzNexFragment; static;
    // Texto com uma lista de binds ja montada.
    class function Make(const AText: string; const ABindings: TLzNexBindings): TLzNexFragment; static;

    // O SQL do fragmento.
    function Text: string;
    // Os binds, na ordem dos '?' do texto.
    function Bindings: TLzNexBindings;
    // True se nao ha texto.
    function IsEmpty: Boolean;

    // Junta outro fragmento no fim, com separador. Texto e binds
    // andam juntos, entao a ordem posicional nunca se perde.
    function Concat(const AOther: TLzNexFragment; const ASep: string = ' '): TLzNexFragment;
    // Envolve o texto (ex.: parenteses), preservando os binds.
    function Wrap(const ABefore, AAfter: string): TLzNexFragment;
    // Prefixa o texto (ex.: 'where '), preservando os binds.
    function Prefix(const APrefix: string): TLzNexFragment;
  end;

  TLzNexFragments = array of TLzNexFragment;

// Junta fragmentos com separador, omitindo os vazios.
// A ordem dos binds e a ordem dos fragmentos na lista -- e o chamador que
// decide a ordem, nao um efeito colateral.
function JoinFragments(const AItems: TLzNexFragments; const ASep: string = ' '): TLzNexFragment;

// "?, ?, ?" com um bind por valor. Valor nao bindavel
// (identificador, raw, subquery) nao e aceito aqui.
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
