unit LzNex.Cursor;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Ast,
  LzNex.Exceptions;

type

  TLzNexOrderKey = record
    Column: string;
    Descending: Boolean;
  end;
  TLzNexOrderKeys = array of TLzNexOrderKey;

{ Le a ordenacao da query e devolve as chaves do keyset. Recusa o que o corte
  por valor nao consegue reproduzir: ordem ausente, OrderByRaw e ordem de nulos
  explicita (no MySQL ela e emulada com uma expressao extra que o WHERE nao
  reproduz, e a pagina sairia furada). }
function OrderKeysOf(const AQuery: ILzNexQuery): TLzNexOrderKeys;

// Os valores das colunas de ordenacao numa linha ja lida.
function KeyValuesOf(const ARow: ILzNexRow;
  const AKeys: TLzNexOrderKeys): TLzNexValues;

{ Adiciona o corte "depois desta linha" como um grupo fechado de predicados.
  Com duas chaves sai "(k1 > ? or (k1 = ? and k2 > ?))" -- forma expandida em
  vez de "(k1, k2) > (?, ?)", que o Firebird nao tem. }
procedure ApplyKeyset(const AQuery: ILzNexQuery; const AKeys: TLzNexOrderKeys;
  const AValues: TLzNexValues; const ABackward: Boolean);

// Inverte asc/desc de toda a ordenacao, para ler a pagina anterior.
procedure FlipOrderDirection(const AQuery: ILzNexQuery);

function EncodeCursor(const AValues: TLzNexValues;
  const ABackward: Boolean): string;

// False quando o texto nao e um cursor desta versao ou esta corrompido.
function DecodeCursor(const ACursor: string; out AValues: TLzNexValues;
  out ABackward: Boolean): Boolean;

// Base64 url-safe e sem padding: o cursor viaja em query string.
function LzNexBase64Encode(const ABytes: TBytes): string;
function LzNexBase64Decode(const AText: string; out ABytes: TBytes): Boolean;

implementation

const
  B64_URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  CURSOR_PREFIX = 'lzc1';

  DATE_PATTERN = 'yyyy-mm-dd';
  TIME_PATTERN = 'hh:nn:ss.zzz';
  STAMP_PATTERN = 'yyyy-mm-dd hh:nn:ss.zzz';

var
  // Formato fixo: cursor gerado numa maquina tem de ser lido noutra.
  GFmt: TFormatSettings;

function LzNexBase64Encode(const ABytes: TBytes): string;
var
  I, N: Integer;
  A, B, C: Byte;
  SB: TStringBuilder;
begin
  Result := '';
  N := Length(ABytes);
  if N = 0 then
    Exit;

  SB := TStringBuilder.Create;
  try
    I := 0;
    while I + 2 < N do
    begin
      A := ABytes[I];
      B := ABytes[I + 1];
      C := ABytes[I + 2];
      SB.Append(B64_URL[(A shr 2) + 1]);
      SB.Append(B64_URL[(((A and $03) shl 4) or (B shr 4)) + 1]);
      SB.Append(B64_URL[(((B and $0F) shl 2) or (C shr 6)) + 1]);
      SB.Append(B64_URL[(C and $3F) + 1]);
      Inc(I, 3);
    end;

    case N - I of
      1:
        begin
          A := ABytes[I];
          SB.Append(B64_URL[(A shr 2) + 1]);
          SB.Append(B64_URL[((A and $03) shl 4) + 1]);
        end;
      2:
        begin
          A := ABytes[I];
          B := ABytes[I + 1];
          SB.Append(B64_URL[(A shr 2) + 1]);
          SB.Append(B64_URL[(((A and $03) shl 4) or (B shr 4)) + 1]);
          SB.Append(B64_URL[((B and $0F) shl 2) + 1]);
        end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function B64Value(const ACh: Char): Integer;
begin
  case ACh of
    'A'..'Z': Result := Ord(ACh) - Ord('A');
    'a'..'z': Result := Ord(ACh) - Ord('a') + 26;
    '0'..'9': Result := Ord(ACh) - Ord('0') + 52;
    '-', '+': Result := 62;
    '_', '/': Result := 63;
  else
    Result := -1;
  end;
