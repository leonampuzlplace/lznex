unit LzNex.Client.Postgres;

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
  TLzNexPostgresCompiler = class(TLzNexCompilerBase)
  protected

    function CompileTruncate: TLzNexFragment; override;

    function CompileWhereJson(const AStmt: TLzNexJsonStmt): TLzNexFragment; override;
    function CompileWhereFullText(const AStmt: TLzNexFullTextStmt): TLzNexFragment; override;
  end;

  TLzNexPostgresClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;

    function QuoteLiteral(const AValue: TLzNexValue): string; override;

    function SupportsReturning: Boolean; override;
    function SupportsOnConflictWhere: Boolean; override;
    function SupportsNullsOrdering: Boolean; override;
    function SupportsDistinctOn: Boolean; override;
    function SupportsJson: Boolean; override;
    function SupportsFullText: Boolean; override;

    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

implementation

uses

  LzNex.Schema.Postgres,

  ZDbcPostgreSql;

function TLzNexPostgresCompiler.CompileTruncate: TLzNexFragment;
begin
  Result := inherited CompileTruncate;
  Result := Result.Concat(Txt('restart identity'));
end;

function PostgresJsonPath(const APath: string): string;
var
  I: Integer;
  C: Char;
  SB: TStringBuilder;
  Started: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    Started := False;
    for I := 1 to Length(APath) do
    begin
      C := APath[I];
      case C of
        '$': ;
        '.', '[':
          begin
            if Started then
              SB.Append(',');
            Started := False;
          end;
        ']': ;
      else
        begin
          SB.Append(C);
          Started := True;
        end;
      end;
    end;
    Result := '{' + SB.ToString + '}';
  finally
    SB.Free;
  end;
end;

function TLzNexPostgresCompiler.CompileWhereJson(
  const AStmt: TLzNexJsonStmt): TLzNexFragment;
var
  Col, Value, Candidate: TLzNexFragment;
  PGPath: string;
begin
  Col := CompileExpr(AStmt.Column, 'where json');
  Value := CompileBind(AStmt.Value, AStmt.Column.Text);
  if AStmt.Path <> '' then
    PGPath := PostgresJsonPath(AStmt.Path);

  case AStmt.JsonOp of
    joPath:
      Result := Col.Wrap('', ' #>> ''' + PGPath + '''')
        .Concat(Txt(AStmt.Op)).Concat(Value);
    joContains:
      begin

        if AStmt.Value.Kind = vkString then
          Candidate := Value.Wrap('', '::jsonb')
        else
          Candidate := Value.Wrap('to_jsonb(', ')');
        if AStmt.Path = '' then
          Result := Col.Wrap('', '::jsonb @> ').Concat(Candidate, '')
        else
          Result := Col.Wrap('(', ' #> ''' + PGPath + ''')::jsonb @> ')
            .Concat(Candidate, '');
      end;
    joLength:
      begin
        if AStmt.Path = '' then
          Result := Col.Wrap('jsonb_array_length(', '::jsonb)')
        else
          Result := Col.Wrap('jsonb_array_length((', ' #> ''' + PGPath + ''')::jsonb)');
        Result := Result.Concat(Txt(AStmt.Op)).Concat(Value);
      end;
  else
    raise ELzNexCompile.Create('Unknown JSON operation.');
  end;

  if AStmt.Negated then
    Result := Wrapped(Result).Prefix('not ');
end;

function TLzNexPostgresCompiler.CompileWhereFullText(
  const AStmt: TLzNexFullTextStmt): TLzNexFragment;
var
  I: Integer;
  ColsSQL, FuncName: string;
  Search: TLzNexFragment;
begin
  ColsSQL := '';
  for I := 0 to High(AStmt.Columns) do
  begin
    if I > 0 then
      ColsSQL := ColsSQL + ' || '' '' || ';
    ColsSQL := ColsSQL + 'coalesce(' + Ident(AStmt.Columns[I].Text) + ', '''')';
  end;

  if AStmt.Mode = ftBoolean then
    FuncName := 'websearch_to_tsquery'
  else
    FuncName := 'plainto_tsquery';

  Search := CompileBind(AStmt.Search, 'full text');
  Result := Search.Wrap(
    'to_tsvector(''simple'', ' + ColsSQL + ') @@ ' + FuncName + '(''simple'', ', ')');
  if AStmt.Negated then
    Result := Wrapped(Result).Prefix('not ');
end;

function TLzNexPostgresClient.DialectName: string;
begin
  Result := 'postgresql';
end;

function TLzNexPostgresClient.ZeosProtocol: string;
begin
  Result := 'postgresql';
end;

function TLzNexPostgresClient.QuoteLiteral(const AValue: TLzNexValue): string;
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

function TLzNexPostgresClient.SupportsJson: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.SupportsFullText: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.SupportsReturning: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.SupportsOnConflictWhere: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.SupportsNullsOrdering: Boolean;
begin

  Result := True;
end;

function TLzNexPostgresClient.SupportsDistinctOn: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.NewCompiler: ILzNexCompiler;
begin
  Result := TLzNexPostgresCompiler.Create(Self);
end;

function TLzNexPostgresClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := NewPostgresSchemaCompiler(Self);
end;

initialization
  RegisterClient('postgresql', TLzNexPostgresClient);

  RegisterClient('postgres', TLzNexPostgresClient);

end.
