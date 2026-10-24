unit LzNex.Value;

{ TLzNexValue: record com tag que representa qualquer valor que entra numa query.
  Substitui o duck typing do knex (isRawInstance / instanceof) por discriminante
  explicito, e evita Variant no caminho quente.

  Os `class operator Implicit` permitem escrever Where('id', 1) e Where('nome', 'x')
  sem conversao manual. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Exceptions;

type
  TLzNexValue = record
  private
    FKind: TLzNexValueKind;
    FBool: Boolean;
    FInt: Int64;
    FFloat: Double;
    FCurrency: Currency;
    FDateTime: TDateTime;
    FStr: string;          // string, identifier e o texto do raw
    FBytes: TBytes;
    FRef: IInterface;      // ILzNexRaw ou ILzNexQuery -- IInterface evita ciclo de units
  public
    // --- construtores nomeados ---

    // Valor nao informado. Em INSERT vira DEFAULT; em WHERE e erro.
    class function Unset: TLzNexValue; static;
    // NULL explicito.
    class function Null: TLzNexValue; static;
    // Booleano.
    class function FromBoolean(const AValue: Boolean): TLzNexValue; static;
    // Inteiro de 32 bits.
    class function FromInteger(const AValue: Integer): TLzNexValue; static;
    // Inteiro de 64 bits.
    class function FromInt64(const AValue: Int64): TLzNexValue; static;
    // Ponto flutuante.
    class function FromFloat(const AValue: Double): TLzNexValue; static;
    // Monetario (escala fixa, evita erro de arredondamento).
    class function FromCurrency(const AValue: Currency): TLzNexValue; static;
    // Texto.
    class function FromString(const AValue: string): TLzNexValue; static;
    // Binario (BLOB).
    class function FromBytes(const AValue: TBytes): TLzNexValue; static;
    // Somente data.
    class function FromDate(const AValue: TDateTime): TLzNexValue; static;
    // Somente hora.
    class function FromTime(const AValue: TDateTime): TLzNexValue; static;
    // Data e hora.
    class function FromDateTime(const AValue: TDateTime): TLzNexValue; static;
    // Nome de coluna/tabela. NAO gera bind: vai quotado no SQL.
    class function Identifier(const AName: string): TLzNexValue; static;
    // Fragmento de SQL cru (um ILzNexRaw). Nao gera bind por si.
    class function Raw(const ARaw: IInterface): TLzNexValue; static;
    // Subconsulta (um ILzNexQuery). Os binds dela entram na posicao certa.
    class function SubQuery(const AQuery: IInterface): TLzNexValue; static;

    // --- conversao implicita, para a API fluente ficar curta ---
    class operator Implicit(const AValue: Boolean): TLzNexValue;
    class operator Implicit(const AValue: Integer): TLzNexValue;
    class operator Implicit(const AValue: Int64): TLzNexValue;
    class operator Implicit(const AValue: Double): TLzNexValue;
    class operator Implicit(const AValue: Currency): TLzNexValue;
    class operator Implicit(const AValue: string): TLzNexValue;

    // --- consulta ---

    // A tag do valor.
    property Kind: TLzNexValueKind read FKind;
    // True se o valor nunca foi informado.
    function IsUnset: Boolean;
    // True se e NULL explicito.
    function IsNull: Boolean;
    // True se o valor deve virar um placeholder com bind.
    // Identifier, Raw, SubQuery e Unset nao sao bindaveis.
    function IsBindable: Boolean;

    // AsBoolean / AsInt64 / ... — leitura tipada. Levanta se a tag nao bate.
    function AsBoolean: Boolean;
    function AsInt64: Int64;
    function AsFloat: Double;
    function AsCurrency: Currency;
    function AsString: string;
    function AsBytes: TBytes;
    function AsDateTime: TDateTime;
    // A interface guardada (Raw ou SubQuery). nil nos outros casos.
    function Ref: IInterface;
    // O texto bruto de Identifier/String/Raw, sem checar a tag.
    function Text: string;

    // Descricao curta para mensagem de erro e log.
    function Describe: string;
  end;

  TLzNexValues = array of TLzNexValue;

  // Par coluna/valor, usado em INSERT e UPDATE.
  // Preserva a ORDEM de insercao (o knex ordena alfabeticamente, o que surpreende).
  TLzNexNamedValue = record
    Name: string;
    Value: TLzNexValue;
  end;
  TLzNexNamedValues = array of TLzNexNamedValue;

// Converte ['col', valor, 'col2', valor2] em pares nomeados.
// Aceita so primitivos: `array of const` nao transporta record (restricao do FPC).
function Vals(const AArgs: array of const): TLzNexNamedValues;

// Normaliza um elemento de `array of const` para TLzNexValue.
// Trata as armadilhas do TVarRec: vtExtended/vtInt64/vtCurrency guardam PONTEIRO,
// vtAnsiString precisa de cast, e Cardinal > MaxInt chega como vtInteger negativo.
function ValueOf(const AArg: TVarRec): TLzNexValue;

// Converte [1, 2, 'x'] numa lista de valores (para WhereIn, Insert).
function ValueList(const AArgs: array of const): TLzNexValues;

// Converte um array de string em valores.
function StringsToValues(const AItems: array of string): TLzNexValues;

implementation

{ TLzNexValue }

class function TLzNexValue.Unset: TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkUnset;
end;

class function TLzNexValue.Null: TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkNull;
end;

class function TLzNexValue.FromBoolean(const AValue: Boolean): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkBoolean;
  Result.FBool := AValue;
end;

class function TLzNexValue.FromInteger(const AValue: Integer): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkInteger;
  Result.FInt := AValue;
end;

class function TLzNexValue.FromInt64(const AValue: Int64): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkInt64;
  Result.FInt := AValue;
end;

class function TLzNexValue.FromFloat(const AValue: Double): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkFloat;
  Result.FFloat := AValue;
end;

class function TLzNexValue.FromCurrency(const AValue: Currency): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkCurrency;
  Result.FCurrency := AValue;
end;

class function TLzNexValue.FromString(const AValue: string): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkString;
  Result.FStr := AValue;
end;

class function TLzNexValue.FromBytes(const AValue: TBytes): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkBytes;
  Result.FBytes := AValue;
end;

class function TLzNexValue.FromDate(const AValue: TDateTime): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkDate;
  Result.FDateTime := AValue;
end;

class function TLzNexValue.FromTime(const AValue: TDateTime): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkTime;
  Result.FDateTime := AValue;
end;

class function TLzNexValue.FromDateTime(const AValue: TDateTime): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkDateTime;
  Result.FDateTime := AValue;
end;

class function TLzNexValue.Identifier(const AName: string): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkIdentifier;
  Result.FStr := AName;
end;

class function TLzNexValue.Raw(const ARaw: IInterface): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkRaw;
  Result.FRef := ARaw;
end;

class function TLzNexValue.SubQuery(const AQuery: IInterface): TLzNexValue;
begin
  Result := Default(TLzNexValue);
  Result.FKind := vkSubQuery;
  Result.FRef := AQuery;
end;

class operator TLzNexValue.Implicit(const AValue: Boolean): TLzNexValue;
begin
  Result := TLzNexValue.FromBoolean(AValue);
end;

class operator TLzNexValue.Implicit(const AValue: Integer): TLzNexValue;
begin
  Result := TLzNexValue.FromInteger(AValue);
end;

class operator TLzNexValue.Implicit(const AValue: Int64): TLzNexValue;
begin
  Result := TLzNexValue.FromInt64(AValue);
end;

class operator TLzNexValue.Implicit(const AValue: Double): TLzNexValue;
begin
  Result := TLzNexValue.FromFloat(AValue);
end;

class operator TLzNexValue.Implicit(const AValue: Currency): TLzNexValue;
begin
  Result := TLzNexValue.FromCurrency(AValue);
end;

class operator TLzNexValue.Implicit(const AValue: string): TLzNexValue;
begin
  Result := TLzNexValue.FromString(AValue);
end;

function TLzNexValue.IsUnset: Boolean;
begin
  Result := FKind = vkUnset;
end;

function TLzNexValue.IsNull: Boolean;
begin
  Result := FKind = vkNull;
end;

function TLzNexValue.IsBindable: Boolean;
begin
  Result := not (FKind in [vkUnset, vkIdentifier, vkRaw, vkSubQuery]);
end;

function TLzNexValue.AsBoolean: Boolean;
begin
  case FKind of
    vkBoolean: Result := FBool;
    vkInteger, vkInt64: Result := FInt <> 0;
    vkNull, vkUnset: Result := False;
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not a boolean', [Describe]);
  end;
end;

function TLzNexValue.AsInt64: Int64;
begin
  case FKind of
    vkInteger, vkInt64: Result := FInt;
    vkBoolean: Result := Ord(FBool);
    vkFloat: Result := Round(FFloat);
    vkNull, vkUnset: Result := 0;
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not an integer', [Describe]);
  end;
end;

function TLzNexValue.AsFloat: Double;
begin
  case FKind of
    vkFloat: Result := FFloat;
    vkCurrency: Result := FCurrency;
    vkInteger, vkInt64: Result := FInt;
    vkNull, vkUnset: Result := 0;
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not numeric', [Describe]);
  end;
end;

function TLzNexValue.AsCurrency: Currency;
begin
  case FKind of
    vkCurrency: Result := FCurrency;
    vkFloat: Result := FFloat;
    vkInteger, vkInt64: Result := FInt;
    vkNull, vkUnset: Result := 0;
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not a currency value', [Describe]);
  end;
end;

function TLzNexValue.AsString: string;
begin
  case FKind of
    vkString, vkIdentifier: Result := FStr;
    vkBoolean: Result := BoolToStr(FBool, True);
    vkInteger, vkInt64: Result := IntToStr(FInt);
    vkFloat: Result := FloatToStr(FFloat);
    vkCurrency: Result := CurrToStr(FCurrency);
    vkDate: Result := FormatDateTime('yyyy-mm-dd', FDateTime);
    vkTime: Result := FormatDateTime('hh:nn:ss', FDateTime);
    vkDateTime: Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', FDateTime);
    vkNull, vkUnset: Result := '';
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not textual', [Describe]);
  end;
end;

function TLzNexValue.AsBytes: TBytes;
begin
  Result := nil;
  case FKind of
    vkBytes:
      Result := FBytes;
    vkString:
      begin
        // FStr ja guarda os bytes UTF-8; copia crua evita conversao
        // AnsiString->UnicodeString que o TEncoding forcaria.
        SetLength(Result, Length(FStr));
        if Length(FStr) > 0 then
          Move(FStr[1], Result[0], Length(FStr));
      end;
    vkNull, vkUnset:
      Result := nil;
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not binary', [Describe]);
  end;
end;

function TLzNexValue.AsDateTime: TDateTime;
begin
  case FKind of
    vkDate, vkTime, vkDateTime: Result := FDateTime;
    vkNull, vkUnset: Result := 0;
  else
    raise ELzNexBuilder.CreateFmt('TLzNexValue: %s is not a date/time', [Describe]);
  end;
end;

function TLzNexValue.Ref: IInterface;
begin
  Result := FRef;
end;

function TLzNexValue.Text: string;
begin
  Result := FStr;
end;

function TLzNexValue.Describe: string;
begin
  case FKind of
    vkUnset: Result := '<unset>';
    vkNull: Result := 'NULL';
    vkBoolean: Result := 'boolean(' + BoolToStr(FBool, True) + ')';
    vkInteger: Result := 'integer(' + IntToStr(FInt) + ')';
    vkInt64: Result := 'int64(' + IntToStr(FInt) + ')';
    vkFloat: Result := 'float(' + FloatToStr(FFloat) + ')';
    vkCurrency: Result := 'currency(' + CurrToStr(FCurrency) + ')';
    vkString: Result := 'string(' + QuotedStr(FStr) + ')';
    vkBytes: Result := 'bytes(' + IntToStr(Length(FBytes)) + ' B)';
    vkDate: Result := 'date(' + FormatDateTime('yyyy-mm-dd', FDateTime) + ')';
    vkTime: Result := 'time(' + FormatDateTime('hh:nn:ss', FDateTime) + ')';
    vkDateTime: Result := 'datetime(' + FormatDateTime('yyyy-mm-dd hh:nn:ss', FDateTime) + ')';
    vkIdentifier: Result := 'identifier(' + FStr + ')';
    vkRaw: Result := 'raw';
    vkSubQuery: Result := 'subquery';
  else
    Result := '<?>';
  end;
end;

{ helpers de modulo }

function ValueOf(const AArg: TVarRec): TLzNexValue;
begin
  case AArg.VType of
    vtInteger:
      Result := TLzNexValue.FromInteger(AArg.VInteger);
    vtBoolean:
      Result := TLzNexValue.FromBoolean(AArg.VBoolean);
    vtChar:
      Result := TLzNexValue.FromString(string(AArg.VChar));
    vtWideChar:
      Result := TLzNexValue.FromString(string(AArg.VWideChar));
    vtExtended:
      Result := TLzNexValue.FromFloat(AArg.VExtended^);       // ponteiro
    vtCurrency:
      Result := TLzNexValue.FromCurrency(AArg.VCurrency^);    // ponteiro
    vtInt64:
      Result := TLzNexValue.FromInt64(AArg.VInt64^);          // ponteiro
    vtQWord:
      Result := TLzNexValue.FromInt64(Int64(AArg.VQWord^));   // ponteiro
    vtString:
      Result := TLzNexValue.FromString(string(AArg.VString^)); // PShortString
    vtAnsiString:
      Result := TLzNexValue.FromString(string(AnsiString(AArg.VAnsiString))); // cast
    vtUnicodeString:
      Result := TLzNexValue.FromString(string(UnicodeString(AArg.VUnicodeString)));
    vtWideString:
      Result := TLzNexValue.FromString(string(WideString(AArg.VWideString)));
    vtPChar:
      Result := TLzNexValue.FromString(string(AnsiString(AArg.VPChar)));
    vtPWideChar:
      Result := TLzNexValue.FromString(string(WideString(AArg.VPWideChar)));
    vtPointer:
      if AArg.VPointer = nil then
        Result := TLzNexValue.Null
      else
        raise ELzNexBuilder.Create('TLzNexValue: a non-nil pointer is not a valid value');
    vtInterface:
      Result := TLzNexValue.Raw(IInterface(AArg.VInterface));
  else
    raise ELzNexBuilder.CreateFmt(
      'TLzNexValue: unsupported type in array of const (VType=%d). ' +
      'Remember: a record cannot be passed in an array of const.', [AArg.VType]);
  end;
end;

function ValueList(const AArgs: array of const): TLzNexValues;
var
  I: Integer;
begin
  Result := nil;   // Result e tratado como parametro var no FPC: inicializar sempre
  SetLength(Result, Length(AArgs));
  for I := 0 to High(AArgs) do
    Result[I] := ValueOf(AArgs[I]);
end;

function Vals(const AArgs: array of const): TLzNexNamedValues;
var
  I, N: Integer;
begin
  Result := nil;
  if Odd(Length(AArgs)) then
    raise ELzNexBuilder.Create(
      'Vals: expected column/value pairs, got ' + IntToStr(Length(AArgs)) + ' items');

  N := Length(AArgs) div 2;
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Result[I].Name := ValueOf(AArgs[I * 2]).Text;
    if Result[I].Name = '' then
      raise ELzNexBuilder.Create('Vals: empty column name at position ' + IntToStr(I * 2));
    Result[I].Value := ValueOf(AArgs[I * 2 + 1]);
  end;
end;

function StringsToValues(const AItems: array of string): TLzNexValues;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for I := 0 to High(AItems) do
    Result[I] := TLzNexValue.FromString(AItems[I]);
end;

end.
