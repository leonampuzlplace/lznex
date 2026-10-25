unit LzNex.Client.SQLite;

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

const

  LZNEX_SQLITE_LIMIT_NONE = '-1';

type
  TLzNexSQLiteCompiler = class(TLzNexCompilerBase)
  protected
    function CompileLimit: TLzNexFragment; override;

    function CompileTruncate: TLzNexFragment; override;

    function CompileLock: TLzNexFragment; override;

    function LikeOperator(const ACaseInsensitive, ANegated: Boolean): string; override;

    procedure DatePartWrap(const APart: TLzNexDatePart;
      out ABefore, AAfter: string); override;

    function CompileWhereJson(const AStmt: TLzNexJsonStmt): TLzNexFragment; override;

    function CompileWhereFullText(const AStmt: TLzNexFullTextStmt): TLzNexFragment; override;
  end;

  TLzNexSQLiteClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;

    function SupportsJson: Boolean; override;

    function SupportsReturning: Boolean; override;
    function SupportsOnConflictWhere: Boolean; override;
    function SupportsNullsOrdering: Boolean; override;
    function SupportsDistinctOn: Boolean; override;

    function IsRetryableError(const ACode: Integer;
      const ASQLState: string): Boolean; override;

    function InvalidComponents(const AMethod: TLzNexQueryMethod): TLzNexComponents; override;

    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

implementation

uses

  LzNex.Schema.SQLite,

  ZDbcSqLite;

function SQLiteJsonPath(const APath: string): string;
begin
  if APath = '' then
    Exit('$');
  if (APath[1] = '$') or (APath[1] = '[') then
    Exit(APath);
  Result := '$.' + APath;
end;

