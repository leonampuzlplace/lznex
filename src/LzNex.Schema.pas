unit LzNex.Schema;

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

  TLzNexColumnModifierSet = set of TLzNexColumnModifier;

  TLzNexSchemaRaw = class(TInterfacedObject, ILzNexRaw)
  private
    FSQL: string;
  public
    constructor Create(const ASQL: string);
    function Build(const AClient: ILzNexClient): TLzNexFragment;
    function Template: string;
  end;

  TLzNexColumnDefImpl = class(TInterfacedObject, ILzNexColumnDef)
  private
    FName: string;
    FType: TLzNexColumnType;
    FParam1: Integer;
    FParam2: Integer;
    FEnumItems: TLzNexValues;
    FSpecificType: string;
    FMods: TLzNexColumnModifierSet;
    FDefault: TLzNexValue;
    FComment: string;
    FCollate: string;
    FAfter: string;
    FIsChange: Boolean;
    FIsDrop: Boolean;
  public
    constructor Create(const AName: string; const AType: TLzNexColumnType;
      const AParam1: Integer = 0; const AParam2: Integer = 0);

    function ColumnName: string;
    function ColumnType: TLzNexColumnType;
    function Param1: Integer;
    function Param2: Integer;
    function EnumItems: TLzNexValues;
    function SpecificType: string;
    function HasModifier(const AMod: TLzNexColumnModifier): Boolean;
    function DefaultValue: TLzNexValue;
    function CommentText: string;
    function CollateName: string;
    function AfterColumn: string;
    function IsChange: Boolean;
    function IsDrop: Boolean;

    procedure AddMod(const AMod: TLzNexColumnModifier);
    procedure RemoveMod(const AMod: TLzNexColumnModifier);
    procedure SetDefault(const AValue: TLzNexValue);
    procedure SetComment(const AText: string);
    procedure SetCollate(const AName: string);
    procedure SetAfter(const AColumn: string);
    procedure SetEnumItems(const AItems: TLzNexValues);
    procedure SetSpecificType(const AType: string);
    procedure MarkChange;
    procedure MarkDrop;
  end;

  TLzNexIndexDefImpl = class(TInterfacedObject, ILzNexIndexDef)
  private
    FKind: TLzNexIndexKind;
    FColumns: TLzNexValues;
    FNameOverride: string;
    FIsDrop: Boolean;
  public
    constructor Create(const AKind: TLzNexIndexKind;
      const AColumns: TLzNexValues; const AIsDrop: Boolean);

    function IndexKind: TLzNexIndexKind;
    function Columns: TLzNexValues;
    function IndexNameOverride: string;
    function RefTable: string; virtual;
    function RefColumns: TLzNexValues; virtual;
    function OnDeleteAction: string; virtual;
    function OnUpdateAction: string; virtual;
    function IsDrop: Boolean;

    procedure SetNameOverride(const AName: string);
    procedure AddColumn(const AColumn: string);
  end;

  TLzNexForeignDef = class(TLzNexIndexDefImpl)
  private
    FRefTable: string;
    FRefColumns: TLzNexValues;
    FOnDelete: string;
    FOnUpdate: string;
  public
    constructor CreateFk(const AColumns: TLzNexValues);

    function RefTable: string; override;
    function RefColumns: TLzNexValues; override;
    function OnDeleteAction: string; override;
    function OnUpdateAction: string; override;

    procedure SetRefTable(const ATable: string);
    procedure SetRefColumns(const AColumns: TLzNexValues);
    procedure SetOnDelete(const AAction: string);
    procedure SetOnUpdate(const AAction: string);
  end;

  TLzNexColumnDefs = array of ILzNexColumnDef;
  TLzNexIndexDefs = array of ILzNexIndexDef;

  TLzNexTableBase = class(TInterfacedObject, ILzNexTable)
  private
    FDb: ILzNex;
    FClient: ILzNexClient;
    FTable: string;
    FSchema: string;
    FMethod: TLzNexTableMethod;
    FColumns: TLzNexColumnDefs;
    FIndexes: TLzNexIndexDefs;
    FRenames: TLzNexNamedValues;
    FEngine: string;
    FCharset: string;
    FCollate: string;
    FComment: string;

    FLastColumn: TLzNexColumnDefImpl;
    FLastIndex: TLzNexIndexDefImpl;
    FLastForeign: TLzNexForeignDef;
    FPrimary: TLzNexIndexDefImpl;

    procedure EnsureCreate(const AMethod: string);
    procedure EnsureAlter(const AMethod: string);
    function LastColumn(const AMethod: string): TLzNexColumnDefImpl;
    function LastForeign(const AMethod: string): TLzNexForeignDef;
    function PushColumn(const AName: string; const AType: TLzNexColumnType;
      const AParam1: Integer = 0; const AParam2: Integer = 0): TLzNexColumnDefImpl;
    function PushIndex(const AKind: TLzNexIndexKind;
      const AColumns: TLzNexValues; const AIsDrop: Boolean): TLzNexIndexDefImpl;
    function FindPrimary: TLzNexIndexDefImpl;
    function Mark(const AMod: TLzNexColumnModifier; const AMethod: string): ILzNexTable;
  public
    constructor Create(const ADb: ILzNex; const AClient: ILzNexClient;
      const ATable, ASchema: string; const AMethod: TLzNexTableMethod);

    function Increments(const AName: string = 'id'): ILzNexTable;
    function BigIncrements(const AName: string = 'id'): ILzNexTable;
    function TinyInt(const AName: string): ILzNexTable;
    function SmallInt(const AName: string): ILzNexTable;
    function Int(const AName: string): ILzNexTable;
    function BigInt(const AName: string): ILzNexTable;
    function Bool(const AName: string): ILzNexTable;
    function Decimal(const AName: string; const APrecision: Integer = 8;
      const AScale: Integer = 2): ILzNexTable;
    function Float(const AName: string): ILzNexTable;
    function Double(const AName: string): ILzNexTable;
    function Char_(const AName: string; const ALength: Integer = 255): ILzNexTable;
    function Str(const AName: string; const ALength: Integer = 255): ILzNexTable;
    function Text(const AName: string): ILzNexTable;
    function MediumText(const AName: string): ILzNexTable;
    function LongText(const AName: string): ILzNexTable;
    function Binary(const AName: string; const ALength: Integer = 0): ILzNexTable;
    function Blob(const AName: string): ILzNexTable;
    function Date(const AName: string): ILzNexTable;
    function Time(const AName: string): ILzNexTable;
    function DateTime(const AName: string): ILzNexTable;
    function Timestamp(const AName: string): ILzNexTable;
    function Json(const AName: string): ILzNexTable;
    function Uuid(const AName: string): ILzNexTable;
    function Enum(const AName: string; const AItems: array of string): ILzNexTable;
    function Specific(const AName, ATypeSQL: string): ILzNexTable;
    function Timestamps(const ADefaultNow: Boolean = True): ILzNexTable;

    function NotNull: ILzNexTable;
    function Nullable: ILzNexTable;
    function Unsigned: ILzNexTable;
    function Default_(const AValue: TLzNexValue): ILzNexTable;
    function DefaultRaw(const ASQL: string): ILzNexTable;
    function Comment(const AText: string): ILzNexTable;
    function Collate(const AName: string): ILzNexTable;
    function After(const AColumn: string): ILzNexTable;
    function Primary: ILzNexTable; overload;
    function Unique: ILzNexTable; overload;
    function Index: ILzNexTable; overload;
    function Change: ILzNexTable;

    function References(const AColumn: string): ILzNexTable;
    function InTable(const ATable: string): ILzNexTable;
    function OnDelete(const AAction: string): ILzNexTable;
    function OnUpdate(const AAction: string): ILzNexTable;
    function ConstraintName(const AName: string): ILzNexTable;

    function Primary(const AColumns: array of string): ILzNexTable; overload;
    function Unique(const AColumns: array of string): ILzNexTable; overload;
    function Index(const AColumns: array of string): ILzNexTable; overload;
    function DropColumn(const AName: string): ILzNexTable;
    function DropIndex(const AColumns: array of string): ILzNexTable;
    function DropUnique(const AColumns: array of string): ILzNexTable;
    function DropForeign(const AColumns: array of string): ILzNexTable;
    function DropPrimary: ILzNexTable;
    function RenameColumn(const AFrom, ATo: string): ILzNexTable;

    function Engine(const AName: string): ILzNexTable;
    function Charset(const AName: string): ILzNexTable;
    function TableCollate(const AName: string): ILzNexTable;
    function TableComment(const AText: string): ILzNexTable;

    function ToSQL: TLzNexDdlPlan;
    function Execute: Integer;

    function TableName: string;
    function SchemaName: string;
    function TableMethod: TLzNexTableMethod;
    function ColumnCount: Integer;
    function ColumnAt(const AIndex: Integer): ILzNexColumnDef;
    function IndexCount: Integer;
    function IndexAt(const AIndex: Integer): ILzNexIndexDef;
    function RenamedColumns: TLzNexNamedValues;
    function EngineName: string;
    function CharsetName: string;
    function CollateName: string;
    function CommentText: string;
    function Client: ILzNexClient;
  end;

  TLzNexCreateTable = class(TLzNexTableBase)
  public
    constructor Create(const ADb: ILzNex; const AClient: ILzNexClient;
      const ATable, ASchema: string);
  end;

  TLzNexAlterTable = class(TLzNexTableBase)
  public
    constructor Create(const ADb: ILzNex; const AClient: ILzNexClient;
      const ATable, ASchema: string);
  end;

  TLzNexSchema = class(TInterfacedObject, ILzNexSchema)
  private
    FDb: ILzNex;
    FClient: ILzNexClient;
    FSchema: string;

    function NeedDb(const AMethod: string): ILzNex;
    function Compiler(const AMethod: string): ILzNexSchemaCompiler;
    function RunOne(const AMethod: string; const AFragment: TLzNexFragment): Int64;
  public
    constructor Create(const ADb: ILzNex; const AClient: ILzNexClient);

    function WithSchema(const AName: string): ILzNexSchema;
    function CreateTable(const AName: string): ILzNexTable;
    function Table(const AName: string): ILzNexTable;
    function HasTable(const AName: string): Boolean;
    function HasColumn(const ATable, AColumn: string): Boolean;
    procedure DropTable(const AName: string);
    procedure DropTableIfExists(const AName: string);
    procedure RenameTable(const AFrom, ATo: string);
    procedure Truncate(const AName: string);
    procedure Raw(const ASQL: string; const AArgs: array of const);
  end;

