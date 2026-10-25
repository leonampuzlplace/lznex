unit LzNex.Schema.SQLite;

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
  TLzNexSQLiteSchemaCompiler = class(TLzNexSchemaCompilerBase)
  protected
    function ModifierSQL(const AMod: TLzNexColumnModifier;
      const ACol: ILzNexColumnDef): string; override;
    function ColumnDefinitionSQL(const ACol: ILzNexColumnDef): string; override;

    procedure CompileComments(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan); override;

    procedure CompileCreate(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan); override;

    procedure CompileAlter(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan); override;

    function IndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; override;
    function DropIndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; override;

    function TableConstraintSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string;
    procedure CheckAddable(const ATable: ILzNexTable; const ACol: ILzNexColumnDef);
  public
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string; override;
    function ModifierOrder: TLzNexColumnModifiers; override;
    function TruncateTableSQL(const ATable: string): TLzNexFragment; override;
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment; override;
    function TablesSQL(const ASchema: string): TLzNexFragment; override;
    function ColumnsSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasIndexSQL(const ATable: string; const AColumns: TLzNexValues;
      const ASchema: string): TLzNexFragment; override;
  end;

function NewSQLiteSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;

implementation

function TLzNexSQLiteSchemaCompiler.ModifierSQL(
  const AMod: TLzNexColumnModifier; const ACol: ILzNexColumnDef): string;
begin
  case AMod of
    mdNullable:
      if ACol.HasModifier(mdNullable) then
        Result := ''
      else
        Result := 'not null';
    mdCollate:
      if ACol.HasModifier(mdCollate) then
        Result := 'collate ' + ACol.CollateName
      else
        Result := '';
  else
    Result := inherited ModifierSQL(AMod, ACol);
  end;
end;

function TLzNexSQLiteSchemaCompiler.ColumnDefinitionSQL(
  const ACol: ILzNexColumnDef): string;
begin
  Result := inherited ColumnDefinitionSQL(ACol);
  if ACol.ColumnType <> ctEnum then
    Exit;

  Result := Result + ' check (' + Wrap(ACol.ColumnName) + ' in (' +
            EnumList(ACol.EnumItems) + '))';
end;

procedure TLzNexSQLiteSchemaCompiler.CompileComments(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan);
begin

end;

function TLzNexSQLiteSchemaCompiler.TableConstraintSQL(
  const ATable: ILzNexTable; const AIndex: ILzNexIndexDef): string;
begin
  if Length(AIndex.Columns) = 0 then
    raise ELzNexSchema.CreateFmt(
      'Index without columns on table "%s".', [ATable.TableName]);

  case AIndex.IndexKind of
    ixUnique:
      Result := 'constraint ' + Wrap(IndexNameOf(ATable, AIndex)) +
                ' unique (' + ColumnList(AIndex.Columns) + ')';
    ixForeign:
      begin
        if Trim(AIndex.RefTable) = '' then
          raise ELzNexSchema.CreateFmt(
            'FK on "%s" without a referenced table: InTable is missing (or use ' +
            'References(''table.column'')).', [ATable.TableName]);
        if Length(AIndex.RefColumns) = 0 then
          raise ELzNexSchema.CreateFmt(
            'FK on "%s" without a referenced column: References is missing.',
            [ATable.TableName]);

        Result := 'constraint ' + Wrap(IndexNameOf(ATable, AIndex)) +
                  ' foreign key (' + ColumnList(AIndex.Columns) +
                  ') references ' + WrapPath(AIndex.RefTable) +
                  ' (' + ColumnList(AIndex.RefColumns) + ')';
        if AIndex.OnDeleteAction <> '' then
          Result := Result + ' on delete ' + AIndex.OnDeleteAction;
        if AIndex.OnUpdateAction <> '' then
          Result := Result + ' on update ' + AIndex.OnUpdateAction;
      end;
  else
    raise ELzNexSchema.Create('Index kind is not a table constraint.');
  end;
end;

procedure TLzNexSQLiteSchemaCompiler.CompileCreate(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan);
var
  SB: TStringBuilder;
  I: Integer;
  Col: ILzNexColumnDef;
  Idx: ILzNexIndexDef;
  Prim: ILzNexIndexDef;
