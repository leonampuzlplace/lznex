unit LzNex;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Client,
  LzNex.Config,
  LzNex.Raw,
  LzNex.Query,
  LzNex.Pool,
  LzNex.Transaction,
  LzNex.Schema,
  LzNex.Migrator,
  LzNex.Seed;

type

  TLzNexValue = LzNex.Value.TLzNexValue;
  TLzNexValues = LzNex.Value.TLzNexValues;
  TLzNexNamedValue = LzNex.Value.TLzNexNamedValue;
  TLzNexNamedValues = LzNex.Value.TLzNexNamedValues;

  ILzNex = LzNex.Intf.ILzNex;
  ILzNexQuery = LzNex.Intf.ILzNexQuery;
  ILzNexJoin = LzNex.Intf.ILzNexJoin;
  ILzNexResult = LzNex.Intf.ILzNexResult;
  ILzNexRow = LzNex.Intf.ILzNexRow;
  ILzNexSchema = LzNex.Intf.ILzNexSchema;
  ILzNexTable = LzNex.Intf.ILzNexTable;
  ILzNexTransaction = LzNex.Intf.ILzNexTransaction;
  ILzNexConfig = LzNex.Intf.ILzNexConfig;
  ILzNexMigrator = LzNex.Intf.ILzNexMigrator;

  TLzNexDb = class(TInterfacedObject, ILzNex)
  private
    FConfig: ILzNexConfig;
    FClient: ILzNexClient;
    FPool: ILzNexPool;
  public
    constructor Create(const AConfig: ILzNexConfig);
    destructor Destroy; override;

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

function Connect(const AConfig: ILzNexConfig): ILzNex;

function NewConfig: ILzNexConfig;

function ConnectFromFile(const APath, AEnv: string): ILzNex;

implementation

constructor TLzNexDb.Create(const AConfig: ILzNexConfig);
begin
  inherited Create;
  if AConfig = nil then
    raise ELzNexConfig.Create('Connect: no configuration given');

  FConfig := AConfig;
  FConfig.Validate;
  FClient := CreateClient(FConfig.GetClient);
  FPool := NewPool(FConfig, FClient);
end;

destructor TLzNexDb.Destroy;
begin
  if FPool <> nil then
    FPool.Shutdown;
  FPool := nil;
  inherited Destroy;
end;

function TLzNexDb.Table(const AName: string): ILzNexQuery;
begin
  Result := NewBoundQuery(Self, nil).Table(AName);
end;

function TLzNexDb.From(const AName: string): ILzNexQuery;
begin
  Result := Table(AName);
end;

function TLzNexDb.Query: ILzNexQuery;
begin
  Result := NewBoundQuery(Self, nil);
end;

function TLzNexDb.Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
begin
  Result := LzNexRaw(ASQL, AArgs);
end;

function TLzNexDb.Schema: ILzNexSchema;
begin

  Result := NewSchema(Self, FClient);
end;

function TLzNexDb.Transaction: ILzNexTransaction;
begin
  Result := Transaction(ilDefault);
end;

function TLzNexDb.Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction;
begin

  Result := NewTransaction(Self, FPool.Acquire, AIsolation);
end;

function TLzNexDb.Migrator: ILzNexMigrator;
begin
  Result := NewMigrator(Self);
end;

function TLzNexDb.Seeder: ILzNexSeeder;
begin
  Result := NewSeeder(Self);
end;

function TLzNexDb.Execute(const ASQL: string; const AArgs: array of const): Int64;
begin
  Result := Connection.Execute(LzNexRaw(ASQL, AArgs).Build(FClient));
end;

function TLzNexDb.Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
begin
  Result := Connection.Query(LzNexRaw(ASQL, AArgs).Build(FClient));
end;

function TLzNexDb.Client: ILzNexClient;
begin
  Result := FClient;
end;

function TLzNexDb.Config: ILzNexConfig;
begin
  Result := FConfig;
end;

function TLzNexDb.Pool: ILzNexPool;
begin
  Result := FPool;
end;

function TLzNexDb.Connection: ILzNexConnection;
begin

  Result := FPool.Acquire;
end;

function TLzNexDb.IsTransaction: Boolean;
begin
  Result := False;
end;

procedure TLzNexDb.Shutdown;
begin
  if FPool <> nil then
    FPool.Shutdown;
end;

function Connect(const AConfig: ILzNexConfig): ILzNex;
begin
  Result := TLzNexDb.Create(AConfig) as ILzNex;
end;

function NewConfig: ILzNexConfig;
begin
  Result := TLzNexConfig.New;
end;

function ConnectFromFile(const APath, AEnv: string): ILzNex;
begin
  Result := Connect(LoadConfigFile(APath, AEnv));
end;

end.