function NewSchema(const ADb: ILzNex; const AClient: ILzNexClient): ILzNexSchema;

function NormalizeFkAction(const AAction: string): string;

implementation

const

  LZNEX_FK_ACTIONS: array[0..4] of string = (
    'cascade', 'restrict', 'set null', 'no action', 'set default'
  );

function NormalizeFkAction(const AAction: string): string;
var
  I: Integer;
begin
  Result := LowerCase(Trim(AAction));
  Result := StringReplace(Result, '_', ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);

  for I := Low(LZNEX_FK_ACTIONS) to High(LZNEX_FK_ACTIONS) do
    if Result = LZNEX_FK_ACTIONS[I] then
      Exit;

  raise ELzNexSchema.CreateFmt(
    'Referential action "%s" is not allowed. Use: cascade, restrict, ' +
    'set null, no action, set default. The list is closed because the action ' +
    'is interpolated into the DDL.', [AAction]);
end;

constructor TLzNexSchemaRaw.Create(const ASQL: string);
begin
  inherited Create;
  FSQL := ASQL;
end;

function TLzNexSchemaRaw.Build(const AClient: ILzNexClient): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit(FSQL);
end;

function TLzNexSchemaRaw.Template: string;
begin
  Result := FSQL;
end;

constructor TLzNexColumnDefImpl.Create(const AName: string;
  const AType: TLzNexColumnType; const AParam1, AParam2: Integer);
