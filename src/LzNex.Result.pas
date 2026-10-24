unit LzNex.Result;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  ZDbcIntfs,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Exceptions;

type

  TLzNexKindArray = array of TLzNexValueKind;

  TLzNexRow = class(TInterfacedObject, ILzNexRow)
  private
    FNames: TLzNexStringArray;
    FValues: TLzNexValues;
    function IndexOfName(const AName: string): Integer;
  public
    constructor Create(const ANames: TLzNexStringArray; const AValues: TLzNexValues);

    function Field(const AName: string): TLzNexValue;
    function TryField(const AName: string; out AValue: TLzNexValue): Boolean;
    function FieldAt(const AIndex: Integer): TLzNexValue;
    function Has(const AName: string): Boolean;
    function FieldCount: Integer;
    function FieldName(const AIndex: Integer): string;
    function ToJSON: string;
  end;

  TLzNexResult = class(TInterfacedObject, ILzNexResult)
  private
    FRS: IZResultSet;

    FOwner: IInterface;
    FNames: TLzNexStringArray;
    FKinds: TLzNexKindArray;
    FColCount: Integer;
    FOnRow: Boolean;
    FClosed: Boolean;
    procedure ReadSchema;
    procedure NeedOpen;
    procedure NeedRow;
    function IndexOfName(const AName: string): Integer;

    function ReadColumn(const AIndex: Integer): TLzNexValue;
    function SnapshotValues: TLzNexValues;
  public
    constructor Create(const ARS: IZResultSet; const AOwner: IInterface);
    destructor Destroy; override;

    function Next: Boolean;
    function Field(const AName: string): TLzNexValue;
    function FieldAt(const AIndex: Integer): TLzNexValue;
    function FieldCount: Integer;
    function FieldName(const AIndex: Integer): string;
    function CurrentRow: ILzNexRow;
    function ToRows: TLzNexRowArray;
    function ToJSON: string;
    procedure Close;
  end;

function NewResult(const ARS: IZResultSet; const AOwner: IInterface): ILzNexResult;

function LzNexKindOfSQLType(const AType: TZSQLType): TLzNexValueKind;

function LzNexJSONQuote(const AText: string): string;

function LzNexJSONValue(const AValue: TLzNexValue): string;

function LzNexJSONObject(const ANames: TLzNexStringArray;
  const AValues: TLzNexValues): string;

implementation

const
  B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function NameList(const ANames: TLzNexStringArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ANames) do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + ANames[I];
  end;
  if Result = '' then
    Result := '<none>';
end;

function Base64Of(const ABytes: TBytes): string;
var
  I, N, Rem: Integer;
  A, B, C: Byte;
begin
  Result := '';
  N := Length(ABytes);
  if N = 0 then
    Exit;

  Rem := N mod 3;
  I := 0;
  while I + 2 < N do
  begin
    A := ABytes[I];
    B := ABytes[I + 1];
    C := ABytes[I + 2];
    Result := Result
      + B64_ALPHABET[(A shr 2) + 1]
      + B64_ALPHABET[(((A and $03) shl 4) or (B shr 4)) + 1]
      + B64_ALPHABET[(((B and $0F) shl 2) or (C shr 6)) + 1]
      + B64_ALPHABET[(C and $3F) + 1];
    Inc(I, 3);
  end;

  if Rem = 1 then
  begin
    A := ABytes[N - 1];
    Result := Result
      + B64_ALPHABET[(A shr 2) + 1]
      + B64_ALPHABET[((A and $03) shl 4) + 1]
      + '==';
  end
  else if Rem = 2 then
  begin
    A := ABytes[N - 2];
    B := ABytes[N - 1];
    Result := Result
      + B64_ALPHABET[(A shr 2) + 1]
      + B64_ALPHABET[(((A and $03) shl 4) or (B shr 4)) + 1]
      + B64_ALPHABET[((B and $0F) shl 2) + 1]
      + '=';
  end;
end;

function LzNexJSONQuote(const AText: string): string;
var
  I: Integer;
  Ch: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('"');
    for I := 1 to Length(AText) do
    begin
      Ch := AText[I];
      case Ch of
        '"':  SB.Append('\"');
        '\':  SB.Append('\\');
        #8:   SB.Append('\b');
        #9:   SB.Append('\t');
        #10:  SB.Append('\n');
        #12:  SB.Append('\f');
        #13:  SB.Append('\r');
      else
        if Ch < #32 then
          SB.Append('\u00' + LowerCase(IntToHex(Ord(Ch), 2)))
        else
          SB.Append(Ch);
      end;
    end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function JSONNumber(const AValue: Double): string;
begin
  Result := FloatToStr(AValue);
  Result := StringReplace(Result, ',', '.', [rfReplaceAll]);
end;

