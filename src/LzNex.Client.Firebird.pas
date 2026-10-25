unit LzNex.Client.Firebird;

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
  LzNex.Compiler,
  LzNex.Exceptions;

type
  TLzNexFirebirdCompiler = class(TLzNexCompilerBase)
  protected

    function CompileLimit: TLzNexFragment; override;
    function CompileOffset: TLzNexFragment; override;

    function CompileLock: TLzNexFragment; override;

    function CompileTruncate: TLzNexFragment; override;

    function InsertVerb: string; override;
    function CompileConflict(const AColumns: TLzNexStringArray): TLzNexFragment; override;

    function LikeOperator(const ACaseInsensitive, ANegated: Boolean): string; override;

    function CompileWhereLike(const AStmt: TLzNexLikeStmt): TLzNexFragment; override;

    function UnionWord(const AKind: TLzNexUnionKind): string; override;

    procedure DatePartWrap(const APart: TLzNexDatePart;
      out ABefore, AAfter: string); override;

    function RandomSQL: string; override;
  end;

  TLzNexFirebirdClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;

    function QuoteLiteral(const AValue: TLzNexValue): string; override;

    function SupportsReturning: Boolean; override;
    function SupportsOnConflictWhere: Boolean; override;
    function SupportsNullsOrdering: Boolean; override;
    function SupportsDistinctOn: Boolean; override;

    function DefaultIsolation: TLzNexIsolation; override;

    function IsRetryableError(const ACode: Integer;
      const ASQLState: string): Boolean; override;

    function Components(const AMethod: TLzNexQueryMethod): TLzNexComponents; override;
    function InvalidComponents(const AMethod: TLzNexQueryMethod): TLzNexComponents; override;

    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

implementation

uses

  LzNex.Schema.Firebird,

  ZDbcFirebird;

function TLzNexFirebirdCompiler.CompileLimit: TLzNexFragment;
begin
  if not FAst.Single.HasLimit then
  begin
    if FAst.Single.Method = qmFirst then
      Exit(TLzNexFragment.Param(TLzNexValue.FromInt64(1))
        .Wrap('fetch next ', ' rows only'));
    Exit(TLzNexFragment.Empty);
  end;
  Result := TLzNexFragment.Param(FAst.Single.LimitValue)
    .Wrap('fetch next ', ' rows only');
end;

function TLzNexFirebirdCompiler.CompileOffset: TLzNexFragment;
begin
  if not FAst.Single.HasOffset then
    Exit(TLzNexFragment.Empty);
  Result := TLzNexFragment.Param(FAst.Single.OffsetValue)
    .Wrap('offset ', ' rows');
end;

function TLzNexFirebirdCompiler.CompileLock: TLzNexFragment;
begin
  case FAst.Single.Lock of
    lkNone:
      Exit(TLzNexFragment.Empty);
    lkForShare:
      raise ELzNexCompile.Create(
        'ForShare does not exist in Firebird: WITH LOCK is always exclusive. ' +
        'Use ForUpdate, or a read committed transaction.');
  end;

  case FAst.Single.Wait of
    wtNoWait:
      raise ELzNexCompile.Create(
        'NoWait is not a clause of the Firebird lock: waiting is an attribute ' +
        'of the transaction. Open the transaction with ilReadCommitted, which ' +
        'already asks the server for nowait.');
    wtSkipLocked:
      Exit(Txt('with lock skip locked'));
  end;

  Result := Txt('with lock');
end;

function TLzNexFirebirdCompiler.CompileTruncate: TLzNexFragment;
begin
  if FAst.Single.Table.IsUnset then
    raise ELzNexCompile.Create('TRUNCATE requires a table.');
  Result := Txt('delete from').Concat(CompileTarget);
end;

function TLzNexFirebirdCompiler.InsertVerb: string;
begin
  if FAst.Single.Conflict = caMerge then
    Result := 'update or insert into'
  else
    Result := 'insert into';
end;

function TLzNexFirebirdCompiler.CompileConflict(
  const AColumns: TLzNexStringArray): TLzNexFragment;
begin
  case FAst.Single.Conflict of
    caNone:
      Exit(TLzNexFragment.Empty);
    caIgnore:
      raise ELzNexCompile.Create(
        'OnConflict.Ignore has no equivalent in Firebird: there is no ' +
        'ON CONFLICT DO NOTHING, and MERGE would need a cast on every ' +
        'parameter. Use OnConflict(...).Merge (UPDATE OR INSERT) or check ' +
        'with Exists before inserting.');
  end;

  if Length(FAst.Single.InsertRows) > 1 then
    raise ELzNexCompile.Create(
      'UPDATE OR INSERT takes a single row: Firebird has no multi-row upsert. ' +
      'Insert one row per call.');

  if Length(FAst.Single.ConflictMerge) > 0 then
    raise ELzNexCompile.Create(
      'UPDATE OR INSERT always updates every column of the row, so it cannot ' +
      'honour a Merge with a column list or with explicit values. Use Merge ' +
      'with no arguments, or write the MERGE by hand with Raw.');

  if Length(FAst.Single.ConflictTargets) = 0 then
    Exit(TLzNexFragment.Empty);

  Result := Txt('matching (' + IdentListV(FAst.Single.ConflictTargets) + ')');
