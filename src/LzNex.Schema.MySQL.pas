unit LzNex.Schema.MySQL;

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
    function TablesSQL(const ASchema: string): TLzNexFragment; override;
    function ColumnsSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasIndexSQL(const ATable: string; const AColumns: TLzNexValues;
      const ASchema: string): TLzNexFragment; override;
  end;

function NewMySQLSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;

implementation

function TLzNexMySQLSchemaCompiler.InlineComments: Boolean;
begin

  Result := True;
end;

function TLzNexMySQLSchemaCompiler.SupportsDefaultOn(
  const ACol: ILzNexColumnDef): Boolean;
begin

  case ACol.ColumnType of
    ctTinyText, ctText, ctMediumText, ctLongText, ctBlob, ctJson, ctJsonb:
      Result := False;
    ctBinary:
      Result := ACol.Param1 > 0;
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
    Result := Result + ' comment = ' + FClient.EscapeStringLiteral(ATable.CommentText);
end;

function TLzNexMySQLSchemaCompiler.IndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  if (AIndex.IndexKind in [ixIndex, ixUnique, ixPrimary, ixFullText]) and
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

      Result := 'alter table ' + TableRef(ATable) + ' add primary key (' +
                ColumnList(AIndex.Columns) + ')';
    ixFullText:
      Result := 'alter table ' + TableRef(ATable) + ' add fulltext index ' +
                Wrap(IndexNameOf(ATable, AIndex)) +
                '(' + ColumnList(AIndex.Columns) + ')';
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

function TLzNexMySQLSchemaCompiler.TablesSQL(const ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  S: string;
begin
  B := TLzNexBindings.Empty;
  S := 'select table_name from information_schema.tables where table_type = ''BASE TABLE''';
  if Trim(ASchema) <> '' then
  begin
    S := S + ' and table_schema = ?';
    B.Add(TLzNexValue.FromString(ASchema));
  end
  else
    S := S + ' and table_schema = database()';
  S := S + ' order by table_name';
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexMySQLSchemaCompiler.ColumnsSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  S: string;
begin
  B := TLzNexBindings.Empty;
  S := 'select column_name from information_schema.columns where table_name = ?';
  B.Add(TLzNexValue.FromString(ATable));
  if Trim(ASchema) <> '' then
  begin
    S := S + ' and table_schema = ?';
    B.Add(TLzNexValue.FromString(ASchema));
  end
  else
    S := S + ' and table_schema = database()';
  S := S + ' order by ordinal_position';
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexMySQLSchemaCompiler.HasIndexSQL(const ATable: string;
  const AColumns: TLzNexValues; const ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  S, Marks: string;
  I: Integer;
begin
  if Length(AColumns) = 0 then
    raise ELzNexSchema.Create('HasIndex without columns.');

  B := TLzNexBindings.Empty;
  Marks := '';
  for I := 0 to High(AColumns) do
  begin
    if I > 0 then
      Marks := Marks + ', ';
    Marks := Marks + '?';
  end;

  S := 'select count(*) from (' +
       'select i.indexname from (' +
       'select s.index_name as indexname, s.column_name from information_schema.statistics s ' +
       'where s.table_name = ?';
  B.Add(TLzNexValue.FromString(ATable));
  if Trim(ASchema) <> '' then
  begin
    S := S + ' and s.table_schema = ?';
    B.Add(TLzNexValue.FromString(ASchema));
  end
  else
    S := S + ' and s.table_schema = database()';
  S := S + ') i group by i.indexname ' +
       'having sum(case when i.column_name in (' + Marks + ') then 1 else 0 end) = ? ' +
       'and count(*) = ?) m';

  for I := 0 to High(AColumns) do
    B.Add(TLzNexValue.FromString(AColumns[I].Text));
  B.Add(TLzNexValue.FromInteger(Length(AColumns)));
  B.Add(TLzNexValue.FromInteger(Length(AColumns)));

  Result := TLzNexFragment.Make(S, B);
end;

function NewMySQLSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;
begin
  Result := TLzNexMySQLSchemaCompiler.Create(AClient);
end;

end.