end;

function LzNexBase64Decode(const AText: string; out ABytes: TBytes): Boolean;
var
  I, N, Bits, Acc, Count_: Integer;
  V: Integer;
begin
  ABytes := nil;
  Result := False;
  N := Length(AText);

  SetLength(ABytes, (N * 3) div 4 + 1);
  Count_ := 0;
  Acc := 0;
  Bits := 0;

  for I := 1 to N do
  begin
    if AText[I] = '=' then
      Break;
    V := B64Value(AText[I]);
    if V < 0 then
    begin
      ABytes := nil;
      Exit(False);
    end;
    Acc := (Acc shl 6) or V;
    Inc(Bits, 6);
    if Bits >= 8 then
    begin
      Dec(Bits, 8);
      ABytes[Count_] := Byte((Acc shr Bits) and $FF);
      Inc(Count_);
    end;
  end;

  SetLength(ABytes, Count_);
  Result := True;
end;

function BytesOfString(const AText: string): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(AText));
  if Length(AText) > 0 then
    Move(AText[1], Result[0], Length(AText));
end;

function StringOfBytes(const ABytes: TBytes): string;
begin
  Result := '';
  SetLength(Result, Length(ABytes));
  if Length(ABytes) > 0 then
    Move(ABytes[0], Result[1], Length(ABytes));
end;

function OrderKeysOf(const AQuery: ILzNexQuery): TLzNexOrderKeys;
var
  Items: TLzNexStatementList;
  Stmt: TLzNexOrderByStmt;
  I: Integer;
begin
  Result := nil;
  if AQuery = nil then
    raise ELzNexBuilder.Create('Cursor pagination without a query');

  Items := AQuery.Ast.Group(sgOrder);
  if Items.Count = 0 then
    raise ELzNexBuilder.Create(
      'CursorPaginate requires at least one OrderBy: the cursor cuts the set ' +
      'by the ordering values, so without an order there is nothing to cut ' +
      'by. Order by a unique column (usually the primary key) last.');

  SetLength(Result, Items.Count);
  for I := 0 to Items.Count - 1 do
  begin
    if Items[I].Kind = skOrderByRaw then
      raise ELzNexBuilder.Create(
        'CursorPaginate does not accept OrderByRaw: the cursor needs a column ' +
        'name to compare against, and raw SQL does not give one. Use OrderBy ' +
        'with a column, or paginate with Paginate/SimplePaginate.');

    Stmt := TLzNexOrderByStmt(Items[I]);
    if Stmt.Expr.Kind <> vkIdentifier then
      raise ELzNexBuilder.Create(
        'CursorPaginate needs plain columns in the OrderBy: the expression ' +
        'found is not an identifier.');
    if Stmt.Nulls <> nlDefault then
      raise ELzNexBuilder.CreateFmt(
        'CursorPaginate does not accept an explicit nulls ordering on "%s": in ' +
        'MySQL it is emulated with an extra sort expression that the cursor ' +
        'WHERE cannot reproduce, so pages would skip rows. Drop the nulls ' +
        'ordering, or order by a NOT NULL column.', [Stmt.Expr.Text]);

    Result[I].Column := Stmt.Expr.Text;
    Result[I].Descending := Stmt.Dir = odDesc;
  end;
end;

// "users.id" no order by chega como "id" no resultado.
function UnqualifiedName(const AName: string): string;
var
  P: Integer;
begin
  Result := AName;
  for P := Length(AName) downto 1 do
    if AName[P] = '.' then
      Exit(Copy(AName, P + 1, Length(AName) - P));
end;

function KeyValuesOf(const ARow: ILzNexRow;
  const AKeys: TLzNexOrderKeys): TLzNexValues;
var
  I: Integer;
  V: TLzNexValue;
