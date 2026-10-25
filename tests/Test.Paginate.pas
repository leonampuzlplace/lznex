unit Test.Paginate;

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
  LzNex.Exceptions,
  LzNex.Client,
  LzNex.Query,
  LzNex.Cursor,
  Test.Helper;

type

  { O corte do cursor sai expandido ("a > ? or (a = ? and b > ?)") em vez de
    row value, que o Firebird nao tem -- por isso o SQL e identico nos cinco
    bancos e pode ser conferido aqui, num dialeto so. }
  TKeysetTest = class(TLzNexTestCase)
  private
    function Keys(const AQuery: ILzNexQuery): TLzNexOrderKeys;
  published
    procedure SingleAscendingKeyComparesGreater;
    procedure SingleDescendingKeyComparesLess;
    procedure TwoKeysTieOnTheFirstAndBreakOnTheSecond;
    procedure BackwardFlipsEveryComparison;
    procedure BackwardOnDescendingKeyComparesGreater;
    procedure KeysetKeepsThePreviousWhere;
    procedure KeysetEnclosesAWhereWithOr;
    procedure KeysetDoesNotEncloseAWhereWithoutOr;
    procedure NullInTheCursorRaises;
    procedure ValueCountMismatchRaises;
  end;

  TOrderKeysTest = class(TLzNexTestCase)
  published
    procedure WithoutOrderByRaises;
    procedure OrderByRawRaises;
    procedure ExplicitNullsOrderingRaises;
    procedure QualifiedColumnKeepsTheQualifier;
    procedure DescendingIsReported;
  end;

  TCursorCodecTest = class(TTestCase)
  published
    procedure IntegerRoundTrip;
    procedure StringWithSeparatorsRoundTrip;
    procedure EmptyStringRoundTrip;
    procedure DateTimeKeepsMilliseconds;
    procedure DateAndTimeRoundTrip;
    procedure FloatRoundTripIsLocaleIndependent;
    procedure BooleanAndNullRoundTrip;
    procedure BackwardFlagSurvives;
    procedure GarbageIsRejected;
    procedure ForeignBase64IsRejected;
    procedure TruncatedCursorIsRejected;
    procedure EmptyCursorIsRejected;
    procedure CursorIsUrlSafe;
  end;

  TPagingBuilderTest = class(TLzNexTestCase)
  published
    procedure ClearPagingRemovesLimitAndOffset;
    procedure ClearPagingKeepsTheRest;
    procedure ChunkWithoutOrderByRaises;
    procedure ChunkWithZeroSizeRaises;
    procedure ChunkByIdWithoutKeyRaises;
    procedure ChunkByIdDoesNotRequireOrderBy;
    procedure CursorPaginateWithZeroPerPageRaises;
    procedure CursorPaginateWithoutOrderByRaises;
    procedure CursorPaginateWithBrokenCursorRaises;
  end;

implementation

function TKeysetTest.Keys(const AQuery: ILzNexQuery): TLzNexOrderKeys;
begin
  Result := OrderKeysOf(AQuery);
end;

procedure TKeysetTest.SingleAscendingKeyComparesGreater;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').OrderBy('id');
  ApplyKeyset(Q, Keys(Q), ValueList([10]), False);
  AssertQuery('select * from `t` where ((`id` > ?)) order by `id` asc', '10', Q);
end;

procedure TKeysetTest.SingleDescendingKeyComparesLess;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').OrderByDesc('id');
  ApplyKeyset(Q, Keys(Q), ValueList([10]), False);
  AssertQuery('select * from `t` where ((`id` < ?)) order by `id` desc', '10', Q);
end;

procedure TKeysetTest.TwoKeysTieOnTheFirstAndBreakOnTheSecond;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').OrderBy('name').OrderBy('id');
  ApplyKeyset(Q, Keys(Q), ValueList(['bob', 7]), False);
  AssertQuery(
    'select * from `t` where ((`name` > ?) or (`name` = ? and `id` > ?)) ' +
    'order by `name` asc, `id` asc',
    'bob|bob|7', Q);
end;

procedure TKeysetTest.BackwardFlipsEveryComparison;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').OrderBy('name').OrderBy('id');
  ApplyKeyset(Q, Keys(Q), ValueList(['bob', 7]), True);
  AssertQuery(
    'select * from `t` where ((`name` < ?) or (`name` = ? and `id` < ?)) ' +
    'order by `name` asc, `id` asc',
    'bob|bob|7', Q);