begin
  if ATable.ColumnCount = 0 then
    raise ELzNexSchema.CreateFmt(
      'create table "%s" has no columns at all.', [ATable.TableName]);

  Prim := nil;
  for I := 0 to ATable.IndexCount - 1 do
  begin
    Idx := ATable.IndexAt(I);
    if Idx.IsDrop then
      raise ELzNexSchema.CreateFmt(
        'create table "%s" cannot drop an index: the table does not exist yet.',
        [ATable.TableName]);
    if (Idx.IndexKind = ixPrimary) and (Prim = nil) then
      Prim := Idx;
  end;

  SB := TStringBuilder.Create;
  try
    SB.Append('create table ');
    SB.Append(TableRef(ATable));
    SB.Append(' (');

    for I := 0 to ATable.ColumnCount - 1 do
    begin
      Col := ATable.ColumnAt(I);
      if I > 0 then
        SB.Append(', ');
      SB.Append(ColumnDefinitionSQL(Col));
    end;

    if (Prim <> nil) and (Length(Prim.Columns) > 0) then
    begin
      SB.Append(', primary key (');
      SB.Append(ColumnList(Prim.Columns));
      SB.Append(')');
    end;

    for I := 0 to ATable.IndexCount - 1 do
    begin
      Idx := ATable.IndexAt(I);
      if not (Idx.IndexKind in [ixUnique, ixForeign]) then
        Continue;
      SB.Append(', ');
      SB.Append(TableConstraintSQL(ATable, Idx));
    end;

    SB.Append(')');
    PushStmt(APlan, SB.ToString);
  finally
    SB.Free;
  end;

  for I := 0 to ATable.IndexCount - 1 do
  begin
    Idx := ATable.IndexAt(I);
    if Idx.IndexKind = ixIndex then
      PushPost(APlan, IndexSQL(ATable, Idx));
  end;
end;

procedure TLzNexSQLiteSchemaCompiler.CheckAddable(const ATable: ILzNexTable;
  const ACol: ILzNexColumnDef);
begin

  if ACol.HasModifier(mdNullable) or ACol.HasModifier(mdDefault) then
    Exit;
  if ACol.ColumnType in [ctIncrements, ctBigIncrements] then
    Exit;

  raise ELzNexSchema.CreateFmt(
    'SQLite refuses "add column %s not null" without a default: the rows ' +
    'already in "%s" would have nowhere to get the value. Add Nullable or ' +
    'Default_(...).', [ACol.ColumnName, ATable.TableName]);
end;

procedure TLzNexSQLiteSchemaCompiler.CompileAlter(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan);
var
  I: Integer;
  Col: ILzNexColumnDef;
  Idx: ILzNexIndexDef;
  Ren: TLzNexNamedValues;
  Head: string;
begin
  Head := 'alter table ' + TableRef(ATable) + ' ';

  for I := 0 to ATable.ColumnCount - 1 do
  begin
    Col := ATable.ColumnAt(I);
    if Col.IsDrop then
      PushStmt(APlan, Head + DropColumnPrefix + Wrap(Col.ColumnName))
    else if Col.IsChange then
      raise ELzNexSchema.CreateFmt(
        'SQLite cannot change column "%s" of "%s": there is no ALTER COLUMN. ' +
        'Recreate the table (create the new one, copy, drop, rename) inside ' +
        'the migration.', [Col.ColumnName, ATable.TableName])
    else
    begin
      CheckAddable(ATable, Col);
      PushStmt(APlan, Head + AddColumnPrefix + ColumnDefinitionSQL(Col));
    end;
  end;

  Ren := ATable.RenamedColumns;
  for I := 0 to High(Ren) do
    PushStmt(APlan, RenameColumnSQL(ATable, Ren[I].Name, Ren[I].Value.AsString));

  for I := 0 to ATable.IndexCount - 1 do
  begin
    Idx := ATable.IndexAt(I);
    if Idx.IsDrop then
      PushPost(APlan, DropIndexSQL(ATable, Idx))
    else
      PushPost(APlan, IndexSQL(ATable, Idx));
  end;

  if APlan.Count = 0 then
    raise ELzNexSchema.CreateFmt(
      'alter table "%s" has no operations at all: nothing to do.',
      [ATable.TableName]);
end;

function TLzNexSQLiteSchemaCompiler.IndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  if Length(AIndex.Columns) = 0 then
    raise ELzNexSchema.CreateFmt(
      'Index without columns on table "%s".', [ATable.TableName]);

  case AIndex.IndexKind of
    ixIndex:
      Result := 'create index ' + Wrap(IndexNameOf(ATable, AIndex)) +
                ' on ' + TableRef(ATable) +
                ' (' + ColumnList(AIndex.Columns) + ')';
    ixUnique:

      Result := 'create unique index ' + Wrap(IndexNameOf(ATable, AIndex)) +
                ' on ' + TableRef(ATable) +
                ' (' + ColumnList(AIndex.Columns) + ')';
  else
    raise ELzNexSchema.CreateFmt(
      'SQLite cannot add a %s key to the existing table "%s": there is no ' +
      'ALTER TABLE ADD CONSTRAINT. Declare it in CreateTable, or recreate the ' +
      'table inside the migration.',
      [IndexKindSuffix(AIndex.IndexKind), ATable.TableName]);
  end;
