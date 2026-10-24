unit LzNex.Client.MySQL;

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

  LZNEX_MYSQL_LIMIT_MAX = '18446744073709551615';

type
  TLzNexMySQLCompiler = class(TLzNexCompilerBase)
  protected

    function InsertVerb: string; override;
    function CompileConflict(const AColumns: TLzNexStringArray): TLzNexFragment; override;
    function CompileLimit: TLzNexFragment; override;

    function LikeOperator(const ACaseInsensitive, ANegated: Boolean): string; override;

    function DeleteHead: string; override;

  end;

  TLzNexMySQLClient = class(TLzNexClientBase)
  protected
    function QuoteChar: string; override;
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;

    function SupportsReturning: Boolean; override;
    function SupportsOnConflictWhere: Boolean; override;
    function SupportsNullsOrdering: Boolean; override;
    function SupportsDistinctOn: Boolean; override;
    function SupportsSavepoints: Boolean; override;
    function DdlIsTransactional: Boolean; override;

    function InvalidComponents(const AMethod: TLzNexQueryMethod): TLzNexComponents; override;

    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

implementation

uses

  LzNex.Schema.MySQL,

  ZDbcMySql;

function TLzNexMySQLCompiler.InsertVerb: string;
begin
  if FAst.Single.Conflict = caIgnore then
    Result := 'insert ignore into'
  else
    Result := 'insert into';
end;

function TLzNexMySQLCompiler.CompileConflict(
  const AColumns: TLzNexStringArray): TLzNexFragment;
var
  I: Integer;
  Buf: TLzNexFragBuf;
  Merge: TLzNexNamedValues;
begin
  case FAst.Single.Conflict of
    caNone:
      Exit(TLzNexFragment.Empty);
    caIgnore:

      Exit(TLzNexFragment.Empty);
  end;

  Buf.Clear;
  Merge := FAst.Single.ConflictMerge;
  if Length(Merge) > 0 then
  begin
    for I := 0 to High(Merge) do

      if Merge[I].Value.IsUnset then
        Buf.Add(Txt(Ident(Merge[I].Name) + ' = values(' + Ident(Merge[I].Name) + ')'))
      else
        Buf.Add(Txt(Ident(Merge[I].Name) + ' = ').Concat(
          CompileSetValue(Merge[I].Value, Merge[I].Name), ''));
  end
  else

    for I := 0 to High(AColumns) do
      Buf.Add(Txt(Ident(AColumns[I]) + ' = values(' + Ident(AColumns[I]) + ')'));

  Result := Buf.Join(', ').Prefix('on duplicate key update ');
end;

function TLzNexMySQLCompiler.CompileLimit: TLzNexFragment;
begin
  if (not FAst.Single.HasLimit) and FAst.Single.HasOffset then
    Exit(Txt('limit ' + LZNEX_MYSQL_LIMIT_MAX));
  Result := inherited CompileLimit;
end;

function TLzNexMySQLCompiler.LikeOperator(const ACaseInsensitive,
  ANegated: Boolean): string;
begin
  if ANegated then
    Result := 'not like'
  else
    Result := 'like';
end;

function TLzNexMySQLCompiler.DeleteHead: string;
begin
  Result := 'delete';
  if not FAst.Has(sgJoin) then
    Exit;
  if FAst.Single.TableAlias <> '' then
    Result := 'delete ' + Client.WrapIdentifier(FAst.Single.TableAlias)
  else if FAst.Single.Table.Kind = vkIdentifier then
    Result := 'delete ' + Client.WrapQualified(FAst.Single.Table.Text);
end;

function TLzNexMySQLClient.QuoteChar: string;
begin

  Result := '`';
end;

function TLzNexMySQLClient.DialectName: string;
begin
  Result := 'mysql';
end;

function TLzNexMySQLClient.ZeosProtocol: string;
begin
  Result := 'mysql';
end;

function TLzNexMySQLClient.SupportsReturning: Boolean;
begin
  Result := False;
end;

function TLzNexMySQLClient.SupportsOnConflictWhere: Boolean;
begin

  Result := False;
end;

function TLzNexMySQLClient.SupportsNullsOrdering: Boolean;
begin

  Result := False;
end;

function TLzNexMySQLClient.SupportsDistinctOn: Boolean;
begin
  Result := False;
end;

function TLzNexMySQLClient.SupportsSavepoints: Boolean;
begin
  Result := True;
end;

function TLzNexMySQLClient.DdlIsTransactional: Boolean;
begin

  Result := False;
end;

function TLzNexMySQLClient.InvalidComponents(
  const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of
    qmDelete:

      Result := TLzNexComponents.Create(cpHaving, cpGroup);
  else
    Result := inherited InvalidComponents(AMethod);
  end;
end;

function TLzNexMySQLClient.NewCompiler: ILzNexCompiler;
begin
  Result := TLzNexMySQLCompiler.Create(Self);
end;

function TLzNexMySQLClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := NewMySQLSchemaCompiler(Self);
end;

initialization
  RegisterClient('mysql', TLzNexMySQLClient);

  RegisterClient('mariadb', TLzNexMySQLClient);

end.
