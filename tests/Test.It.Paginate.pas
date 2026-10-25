unit Test.It.Paginate;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  LzNex,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Exceptions,
  Test.It.Config;

type

  { Paginacao contra banco de verdade. O mesmo teste roda nos cinco bancos: o
    que muda e so como o dialeto escreve a janela (LIMIT/OFFSET ou
    OFFSET/FETCH), e o resultado tem de ser identico. }
  TPaginateTest = class(TTestCase)
  protected
    FDb: ILzNex;

    // Estado do Each, que recebe ponteiro de metodo e nao closure.
    FVisited: Integer;
    FFirstTag: string;
    FLastTag: string;
    FStopAfter: Integer;

    procedure SetUp; override;
    procedure TearDown; override;
    function SkipWithoutDatabase: Boolean;
    procedure Seed;
    function TagsOf(const APage: TLzNexRowArray): string;
    function TagCount(const AList: string): Integer;
    function HasRepeatedTag(const AList: string): Boolean;

    procedure VisitRow(const ARow: ILzNexRow; var AStop: Boolean);
  published
    procedure PaginateReportsTotalAndWindow;
    procedure PaginateLastPageIsShorter;
    procedure PaginatePastTheEndIsEmptyButKeepsTheTotal;
    procedure PaginateCountsOnlyWhatTheWhereKeeps;
    procedure PaginateWithGroupByCountsGroupsNotRows;
    procedure PaginateWithDistinctCountsDistinctRows;
    procedure PaginateDoesNotLeaveTheQueryCounting;

    procedure SimplePaginateFlagsMorePages;
    procedure SimplePaginateOnTheLastPageHasNoMore;

    procedure CursorWalksForwardThroughEveryRow;
    procedure CursorWalksBackToThePreviousPage;
    procedure CursorIsStableWhenRowsAppearMidWalk;
    procedure CursorFollowsDescendingOrder;
    procedure CursorBreaksTiesWithTheSecondKey;
    procedure CursorOnAnEmptySetHasNoCursors;
    procedure CursorFromAnotherOrderingIsRejected;

    procedure ChunkVisitsEveryRowOnce;
    procedure ChunkByIdVisitsEveryRowOnce;
    procedure ChunkByIdDoesNotRepeatWhenRowsAppear;
    procedure EachWalksEveryRow;
    procedure EachStopsWhenTheHandlerAsks;
  end;

implementation

const
  PAGING_TABLE = 'it_paging';
  SEED_ROWS = 25;

var
  GTableReady: Boolean = False;

function TPaginateTest.SkipWithoutDatabase: Boolean;
begin
  Result := not ItEnabled;
  if Result then
    Ignore('LZNEX_IT not set: paginate test skipped');
end;

procedure TPaginateTest.SetUp;
begin
  inherited SetUp;
  if not ItEnabled then
    Exit;

  FDb := Connect(ItConfig(4));

  if not GTableReady then
  begin
    FDb.Schema.DropTableIfExists(PAGING_TABLE);
    FDb.Schema.CreateTable(PAGING_TABLE)
      .Increments('id')
      .Str('tag', 60).NotNull
      .Int('score').NotNull
      .Execute;
    GTableReady := True;
  end;
end;

procedure TPaginateTest.TearDown;
begin
  if FDb <> nil then
  begin
    FDb.Shutdown;
    FDb := nil;
  end;
  inherited TearDown;
end;

procedure TPaginateTest.Seed;
var
  I: Integer;
begin
  FDb.Table(PAGING_TABLE).Truncate;
  { Tag com dois digitos para a ordem alfabetica bater com a numerica; score
    repetido de proposito, para o cursor ter empate para desempatar. }
  for I := 1 to SEED_ROWS do
    FDb.Table(PAGING_TABLE).Insert(Vals([
      'tag', Format('row-%.2d', [I]),
      'score', I mod 5]));
end;

