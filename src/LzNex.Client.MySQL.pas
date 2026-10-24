unit LzNex.Client.MySQL;

{ Dialeto MySQL/MariaDB: o que muda em relacao ao ANSI da classe base.

  Tudo aqui e sobrescrita pontual -- nenhum metodo do compiler base foi
  duplicado. Dar `uses` nesta unit registra 'mysql' e 'mariadb' no registry. }

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
  // MySQL nao aceita OFFSET sem LIMIT; o teto do BIGINT UNSIGNED e a forma
  // documentada de dizer "sem limite".
  LZNEX_MYSQL_LIMIT_MAX = '18446744073709551615';

type
  TLzNexMySQLCompiler = class(TLzNexCompilerBase)
  protected
    // 'insert ignore into' resolve o IGNORE na emissao, em vez de
    // reescrever a string depois (o knex faz um replace no SQL ja montado).
    function InsertVerb: string; override;
    function CompileConflict(const AColumns: TLzNexStringArray): TLzNexFragment; override;
    function CompileLimit: TLzNexFragment; override;
    // MySQL nao tem ILIKE: o LIKE ja e case-insensitive na collation _ci.
    function LikeOperator(const ACaseInsensitive, ANegated: Boolean): string; override;
    // Delete com join exige repetir o alvo: "delete `u` from `users` `u` join ...".
    function DeleteHead: string; override;
    // Emulacao de NULLS FIRST/LAST com "(col is null)" vem da classe base,
    // acionada por SupportsNullsOrdering = False.
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
  // No implementation para que a unit de DDL possa evoluir sem arrastar
  // dependencia na interface deste dialeto.
  LzNex.Schema.MySQL,
  // Registra o driver 'mysql'/'mariadb' no DriverManager do Zeos pelo
  // initialization dela. Sem esta linha o DriverManager responde
  // "Requested database driver was not found" em runtime -- unit que ninguem
  // referencia nao e linkada, entao o initialization nao roda.
  // Fica aqui de proposito: quem usa este dialeto ganha o driver junto.
  ZDbcMySql;

{ TLzNexMySQLCompiler }

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
      // Ja resolvido no verbo.
      Exit(TLzNexFragment.Empty);
  end;

  Buf.Clear;
  Merge := FAst.Single.ConflictMerge;
  if Length(Merge) > 0 then
  begin
    for I := 0 to High(Merge) do
      // vkUnset na lista de merge quer dizer "reaproveita o valor do
      // proprio INSERT", nao bind faltando.
      if Merge[I].Value.IsUnset then
        Buf.Add(Txt(Ident(Merge[I].Name) + ' = values(' + Ident(Merge[I].Name) + ')'))
      else
        Buf.Add(Txt(Ident(Merge[I].Name) + ' = ').Concat(
          CompileSetValue(Merge[I].Value, Merge[I].Name), ''));
  end
  else
    // values(col) reaproveita o valor que ja foi enviado na linha:
    // nao duplica bind nem depende de alias de linha (MySQL < 8.0.19).
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

{ TLzNexMySQLClient }

function TLzNexMySQLClient.QuoteChar: string;
begin
  // A base dobra o caractere para escapar: `we``ird`.
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
  // ON DUPLICATE KEY UPDATE nao aceita condicao.
  Result := False;
end;

function TLzNexMySQLClient.SupportsNullsOrdering: Boolean;
begin
  // Sem NULLS FIRST/LAST nativo; o compiler emula com "(col is null)".
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
  // MySQL faz COMMIT IMPLICITO em DDL: um CREATE TABLE no meio de uma
  // transacao confirma tudo que veio antes. O migrator usa isso para avisar
  // que o rollback nao cobre o DDL.
  Result := False;
end;

function TLzNexMySQLClient.InvalidComponents(
  const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of
    qmDelete:
      // MySQL aceita LIMIT em DELETE (o ANSI da base nao).
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
  // MariaDB fala o mesmo dialeto e usa o mesmo protocolo no Zeos.
  RegisterClient('mariadb', TLzNexMySQLClient);

end.
