unit LzNex.Bindings;

{ Lista ordenada de parametros de uma query. Append-only de proposito: a ordem
  dos binds TEM que ser a mesma ordem dos '?' no texto, e append-only torna isso
  impossivel de violar por acidente. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Exceptions;

type
  TLzNexBindings = record
  private
    FItems: TLzNexValues;
    FCount: Integer;
  public
    // Lista vazia.
    class function Empty: TLzNexBindings; static;
    // Lista com um unico valor.
    class function One(const AValue: TLzNexValue): TLzNexBindings; static;
    // Lista a partir de um array de valores.
    class function FromValues(const AValues: TLzNexValues): TLzNexBindings; static;

    // Acrescenta um valor no fim. Rejeita vkUnset: valor nao informado
    // nunca pode virar bind (e o que pega Where('x', obj.campoInexistente)).
    procedure Add(const AValue: TLzNexValue);
    // Acrescenta vários valores, preservando a ordem.
    procedure AddMany(const AValues: TLzNexValues);
    // Concatena outra lista no fim. E assim que os binds de uma
    // subquery entram na posicao textual correta.
    procedure Append(const AOther: TLzNexBindings);

    // Quantidade de binds.
    function Count: Integer;
    // Acesso por indice (0-based).
    function Items(const AIndex: Integer): TLzNexValue;
    // Copia como array.
    function ToValues: TLzNexValues;
    // "[1, 'x', NULL]" para mensagem de erro e log.
    function Describe: string;
  end;

implementation

class function TLzNexBindings.Empty: TLzNexBindings;
begin
  Result := Default(TLzNexBindings);
  Result.FItems := nil;
  Result.FCount := 0;
end;

class function TLzNexBindings.One(const AValue: TLzNexValue): TLzNexBindings;
begin
  Result := TLzNexBindings.Empty;
  Result.Add(AValue);
end;

class function TLzNexBindings.FromValues(const AValues: TLzNexValues): TLzNexBindings;
begin
  Result := TLzNexBindings.Empty;
  Result.AddMany(AValues);
end;

procedure TLzNexBindings.Add(const AValue: TLzNexValue);
begin
  if AValue.IsUnset then
    raise ELzNexBuilder.Create(
      'Unset binding detected. A vkUnset value reached a place where a ' +
      'parameter is expected -- most likely an uninitialized variable.');

  if FCount >= Length(FItems) then
  begin
    if Length(FItems) = 0 then
      SetLength(FItems, 8)
    else
      SetLength(FItems, Length(FItems) * 2);   // crescimento amortizado
  end;
  FItems[FCount] := AValue;
  Inc(FCount);
end;

procedure TLzNexBindings.AddMany(const AValues: TLzNexValues);
var
  I: Integer;
begin
  for I := 0 to High(AValues) do
    Add(AValues[I]);
end;

procedure TLzNexBindings.Append(const AOther: TLzNexBindings);
var
  I: Integer;
begin
  for I := 0 to AOther.FCount - 1 do
    Add(AOther.FItems[I]);
end;

function TLzNexBindings.Count: Integer;
begin
  Result := FCount;
end;

function TLzNexBindings.Items(const AIndex: Integer): TLzNexValue;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise ELzNexBuilder.CreateFmt(
      'Binding out of range: index %d, total %d', [AIndex, FCount]);
  Result := FItems[AIndex];
end;

function TLzNexBindings.ToValues: TLzNexValues;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, FCount);
  for I := 0 to FCount - 1 do
    Result[I] := FItems[I];
end;

function TLzNexBindings.Describe: string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to FCount - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + FItems[I].Describe;
  end;
  Result := Result + ']';
end;

end.
