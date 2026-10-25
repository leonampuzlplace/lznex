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
  public
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string; override;
    function ModifierOrder: TLzNexColumnModifiers; override;
    function TruncateTableSQL(const ATable: string): TLzNexFragment; override;
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment; override;
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

function NewPostgresSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;
begin
  Result := TLzNexPostgresSchemaCompiler.Create(AClient);
end;

end.