end;

procedure TKeysetTest.BackwardOnDescendingKeyComparesGreater;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').OrderByDesc('id');
  ApplyKeyset(Q, Keys(Q), ValueList([10]), True);
  AssertQuery('select * from `t` where ((`id` > ?)) order by `id` desc', '10', Q);
end;

procedure TKeysetTest.KeysetKeepsThePreviousWhere;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').Where('active', True).OrderBy('id');
  ApplyKeyset(Q, Keys(Q), ValueList([10]), False);
  AssertQuery(
    'select * from `t` where `active` = ? and ((`id` > ?)) order by `id` asc',
    'True|10', Q);
end;

{ Sem os parenteses o and do corte ficaria preso ao ultimo ramo do or, o corte
  nao valeria para o primeiro e a pagina seguinte repetiria as mesmas linhas. }
procedure TKeysetTest.KeysetEnclosesAWhereWithOr;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t')
    .Where('kind', 'a')
    .OrWhere('kind', 'b')
    .OrderBy('id');
  ApplyKeyset(Q, Keys(Q), ValueList([10]), False);
  AssertQuery(
    'select * from `t` where (`kind` = ? or `kind` = ?) and ((`id` > ?)) ' +
    'order by `id` asc',
    'a|b|10', Q);
end;

// Tudo em and: somar mais um and nao muda o sentido, e o SQL fica sem sobra.
procedure TKeysetTest.KeysetDoesNotEncloseAWhereWithoutOr;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t')
    .Where('kind', 'a')
    .Where('active', True)
    .OrderBy('id');
  ApplyKeyset(Q, Keys(Q), ValueList([10]), False);
  AssertSQL(
    'select * from `t` where `kind` = ? and `active` = ? and ((`id` > ?)) ' +
    'order by `id` asc', Q);
end;

procedure TKeysetTest.NullInTheCursorRaises;
var
  Q: ILzNexQuery;
  Values: TLzNexValues;
begin
  Q := NewTestQuery.Table('t').OrderBy('id');
  SetLength(Values, 1);
  Values[0] := TLzNexValue.Null;
  try
    ApplyKeyset(Q, Keys(Q), Values, False);
    Fail('expected ELzNexBuilder for a null keyset value');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TKeysetTest.ValueCountMismatchRaises;
var
  Q: ILzNexQuery;
begin
  Q := NewTestQuery.Table('t').OrderBy('name').OrderBy('id');
  try
    ApplyKeyset(Q, Keys(Q), ValueList([1]), False);
    Fail('expected ELzNexBuilder when the cursor has fewer values than keys');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TOrderKeysTest.WithoutOrderByRaises;
begin
  try
    OrderKeysOf(NewTestQuery.Table('t'));
    Fail('expected ELzNexBuilder without an order by');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TOrderKeysTest.OrderByRawRaises;
begin
  try
    OrderKeysOf(NewTestQuery.Table('t').OrderByRaw('id + ?', [1]));
    Fail('expected ELzNexBuilder for a raw order by');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TOrderKeysTest.ExplicitNullsOrderingRaises;
begin
  try
    OrderKeysOf(NewTestQuery.Table('t').OrderBy('score', odAsc, nlLast));
    Fail('expected ELzNexBuilder for an explicit nulls ordering');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TOrderKeysTest.QualifiedColumnKeepsTheQualifier;
var
  K: TLzNexOrderKeys;
begin
  K := OrderKeysOf(NewTestQuery.Table('users').OrderBy('users.id'));
  AssertEquals('key count', 1, Length(K));
  AssertEquals('column', 'users.id', K[0].Column);
end;

procedure TOrderKeysTest.DescendingIsReported;
var
  K: TLzNexOrderKeys;
begin
  K := OrderKeysOf(NewTestQuery.Table('t').OrderBy('a').OrderByDesc('b'));
  AssertEquals('key count', 2, Length(K));
  AssertFalse('first ascending', K[0].Descending);
  AssertTrue('second descending', K[1].Descending);
end;

procedure TCursorCodecTest.IntegerRoundTrip;
var
  Back: TLzNexValues;
  Backward: Boolean;