end;

function TLzNexSQLiteSchemaCompiler.DropIndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  if not (AIndex.IndexKind in [ixIndex, ixUnique]) then
    raise ELzNexSchema.CreateFmt(
      'SQLite cannot drop a %s key from "%s": there is no ALTER TABLE DROP ' +
      'CONSTRAINT. Recreate the table inside the migration.',
      [IndexKindSuffix(AIndex.IndexKind), ATable.TableName]);

  Result := 'drop index ' + Wrap(IndexNameOf(ATable, AIndex));
end;

function TLzNexSQLiteSchemaCompiler.ColumnTypeSQL(const AType: TLzNexColumnType;
  const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;
var
  Len: Integer;
begin
  case AType of
    ctIncrements, ctBigIncrements:

      Result := 'integer primary key autoincrement';
    ctTinyInt:
      Result := 'tinyint';
    ctSmallInt:
      Result := 'smallint';
    ctMediumInt:
      Result := 'mediumint';
    ctInteger:
      Result := 'integer';
    ctBigInt:
      Result := 'bigint';
    ctBoolean:
      Result := 'boolean';
    ctDecimal:
      if AParam1 <= 0 then
        Result := 'decimal'
      else
        Result := 'decimal(' + IntToStr(AParam1) + ', ' + IntToStr(AParam2) + ')';
    ctFloat:
      Result := 'real';
    ctDouble:
      Result := 'double precision';
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
    ctTinyText, ctText, ctMediumText, ctLongText:
      Result := 'text';
    ctBinary, ctBlob:
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
      Result := 'text';
    ctUuid:
      Result := 'char(36)';
    ctEnum:
      begin
        if Length(AItems) = 0 then
          raise ELzNexSchema.Create('enum without items in SQLite DDL.');

        Result := 'varchar(255)';
      end;
    ctSpecific:
      Result := '';
  else
    Result := inherited ColumnTypeSQL(AType, AParam1, AParam2, AItems);
  end;
end;

function TLzNexSQLiteSchemaCompiler.ModifierOrder: TLzNexColumnModifiers;
begin
  Result := TLzNexColumnModifiers.Create(mdNullable, mdDefault, mdCollate);
end;

function TLzNexSQLiteSchemaCompiler.TruncateTableSQL(
  const ATable: string): TLzNexFragment;
begin

  Result := TLzNexFragment.Lit('delete from ' + WrapPath(ATable));
end;

function TLzNexSQLiteSchemaCompiler.HasTableSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
begin
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  Result := TLzNexFragment.Make(
    'select count(*) from sqlite_master ' +
    'where type in (''table'', ''view'') and name = ?', B);
end;

function TLzNexSQLiteSchemaCompiler.HasColumnSQL(
  const ATable, AColumn, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
begin
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  B.Add(TLzNexValue.FromString(AColumn));
  Result := TLzNexFragment.Make(
    'select count(*) from pragma_table_info(?) where name = ?', B);
end;

function TLzNexSQLiteSchemaCompiler.TablesSQL(const ASchema: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit(
    'select name from sqlite_master ' +
    'where type = ''table'' and name not like ''sqlite\_%'' escape ''\'' ' +
    'order by name');
end;

function TLzNexSQLiteSchemaCompiler.ColumnsSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
begin
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  Result := TLzNexFragment.Make(
    'select name from pragma_table_info(?) order by cid', B);
end;

function TLzNexSQLiteSchemaCompiler.HasIndexSQL(const ATable: string;
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
       'select il.name as indexname, ii.name as column_name ' +
       'from pragma_index_list(?) il, pragma_index_info(il.name) ii' +
       ') i group by i.indexname ' +
       'having sum(case when i.column_name in (' + Marks + ') then 1 else 0 end) = ? ' +
       'and count(*) = ?) m';

  B.Add(TLzNexValue.FromString(ATable));
  for I := 0 to High(AColumns) do
    B.Add(TLzNexValue.FromString(AColumns[I].Text));
  B.Add(TLzNexValue.FromInteger(Length(AColumns)));
  B.Add(TLzNexValue.FromInteger(Length(AColumns)));

  Result := TLzNexFragment.Make(S, B);
end;

function NewSQLiteSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;
begin
  Result := TLzNexSQLiteSchemaCompiler.Create(AClient);
end;

end.
