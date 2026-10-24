unit LzNex.Schema.Compiler;

{ TLzNexSchemaCompilerBase: gerador de DDL com defaults ANSI.

  Incluir um banco novo no schema builder = descender desta classe e sobrescrever
  o que muda (tipos fisicos, ordem de modificadores, prefixos de alter).

  Dois pontos estruturais que valem destacar:

  1. A ORDEM dos modificadores no DDL e do DIALETO (ModifierOrder), nunca a ordem
     em que o usuario chamou. T.Int('x').Default_(1).Unsigned e
     T.Int('x').Unsigned.Default_(1) tem que sair identicos, senao bastaria
     inverter duas chamadas para gerar DDL invalido.

  2. O DEFAULT e INTERPOLADO no texto, nao vira bind: a maioria dos bancos nao
     aceita placeholder em DDL. A interpolacao aqui e legitima e passa por
     Client.EscapeForLog, que e o unico escapador do projeto. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Exceptions;

type
  TLzNexSchemaCompilerBase = class(TInterfacedObject, ILzNexSchemaCompiler)
  protected
    FClient: ILzNexClient;

    // --- lexico ---
    function Wrap(const AName: string): string;
    function WrapPath(const AName: string): string;
    function ColumnList(const AColumns: TLzNexValues): string;
    function EnumList(const AItems: TLzNexValues): string;
    function TableRef(const ATable: ILzNexTable): string;

    // --- coluna ---
    // True para os tipos cujo texto ja carrega not null/PK/auto_increment.
    // Nesses o compiler nao emite modificador nenhum.
    function IsAutoType(const AType: TLzNexColumnType): Boolean; virtual;
    // Se o comentario de coluna cabe na propria definicao (MySQL) ou precisa de
    // um comando separado (ANSI/PostgreSQL).
    function InlineComments: Boolean; virtual;
    // Se o tipo aceita DEFAULT. MySQL recusa em TEXT/BLOB.
    function SupportsDefaultOn(const ACol: ILzNexColumnDef): Boolean; virtual;
    function DefaultLiteral(const ACol: ILzNexColumnDef): string; virtual;
    function ColumnTypeFor(const ACol: ILzNexColumnDef): string;
    function ModifierSQL(const AMod: TLzNexColumnModifier;
      const ACol: ILzNexColumnDef): string; virtual;
    function ColumnDefinitionSQL(const ACol: ILzNexColumnDef): string; virtual;

    // --- prefixos de alter ---
    function AddColumnPrefix: string; virtual;
    function ChangeColumnPrefix: string; virtual;
    function DropColumnPrefix: string; virtual;

    // --- pedacos de comando ---
    function TableOptionsSQL(const ATable: ILzNexTable): string; virtual;
    function IndexNameOf(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string;
    function IndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; virtual;
    function DropIndexSQL(const ATable: ILzNexTable;
      const AIndex: ILzNexIndexDef): string; virtual;
    function RenameColumnSQL(const ATable: ILzNexTable;
      const AFrom, ATo: string): string; virtual;
    function ColumnCommentSQL(const ATable: ILzNexTable;
      const ACol: ILzNexColumnDef): string; virtual;
    function TableCommentSQL(const ATable: ILzNexTable): string; virtual;

    procedure PushStmt(var APlan: TLzNexDdlPlan; const ASQL: string);
    procedure PushPost(var APlan: TLzNexDdlPlan; const ASQL: string);
    procedure CompileCreate(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan); virtual;
    procedure CompileAlter(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan); virtual;
    procedure CompileIndexes(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan; const ASkipPrimary: Boolean);
    procedure CompileComments(const ATable: ILzNexTable;
      var APlan: TLzNexDdlPlan);
  public
    constructor Create(const AClient: ILzNexClient);

    // O dialeto usado por este compiler.
    function Client: ILzNexClient;

    function CompileTable(const ATable: ILzNexTable): TLzNexDdlPlan; virtual;
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string; virtual;
    function ModifierOrder: TLzNexColumnModifiers; virtual;
    function DropTableSQL(const ATable: string;
      const AIfExists: Boolean): TLzNexFragment; virtual;
    function RenameTableSQL(const AFrom, ATo: string): TLzNexFragment; virtual;
    function TruncateTableSQL(const ATable: string): TLzNexFragment; virtual;
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment; virtual;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment; virtual;
    function IndexName(const ATable: string; const AColumns: TLzNexValues;
      const AKind: TLzNexIndexKind): string; virtual;
  end;

// Sufixo do nome automatico de indice ('index', 'unique', 'primary', 'foreign').
function IndexKindSuffix(const AKind: TLzNexIndexKind): string;

implementation

function IndexKindSuffix(const AKind: TLzNexIndexKind): string;
begin
  case AKind of
    ixIndex: Result := 'index';
    ixUnique: Result := 'unique';
    ixPrimary: Result := 'primary';
    ixForeign: Result := 'foreign';
  else
    Result := 'index';
  end;
end;

{ TLzNexSchemaCompilerBase }

constructor TLzNexSchemaCompilerBase.Create(const AClient: ILzNexClient);
begin
  inherited Create;
  if AClient = nil then
    raise ELzNexSchema.Create('Schema compiler without a dialect: ILzNexClient is nil.');
  FClient := AClient;
end;

function TLzNexSchemaCompilerBase.Client: ILzNexClient;
begin
  Result := FClient;
end;

{ lexico }

function TLzNexSchemaCompilerBase.Wrap(const AName: string): string;
begin
  Result := FClient.WrapIdentifier(AName);
end;

function TLzNexSchemaCompilerBase.WrapPath(const AName: string): string;
begin
  Result := FClient.WrapQualified(AName);
end;

function TLzNexSchemaCompilerBase.ColumnList(const AColumns: TLzNexValues): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(AColumns) do
    begin
      if I > 0 then
        SB.Append(', ');
      SB.Append(Wrap(AColumns[I].Text));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexSchemaCompilerBase.EnumList(const AItems: TLzNexValues): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(AItems) do
    begin
      if I > 0 then
        SB.Append(', ');
      SB.Append(QuotedStr(AItems[I].AsString));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexSchemaCompilerBase.TableRef(const ATable: ILzNexTable): string;
begin
  if Trim(ATable.SchemaName) <> '' then
    Result := Wrap(ATable.SchemaName) + '.' + Wrap(ATable.TableName)
  else
    Result := Wrap(ATable.TableName);
end;

{ coluna }

function TLzNexSchemaCompilerBase.IsAutoType(const AType: TLzNexColumnType): Boolean;
begin
  Result := AType in [ctIncrements, ctBigIncrements];
end;

function TLzNexSchemaCompilerBase.InlineComments: Boolean;
begin
  Result := False;
end;

function TLzNexSchemaCompilerBase.SupportsDefaultOn(const ACol: ILzNexColumnDef): Boolean;
begin
  Result := True;
end;

function TLzNexSchemaCompilerBase.DefaultLiteral(const ACol: ILzNexColumnDef): string;
var
  V: TLzNexValue;
  R: ILzNexRaw;
begin
  V := ACol.DefaultValue;
  if V.Kind = vkRaw then
  begin
    R := nil;
    if (V.Ref = nil) or (not Supports(V.Ref, ILzNexRaw, R)) then
      raise ELzNexSchema.CreateFmt(
        'Invalid raw default on column "%s": the value does not carry an ILzNexRaw.',
        [ACol.ColumnName]);
    Exit(R.Template);
  end;

  // Em DDL o default NAO pode ser bind (nem MySQL nem PostgreSQL aceitam
  // placeholder ali), logo aqui a interpolacao e legitima. O escapador e o
  // mesmo do log, que e o unico do projeto.
  Result := FClient.EscapeForLog(V);
end;

function TLzNexSchemaCompilerBase.ColumnTypeFor(const ACol: ILzNexColumnDef): string;
begin
  if ACol.ColumnType = ctSpecific then
  begin
    if Trim(ACol.SpecificType) = '' then
      raise ELzNexSchema.CreateFmt(
        'Column "%s" is ctSpecific but carries no type text.',
        [ACol.ColumnName]);
    Exit(ACol.SpecificType);
  end;
  Result := ColumnTypeSQL(ACol.ColumnType, ACol.Param1, ACol.Param2, ACol.EnumItems);
end;

function TLzNexSchemaCompilerBase.ModifierSQL(const AMod: TLzNexColumnModifier;
  const ACol: ILzNexColumnDef): string;
begin
  Result := '';
  case AMod of
    mdUnsigned:
      if ACol.HasModifier(mdUnsigned) then
        Result := 'unsigned';
    mdNullable:
      // Sempre explicito: ausencia de mdNullable significa not null.
      if ACol.HasModifier(mdNullable) then
        Result := 'null'
      else
        Result := 'not null';
    mdDefault:
      if ACol.HasModifier(mdDefault) and SupportsDefaultOn(ACol) then
        Result := 'default ' + DefaultLiteral(ACol);
    mdComment:
      if ACol.HasModifier(mdComment) and InlineComments then
        Result := 'comment ' + QuotedStr(ACol.CommentText);
    mdCollate:
      if ACol.HasModifier(mdCollate) then
        Result := 'collate ' + QuotedStr(ACol.CollateName);
    mdFirst:
      if ACol.HasModifier(mdFirst) then
        Result := 'first';
    mdAfter:
      if ACol.HasModifier(mdAfter) then
        Result := 'after ' + Wrap(ACol.AfterColumn);
    mdPrimaryKey:
      if ACol.HasModifier(mdPrimaryKey) then
        Result := 'primary key';
    mdAutoIncrement:
      if ACol.HasModifier(mdAutoIncrement) then
        Result := 'auto_increment';
  end;
end;

function TLzNexSchemaCompilerBase.ColumnDefinitionSQL(
  const ACol: ILzNexColumnDef): string;
var
  SB: TStringBuilder;
  Order: TLzNexColumnModifiers;
  I: Integer;
  Piece: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(Wrap(ACol.ColumnName));
    SB.Append(' ');
    SB.Append(ColumnTypeFor(ACol));

    // Increments ja vem completo do tipo fisico; qualquer modificador aqui
    // duplicaria not null/primary key.
    if not IsAutoType(ACol.ColumnType) then
    begin
      Order := ModifierOrder;
      for I := 0 to High(Order) do
      begin
        Piece := ModifierSQL(Order[I], ACol);
        if Piece <> '' then
        begin
          SB.Append(' ');
          SB.Append(Piece);
        end;
      end;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ prefixos de alter }

function TLzNexSchemaCompilerBase.AddColumnPrefix: string;
begin
  Result := 'add column ';
end;

function TLzNexSchemaCompilerBase.ChangeColumnPrefix: string;
begin
  Result := 'alter column ';
end;

function TLzNexSchemaCompilerBase.DropColumnPrefix: string;
begin
  Result := 'drop column ';
end;

{ pedacos de comando }

function TLzNexSchemaCompilerBase.TableOptionsSQL(const ATable: ILzNexTable): string;
begin
  // ANSI nao tem engine/charset por tabela.
  Result := '';
end;

function TLzNexSchemaCompilerBase.IndexNameOf(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
begin
  if Trim(AIndex.IndexNameOverride) <> '' then
    Result := AIndex.IndexNameOverride
  else
    Result := IndexName(ATable.TableName, AIndex.Columns, AIndex.IndexKind);
end;

function TLzNexSchemaCompilerBase.IndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
var
  Name: string;
begin
  if Length(AIndex.Columns) = 0 then
    raise ELzNexSchema.CreateFmt(
      'Index without columns on table "%s".', [ATable.TableName]);

  Name := IndexNameOf(ATable, AIndex);
  case AIndex.IndexKind of
    ixIndex:
      Result := 'create index ' + Wrap(Name) + ' on ' + TableRef(ATable) +
                ' (' + ColumnList(AIndex.Columns) + ')';
    ixUnique:
      Result := 'alter table ' + TableRef(ATable) + ' add constraint ' +
                Wrap(Name) + ' unique (' + ColumnList(AIndex.Columns) + ')';
    ixPrimary:
      Result := 'alter table ' + TableRef(ATable) + ' add constraint ' +
                Wrap(Name) + ' primary key (' + ColumnList(AIndex.Columns) + ')';
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

        Result := 'alter table ' + TableRef(ATable) + ' add constraint ' +
                  Wrap(Name) + ' foreign key (' + ColumnList(AIndex.Columns) +
                  ') references ' + WrapPath(AIndex.RefTable) +
                  ' (' + ColumnList(AIndex.RefColumns) + ')';
        if AIndex.OnDeleteAction <> '' then
          Result := Result + ' on delete ' + AIndex.OnDeleteAction;
        if AIndex.OnUpdateAction <> '' then
          Result := Result + ' on update ' + AIndex.OnUpdateAction;
      end;
  else
    raise ELzNexSchema.Create('Unknown index kind.');
  end;
end;

function TLzNexSchemaCompilerBase.DropIndexSQL(const ATable: ILzNexTable;
  const AIndex: ILzNexIndexDef): string;
var
  Name: string;
begin
  Name := IndexNameOf(ATable, AIndex);
  if AIndex.IndexKind = ixIndex then
    Result := 'drop index ' + Wrap(Name)
  else
    Result := 'alter table ' + TableRef(ATable) + ' drop constraint ' + Wrap(Name);
end;

function TLzNexSchemaCompilerBase.RenameColumnSQL(const ATable: ILzNexTable;
  const AFrom, ATo: string): string;
begin
  Result := 'alter table ' + TableRef(ATable) + ' rename column ' +
            Wrap(AFrom) + ' to ' + Wrap(ATo);
end;

function TLzNexSchemaCompilerBase.ColumnCommentSQL(const ATable: ILzNexTable;
  const ACol: ILzNexColumnDef): string;
begin
  Result := 'comment on column ' + TableRef(ATable) + '.' +
            Wrap(ACol.ColumnName) + ' is ' + QuotedStr(ACol.CommentText);
end;

function TLzNexSchemaCompilerBase.TableCommentSQL(const ATable: ILzNexTable): string;
begin
  Result := 'comment on table ' + TableRef(ATable) + ' is ' +
            QuotedStr(ATable.CommentText);
end;

{ montagem do plano }

procedure TLzNexSchemaCompilerBase.PushStmt(var APlan: TLzNexDdlPlan;
  const ASQL: string);
begin
  SetLength(APlan.Statements, Length(APlan.Statements) + 1);
  APlan.Statements[High(APlan.Statements)] := TLzNexFragment.Lit(ASQL);
end;

procedure TLzNexSchemaCompilerBase.PushPost(var APlan: TLzNexDdlPlan;
  const ASQL: string);
begin
  SetLength(APlan.Post, Length(APlan.Post) + 1);
  APlan.Post[High(APlan.Post)] := TLzNexFragment.Lit(ASQL);
end;

procedure TLzNexSchemaCompilerBase.CompileIndexes(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan; const ASkipPrimary: Boolean);
var
  I: Integer;
  Idx: ILzNexIndexDef;
begin
  for I := 0 to ATable.IndexCount - 1 do
  begin
    Idx := ATable.IndexAt(I);
    if ASkipPrimary and (Idx.IndexKind = ixPrimary) and (not Idx.IsDrop) then
      Continue;   // em create a PK vai inline no proprio create table
    if Idx.IsDrop then
      PushPost(APlan, DropIndexSQL(ATable, Idx))
    else
      PushPost(APlan, IndexSQL(ATable, Idx));
  end;
end;

procedure TLzNexSchemaCompilerBase.CompileComments(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan);
var
  I: Integer;
  Col: ILzNexColumnDef;
begin
  if InlineComments then
    Exit;

  for I := 0 to ATable.ColumnCount - 1 do
  begin
    Col := ATable.ColumnAt(I);
    if Col.IsDrop then
      Continue;
    if Col.HasModifier(mdComment) then
      PushPost(APlan, ColumnCommentSQL(ATable, Col));
  end;

  if (ATable.TableMethod = tmCreate) and (Trim(ATable.CommentText) <> '') then
    PushPost(APlan, TableCommentSQL(ATable));
end;

procedure TLzNexSchemaCompilerBase.CompileCreate(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan);
var
  SB: TStringBuilder;
  I: Integer;
  Col: ILzNexColumnDef;
  Prim: ILzNexIndexDef;
  First: Boolean;
begin
  if ATable.ColumnCount = 0 then
    raise ELzNexSchema.CreateFmt(
      'create table "%s" has no columns at all.', [ATable.TableName]);

  Prim := nil;
  for I := 0 to ATable.IndexCount - 1 do
    if (ATable.IndexAt(I).IndexKind = ixPrimary) and (not ATable.IndexAt(I).IsDrop) then
    begin
      Prim := ATable.IndexAt(I);
      Break;
    end;

  SB := TStringBuilder.Create;
  try
    SB.Append('create table ');
    SB.Append(TableRef(ATable));
    SB.Append(' (');

    First := True;
    for I := 0 to ATable.ColumnCount - 1 do
    begin
      Col := ATable.ColumnAt(I);
      if not First then
        SB.Append(', ');
      SB.Append(ColumnDefinitionSQL(Col));
      First := False;
    end;

    // PK inline: um comando so para a tabela inteira.
    if (Prim <> nil) and (Length(Prim.Columns) > 0) then
    begin
      SB.Append(', primary key (');
      SB.Append(ColumnList(Prim.Columns));
      SB.Append(')');
    end;

    SB.Append(')');
    SB.Append(TableOptionsSQL(ATable));
    PushStmt(APlan, SB.ToString);
  finally
    SB.Free;
  end;

  CompileIndexes(ATable, APlan, True);
  CompileComments(ATable, APlan);
end;

procedure TLzNexSchemaCompilerBase.CompileAlter(const ATable: ILzNexTable;
  var APlan: TLzNexDdlPlan);
var
  Adds, Changes, Drops: TStringBuilder;
  NAdds, NChanges, NDrops: Integer;
  I: Integer;
  Col: ILzNexColumnDef;
  Ren: TLzNexNamedValues;
  Head: string;
begin
  Head := 'alter table ' + TableRef(ATable) + ' ';
  NAdds := 0;
  NChanges := 0;
  NDrops := 0;

  // Os tres builders nascem DENTRO do try: se o segundo Create levantasse, o
  // primeiro ficaria orfao sem ninguem para liberar. Free em nil e seguro.
  Adds := nil;
  Changes := nil;
  Drops := nil;
  try
    Adds := TStringBuilder.Create;
    Changes := TStringBuilder.Create;
    Drops := TStringBuilder.Create;

    for I := 0 to ATable.ColumnCount - 1 do
    begin
      Col := ATable.ColumnAt(I);
      if Col.IsDrop then
      begin
        if NDrops > 0 then
          Drops.Append(', ');
        Drops.Append(DropColumnPrefix);
        Drops.Append(Wrap(Col.ColumnName));
        Inc(NDrops);
      end
      else if Col.IsChange then
      begin
        if NChanges > 0 then
          Changes.Append(', ');
        Changes.Append(ChangeColumnPrefix);
        Changes.Append(ColumnDefinitionSQL(Col));
        Inc(NChanges);
      end
      else
      begin
        if NAdds > 0 then
          Adds.Append(', ');
        Adds.Append(AddColumnPrefix);
        Adds.Append(ColumnDefinitionSQL(Col));
        Inc(NAdds);
      end;
    end;

    // Um comando por categoria: agregar evita N viagens ao banco e N rebuilds
    // de tabela no MySQL.
    if NAdds > 0 then
      PushStmt(APlan, Head + Adds.ToString);
    if NChanges > 0 then
      PushStmt(APlan, Head + Changes.ToString);
    if NDrops > 0 then
      PushStmt(APlan, Head + Drops.ToString);
  finally
    Drops.Free;
    Changes.Free;
    Adds.Free;
  end;

  Ren := ATable.RenamedColumns;
  for I := 0 to High(Ren) do
    PushStmt(APlan, RenameColumnSQL(ATable, Ren[I].Name, Ren[I].Value.AsString));

  CompileIndexes(ATable, APlan, False);
  CompileComments(ATable, APlan);

  if APlan.Count = 0 then
    raise ELzNexSchema.CreateFmt(
      'alter table "%s" has no operations at all: nothing to do.',
      [ATable.TableName]);
end;

{ ILzNexSchemaCompiler }

function TLzNexSchemaCompilerBase.CompileTable(
  const ATable: ILzNexTable): TLzNexDdlPlan;
begin
  Result := Default(TLzNexDdlPlan);
  if ATable = nil then
    raise ELzNexSchema.Create('CompileTable received nil.');

  if ATable.TableMethod = tmCreate then
    CompileCreate(ATable, Result)
  else
    CompileAlter(ATable, Result);
end;

function TLzNexSchemaCompilerBase.ColumnTypeSQL(const AType: TLzNexColumnType;
  const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;
var
  Len: Integer;
begin
  case AType of
    ctIncrements:
      Result := 'integer not null primary key';
    ctBigIncrements:
      Result := 'bigint not null primary key';
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
    ctDateTime, ctTimestamp:
      Result := 'timestamp';
    ctJson, ctJsonb:
      Result := 'json';
    ctUuid:
      Result := 'char(36)';
    ctEnum:
      // ANSI nao tem enum; o dialeto que tiver sobrescreve.
      Result := 'varchar(255)';
    ctSpecific:
      Result := '';
  else
    raise ELzNexSchema.CreateFmt(
      'Column type %d is not supported by dialect "%s".',
      [Ord(AType), FClient.DialectName]);
  end;
end;

function TLzNexSchemaCompilerBase.ModifierOrder: TLzNexColumnModifiers;
begin
  // Ordem ANSI. Comentario nao entra: no ANSI ele e um comando separado.
  Result := TLzNexColumnModifiers.Create(
    mdUnsigned, mdCollate, mdNullable, mdDefault, mdFirst, mdAfter);
end;

function TLzNexSchemaCompilerBase.DropTableSQL(const ATable: string;
  const AIfExists: Boolean): TLzNexFragment;
begin
  if AIfExists then
    Result := TLzNexFragment.Lit('drop table if exists ' + WrapPath(ATable))
  else
    Result := TLzNexFragment.Lit('drop table ' + WrapPath(ATable));
end;

function TLzNexSchemaCompilerBase.RenameTableSQL(const AFrom, ATo: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit(
    'alter table ' + WrapPath(AFrom) + ' rename to ' + WrapPath(ATo));
end;

function TLzNexSchemaCompilerBase.TruncateTableSQL(const ATable: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit('truncate table ' + WrapPath(ATable));
end;

function TLzNexSchemaCompilerBase.HasTableSQL(const ATable, ASchema: string): TLzNexFragment;
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
  end;
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexSchemaCompilerBase.HasColumnSQL(
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
  end;
  Result := TLzNexFragment.Make(S, B);
end;

function TLzNexSchemaCompilerBase.IndexName(const ATable: string;
  const AColumns: TLzNexValues; const AKind: TLzNexIndexKind): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  // Convencao do knex: <tabela>_<colunas unidas por _>_<tipo>, minusculo,
  // com '.' e '-' virando '_'.
  SB := TStringBuilder.Create;
  try
    SB.Append(ATable);
    for I := 0 to High(AColumns) do
    begin
      SB.Append('_');
      SB.Append(AColumns[I].Text);
    end;
    SB.Append('_');
    SB.Append(IndexKindSuffix(AKind));
    Result := SB.ToString;
  finally
    SB.Free;
  end;

  Result := LowerCase(Result);
  Result := StringReplace(Result, '.', '_', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '_', [rfReplaceAll]);
end;

end.