begin
  inherited Create;
  FName := AName;
  FType := AType;
  FParam1 := AParam1;
  FParam2 := AParam2;
  FMods := [];
  FDefault := TLzNexValue.Unset;
end;

function TLzNexColumnDefImpl.ColumnName: string;
begin
  Result := FName;
end;

function TLzNexColumnDefImpl.ColumnType: TLzNexColumnType;
begin
  Result := FType;
end;

function TLzNexColumnDefImpl.Param1: Integer;
begin
  Result := FParam1;
end;

function TLzNexColumnDefImpl.Param2: Integer;
begin
  Result := FParam2;
end;

function TLzNexColumnDefImpl.EnumItems: TLzNexValues;
begin
  Result := FEnumItems;
end;

function TLzNexColumnDefImpl.SpecificType: string;
begin
  Result := FSpecificType;
end;

function TLzNexColumnDefImpl.HasModifier(const AMod: TLzNexColumnModifier): Boolean;
begin
  Result := AMod in FMods;
end;

function TLzNexColumnDefImpl.DefaultValue: TLzNexValue;
begin
  Result := FDefault;
end;

function TLzNexColumnDefImpl.CommentText: string;
begin
  Result := FComment;
end;

function TLzNexColumnDefImpl.CollateName: string;
begin
  Result := FCollate;
end;

function TLzNexColumnDefImpl.AfterColumn: string;
begin
  Result := FAfter;
end;

function TLzNexColumnDefImpl.IsChange: Boolean;
begin
  Result := FIsChange;
end;

function TLzNexColumnDefImpl.IsDrop: Boolean;
begin
  Result := FIsDrop;
end;

procedure TLzNexColumnDefImpl.AddMod(const AMod: TLzNexColumnModifier);
begin
  Include(FMods, AMod);
end;

procedure TLzNexColumnDefImpl.RemoveMod(const AMod: TLzNexColumnModifier);
begin
  Exclude(FMods, AMod);
end;

procedure TLzNexColumnDefImpl.SetDefault(const AValue: TLzNexValue);
begin
  if AValue.IsUnset then
    raise ELzNexSchema.CreateFmt(
      'Unset default on column "%s": a vkUnset TLzNexValue reached Default_. ' +
      'Use TLzNexValue.Null for an explicit NULL.', [FName]);
  FDefault := AValue;
  Include(FMods, mdDefault);
end;

procedure TLzNexColumnDefImpl.SetComment(const AText: string);
begin
  FComment := AText;
  Include(FMods, mdComment);
end;

procedure TLzNexColumnDefImpl.SetCollate(const AName: string);
begin
  FCollate := AName;
  Include(FMods, mdCollate);
end;

procedure TLzNexColumnDefImpl.SetAfter(const AColumn: string);
begin
  FAfter := AColumn;
  Include(FMods, mdAfter);
end;

procedure TLzNexColumnDefImpl.SetEnumItems(const AItems: TLzNexValues);
begin
  FEnumItems := AItems;
end;

procedure TLzNexColumnDefImpl.SetSpecificType(const AType: string);
begin
  FSpecificType := AType;
end;

procedure TLzNexColumnDefImpl.MarkChange;
begin
  FIsChange := True;
end;

procedure TLzNexColumnDefImpl.MarkDrop;
begin
  FIsDrop := True;
end;

constructor TLzNexIndexDefImpl.Create(const AKind: TLzNexIndexKind;
  const AColumns: TLzNexValues; const AIsDrop: Boolean);
