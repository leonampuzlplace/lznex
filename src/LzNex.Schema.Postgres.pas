unit LzNex.Schema.Postgres;

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
  TLzNexPostgresSchemaCompiler = class(TLzNexSchemaCompilerBase)
  protected
    function ColumnDefinitionSQL(const ACol: ILzNexColumnDef): string; override;
    function ChangeColumnParts(const ACol: ILzNexColumnDef): TLzNexStringArray; override;
    function IndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; override;
    function DropIndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; override;
    // Mesma expressao que o CompileWhereFullText usa no "where", token a
    // token -- senao o indice GIN nasce e nunca e usado pela busca.
    function FullTextExpr(const AColumns: TLzNexValues): string;
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

function NewPostgresSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;

implementation

function TLzNexPostgresSchemaCompiler.ColumnTypeSQL(const AType: TLzNexColumnType;
  const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;
var
  Len: Integer;
begin
  case AType of
    ctIncrements:

      Result := 'serial primary key';
    ctBigIncrements:
      Result := 'bigserial primary key';
    ctTinyInt, ctSmallInt:

      Result := 'smallint';
    ctMediumInt, ctInteger:
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

      Result := 'bytea';
    ctDate:
      Result := 'date';
    ctTime:
      Result := 'time';
    ctDateTime, ctTimestamp:
      Result := 'timestamp';
    ctJson:
      Result := 'json';
    ctJsonb:

      Result := 'jsonb';
    ctUuid:
      Result := 'uuid';
    ctEnum:
      begin
        if Length(AItems) = 0 then
          raise ELzNexSchema.Create('enum without items in PostgreSQL DDL.');

        Result := 'text';
      end;
    ctSpecific:
      Result := '';
  else
    Result := inherited ColumnTypeSQL(AType, AParam1, AParam2, AItems);
  end;
end;

function TLzNexPostgresSchemaCompiler.ColumnDefinitionSQL(
  const ACol: ILzNexColumnDef): string;
begin
  Result := inherited ColumnDefinitionSQL(ACol);
  if ACol.ColumnType <> ctEnum then
    Exit;
  Result := Result + ' check (' + Wrap(ACol.ColumnName) + ' in (' +
            EnumList(ACol.EnumItems) + '))';
end;

function TLzNexPostgresSchemaCompiler.ChangeColumnParts(
  const ACol: ILzNexColumnDef): TLzNexStringArray;
var
  Col: string;
  N: Integer;

  procedure Add(const ASQL: string);
  begin
    SetLength(Result, N + 1);
    Result[N] := Col + ASQL;
    Inc(N);
  end;

begin
  { O PostgreSQL nao aceita redeclarar a coluna inteira: cada aspecto e uma
    acao propria. As tres cabem no mesmo ALTER TABLE, separadas por virgula. }
  Result := nil;
  N := 0;
  Col := ChangeColumnPrefix + Wrap(ACol.ColumnName) + ' ';

  Add('type ' + ColumnTypeFor(ACol));

  if ACol.HasModifier(mdNullable) then
    Add('drop not null')
  else
    Add('set not null');

  if ACol.HasModifier(mdDefault) and SupportsDefaultOn(ACol) then
    Add('set default ' + DefaultLiteral(ACol));
end;

function TLzNexPostgresSchemaCompiler.FullTextExpr(
  const AColumns: TLzNexValues): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(AColumns) do
    begin
      if I > 0 then
        SB.Append(' || '' '' || ');
      SB.Append('coalesce(');
      SB.Append(Wrap(AColumns[I].Text));
      SB.Append(','''')');
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexPostgresSchemaCompiler.IndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  if AIndex.IndexKind <> ixFullText then
    Exit(inherited IndexSQL(ATable, AIndex));

  if Length(AIndex.Columns) = 0 then
    raise ELzNexSchema.CreateFmt(
      'Full text index without columns on table "%s".', [ATable.TableName]);

  Result := 'create index ' + Wrap(IndexNameOf(ATable, AIndex)) + ' on ' +
            TableRef(ATable) + ' using gin (to_tsvector(''simple'', ' +
            FullTextExpr(AIndex.Columns) + '))';
end;

function TLzNexPostgresSchemaCompiler.DropIndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  // O GIN e um indice avulso (create index), nao uma constraint: DROP INDEX, nao DROP CONSTRAINT.
  if AIndex.IndexKind = ixFullText then
    Exit('drop index ' + Wrap(IndexNameOf(ATable, AIndex)));
  Result := inherited DropIndexSQL(ATable, AIndex);
end;

function TLzNexPostgresSchemaCompiler.ModifierOrder: TLzNexColumnModifiers;
begin

  Result := TLzNexColumnModifiers.Create(mdNullable, mdDefault);
end;

function TLzNexPostgresSchemaCompiler.TruncateTableSQL(
  const ATable: string): TLzNexFragment;
begin

  Result := TLzNexFragment.Lit(
    'truncate ' + WrapPath(ATable) + ' restart identity');
end;

function TLzNexPostgresSchemaCompiler.HasTableSQL(
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

    S := S + ' and table_schema = current_schema()';
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexPostgresSchemaCompiler.HasColumnSQL(
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
    S := S + ' and table_schema = current_schema()';
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexPostgresSchemaCompiler.TablesSQL(
  const ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  Schema: string;
begin
  Schema := ASchema;
  if Trim(Schema) = '' then
    Schema := 'public';
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(Schema));
  Result := TLzNexFragment.Make(
    'select table_name from information_schema.tables ' +
    'where table_type = ''BASE TABLE'' and table_schema = ? order by table_name', B);
end;

function TLzNexPostgresSchemaCompiler.ColumnsSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  Schema: string;
begin
  Schema := ASchema;
  if Trim(Schema) = '' then
    Schema := 'public';
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  B.Add(TLzNexValue.FromString(Schema));
  Result := TLzNexFragment.Make(
    'select column_name from information_schema.columns ' +
    'where table_name = ? and table_schema = ? order by ordinal_position', B);
end;

function TLzNexPostgresSchemaCompiler.HasIndexSQL(const ATable: string;
  const AColumns: TLzNexValues; const ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
  S, Marks, Schema: string;
  I: Integer;
begin
  if Length(AColumns) = 0 then
    raise ELzNexSchema.Create('HasIndex without columns.');

  Schema := ASchema;
  if Trim(Schema) = '' then
    Schema := 'public';

  B := TLzNexBindings.Empty;
  Marks := '';
  for I := 0 to High(AColumns) do
  begin
    if I > 0 then
      Marks := Marks + ', ';
    Marks := Marks + '?';
  end;

  { pg_index guarda so o numero da coluna (indkey); o join com pg_attribute
    devolve uma linha por coluna do indice, igual ao information_schema.statistics
    do MySQL -- dai reaproveitar a mesma logica de agrupar por indice e comparar
    o conjunto de colunas. }
  S := 'select count(*) from (' +
       'select i.indexname from (' +
       'select ci.relname as indexname, a.attname as column_name ' +
       'from pg_index pi ' +
       'join pg_class ct on ct.oid = pi.indrelid ' +
       'join pg_class ci on ci.oid = pi.indexrelid ' +
       'join pg_namespace ns on ns.oid = ct.relnamespace ' +
       'join pg_attribute a on a.attrelid = pi.indrelid and a.attnum = any(pi.indkey) ' +
       'where ct.relname = ? and ns.nspname = ?' +
       ') i group by i.indexname ' +
       'having sum(case when i.column_name in (' + Marks + ') then 1 else 0 end) = ? ' +
       'and count(*) = ?) m';

  B.Add(TLzNexValue.FromString(ATable));
  B.Add(TLzNexValue.FromString(Schema));
  for I := 0 to High(AColumns) do
    B.Add(TLzNexValue.FromString(AColumns[I].Text));
  B.Add(TLzNexValue.FromInteger(Length(AColumns)));
  B.Add(TLzNexValue.FromInteger(Length(AColumns)));

  Result := TLzNexFragment.Make(S, B);
end;

function NewPostgresSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;
begin
  Result := TLzNexPostgresSchemaCompiler.Create(AClient);
end;

end.
