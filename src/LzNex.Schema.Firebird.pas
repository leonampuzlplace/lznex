unit LzNex.Schema.Firebird;

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

const

  // Limite do Firebird 3. O 4 e o 5 aceitam 63, mas um nome que caiba nos tres
  // e a unica forma de o mesmo DDL rodar em todos.
  LZNEX_FIREBIRD_MAX_IDENTIFIER = 31;

type
  TLzNexFirebirdSchemaCompiler = class(TLzNexSchemaCompilerBase)
  protected
    function IsAutoType(const AType: TLzNexColumnType): Boolean; override;
    function ModifierSQL(const AMod: TLzNexColumnModifier;
      const ACol: ILzNexColumnDef): string; override;
    function ColumnDefinitionSQL(const ACol: ILzNexColumnDef): string; override;

    function AddColumnPrefix: string; override;
    function DropColumnPrefix: string; override;
    function ChangeColumnParts(const ACol: ILzNexColumnDef): TLzNexStringArray; override;
    function RenameColumnSQL(const ATable: ILzNexTable;
      const AFrom, ATo: string): string; override;
  public
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string; override;
    function ModifierOrder: TLzNexColumnModifiers; override;
    function DropTableSQL(const ATable: string;
      const AIfExists: Boolean): TLzNexFragment; override;
    function RenameTableSQL(const AFrom, ATo: string): TLzNexFragment; override;
    function TruncateTableSQL(const ATable: string): TLzNexFragment; override;
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment; override;
    function TablesSQL(const ASchema: string): TLzNexFragment; override;
    function ColumnsSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasIndexSQL(const ATable: string; const AColumns: TLzNexValues;
      const ASchema: string): TLzNexFragment; override;
    function IndexName(const ATable: string; const AColumns: TLzNexValues;
      const AKind: TLzNexIndexKind): string; override;
  end;

function NewFirebirdSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;

// Corta o nome para caber no limite do Firebird sem perder a unicidade: o que
// sobra do corte vira um sufixo de hash do nome inteiro.
function ShortenFirebirdIdentifier(const AName: string;
  const AMaxLength: Integer = LZNEX_FIREBIRD_MAX_IDENTIFIER): string;

implementation

// O estouro e o proprio algoritmo: sem {$Q-} o build com -Co derruba aqui.
{$PUSH}{$Q-}{$R-}
function FnvHash(const AText: string): LongWord;
var
  I: Integer;
begin
  Result := LongWord($811C9DC5);
  for I := 1 to Length(AText) do
  begin
    Result := Result xor LongWord(Ord(AText[I]));
    Result := Result * LongWord(16777619);
  end;
end;
{$POP}

function ShortenFirebirdIdentifier(const AName: string;
  const AMaxLength: Integer): string;
var
  Suffix: string;
begin
  if Length(AName) <= AMaxLength then
    Exit(AName);

  Suffix := '_' + LowerCase(IntToHex(FnvHash(AName), 8));
  Result := Copy(AName, 1, AMaxLength - Length(Suffix)) + Suffix;
end;

function TLzNexFirebirdSchemaCompiler.IsAutoType(
  const AType: TLzNexColumnType): Boolean;
begin
  Result := AType in [ctIncrements, ctBigIncrements];
end;

function TLzNexFirebirdSchemaCompiler.ModifierSQL(
  const AMod: TLzNexColumnModifier; const ACol: ILzNexColumnDef): string;
begin
  case AMod of
    mdNullable:
      { O Firebird nao aceita NULL explicito como restricao de coluna: coluna
        sem NOT NULL ja e anulavel. }
      if ACol.HasModifier(mdNullable) then
        Result := ''
      else
        Result := 'not null';
    mdCollate:
      // A collation e um identificador, nao um literal: UNICODE_CI, nao 'UNICODE_CI'.
      if ACol.HasModifier(mdCollate) then
        Result := 'collate ' + ACol.CollateName
      else
        Result := '';
  else
    Result := inherited ModifierSQL(AMod, ACol);
  end;
end;

function TLzNexFirebirdSchemaCompiler.ColumnDefinitionSQL(
  const ACol: ILzNexColumnDef): string;
begin
  Result := inherited ColumnDefinitionSQL(ACol);
  if ACol.ColumnType <> ctEnum then
    Exit;

  // Sem tipo enum: a lista vira CHECK, como no PostgreSQL.
  Result := Result + ' check (' + Wrap(ACol.ColumnName) + ' in (' +
            EnumList(ACol.EnumItems) + '))';
end;

function TLzNexFirebirdSchemaCompiler.AddColumnPrefix: string;
begin
  Result := 'add ';
end;

function TLzNexFirebirdSchemaCompiler.DropColumnPrefix: string;
begin
  Result := 'drop ';
end;