begin
  inherited Create;
  FKind := AKind;
  FColumns := AColumns;
  FIsDrop := AIsDrop;
end;

function TLzNexIndexDefImpl.IndexKind: TLzNexIndexKind;
begin
  Result := FKind;
end;

function TLzNexIndexDefImpl.Columns: TLzNexValues;
begin
  Result := FColumns;
end;

function TLzNexIndexDefImpl.IndexNameOverride: string;
begin
  Result := FNameOverride;
end;

function TLzNexIndexDefImpl.RefTable: string;
begin
  Result := '';
end;

function TLzNexIndexDefImpl.RefColumns: TLzNexValues;
begin
  Result := nil;
end;

function TLzNexIndexDefImpl.OnDeleteAction: string;
begin
  Result := '';
end;

function TLzNexIndexDefImpl.OnUpdateAction: string;
begin
  Result := '';
end;

function TLzNexIndexDefImpl.IsDrop: Boolean;
begin
  Result := FIsDrop;
end;

procedure TLzNexIndexDefImpl.SetNameOverride(const AName: string);
begin
  FNameOverride := AName;
end;

procedure TLzNexIndexDefImpl.AddColumn(const AColumn: string);
begin
  SetLength(FColumns, Length(FColumns) + 1);
  FColumns[High(FColumns)] := TLzNexValue.Identifier(AColumn);
end;

constructor TLzNexForeignDef.CreateFk(const AColumns: TLzNexValues);
begin
  inherited Create(ixForeign, AColumns, False);
end;

function TLzNexForeignDef.RefTable: string;
begin
  Result := FRefTable;
end;

function TLzNexForeignDef.RefColumns: TLzNexValues;
begin
  Result := FRefColumns;
end;

function TLzNexForeignDef.OnDeleteAction: string;
begin
  Result := FOnDelete;
end;

function TLzNexForeignDef.OnUpdateAction: string;
begin
  Result := FOnUpdate;
end;

procedure TLzNexForeignDef.SetRefTable(const ATable: string);
begin
  FRefTable := ATable;
end;

procedure TLzNexForeignDef.SetRefColumns(const AColumns: TLzNexValues);
begin
  FRefColumns := AColumns;
end;

procedure TLzNexForeignDef.SetOnDelete(const AAction: string);
begin
  FOnDelete := NormalizeFkAction(AAction);
end;

procedure TLzNexForeignDef.SetOnUpdate(const AAction: string);
begin
  FOnUpdate := NormalizeFkAction(AAction);
end;

constructor TLzNexTableBase.Create(const ADb: ILzNex; const AClient: ILzNexClient;
  const ATable, ASchema: string; const AMethod: TLzNexTableMethod);
begin
  inherited Create;
  FDb := ADb;
  FClient := AClient;
  if (FClient = nil) and (FDb <> nil) then
    FClient := FDb.Client;
  if Trim(ATable) = '' then
    raise ELzNexSchema.Create('Empty table name in the schema builder.');
  FTable := ATable;
  FSchema := ASchema;
  FMethod := AMethod;
end;

procedure TLzNexTableBase.EnsureCreate(const AMethod: string);
begin
  if FMethod <> tmCreate then
    raise ELzNexSchema.CreateFmt(
      '%s is only valid in create table. Table "%s" is in alter mode: a ' +
      'table option does not belong in an alter here.', [AMethod, FTable]);
end;

procedure TLzNexTableBase.EnsureAlter(const AMethod: string);
begin
  if FMethod <> tmAlter then
    raise ELzNexSchema.CreateFmt(
      '%s is only valid in alter table. Table "%s" is in create mode: use ' +
      'Schema.Table(''%s'') to alter an existing table.',
      [AMethod, FTable, FTable]);
end;

function TLzNexTableBase.LastColumn(const AMethod: string): TLzNexColumnDefImpl;
begin
  if FLastColumn = nil then
    raise ELzNexSchema.CreateFmt(
      '%s has no column to apply to: the modifier acts on the LAST column ' +
      'added (e.g. T.Str(''email'', 191).NotNull). Add the column first.',
      [AMethod]);
  Result := FLastColumn;
end;

function TLzNexTableBase.LastForeign(const AMethod: string): TLzNexForeignDef;
begin
  if FLastForeign = nil then
    raise ELzNexSchema.CreateFmt(
      '%s has no foreign key to complete: call References first ' +
      '(e.g. T.Int(''user_id'').References(''id'').InTable(''users'')).', [AMethod]);
  Result := FLastForeign;
end;

function TLzNexTableBase.PushColumn(const AName: string;
  const AType: TLzNexColumnType; const AParam1, AParam2: Integer): TLzNexColumnDefImpl;
begin
  if Trim(AName) = '' then
    raise ELzNexSchema.CreateFmt(
      'Empty column name on table "%s".', [FTable]);

  Result := TLzNexColumnDefImpl.Create(AName, AType, AParam1, AParam2);

  Result.AddMod(mdNullable);

  SetLength(FColumns, Length(FColumns) + 1);
  FColumns[High(FColumns)] := Result;
  FLastColumn := Result;
  FLastForeign := nil;
end;

function TLzNexTableBase.PushIndex(const AKind: TLzNexIndexKind;
  const AColumns: TLzNexValues; const AIsDrop: Boolean): TLzNexIndexDefImpl;
