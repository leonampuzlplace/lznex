unit LzNex.Intf;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast;

type
  ILzNexRaw = interface;
  ILzNexQuery = interface;
  ILzNexJoin = interface;
  ILzNexOnConflict = interface;
  ILzNexResult = interface;
  ILzNexRow = interface;
  ILzNexSchema = interface;
  ILzNexTable = interface;
  ILzNexConnection = interface;
  ILzNexPool = interface;
  ILzNexTransaction = interface;
  ILzNexClient = interface;
  ILzNexCompiler = interface;
  ILzNexSchemaCompiler = interface;
  ILzNexConfig = interface;
  ILzNexLogger = interface;
  ILzNexMigration = interface;
  ILzNexMigrationSource = interface;
  ILzNexMigrator = interface;
  ILzNexSeeder = interface;
  ILzNexColumnDef = interface;
  ILzNexIndexDef = interface;
  ILzNex = interface;

  TLzNexStringArray = array of string;
  TLzNexRowArray = array of ILzNexRow;
  TLzNexMigrationArray = array of ILzNexMigration;

  ILzNexRaw = interface
    ['{9A1C0E10-0001-4C2E-9B01-6E5B2A7F0001}']

    function Build(const AClient: ILzNexClient): TLzNexFragment;

    function Template: string;
  end;

  ILzNexRow = interface
    ['{9A1C0E10-0002-4C2E-9B01-6E5B2A7F0002}']

    function Field(const AName: string): TLzNexValue;

    function TryField(const AName: string; out AValue: TLzNexValue): Boolean;

    function FieldAt(const AIndex: Integer): TLzNexValue;

    function Has(const AName: string): Boolean;

    function FieldCount: Integer;

    function FieldName(const AIndex: Integer): string;

    function ToJSON: string;
  end;

  ILzNexResult = interface
    ['{9A1C0E10-0003-4C2E-9B01-6E5B2A7F0003}']

    function Next: Boolean;

    function Field(const AName: string): TLzNexValue;

    function FieldAt(const AIndex: Integer): TLzNexValue;

    function FieldCount: Integer;

    function FieldName(const AIndex: Integer): string;

    function CurrentRow: ILzNexRow;

    function ToRows: TLzNexRowArray;

    function ToJSON: string;

    procedure Close;
  end;

  ILzNexClient = interface
    ['{9A1C0E10-0004-4C2E-9B01-6E5B2A7F0004}']

    function DialectName: string;

    function ZeosProtocol: string;

    function WrapIdentifier(const AName: string): string;

    function WrapQualified(const AName: string): string;

    function Alias(const AExpr, AAlias: string): string;

    function Placeholder(const AIndex: Integer): string;

    function EscapeForLog(const AValue: TLzNexValue): string;

    function SupportsReturning: Boolean;

    function SupportsOnConflictWhere: Boolean;

    function SupportsNullsOrdering: Boolean;

    function SupportsDistinctOn: Boolean;

    function SupportsSavepoints: Boolean;

    function DdlIsTransactional: Boolean;

    function Components(const AMethod: TLzNexQueryMethod): TLzNexComponents;

    function InvalidComponents(const AMethod: TLzNexQueryMethod): TLzNexComponents;

    function NewCompiler: ILzNexCompiler;

    function NewSchemaCompiler: ILzNexSchemaCompiler;
  end;

  ILzNexCompiler = interface
    ['{9A1C0E10-0005-4C2E-9B01-6E5B2A7F0005}']

    function Compile(const AAst: TLzNexAst): TLzNexFragment;

    function CompilePredicates(const AGroup: TLzNexStatementGroup;
      const AItems: TLzNexStatementList): TLzNexFragment;

    function Client: ILzNexClient;
  end;

  TLzNexDdlPlan = record

    Pre: TLzNexFragments;

    Statements: TLzNexFragments;

    Post: TLzNexFragments;

    function All: TLzNexFragments;

    function Count: Integer;
  end;

  ILzNexSchemaCompiler = interface
    ['{9A1C0E10-0006-4C2E-9B01-6E5B2A7F0006}']

    function CompileTable(const ATable: ILzNexTable): TLzNexDdlPlan;

    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;

    function ModifierOrder: TLzNexColumnModifiers;

    function DropTableSQL(const ATable: string; const AIfExists: Boolean): TLzNexFragment;
    function RenameTableSQL(const AFrom, ATo: string): TLzNexFragment;
    function TruncateTableSQL(const ATable: string): TLzNexFragment;

    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment;

    function IndexName(const ATable: string; const AColumns: TLzNexValues;
      const AKind: TLzNexIndexKind): string;
  end;

  ILzNexQuery = interface
    ['{9A1C0E10-0007-4C2E-9B01-6E5B2A7F0007}']

    function Table(const AName: string): ILzNexQuery;

    function From(const AName: string): ILzNexQuery;

    function FromAs(const AName, AAlias: string): ILzNexQuery;

    function FromSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;

    function FromRaw(const ARaw: ILzNexRaw): ILzNexQuery;

    function WithSchema(const ASchema: string): ILzNexQuery;

    function AsAlias(const AAlias: string): ILzNexQuery;

    function Select(const AColumns: array of string): ILzNexQuery;

    function Column(const AColumn: string): ILzNexQuery;

    function SelectAs(const AColumn, AAlias: string): ILzNexQuery;

    function SelectRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function SelectSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;

    function Distinct: ILzNexQuery;

    function DistinctOn(const AColumns: array of string): ILzNexQuery;

    function Where(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function Where(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function WhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function WhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhere(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhere(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;

    function WhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;
    function OrWhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;

    function WhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function WhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function OrWhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function OrWhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;

    function WhereInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;
    function WhereNotInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;

    function WhereNull(const AColumn: string): ILzNexQuery;
    function WhereNotNull(const AColumn: string): ILzNexQuery;
    function OrWhereNull(const AColumn: string): ILzNexQuery;
    function OrWhereNotNull(const AColumn: string): ILzNexQuery;

    function WhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function WhereNotBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function OrWhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;

    function WhereLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
    function WhereNotLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
    function WhereILike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;

    function WhereExists(const ASub: ILzNexQuery): ILzNexQuery;
    function WhereNotExists(const ASub: ILzNexQuery): ILzNexQuery;

    function WhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function OrWhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function WhereOpen: ILzNexQuery;

    function OrWhereOpen: ILzNexQuery;

    function WhereNotOpen: ILzNexQuery;

    function WhereClose: ILzNexQuery;

    function Join(const ATable: string): ILzNexJoin;
    function JoinAs(const ATable, AAlias: string): ILzNexJoin;
    function InnerJoin(const ATable: string): ILzNexJoin;
    function LeftJoin(const ATable: string): ILzNexJoin;
    function LeftOuterJoin(const ATable: string): ILzNexJoin;
    function RightJoin(const ATable: string): ILzNexJoin;
    function RightOuterJoin(const ATable: string): ILzNexJoin;
    function FullOuterJoin(const ATable: string): ILzNexJoin;
    function CrossJoin(const ATable: string): ILzNexJoin;
    function JoinSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexJoin;
    function JoinRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function GroupBy(const AColumns: array of string): ILzNexQuery;
    function GroupByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function Having(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
    function OrHaving(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
    function HavingIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function HavingNull(const AColumn: string): ILzNexQuery;
    function HavingNotNull(const AColumn: string): ILzNexQuery;
    function HavingBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function HavingRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function HavingOpen: ILzNexQuery;
    function HavingClose: ILzNexQuery;

    function OrderBy(const AColumn: string): ILzNexQuery; overload;
    function OrderBy(const AColumn: string; const ADir: TLzNexOrderDir): ILzNexQuery; overload;
    function OrderBy(const AColumn: string; const ADir: TLzNexOrderDir;
      const ANulls: TLzNexNullsOrder): ILzNexQuery; overload;
    function OrderByDesc(const AColumn: string): ILzNexQuery;
    function OrderByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function Limit(const ACount: Int64): ILzNexQuery;
    function Offset(const ACount: Int64): ILzNexQuery;

    function Page(const APage, APerPage: Int64): ILzNexQuery;
    function ForUpdate: ILzNexQuery;
    function ForShare: ILzNexQuery;
    function SkipLocked: ILzNexQuery;
    function NoWait: ILzNexQuery;

    function Union(const ASub: ILzNexQuery): ILzNexQuery;
    function UnionAll(const ASub: ILzNexQuery): ILzNexQuery;
    function Intersect(const ASub: ILzNexQuery): ILzNexQuery;
    function Except_(const ASub: ILzNexQuery): ILzNexQuery;
    function With_(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
    function WithRecursive(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
    function HintComment(const AHint: string): ILzNexQuery;

    function OnConflict(const AColumns: array of string): ILzNexOnConflict;

    function Returning(const AColumns: array of string): ILzNexQuery;

    function Clear(const AGroup: TLzNexStatementGroup): ILzNexQuery;

    function Clone: ILzNexQuery;

    function Transacting(const ATrx: ILzNexTransaction): ILzNexQuery;

    function ToSQL: TLzNexFragment;

    function ToSQLString: string;

    function Get: ILzNexResult;

    function First: ILzNexRow;

    function Value(const AColumn: string): TLzNexValue;

    function Scalar: TLzNexValue;

    function Pluck(const AColumn: string): TLzNexValues;

    function Exists: Boolean;

    function Count: Int64;

    function Aggregate(const AAgg: TLzNexAggregate; const AColumn: string): TLzNexValue;

    function Insert(const AValues: TLzNexNamedValues): Int64;

    function InsertGetId(const AValues: TLzNexNamedValues): Int64;

    function InsertMany(const ARows: array of TLzNexNamedValues): Int64;

    function Update(const AValues: TLzNexNamedValues): Int64;

    function Increment(const AColumn: string; const ABy: Int64 = 1): Int64;
    function Decrement(const AColumn: string; const ABy: Int64 = 1): Int64;

    function Delete: Int64;

    procedure Truncate;

    function Ast: TLzNexAst;

    function Client: ILzNexClient;

    function OpenGroupCount: Integer;
  end;

  ILzNexJoin = interface(ILzNexQuery)
    ['{9A1C0E10-0008-4C2E-9B01-6E5B2A7F0008}']

    function OnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;

    function OnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function AndOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function OrOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function AndOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function OrOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function OnIn(const AColumn: string; const AValues: TLzNexValues): ILzNexJoin;
    function OnNull(const AColumn: string): ILzNexJoin;
    function OnNotNull(const AColumn: string): ILzNexJoin;
    function OnBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexJoin;
    function OnRaw(const ASQL: string; const AArgs: array of const): ILzNexJoin;

    function Using(const AColumns: array of string): ILzNexJoin;
  end;

  ILzNexOnConflict = interface
    ['{9A1C0E10-0009-4C2E-9B01-6E5B2A7F0009}']

    function Ignore: ILzNexQuery;

    function Merge: ILzNexQuery; overload;

    function Merge(const AColumns: array of string): ILzNexQuery; overload;

    function MergeValues(const AValues: TLzNexNamedValues): ILzNexQuery;
  end;

  ILzNexColumnDef = interface
    ['{9A1C0E10-000A-4C2E-9B01-6E5B2A7F000A}']
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
  end;

  ILzNexIndexDef = interface
    ['{9A1C0E10-000B-4C2E-9B01-6E5B2A7F000B}']
    function IndexKind: TLzNexIndexKind;
    function Columns: TLzNexValues;
    function IndexNameOverride: string;
    function RefTable: string;
    function RefColumns: TLzNexValues;
    function OnDeleteAction: string;
    function OnUpdateAction: string;
    function IsDrop: Boolean;
  end;

  ILzNexTable = interface
    ['{9A1C0E10-000C-4C2E-9B01-6E5B2A7F000C}']

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

  ILzNexSchema = interface
    ['{9A1C0E10-000D-4C2E-9B01-6E5B2A7F000D}']

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

  ILzNexConnection = interface
    ['{9A1C0E10-000E-4C2E-9B01-6E5B2A7F000E}']

    function Execute(const AFragment: TLzNexFragment): Int64;

    function Query(const AFragment: TLzNexFragment): ILzNexResult;

    function ExecuteScript(const ASQL: string): Int64;

    function LastInsertId: Int64;

    function StartTransaction: Integer;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function TransactionLevel: Integer;

    function Ping: Boolean;
    function IsClosed: Boolean;
    procedure Close;

    function Native: IInterface;

    function Client: ILzNexClient;
  end;

  ILzNexPool = interface
    ['{9A1C0E10-000F-4C2E-9B01-6E5B2A7F000F}']

    function Acquire: ILzNexConnection;

    function Size: Integer;
    function InUse: Integer;
    procedure Shutdown;
  end;

  ILzNexConfig = interface
    ['{9A1C0E10-0011-4C2E-9B01-6E5B2A7F0011}']
    function Client(const AName: string): ILzNexConfig;
    function Host(const AValue: string): ILzNexConfig;
    function Port(const AValue: Integer): ILzNexConfig;
    function Database(const AValue: string): ILzNexConfig;
    function User(const AValue: string): ILzNexConfig;
    function Password(const AValue: string): ILzNexConfig;

    function LibraryLocation(const AValue: string): ILzNexConfig;
    function Charset(const AValue: string): ILzNexConfig;
    function Pool(const AMin, AMax: Integer): ILzNexConfig;
    function AcquireTimeout(const AMilliseconds: Integer): ILzNexConfig;
    function MigrationsTable(const AValue: string): ILzNexConfig;
    function MigrationsDir(const AValue: string): ILzNexConfig;
    function SeedsDir(const AValue: string): ILzNexConfig;
    function Prop(const AName, AValue: string): ILzNexConfig;
    function Logger(const AValue: ILzNexLogger): ILzNexConfig;

    function GetClient: string;
    function GetHost: string;
    function GetPort: Integer;
    function GetDatabase: string;
    function GetUser: string;
    function GetPassword: string;
    function GetLibraryLocation: string;
    function GetCharset: string;
    function GetPoolMin: Integer;
    function GetPoolMax: Integer;
    function GetAcquireTimeout: Integer;
    function GetMigrationsTable: string;
    function GetMigrationsDir: string;
    function GetSeedsDir: string;
    function GetProps: TLzNexNamedValues;
    function GetLogger: ILzNexLogger;

    procedure Validate;
  end;

  ILzNexLogger = interface
    ['{9A1C0E10-0012-4C2E-9B01-6E5B2A7F0012}']
    procedure LogQuery(const ASQL: string; const ABindings: TLzNexBindings;
      const AElapsedMs: Int64);
    procedure LogError(const ASQL: string; const AError: string);
    procedure LogWarning(const AMessage: string);
    procedure LogInfo(const AMessage: string);
  end;

  ILzNexMigration = interface
    ['{9A1C0E10-0013-4C2E-9B01-6E5B2A7F0013}']

    function Id: string;

    function Name: string;

    function UseTransaction: Boolean;

    procedure Up(const ADb: ILzNex);
    procedure Down(const ADb: ILzNex);
  end;

  ILzNexMigrationSource = interface
    ['{9A1C0E10-0014-4C2E-9B01-6E5B2A7F0014}']

    function All: TLzNexMigrationArray;

    function SourceName: string;
  end;

  TLzNexMigrationStatus = record
    Name: string;
    Source: string;
    Applied: Boolean;
    Batch: Integer;
    AppliedAt: TDateTime;
  end;
  TLzNexMigrationStatusList = array of TLzNexMigrationStatus;

  ILzNexMigrator = interface
    ['{9A1C0E10-0015-4C2E-9B01-6E5B2A7F0015}']

    function AddSource(const ASource: ILzNexMigrationSource): ILzNexMigrator;

    function Latest: Integer;

    function Rollback: Integer;

    function RollbackAll: Integer;

    function Up(const AName: string = ''): Integer;

    function Down(const AName: string = ''): Integer;

    function MigrateTo(const AName: string): Integer;

    function Status: TLzNexMigrationStatusList;

    function Pending: TLzNexMigrationArray;

    function CurrentVersion: string;

    procedure Unlock;

    procedure EnsureTables;
  end;

  ILzNexSeeder = interface
    ['{9A1C0E10-0016-4C2E-9B01-6E5B2A7F0016}']
    function Run: Integer;
    function RunOne(const AName: string): Integer;
    function Names: TLzNexStringArray;
  end;

  ILzNex = interface
    ['{9A1C0E10-0017-4C2E-9B01-6E5B2A7F0017}']

    function Table(const AName: string): ILzNexQuery;
    function From(const AName: string): ILzNexQuery;

    function Query: ILzNexQuery;

    function Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;

    function Schema: ILzNexSchema;

    function Transaction: ILzNexTransaction; overload;
    function Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction; overload;

    function Migrator: ILzNexMigrator;
    function Seeder: ILzNexSeeder;

    function Execute(const ASQL: string; const AArgs: array of const): Int64;
    function Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;

    function Client: ILzNexClient;
    function Config: ILzNexConfig;
    function Pool: ILzNexPool;

    function Connection: ILzNexConnection;

    function IsTransaction: Boolean;
    procedure Shutdown;
  end;

  ILzNexTransaction = interface(ILzNex)
    ['{9A1C0E10-0010-4C2E-9B01-6E5B2A7F0010}']
    procedure Commit;
    procedure Rollback;

    function Savepoint: ILzNexTransaction;

    function IsCompleted: Boolean;

    function Level: Integer;

  end;

implementation

function TLzNexDdlPlan.All: TLzNexFragments;
var
  I, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Pre) + Length(Statements) + Length(Post));
  N := 0;
  for I := 0 to High(Pre) do
  begin
    Result[N] := Pre[I];
    Inc(N);
  end;
  for I := 0 to High(Statements) do
  begin
    Result[N] := Statements[I];
    Inc(N);
  end;
  for I := 0 to High(Post) do
  begin
    Result[N] := Post[I];
    Inc(N);
  end;
end;

function TLzNexDdlPlan.Count: Integer;
begin
  Result := Length(Pre) + Length(Statements) + Length(Post);
end;

end.
