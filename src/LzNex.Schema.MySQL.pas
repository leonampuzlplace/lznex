unit LzNex.Schema.MySQL;

{ Gerador de DDL do MySQL/MariaDB.

  So sobrescreve o que difere do ANSI: tipos fisicos, ordem dos modificadores,
  prefixos do alter (MySQL usa `add`/`modify`/`drop`, sem o `column`), opcoes de
  tabela (engine/charset/collate/comment) e as consultas de existencia via
  information_schema. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Schema.Compiler;

type
  TLzNexMySQLSchemaCompiler = class(TLzNexSchemaCompilerBase)
  protected
    function InlineComments: Boolean; override;
    function SupportsDefaultOn(const ACol: ILzNexColumnDef): Boolean; override;

    function AddColumnPrefix: string; override;
    function ChangeColumnPrefix: string; override;
    function DropColumnPrefix: string; override;

    function TableOptionsSQL(const ATable: ILzNexTable): string; override;
    function IndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; override;
    function DropIndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; override;
  public
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string; override;
    function ModifierOrder: TLzNexColumnModifiers; override;
    function RenameTableSQL(const AFrom, ATo: string): TLzNexFragment; override;
    function TruncateTableSQL(const ATable: string): TLzNexFragment; override;
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment; override;
  end;

// Fabrica de modulo. O NewSchemaCompiler do LzNex.Client.MySQL deve delegar
// para esta funcao (a unit do client nao pode usar esta: seria ciclo).
function NewMySQLSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;

implementation

{ TLzNexMySQLSchemaCompiler }

function TLzNexMySQLSchemaCompiler.InlineComments: Boolean;
begin
  // No MySQL o comentario e um modificador da propria coluna.
  Result := True;
end;

function TLzNexMySQLSchemaCompiler.SupportsDefaultOn(
  const ACol: ILzNexColumnDef): Boolean;
begin
  // O MySQL NAO aceita DEFAULT em TEXT/BLOB (nem literal em JSON): declarar
  // isso e erro 1101. O default e omitido em silencio em vez de gerar DDL que
  // o banco recusa.
  case ACol.ColumnType of
    ctTinyText, ctText, ctMediumText, ctLongText, ctBlob, ctJson, ctJsonb:
      Result := False;
    ctBinary:
      Result := ACol.Param1 > 0;   // varbinary aceita; blob nao
  else
    Result := True;
  end;
end;

function TLzNexMySQLSchemaCompiler.AddColumnPrefix: string;
begin
  Result := 'add ';
end;

function TLzNexMySQLSchemaCompiler.ChangeColumnPrefix: string;
begin
  Result := 'modify ';
end;

function TLzNexMySQLSchemaCompiler.DropColumnPrefix: string;
begin
  Result := 'drop ';
end;

function TLzNexMySQLSchemaCompiler.TableOptionsSQL(const ATable: ILzNexTable): string;
begin
  Result := '';
  if Trim(ATable.EngineName) <> '' then
    Result := Result + ' engine = ' + ATable.EngineName;
  if Trim(ATable.CharsetName) <> '' then
    Result := Result + ' default character set ' + ATable.CharsetName;
  if Trim(ATable.CollateName) <> '' then
    Result := Result + ' collate ' + ATable.CollateName;
  if Trim(ATable.CommentText) <> '' then
    Result := Result + ' comment = ' + QuotedStr(ATable.CommentText);
end;

function TLzNexMySQLSchemaCompiler.IndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  if (AIndex.IndexKind in [ixIndex, ixUnique, ixPrimary]) and
     (Length(AIndex.Columns) = 0) then
    raise ELzNexSchema.CreateFmt(
      'Index without columns on table "%s".', [ATable.TableName]);

  case AIndex.IndexKind of
    ixIndex:
      Result := 'alter table ' + TableRef(ATable) + ' add index ' +
                Wrap(IndexNameOf(ATable, AIndex)) +
                '(' + ColumnList(AIndex.Columns) + ')';
    ixUnique:
      Result := 'alter table ' + TableRef(ATable) + ' add unique ' +
                Wrap(IndexNameOf(ATable, AIndex)) +
                '(' + ColumnList(AIndex.Columns) + ')';
    ixPrimary:
      // O MySQL nao nomeia primary key: o nome e sempre PRIMARY.
      Result := 'alter table ' + TableRef(ATable) + ' add primary key (' +
                ColumnList(AIndex.Columns) + ')';
  else
    Result := inherited IndexSQL(ATable, AIndex);
  end;
end;

function TLzNexMySQLSchemaCompiler.DropIndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  case AIndex.IndexKind of
    ixPrimary:
      Result := 'alter table ' + TableRef(ATable) + ' drop primary key';
    ixForeign:
      Result := 'alter table ' + TableRef(ATable) + ' drop foreign key ' +
                Wrap(IndexNameOf(ATable, AIndex));
  else
    // No MySQL unique tambem e indice: drop index serve para os dois.
    Result := 'alter table ' + TableRef(ATable) + ' drop index ' +
              Wrap(IndexNameOf(ATable, AIndex));
  end;
end;

function TLzNexMySQLSchemaCompiler.ColumnTypeSQL(const AType: TLzNexColumnType;
  const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;
var
  Len: Integer;
begin
  case AType of
    ctIncrements:
      Result := 'int unsigned not null auto_increment primary key';
    ctBigIncrements:
      Result := 'bigint unsigned not null auto_increment primary key';
    ctTinyInt:
      Result := 'tinyint';
    ctSmallInt:
      Result := 'smallint';
    ctMediumInt:
      Result := 'mediumint';
    ctInteger:
      Result := 'int';
    ctBigInt:
      Result := 'bigint';
    ctBoolean:
      // tinyint(1) e o que o MySQL usa como booleano.
      Result := 'tinyint(1)';
    ctDecimal:
      if AParam1 <= 0 then
        Result := 'decimal'
      else
        Result := 'decimal(' + IntToStr(AParam1) + ', ' + IntToStr(AParam2) + ')';
    ctFloat:
      Result := 'float';
    ctDouble:
      Result := 'double';
    ctChar:
      begin
        Len := AParam1;
        if Len <= 0 then
          Len := 255;
        Result := 'char(' + IntToStr(Len) + ')';
      end;
    ctString:
      begin
        Len := AParam1;
        if Len <= 0 then
          Len := 255;
        Result := 'varchar(' + IntToStr(Len) + ')';
      end;
    ctTinyText:
      Result := 'tinytext';
    ctText:
      Result := 'text';
    ctMediumText:
      Result := 'mediumtext';
    ctLongText:
      Result := 'longtext';
    ctBinary:
      if AParam1 > 0 then
        Result := 'varbinary(' + IntToStr(AParam1) + ')'
      else
        Result := 'blob';
    ctBlob:
      Result := 'blob';
    ctDate:
      Result := 'date';
    ctTime:
      Result := 'time';
    ctDateTime:
      Result := 'datetime';
    ctTimestamp:
      Result := 'timestamp';
    ctJson, ctJsonb:
      Result := 'json';
    ctUuid:
      Result := 'char(36)';
    ctEnum:
      begin
        if Length(AItems) = 0 then
          raise ELzNexSchema.Create('enum without items in MySQL DDL.');
        Result := 'enum(' + EnumList(AItems) + ')';
      end;
    ctSpecific:
      Result := '';
  else
    Result := inherited ColumnTypeSQL(AType, AParam1, AParam2, AItems);
  end;
end;

function TLzNexMySQLSchemaCompiler.ModifierOrder: TLzNexColumnModifiers;
begin
  // Ordem do MySQL. Quem define a ordem e o dialeto, nao a ordem de chamada do
  // usuario: `.Default_(1).Unsigned` e `.Unsigned.Default_(1)` saem iguais.
  Result := TLzNexColumnModifiers.Create(
    mdUnsigned, mdNullable, mdDefault, mdComment, mdCollate, mdAfter);
end;

function TLzNexMySQLSchemaCompiler.RenameTableSQL(
  const AFrom, ATo: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit(
    'rename table ' + WrapPath(AFrom) + ' to ' + WrapPath(ATo));
end;

function TLzNexMySQLSchemaCompiler.TruncateTableSQL(
  const ATable: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit('truncate ' + WrapPath(ATable));
end;

function TLzNexMySQLSchemaCompiler.HasTableSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  S: string;
begin
  B := TLzNexBindings.Empty;
  S := 'select count(*) from information_schema.tables where table_name = ?';
  B.Add(TLzNexValue.FromString(ATable));
  if Trim(ASchema) <> '' then
  begin
    S := S + ' and table_schema = ?';
    B.Add(TLzNexValue.FromString(ASchema));
  end
  else
    // Sem schema explicito, o alvo e o database da conexao.
    S := S + ' and table_schema = database()';
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexMySQLSchemaCompiler.HasColumnSQL(
  const ATable, AColumn, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  S: string;
begin
  B := TLzNexBindings.Empty;
  S := 'select count(*) from information_schema.columns ' +
       'where table_name = ? and column_name = ?';
  B.Add(TLzNexValue.FromString(ATable));
  B.Add(TLzNexValue.FromString(AColumn));
  if Trim(ASchema) <> '' then
  begin
    S := S + ' and table_schema = ?';
    B.Add(TLzNexValue.FromString(ASchema));
  end
  else
    S := S + ' and table_schema = database()';
  Result := TLzNexFragment.Make(S, B);
end;

function NewMySQLSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;
begin
  Result := TLzNexMySQLSchemaCompiler.Create(AClient);
end;

end.