function LzNexJSONValue(const AValue: TLzNexValue): string;
begin
  case AValue.Kind of
    vkUnset, vkNull:
      Result := 'null';
    vkBoolean:
      if AValue.AsBoolean then Result := 'true' else Result := 'false';
    vkInteger, vkInt64:
      Result := IntToStr(AValue.AsInt64);
    vkFloat:
      Result := JSONNumber(AValue.AsFloat);
    vkCurrency:
      Result := JSONNumber(AValue.AsCurrency);
    vkBytes:
      Result := LzNexJSONQuote(Base64Of(AValue.AsBytes));
    vkDate:
      Result := LzNexJSONQuote(FormatDateTime('yyyy-mm-dd', AValue.AsDateTime));
    vkTime:
      Result := LzNexJSONQuote(FormatDateTime('hh:nn:ss', AValue.AsDateTime));
    vkDateTime:
      Result := LzNexJSONQuote(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', AValue.AsDateTime));
  else
    Result := LzNexJSONQuote(AValue.AsString);
  end;
end;

function LzNexJSONObject(const ANames: TLzNexStringArray;
  const AValues: TLzNexValues): string;
var
  I, N: Integer;
  SB: TStringBuilder;
begin
  N := Length(ANames);
  if Length(AValues) < N then
    N := Length(AValues);

  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    for I := 0 to N - 1 do
    begin
      if I > 0 then
        SB.Append(',');
      SB.Append(LzNexJSONQuote(ANames[I]));
      SB.Append(':');
      SB.Append(LzNexJSONValue(AValues[I]));
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function LzNexKindOfSQLType(const AType: TZSQLType): TLzNexValueKind;
begin
  case AType of
    stBoolean:
      Result := vkBoolean;
    stByte, stShort, stWord, stSmall, stLongWord, stInteger, stULong, stLong:
      Result := vkInt64;
    stFloat, stDouble:
      Result := vkFloat;
    stCurrency, stBigDecimal:
      Result := vkCurrency;
    stDate:
      Result := vkDate;
    stTime:
      Result := vkTime;
    stTimestamp:
      Result := vkDateTime;
    stBytes, stBinaryStream:
      Result := vkBytes;
    stString, stUnicodeString, stAsciiStream, stUnicodeStream, stGUID:
      Result := vkString;
  else

    Result := vkString;
  end;
end;

constructor TLzNexRow.Create(const ANames: TLzNexStringArray;
  const AValues: TLzNexValues);
begin
  inherited Create;
  FNames := ANames;
  FValues := AValues;
end;

function TLzNexRow.IndexOfName(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNames) do
    if FNames[I] = AName then
      Exit(I);

  for I := 0 to High(FNames) do
    if SameText(FNames[I], AName) then
      Exit(I);
  Result := -1;
end;

function TLzNexRow.Field(const AName: string): TLzNexValue;
var
  Idx: Integer;
begin
  Idx := IndexOfName(AName);
  if Idx < 0 then
    raise ELzNexQuery.CreateFmt(
      Format('Column "%s" does not exist in the row. Columns: %s',
             [AName, NameList(FNames)]), '');
  Result := FValues[Idx];
end;

function TLzNexRow.TryField(const AName: string; out AValue: TLzNexValue): Boolean;
var
  Idx: Integer;
begin
  AValue := TLzNexValue.Unset;
  Idx := IndexOfName(AName);
  Result := Idx >= 0;
  if Result then
    AValue := FValues[Idx];
end;

function TLzNexRow.FieldAt(const AIndex: Integer): TLzNexValue;
begin
  if (AIndex < 0) or (AIndex > High(FValues)) then
    raise ELzNexQuery.CreateFmt(
      Format('Column %d out of range: the row has %d columns',
             [AIndex, Length(FValues)]), '');
  Result := FValues[AIndex];
end;

function TLzNexRow.Has(const AName: string): Boolean;
begin
  Result := IndexOfName(AName) >= 0;
end;

function TLzNexRow.FieldCount: Integer;
begin
  Result := Length(FValues);
end;

function TLzNexRow.FieldName(const AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(FNames)) then
    raise ELzNexQuery.CreateFmt(
      Format('Column %d out of range: the row has %d columns',
             [AIndex, Length(FNames)]), '');
  Result := FNames[AIndex];
end;

function TLzNexRow.ToJSON: string;
begin
  Result := LzNexJSONObject(FNames, FValues);
end;

constructor TLzNexResult.Create(const ARS: IZResultSet; const AOwner: IInterface);
begin
  inherited Create;
  if ARS = nil then
    raise ELzNexQuery.CreateFmt('Nil resultset returned by the driver', '');
  FRS := ARS;
  FOwner := AOwner;
  FOnRow := False;
  FClosed := False;
  ReadSchema;
end;

destructor TLzNexResult.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TLzNexResult.ReadSchema;
var
  Meta: IZResultSetMetadata;
  I: Integer;
  Name_: string;
begin
  FNames := nil;
  FKinds := nil;
  Meta := FRS.GetMetadata;
  FColCount := Meta.GetColumnCount;
  SetLength(FNames, FColCount);
  SetLength(FKinds, FColCount);
  for I := 0 to FColCount - 1 do
  begin

    Name_ := Meta.GetColumnLabel(I + FirstDbcIndex);
    if Name_ = '' then
      Name_ := Meta.GetColumnName(I + FirstDbcIndex);
    FNames[I] := Name_;
    FKinds[I] := LzNexKindOfSQLType(Meta.GetColumnType(I + FirstDbcIndex));
  end;
end;

procedure TLzNexResult.NeedOpen;
begin
  if FClosed then
    raise ELzNexQuery.CreateFmt('Cursor already closed', '');
end;

procedure TLzNexResult.NeedRow;
begin
  NeedOpen;
  if not FOnRow then
    raise ELzNexQuery.CreateFmt(
      'Cursor is not on a row. Call Next before reading a column.', '');
end;

function TLzNexResult.IndexOfName(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FColCount - 1 do
    if FNames[I] = AName then
      Exit(I);
  for I := 0 to FColCount - 1 do
    if SameText(FNames[I], AName) then
      Exit(I);
  Result := -1;
end;

function TLzNexResult.ReadColumn(const AIndex: Integer): TLzNexValue;
var
  Z: Integer;
begin
  Z := AIndex + FirstDbcIndex;
  if FRS.IsNull(Z) then
    Exit(TLzNexValue.Null);

  case FKinds[AIndex] of
    vkBoolean:
      Result := TLzNexValue.FromBoolean(FRS.GetBoolean(Z));
    vkInt64:
      Result := TLzNexValue.FromInt64(FRS.GetLong(Z));
    vkFloat:
      Result := TLzNexValue.FromFloat(FRS.GetDouble(Z));
    vkCurrency:
      Result := TLzNexValue.FromCurrency(FRS.GetCurrency(Z));
    vkDate:
      Result := TLzNexValue.FromDate(FRS.GetDate(Z));
    vkTime:
      Result := TLzNexValue.FromTime(FRS.GetTime(Z));
    vkDateTime:
      Result := TLzNexValue.FromDateTime(FRS.GetTimestamp(Z));
    vkBytes:
      Result := TLzNexValue.FromBytes(FRS.GetBytes(Z));
  else
    Result := TLzNexValue.FromString(FRS.GetString(Z));
  end;
end;

function TLzNexResult.SnapshotValues: TLzNexValues;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, FColCount);
  for I := 0 to FColCount - 1 do
    Result[I] := ReadColumn(I);
end;

function TLzNexResult.Next: Boolean;
begin
  if FClosed then
    Exit(False);
  try
    Result := FRS.Next;
  except
    on E: Exception do
      raise ELzNexQuery.CreateFmt('Failed to advance the cursor: ' + E.Message, '');
  end;
  FOnRow := Result;
end;

function TLzNexResult.Field(const AName: string): TLzNexValue;
var
  Idx: Integer;
begin
  NeedRow;
  Idx := IndexOfName(AName);
  if Idx < 0 then
    raise ELzNexQuery.CreateFmt(
      Format('Column "%s" does not exist in the result. Columns: %s',
             [AName, NameList(FNames)]), '');
  Result := ReadColumn(Idx);
end;

function TLzNexResult.FieldAt(const AIndex: Integer): TLzNexValue;
begin
  NeedRow;
  if (AIndex < 0) or (AIndex >= FColCount) then
    raise ELzNexQuery.CreateFmt(
      Format('Column %d out of range: the result has %d columns',
             [AIndex, FColCount]), '');
  Result := ReadColumn(AIndex);
end;

function TLzNexResult.FieldCount: Integer;
begin
  Result := FColCount;
end;

function TLzNexResult.FieldName(const AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= FColCount) then
    raise ELzNexQuery.CreateFmt(
      Format('Column %d out of range: the result has %d columns',
             [AIndex, FColCount]), '');
  Result := FNames[AIndex];
end;

function TLzNexResult.CurrentRow: ILzNexRow;
begin
  NeedRow;

  Result := TLzNexRow.Create(FNames, SnapshotValues) as ILzNexRow;
end;

function TLzNexResult.ToRows: TLzNexRowArray;
var
  Count_: Integer;
begin
  Result := nil;
  NeedOpen;
  Count_ := 0;

  while FOnRow or Next do
  begin
    if Count_ >= Length(Result) then
    begin
      if Length(Result) = 0 then
        SetLength(Result, 16)
      else
        SetLength(Result, Length(Result) * 2);
    end;
    Result[Count_] := CurrentRow;
    Inc(Count_);
    FOnRow := False;
  end;
  SetLength(Result, Count_);
end;

function TLzNexResult.ToJSON: string;
var
  SB: TStringBuilder;
  First: Boolean;
begin
  NeedOpen;
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    First := True;
    while FOnRow or Next do
    begin
      if not First then
        SB.Append(',');
      SB.Append(LzNexJSONObject(FNames, SnapshotValues));
      First := False;
      FOnRow := False;
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TLzNexResult.Close;
begin
  if FClosed then
    Exit;
  FClosed := True;
  FOnRow := False;
  if FRS <> nil then
  begin
    try
      FRS.Close;
    except

    end;
    FRS := nil;
  end;
  FOwner := nil;
end;

function NewResult(const ARS: IZResultSet; const AOwner: IInterface): ILzNexResult;
begin
  Result := TLzNexResult.Create(ARS, AOwner) as ILzNexResult;
end;

end.