function SQLiteJsonPathArg(const APath: string): string;
begin
  if APath = '' then
    Result := ''
  else
    Result := ', ''' + SQLiteJsonPath(APath) + '''';
end;

function TLzNexSQLiteCompiler.CompileLimit: TLzNexFragment;
begin

  if (not FAst.Single.HasLimit) and FAst.Single.HasOffset then
    Exit(Txt('limit ' + LZNEX_SQLITE_LIMIT_NONE));
  Result := inherited CompileLimit;
end;

function TLzNexSQLiteCompiler.CompileTruncate: TLzNexFragment;
begin
  if FAst.Single.Table.IsUnset then
    raise ELzNexCompile.Create('TRUNCATE requires a table.');
  Result := Txt('delete from').Concat(CompileTarget);
end;

function TLzNexSQLiteCompiler.CompileLock: TLzNexFragment;
begin
  if FAst.Single.Lock = lkNone then
    Exit(TLzNexFragment.Empty);
  raise ELzNexCompile.Create(
    'SQLite has no row lock: a write transaction locks the whole database. ' +
    'Drop ForUpdate/ForShare, or serialize the writers in the application.');
end;

function TLzNexSQLiteCompiler.LikeOperator(const ACaseInsensitive,
  ANegated: Boolean): string;
begin

  if ANegated then
    Result := 'not like'
  else
    Result := 'like';
end;

procedure TLzNexSQLiteCompiler.DatePartWrap(const APart: TLzNexDatePart;
  out ABefore, AAfter: string);
begin
  case APart of
    dpDate:
      begin
        ABefore := 'date(';
        AAfter := ')';
      end;
    dpTime:
      begin
        ABefore := 'time(';
        AAfter := ')';
      end;
    dpYear:
      begin
        ABefore := 'cast(strftime(''%Y'', ';
        AAfter := ') as integer)';
      end;
    dpMonth:
      begin
        ABefore := 'cast(strftime(''%m'', ';
        AAfter := ') as integer)';
      end;
    dpDay:
      begin
        ABefore := 'cast(strftime(''%d'', ';
        AAfter := ') as integer)';
      end;
    dpHour:
      begin
        ABefore := 'cast(strftime(''%H'', ';
        AAfter := ') as integer)';
      end;
    dpMinute:
      begin
        ABefore := 'cast(strftime(''%M'', ';
        AAfter := ') as integer)';
      end;
    dpSecond:
      begin
        ABefore := 'cast(strftime(''%S'', ';
        AAfter := ') as integer)';
      end;
  else
    inherited DatePartWrap(APart, ABefore, AAfter);
  end;
end;

function LooksLikeJsonDocument(const AValue: TLzNexValue): Boolean;
var
  S: string;
begin
  Result := False;
  if AValue.Kind <> vkString then
    Exit;
  S := Trim(AValue.AsString);
  Result := (S <> '') and ((S[1] = '{') or (S[1] = '['));
end;

function TLzNexSQLiteCompiler.CompileWhereJson(
  const AStmt: TLzNexJsonStmt): TLzNexFragment;
var
  Col, Fn: TLzNexFragment;
  Arg: string;
begin
  Col := CompileExpr(AStmt.Column, 'where json');
  Arg := SQLiteJsonPathArg(AStmt.Path);
  case AStmt.JsonOp of
    joPath:

      Result := Col.Wrap('json_extract(', Arg + ')').Wrap('cast(', ' as text)')
        .Concat(Txt(AStmt.Op))
        .Concat(CompileBind(AStmt.Value, AStmt.Column.Text));
    joContains:
      begin
        if (AStmt.Path = '') and LooksLikeJsonDocument(AStmt.Value) then
          raise ELzNexCompile.Create(
            'WhereJsonContains on SQLite only answers for a scalar value ' +
            'inside the top-level array/object: there is no json_contains() ' +
            'to match a whole sub-document against the root. Point at the ' +
            'key with WhereJsonPath instead, or compare by hand with WhereRaw.');

        Fn := Col.Wrap('json_each(', Arg + ')')
          .Prefix('exists (select 1 from ')
          .Concat(Txt('where value'))
          .Concat(Txt(AStmt.Op))
          .Concat(CompileBind(AStmt.Value, AStmt.Column.Text))
          .Wrap('', ')');
        Result := Fn;
      end;
    joLength:
      Result := Col.Wrap('json_array_length(', Arg + ')')
        .Concat(Txt(AStmt.Op))
        .Concat(CompileBind(AStmt.Value, AStmt.Column.Text));
  else
    raise ELzNexCompile.Create('Unknown JSON operation.');
  end;

  if AStmt.Negated then
    Result := Wrapped(Result).Prefix('not ');
end;

function TLzNexSQLiteCompiler.CompileWhereFullText(
  const AStmt: TLzNexFullTextStmt): TLzNexFragment;
begin
  raise ELzNexCompile.Create(
    'SQLite has no full text search over a plain table: it would need a ' +
    'virtual FTS5 table built with CREATE VIRTUAL TABLE ... USING fts5(...), ' +
    'kept in sync with triggers. Create that table through Schema/Raw and ' +
    'query it directly with WhereRaw, or fall back to WhereLike here.');
end;

function TLzNexSQLiteClient.DialectName: string;
begin
  Result := 'sqlite';
end;

function TLzNexSQLiteClient.ZeosProtocol: string;
begin
  Result := 'sqlite';
end;

function TLzNexSQLiteClient.SupportsJson: Boolean;
begin

  Result := True;
end;

function TLzNexSQLiteClient.SupportsReturning: Boolean;
begin

  Result := False;
end;

function TLzNexSQLiteClient.SupportsOnConflictWhere: Boolean;
begin

  Result := True;
end;

function TLzNexSQLiteClient.SupportsNullsOrdering: Boolean;
begin

  Result := True;
end;

function TLzNexSQLiteClient.SupportsDistinctOn: Boolean;
begin
  Result := False;
end;

function TLzNexSQLiteClient.IsRetryableError(const ACode: Integer;
  const ASQLState: string): Boolean;
begin
  if (ACode = 5) or (ACode = 6) then
    Exit(True);
  Result := inherited IsRetryableError(ACode, ASQLState);
end;

function TLzNexSQLiteClient.InvalidComponents(
  const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of

    qmDelete:
      Result := TLzNexComponents.Create(cpHaving, cpGroup, cpLimit, cpJoin);
    qmUpdate:
      Result := TLzNexComponents.Create(cpHaving, cpGroup, cpLimit, cpJoin);
  else
    Result := inherited InvalidComponents(AMethod);
  end;
end;

function TLzNexSQLiteClient.NewCompiler: ILzNexCompiler;
begin
  Result := TLzNexSQLiteCompiler.Create(Self);
end;

function TLzNexSQLiteClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := NewSQLiteSchemaCompiler(Self);
end;

initialization
  RegisterClient('sqlite', TLzNexSQLiteClient);

  RegisterClient('sqlite3', TLzNexSQLiteClient);

end.