end;

function TLzNexFirebirdCompiler.LikeOperator(const ACaseInsensitive,
  ANegated: Boolean): string;
begin
  if ANegated then
    Result := 'not like'
  else
    Result := 'like';
end;

function TLzNexFirebirdCompiler.CompileWhereLike(
  const AStmt: TLzNexLikeStmt): TLzNexFragment;
var
  Left, Pattern: TLzNexFragment;
begin
  if not AStmt.CaseInsensitive then
    Exit(inherited CompileWhereLike(AStmt));

  Left := CompileExpr(AStmt.Column, 'where like').Wrap('upper(', ')');
  Pattern := CompileBind(AStmt.Pattern, AStmt.Column.Text).Wrap('upper(', ')');
  Result := Left
    .Concat(Txt(LikeOperator(True, AStmt.Negated)))
    .Concat(Pattern);
end;

function TLzNexFirebirdCompiler.UnionWord(const AKind: TLzNexUnionKind): string;
begin
  if AKind in [ukIntersect, ukExcept] then
    raise ELzNexCompile.Create(
      'Firebird supports neither INTERSECT nor EXCEPT. Rewrite with ' +
      'WhereInSub or WhereNotExists.');
  Result := inherited UnionWord(AKind);
end;

procedure TLzNexFirebirdCompiler.DatePartWrap(const APart: TLzNexDatePart;
  out ABefore, AAfter: string);
begin
  if APart = dpSecond then
  begin

    ABefore := 'cast(extract(second from ';
    AAfter := ') as integer)';
    Exit;
  end;
  inherited DatePartWrap(APart, ABefore, AAfter);
end;

function TLzNexFirebirdCompiler.RandomSQL: string;
begin
  Result := 'rand()';
end;

function TLzNexFirebirdClient.DialectName: string;
begin
  Result := 'firebird';
end;

function TLzNexFirebirdClient.ZeosProtocol: string;
begin

  Result := 'firebird';
end;

function TLzNexFirebirdClient.QuoteLiteral(const AValue: TLzNexValue): string;
begin
  if AValue.Kind = vkBoolean then
  begin
    if AValue.AsBoolean then
      Result := 'true'
    else
      Result := 'false';
    Exit;
  end;
  Result := inherited QuoteLiteral(AValue);
end;

function TLzNexFirebirdClient.SupportsReturning: Boolean;
begin
  Result := True;
end;

function TLzNexFirebirdClient.SupportsOnConflictWhere: Boolean;
begin

  Result := False;
end;

function TLzNexFirebirdClient.SupportsNullsOrdering: Boolean;
begin

  Result := True;
end;

function TLzNexFirebirdClient.SupportsDistinctOn: Boolean;
begin
  Result := False;
end;

function TLzNexFirebirdClient.DefaultIsolation: TLzNexIsolation;
begin

  Result := ilReadCommitted;
end;

function TLzNexFirebirdClient.IsRetryableError(const ACode: Integer;
  const ASQLState: string): Boolean;
begin

  if (ACode = 335544336) or (ACode = 335544451) then
    Exit(True);
  Result := inherited IsRetryableError(ACode, ASQLState);
end;

function TLzNexFirebirdClient.Components(
  const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of
    qmSelect, qmFirst:

      Result := TLzNexComponents.Create(
        cpHints, cpColumns, cpFrom, cpJoin, cpWhere, cpGroup, cpHaving,
        cpUnion, cpOrder, cpOffset, cpLimit, cpLock);
  else
    Result := inherited Components(AMethod);
  end;
end;

function TLzNexFirebirdClient.InvalidComponents(
  const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of

    qmDelete, qmUpdate:
      Result := TLzNexComponents.Create(cpHaving, cpGroup, cpLimit, cpJoin);
  else
    Result := inherited InvalidComponents(AMethod);
  end;
end;

function TLzNexFirebirdClient.NewCompiler: ILzNexCompiler;
begin
  Result := TLzNexFirebirdCompiler.Create(Self);
end;

function TLzNexFirebirdClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := NewFirebirdSchemaCompiler(Self);
end;

initialization
  RegisterClient('firebird', TLzNexFirebirdClient);

end.