begin
  Result := TLzNexIndexDefImpl.Create(AKind, AColumns, AIsDrop);
  SetLength(FIndexes, Length(FIndexes) + 1);
  FIndexes[High(FIndexes)] := Result;
  FLastIndex := Result;
  if (AKind = ixPrimary) and (not AIsDrop) then
    FPrimary := Result;
end;

function TLzNexTableBase.FindPrimary: TLzNexIndexDefImpl;
begin
  Result := FPrimary;
end;

function TLzNexTableBase.Mark(const AMod: TLzNexColumnModifier;
  const AMethod: string): ILzNexTable;
begin
  LastColumn(AMethod).AddMod(AMod);
  Result := Self;
end;

function TLzNexTableBase.Increments(const AName: string): ILzNexTable;
var
  C: TLzNexColumnDefImpl;
begin
  C := PushColumn(AName, ctIncrements);

  C.RemoveMod(mdNullable);
  C.AddMod(mdUnsigned);
  C.AddMod(mdAutoIncrement);
  C.AddMod(mdPrimaryKey);
  Result := Self;
end;

function TLzNexTableBase.BigIncrements(const AName: string): ILzNexTable;
var
  C: TLzNexColumnDefImpl;
begin
  C := PushColumn(AName, ctBigIncrements);
  C.RemoveMod(mdNullable);
  C.AddMod(mdUnsigned);
  C.AddMod(mdAutoIncrement);
  C.AddMod(mdPrimaryKey);
  Result := Self;
end;

function TLzNexTableBase.TinyInt(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctTinyInt);
  Result := Self;
end;

function TLzNexTableBase.SmallInt(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctSmallInt);
  Result := Self;
end;

function TLzNexTableBase.Int(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctInteger);
  Result := Self;
end;

function TLzNexTableBase.BigInt(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctBigInt);
  Result := Self;
end;

function TLzNexTableBase.Bool(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctBoolean);
  Result := Self;
end;

function TLzNexTableBase.Decimal(const AName: string;
  const APrecision, AScale: Integer): ILzNexTable;
begin
  PushColumn(AName, ctDecimal, APrecision, AScale);
  Result := Self;
end;

function TLzNexTableBase.Float(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctFloat);
  Result := Self;
end;

function TLzNexTableBase.Double(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctDouble);
  Result := Self;
end;

function TLzNexTableBase.Char_(const AName: string; const ALength: Integer): ILzNexTable;
begin
  PushColumn(AName, ctChar, ALength);
  Result := Self;
end;

function TLzNexTableBase.Str(const AName: string; const ALength: Integer): ILzNexTable;
begin
  PushColumn(AName, ctString, ALength);
  Result := Self;
end;

function TLzNexTableBase.Text(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctText);
  Result := Self;
end;

function TLzNexTableBase.MediumText(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctMediumText);
  Result := Self;
end;

function TLzNexTableBase.LongText(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctLongText);
  Result := Self;
end;

function TLzNexTableBase.Binary(const AName: string; const ALength: Integer): ILzNexTable;
begin
  PushColumn(AName, ctBinary, ALength);
  Result := Self;
end;

function TLzNexTableBase.Blob(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctBlob);
  Result := Self;
end;

function TLzNexTableBase.Date(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctDate);
  Result := Self;
end;

function TLzNexTableBase.Time(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctTime);
  Result := Self;
end;

function TLzNexTableBase.DateTime(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctDateTime);
  Result := Self;
end;

function TLzNexTableBase.Timestamp(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctTimestamp);
  Result := Self;
end;

function TLzNexTableBase.Json(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctJson);
  Result := Self;
end;

function TLzNexTableBase.Uuid(const AName: string): ILzNexTable;
begin
  PushColumn(AName, ctUuid, 36);
  Result := Self;
end;

function TLzNexTableBase.Enum(const AName: string;
  const AItems: array of string): ILzNexTable;
var
  C: TLzNexColumnDefImpl;
begin
  if Length(AItems) = 0 then
    raise ELzNexSchema.CreateFmt('Enum "%s" has no items.', [AName]);
  C := PushColumn(AName, ctEnum);
  C.SetEnumItems(StringsToValues(AItems));
  Result := Self;
end;

function TLzNexTableBase.Specific(const AName, ATypeSQL: string): ILzNexTable;
var
  C: TLzNexColumnDefImpl;
begin
  if Trim(ATypeSQL) = '' then
    raise ELzNexSchema.CreateFmt('Specific("%s") without the SQL type.', [AName]);
  C := PushColumn(AName, ctSpecific);
  C.SetSpecificType(ATypeSQL);
  Result := Self;
end;

function TLzNexTableBase.Timestamps(const ADefaultNow: Boolean): ILzNexTable;
var
  C: TLzNexColumnDefImpl;
  R: ILzNexRaw;
begin

  C := PushColumn('created_at', ctTimestamp);
  if ADefaultNow then
  begin
    C.RemoveMod(mdNullable);
    R := TLzNexSchemaRaw.Create('CURRENT_TIMESTAMP');
    C.SetDefault(TLzNexValue.Raw(R));
  end;

  C := PushColumn('updated_at', ctTimestamp);
  if ADefaultNow then
  begin
    C.RemoveMod(mdNullable);
    R := TLzNexSchemaRaw.Create('CURRENT_TIMESTAMP');
    C.SetDefault(TLzNexValue.Raw(R));
  end;

  Result := Self;