begin
  Result := nil;
  if ARow = nil then
    raise ELzNexBuilder.Create('Cursor built from a nil row');

  SetLength(Result, Length(AKeys));
  for I := 0 to High(AKeys) do
  begin
    if ARow.TryField(AKeys[I].Column, V) then
      Result[I] := V
    else if ARow.TryField(UnqualifiedName(AKeys[I].Column), V) then
      Result[I] := V
    else
      raise ELzNexBuilder.CreateFmt(
        'CursorPaginate cannot build the cursor: the order column "%s" is not ' +
        'in the result. Add it to the Select (the cursor carries its value), ' +
        'or order by a column that is selected.', [AKeys[I].Column]);
  end;
end;

function KeysetOperator(const ADescending, ABackward: Boolean): string;
begin
  { asc indo para frente e desc voltando procuram valor maior; os outros dois
    casos procuram menor. }
  if ADescending = ABackward then
    Result := '>'
  else
    Result := '<';
end;

procedure ApplyKeyset(const AQuery: ILzNexQuery; const AKeys: TLzNexOrderKeys;
  const AValues: TLzNexValues; const ABackward: Boolean);
var
  I, J: Integer;
begin
  if AQuery = nil then
    raise ELzNexBuilder.Create('Keyset on a nil query');
  if Length(AKeys) = 0 then
    raise ELzNexBuilder.Create('Keyset without order keys');
  if Length(AValues) <> Length(AKeys) then
    raise ELzNexBuilder.CreateFmt(
      'The cursor carries %d value(s) but the query orders by %d column(s). ' +
      'The cursor belongs to another ordering -- start the listing again.',
      [Length(AValues), Length(AKeys)]);

  for I := 0 to High(AValues) do
    if AValues[I].IsNull then
      raise ELzNexBuilder.CreateFmt(
        'The cursor carries NULL for "%s", and a comparison against NULL is ' +
        'never true, so the next page would come back empty. Order by a NOT ' +
        'NULL column, or use Paginate/SimplePaginate.', [AKeys[I].Column]);

  AQuery.WhereOpen;
  try
    for I := 0 to High(AKeys) do
    begin
      if I = 0 then
        AQuery.WhereOpen
      else
        AQuery.OrWhereOpen;

      // Empate em todas as chaves anteriores, e desempate na chave corrente.
      for J := 0 to I - 1 do
        AQuery.Where(AKeys[J].Column, '=', AValues[J]);
      AQuery.Where(AKeys[I].Column,
        KeysetOperator(AKeys[I].Descending, ABackward), AValues[I]);

      AQuery.WhereClose;
    end;
  finally
    AQuery.WhereClose;
  end;
end;

procedure FlipOrderDirection(const AQuery: ILzNexQuery);
var
  Items: TLzNexStatementList;
  Stmt: TLzNexOrderByStmt;
  I: Integer;
begin
  Items := AQuery.Ast.Group(sgOrder);
  for I := 0 to Items.Count - 1 do
  begin
    if Items[I].Kind = skOrderByRaw then
      Continue;
    Stmt := TLzNexOrderByStmt(Items[I]);
    if Stmt.Dir = odAsc then
      Stmt.Dir := odDesc
    else
      Stmt.Dir := odAsc;
  end;
end;

function KindTag(const AValue: TLzNexValue): Char;
begin
  case AValue.Kind of
    vkNull: Result := 'n';
    vkBoolean: Result := 'b';
    vkInteger, vkInt64: Result := 'i';
    vkFloat: Result := 'f';
    vkCurrency: Result := 'c';
    vkString: Result := 's';
    vkDate: Result := 'd';
    vkTime: Result := 't';
    vkDateTime: Result := 'm';
  else
    raise ELzNexBuilder.CreateFmt(
      'A %s cannot travel in a cursor: order by a column whose value is a ' +
      'number, a text or a date.', [AValue.Describe]);
  end;
end;