begin
  AssertTrue('decoded',
    DecodeCursor(EncodeCursor(ValueList([42]), False), Back, Backward));
  AssertEquals('value count', 1, Length(Back));
  AssertEquals('value', 42, Back[0].AsInt64);
  AssertFalse('forward', Backward);
end;

procedure TCursorCodecTest.StringWithSeparatorsRoundTrip;
var
  Back: TLzNexValues;
  Backward: Boolean;
begin
  // ';' e ',' sao os separadores do formato: o tamanho declarado tem de vencer.
  AssertTrue('decoded',
    DecodeCursor(EncodeCursor(ValueList(['a;b,c=2']), False), Back, Backward));
  AssertEquals('value', 'a;b,c=2', Back[0].AsString);
end;

procedure TCursorCodecTest.EmptyStringRoundTrip;
var
  Back: TLzNexValues;
  Backward: Boolean;
begin
  AssertTrue('decoded',
    DecodeCursor(EncodeCursor(ValueList(['']), False), Back, Backward));
  AssertEquals('kind', Ord(vkString), Ord(Back[0].Kind));
  AssertEquals('value', '', Back[0].AsString);
end;

procedure TCursorCodecTest.DateTimeKeepsMilliseconds;
var
  Source, Decoded: TDateTime;
  Values, Back: TLzNexValues;
  Backward: Boolean;
begin
  Source := EncodeDate(2024, 1, 2) + EncodeTime(3, 4, 5, 678);
  SetLength(Values, 1);
  Values[0] := TLzNexValue.FromDateTime(Source);

  AssertTrue('decoded', DecodeCursor(EncodeCursor(Values, False), Back, Backward));
  Decoded := Back[0].AsDateTime;
  AssertEquals('milliseconds survive', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Source),
    FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Decoded));
end;

procedure TCursorCodecTest.DateAndTimeRoundTrip;
var
  Values, Back: TLzNexValues;
  Backward: Boolean;
begin
  SetLength(Values, 2);
  Values[0] := TLzNexValue.FromDate(EncodeDate(2030, 12, 31));
  Values[1] := TLzNexValue.FromTime(EncodeTime(23, 59, 58, 7));

  AssertTrue('decoded', DecodeCursor(EncodeCursor(Values, False), Back, Backward));
  AssertEquals('date', '2030-12-31', FormatDateTime('yyyy-mm-dd', Back[0].AsDateTime));
  AssertEquals('time', '23:59:58.007',
    FormatDateTime('hh:nn:ss.zzz', Back[1].AsDateTime));
end;

procedure TCursorCodecTest.FloatRoundTripIsLocaleIndependent;
var
  Values, Back: TLzNexValues;
  Backward: Boolean;
begin
  SetLength(Values, 1);
  Values[0] := TLzNexValue.FromFloat(1234.5678);

  AssertTrue('decoded', DecodeCursor(EncodeCursor(Values, False), Back, Backward));
  AssertTrue('float survives', Abs(Back[0].AsFloat - 1234.5678) < 0.000001);
end;

procedure TCursorCodecTest.BooleanAndNullRoundTrip;
var
  Values, Back: TLzNexValues;
  Backward: Boolean;
begin
  SetLength(Values, 2);
  Values[0] := TLzNexValue.FromBoolean(True);
  Values[1] := TLzNexValue.Null;

  AssertTrue('decoded', DecodeCursor(EncodeCursor(Values, False), Back, Backward));
  AssertTrue('boolean', Back[0].AsBoolean);
  AssertTrue('null', Back[1].IsNull);
end;

procedure TCursorCodecTest.BackwardFlagSurvives;
var
  Back: TLzNexValues;
  Backward: Boolean;
begin
  AssertTrue('decoded',
    DecodeCursor(EncodeCursor(ValueList([1]), True), Back, Backward));
  AssertTrue('backward', Backward);
end;

procedure TCursorCodecTest.GarbageIsRejected;
var
  Back: TLzNexValues;
  Backward: Boolean;
begin
  AssertFalse('not a cursor', DecodeCursor('nao!e!cursor', Back, Backward));
  AssertEquals('no values', 0, Length(Back));
end;

procedure TCursorCodecTest.ForeignBase64IsRejected;
var
  Back: TLzNexValues;
  Backward: Boolean;
  Bytes: TBytes;