end;

function TLzNexTableBase.NotNull: ILzNexTable;
begin
  LastColumn('NotNull').RemoveMod(mdNullable);
  Result := Self;
end;

function TLzNexTableBase.Nullable: ILzNexTable;
begin
  Result := Mark(mdNullable, 'Nullable');
end;

function TLzNexTableBase.Unsigned: ILzNexTable;
begin
  Result := Mark(mdUnsigned, 'Unsigned');
end;

function TLzNexTableBase.Default_(const AValue: TLzNexValue): ILzNexTable;
begin
  LastColumn('Default_').SetDefault(AValue);
  Result := Self;
end;

function TLzNexTableBase.DefaultRaw(const ASQL: string): ILzNexTable;
var
  R: ILzNexRaw;
  C: TLzNexColumnDefImpl;
begin
  if Trim(ASQL) = '' then
    raise ELzNexSchema.Create('DefaultRaw without SQL.');

  C := LastColumn('DefaultRaw');
  R := TLzNexSchemaRaw.Create(ASQL);
  C.SetDefault(TLzNexValue.Raw(R));
  Result := Self;
end;

function TLzNexTableBase.Comment(const AText: string): ILzNexTable;
begin
  LastColumn('Comment').SetComment(AText);
  Result := Self;
end;

function TLzNexTableBase.Collate(const AName: string): ILzNexTable;
begin
  LastColumn('Collate').SetCollate(AName);
  Result := Self;
end;

function TLzNexTableBase.After(const AColumn: string): ILzNexTable;
begin
  LastColumn('After').SetAfter(AColumn);
  Result := Self;
end;

function TLzNexTableBase.Primary: ILzNexTable;
var
  P: TLzNexIndexDefImpl;
  Name: string;
begin
  Name := LastColumn('Primary').ColumnName;

  P := FindPrimary;
  if P <> nil then
    P.AddColumn(Name)
  else
    PushIndex(ixPrimary, StringsToValues([Name]), False);
  Result := Self;
end;

function TLzNexTableBase.Unique: ILzNexTable;
var
  Name: string;
begin

  Name := LastColumn('Unique').ColumnName;
  PushIndex(ixUnique, StringsToValues([Name]), False);
  Result := Self;
end;

function TLzNexTableBase.Index: ILzNexTable;
var
  Name: string;
begin
  Name := LastColumn('Index').ColumnName;
  PushIndex(ixIndex, StringsToValues([Name]), False);
  Result := Self;
end;

function TLzNexTableBase.Change: ILzNexTable;
begin
  EnsureAlter('Change');
  LastColumn('Change').MarkChange;
  Result := Self;
end;

function TLzNexTableBase.References(const AColumn: string): ILzNexTable;
var
  FK: TLzNexForeignDef;
  Dot: Integer;
  Local: string;
begin

  Local := LastColumn('References').ColumnName;
  if Trim(AColumn) = '' then
    raise ELzNexSchema.CreateFmt(
      'References on column "%s" without the referenced column.', [Local]);

  FK := TLzNexForeignDef.CreateFk(StringsToValues([Local]));
  SetLength(FIndexes, Length(FIndexes) + 1);
  FIndexes[High(FIndexes)] := FK;
  FLastIndex := FK;
  FLastForeign := FK;

  Dot := Pos('.', AColumn);
  if Dot > 0 then
  begin
    FK.SetRefTable(Copy(AColumn, 1, Dot - 1));
    FK.SetRefColumns(StringsToValues([Copy(AColumn, Dot + 1, Length(AColumn))]));
  end
  else
    FK.SetRefColumns(StringsToValues([AColumn]));

  Result := Self;
end;

function TLzNexTableBase.InTable(const ATable: string): ILzNexTable;
begin
  LastForeign('InTable').SetRefTable(ATable);
  Result := Self;
end;

function TLzNexTableBase.OnDelete(const AAction: string): ILzNexTable;
begin
  LastForeign('OnDelete').SetOnDelete(AAction);
  Result := Self;
end;

function TLzNexTableBase.OnUpdate(const AAction: string): ILzNexTable;
begin
  LastForeign('OnUpdate').SetOnUpdate(AAction);
  Result := Self;
end;

function TLzNexTableBase.ConstraintName(const AName: string): ILzNexTable;
begin
  if FLastIndex = nil then
    raise ELzNexSchema.Create(
      'ConstraintName has no index/FK to name: call References, Unique, ' +
      'Index or Primary first.');
  FLastIndex.SetNameOverride(AName);
  Result := Self;
end;

function TLzNexTableBase.Primary(const AColumns: array of string): ILzNexTable;
begin
  if Length(AColumns) = 0 then
    raise ELzNexSchema.Create('Primary without columns.');
  PushIndex(ixPrimary, StringsToValues(AColumns), False);
  Result := Self;
end;

