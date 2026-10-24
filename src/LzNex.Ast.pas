unit LzNex.Ast;

{ AST da query: o que o builder acumula e o compiler le.

  Fica ABAIXO de LzNex.Intf no grafo de units de proposito -- subquery e raw sao
  guardados como IInterface (mesmo truque do TLzNexValue), entao a AST nao precisa
  conhecer ILzNexQuery. Isso elimina referencia circular e deixa a Intf poder
  expor a AST com tipo forte.

  Cada statement tem Kind (enum) para o compiler despachar com `case`, em vez do
  despacho por nome de metodo em string que o knex usa. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Generics.Collections,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Exceptions;

type
  TLzNexStatement = class;
  TLzNexStatementList = class;

  // Base de todo item da AST.
  TLzNexStatement = class
  private
    FKind: TLzNexStatementKind;
    FGroup: TLzNexStatementGroup;
    FBoolOp: TLzNexBoolOp;
    FNegated: Boolean;
  public
    constructor Create(const AKind: TLzNexStatementKind;
      const AGroup: TLzNexStatementGroup);
    // Copia PROFUNDA. O knex faz shallow e os clones compartilham
    // statements; aqui isso viraria double free.
    function Clone: TLzNexStatement; virtual; abstract;

    property Kind: TLzNexStatementKind read FKind;
    property Group: TLzNexStatementGroup read FGroup;
    // Conector com o predicado anterior do mesmo grupo.
    property BoolOp: TLzNexBoolOp read FBoolOp write FBoolOp;
    // Prefixo NOT.
    property Negated: Boolean read FNegated write FNegated;
  end;

  // Lista que E DONA dos statements.
  TLzNexStatementList = class(TObjectList<TLzNexStatement>)
  public
    constructor Create;
    // Copia profunda de todos os itens para outra lista.
    procedure CloneInto(const ATarget: TLzNexStatementList);
  end;

  // --- colunas e agregados ---

  // Uma coluna do SELECT. Expr pode ser identificador,
  // raw ou subquery; Alias vazio significa sem AS.
  TLzNexColumnStmt = class(TLzNexStatement)
  public
    Expr: TLzNexValue;
    Alias: string;
    constructor Create(const AExpr: TLzNexValue; const AAlias: string = '');
    function Clone: TLzNexStatement; override;
  end;

  // Count/min/max/sum/avg de uma coluna.
  TLzNexAggregateStmt = class(TLzNexStatement)
  public
    Agg: TLzNexAggregate;
    Column: TLzNexValue;
    Alias: string;
    Distinct: Boolean;
    constructor Create(const AAgg: TLzNexAggregate; const AColumn: TLzNexValue;
      const AAlias: string = ''; const ADistinct: Boolean = False);
    function Clone: TLzNexStatement; override;
  end;

  // DISTINCT. Columns vazio = DISTINCT simples;
  // com colunas = DISTINCT ON (so PostgreSQL).
  TLzNexDistinctStmt = class(TLzNexStatement)
  public
    Columns: TLzNexValues;
    constructor Create(const AColumns: TLzNexValues);
    function Clone: TLzNexStatement; override;
  end;

  // --- predicados (where e having compartilham as classes; muda o Group) ---

  // "col OP valor". AsColumn=True compara com identificador
  // em vez de bind (e o WhereColumn).
  TLzNexBasicStmt = class(TLzNexStatement)
  public
    Column: TLzNexValue;
    Op: string;
    Value: TLzNexValue;
    AsColumn: Boolean;
    constructor Create(const AGroup: TLzNexStatementGroup;
      const AColumn: TLzNexValue; const AOp: string; const AValue: TLzNexValue);
    function Clone: TLzNexStatement; override;
  end;

  // "col IN (...)". Sub preenchido = subquery no lugar da lista.
  // Columns com mais de um item = IN de tupla ("(a,b) IN ((?,?),(?,?))").
  TLzNexInStmt = class(TLzNexStatement)
  public
    Columns: TLzNexValues;
    Values: TLzNexValues;
    Tuples: array of TLzNexValues;
    Sub: IInterface;
    constructor Create(const AGroup: TLzNexStatementGroup;
      const AColumns, AValues: TLzNexValues);
    function Clone: TLzNexStatement; override;
  end;

  // "col IS [NOT] NULL".
  TLzNexNullStmt = class(TLzNexStatement)
  public
    Column: TLzNexValue;
    constructor Create(const AGroup: TLzNexStatementGroup; const AColumn: TLzNexValue);
    function Clone: TLzNexStatement; override;
  end;

  // "col [NOT] BETWEEN ? AND ?".
  TLzNexBetweenStmt = class(TLzNexStatement)
  public
    Column: TLzNexValue;
    Lo: TLzNexValue;
    Hi: TLzNexValue;
    constructor Create(const AGroup: TLzNexStatementGroup;
      const AColumn, ALo, AHi: TLzNexValue);
    function Clone: TLzNexStatement; override;
  end;

  // "col [NOT] LIKE ?". CaseInsensitive pede o ILIKE do dialeto.
  TLzNexLikeStmt = class(TLzNexStatement)
  public
    Column: TLzNexValue;
    Pattern: TLzNexValue;
    CaseInsensitive: Boolean;
    constructor Create(const AGroup: TLzNexStatementGroup;
      const AColumn, APattern: TLzNexValue; const ACaseInsensitive: Boolean);
    function Clone: TLzNexStatement; override;
  end;

  // "[NOT] EXISTS (subquery)".
  TLzNexExistsStmt = class(TLzNexStatement)
  public
    Sub: IInterface;
    constructor Create(const AGroup: TLzNexStatementGroup; const ASub: IInterface);
    function Clone: TLzNexStatement; override;
  end;

  // Fragmento cru num predicado.
  TLzNexRawStmt = class(TLzNexStatement)
  public
    Raw: IInterface;
    constructor Create(const AKind: TLzNexStatementKind;
      const AGroup: TLzNexStatementGroup; const ARaw: IInterface);
    function Clone: TLzNexStatement; override;
  end;

  // Grupo parentetizado "( ... )". E assim que WhereOpen/
  // WhereClose substituem o callback do knex, sem precisar de closure.
  TLzNexGroupStmt = class(TLzNexStatement)
  public
    Items: TLzNexStatementList;
    constructor Create(const AGroup: TLzNexStatementGroup);
    destructor Destroy; override;
    function Clone: TLzNexStatement; override;
  end;

  // --- join ---

  // Uma cláusula ON. jcColumns compara identificadores;
  // jcValue gera bind. Separado de proposito: no knex `on(a, true)` virava
  // comparacao com o identificador "true", uma pegadinha classica.
  TLzNexJoinClause = class
  public
    ClauseKind: TLzNexJoinClauseKind;
    BoolOp: TLzNexBoolOp;
    Negated: Boolean;
    Left: TLzNexValue;
    Op: string;
    Right: TLzNexValue;
    Values: TLzNexValues;
    Sub: IInterface;
    Raw: IInterface;
    UsingColumns: TLzNexValues;
    function Clone: TLzNexJoinClause;
  end;

  TLzNexJoinClauseList = class(TObjectList<TLzNexJoinClause>)
  public
    constructor Create;
  end;

  // Um JOIN com suas cláusulas ON.
  TLzNexJoinStmt = class(TLzNexStatement)
  public
    JoinType: TLzNexJoinType;
    Table: TLzNexValue;
    Alias: string;
    Clauses: TLzNexJoinClauseList;
    Raw: IInterface;
    constructor Create(const AJoinType: TLzNexJoinType; const ATable: TLzNexValue;
      const AAlias: string = '');
    destructor Destroy; override;
    function Clone: TLzNexStatement; override;
  end;

  // --- group by / order by ---

  // Item do GROUP BY.
  TLzNexGroupByStmt = class(TLzNexStatement)
  public
    Expr: TLzNexValue;
    constructor Create(const AExpr: TLzNexValue; const ARaw: Boolean = False);
    function Clone: TLzNexStatement; override;
  end;

  // Item do ORDER BY, com direcao e posicao dos NULL.
  TLzNexOrderByStmt = class(TLzNexStatement)
  public
    Expr: TLzNexValue;
    Dir: TLzNexOrderDir;
    Nulls: TLzNexNullsOrder;
    constructor Create(const AExpr: TLzNexValue; const ADir: TLzNexOrderDir;
      const ANulls: TLzNexNullsOrder = nlDefault; const ARaw: Boolean = False);
    function Clone: TLzNexStatement; override;
  end;

  // --- union / with / hint ---

  // UNION / UNION ALL / INTERSECT / EXCEPT.
  TLzNexUnionStmt = class(TLzNexStatement)
  public
    UnionKind: TLzNexUnionKind;
    Sub: IInterface;
    WrapInParens: Boolean;
    constructor Create(const AUnionKind: TLzNexUnionKind; const ASub: IInterface;
      const AWrap: Boolean = True);
    function Clone: TLzNexStatement; override;
  end;

  // CTE ("WITH alias (cols) AS (...)").
  TLzNexWithStmt = class(TLzNexStatement)
  public
    Alias: string;
    Columns: TLzNexValues;
    Sub: IInterface;
    Recursive: Boolean;
    constructor Create(const AAlias: string; const AColumns: TLzNexValues;
      const ASub: IInterface; const ARecursive: Boolean = False);
    function Clone: TLzNexStatement; override;
  end;

  // Comentario de hint do otimizador ("/*+ ... */").
  TLzNexHintStmt = class(TLzNexStatement)
  public
    Text: string;
    constructor Create(const AText: string);
    function Clone: TLzNexStatement; override;
  end;

  // --- valores unicos da query (o "_single" do knex) ---

  // Tudo que existe no maximo uma vez por query.
  // Fica fora da AST porque nao e lista ordenada.
  TLzNexQuerySingle = record
    Method: TLzNexQueryMethod;
    Table: TLzNexValue;            // identificador, subquery ou raw
    TableAlias: string;
    SchemaName: string;
    QueryAlias: string;            // alias quando esta query e subquery
    LimitValue: TLzNexValue;       // vkUnset = nao informado
    OffsetValue: TLzNexValue;
    Lock: TLzNexLockMode;
    Wait: TLzNexWaitMode;
    InsertRows: array of TLzNexNamedValues;
    UpdateValues: TLzNexNamedValues;
    Counters: TLzNexNamedValues;   // increment/decrement: valor e o delta
    Returning: TLzNexValues;
    Conflict: TLzNexConflictAction;
    ConflictTargets: TLzNexValues;
    ConflictMerge: TLzNexNamedValues;
    PluckColumn: string;
    // Zera para o estado inicial.
    procedure Reset;
    // Copia (arrays sao copiados, nao compartilhados).
    function Clone: TLzNexQuerySingle;
    // HasLimit / HasOffset — se o valor foi informado.
    function HasLimit: Boolean;
    function HasOffset: Boolean;
  end;

  // A arvore completa de uma query: os valores unicos mais uma
  // lista por grupo.
  //
  // Existe para DESACOPLAR o compiler do builder: o compiler recebe isto, nao
  // ILzNexQuery. Assim da para testar o compiler montando AST na mao, e testar
  // o builder conferindo a AST que ele produz -- sem um depender do outro.
  TLzNexAst = class
  private
    FGroups: array[TLzNexStatementGroup] of TLzNexStatementList;
  public
    Single: TLzNexQuerySingle;
    constructor Create;
    destructor Destroy; override;
    // A lista do grupo. Nunca nil.
    function Group(const AGroup: TLzNexStatementGroup): TLzNexStatementList;
    // Acrescenta um statement no grupo dele. A AST passa a ser dona.
    function Add(const AStatement: TLzNexStatement): TLzNexStatement;
    // Se o grupo tem algum item.
    function Has(const AGroup: TLzNexStatementGroup): Boolean;
    // Quantidade de itens no grupo.
    function CountOf(const AGroup: TLzNexStatementGroup): Integer;
    // Remove e libera todos os itens do grupo.
    procedure ClearGroup(const AGroup: TLzNexStatementGroup);
    // Copia PROFUNDA de toda a arvore.
    function Clone: TLzNexAst;
  end;

implementation

{ TLzNexStatement }

constructor TLzNexStatement.Create(const AKind: TLzNexStatementKind;
  const AGroup: TLzNexStatementGroup);
begin
  inherited Create;
  FKind := AKind;
  FGroup := AGroup;
  FBoolOp := boAnd;
  FNegated := False;
end;

{ TLzNexStatementList }

constructor TLzNexStatementList.Create;
begin
  inherited Create(True);   // OwnsObjects: a lista libera os statements
end;

procedure TLzNexStatementList.CloneInto(const ATarget: TLzNexStatementList);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    ATarget.Add(Items[I].Clone);
end;

{ TLzNexColumnStmt }

constructor TLzNexColumnStmt.Create(const AExpr: TLzNexValue; const AAlias: string);
begin
  inherited Create(skColumn, sgColumns);
  Expr := AExpr;
  Alias := AAlias;
end;

function TLzNexColumnStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexColumnStmt.Create(Expr, Alias);
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
end;

{ TLzNexAggregateStmt }

constructor TLzNexAggregateStmt.Create(const AAgg: TLzNexAggregate;
  const AColumn: TLzNexValue; const AAlias: string; const ADistinct: Boolean);
begin
  inherited Create(skAggregate, sgColumns);
  Agg := AAgg;
  Column := AColumn;
  Alias := AAlias;
  Distinct := ADistinct;
end;

function TLzNexAggregateStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexAggregateStmt.Create(Agg, Column, Alias, Distinct);
end;

{ TLzNexDistinctStmt }

constructor TLzNexDistinctStmt.Create(const AColumns: TLzNexValues);
begin
  inherited Create(skDistinct, sgColumns);
  Columns := Copy(AColumns);
end;

function TLzNexDistinctStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexDistinctStmt.Create(Columns);
end;

{ TLzNexBasicStmt }

constructor TLzNexBasicStmt.Create(const AGroup: TLzNexStatementGroup;
  const AColumn: TLzNexValue; const AOp: string; const AValue: TLzNexValue);
begin
  if AGroup = sgHaving then
    inherited Create(skHavingBasic, AGroup)
  else
    inherited Create(skWhereBasic, AGroup);
  Column := AColumn;
  Op := AOp;
  Value := AValue;
  AsColumn := False;
end;

function TLzNexBasicStmt.Clone: TLzNexStatement;
var
  C: TLzNexBasicStmt;
begin
  C := TLzNexBasicStmt.Create(Group, Column, Op, Value);
  C.AsColumn := AsColumn;
  C.BoolOp := BoolOp;
  C.Negated := Negated;
  Result := C;
end;

{ TLzNexInStmt }

constructor TLzNexInStmt.Create(const AGroup: TLzNexStatementGroup;
  const AColumns, AValues: TLzNexValues);
begin
  if AGroup = sgHaving then
    inherited Create(skHavingIn, AGroup)
  else
    inherited Create(skWhereIn, AGroup);
  Columns := Copy(AColumns);
  Values := Copy(AValues);
  Tuples := nil;
  Sub := nil;
end;

function TLzNexInStmt.Clone: TLzNexStatement;
var
  C: TLzNexInStmt;
  I: Integer;
begin
  C := TLzNexInStmt.Create(Group, Columns, Values);
  C.Sub := Sub;
  SetLength(C.Tuples, Length(Tuples));
  for I := 0 to High(Tuples) do
    C.Tuples[I] := Copy(Tuples[I]);
  C.BoolOp := BoolOp;
  C.Negated := Negated;
  Result := C;
end;

{ TLzNexNullStmt }

constructor TLzNexNullStmt.Create(const AGroup: TLzNexStatementGroup;
  const AColumn: TLzNexValue);
begin
  if AGroup = sgHaving then
    inherited Create(skHavingNull, AGroup)
  else
    inherited Create(skWhereNull, AGroup);
  Column := AColumn;
end;

function TLzNexNullStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexNullStmt.Create(Group, Column);
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
end;

{ TLzNexBetweenStmt }

constructor TLzNexBetweenStmt.Create(const AGroup: TLzNexStatementGroup;
  const AColumn, ALo, AHi: TLzNexValue);
begin
  if AGroup = sgHaving then
    inherited Create(skHavingBetween, AGroup)
  else
    inherited Create(skWhereBetween, AGroup);
  Column := AColumn;
  Lo := ALo;
  Hi := AHi;
end;

function TLzNexBetweenStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexBetweenStmt.Create(Group, Column, Lo, Hi);
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
end;

{ TLzNexLikeStmt }

constructor TLzNexLikeStmt.Create(const AGroup: TLzNexStatementGroup;
  const AColumn, APattern: TLzNexValue; const ACaseInsensitive: Boolean);
begin
  inherited Create(skWhereLike, AGroup);
  Column := AColumn;
  Pattern := APattern;
  CaseInsensitive := ACaseInsensitive;
end;

function TLzNexLikeStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexLikeStmt.Create(Group, Column, Pattern, CaseInsensitive);
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
end;

{ TLzNexExistsStmt }

constructor TLzNexExistsStmt.Create(const AGroup: TLzNexStatementGroup;
  const ASub: IInterface);
begin
  inherited Create(skWhereExists, AGroup);
  Sub := ASub;
end;

function TLzNexExistsStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexExistsStmt.Create(Group, Sub);
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
end;

{ TLzNexRawStmt }

constructor TLzNexRawStmt.Create(const AKind: TLzNexStatementKind;
  const AGroup: TLzNexStatementGroup; const ARaw: IInterface);
begin
  inherited Create(AKind, AGroup);
  Raw := ARaw;
end;

function TLzNexRawStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexRawStmt.Create(Kind, Group, Raw);
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
end;

{ TLzNexGroupStmt }

constructor TLzNexGroupStmt.Create(const AGroup: TLzNexStatementGroup);
begin
  if AGroup = sgHaving then
    inherited Create(skHavingGroup, AGroup)
  else
    inherited Create(skWhereGroup, AGroup);
  Items := TLzNexStatementList.Create;
end;

destructor TLzNexGroupStmt.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

function TLzNexGroupStmt.Clone: TLzNexStatement;
var
  C: TLzNexGroupStmt;
begin
  C := TLzNexGroupStmt.Create(Group);
  Items.CloneInto(C.Items);
  C.BoolOp := BoolOp;
  C.Negated := Negated;
  Result := C;
end;

{ TLzNexJoinClause }

function TLzNexJoinClause.Clone: TLzNexJoinClause;
begin
  Result := TLzNexJoinClause.Create;
  Result.ClauseKind := ClauseKind;
  Result.BoolOp := BoolOp;
  Result.Negated := Negated;
  Result.Left := Left;
  Result.Op := Op;
  Result.Right := Right;
  Result.Values := Copy(Values);
  Result.Sub := Sub;
  Result.Raw := Raw;
  Result.UsingColumns := Copy(UsingColumns);
end;

{ TLzNexJoinClauseList }

constructor TLzNexJoinClauseList.Create;
begin
  inherited Create(True);
end;

{ TLzNexJoinStmt }

constructor TLzNexJoinStmt.Create(const AJoinType: TLzNexJoinType;
  const ATable: TLzNexValue; const AAlias: string);
begin
  inherited Create(skJoin, sgJoin);
  JoinType := AJoinType;
  Table := ATable;
  Alias := AAlias;
  Clauses := TLzNexJoinClauseList.Create;
end;

destructor TLzNexJoinStmt.Destroy;
begin
  Clauses.Free;
  inherited Destroy;
end;

function TLzNexJoinStmt.Clone: TLzNexStatement;
var
  C: TLzNexJoinStmt;
  I: Integer;
begin
  C := TLzNexJoinStmt.Create(JoinType, Table, Alias);
  C.Raw := Raw;
  for I := 0 to Clauses.Count - 1 do
    C.Clauses.Add(Clauses[I].Clone);
  Result := C;
end;

{ TLzNexGroupByStmt }

constructor TLzNexGroupByStmt.Create(const AExpr: TLzNexValue; const ARaw: Boolean);
begin
  if ARaw then
    inherited Create(skGroupByRaw, sgGroup)
  else
    inherited Create(skGroupBy, sgGroup);
  Expr := AExpr;
end;

function TLzNexGroupByStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexGroupByStmt.Create(Expr, Kind = skGroupByRaw);
end;

{ TLzNexOrderByStmt }

constructor TLzNexOrderByStmt.Create(const AExpr: TLzNexValue;
  const ADir: TLzNexOrderDir; const ANulls: TLzNexNullsOrder; const ARaw: Boolean);
begin
  if ARaw then
    inherited Create(skOrderByRaw, sgOrder)
  else
    inherited Create(skOrderBy, sgOrder);
  Expr := AExpr;
  Dir := ADir;
  Nulls := ANulls;
end;

function TLzNexOrderByStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexOrderByStmt.Create(Expr, Dir, Nulls, Kind = skOrderByRaw);
end;

{ TLzNexUnionStmt }

constructor TLzNexUnionStmt.Create(const AUnionKind: TLzNexUnionKind;
  const ASub: IInterface; const AWrap: Boolean);
begin
  inherited Create(skUnion, sgUnion);
  UnionKind := AUnionKind;
  Sub := ASub;
  WrapInParens := AWrap;
end;

function TLzNexUnionStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexUnionStmt.Create(UnionKind, Sub, WrapInParens);
end;

{ TLzNexWithStmt }

constructor TLzNexWithStmt.Create(const AAlias: string; const AColumns: TLzNexValues;
  const ASub: IInterface; const ARecursive: Boolean);
begin
  inherited Create(skWith, sgWith);
  Alias := AAlias;
  Columns := Copy(AColumns);
  Sub := ASub;
  Recursive := ARecursive;
end;

function TLzNexWithStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexWithStmt.Create(Alias, Columns, Sub, Recursive);
end;

{ TLzNexHintStmt }

constructor TLzNexHintStmt.Create(const AText: string);
begin
  inherited Create(skHint, sgHint);
  Text := AText;
end;

function TLzNexHintStmt.Clone: TLzNexStatement;
begin
  Result := TLzNexHintStmt.Create(Text);
end;

{ TLzNexQuerySingle }

procedure TLzNexQuerySingle.Reset;
begin
  Method := qmSelect;
  Table := TLzNexValue.Unset;
  TableAlias := '';
  SchemaName := '';
  QueryAlias := '';
  LimitValue := TLzNexValue.Unset;
  OffsetValue := TLzNexValue.Unset;
  Lock := lkNone;
  Wait := wtDefault;
  InsertRows := nil;
  UpdateValues := nil;
  Counters := nil;
  Returning := nil;
  Conflict := caNone;
  ConflictTargets := nil;
  ConflictMerge := nil;
  PluckColumn := '';
end;

function TLzNexQuerySingle.Clone: TLzNexQuerySingle;
var
  I: Integer;
begin
  Result := Self;
  SetLength(Result.InsertRows, Length(InsertRows));
  for I := 0 to High(InsertRows) do
    Result.InsertRows[I] := Copy(InsertRows[I]);
  Result.UpdateValues := Copy(UpdateValues);
  Result.Counters := Copy(Counters);
  Result.Returning := Copy(Returning);
  Result.ConflictTargets := Copy(ConflictTargets);
  Result.ConflictMerge := Copy(ConflictMerge);
end;

function TLzNexQuerySingle.HasLimit: Boolean;
begin
  Result := not LimitValue.IsUnset;
end;

function TLzNexQuerySingle.HasOffset: Boolean;
begin
  Result := not OffsetValue.IsUnset;
end;

{ TLzNexAst }

constructor TLzNexAst.Create;
var
  G: TLzNexStatementGroup;
begin
  inherited Create;
  Single.Reset;
  for G := Low(TLzNexStatementGroup) to High(TLzNexStatementGroup) do
    FGroups[G] := TLzNexStatementList.Create;
end;

destructor TLzNexAst.Destroy;
var
  G: TLzNexStatementGroup;
begin
  for G := Low(TLzNexStatementGroup) to High(TLzNexStatementGroup) do
    FGroups[G].Free;
  inherited Destroy;
end;

function TLzNexAst.Group(const AGroup: TLzNexStatementGroup): TLzNexStatementList;
begin
  Result := FGroups[AGroup];
end;

function TLzNexAst.Add(const AStatement: TLzNexStatement): TLzNexStatement;
begin
  if AStatement = nil then
    raise ELzNexBuilder.Create('TLzNexAst.Add: statement nil');
  FGroups[AStatement.Group].Add(AStatement);
  Result := AStatement;
end;

function TLzNexAst.Has(const AGroup: TLzNexStatementGroup): Boolean;
begin
  Result := FGroups[AGroup].Count > 0;
end;

function TLzNexAst.CountOf(const AGroup: TLzNexStatementGroup): Integer;
begin
  Result := FGroups[AGroup].Count;
end;

procedure TLzNexAst.ClearGroup(const AGroup: TLzNexStatementGroup);
begin
  FGroups[AGroup].Clear;
end;

function TLzNexAst.Clone: TLzNexAst;
var
  G: TLzNexStatementGroup;
begin
  Result := TLzNexAst.Create;
  Result.Single := Single.Clone;
  for G := Low(TLzNexStatementGroup) to High(TLzNexStatementGroup) do
    FGroups[G].CloneInto(Result.FGroups[G]);
end;

end.