function PayloadOf(const AValue: TLzNexValue): string;
begin
  case AValue.Kind of
    vkNull: Result := '';
    vkBoolean:
      if AValue.AsBoolean then Result := '1' else Result := '0';
    vkInteger, vkInt64: Result := IntToStr(AValue.AsInt64);
    vkFloat: Result := FloatToStr(AValue.AsFloat, GFmt);
    vkCurrency: Result := CurrToStr(AValue.AsCurrency, GFmt);
    vkString: Result := AValue.AsString;
    vkDate: Result := FormatDateTime(DATE_PATTERN, AValue.AsDateTime, GFmt);
    vkTime: Result := FormatDateTime(TIME_PATTERN, AValue.AsDateTime, GFmt);
    vkDateTime: Result := FormatDateTime(STAMP_PATTERN, AValue.AsDateTime, GFmt);
  else
    Result := '';
  end;
end;

// Numero em posicao fixa. Levanta se nao for digito -- cursor adulterado.
function DigitsAt(const AText: string; const AStart, ACount: Integer): Word;
var
  I: Integer;
begin
  Result := 0;
  if AStart + ACount - 1 > Length(AText) then
    raise ELzNexBuilder.Create('Truncated date in cursor');
  for I := AStart to AStart + ACount - 1 do
  begin
    if (AText[I] < '0') or (AText[I] > '9') then
      raise ELzNexBuilder.Create('Non numeric date in cursor');
    Result := Result * 10 + Word(Ord(AText[I]) - Ord('0'));
  end;
end;

{ Data e hora sao lidas por posicao, nao por StrToDate: o formato e escrito
  aqui mesmo, e depender do locale faria um cursor gerado num servidor ser
  ilegivel noutro. }
function ParseDatePart(const AText: string): TDateTime;
begin
  Result := EncodeDate(DigitsAt(AText, 1, 4), DigitsAt(AText, 6, 2),
    DigitsAt(AText, 9, 2));
end;

function ParseTimePart(const AText: string; const AOffset: Integer): TDateTime;
begin
  Result := EncodeTime(DigitsAt(AText, AOffset, 2),
    DigitsAt(AText, AOffset + 3, 2), DigitsAt(AText, AOffset + 6, 2),
    DigitsAt(AText, AOffset + 9, 3));
end;

function ValueOfPayload(const ATag: Char; const APayload: string): TLzNexValue;
begin
  case ATag of
    'n': Result := TLzNexValue.Null;
    'b': Result := TLzNexValue.FromBoolean(APayload = '1');
    'i': Result := TLzNexValue.FromInt64(StrToInt64(APayload));
    'f': Result := TLzNexValue.FromFloat(StrToFloat(APayload, GFmt));
    'c': Result := TLzNexValue.FromCurrency(StrToCurr(APayload, GFmt));
    's': Result := TLzNexValue.FromString(APayload);
    'd': Result := TLzNexValue.FromDate(ParseDatePart(APayload));
    't': Result := TLzNexValue.FromTime(ParseTimePart(APayload, 1));
    'm': Result := TLzNexValue.FromDateTime(
           ParseDatePart(APayload) + ParseTimePart(APayload, 12));
  else
    raise ELzNexBuilder.CreateFmt('Unknown value tag "%s" in cursor', [ATag]);
  end;
end;

function EncodeCursor(const AValues: TLzNexValues;
  const ABackward: Boolean): string;
var
  SB: TStringBuilder;
  I: Integer;
  Payload: string;
  Dir: string;
begin
  if Length(AValues) = 0 then
    raise ELzNexBuilder.Create('Cursor without values');

  if ABackward then
    Dir := 'b'
  else
    Dir := 'f';

  SB := TStringBuilder.Create;
  try
    SB.Append(CURSOR_PREFIX);
    SB.Append(';');
    SB.Append(Dir);
    SB.Append(';');
    SB.Append(IntToStr(Length(AValues)));

    { "tag,tamanho,dados": o tamanho resolve dados que contenham o proprio
      separador, sem precisar de escape. }
    for I := 0 to High(AValues) do
    begin
      Payload := PayloadOf(AValues[I]);
      SB.Append(';');
      SB.Append(KindTag(AValues[I]));
      SB.Append(',');
      SB.Append(IntToStr(Length(Payload)));
      SB.Append(',');
      SB.Append(Payload);
    end;

    Result := LzNexBase64Encode(BytesOfString(SB.ToString));
  finally
    SB.Free;
  end;