function TLzNexTableBase.Unique(const AColumns: array of string): ILzNexTable;
begin
  if Length(AColumns) = 0 then
    raise ELzNexSchema.Create('Unique without columns.');
  PushIndex(ixUnique, StringsToValues(AColumns), False);
  Result := Self;
end;

function TLzNexTableBase.Index(const AColumns: array of string): ILzNexTable;
begin
  if Length(AColumns) = 0 then
    raise ELzNexSchema.Create('Index without columns.');
  PushIndex(ixIndex, StringsToValues(AColumns), False);
  Result := Self;
end;

function TLzNexTableBase.DropColumn(const AName: string): ILzNexTable;
var
  C: TLzNexColumnDefImpl;
begin
  EnsureAlter('DropColumn');
  if Trim(AName) = '' then
    raise ELzNexSchema.Create('DropColumn without a name.');
  C := TLzNexColumnDefImpl.Create(AName, ctSpecific);
  C.MarkDrop;
  SetLength(FColumns, Length(FColumns) + 1);
  FColumns[High(FColumns)] := C;

  FLastColumn := nil;
  FLastForeign := nil;
  Result := Self;
end;

function TLzNexTableBase.DropIndex(const AColumns: array of string): ILzNexTable;
begin
  EnsureAlter('DropIndex');
  PushIndex(ixIndex, StringsToValues(AColumns), True);
  Result := Self;
end;

function TLzNexTableBase.DropUnique(const AColumns: array of string): ILzNexTable;
begin
  EnsureAlter('DropUnique');
  PushIndex(ixUnique, StringsToValues(AColumns), True);
  Result := Self;
end;

function TLzNexTableBase.DropForeign(const AColumns: array of string): ILzNexTable;
begin
  EnsureAlter('DropForeign');
  PushIndex(ixForeign, StringsToValues(AColumns), True);
  Result := Self;
end;

function TLzNexTableBase.DropPrimary: ILzNexTable;
begin
  EnsureAlter('DropPrimary');
  PushIndex(ixPrimary, nil, True);
  Result := Self;
end;

function TLzNexTableBase.RenameColumn(const AFrom, ATo: string): ILzNexTable;
begin
  EnsureAlter('RenameColumn');
  if (Trim(AFrom) = '') or (Trim(ATo) = '') then
    raise ELzNexSchema.Create('RenameColumn requires both the old and the new name.');
  SetLength(FRenames, Length(FRenames) + 1);
  FRenames[High(FRenames)].Name := AFrom;
  FRenames[High(FRenames)].Value := TLzNexValue.FromString(ATo);
  FLastColumn := nil;
  FLastForeign := nil;
  Result := Self;
end;

function TLzNexTableBase.Engine(const AName: string): ILzNexTable;
begin
  EnsureCreate('Engine');
  FEngine := AName;
  Result := Self;
end;

function TLzNexTableBase.Charset(const AName: string): ILzNexTable;
begin
  EnsureCreate('Charset');
  FCharset := AName;
  Result := Self;
end;

function TLzNexTableBase.TableCollate(const AName: string): ILzNexTable;
begin
  EnsureCreate('TableCollate');
  FCollate := AName;
  Result := Self;
end;

function TLzNexTableBase.TableComment(const AText: string): ILzNexTable;
begin
  EnsureCreate('TableComment');
  FComment := AText;
  Result := Self;
end;

function TLzNexTableBase.ToSQL: TLzNexDdlPlan;
var
  Comp: ILzNexSchemaCompiler;
begin
  if FClient = nil then
    raise ELzNexSchema.CreateFmt(
      'Table "%s" has no dialect: ToSQL requires an ILzNexClient.', [FTable]);
  Comp := FClient.NewSchemaCompiler;
  if Comp = nil then
    raise ELzNexSchema.CreateFmt(
      'Dialect "%s" has no schema compiler: NewSchemaCompiler returned nil.',
      [FClient.DialectName]);
  Result := Comp.CompileTable(Self);
end;

function TLzNexTableBase.Execute: Integer;
var
  Plan: TLzNexDdlPlan;
  Cmds: TLzNexFragments;
  Conn: ILzNexConnection;
  I: Integer;
begin
  if FDb = nil then
    raise ELzNexSchema.CreateFmt(
      'Execute is unavailable on table "%s": this builder was created in ' +
      'SQL-only mode (ILzNex nil). Use ToSQL to get the DDL plan.', [FTable]);

  Plan := ToSQL;
  Cmds := Plan.All;
  Conn := FDb.Connection;
  for I := 0 to High(Cmds) do
    Conn.Execute(Cmds[I]);
  Result := Length(Cmds);
end;

function TLzNexTableBase.TableName: string;
begin
  Result := FTable;
end;

function TLzNexTableBase.SchemaName: string;
begin
  Result := FSchema;
end;

function TLzNexTableBase.TableMethod: TLzNexTableMethod;
begin
  Result := FMethod;
end;

function TLzNexTableBase.ColumnCount: Integer;
begin
  Result := Length(FColumns);
end;

function TLzNexTableBase.ColumnAt(const AIndex: Integer): ILzNexColumnDef;
begin
  if (AIndex < 0) or (AIndex > High(FColumns)) then
    raise ELzNexSchema.CreateFmt(
      'Column out of range: index %d, total %d.', [AIndex, Length(FColumns)]);
  Result := FColumns[AIndex];
