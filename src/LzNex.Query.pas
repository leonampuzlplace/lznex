unit LzNex.Query;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Generics.Collections,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Client,
  LzNex.Raw,
  LzNex.Exceptions;

type
  TLzNexGroupStack = class(TList<TLzNexGroupStmt>);

  TLzNexQuery = class(TInterfacedObject, ILzNexQuery, ILzNexJoin, ILzNexOnConflict)
  private
    FClient: ILzNexClient;
    FDb: ILzNex;
    FTrx: ILzNexTransaction;
    FAst: TLzNexAst;

    FWhereStack: TLzNexGroupStack;
    FHavingStack: TLzNexGroupStack;

    FCurrentJoin: TLzNexJoinStmt;

    procedure Emit(const AStmt: TLzNexStatement);

    function StackOf(const AGroup: TLzNexStatementGroup): TLzNexGroupStack;

    procedure AddBasic(const AGroup: TLzNexStatementGroup; const ACol, AOp: string;
      const AValue: TLzNexValue; const ABool: TLzNexBoolOp = boAnd;
      const ANot: Boolean = False; const AAsColumn: Boolean = False);

    procedure AddIn(const AGroup: TLzNexStatementGroup; const ACol: string;
      const AValues: TLzNexValues; const ASub: IInterface = nil;
      const ABool: TLzNexBoolOp = boAnd; const ANot: Boolean = False);
    procedure AddNull(const AGroup: TLzNexStatementGroup; const ACol: string;
      const ABool: TLzNexBoolOp = boAnd; const ANot: Boolean = False);
    procedure AddBetween(const AGroup: TLzNexStatementGroup; const ACol: string;
      const ALo, AHi: TLzNexValue; const ABool: TLzNexBoolOp = boAnd;
      const ANot: Boolean = False);
    procedure AddLike(const ACol: string; const APattern: TLzNexValue;
      const ANot: Boolean = False; const ACaseInsensitive: Boolean = False;
      const ABool: TLzNexBoolOp = boAnd);
    procedure AddExists(const ASub: IInterface; const ANot: Boolean = False;
      const ABool: TLzNexBoolOp = boAnd);
    procedure AddRawStmt(const AKind: TLzNexStatementKind;
      const AGroup: TLzNexStatementGroup; const ARaw: ILzNexRaw;
      const ABool: TLzNexBoolOp = boAnd);
    procedure OpenGroup(const AGroup: TLzNexStatementGroup;
      const ABool: TLzNexBoolOp = boAnd; const ANot: Boolean = False);
    procedure CloseGroup(const AGroup: TLzNexStatementGroup);

    function StartJoin(const AType: TLzNexJoinType; const ATable: TLzNexValue;
      const AAlias: string): ILzNexJoin;

    function RequireJoin: TLzNexJoinStmt;
    procedure AddClause(const AKind: TLzNexJoinClauseKind;
      const ALeft: TLzNexValue; const AOp: string; const ARight: TLzNexValue;
      const ABool: TLzNexBoolOp = boAnd; const ANot: Boolean = False);

    function ActiveConnection: ILzNexConnection;

    function RunExecute: Int64;
  public
    constructor Create(const AClient: ILzNexClient; const ADb: ILzNex;
      const ATrx: ILzNexTransaction);
    destructor Destroy; override;

    function Table(const AName: string): ILzNexQuery;
    function From(const AName: string): ILzNexQuery;
    function FromAs(const AName, AAlias: string): ILzNexQuery;
    function FromSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;
    function FromRaw(const ARaw: ILzNexRaw): ILzNexQuery;
    function WithSchema(const ASchema: string): ILzNexQuery;
    function AsAlias(const AAlias: string): ILzNexQuery;

    function Select(const AColumns: array of string): ILzNexQuery;
    function Column(const AColumn: string): ILzNexQuery;
    function SelectAs(const AColumn, AAlias: string): ILzNexQuery;
    function SelectRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function SelectSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;
    function Distinct: ILzNexQuery;
    function DistinctOn(const AColumns: array of string): ILzNexQuery;

    function Where(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function Where(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function WhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function WhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhere(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhere(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;

    function WhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;
    function OrWhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;

    function WhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function WhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function OrWhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function OrWhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function WhereInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;
    function WhereNotInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;

    function WhereNull(const AColumn: string): ILzNexQuery;
    function WhereNotNull(const AColumn: string): ILzNexQuery;
    function OrWhereNull(const AColumn: string): ILzNexQuery;
    function OrWhereNotNull(const AColumn: string): ILzNexQuery;

    function WhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function WhereNotBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function OrWhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;

    function WhereLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
    function WhereNotLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
    function WhereILike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;

    function WhereExists(const ASub: ILzNexQuery): ILzNexQuery;
    function WhereNotExists(const ASub: ILzNexQuery): ILzNexQuery;

    function WhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function OrWhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function WhereOpen: ILzNexQuery;
    function OrWhereOpen: ILzNexQuery;
    function WhereNotOpen: ILzNexQuery;
    function WhereClose: ILzNexQuery;

    function Join(const ATable: string): ILzNexJoin;
    function JoinAs(const ATable, AAlias: string): ILzNexJoin;
    function InnerJoin(const ATable: string): ILzNexJoin;
    function LeftJoin(const ATable: string): ILzNexJoin;
    function LeftOuterJoin(const ATable: string): ILzNexJoin;
    function RightJoin(const ATable: string): ILzNexJoin;
    function RightOuterJoin(const ATable: string): ILzNexJoin;
    function FullOuterJoin(const ATable: string): ILzNexJoin;
    function CrossJoin(const ATable: string): ILzNexJoin;
    function JoinSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexJoin;
    function JoinRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function GroupBy(const AColumns: array of string): ILzNexQuery;
    function GroupByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function Having(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
    function OrHaving(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
    function HavingIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function HavingNull(const AColumn: string): ILzNexQuery;
    function HavingNotNull(const AColumn: string): ILzNexQuery;
    function HavingBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function HavingRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function HavingOpen: ILzNexQuery;
    function HavingClose: ILzNexQuery;

    function OrderBy(const AColumn: string): ILzNexQuery; overload;
    function OrderBy(const AColumn: string; const ADir: TLzNexOrderDir): ILzNexQuery; overload;
    function OrderBy(const AColumn: string; const ADir: TLzNexOrderDir;
      const ANulls: TLzNexNullsOrder): ILzNexQuery; overload;
    function OrderByDesc(const AColumn: string): ILzNexQuery;
    function OrderByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function Limit(const ACount: Int64): ILzNexQuery;
    function Offset(const ACount: Int64): ILzNexQuery;
    function Page(const APage, APerPage: Int64): ILzNexQuery;
    function ForUpdate: ILzNexQuery;
    function ForShare: ILzNexQuery;
    function SkipLocked: ILzNexQuery;
    function NoWait: ILzNexQuery;

    function Union(const ASub: ILzNexQuery): ILzNexQuery;
    function UnionAll(const ASub: ILzNexQuery): ILzNexQuery;
    function Intersect(const ASub: ILzNexQuery): ILzNexQuery;
    function Except_(const ASub: ILzNexQuery): ILzNexQuery;
    function With_(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
    function WithRecursive(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
    function HintComment(const AHint: string): ILzNexQuery;

    function OnConflict(const AColumns: array of string): ILzNexOnConflict;
    function Returning(const AColumns: array of string): ILzNexQuery;

    function Clear(const AGroup: TLzNexStatementGroup): ILzNexQuery;
    function Clone: ILzNexQuery;
    function Transacting(const ATrx: ILzNexTransaction): ILzNexQuery;

    function ToSQL: TLzNexFragment;
    function ToSQLString: string;

    function Get: ILzNexResult;
    function First: ILzNexRow;
    function Value(const AColumn: string): TLzNexValue;
    function Scalar: TLzNexValue;
    function Pluck(const AColumn: string): TLzNexValues;
    function Exists: Boolean;
    function Count: Int64;
    function Aggregate(const AAgg: TLzNexAggregate; const AColumn: string): TLzNexValue;

    function Insert(const AValues: TLzNexNamedValues): Int64;
    function InsertGetId(const AValues: TLzNexNamedValues): Int64; overload;
    function InsertGetId(const AValues: TLzNexNamedValues;
      const AIdColumn: string): Int64; overload;
    function InsertMany(const ARows: array of TLzNexNamedValues): Int64;
    function Update(const AValues: TLzNexNamedValues): Int64;
    function Increment(const AColumn: string; const ABy: Int64 = 1): Int64;
    function Decrement(const AColumn: string; const ABy: Int64 = 1): Int64;
    function Delete: Int64;
    procedure Truncate;

    function Ast: TLzNexAst;
    function Client: ILzNexClient;
    function OpenGroupCount: Integer;

    function OnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function OnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function AndOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function OrOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function AndOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function OrOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function OnIn(const AColumn: string; const AValues: TLzNexValues): ILzNexJoin;
    function OnNull(const AColumn: string): ILzNexJoin;
    function OnNotNull(const AColumn: string): ILzNexJoin;
    function OnBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexJoin;
    function OnRaw(const ASQL: string; const AArgs: array of const): ILzNexJoin;
    function Using(const AColumns: array of string): ILzNexJoin;

    function Ignore: ILzNexQuery;
    function Merge: ILzNexQuery; overload;
    function Merge(const AColumns: array of string): ILzNexQuery; overload;
    function MergeValues(const AValues: TLzNexNamedValues): ILzNexQuery;
  end;

function NewQuery(const AClient: ILzNexClient): ILzNexQuery;

function NewBoundQuery(const ADb: ILzNex; const ATrx: ILzNexTransaction): ILzNexQuery;

implementation

function Ident(const AName: string): TLzNexValue;
begin
  Result := TLzNexValue.Identifier(AName);
end;

constructor TLzNexQuery.Create(const AClient: ILzNexClient; const ADb: ILzNex;
  const ATrx: ILzNexTransaction);
begin
  inherited Create;
  if AClient = nil then
    raise ELzNexBuilder.Create('TLzNexQuery: dialect (ILzNexClient) not given');
  FClient := AClient;
  FDb := ADb;
  FTrx := ATrx;
  FAst := TLzNexAst.Create;
  FWhereStack := TLzNexGroupStack.Create;
  FHavingStack := TLzNexGroupStack.Create;
  FCurrentJoin := nil;
end;

destructor TLzNexQuery.Destroy;
begin
  FWhereStack.Free;
  FHavingStack.Free;
  FAst.Free;
  inherited Destroy;
end;

function TLzNexQuery.StackOf(const AGroup: TLzNexStatementGroup): TLzNexGroupStack;
begin
  if AGroup = sgHaving then
    Result := FHavingStack
  else
    Result := FWhereStack;
end;

procedure TLzNexQuery.Emit(const AStmt: TLzNexStatement);
var
  Stack: TLzNexGroupStack;
begin
  if AStmt.Group in [sgWhere, sgHaving] then
  begin
    Stack := StackOf(AStmt.Group);
    if Stack.Count > 0 then
    begin
      Stack[Stack.Count - 1].Items.Add(AStmt);
      Exit;
    end;
  end;
  FAst.Add(AStmt);
end;

function TLzNexQuery.Table(const AName: string): ILzNexQuery;
begin
  Result := From(AName);
end;

function TLzNexQuery.From(const AName: string): ILzNexQuery;
begin
  FAst.Single.Table := Ident(AName);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.FromAs(const AName, AAlias: string): ILzNexQuery;
begin
  FAst.Single.Table := Ident(AName);
  FAst.Single.TableAlias := AAlias;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.FromSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('FromSub: subquery nil');
  if Trim(AAlias) = '' then
    raise ELzNexBuilder.Create('FromSub: an alias is required for a subquery in the from clause');
  FAst.Single.Table := TLzNexValue.SubQuery(ASub);
  FAst.Single.TableAlias := AAlias;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.FromRaw(const ARaw: ILzNexRaw): ILzNexQuery;
begin
  if ARaw = nil then
    raise ELzNexBuilder.Create('FromRaw: raw nil');
  FAst.Single.Table := TLzNexValue.Raw(ARaw);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WithSchema(const ASchema: string): ILzNexQuery;
begin
  FAst.Single.SchemaName := ASchema;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.AsAlias(const AAlias: string): ILzNexQuery;
begin
  FAst.Single.QueryAlias := AAlias;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Select(const AColumns: array of string): ILzNexQuery;
var
  I: Integer;
begin
  for I := 0 to High(AColumns) do
    FAst.Add(TLzNexColumnStmt.Create(Ident(AColumns[I])));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Column(const AColumn: string): ILzNexQuery;
begin
  FAst.Add(TLzNexColumnStmt.Create(Ident(AColumn)));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.SelectAs(const AColumn, AAlias: string): ILzNexQuery;
begin
  FAst.Add(TLzNexColumnStmt.Create(Ident(AColumn), AAlias));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.SelectRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
var
  R: ILzNexRaw;
begin
  R := LzNexRaw(ASQL, AArgs);
  FAst.Add(TLzNexRawStmt.Create(skColumnRaw, sgColumns, R));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.SelectSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('SelectSub: subquery nil');

  FAst.Add(TLzNexColumnStmt.Create(TLzNexValue.SubQuery(ASub), AAlias));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Distinct: ILzNexQuery;
begin
  FAst.Add(TLzNexDistinctStmt.Create(nil));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.DistinctOn(const AColumns: array of string): ILzNexQuery;
var
  Cols: TLzNexValues;
  I: Integer;
begin
  if not FClient.SupportsDistinctOn then
    raise ELzNexCompile.CreateFmt(
      'DistinctOn: dialect "%s" does not support DISTINCT ON', [FClient.DialectName]);
  if Length(AColumns) = 0 then
    raise ELzNexBuilder.Create('DistinctOn: give at least one column');
  Cols := nil;
  SetLength(Cols, Length(AColumns));
  for I := 0 to High(AColumns) do
    Cols[I] := Ident(AColumns[I]);
  FAst.Add(TLzNexDistinctStmt.Create(Cols));
  Result := Self as ILzNexQuery;
end;

procedure TLzNexQuery.AddBasic(const AGroup: TLzNexStatementGroup;
  const ACol, AOp: string; const AValue: TLzNexValue; const ABool: TLzNexBoolOp;
  const ANot: Boolean; const AAsColumn: Boolean);
var
  S: TLzNexBasicStmt;
  Op: string;
begin

  Op := NormalizeOperator(AOp);
  S := TLzNexBasicStmt.Create(AGroup, Ident(ACol), Op, AValue);
  S.AsColumn := AAsColumn;
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
end;

procedure TLzNexQuery.AddIn(const AGroup: TLzNexStatementGroup; const ACol: string;
  const AValues: TLzNexValues; const ASub: IInterface; const ABool: TLzNexBoolOp;
  const ANot: Boolean);
var
  S: TLzNexInStmt;
  Cols: TLzNexValues;
begin
  Cols := nil;
  SetLength(Cols, 1);
  Cols[0] := Ident(ACol);
  S := TLzNexInStmt.Create(AGroup, Cols, AValues);
  S.Sub := ASub;
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
end;

procedure TLzNexQuery.AddNull(const AGroup: TLzNexStatementGroup; const ACol: string;
  const ABool: TLzNexBoolOp; const ANot: Boolean);
var
  S: TLzNexNullStmt;
begin
  S := TLzNexNullStmt.Create(AGroup, Ident(ACol));
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
end;

procedure TLzNexQuery.AddBetween(const AGroup: TLzNexStatementGroup; const ACol: string;
  const ALo, AHi: TLzNexValue; const ABool: TLzNexBoolOp; const ANot: Boolean);
var
  S: TLzNexBetweenStmt;
begin
  S := TLzNexBetweenStmt.Create(AGroup, Ident(ACol), ALo, AHi);
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
end;

procedure TLzNexQuery.AddLike(const ACol: string; const APattern: TLzNexValue;
  const ANot: Boolean; const ACaseInsensitive: Boolean; const ABool: TLzNexBoolOp);
var
  S: TLzNexLikeStmt;
begin
  S := TLzNexLikeStmt.Create(sgWhere, Ident(ACol), APattern, ACaseInsensitive);
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
end;

procedure TLzNexQuery.AddExists(const ASub: IInterface; const ANot: Boolean;
  const ABool: TLzNexBoolOp);
var
  S: TLzNexExistsStmt;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('WhereExists: subquery nil');
  S := TLzNexExistsStmt.Create(sgWhere, ASub);
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
end;

procedure TLzNexQuery.AddRawStmt(const AKind: TLzNexStatementKind;
  const AGroup: TLzNexStatementGroup; const ARaw: ILzNexRaw; const ABool: TLzNexBoolOp);
var
  S: TLzNexRawStmt;
begin
  S := TLzNexRawStmt.Create(AKind, AGroup, ARaw);
  S.BoolOp := ABool;
  Emit(S);
end;

procedure TLzNexQuery.OpenGroup(const AGroup: TLzNexStatementGroup;
  const ABool: TLzNexBoolOp; const ANot: Boolean);
var
  S: TLzNexGroupStmt;
begin
  S := TLzNexGroupStmt.Create(AGroup);
  S.BoolOp := ABool;
  S.Negated := ANot;
  Emit(S);
  StackOf(AGroup).Add(S);
end;

procedure TLzNexQuery.CloseGroup(const AGroup: TLzNexStatementGroup);
var
  Stack: TLzNexGroupStack;
begin
  Stack := StackOf(AGroup);
  if Stack.Count = 0 then
    raise ELzNexBuilder.Create(
      'Group close without a matching open: there is no open predicate group. ' +
      'Every WhereClose/HavingClose needs a WhereOpen/HavingOpen before it.');
  Stack.Delete(Stack.Count - 1);
end;

function TLzNexQuery.Where(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, '=', AValue);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Where(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, AOp, AValue);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, '=', AValue, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, AOp, AValue, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhere(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, '=', AValue, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhere(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, AOp, AValue, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, '=', AValue, boOr, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgWhere, AColumn, AOp, AValue, boOr, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;
begin
  AddBasic(sgWhere, ALeft, AOp, Ident(ARight), boAnd, False, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;
begin
  AddBasic(sgWhere, ALeft, AOp, Ident(ARight), boOr, False, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
begin
  AddIn(sgWhere, AColumn, AValues);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
begin
  AddIn(sgWhere, AColumn, AValues, nil, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
begin
  AddIn(sgWhere, AColumn, AValues, nil, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
begin
  AddIn(sgWhere, AColumn, AValues, nil, boOr, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('WhereInSub: subquery nil');
  AddIn(sgWhere, AColumn, nil, ASub);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('WhereNotInSub: subquery nil');
  AddIn(sgWhere, AColumn, nil, ASub, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNull(const AColumn: string): ILzNexQuery;
begin
  AddNull(sgWhere, AColumn);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotNull(const AColumn: string): ILzNexQuery;
begin
  AddNull(sgWhere, AColumn, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereNull(const AColumn: string): ILzNexQuery;
begin
  AddNull(sgWhere, AColumn, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereNotNull(const AColumn: string): ILzNexQuery;
begin
  AddNull(sgWhere, AColumn, boOr, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
begin
  AddBetween(sgWhere, AColumn, ALo, AHi);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
begin
  AddBetween(sgWhere, AColumn, ALo, AHi, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
begin
  AddBetween(sgWhere, AColumn, ALo, AHi, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
begin
  AddLike(AColumn, APattern);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
begin
  AddLike(AColumn, APattern, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereILike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
begin
  AddLike(AColumn, APattern, False, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereExists(const ASub: ILzNexQuery): ILzNexQuery;
begin
  AddExists(ASub);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotExists(const ASub: ILzNexQuery): ILzNexQuery;
begin
  AddExists(ASub, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
begin
  AddRawStmt(skWhereRaw, sgWhere, LzNexRaw(ASQL, AArgs));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
begin
  AddRawStmt(skWhereRaw, sgWhere, LzNexRaw(ASQL, AArgs), boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereOpen: ILzNexQuery;
begin
  OpenGroup(sgWhere);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrWhereOpen: ILzNexQuery;
begin
  OpenGroup(sgWhere, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereNotOpen: ILzNexQuery;
begin
  OpenGroup(sgWhere, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WhereClose: ILzNexQuery;
begin
  CloseGroup(sgWhere);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.StartJoin(const AType: TLzNexJoinType; const ATable: TLzNexValue;
  const AAlias: string): ILzNexJoin;
var
  J: TLzNexJoinStmt;
begin
  J := TLzNexJoinStmt.Create(AType, ATable, AAlias);
  FAst.Add(J);
  FCurrentJoin := J;
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.RequireJoin: TLzNexJoinStmt;
begin
  if FCurrentJoin = nil then
    raise ELzNexBuilder.Create(
      'ON clause without a join: call Join/LeftJoin/... before On*. ' +
      'Clone does not inherit the current join either.');
  Result := FCurrentJoin;
end;

procedure TLzNexQuery.AddClause(const AKind: TLzNexJoinClauseKind;
  const ALeft: TLzNexValue; const AOp: string; const ARight: TLzNexValue;
  const ABool: TLzNexBoolOp; const ANot: Boolean);
var
  J: TLzNexJoinStmt;
  C: TLzNexJoinClause;
  Op: string;
begin
  J := RequireJoin;

  if AOp = '' then
    Op := ''
  else
    Op := NormalizeOperator(AOp);

  C := TLzNexJoinClause.Create;
  C.ClauseKind := AKind;
  C.BoolOp := ABool;
  C.Negated := ANot;
  C.Left := ALeft;
  C.Op := Op;
  C.Right := ARight;
  J.Clauses.Add(C);
end;

function TLzNexQuery.Join(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtInner, Ident(ATable), '');
end;

function TLzNexQuery.JoinAs(const ATable, AAlias: string): ILzNexJoin;
begin
  Result := StartJoin(jtInner, Ident(ATable), AAlias);
end;

function TLzNexQuery.InnerJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtInner, Ident(ATable), '');
end;

function TLzNexQuery.LeftJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtLeft, Ident(ATable), '');
end;

function TLzNexQuery.LeftOuterJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtLeftOuter, Ident(ATable), '');
end;

function TLzNexQuery.RightJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtRight, Ident(ATable), '');
end;

function TLzNexQuery.RightOuterJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtRightOuter, Ident(ATable), '');
end;

function TLzNexQuery.FullOuterJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtFullOuter, Ident(ATable), '');
end;

function TLzNexQuery.CrossJoin(const ATable: string): ILzNexJoin;
begin
  Result := StartJoin(jtCross, Ident(ATable), '');
end;

function TLzNexQuery.JoinSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexJoin;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('JoinSub: subquery nil');
  if Trim(AAlias) = '' then
    raise ELzNexBuilder.Create('JoinSub: an alias is required for a subquery in the join');
  Result := StartJoin(jtInner, TLzNexValue.SubQuery(ASub), AAlias);
end;

function TLzNexQuery.JoinRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
var
  J: TLzNexJoinStmt;
  R: ILzNexRaw;
begin

  R := LzNexRaw(ASQL, AArgs);
  J := TLzNexJoinStmt.Create(jtRaw, TLzNexValue.Unset, '');
  J.Raw := R;
  FAst.Add(J);

  FCurrentJoin := nil;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
begin
  AddClause(jcColumns, Ident(ALeft), AOp, Ident(ARight));
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.OnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
begin
  AddClause(jcValue, Ident(AColumn), AOp, AValue);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.AndOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
begin
  Result := OnColumns(ALeft, AOp, ARight);
end;

function TLzNexQuery.OrOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
begin
  AddClause(jcColumns, Ident(ALeft), AOp, Ident(ARight), boOr);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.AndOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
begin
  Result := OnValue(AColumn, AOp, AValue);
end;

function TLzNexQuery.OrOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
begin
  AddClause(jcValue, Ident(AColumn), AOp, AValue, boOr);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.OnIn(const AColumn: string; const AValues: TLzNexValues): ILzNexJoin;
var
  J: TLzNexJoinStmt;
  C: TLzNexJoinClause;
begin
  J := RequireJoin;
  C := TLzNexJoinClause.Create;
  C.ClauseKind := jcIn;
  C.Left := Ident(AColumn);
  C.Values := Copy(AValues);
  J.Clauses.Add(C);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.OnNull(const AColumn: string): ILzNexJoin;
begin
  AddClause(jcNull, Ident(AColumn), '', TLzNexValue.Null);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.OnNotNull(const AColumn: string): ILzNexJoin;
begin
  AddClause(jcNull, Ident(AColumn), '', TLzNexValue.Null, boAnd, True);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.OnBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexJoin;
var
  J: TLzNexJoinStmt;
  C: TLzNexJoinClause;
begin
  J := RequireJoin;
  C := TLzNexJoinClause.Create;
  C.ClauseKind := jcBetween;
  C.Left := Ident(AColumn);

  SetLength(C.Values, 2);
  C.Values[0] := ALo;
  C.Values[1] := AHi;
  J.Clauses.Add(C);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.OnRaw(const ASQL: string; const AArgs: array of const): ILzNexJoin;
var
  J: TLzNexJoinStmt;
  C: TLzNexJoinClause;
  R: ILzNexRaw;
begin
  J := RequireJoin;

  R := LzNexRaw(ASQL, AArgs);
  C := TLzNexJoinClause.Create;
  C.ClauseKind := jcRaw;
  C.Raw := R;
  J.Clauses.Add(C);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.Using(const AColumns: array of string): ILzNexJoin;
var
  J: TLzNexJoinStmt;
  C: TLzNexJoinClause;
  I: Integer;
begin
  J := RequireJoin;
  if Length(AColumns) = 0 then
    raise ELzNexBuilder.Create('Using: give at least one column');
  C := TLzNexJoinClause.Create;
  C.ClauseKind := jcUsing;
  SetLength(C.UsingColumns, Length(AColumns));
  for I := 0 to High(AColumns) do
    C.UsingColumns[I] := Ident(AColumns[I]);
  J.Clauses.Add(C);
  Result := Self as ILzNexJoin;
end;

function TLzNexQuery.GroupBy(const AColumns: array of string): ILzNexQuery;
var
  I: Integer;
begin
  for I := 0 to High(AColumns) do
    FAst.Add(TLzNexGroupByStmt.Create(Ident(AColumns[I])));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.GroupByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
var
  R: ILzNexRaw;
begin
  R := LzNexRaw(ASQL, AArgs);
  FAst.Add(TLzNexGroupByStmt.Create(TLzNexValue.Raw(R), True));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Having(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgHaving, AColumn, AOp, AValue);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrHaving(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
begin
  AddBasic(sgHaving, AColumn, AOp, AValue, boOr);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
begin
  AddIn(sgHaving, AColumn, AValues);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingNull(const AColumn: string): ILzNexQuery;
begin
  AddNull(sgHaving, AColumn);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingNotNull(const AColumn: string): ILzNexQuery;
begin
  AddNull(sgHaving, AColumn, boAnd, True);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
begin
  AddBetween(sgHaving, AColumn, ALo, AHi);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
begin
  AddRawStmt(skHavingRaw, sgHaving, LzNexRaw(ASQL, AArgs));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingOpen: ILzNexQuery;
begin
  OpenGroup(sgHaving);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HavingClose: ILzNexQuery;
begin
  CloseGroup(sgHaving);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrderBy(const AColumn: string): ILzNexQuery;
begin
  Result := OrderBy(AColumn, odAsc, nlDefault);
end;

function TLzNexQuery.OrderBy(const AColumn: string; const ADir: TLzNexOrderDir): ILzNexQuery;
begin
  Result := OrderBy(AColumn, ADir, nlDefault);
end;

function TLzNexQuery.OrderBy(const AColumn: string; const ADir: TLzNexOrderDir;
  const ANulls: TLzNexNullsOrder): ILzNexQuery;
begin
  FAst.Add(TLzNexOrderByStmt.Create(Ident(AColumn), ADir, ANulls));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OrderByDesc(const AColumn: string): ILzNexQuery;
begin
  Result := OrderBy(AColumn, odDesc, nlDefault);
end;

function TLzNexQuery.OrderByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
var
  R: ILzNexRaw;
begin
  R := LzNexRaw(ASQL, AArgs);
  FAst.Add(TLzNexOrderByStmt.Create(TLzNexValue.Raw(R), odAsc, nlDefault, True));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Limit(const ACount: Int64): ILzNexQuery;
begin
  if ACount < 0 then
    raise ELzNexBuilder.CreateFmt('Limit: negative value (%d)', [ACount]);
  FAst.Single.LimitValue := TLzNexValue.FromInt64(ACount);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Offset(const ACount: Int64): ILzNexQuery;
begin
  if ACount < 0 then
    raise ELzNexBuilder.CreateFmt('Offset: negative value (%d)', [ACount]);
  FAst.Single.OffsetValue := TLzNexValue.FromInt64(ACount);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Page(const APage, APerPage: Int64): ILzNexQuery;
begin
  if APage < 1 then
    raise ELzNexBuilder.CreateFmt('Page: the page number is 1-based, got %d', [APage]);
  if APerPage < 1 then
    raise ELzNexBuilder.CreateFmt('Page: items per page must be >= 1, got %d', [APerPage]);
  Limit(APerPage);
  Offset((APage - 1) * APerPage);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.ForUpdate: ILzNexQuery;
begin
  FAst.Single.Lock := lkForUpdate;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.ForShare: ILzNexQuery;
begin
  FAst.Single.Lock := lkForShare;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.SkipLocked: ILzNexQuery;
begin
  FAst.Single.Wait := wtSkipLocked;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.NoWait: ILzNexQuery;
begin
  FAst.Single.Wait := wtNoWait;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Union(const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('Union: subquery nil');
  FAst.Add(TLzNexUnionStmt.Create(ukUnion, ASub));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.UnionAll(const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('UnionAll: subquery nil');
  FAst.Add(TLzNexUnionStmt.Create(ukUnionAll, ASub));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Intersect(const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('Intersect: subquery nil');
  FAst.Add(TLzNexUnionStmt.Create(ukIntersect, ASub));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Except_(const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('Except_: subquery nil');
  FAst.Add(TLzNexUnionStmt.Create(ukExcept, ASub));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.With_(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('With_: subquery nil');
  if Trim(AAlias) = '' then
    raise ELzNexBuilder.Create('With_: the CTE alias is required');
  FAst.Add(TLzNexWithStmt.Create(AAlias, nil, ASub, False));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.WithRecursive(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
begin
  if ASub = nil then
    raise ELzNexBuilder.Create('WithRecursive: subquery nil');
  if Trim(AAlias) = '' then
    raise ELzNexBuilder.Create('WithRecursive: the CTE alias is required');
  FAst.Add(TLzNexWithStmt.Create(AAlias, nil, ASub, True));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.HintComment(const AHint: string): ILzNexQuery;
begin
  FAst.Add(TLzNexHintStmt.Create(AHint));
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.OnConflict(const AColumns: array of string): ILzNexOnConflict;
var
  I: Integer;
begin

  SetLength(FAst.Single.ConflictTargets, Length(AColumns));
  for I := 0 to High(AColumns) do
    FAst.Single.ConflictTargets[I] := Ident(AColumns[I]);
  Result := Self as ILzNexOnConflict;
end;

function TLzNexQuery.Ignore: ILzNexQuery;
begin
  FAst.Single.Conflict := caIgnore;
  FAst.Single.ConflictMerge := nil;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Merge: ILzNexQuery;
begin

  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictMerge := nil;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Merge(const AColumns: array of string): ILzNexQuery;
var
  I: Integer;
begin
  FAst.Single.Conflict := caMerge;

  SetLength(FAst.Single.ConflictMerge, Length(AColumns));
  for I := 0 to High(AColumns) do
  begin
    FAst.Single.ConflictMerge[I].Name := AColumns[I];
    FAst.Single.ConflictMerge[I].Value := TLzNexValue.Unset;
  end;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.MergeValues(const AValues: TLzNexNamedValues): ILzNexQuery;
begin
  if Length(AValues) = 0 then
    raise ELzNexBuilder.Create('MergeValues: give at least one column');
  FAst.Single.Conflict := caMerge;
  FAst.Single.ConflictMerge := Copy(AValues);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Returning(const AColumns: array of string): ILzNexQuery;
var
  I: Integer;
begin
  if not FClient.SupportsReturning then
    raise ELzNexCompile.CreateFmt(
      'Returning: dialect "%s" does not support RETURNING', [FClient.DialectName]);
  SetLength(FAst.Single.Returning, Length(AColumns));
  for I := 0 to High(AColumns) do
    FAst.Single.Returning[I] := Ident(AColumns[I]);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Clear(const AGroup: TLzNexStatementGroup): ILzNexQuery;
begin

  if AGroup in [sgWhere, sgHaving] then
    StackOf(AGroup).Clear;
  if AGroup = sgJoin then
    FCurrentJoin := nil;
  FAst.ClearGroup(AGroup);
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.Clone: ILzNexQuery;
var
  Q: TLzNexQuery;
  Copied: TLzNexAst;
begin
  if OpenGroupCount > 0 then
    raise ELzNexBuilder.CreateFmt(
      'Clone: there are %d open predicate group(s). Close them before cloning, ' +
      'otherwise the clone would inherit a stack pointing at the old tree.',
      [OpenGroupCount]);

  Copied := FAst.Clone;
  try
    Q := TLzNexQuery.Create(FClient, FDb, FTrx);
  except
    Copied.Free;
    raise;
  end;

  Q.FAst.Free;
  Q.FAst := Copied;
  Result := Q as ILzNexQuery;
end;

function TLzNexQuery.Transacting(const ATrx: ILzNexTransaction): ILzNexQuery;
begin
  FTrx := ATrx;
  Result := Self as ILzNexQuery;
end;

function TLzNexQuery.ToSQL: TLzNexFragment;
var
  Comp: ILzNexCompiler;
begin
  if OpenGroupCount > 0 then
    raise ELzNexBuilder.CreateFmt(
      'ToSQL: there are %d open predicate group(s) (where: %d, having: %d). ' +
      'A WhereClose/HavingClose is missing.',
      [OpenGroupCount, FWhereStack.Count, FHavingStack.Count]);
  Comp := FClient.NewCompiler;
  if Comp = nil then
    raise ELzNexBuilder.CreateFmt(
      'ToSQL: dialect "%s" returned no compiler', [FClient.DialectName]);
  Result := Comp.Compile(FAst);
end;

function TLzNexQuery.ToSQLString: string;
var
  Frag: TLzNexFragment;
  Binds: TLzNexBindings;
  SB: TStringBuilder;
  Txt: string;
  I, N: Integer;
begin
  Frag := ToSQL;
  Binds := Frag.Bindings;
  Txt := Frag.Text;
  N := 0;
  SB := TStringBuilder.Create;
  try

    for I := 1 to Length(Txt) do
      if (Txt[I] = '?') and (N < Binds.Count) then
      begin
        SB.Append(FClient.EscapeForLog(Binds.Items(N)));
        Inc(N);
      end
      else
        SB.Append(Txt[I]);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexQuery.ActiveConnection: ILzNexConnection;
begin
  if FTrx <> nil then
    Exit(FTrx.Connection);
  if FDb = nil then
    raise ELzNexBuilder.Create(
      'This query is not bound to a connection: it was created with NewQuery, ' +
      'which only builds SQL (ToSQL/ToSQLString). Use Db.Table(...) or ' +
      'NewBoundQuery to be able to execute.');
  Result := FDb.Connection;
end;

function TLzNexQuery.RunExecute: Int64;
var
  Conn: ILzNexConnection;
begin
  Conn := ActiveConnection;
  Result := Conn.Execute(ToSQL);
end;

function TLzNexQuery.Get: ILzNexResult;
var
  Conn: ILzNexConnection;
begin
  FAst.Single.Method := qmSelect;
  Conn := ActiveConnection;
  Result := Conn.Query(ToSQL);
end;

function TLzNexQuery.First: ILzNexRow;
var
  Conn: ILzNexConnection;
  Res: ILzNexResult;
begin
  Result := nil;
  FAst.Single.Method := qmFirst;
  if not FAst.Single.HasLimit then
    FAst.Single.LimitValue := TLzNexValue.FromInt64(1);
  Conn := ActiveConnection;
  Res := Conn.Query(ToSQL);
  if Res.Next then
    Result := Res.CurrentRow;
  Res.Close;
end;

function TLzNexQuery.Value(const AColumn: string): TLzNexValue;
var
  Row: ILzNexRow;
begin

  FAst.ClearGroup(sgColumns);
  Column(AColumn);
  Row := First;
  if Row = nil then
    Result := TLzNexValue.Null
  else
    Result := Row.FieldAt(0);
end;

function TLzNexQuery.Scalar: TLzNexValue;
var
  Row: ILzNexRow;
begin
  Row := First;
  if Row = nil then
    Result := TLzNexValue.Null
  else
    Result := Row.FieldAt(0);
end;

function TLzNexQuery.Pluck(const AColumn: string): TLzNexValues;
var
  Res: ILzNexResult;
  N: Integer;
begin
  Result := nil;
  FAst.ClearGroup(sgColumns);
  Column(AColumn);
  FAst.Single.PluckColumn := AColumn;
  Res := Get;
  N := 0;
  while Res.Next do
  begin
    if N >= Length(Result) then
      if Length(Result) = 0 then
        SetLength(Result, 16)
      else
        SetLength(Result, Length(Result) * 2);
    Result[N] := Res.FieldAt(0);
    Inc(N);
  end;
  Res.Close;
  SetLength(Result, N);
end;

function TLzNexQuery.Exists: Boolean;
begin
  Limit(1);
  Result := First <> nil;
end;

function TLzNexQuery.Count: Int64;
begin
  Result := Aggregate(agCount, '*').AsInt64;
end;

function TLzNexQuery.Aggregate(const AAgg: TLzNexAggregate;
  const AColumn: string): TLzNexValue;
var
  Row: ILzNexRow;
begin
  FAst.ClearGroup(sgColumns);
  FAst.Add(TLzNexAggregateStmt.Create(AAgg, Ident(AColumn), ''));
  Row := First;
  if Row = nil then
    Result := TLzNexValue.Null
  else
    Result := Row.FieldAt(0);
end;

function TLzNexQuery.Insert(const AValues: TLzNexNamedValues): Int64;
begin
  if Length(AValues) = 0 then
    raise ELzNexBuilder.Create('Insert: no columns given');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Copy(AValues);
  Result := RunExecute;
end;

function TLzNexQuery.InsertGetId(const AValues: TLzNexNamedValues): Int64;
begin
  Result := InsertGetId(AValues, 'id');
end;

function TLzNexQuery.InsertGetId(const AValues: TLzNexNamedValues;
  const AIdColumn: string): Int64;
var
  Conn: ILzNexConnection;
  Res: ILzNexResult;
begin
  if Length(AValues) = 0 then
    raise ELzNexBuilder.Create('InsertGetId: no columns given');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, 1);
  FAst.Single.InsertRows[0] := Copy(AValues);

  Conn := ActiveConnection;

  { Onde ha RETURNING, o id vem do proprio insert. O caminho alternativo
    pergunta ao banco qual foi o ultimo id da sessao, o que e sensivel a
    gatilho que escreva noutra tabela -- e o unico caminho em MySQL. }
  if (FClient <> nil) and FClient.SupportsReturning then
  begin
    Returning([AIdColumn]);
    Result := 0;
    Res := Conn.Query(ToSQL);
    try
      if Res.Next then
        Result := Res.FieldAt(0).AsInt64;
    finally
      Res.Close;
    end;
    Exit;
  end;

  Conn.Execute(ToSQL);
  Result := Conn.LastInsertId;
end;

function TLzNexQuery.InsertMany(const ARows: array of TLzNexNamedValues): Int64;
var
  I: Integer;
begin
  if Length(ARows) = 0 then
    raise ELzNexBuilder.Create('InsertMany: no rows given');
  FAst.Single.Method := qmInsert;
  SetLength(FAst.Single.InsertRows, Length(ARows));
  for I := 0 to High(ARows) do
    FAst.Single.InsertRows[I] := Copy(ARows[I]);
  Result := RunExecute;
end;

function TLzNexQuery.Update(const AValues: TLzNexNamedValues): Int64;
begin
  if Length(AValues) = 0 then
    raise ELzNexBuilder.Create('Update: no columns given');
  FAst.Single.Method := qmUpdate;
  FAst.Single.UpdateValues := Copy(AValues);
  Result := RunExecute;
end;

function TLzNexQuery.Increment(const AColumn: string; const ABy: Int64): Int64;
begin
  FAst.Single.Method := qmUpdate;
  SetLength(FAst.Single.Counters, 1);
  FAst.Single.Counters[0].Name := AColumn;
  FAst.Single.Counters[0].Value := TLzNexValue.FromInt64(ABy);
  Result := RunExecute;
end;

function TLzNexQuery.Decrement(const AColumn: string; const ABy: Int64): Int64;
begin
  FAst.Single.Method := qmUpdate;
  SetLength(FAst.Single.Counters, 1);
  FAst.Single.Counters[0].Name := AColumn;
  FAst.Single.Counters[0].Value := TLzNexValue.FromInt64(-ABy);
  Result := RunExecute;
end;

function TLzNexQuery.Delete: Int64;
begin
  FAst.Single.Method := qmDelete;
  Result := RunExecute;
end;

procedure TLzNexQuery.Truncate;
begin
  FAst.Single.Method := qmTruncate;
  RunExecute;
end;

function TLzNexQuery.Ast: TLzNexAst;
begin

  Result := FAst;
end;

function TLzNexQuery.Client: ILzNexClient;
begin
  Result := FClient;
end;

function TLzNexQuery.OpenGroupCount: Integer;
begin
  Result := FWhereStack.Count + FHavingStack.Count;
end;

function NewQuery(const AClient: ILzNexClient): ILzNexQuery;
begin
  Result := TLzNexQuery.Create(AClient, nil, nil) as ILzNexQuery;
end;

function NewBoundQuery(const ADb: ILzNex; const ATrx: ILzNexTransaction): ILzNexQuery;
begin
  if ADb = nil then
    raise ELzNexBuilder.Create('NewBoundQuery: facade (ILzNex) not given');
  Result := TLzNexQuery.Create(ADb.Client, ADb, ATrx) as ILzNexQuery;
end;

end.