function TPaginateTest.TagsOf(const APage: TLzNexRowArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(APage) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + APage[I].Field('tag').AsString;
  end;
end;

function TPaginateTest.TagCount(const AList: string): Integer;
begin
  if AList = '' then
    Exit(0);
  Result := Length(AList.Split([',']));
end;

function TPaginateTest.HasRepeatedTag(const AList: string): Boolean;
var
  Items: TStringArray;
  I, J: Integer;
begin
  Result := False;
  if AList = '' then
    Exit;
  Items := AList.Split([',']);
  for I := 0 to High(Items) do
    for J := I + 1 to High(Items) do
      if Items[I] = Items[J] then
        Exit(True);
end;

procedure TPaginateTest.VisitRow(const ARow: ILzNexRow; var AStop: Boolean);
begin
  Inc(FVisited);
  if FVisited = 1 then
    FFirstTag := ARow.Field('tag').AsString;
  FLastTag := ARow.Field('tag').AsString;
  if (FStopAfter > 0) and (FVisited >= FStopAfter) then
    AStop := True;
end;

procedure TPaginateTest.PaginateReportsTotalAndWindow;
var
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE).OrderBy('tag').Paginate(2, 10);

  AssertEquals('total', SEED_ROWS, Integer(P.Total));
  AssertEquals('rows in the window', 10, P.Count);
  AssertEquals('current page', 2, Integer(P.CurrentPage));
  AssertEquals('last page', 3, Integer(P.LastPage));
  AssertTrue('has more pages', P.HasMorePages);
  AssertEquals('window start', 'row-11', P.Rows[0].Field('tag').AsString);
  AssertEquals('window end', 'row-20', P.Rows[9].Field('tag').AsString);
end;

procedure TPaginateTest.PaginateLastPageIsShorter;
var
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE).OrderBy('tag').Paginate(3, 10);

  AssertEquals('rows on the last page', 5, P.Count);
  AssertFalse('no more pages', P.HasMorePages);
  AssertEquals('first of the tail', 'row-21', P.Rows[0].Field('tag').AsString);
end;

procedure TPaginateTest.PaginatePastTheEndIsEmptyButKeepsTheTotal;
var
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE).OrderBy('tag').Paginate(9, 10);

  AssertTrue('empty window', P.IsEmpty);
  AssertEquals('total still counted', SEED_ROWS, Integer(P.Total));
  AssertEquals('last page', 3, Integer(P.LastPage));
end;

procedure TPaginateTest.PaginateCountsOnlyWhatTheWhereKeeps;
var
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  // score = 0 em 5 das 25 linhas (5, 10, 15, 20 e 25).
  P := FDb.Table(PAGING_TABLE).Where('score', 0).OrderBy('tag').Paginate(1, 2);

  AssertEquals('filtered total', 5, Integer(P.Total));
  AssertEquals('window', 2, P.Count);
  AssertEquals('last page', 3, Integer(P.LastPage));
end;

procedure TPaginateTest.PaginateWithGroupByCountsGroupsNotRows;
var
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { Sem a subquery, o count(*) entraria no group by e devolveria a quantidade
    de linhas do primeiro grupo em vez da quantidade de grupos. }
  P := FDb.Table(PAGING_TABLE)
    .Select(['score'])
    .GroupBy(['score'])
    .OrderBy('score')
    .Paginate(1, 2);

  AssertEquals('groups', 5, Integer(P.Total));
  AssertEquals('window', 2, P.Count);
end;

procedure TPaginateTest.PaginateWithDistinctCountsDistinctRows;
var
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE)
    .Distinct
    .Select(['score'])
    .OrderBy('score')
    .Paginate(1, 10);

  AssertEquals('distinct scores', 5, Integer(P.Total));
  AssertEquals('window', 5, P.Count);
end;

procedure TPaginateTest.PaginateDoesNotLeaveTheQueryCounting;
var
  Q: ILzNexQuery;
  P: TLzNexPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { O count roda num clone. Se vazasse para esta query, a janela voltaria com
    count(*) no lugar das colunas. }
  Q := FDb.Table(PAGING_TABLE).OrderBy('tag');
  P := Q.Paginate(1, 3);

  AssertEquals('window', 3, P.Count);
  AssertTrue('the row still has the tag column', P.Rows[0].Has('tag'));
end;

procedure TPaginateTest.SimplePaginateFlagsMorePages;
var
  P: TLzNexSimplePage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE).OrderBy('tag').SimplePaginate(1, 10);

  AssertEquals('window', 10, P.Count);
  AssertTrue('has more pages', P.HasMorePages);
  AssertEquals('window start', 'row-01', P.Rows[0].Field('tag').AsString);
  AssertEquals('the extra row was dropped', 'row-10',
    P.Rows[9].Field('tag').AsString);
end;

procedure TPaginateTest.SimplePaginateOnTheLastPageHasNoMore;
var
  P: TLzNexSimplePage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE).OrderBy('tag').SimplePaginate(3, 10);

  AssertEquals('window', 5, P.Count);
  AssertFalse('no more pages', P.HasMorePages);
end;