end;

function TLzNexTableBase.IndexCount: Integer;
begin
  Result := Length(FIndexes);
end;

function TLzNexTableBase.IndexAt(const AIndex: Integer): ILzNexIndexDef;
begin
  if (AIndex < 0) or (AIndex > High(FIndexes)) then
    raise ELzNexSchema.CreateFmt(
      'Index out of range: index %d, total %d.', [AIndex, Length(FIndexes)]);
  Result := FIndexes[AIndex];
end;

function TLzNexTableBase.RenamedColumns: TLzNexNamedValues;
begin
  Result := FRenames;
end;

function TLzNexTableBase.EngineName: string;
begin
  Result := FEngine;
end;

function TLzNexTableBase.CharsetName: string;
begin
  Result := FCharset;
end;

function TLzNexTableBase.CollateName: string;
begin
  Result := FCollate;
end;

function TLzNexTableBase.CommentText: string;
begin
  Result := FComment;
end;

function TLzNexTableBase.Client: ILzNexClient;
begin
  Result := FClient;
end;

constructor TLzNexCreateTable.Create(const ADb: ILzNex;
  const AClient: ILzNexClient; const ATable, ASchema: string);
begin
  inherited Create(ADb, AClient, ATable, ASchema, tmCreate);
end;

constructor TLzNexAlterTable.Create(const ADb: ILzNex;
  const AClient: ILzNexClient; const ATable, ASchema: string);
begin
  inherited Create(ADb, AClient, ATable, ASchema, tmAlter);
end;

constructor TLzNexSchema.Create(const ADb: ILzNex; const AClient: ILzNexClient);
begin
  inherited Create;
  FDb := ADb;
  FClient := AClient;
  if (FClient = nil) and (FDb <> nil) then
    FClient := FDb.Client;
  if FClient = nil then
    raise ELzNexSchema.Create(
      'Schema builder without a dialect: pass an ILzNexClient (or an ILzNex ' +
      'that has one).');
end;

function TLzNexSchema.NeedDb(const AMethod: string): ILzNex;
begin
  if FDb = nil then
    raise ELzNexSchema.CreateFmt(
      '%s requires a connection: this schema builder was created in SQL-only ' +
      'mode (ILzNex nil).', [AMethod]);
  Result := FDb;
end;

function TLzNexSchema.Compiler(const AMethod: string): ILzNexSchemaCompiler;
begin
  Result := FClient.NewSchemaCompiler;
  if Result = nil then
    raise ELzNexSchema.CreateFmt(
      '%s is unavailable: dialect "%s" returned nil from NewSchemaCompiler.',
      [AMethod, FClient.DialectName]);
end;

function TLzNexSchema.RunOne(const AMethod: string;
  const AFragment: TLzNexFragment): Int64;
begin
  Result := NeedDb(AMethod).Connection.Execute(AFragment);
end;

function TLzNexSchema.WithSchema(const AName: string): ILzNexSchema;
begin
  FSchema := AName;
  Result := Self;
end;

function TLzNexSchema.CreateTable(const AName: string): ILzNexTable;
begin
  Result := TLzNexCreateTable.Create(FDb, FClient, AName, FSchema);
end;

function TLzNexSchema.Table(const AName: string): ILzNexTable;
begin
  Result := TLzNexAlterTable.Create(FDb, FClient, AName, FSchema);
end;

function TLzNexSchema.HasTable(const AName: string): Boolean;
var
  R: ILzNexResult;
begin
  R := NeedDb('HasTable').Connection.Query(
    Compiler('HasTable').HasTableSQL(AName, FSchema));
  Result := (R <> nil) and R.Next and (R.FieldAt(0).AsInt64 > 0);
end;

function TLzNexSchema.HasColumn(const ATable, AColumn: string): Boolean;
var
  R: ILzNexResult;
begin
  R := NeedDb('HasColumn').Connection.Query(
    Compiler('HasColumn').HasColumnSQL(ATable, AColumn, FSchema));
  Result := (R <> nil) and R.Next and (R.FieldAt(0).AsInt64 > 0);
end;

procedure TLzNexSchema.DropTable(const AName: string);
begin
  RunOne('DropTable', Compiler('DropTable').DropTableSQL(AName, False));
end;

procedure TLzNexSchema.DropTableIfExists(const AName: string);
begin
  RunOne('DropTableIfExists',
    Compiler('DropTableIfExists').DropTableSQL(AName, True));
end;

procedure TLzNexSchema.RenameTable(const AFrom, ATo: string);
begin
  RunOne('RenameTable', Compiler('RenameTable').RenameTableSQL(AFrom, ATo));
end;

procedure TLzNexSchema.Truncate(const AName: string);
begin
  RunOne('Truncate', Compiler('Truncate').TruncateTableSQL(AName));
end;

procedure TLzNexSchema.Raw(const ASQL: string; const AArgs: array of const);
begin
  NeedDb('Raw').Execute(ASQL, AArgs);
end;

function NewSchema(const ADb: ILzNex; const AClient: ILzNexClient): ILzNexSchema;
begin
  Result := TLzNexSchema.Create(ADb, AClient);
end;

end.
