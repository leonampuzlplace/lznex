unit LzNex.Compiler;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Client,
  LzNex.Exceptions;

type

  TLzNexFragBuf = record
  private
    FItems: TLzNexFragments;
    FCount: Integer;
  public

    procedure Clear;

    procedure Add(const AFrag: TLzNexFragment);

    function Count: Integer;

    function Join(const ASep: string = ' '): TLzNexFragment;
  end;

  TLzNexCompilerBase = class(TInterfacedObject, ILzNexCompiler)
  protected
    FClient: ILzNexClient;
    FAst: TLzNexAst;

    function ComponentName(const AComponent: TLzNexComponent): string; virtual;
    function MethodName(const AMethod: TLzNexQueryMethod): string; virtual;

    function Txt(const AText: string): TLzNexFragment;

    function Wrapped(const AFrag: TLzNexFragment): TLzNexFragment;

    function Ident(const AName: string): string;

    function IdentList(const ANames: TLzNexStringArray): string;

    function IdentListV(const AValues: TLzNexValues): string;
    function BoolWord(const AOp: TLzNexBoolOp): string;
    function DirWord(const ADir: TLzNexOrderDir): string;
    function NullsWord(const ANulls: TLzNexNullsOrder): string;
    function AggWord(const AAgg: TLzNexAggregate): string;
    function JoinTypeSQL(const AType: TLzNexJoinType): string; virtual;
    function UnionWord(const AKind: TLzNexUnionKind): string; virtual;

    function LikeOperator(const ACaseInsensitive, ANegated: Boolean): string; virtual;

    function RawFragment(const ARef: IInterface; const AWhere: string): TLzNexFragment;

    function SubFragment(const ARef: IInterface; const AWhere: string): TLzNexFragment;

    function CompileExpr(const AValue: TLzNexValue; const AWhere: string): TLzNexFragment; virtual;

    function CompileIdent(const AValue: TLzNexValue; const AWhere: string): TLzNexFragment; virtual;

    function CompileBind(const AValue: TLzNexValue; const AColumn: string): TLzNexFragment; virtual;

    function CompileBindList(const AValues: TLzNexValues; const AColumn: string): TLzNexFragment; virtual;

    procedure ValidateComponents(const AMethod: TLzNexQueryMethod); virtual;

    function HasComponent(const AComponent: TLzNexComponent): Boolean; virtual;

    function CompileSelect: TLzNexFragment; virtual;
    function CompileInsert: TLzNexFragment; virtual;
    function CompileUpdate: TLzNexFragment; virtual;
    function CompileDelete: TLzNexFragment; virtual;
    function CompileTruncate: TLzNexFragment; virtual;

    function CompileComponent(const AComponent: TLzNexComponent): TLzNexFragment; virtual;

    function CompileComponents(const AMethod: TLzNexQueryMethod;
      const ASkip: TLzNexComponents): TLzNexFragment;

    function CompileWith: TLzNexFragment; virtual;
    function CompileHints: TLzNexFragment; virtual;
    function CompileColumns: TLzNexFragment; virtual;
    function CompileFrom: TLzNexFragment; virtual;
    function CompileJoins: TLzNexFragment; virtual;
    function CompileWhere: TLzNexFragment; virtual;
    function CompileGroup: TLzNexFragment; virtual;
    function CompileHaving: TLzNexFragment; virtual;
    function CompileUnion: TLzNexFragment; virtual;
    function CompileOrder: TLzNexFragment; virtual;

    function CompileLimitPrefix: TLzNexFragment; virtual;
    function CompileLimit: TLzNexFragment; virtual;
    function CompileOffset: TLzNexFragment; virtual;
    function CompileLock: TLzNexFragment; virtual;
    function CompileReturning: TLzNexFragment; virtual;

    function CompileColumn(const AStmt: TLzNexColumnStmt): TLzNexFragment; virtual;
    function CompileAggregate(const AStmt: TLzNexAggregateStmt): TLzNexFragment; virtual;
    function CompileDistinct(const AStmt: TLzNexDistinctStmt): TLzNexFragment; virtual;

    function Aliased(const AFrag: TLzNexFragment; const AAlias: string): TLzNexFragment;

    function CompileTarget: TLzNexFragment; virtual;

    function CompileJoin(const AStmt: TLzNexJoinStmt): TLzNexFragment; virtual;
    function CompileJoinTarget(const AStmt: TLzNexJoinStmt): TLzNexFragment; virtual;
    function CompileJoinClauses(const AClauses: TLzNexJoinClauseList): TLzNexFragment; virtual;
    function CompileJoinClause(const AClause: TLzNexJoinClause): TLzNexFragment; virtual;

    function CompilePredicate(const AStmt: TLzNexStatement): TLzNexFragment; virtual;
    function CompileWhereBasic(const AStmt: TLzNexBasicStmt): TLzNexFragment; virtual;
    function CompileWhereIn(const AStmt: TLzNexInStmt): TLzNexFragment; virtual;
    function CompileWhereNull(const AStmt: TLzNexNullStmt): TLzNexFragment; virtual;
    function CompileWhereBetween(const AStmt: TLzNexBetweenStmt): TLzNexFragment; virtual;
    function CompileWhereLike(const AStmt: TLzNexLikeStmt): TLzNexFragment; virtual;
    function CompileWhereExists(const AStmt: TLzNexExistsStmt): TLzNexFragment; virtual;
    function CompileWhereRaw(const AStmt: TLzNexRawStmt): TLzNexFragment; virtual;
    function CompileWhereGroup(const AStmt: TLzNexGroupStmt): TLzNexFragment; virtual;

    { O que envolve a coluna para extrair a parte da data. A base usa o ANSI
      (cast e extract); quem tem funcao propria sobrescreve. }
    procedure DatePartWrap(const APart: TLzNexDatePart;
      out ABefore, AAfter: string); virtual;
    function CompileWhereDatePart(const AStmt: TLzNexDatePartStmt): TLzNexFragment; virtual;

    { JSON e texto completo nao tem forma portavel: a base recusa, e cada
      dialeto que suporta escreve a sua. O builder ja barra antes pelas
      capacidades do client, isto aqui e a rede de seguranca. }
    function CompileWhereJson(const AStmt: TLzNexJsonStmt): TLzNexFragment; virtual;
    function CompileWhereFullText(const AStmt: TLzNexFullTextStmt): TLzNexFragment; virtual;

    function RandomSQL: string; virtual;

    function CompileInTarget(const AStmt: TLzNexInStmt): TLzNexFragment; virtual;

    function CompileOrderByItem(const AStmt: TLzNexOrderByStmt): TLzNexFragment; virtual;

    function InsertVerb: string; virtual;

    function InsertColumnOrder: TLzNexStringArray; virtual;
    function CompileInsertCell(const AValue: TLzNexValue; const AColumn: string): TLzNexFragment; virtual;
    function CompileConflict(const AColumns: TLzNexStringArray): TLzNexFragment; virtual;

    function CompileSet: TLzNexFragment; virtual;
    function CompileSetValue(const AValue: TLzNexValue; const AColumn: string): TLzNexFragment; virtual;

    function DeleteHead: string; virtual;
  public
    constructor Create(const AClient: ILzNexClient);

    function Compile(const AAst: TLzNexAst): TLzNexFragment;
    function CompilePredicates(const AGroup: TLzNexStatementGroup;
      const AItems: TLzNexStatementList): TLzNexFragment;
    function Client: ILzNexClient;
  end;