procedure TPaginateTest.CursorWalksForwardThroughEveryRow;
var
  P: TLzNexCursorPage;
  Cursor, Seen: string;
  Pages: Integer;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Cursor := '';
  Seen := '';
  Pages := 0;
  repeat
    P := FDb.Table(PAGING_TABLE).OrderBy('tag').CursorPaginate(7, Cursor);
    if Seen <> '' then
      Seen := Seen + ',';
    Seen := Seen + TagsOf(P.Rows);
    Cursor := P.NextCursor;
    Inc(Pages);
    AssertTrue('runaway cursor walk', Pages <= 10);
  until Cursor = '';

  AssertEquals('pages of 7 for 25 rows', 4, Pages);
  AssertEquals('every row exactly once, in order',
    'row-01,row-02,row-03,row-04,row-05,row-06,row-07,' +
    'row-08,row-09,row-10,row-11,row-12,row-13,row-14,' +
    'row-15,row-16,row-17,row-18,row-19,row-20,row-21,' +
    'row-22,row-23,row-24,row-25', Seen);
end;

procedure TPaginateTest.CursorWalksBackToThePreviousPage;
var
  First, Second, Back: TLzNexCursorPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  First := FDb.Table(PAGING_TABLE).OrderBy('tag').CursorPaginate(5);
  AssertEquals('first page', 'row-01,row-02,row-03,row-04,row-05',
    TagsOf(First.Rows));
  AssertEquals('no previous page on the first one', '', First.PrevCursor);

  Second := FDb.Table(PAGING_TABLE).OrderBy('tag')
    .CursorPaginate(5, First.NextCursor);
  AssertEquals('second page', 'row-06,row-07,row-08,row-09,row-10',
    TagsOf(Second.Rows));
  AssertTrue('second page knows the way back', Second.PrevCursor <> '');

  Back := FDb.Table(PAGING_TABLE).OrderBy('tag')
    .CursorPaginate(5, Second.PrevCursor);
  AssertEquals('back to the first page, in the original order',
    'row-01,row-02,row-03,row-04,row-05', TagsOf(Back.Rows));
end;

procedure TPaginateTest.CursorIsStableWhenRowsAppearMidWalk;
var
  First, Second: TLzNexCursorPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  First := FDb.Table(PAGING_TABLE).OrderBy('tag').CursorPaginate(5);
  AssertEquals('first page', 'row-01,row-02,row-03,row-04,row-05',
    TagsOf(First.Rows));

  { Linha nova no inicio do conjunto. Com offset a janela seguinte andaria uma
    posicao para tras e row-05 apareceria duas vezes; o cursor continua de
    onde parou. }
  FDb.Table(PAGING_TABLE).Insert(Vals(['tag', 'row-00', 'score', 9]));

  Second := FDb.Table(PAGING_TABLE).OrderBy('tag')
    .CursorPaginate(5, First.NextCursor);

  AssertEquals('no repeated row after the insert',
    'row-06,row-07,row-08,row-09,row-10', TagsOf(Second.Rows));
end;

procedure TPaginateTest.CursorFollowsDescendingOrder;
var
  First, Second: TLzNexCursorPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  First := FDb.Table(PAGING_TABLE).OrderByDesc('tag').CursorPaginate(3);
  AssertEquals('first page descending', 'row-25,row-24,row-23',
    TagsOf(First.Rows));

  Second := FDb.Table(PAGING_TABLE).OrderByDesc('tag')
    .CursorPaginate(3, First.NextCursor);
  AssertEquals('second page descending', 'row-22,row-21,row-20',
    TagsOf(Second.Rows));
end;

procedure TPaginateTest.CursorBreaksTiesWithTheSecondKey;
var
  P: TLzNexCursorPage;
  Seen, Cursor: string;
  Pages: Integer;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { score tem cinco valores para vinte e cinco linhas: cortar so por score
    pularia ou repetiria as linhas empatadas. O id desempata. }
  Cursor := '';
  Seen := '';
  Pages := 0;
  repeat
    P := FDb.Table(PAGING_TABLE).OrderBy('score').OrderBy('id')
      .CursorPaginate(4, Cursor);
    if Seen <> '' then
      Seen := Seen + ',';
    Seen := Seen + TagsOf(P.Rows);
    Cursor := P.NextCursor;
    Inc(Pages);
    AssertTrue('runaway cursor walk', Pages <= 12);
  until Cursor = '';

  AssertEquals('every row read', SEED_ROWS, TagCount(Seen));
  AssertFalse('no row read twice', HasRepeatedTag(Seen));
  AssertEquals('ordered by score, ties broken by id',
    'row-05,row-10,row-15,row-20,row-25,' +
    'row-01,row-06,row-11,row-16,row-21,' +
    'row-02,row-07,row-12,row-17,row-22,' +
    'row-03,row-08,row-13,row-18,row-23,' +
    'row-04,row-09,row-14,row-19,row-24', Seen);
end;