function TLzNexFirebirdSchemaCompiler.ChangeColumnParts(
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
  { Como no PostgreSQL, cada aspecto e uma acao propria -- aqui com a palavra
    TYPE e com SET/DROP NOT NULL, que existem desde o Firebird 3. }
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

function TLzNexFirebirdSchemaCompiler.RenameColumnSQL(const ATable: ILzNexTable;
  const AFrom, ATo: string): string;
begin

  Result := 'alter table ' + TableRef(ATable) + ' alter column ' +
            Wrap(AFrom) + ' to ' + Wrap(ATo);
end;

function TLzNexFirebirdSchemaCompiler.ColumnTypeSQL(
  const AType: TLzNexColumnType; const AParam1, AParam2: Integer;
  const AItems: TLzNexValues): string;
var
  Len: Integer;
begin
  case AType of
    ctIncrements:

      Result := 'integer generated by default as identity primary key';
    ctBigIncrements:
      Result := 'bigint generated by default as identity primary key';
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
        Result := 'decimal(18, 4)'
      else
        Result := 'decimal(' + IntToStr(AParam1) + ', ' + IntToStr(AParam2) + ')';
    ctFloat:
      Result := 'float';
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

      Result := 'blob sub_type text';
    ctBinary:

      if AParam1 > 0 then
        Result := 'varchar(' + IntToStr(AParam1) + ') character set octets'
      else
        Result := 'blob sub_type binary';
    ctBlob:
      Result := 'blob sub_type binary';
    ctDate:
      Result := 'date';
    ctTime:
      Result := 'time';
    ctDateTime, ctTimestamp:
      Result := 'timestamp';
    ctJson, ctJsonb:

      Result := 'blob sub_type text';
    ctUuid:
      Result := 'char(36)';
    ctEnum:
      begin
        if Length(AItems) = 0 then
          raise ELzNexSchema.Create('enum without items in Firebird DDL.');

        Result := 'varchar(255)';
      end;
    ctSpecific:
      Result := '';
  else
    Result := inherited ColumnTypeSQL(AType, AParam1, AParam2, AItems);
  end;
end;

function TLzNexFirebirdSchemaCompiler.ModifierOrder: TLzNexColumnModifiers;
begin
  { O DEFAULT vem antes das restricoes no Firebird, e a collation depois de
    todas elas. Nao ha unsigned nem comentario inline. }
  Result := TLzNexColumnModifiers.Create(mdDefault, mdNullable, mdCollate);
end;

function TLzNexFirebirdSchemaCompiler.DropTableSQL(const ATable: string;
  const AIfExists: Boolean): TLzNexFragment;
begin
  if not AIfExists then
    Exit(inherited DropTableSQL(ATable, False));

  { Nao existe DROP TABLE IF EXISTS no Firebird 3 nem no 5: o teste de
    existencia vai dentro de um EXECUTE BLOCK, que e um statement so. }
  Result := TLzNexFragment.Lit(
    'execute block as begin ' +
    'if (exists(select 1 from rdb$relations where trim(rdb$relation_name) = ' +
    QuotedStr(ATable) + ')) then ' +
    'execute statement ' + QuotedStr('drop table ' + WrapPath(ATable)) + '; ' +
    'end');
end;

function TLzNexFirebirdSchemaCompiler.RenameTableSQL(
  const AFrom, ATo: string): TLzNexFragment;
begin
  raise ELzNexSchema.CreateFmt(
    'Firebird cannot rename a table (there is no ALTER TABLE ... RENAME in 3 ' +
    'or in 5): "%s" would have to be recreated as "%s", copied and dropped. ' +
    'Write those steps in the migration.', [AFrom, ATo]);
end;

function TLzNexFirebirdSchemaCompiler.TruncateTableSQL(
  const ATable: string): TLzNexFragment;
begin

  Result := TLzNexFragment.Lit('delete from ' + WrapPath(ATable));
end;

function TLzNexFirebirdSchemaCompiler.HasTableSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
begin
  { Nao ha information_schema: o catalogo e RDB$RELATIONS, e o nome vem
    preenchido com espaco a direita, dai o trim. }
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  Result := TLzNexFragment.Make(
    'select count(*) from rdb$relations where trim(rdb$relation_name) = ?', B);
end;

function TLzNexFirebirdSchemaCompiler.HasColumnSQL(
  const ATable, AColumn, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
begin
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  B.Add(TLzNexValue.FromString(AColumn));
  Result := TLzNexFragment.Make(
    'select count(*) from rdb$relation_fields ' +
    'where trim(rdb$relation_name) = ? and trim(rdb$field_name) = ?', B);
end;

function TLzNexFirebirdSchemaCompiler.TablesSQL(
  const ASchema: string): TLzNexFragment;
begin
  // rdb$system_flag = 0 exclui o catalogo; rdb$view_blr nulo exclui view.
  Result := TLzNexFragment.Lit(
    'select trim(rdb$relation_name) as table_name from rdb$relations ' +
    'where rdb$system_flag = 0 and rdb$view_blr is null ' +
    'order by rdb$relation_name');
end;

function TLzNexFirebirdSchemaCompiler.ColumnsSQL(
  const ATable, ASchema: string): TLzNexFragment;
var
  B: TLzNexBindings;
begin
  B := TLzNexBindings.Empty;
  B.Add(TLzNexValue.FromString(ATable));
  Result := TLzNexFragment.Make(
    'select trim(rdb$field_name) as column_name from rdb$relation_fields ' +
    'where trim(rdb$relation_name) = ? order by rdb$field_position', B);
end;

function TLzNexFirebirdSchemaCompiler.HasIndexSQL(const ATable: string;
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

  // rdb$index_name e rdb$field_name vem com padding de char: trim nos dois.
  S := 'select count(*) from (' +
       'select i.indexname from (' +
       'select trim(ix.rdb$index_name) as indexname, ' +
       'trim(seg.rdb$field_name) as column_name ' +
       'from rdb$indices ix ' +
       'join rdb$index_segments seg on seg.rdb$index_name = ix.rdb$index_name ' +
       'where trim(ix.rdb$relation_name) = ?' +
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

function TLzNexFirebirdSchemaCompiler.IndexName(const ATable: string;
  const AColumns: TLzNexValues; const AKind: TLzNexIndexKind): string;
begin
  Result := ShortenFirebirdIdentifier(
    inherited IndexName(ATable, AColumns, AKind));
end;

function NewFirebirdSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;
begin
  Result := TLzNexFirebirdSchemaCompiler.Create(AClient);
end;

end.