begin
  // Base64 valido, conteudo de outro formato: tem de cair fora pelo prefixo.
  SetLength(Bytes, 5);
  Bytes[0] := Ord('h'); Bytes[1] := Ord('e'); Bytes[2] := Ord('l');
  Bytes[3] := Ord('l'); Bytes[4] := Ord('o');
  AssertFalse('foreign payload',
    DecodeCursor(LzNexBase64Encode(Bytes), Back, Backward));
end;

procedure TCursorCodecTest.TruncatedCursorIsRejected;
var
  Cursor: string;
  Back: TLzNexValues;
  Backward: Boolean;
begin
  Cursor := EncodeCursor(ValueList([123456]), False);
  AssertFalse('truncated',
    DecodeCursor(Copy(Cursor, 1, Length(Cursor) - 3), Back, Backward));
end;

procedure TCursorCodecTest.EmptyCursorIsRejected;
var
  Back: TLzNexValues;
  Backward: Boolean;
begin
  AssertFalse('empty', DecodeCursor('', Back, Backward));
  AssertFalse('blank', DecodeCursor('   ', Back, Backward));
end;

procedure TCursorCodecTest.CursorIsUrlSafe;
var
  Cursor: string;
  I: Integer;
begin
  { O cursor viaja em query string: nada de '+', '/' ou '=' para o cliente ter
    de escapar. }
  Cursor := EncodeCursor(ValueList(['um texto bem maior para forcar padding??']), False);
  for I := 1 to Length(Cursor) do
    AssertFalse('char ' + Cursor[I] + ' needs escaping',
      (Cursor[I] = '+') or (Cursor[I] = '/') or (Cursor[I] = '='));
end;

procedure TPagingBuilderTest.ClearPagingRemovesLimitAndOffset;
begin
  AssertSQL('select * from `t`',
    NewTestQuery.Table('t').Limit(5).Offset(10).ClearPaging);
end;

procedure TPagingBuilderTest.ClearPagingKeepsTheRest;
begin
  AssertQuery('select * from `t` where `a` = ? order by `id` asc', '1',
    NewTestQuery.Table('t').Where('a', 1).OrderBy('id').Page(3, 10).ClearPaging);
end;

procedure TPagingBuilderTest.ChunkWithoutOrderByRaises;
begin
  try
    NewTestQuery.Table('t').Chunk(10);
    Fail('expected ELzNexBuilder: offset chunks need a stable order');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPagingBuilderTest.ChunkWithZeroSizeRaises;
begin
  try
    NewTestQuery.Table('t').OrderBy('id').Chunk(0);
    Fail('expected ELzNexBuilder for chunk size 0');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPagingBuilderTest.ChunkByIdWithoutKeyRaises;
begin
  try
    NewTestQuery.Table('t').ChunkById(10, '');
    Fail('expected ELzNexBuilder without a key column');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPagingBuilderTest.ChunkByIdDoesNotRequireOrderBy;
var
  Chunks: ILzNexChunks;
begin
  // A ordem vem da propria chave, entao nao se exige OrderBy.
  Chunks := NewTestQuery.Table('t').ChunkById(10, 'id');
  AssertTrue('chunks created', Chunks <> nil);
  AssertEquals('nothing read yet', 0, Chunks.ChunkIndex);
end;

procedure TPagingBuilderTest.CursorPaginateWithZeroPerPageRaises;
begin
  try
    NewTestQuery.Table('t').OrderBy('id').CursorPaginate(0);
    Fail('expected ELzNexBuilder for per page 0');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPagingBuilderTest.CursorPaginateWithoutOrderByRaises;
begin
  try
    NewTestQuery.Table('t').CursorPaginate(10);
    Fail('expected ELzNexBuilder without an order by');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPagingBuilderTest.CursorPaginateWithBrokenCursorRaises;
begin
  try
    NewTestQuery.Table('t').OrderBy('id').CursorPaginate(10, 'nao!e!cursor');
    Fail('expected ELzNexBuilder for an invalid cursor');
  except
    on E: ELzNexBuilder do ;
  end;
end;

initialization
  RegisterTest('paginate', TKeysetTest);
  RegisterTest('paginate', TOrderKeysTest);
  RegisterTest('paginate', TCursorCodecTest);
  RegisterTest('paginate', TPagingBuilderTest);

end.