procedure TPaginateTest.CursorOnAnEmptySetHasNoCursors;
var
  P: TLzNexCursorPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  P := FDb.Table(PAGING_TABLE).Where('tag', 'no-such-tag').OrderBy('tag')
    .CursorPaginate(5);

  AssertTrue('empty page', P.IsEmpty);
  AssertEquals('no next cursor', '', P.NextCursor);
  AssertEquals('no previous cursor', '', P.PrevCursor);
  AssertFalse('no more pages', P.HasMorePages);
end;

procedure TPaginateTest.CursorFromAnotherOrderingIsRejected;
var
  First: TLzNexCursorPage;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  { Cursor de uma chave numa listagem de duas: tem de recusar, e nao devolver
    uma pagina errada em silencio. }
  First := FDb.Table(PAGING_TABLE).OrderBy('tag').CursorPaginate(5);
  try
    FDb.Table(PAGING_TABLE).OrderBy('score').OrderBy('id')
      .CursorPaginate(5, First.NextCursor);
    Fail('expected ELzNexBuilder for a cursor from another ordering');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPaginateTest.ChunkVisitsEveryRowOnce;
var
  Chunks: ILzNexChunks;
  Seen: string;
  Batches: Integer;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Chunks := FDb.Table(PAGING_TABLE).OrderBy('tag').Chunk(10);
  Seen := '';
  Batches := 0;
  while Chunks.Next do
  begin
    if Seen <> '' then
      Seen := Seen + ',';
    Seen := Seen + TagsOf(Chunks.Rows);
    Inc(Batches);
    AssertTrue('runaway chunk walk', Batches <= 10);
  end;

  AssertEquals('batches of 10 for 25 rows', 3, Batches);
  AssertEquals('rows seen', SEED_ROWS, Integer(Chunks.RowsSeen));
  AssertEquals('every row once', SEED_ROWS, TagCount(Seen));
  AssertFalse('no row read twice', HasRepeatedTag(Seen));
end;

procedure TPaginateTest.ChunkByIdVisitsEveryRowOnce;
var
  Chunks: ILzNexChunks;
  Total, Batches: Integer;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Chunks := FDb.Table(PAGING_TABLE).ChunkById(7, 'id');
  Total := 0;
  Batches := 0;
  while Chunks.Next do
  begin
    Inc(Total, Length(Chunks.Rows));
    Inc(Batches);
    AssertTrue('runaway chunk walk', Batches <= 10);
  end;

  AssertEquals('rows', SEED_ROWS, Total);
  AssertEquals('batches of 7 for 25 rows', 4, Batches);
  AssertEquals('chunk index', 4, Integer(Chunks.ChunkIndex));
end;

procedure TPaginateTest.ChunkByIdDoesNotRepeatWhenRowsAppear;
var
  Chunks: ILzNexChunks;
  Seen: string;
  Batches: Integer;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  Chunks := FDb.Table(PAGING_TABLE).ChunkById(5, 'id');
  Seen := '';
  Batches := 0;
  while Chunks.Next do
  begin
    if Seen <> '' then
      Seen := Seen + ',';
    Seen := Seen + TagsOf(Chunks.Rows);
    Inc(Batches);

    // Linha nova no meio da varredura: a chave cresce, nada se perde.
    if Batches = 1 then
      FDb.Table(PAGING_TABLE).Insert(Vals(['tag', 'row-99', 'score', 9]));
    AssertTrue('runaway chunk walk', Batches <= 12);
  end;

  AssertFalse('no row read twice', HasRepeatedTag(Seen));
  AssertEquals('the row inserted mid walk was read too', SEED_ROWS + 1,
    TagCount(Seen));
end;

procedure TPaginateTest.EachWalksEveryRow;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  FVisited := 0;
  FStopAfter := 0;
  FFirstTag := '';
  FLastTag := '';

  AssertEquals('rows reported', SEED_ROWS,
    Integer(FDb.Table(PAGING_TABLE).Each(VisitRow, 6, 'id')));
  AssertEquals('rows visited', SEED_ROWS, FVisited);
  AssertEquals('first visited', 'row-01', FFirstTag);
  AssertEquals('last visited', 'row-25', FLastTag);
end;

procedure TPaginateTest.EachStopsWhenTheHandlerAsks;
begin
  if SkipWithoutDatabase then Exit;
  Seed;

  FVisited := 0;
  FStopAfter := 3;
  FFirstTag := '';
  FLastTag := '';

  FDb.Table(PAGING_TABLE).Each(VisitRow, 10, 'id');

  AssertEquals('stopped right away', 3, FVisited);
  AssertEquals('last visited', 'row-03', FLastTag);
end;

initialization
  RegisterTest('integration', TPaginateTest);

end.
