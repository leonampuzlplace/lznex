unit LzNex.Schema.Postgres;

{ Gerador de DDL do PostgreSQL.

  So sobrescreve o que difere do ANSI: tipos fisicos (serial/bytea/jsonb/uuid),
  ordem dos modificadores, o CHECK que emula enum, o truncate com `restart
  identity` e as consultas de existencia via information_schema.

  Herdado de proposito, porque o default da base ja e o do Postgres:
    AddColumnPrefix / ChangeColumnPrefix / DropColumnPrefix
                       -> `add column `, `alter column `, `drop column `
                          (o MySQL e quem usa `add `/`modify `/`drop `)
    InlineComments     -> False, entao o comentario de coluna sai como comando
                          SEPARADO (`comment on column "t"."c" is '...'`) no
                          Post do plano, nao como modificador inline
    RenameTableSQL     -> `alter table "a" rename to "b"`
    IndexSQL / DropIndexSQL
                       -> `create index`, `add constraint ... unique`,
                          `drop constraint` -- ja e a sintaxe do Postgres
    TableOptionsSQL    -> vazio: nao existe engine/charset por tabela }

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
  public
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string; override;
    function ModifierOrder: TLzNexColumnModifiers; override;
    function TruncateTableSQL(const ATable: string): TLzNexFragment; override;
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment; override;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment; override;
  end;

// Fabrica de modulo. O NewSchemaCompiler do LzNex.Client.Postgres deve delegar
// para esta funcao (a unit do client nao pode usar esta na interface: seria
// ciclo).
function NewPostgresSchemaCompiler(const AClient: ILzNexClient): ILzNexSchemaCompiler;

implementation

{ TLzNexPostgresSchemaCompiler }

function TLzNexPostgresSchemaCompiler.ColumnTypeSQL(const AType: TLzNexColumnType;
  const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;
var
  Len: Integer;
begin
  case AType of
    ctIncrements:
      // serial ja carrega o default da sequence e o not null.
      Result := 'serial primary key';
    ctBigIncrements:
      Result := 'bigserial primary key';
    ctTinyInt, ctSmallInt:
      // Nao existe inteiro de 1 byte no Postgres.
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
      // text do Postgres nao tem teto, logo os quatro tamanhos do MySQL
      // colapsam num tipo so.
      Result := 'text';
    ctBinary, ctBlob:
      // bytea ignora tamanho: nao existe varbinary(n) aqui.
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
      // jsonb e tipo proprio: guarda parseado e aceita indice GIN.
      Result := 'jsonb';
    ctUuid:
      Result := 'uuid';
    ctEnum:
      begin
        if Length(AItems) = 0 then
          raise ELzNexSchema.Create('enum without items in PostgreSQL DDL.');
        // Caminho nao-nativo: `text` mais um CHECK, montado em
        // ColumnDefinitionSQL (que e quem conhece o nome da coluna). O enum
        // nativo exigiria um `create type ... as enum` no Pre do plano e um
        // `drop type` no rollback, o que o ILzNexSchemaCompiler ainda nao
        // tem como expressar a partir daqui.
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

function TLzNexPostgresSchemaCompiler.ModifierOrder: TLzNexColumnModifiers;
begin
  // Dois modificadores, e os outros ficam de fora por motivo:
  //   mdUnsigned nao existe no Postgres -- deixar fora da ordem e o que faz o
  //     modificador ser IGNORADO em silencio, sem gerar DDL que o banco recusa
  //     e sem quebrar migration escrita para MySQL;
  //   mdComment vira comando separado (`comment on column`);
  //   mdCollate, mdFirst e mdAfter nao tem forma inline aqui.
  Result := TLzNexColumnModifiers.Create(mdNullable, mdDefault);
end;

function TLzNexPostgresSchemaCompiler.TruncateTableSQL(
  const ATable: string): TLzNexFragment;
begin
  // Mesma forma do compiler de query: sem `restart identity` as sequences dos
  // serial ficam onde estavam.
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
    // Sem schema explicito o alvo e o primeiro schema do search_path, que e
    // onde um create table sem qualificacao cairia.
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
