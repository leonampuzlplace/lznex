unit LzNex.Value;

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
    FStr: string;
    FBytes: TBytes;
    FRef: IInterface;
  public

    class function Unset: TLzNexValue; static;

    class function Null: TLzNexValue; static;

    class function FromBoolean(const AValue: Boolean): TLzNexValue; static;

    class function FromInteger(const AValue: Integer): TLzNexValue; static;

    class function FromInt64(const AValue: Int64): TLzNexValue; static;

    class function FromFloat(const AValue: Double): TLzNexValue; static;

    class function FromCurrency(const AValue: Currency): TLzNexValue; static;

    class function FromString(const AValue: string): TLzNexValue; static;

    class function FromBytes(const AValue: TBytes): TLzNexValue; static;

    class function FromDate(const AValue: TDateTime): TLzNexValue; static;

    class function FromTime(const AValue: TDateTime): TLzNexValue; static;

    class function FromDateTime(const AValue: TDateTime): TLzNexValue; static;

    class function Identifier(const AName: string): TLzNexValue; static;

    class function Raw(const ARaw: IInterface): TLzNexValue; static;

    class function SubQuery(const AQuery: IInterface): TLzNexValue; static;

    class operator Implicit(const AValue: Boolean): TLzNexValue;
    class operator Implicit(const AValue: Integer): TLzNexValue;
    class operator Implicit(const AValue: Int64): TLzNexValue;
    class operator Implicit(const AValue: Double): TLzNexValue;
    class operator Implicit(const AValue: Currency): TLzNexValue;
    class operator Implicit(const AValue: string): TLzNexValue;

    property Kind: TLzNexValueKind read FKind;

    function IsUnset: Boolean;

    function IsNull: Boolean;

    function IsBindable: Boolean;

    function AsBoolean: Boolean;
    function AsInt64: Int64;
    function AsFloat: Double;
    function AsCurrency: Currency;
    function AsString: string;
    function AsBytes: TBytes;
    function AsDateTime: TDateTime;

    function Ref: IInterface;

    function Text: string;

    function Describe: string;
  end;

  TLzNexValues = array of TLzNexValue;

  TLzNexNamedValue = record
    Name: string;
    Value: TLzNexValue;
  end;
  TLzNexNamedValues = array of TLzNexNamedValue;

function Vals(const AArgs: array of const): TLzNexNamedValues;

function ValueOf(const AArg: TVarRec): TLzNexValue;

function ValueList(const AArgs: array of const): TLzNexValues;

function StringsToValues(const AItems: array of string): TLzNexValues;

implementation

var
  GValueFmt: TFormatSettings;

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

    vkFloat: Result := FloatToStr(FFloat, GValueFmt);
    vkCurrency: Result := CurrToStr(FCurrency, GValueFmt);
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
      Result := TLzNexValue.FromFloat(AArg.VExtended^);
    vtCurrency:
      Result := TLzNexValue.FromCurrency(AArg.VCurrency^);
    vtInt64:
      Result := TLzNexValue.FromInt64(AArg.VInt64^);
    vtQWord:
      Result := TLzNexValue.FromInt64(Int64(AArg.VQWord^));
    vtString:
      Result := TLzNexValue.FromString(string(AArg.VString^));
    vtAnsiString:
      Result := TLzNexValue.FromString(string(AnsiString(AArg.VAnsiString)));
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
  Result := nil;
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

initialization
  GValueFmt := DefaultFormatSettings;
  GValueFmt.DecimalSeparator := '.';
  GValueFmt.ThousandSeparator := #0;

end.