implementation

function ValueForColumn(const ARow: TLzNexNamedValues;
  const AName: string): TLzNexValue;
var
  I: Integer;
begin
  for I := 0 to High(ARow) do
    if SameText(ARow[I].Name, AName) then
      Exit(ARow[I].Value);
  Result := TLzNexValue.Unset;
end;

procedure TLzNexFragBuf.Clear;
begin
  FItems := nil;
  FCount := 0;
end;

procedure TLzNexFragBuf.Add(const AFrag: TLzNexFragment);
begin
  if AFrag.IsEmpty then
    Exit;
  if FCount >= Length(FItems) then
  begin
    if Length(FItems) = 0 then
      SetLength(FItems, 8)
    else
      SetLength(FItems, Length(FItems) * 2);
  end;
  FItems[FCount] := AFrag;
  Inc(FCount);
end;

function TLzNexFragBuf.Count: Integer;
begin
  Result := FCount;
end;

function TLzNexFragBuf.Join(const ASep: string): TLzNexFragment;
begin
  if FCount = 0 then
    Exit(TLzNexFragment.Empty);
  Result := JoinFragments(Copy(FItems, 0, FCount), ASep);
end;

constructor TLzNexCompilerBase.Create(const AClient: ILzNexClient);
begin
  inherited Create;
  if AClient = nil then
    raise ELzNexCompile.Create('Compiler requires a dialect (ILzNexClient).');
  FClient := AClient;
  FAst := nil;
end;

function TLzNexCompilerBase.Client: ILzNexClient;
begin
  Result := FClient;
end;

function TLzNexCompilerBase.ComponentName(const AComponent: TLzNexComponent): string;
begin
  case AComponent of
    cpHints: Result := 'hint';
    cpColumns: Result := 'columns';
    cpFrom: Result := 'from';
    cpJoin: Result := 'join';
    cpWhere: Result := 'where';
    cpGroup: Result := 'group by';
    cpHaving: Result := 'having';
    cpUnion: Result := 'union';
    cpOrder: Result := 'order by';
    cpLimitPrefix: Result := 'limit (prefix)';
    cpLimit: Result := 'limit';
    cpOffset: Result := 'offset';
    cpLock: Result := 'lock';
  else
    Result := '?';
  end;
end;

function TLzNexCompilerBase.MethodName(const AMethod: TLzNexQueryMethod): string;
begin
  case AMethod of
    qmSelect: Result := 'select';
    qmFirst: Result := 'first';
    qmInsert: Result := 'insert';
    qmUpdate: Result := 'update';
    qmDelete: Result := 'delete';
    qmTruncate: Result := 'truncate';
  else
    Result := '?';
  end;
end;