end;

function DecodeCursor(const ACursor: string; out AValues: TLzNexValues;
  out ABackward: Boolean): Boolean;
var
  Raw: TBytes;
  Text_: string;
  Pos_, Len, N, I, PayloadLen: Integer;
  Field: string;
  Tag: Char;

  // Le ate o proximo ';' e deixa Pos_ depois dele.
  function NextField(out AField: string): Boolean;
  var
    Start: Integer;
  begin
    if Pos_ > Len then
      Exit(False);
    Start := Pos_;
    while (Pos_ <= Len) and (Text_[Pos_] <> ';') do
      Inc(Pos_);
    AField := Copy(Text_, Start, Pos_ - Start);
    if Pos_ <= Len then
      Inc(Pos_);
    Result := True;
  end;

  // Le "tag,tamanho," e devolve os dados crus com o tamanho declarado.
  function NextValue(out AValue: TLzNexValue): Boolean;
  var
    Start: Integer;
    LenText: string;
  begin
    AValue := TLzNexValue.Null;
    if Pos_ + 2 > Len then
      Exit(False);
    Tag := Text_[Pos_];
    Inc(Pos_);
    if (Pos_ > Len) or (Text_[Pos_] <> ',') then
      Exit(False);
    Inc(Pos_);

    Start := Pos_;
    while (Pos_ <= Len) and (Text_[Pos_] <> ',') do
      Inc(Pos_);
    if Pos_ > Len then
      Exit(False);
    LenText := Copy(Text_, Start, Pos_ - Start);
    Inc(Pos_);

    if not TryStrToInt(LenText, PayloadLen) then
      Exit(False);
    if (PayloadLen < 0) or (Pos_ + PayloadLen - 1 > Len) then
      Exit(False);

    AValue := ValueOfPayload(Tag, Copy(Text_, Pos_, PayloadLen));
    Inc(Pos_, PayloadLen);

    // Depois dos dados vem ';' ou o fim do texto.
    if Pos_ <= Len then
    begin
      if Text_[Pos_] <> ';' then
        Exit(False);
      Inc(Pos_);
    end;
    Result := True;
  end;

begin
  AValues := nil;
  ABackward := False;

  if Trim(ACursor) = '' then
    Exit(False);
  if not LzNexBase64Decode(ACursor, Raw) then
    Exit(False);

  Text_ := StringOfBytes(Raw);
  Len := Length(Text_);
  Pos_ := 1;

  try
    if not NextField(Field) then
      Exit(False);
    if Field <> CURSOR_PREFIX then
      Exit(False);

    if not NextField(Field) then
      Exit(False);
    if Field = 'b' then
      ABackward := True
    else if Field <> 'f' then
      Exit(False);

    if not NextField(Field) then
      Exit(False);
    if not TryStrToInt(Field, N) then
      Exit(False);
    if (N <= 0) or (N > 16) then
      Exit(False);

    SetLength(AValues, N);
    for I := 0 to N - 1 do
      if not NextValue(AValues[I]) then
      begin
        AValues := nil;
        Exit(False);
      end;

    // Sobra depois do ultimo valor significa texto adulterado.
    Result := Pos_ > Len;
    if not Result then
      AValues := nil;
  except
    on E: Exception do
    begin
      { Conversao de numero ou data falhou: e cursor invalido, nao erro de
        programa. Quem chamou transforma isso em mensagem ao usuario. }
      AValues := nil;
      Result := False;
    end;
  end;
end;

initialization
  GFmt := DefaultFormatSettings;
  GFmt.DecimalSeparator := '.';
  GFmt.ThousandSeparator := #0;
  GFmt.DateSeparator := '-';
  GFmt.TimeSeparator := ':';
  GFmt.ShortDateFormat := DATE_PATTERN;
  GFmt.LongDateFormat := DATE_PATTERN;
  GFmt.ShortTimeFormat := TIME_PATTERN;
  GFmt.LongTimeFormat := TIME_PATTERN;

end.