function TLzNexCompilerBase.Txt(const AText: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit(AText);
end;

function TLzNexCompilerBase.Wrapped(const AFrag: TLzNexFragment): TLzNexFragment;
begin
  Result := AFrag.Wrap('(', ')');
end;

function TLzNexCompilerBase.Ident(const AName: string): string;
begin
  Result := FClient.WrapQualified(AName);
end;

function TLzNexCompilerBase.IdentList(const ANames: TLzNexStringArray): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  Result := '';
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(ANames) do
    begin
      if I > 0 then
        SB.Append(', ');
      SB.Append(Ident(ANames[I]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexCompilerBase.IdentListV(const AValues: TLzNexValues): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  Result := '';
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(AValues) do
    begin
      if I > 0 then
        SB.Append(', ');
      SB.Append(Ident(AValues[I].Text));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexCompilerBase.BoolWord(const AOp: TLzNexBoolOp): string;
begin
  if AOp = boOr then
    Result := 'or'
  else
    Result := 'and';
end;

function TLzNexCompilerBase.DirWord(const ADir: TLzNexOrderDir): string;
begin
  if ADir = odDesc then
    Result := 'desc'
  else
    Result := 'asc';
end;

function TLzNexCompilerBase.NullsWord(const ANulls: TLzNexNullsOrder): string;
begin
  case ANulls of
    nlFirst: Result := 'nulls first';
    nlLast: Result := 'nulls last';
  else
    Result := '';
  end;
end;

function TLzNexCompilerBase.AggWord(const AAgg: TLzNexAggregate): string;
begin
  case AAgg of
    agCount: Result := 'count';
    agMin: Result := 'min';
    agMax: Result := 'max';
    agSum: Result := 'sum';
    agAvg: Result := 'avg';
  else
    Result := 'count';
  end;
end;

function TLzNexCompilerBase.JoinTypeSQL(const AType: TLzNexJoinType): string;
begin
  case AType of
    jtInner: Result := 'inner join';
    jtLeft: Result := 'left join';
    jtLeftOuter: Result := 'left outer join';
    jtRight: Result := 'right join';
    jtRightOuter: Result := 'right outer join';
    jtOuter: Result := 'outer join';
    jtFullOuter: Result := 'full outer join';
    jtCross: Result := 'cross join';
  else
    Result := '';
  end;
end;

function TLzNexCompilerBase.UnionWord(const AKind: TLzNexUnionKind): string;
begin
  case AKind of
    ukUnion: Result := 'union';
    ukUnionAll: Result := 'union all';
    ukIntersect: Result := 'intersect';
    ukExcept: Result := 'except';
  else
    Result := 'union';
  end;
end;

function TLzNexCompilerBase.LikeOperator(const ACaseInsensitive,
  ANegated: Boolean): string;
begin
  if ACaseInsensitive then
    Result := 'ilike'
  else
    Result := 'like';
  if ANegated then
    Result := 'not ' + Result;
end;

function TLzNexCompilerBase.RawFragment(const ARef: IInterface;
  const AWhere: string): TLzNexFragment;
var
  R: ILzNexRaw;
begin
  if ARef = nil then
    raise ELzNexCompile.CreateFmt('Raw fragment missing in %s.', [AWhere]);
  if not Supports(ARef, ILzNexRaw, R) then
    raise ELzNexCompile.CreateFmt(
      'Raw value in %s does not implement ILzNexRaw.', [AWhere]);
  Result := R.Build(FClient);
end;

function TLzNexCompilerBase.SubFragment(const ARef: IInterface;
  const AWhere: string): TLzNexFragment;
var
  Q: ILzNexQuery;
  R: ILzNexRaw;
begin
  if ARef = nil then
    raise ELzNexCompile.CreateFmt('Subquery missing in %s.', [AWhere]);
  if Supports(ARef, ILzNexQuery, Q) then
    Exit(Q.ToSQL);

  if Supports(ARef, ILzNexRaw, R) then
    Exit(R.Build(FClient));
  raise ELzNexCompile.CreateFmt(
    'Subquery in %s implements neither ILzNexQuery nor ILzNexRaw.', [AWhere]);
end;

function TLzNexCompilerBase.CompileExpr(const AValue: TLzNexValue;
  const AWhere: string): TLzNexFragment;
begin
  case AValue.Kind of
    vkIdentifier, vkString:
      Result := Txt(Ident(AValue.Text));
    vkRaw:
      Result := RawFragment(AValue.Ref, AWhere);
    vkSubQuery:
      Result := Wrapped(SubFragment(AValue.Ref, AWhere));
    vkUnset:
      raise ELzNexBuilder.CreateFmt(
        'No expression given in %s: a vkUnset value arrived where a column or ' +
        'expression is expected.', [AWhere]);
  else

    Result := TLzNexFragment.Param(AValue);
  end;
end;

function TLzNexCompilerBase.CompileIdent(const AValue: TLzNexValue;
  const AWhere: string): TLzNexFragment;
begin
  case AValue.Kind of
    vkIdentifier, vkString:
      Result := Txt(Ident(AValue.Text));
    vkRaw:
      Result := RawFragment(AValue.Ref, AWhere);
  else
    raise ELzNexCompile.CreateFmt(
      'In %s expected an identifier, got %s.', [AWhere, AValue.Describe]);
  end;
end;

function TLzNexCompilerBase.CompileBind(const AValue: TLzNexValue;
  const AColumn: string): TLzNexFragment;
begin
  if AValue.IsUnset then
    raise ELzNexBuilder.CreateFmt(
      'No value given for column "%s": a vkUnset arrived where a parameter is ' +
      'expected. In WHERE this is an error (in INSERT it would become DEFAULT).', [AColumn]);
  case AValue.Kind of
    vkIdentifier:
      Result := Txt(Ident(AValue.Text));
    vkRaw:
      Result := RawFragment(AValue.Ref, 'column ' + AColumn);
    vkSubQuery:
      Result := Wrapped(SubFragment(AValue.Ref, 'column ' + AColumn));
  else
    Result := TLzNexFragment.Param(AValue);
  end;
end;

function TLzNexCompilerBase.CompileBindList(const AValues: TLzNexValues;
  const AColumn: string): TLzNexFragment;
var
  I: Integer;
  Buf: TLzNexFragBuf;
begin
  Buf.Clear;
  for I := 0 to High(AValues) do
    Buf.Add(CompileBind(AValues[I], AColumn));
  Result := Buf.Join(', ');
end;

function TLzNexCompilerBase.HasComponent(const AComponent: TLzNexComponent): Boolean;
begin
  case AComponent of
    cpHints: Result := FAst.Has(sgHint);
    cpColumns: Result := FAst.Has(sgColumns);
    cpFrom: Result := not FAst.Single.Table.IsUnset;
    cpJoin: Result := FAst.Has(sgJoin);
    cpWhere: Result := FAst.Has(sgWhere);
    cpGroup: Result := FAst.Has(sgGroup);
    cpHaving: Result := FAst.Has(sgHaving);
    cpUnion: Result := FAst.Has(sgUnion);
    cpOrder: Result := FAst.Has(sgOrder);
    cpLimitPrefix, cpLimit: Result := FAst.Single.HasLimit;
    cpOffset: Result := FAst.Single.HasOffset;
    cpLock: Result := FAst.Single.Lock <> lkNone;
  else
    Result := False;
  end;
end;

procedure TLzNexCompilerBase.ValidateComponents(const AMethod: TLzNexQueryMethod);
var
  Inv: TLzNexComponents;
  I: Integer;
begin
  Inv := FClient.InvalidComponents(AMethod);
  for I := 0 to High(Inv) do
    if HasComponent(Inv[I]) then
      raise ELzNexCompile.CreateFmt(
        'Section "%s" is not valid in %s on dialect %s. Remove the clause or change the verb.',
        [ComponentName(Inv[I]), MethodName(AMethod), FClient.DialectName]);
end;

function TLzNexCompilerBase.Compile(const AAst: TLzNexAst): TLzNexFragment;
begin
  if AAst = nil then
    raise ELzNexCompile.Create('Compile: AST nil.');
  FAst := AAst;
  ValidateComponents(AAst.Single.Method);

  case AAst.Single.Method of
    qmSelect, qmFirst:
      Result := CompileSelect;
    qmInsert:
      Result := CompileInsert;
    qmUpdate:
      Result := CompileUpdate;
    qmDelete:
      Result := CompileDelete;
    qmTruncate:
      Result := CompileTruncate;
  else
    raise ELzNexCompile.Create('Query verb not supported by the compiler.');
  end;
end;

function TLzNexCompilerBase.CompileSelect: TLzNexFragment;
begin
  Result := JoinFragments([
    CompileWith,
    Txt('select'),
    CompileComponents(FAst.Single.Method, nil)]);
end;

function TLzNexCompilerBase.CompileInsert: TLzNexFragment;
var
  Target, ColList, Rows: TLzNexFragment;
  Cols: TLzNexStringArray;
  RowBuf, CellBuf: TLzNexFragBuf;
  I, J: Integer;
begin
  Target := CompileTarget;
  if Target.IsEmpty then
    raise ELzNexCompile.Create('INSERT requires a table.');

  if Length(FAst.Single.InsertRows) = 0 then
    Exit(JoinFragments([CompileWith, Txt(InsertVerb), Target, Txt('default values'),
      CompileReturning]));

  Cols := InsertColumnOrder;
  ColList := Txt(IdentList(Cols)).Wrap('(', ')');

  RowBuf.Clear;
  for I := 0 to High(FAst.Single.InsertRows) do
  begin
    CellBuf.Clear;
    for J := 0 to High(Cols) do
      CellBuf.Add(CompileInsertCell(
        ValueForColumn(FAst.Single.InsertRows[I], Cols[J]), Cols[J]));
    RowBuf.Add(CellBuf.Join(', ').Wrap('(', ')'));
  end;
  Rows := RowBuf.Join(', ').Prefix('values ');

  Result := JoinFragments([
    CompileWith, Txt(InsertVerb), Target, ColList, Rows,
    CompileConflict(Cols), CompileReturning]);
end;

function TLzNexCompilerBase.CompileUpdate: TLzNexFragment;
var
  Target, SetFrag: TLzNexFragment;
begin
  Target := CompileTarget;
  if Target.IsEmpty then
    raise ELzNexCompile.Create('UPDATE requires a table.');
  SetFrag := CompileSet;
  if SetFrag.IsEmpty then
    raise ELzNexCompile.Create('UPDATE without SET: no column to update.');

  Result := JoinFragments([
    CompileWith, Txt('update'), Target, CompileJoins, SetFrag,
    CompileComponents(qmUpdate, TLzNexComponents.Create(cpFrom, cpJoin)),
    CompileReturning]);
end;

function TLzNexCompilerBase.CompileDelete: TLzNexFragment;
begin
  if FAst.Single.Table.IsUnset then
    raise ELzNexCompile.Create('DELETE requires a table.');
  Result := JoinFragments([
    CompileWith, Txt(DeleteHead),
    CompileComponents(qmDelete, nil),
    CompileReturning]);
end;

function TLzNexCompilerBase.CompileTruncate: TLzNexFragment;
begin
  if FAst.Single.Table.IsUnset then
    raise ELzNexCompile.Create('TRUNCATE requires a table.');
  Result := Txt('truncate').Concat(CompileTarget);
end;

function TLzNexCompilerBase.CompileComponent(
  const AComponent: TLzNexComponent): TLzNexFragment;
begin
  case AComponent of
    cpHints: Result := CompileHints;
    cpColumns: Result := CompileColumns;
    cpFrom: Result := CompileFrom;
    cpJoin: Result := CompileJoins;
    cpWhere: Result := CompileWhere;
    cpGroup: Result := CompileGroup;
    cpHaving: Result := CompileHaving;
    cpUnion: Result := CompileUnion;
    cpOrder: Result := CompileOrder;
    cpLimitPrefix: Result := CompileLimitPrefix;
    cpLimit: Result := CompileLimit;
    cpOffset: Result := CompileOffset;
    cpLock: Result := CompileLock;
  else
    Result := TLzNexFragment.Empty;
  end;
end;

function TLzNexCompilerBase.CompileComponents(const AMethod: TLzNexQueryMethod;
  const ASkip: TLzNexComponents): TLzNexFragment;
var
  List: TLzNexComponents;
  I, J: Integer;
  Skipped: Boolean;
  Buf: TLzNexFragBuf;
begin
  Buf.Clear;
  List := FClient.Components(AMethod);
  for I := 0 to High(List) do
  begin
    Skipped := False;
    for J := 0 to High(ASkip) do
      if ASkip[J] = List[I] then
      begin
        Skipped := True;
        Break;
      end;
    if Skipped then
      Continue;
    Buf.Add(CompileComponent(List[I]));
  end;
  Result := Buf.Join(' ');
end;

function TLzNexCompilerBase.CompileWith: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  W: TLzNexWithStmt;
  Buf: TLzNexFragBuf;
  Head, Cols: string;
  Recursive: Boolean;
  F: TLzNexFragment;
begin
  L := FAst.Group(sgWith);
  if L.Count = 0 then
    Exit(TLzNexFragment.Empty);

  Recursive := False;
  Buf.Clear;
  for I := 0 to L.Count - 1 do
  begin
    if not (L[I] is TLzNexWithStmt) then
      raise ELzNexCompile.Create('Invalid statement in the with section.');
    W := TLzNexWithStmt(L[I]);
    if W.Recursive then
      Recursive := True;
    Cols := '';
    if Length(W.Columns) > 0 then
      Cols := ' (' + IdentListV(W.Columns) + ')';
    F := Wrapped(SubFragment(W.Sub, 'with ' + W.Alias));
    Buf.Add(F.Prefix(Ident(W.Alias) + Cols + ' as '));
  end;

  if Recursive then
    Head := 'with recursive '
  else
    Head := 'with ';
  Result := Buf.Join(', ').Prefix(Head);
end;

function TLzNexCompilerBase.CompileHints: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  S: string;
  Buf: TLzNexFragBuf;
begin
  L := FAst.Group(sgHint);
  if L.Count = 0 then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  for I := 0 to L.Count - 1 do
  begin
    if not (L[I] is TLzNexHintStmt) then
      Continue;
    S := Trim(TLzNexHintStmt(L[I]).Text);
    if S = '' then
      Continue;

    if (Pos('*/', S) > 0) or (Pos('/*', S) > 0) then
      raise ELzNexBuilder.CreateFmt(
        'Hint "%s" contains a comment delimiter. That would allow escaping the ' +
        'comment and injecting SQL.', [S]);
    Buf.Add(Txt('/*+ ' + S + ' */'));
  end;
  Result := Buf.Join(' ');
end;

function TLzNexCompilerBase.CompileColumns: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  Dist, Cols: TLzNexFragment;
  Buf: TLzNexFragBuf;
begin
  L := FAst.Group(sgColumns);
  Dist := TLzNexFragment.Empty;
  Buf.Clear;
  for I := 0 to L.Count - 1 do
    case L[I].Kind of
      skDistinct:
        Dist := CompileDistinct(TLzNexDistinctStmt(L[I]));
      skAggregate:
        Buf.Add(CompileAggregate(TLzNexAggregateStmt(L[I])));
      skColumnRaw:
        Buf.Add(RawFragment(TLzNexRawStmt(L[I]).Raw, 'columns'));
      skColumn, skColumnSub:
        Buf.Add(CompileColumn(TLzNexColumnStmt(L[I])));
    else
      raise ELzNexCompile.CreateFmt(
        'Statement %d does not belong to the columns section.', [Ord(L[I].Kind)]);
    end;

  Cols := Buf.Join(', ');
  if Cols.IsEmpty then
    Cols := Txt('*');
  Result := JoinFragments([Dist, Cols]);
end;

function TLzNexCompilerBase.CompileFrom: TLzNexFragment;
var
  F: TLzNexFragment;
begin
  F := CompileTarget;
  if F.IsEmpty then
    Exit(F);
  Result := F.Prefix('from ');
end;

function TLzNexCompilerBase.CompileJoins: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  Buf: TLzNexFragBuf;
begin
  L := FAst.Group(sgJoin);
  if L.Count = 0 then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  for I := 0 to L.Count - 1 do
  begin
    if L[I].Kind <> skJoin then
      raise ELzNexCompile.Create('Invalid statement in the join section.');
    Buf.Add(CompileJoin(TLzNexJoinStmt(L[I])));
  end;
  Result := Buf.Join(' ');
end;

function TLzNexCompilerBase.CompileWhere: TLzNexFragment;
var
  F: TLzNexFragment;
begin
  F := CompilePredicates(sgWhere, FAst.Group(sgWhere));
  if F.IsEmpty then
    Exit(F);
  Result := F.Prefix('where ');
end;

function TLzNexCompilerBase.CompileGroup: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  Buf: TLzNexFragBuf;
begin
  L := FAst.Group(sgGroup);
  if L.Count = 0 then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  for I := 0 to L.Count - 1 do
  begin
    if not (L[I] is TLzNexGroupByStmt) then
      raise ELzNexCompile.Create('Invalid statement in the group by section.');
    Buf.Add(CompileExpr(TLzNexGroupByStmt(L[I]).Expr, 'group by'));
  end;
  Result := Buf.Join(', ').Prefix('group by ');
end;

function TLzNexCompilerBase.CompileHaving: TLzNexFragment;
var
  F: TLzNexFragment;
begin
  F := CompilePredicates(sgHaving, FAst.Group(sgHaving));
  if F.IsEmpty then
    Exit(F);
  Result := F.Prefix('having ');
end;

function TLzNexCompilerBase.CompileUnion: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  U: TLzNexUnionStmt;
  Sub: TLzNexFragment;
  Buf: TLzNexFragBuf;
begin
  L := FAst.Group(sgUnion);
  if L.Count = 0 then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  for I := 0 to L.Count - 1 do
  begin
    if not (L[I] is TLzNexUnionStmt) then
      raise ELzNexCompile.Create('Invalid statement in the union section.');
    U := TLzNexUnionStmt(L[I]);
    Sub := SubFragment(U.Sub, 'union');
    if U.WrapInParens then
      Sub := Wrapped(Sub);
    Buf.Add(Sub.Prefix(UnionWord(U.UnionKind) + ' '));
  end;
  Result := Buf.Join(' ');
end;

function TLzNexCompilerBase.CompileOrder: TLzNexFragment;
var
  L: TLzNexStatementList;
  I: Integer;
  Buf: TLzNexFragBuf;
begin
  L := FAst.Group(sgOrder);
  if L.Count = 0 then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  for I := 0 to L.Count - 1 do
  begin
    if L[I].Kind = skOrderByRandom then
    begin
      Buf.Add(Txt(RandomSQL));
      Continue;
    end;
    if not (L[I] is TLzNexOrderByStmt) then
      raise ELzNexCompile.Create('Invalid statement in the order by section.');
    Buf.Add(CompileOrderByItem(TLzNexOrderByStmt(L[I])));
  end;
  Result := Buf.Join(', ').Prefix('order by ');
end;

function TLzNexCompilerBase.CompileLimitPrefix: TLzNexFragment;
begin

  Result := TLzNexFragment.Empty;
end;

function TLzNexCompilerBase.CompileLimit: TLzNexFragment;
begin
  if not FAst.Single.HasLimit then
  begin

    if FAst.Single.Method = qmFirst then
      Exit(TLzNexFragment.Param(TLzNexValue.FromInt64(1)).Prefix('limit '));
    Exit(TLzNexFragment.Empty);
  end;
  Result := TLzNexFragment.Param(FAst.Single.LimitValue).Prefix('limit ');
end;

function TLzNexCompilerBase.CompileOffset: TLzNexFragment;
begin
  if not FAst.Single.HasOffset then
    Exit(TLzNexFragment.Empty);
  Result := TLzNexFragment.Param(FAst.Single.OffsetValue).Prefix('offset ');
end;

function TLzNexCompilerBase.CompileLock: TLzNexFragment;
var
  S: string;
begin
  case FAst.Single.Lock of
    lkForUpdate: S := 'for update';
    lkForShare: S := 'for share';
  else
    Exit(TLzNexFragment.Empty);
  end;
  case FAst.Single.Wait of
    wtNoWait: S := S + ' nowait';
    wtSkipLocked: S := S + ' skip locked';
  end;
  Result := Txt(S);
end;

function TLzNexCompilerBase.CompileReturning: TLzNexFragment;
begin
  if Length(FAst.Single.Returning) = 0 then
    Exit(TLzNexFragment.Empty);
  if not FClient.SupportsReturning then
    raise ELzNexCompile.CreateFmt(
      'RETURNING is not supported by %s. Use LastInsertId or a SELECT afterwards.',
      [FClient.DialectName]);
  Result := Txt('returning ' + IdentListV(FAst.Single.Returning));
end;

function TLzNexCompilerBase.Aliased(const AFrag: TLzNexFragment;
  const AAlias: string): TLzNexFragment;
begin
  if (AAlias = '') or AFrag.IsEmpty then
    Exit(AFrag);
  Result := TLzNexFragment.Make(
    FClient.Alias(AFrag.Text, FClient.WrapIdentifier(AAlias)), AFrag.Bindings);
end;

function TLzNexCompilerBase.CompileColumn(
  const AStmt: TLzNexColumnStmt): TLzNexFragment;
begin
  Result := Aliased(CompileExpr(AStmt.Expr, 'columns'), AStmt.Alias);
end;

function TLzNexCompilerBase.CompileAggregate(
  const AStmt: TLzNexAggregateStmt): TLzNexFragment;
var
  Inner: TLzNexFragment;
  Pre: string;
begin
  if AStmt.Column.IsUnset then
    Inner := Txt('*')
  else
    Inner := CompileExpr(AStmt.Column, 'aggregate');
  if AStmt.Distinct then
    Pre := AggWord(AStmt.Agg) + '(distinct '
  else
    Pre := AggWord(AStmt.Agg) + '(';
  Result := Aliased(Inner.Wrap(Pre, ')'), AStmt.Alias);
end;

function TLzNexCompilerBase.CompileDistinct(
  const AStmt: TLzNexDistinctStmt): TLzNexFragment;
begin
  if Length(AStmt.Columns) = 0 then
    Exit(Txt('distinct'));
  if not FClient.SupportsDistinctOn then
    raise ELzNexCompile.CreateFmt(
      'DISTINCT ON is not supported by %s. Use plain Distinct or group by.',
      [FClient.DialectName]);
  Result := Txt('distinct on (' + IdentListV(AStmt.Columns) + ')');
end;

function TLzNexCompilerBase.CompileTarget: TLzNexFragment;
var
  T: TLzNexValue;
  S: string;
  F: TLzNexFragment;
begin
  T := FAst.Single.Table;
  if T.IsUnset then
    Exit(TLzNexFragment.Empty);

  case T.Kind of
    vkIdentifier, vkString:
      begin
        S := Ident(T.Text);
        if FAst.Single.SchemaName <> '' then
          S := Ident(FAst.Single.SchemaName) + '.' + S;
        F := Txt(S);
      end;
    vkRaw:
      F := RawFragment(T.Ref, 'from');
    vkSubQuery:
      begin
        if FAst.Single.TableAlias = '' then
          raise ELzNexCompile.Create(
            'A subquery in FROM requires an alias: without one the SQL is not valid.');
        F := Wrapped(SubFragment(T.Ref, 'from'));
      end;
  else
    raise ELzNexCompile.CreateFmt('Invalid table: %s.', [T.Describe]);
  end;

  Result := Aliased(F, FAst.Single.TableAlias);
end;

function TLzNexCompilerBase.CompileJoin(
  const AStmt: TLzNexJoinStmt): TLzNexFragment;
begin
  if AStmt.JoinType = jtRaw then
    Exit(RawFragment(AStmt.Raw, 'join'));
  Result := JoinFragments([
    Txt(JoinTypeSQL(AStmt.JoinType)),
    CompileJoinTarget(AStmt),
    CompileJoinClauses(AStmt.Clauses)]);
end;

function TLzNexCompilerBase.CompileJoinTarget(
  const AStmt: TLzNexJoinStmt): TLzNexFragment;
var
  F: TLzNexFragment;
begin
  case AStmt.Table.Kind of
    vkIdentifier, vkString:
      F := Txt(Ident(AStmt.Table.Text));
    vkRaw:
      F := RawFragment(AStmt.Table.Ref, 'join');
    vkSubQuery:
      begin
        if AStmt.Alias = '' then
          raise ELzNexCompile.Create('A subquery in JOIN requires an alias.');
        F := Wrapped(SubFragment(AStmt.Table.Ref, 'join'));
      end;
  else
    raise ELzNexCompile.CreateFmt('Invalid join table: %s.',
      [AStmt.Table.Describe]);
  end;
  Result := Aliased(F, AStmt.Alias);
end;

function TLzNexCompilerBase.CompileJoinClauses(
  const AClauses: TLzNexJoinClauseList): TLzNexFragment;
var
  I: Integer;
  C: TLzNexJoinClause;
  F: TLzNexFragment;
  First: Boolean;
  Buf: TLzNexFragBuf;
begin
  if (AClauses = nil) or (AClauses.Count = 0) then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  First := True;
  for I := 0 to AClauses.Count - 1 do
  begin
    C := AClauses[I];
    F := CompileJoinClause(C);
    if F.IsEmpty then
      Continue;
    if First then
    begin

      if C.ClauseKind <> jcUsing then
        F := F.Prefix('on ');
    end
    else
      F := F.Prefix(BoolWord(C.BoolOp) + ' ');
    Buf.Add(F);
    First := False;
  end;
  Result := Buf.Join(' ');
end;

function TLzNexCompilerBase.CompileJoinClause(
  const AClause: TLzNexJoinClause): TLzNexFragment;
var
  Left: TLzNexFragment;
  Op, ColName: string;
begin
  ColName := AClause.Left.Text;
  case AClause.ClauseKind of
    jcColumns:
      begin
        Op := NormalizeOperator(AClause.Op);
        Left := CompileIdent(AClause.Left, 'join on');
        Result := Left.Concat(Txt(Op)).Concat(CompileIdent(AClause.Right, 'join on'));
      end;
    jcValue:
      begin
        Op := NormalizeOperator(AClause.Op);
        Left := CompileIdent(AClause.Left, 'join on');
        Result := Left.Concat(Txt(Op)).Concat(CompileBind(AClause.Right, ColName));
      end;
    jcIn:
      begin
        Left := CompileIdent(AClause.Left, 'join on');
        if Length(AClause.Values) = 0 then
        begin
          if AClause.Negated then
            Exit(Txt('1 = 1'));
          Exit(Txt('1 = 0'));
        end;
        if AClause.Negated then
          Op := 'not in'
        else
          Op := 'in';
        Result := Left.Concat(Txt(Op)).Concat(
          Wrapped(CompileBindList(AClause.Values, ColName)));
      end;
    jcNull:
      begin
        Left := CompileIdent(AClause.Left, 'join on');
        if AClause.Negated then
          Result := Left.Concat(Txt('is not null'))
        else
          Result := Left.Concat(Txt('is null'));
      end;
    jcBetween:
      begin
        if Length(AClause.Values) < 2 then
          raise ELzNexCompile.Create('BETWEEN in JOIN requires two values.');
        Left := CompileIdent(AClause.Left, 'join on');
        if AClause.Negated then
          Op := 'not between'
        else
          Op := 'between';
        Result := Left.Concat(Txt(Op))
          .Concat(CompileBind(AClause.Values[0], ColName))
          .Concat(Txt('and'))
          .Concat(CompileBind(AClause.Values[1], ColName));
      end;
    jcRaw:
      Result := RawFragment(AClause.Raw, 'join on');
    jcUsing:
      begin
        if Length(AClause.UsingColumns) = 0 then
          raise ELzNexCompile.Create('USING in JOIN requires at least one column.');
        Result := Txt('using (' + IdentListV(AClause.UsingColumns) + ')');
      end;
  else
    raise ELzNexCompile.Create('Join clause type not supported.');
  end;

  if AClause.Negated and (AClause.ClauseKind in [jcColumns, jcValue, jcRaw]) then
    Result := Wrapped(Result).Prefix('not ');
end;

function TLzNexCompilerBase.CompilePredicates(const AGroup: TLzNexStatementGroup;
  const AItems: TLzNexStatementList): TLzNexFragment;
var
  I: Integer;
  F: TLzNexFragment;
  First: Boolean;
  Buf: TLzNexFragBuf;
begin
  if (AItems = nil) or (AItems.Count = 0) then
    Exit(TLzNexFragment.Empty);
  Buf.Clear;
  First := True;
  for I := 0 to AItems.Count - 1 do
  begin
    F := CompilePredicate(AItems[I]);
    if F.IsEmpty then
      Continue;

    if not First then
      F := F.Prefix(BoolWord(AItems[I].BoolOp) + ' ');
    Buf.Add(F);
    First := False;
  end;
  Result := Buf.Join(' ');
end;

function TLzNexCompilerBase.CompilePredicate(
  const AStmt: TLzNexStatement): TLzNexFragment;
begin
  case AStmt.Kind of
    skWhereBasic, skHavingBasic, skWhereColumn:
      Result := CompileWhereBasic(TLzNexBasicStmt(AStmt));
    skWhereIn, skHavingIn, skWhereInSub:
      Result := CompileWhereIn(TLzNexInStmt(AStmt));
    skWhereNull, skHavingNull:
      Result := CompileWhereNull(TLzNexNullStmt(AStmt));
    skWhereBetween, skHavingBetween:
      Result := CompileWhereBetween(TLzNexBetweenStmt(AStmt));
    skWhereLike:
      Result := CompileWhereLike(TLzNexLikeStmt(AStmt));
    skWhereExists:
      Result := CompileWhereExists(TLzNexExistsStmt(AStmt));
    skWhereRaw, skHavingRaw:
      Result := CompileWhereRaw(TLzNexRawStmt(AStmt));
    skWhereDatePart:
      Result := CompileWhereDatePart(TLzNexDatePartStmt(AStmt));
    skWhereJson:
      Result := CompileWhereJson(TLzNexJsonStmt(AStmt));
    skWhereFullText:
      Result := CompileWhereFullText(TLzNexFullTextStmt(AStmt));
    skWhereGroup, skHavingGroup:
      Result := CompileWhereGroup(TLzNexGroupStmt(AStmt));
    skWhereSub:

      if AStmt is TLzNexBasicStmt then
        Result := CompileWhereBasic(TLzNexBasicStmt(AStmt))
      else if AStmt is TLzNexRawStmt then
        Result := CompileWhereRaw(TLzNexRawStmt(AStmt))
      else
        raise ELzNexCompile.Create('skWhereSub with an unexpected class.');
  else
    raise ELzNexCompile.CreateFmt(
      'Statement %d is not a where/having predicate.', [Ord(AStmt.Kind)]);
  end;
end;

function TLzNexCompilerBase.CompileWhereBasic(
  const AStmt: TLzNexBasicStmt): TLzNexFragment;
var
  Left, Right: TLzNexFragment;
  Op, ColName: string;
begin
  ColName := AStmt.Column.Text;
  Op := NormalizeOperator(AStmt.Op);
  Left := CompileExpr(AStmt.Column, 'where');

  if AStmt.AsColumn or (AStmt.Kind = skWhereColumn) then
    Right := CompileIdent(AStmt.Value, 'where (column comparison)')
  else
    Right := CompileBind(AStmt.Value, ColName);

  Result := Left.Concat(Txt(Op)).Concat(Right);
  if AStmt.Negated then
    Result := Result.Prefix('not ');
end;

function TLzNexCompilerBase.CompileInTarget(
  const AStmt: TLzNexInStmt): TLzNexFragment;
begin
  if Length(AStmt.Columns) = 0 then
    raise ELzNexCompile.Create('IN without a column on the left side.');
  if Length(AStmt.Columns) = 1 then
    Exit(CompileExpr(AStmt.Columns[0], 'where in'));

  Result := Txt('(' + IdentListV(AStmt.Columns) + ')');
end;

function TLzNexCompilerBase.CompileWhereIn(
  const AStmt: TLzNexInStmt): TLzNexFragment;
var
  Left: TLzNexFragment;
  Op, ColName: string;
  I: Integer;
  Buf: TLzNexFragBuf;
begin
  if AStmt.Negated then
    Op := 'not in'
  else
    Op := 'in';
  ColName := '';
  if Length(AStmt.Columns) > 0 then
    ColName := AStmt.Columns[0].Text;

  if AStmt.Sub <> nil then
  begin
    Left := CompileInTarget(AStmt);
    Exit(Left.Concat(Txt(Op)).Concat(Wrapped(SubFragment(AStmt.Sub, 'where in'))));
  end;

  if Length(AStmt.Tuples) > 0 then
  begin
    Left := CompileInTarget(AStmt);
    Buf.Clear;
    for I := 0 to High(AStmt.Tuples) do
      Buf.Add(Wrapped(CompileBindList(AStmt.Tuples[I], ColName)));
    Exit(Left.Concat(Txt(Op)).Concat(Wrapped(Buf.Join(', '))));
  end;

  if Length(AStmt.Values) = 0 then
  begin

    if AStmt.Negated then
      Exit(Txt('1 = 1'));
    Exit(Txt('1 = 0'));
  end;

  Left := CompileInTarget(AStmt);
  Result := Left.Concat(Txt(Op)).Concat(
    Wrapped(CompileBindList(AStmt.Values, ColName)));
end;

function TLzNexCompilerBase.CompileWhereNull(
  const AStmt: TLzNexNullStmt): TLzNexFragment;
begin
  Result := CompileExpr(AStmt.Column, 'where null');
  if AStmt.Negated then
    Result := Result.Concat(Txt('is not null'))
  else
    Result := Result.Concat(Txt('is null'));
end;

function TLzNexCompilerBase.CompileWhereBetween(
  const AStmt: TLzNexBetweenStmt): TLzNexFragment;
var
  Op, ColName: string;
begin
  ColName := AStmt.Column.Text;
  if AStmt.Negated then
    Op := 'not between'
  else
    Op := 'between';
  Result := CompileExpr(AStmt.Column, 'where between')
    .Concat(Txt(Op))
    .Concat(CompileBind(AStmt.Lo, ColName))
    .Concat(Txt('and'))
    .Concat(CompileBind(AStmt.Hi, ColName));
end;

function TLzNexCompilerBase.CompileWhereLike(
  const AStmt: TLzNexLikeStmt): TLzNexFragment;
begin
  Result := CompileExpr(AStmt.Column, 'where like')
    .Concat(Txt(LikeOperator(AStmt.CaseInsensitive, AStmt.Negated)))
    .Concat(CompileBind(AStmt.Pattern, AStmt.Column.Text));
end;

function TLzNexCompilerBase.CompileWhereExists(
  const AStmt: TLzNexExistsStmt): TLzNexFragment;
var
  Kw: string;
begin
  if AStmt.Negated then
    Kw := 'not exists '
  else
    Kw := 'exists ';
  Result := Wrapped(SubFragment(AStmt.Sub, 'where exists')).Prefix(Kw);
end;

function TLzNexCompilerBase.CompileWhereRaw(
  const AStmt: TLzNexRawStmt): TLzNexFragment;
begin
  Result := RawFragment(AStmt.Raw, 'where raw');
  if AStmt.Negated then
    Result := Wrapped(Result).Prefix('not ');
end;

function TLzNexCompilerBase.CompileWhereGroup(
  const AStmt: TLzNexGroupStmt): TLzNexFragment;
var
  Body: TLzNexFragment;
begin

  Body := CompilePredicates(AStmt.Group, AStmt.Items);
  if Body.IsEmpty then
    Exit(TLzNexFragment.Empty);
  Result := Wrapped(Body);
  if AStmt.Negated then
    Result := Result.Prefix('not ');
end;

procedure TLzNexCompilerBase.DatePartWrap(const APart: TLzNexDatePart;
  out ABefore, AAfter: string);
begin
  case APart of
    dpDate:
      begin
        ABefore := 'cast(';
        AAfter := ' as date)';
      end;
    dpTime:
      begin
        ABefore := 'cast(';
        AAfter := ' as time)';
      end;
    dpYear:
      begin
        ABefore := 'extract(year from ';
        AAfter := ')';
      end;
    dpMonth:
      begin
        ABefore := 'extract(month from ';
        AAfter := ')';
      end;
    dpDay:
      begin
        ABefore := 'extract(day from ';
        AAfter := ')';
      end;
    dpHour:
      begin
        ABefore := 'extract(hour from ';
        AAfter := ')';
      end;
    dpMinute:
      begin
        ABefore := 'extract(minute from ';
        AAfter := ')';
      end;
    dpSecond:
      begin
        ABefore := 'extract(second from ';
        AAfter := ')';
      end;
  else
    raise ELzNexCompile.CreateFmt('Unknown date part %d', [Ord(APart)]);
  end;
end;

function TLzNexCompilerBase.CompileWhereDatePart(
  const AStmt: TLzNexDatePartStmt): TLzNexFragment;
var
  Before, After: string;
  Left, Right: TLzNexFragment;
begin
  DatePartWrap(AStmt.Part, Before, After);
  Left := CompileExpr(AStmt.Column, 'where date part').Wrap(Before, After);
  Right := CompileBind(AStmt.Value, AStmt.Column.Text);

  Result := Left.Concat(Txt(AStmt.Op)).Concat(Right);
  if AStmt.Negated then
    Result := Wrapped(Result).Prefix('not ');
end;

function TLzNexCompilerBase.CompileWhereJson(
  const AStmt: TLzNexJsonStmt): TLzNexFragment;
begin
  raise ELzNexCompile.CreateFmt(
    'Dialect "%s" has no JSON support.', [FClient.DialectName]);
end;

function TLzNexCompilerBase.CompileWhereFullText(
  const AStmt: TLzNexFullTextStmt): TLzNexFragment;
begin
  raise ELzNexCompile.CreateFmt(
    'Dialect "%s" has no full text search.', [FClient.DialectName]);
end;

function TLzNexCompilerBase.RandomSQL: string;
begin
  // ANSI nao define: random() cobre PostgreSQL e SQLite; MySQL e Firebird usam rand().
  Result := 'random()';
end;

function TLzNexCompilerBase.CompileOrderByItem(
  const AStmt: TLzNexOrderByStmt): TLzNexFragment;
var
  E, Flag: TLzNexFragment;
  Dir, FlagDir: string;
begin
  E := CompileExpr(AStmt.Expr, 'order by');
  Dir := DirWord(AStmt.Dir);

  if AStmt.Nulls = nlDefault then
    Exit(E.Concat(Txt(Dir)));

  if FClient.SupportsNullsOrdering then
    Exit(E.Concat(Txt(Dir + ' ' + NullsWord(AStmt.Nulls))));

  if AStmt.Nulls = nlFirst then
    FlagDir := 'desc'
  else
    FlagDir := 'asc';
  Flag := E.Wrap('(', ' is null)').Concat(Txt(FlagDir));
  Result := Flag.Concat(E.Concat(Txt(Dir)), ', ');
end;

function TLzNexCompilerBase.InsertVerb: string;
begin
  Result := 'insert into';
end;

function TLzNexCompilerBase.InsertColumnOrder: TLzNexStringArray;
var
  I, J, K, N: Integer;
  Found: Boolean;
  Rows: TLzNexNamedValues;
begin
  Result := nil;
  N := 0;
  for I := 0 to High(FAst.Single.InsertRows) do
  begin
    Rows := FAst.Single.InsertRows[I];
    for J := 0 to High(Rows) do
    begin
      Found := False;
      for K := 0 to N - 1 do
        if SameText(Result[K], Rows[J].Name) then
        begin
          Found := True;
          Break;
        end;
      if Found then
        Continue;
      if N >= Length(Result) then
        SetLength(Result, N + 8);
      Result[N] := Rows[J].Name;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
  if N = 0 then
    raise ELzNexCompile.Create('INSERT without columns: no row has a value.');
end;

function TLzNexCompilerBase.CompileInsertCell(const AValue: TLzNexValue;
  const AColumn: string): TLzNexFragment;
begin

  if AValue.IsUnset then
    Exit(Txt('default'));
  case AValue.Kind of
    vkIdentifier:
      Result := Txt(Ident(AValue.Text));
    vkRaw:
      Result := RawFragment(AValue.Ref, 'insert ' + AColumn);
    vkSubQuery:
      Result := Wrapped(SubFragment(AValue.Ref, 'insert ' + AColumn));
  else
    Result := TLzNexFragment.Param(AValue);
  end;
end;

function TLzNexCompilerBase.CompileConflict(
  const AColumns: TLzNexStringArray): TLzNexFragment;
var
  I: Integer;
  Targets: string;
  Buf: TLzNexFragBuf;
  Merge: TLzNexNamedValues;
begin
  case FAst.Single.Conflict of
    caNone:
      Exit(TLzNexFragment.Empty);
    caIgnore:
      begin
        if Length(FAst.Single.ConflictTargets) > 0 then
          Exit(Txt('on conflict (' + IdentListV(FAst.Single.ConflictTargets) +
            ') do nothing'));
        Exit(Txt('on conflict do nothing'));
      end;
  end;

  if Length(FAst.Single.ConflictTargets) = 0 then
    raise ELzNexCompile.CreateFmt(
      'ON CONFLICT DO UPDATE requires the conflict columns on dialect %s.',
      [FClient.DialectName]);
  Targets := 'on conflict (' + IdentListV(FAst.Single.ConflictTargets) +
    ') do update set ';

  Buf.Clear;
  Merge := FAst.Single.ConflictMerge;
  if Length(Merge) > 0 then
  begin
    for I := 0 to High(Merge) do

      if Merge[I].Value.IsUnset then
        Buf.Add(Txt(Ident(Merge[I].Name) + ' = excluded.' + Ident(Merge[I].Name)))
      else
        Buf.Add(Txt(Ident(Merge[I].Name) + ' = ').Concat(
          CompileSetValue(Merge[I].Value, Merge[I].Name), ''));
  end
  else

    for I := 0 to High(AColumns) do
      Buf.Add(Txt(Ident(AColumns[I]) + ' = excluded.' + Ident(AColumns[I])));

  Result := Buf.Join(', ').Prefix(Targets);
end;

function TLzNexCompilerBase.CompileSetValue(const AValue: TLzNexValue;
  const AColumn: string): TLzNexFragment;
begin
  if AValue.IsUnset then
    raise ELzNexBuilder.CreateFmt(
      'No value given for column "%s" in the UPDATE SET.', [AColumn]);
  case AValue.Kind of
    vkIdentifier:
      Result := Txt(Ident(AValue.Text));
    vkRaw:
      Result := RawFragment(AValue.Ref, 'set ' + AColumn);
    vkSubQuery:
      Result := Wrapped(SubFragment(AValue.Ref, 'set ' + AColumn));
  else
    Result := TLzNexFragment.Param(AValue);
  end;
end;

function TLzNexCompilerBase.CompileSet: TLzNexFragment;
var
  I: Integer;
  Buf: TLzNexFragBuf;
  NV: TLzNexNamedValues;
begin
  Buf.Clear;
  NV := FAst.Single.UpdateValues;
  for I := 0 to High(NV) do
    Buf.Add(Txt(Ident(NV[I].Name) + ' = ').Concat(
      CompileSetValue(NV[I].Value, NV[I].Name), ''));

  NV := FAst.Single.Counters;
  for I := 0 to High(NV) do
    Buf.Add(Txt(Ident(NV[I].Name) + ' = ' + Ident(NV[I].Name) + ' + ').Concat(
      CompileBind(NV[I].Value, NV[I].Name), ''));

  Result := Buf.Join(', ').Prefix('set ');
end;

function TLzNexCompilerBase.DeleteHead: string;
begin
  Result := 'delete';
end;

end.
