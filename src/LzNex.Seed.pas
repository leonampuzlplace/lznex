unit LzNex.Seed;

{ Seeds: dados de desenvolvimento e de teste.

  Diferenca deliberada em relacao a migration (mesma escolha do knex): seed nao
  tem batch, nao tem lock, nao tem transacao e nao tem tabela de controle. Seed
  roda quantas vezes se quiser e a propria seed cuida de ser idempotente
  (delete antes de insert, ou upsert). Isso e o que permite "zera e popula" no
  comeco de cada suite de teste.

  A ordem e ALFABETICA por nome, nao por timestamp: seed nao tem historico, so
  dependencia entre si -- '01_users', '02_posts'.

  Vale a mesma armadilha de link das migrations: unit que ninguem referencia em
  `uses` nao e linkada, seu `initialization` nao roda e a seed nao se registra. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Exceptions,
  LzNex.Intf;

type
  TLzNexSeed = class;
  TLzNexSeedClass = class of TLzNexSeed;
  TLzNexSeedClassArray = array of TLzNexSeedClass;

  { Nao e TInterfacedObject: nao existe ILzNexSeed no contrato, a seed e so um
    bloco de codigo com nome. O seeder instancia, roda e libera. }
  TLzNexSeed = class(TObject)
  public
    // O nome que define a ordem e aparece no log. Toda subclasse sobrescreve.
    class function SeedName: string; virtual;
    procedure Run(const ADb: ILzNex); virtual; abstract;
  end;

  TLzNexSeeder = class(TInterfacedObject, ILzNexSeeder)
  private
    { Referencia FORTE, e seguro: a facade cria um seeder novo a cada acesso a
      Db.Seeder e NAO guarda a instancia, entao nao ha ciclo de refcount. }
    FDb: ILzNex;
    function Db: ILzNex;
    function Log: ILzNexLogger;
    procedure Execute(const AClass: TLzNexSeedClass);
  public
    constructor Create(const ADb: ILzNex);
    class function New(const ADb: ILzNex): ILzNexSeeder;

    function Run: Integer;
    function RunOne(const AName: string): Integer;
    function Names: TLzNexStringArray;
  end;

// Acrescenta a seed ao registry, mantendo a ordem alfabetica. Chamar no
// `initialization` da unit da seed.
procedure RegisterSeed(const AClass: TLzNexSeedClass);

// Quantas estao registradas.
function RegisteredSeedCount: Integer;

// Copia do registry, em ordem alfabetica.
function RegisteredSeeds: TLzNexSeedClassArray;

// A classe de um nome, ou nil.
function FindSeedClass(const AName: string): TLzNexSeedClass;

// Esvazia o registry. Existe para teste.
procedure ClearSeeds;

// O seeder pronto para uso. Construtor barato: nada vai ao banco aqui.
function NewSeeder(const ADb: ILzNex): ILzNexSeeder;

implementation

var
  GSeeds: TLzNexSeedClassArray = nil;
  GCount: Integer = 0;

{ TLzNexSeed }

class function TLzNexSeed.SeedName: string;
begin
  Result := '';
  raise ELzNex.Create(
    'Seed ' + ClassName + ' did not override SeedName.');
end;

{ Registry }

function RegisteredSeedCount: Integer;
begin
  Result := GCount;
end;

function RegisteredSeeds: TLzNexSeedClassArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, GCount);
  for I := 0 to GCount - 1 do
    Result[I] := GSeeds[I];
end;

function FindSeedClass(const AName: string): TLzNexSeedClass;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to GCount - 1 do
    if SameText(GSeeds[I].SeedName, AName) then
      Exit(GSeeds[I]);
end;

procedure ClearSeeds;
begin
  GSeeds := nil;
  GCount := 0;
end;

procedure RegisterSeed(const AClass: TLzNexSeedClass);
var
  NewName: string;
  I, Slot: Integer;
begin
  if AClass = nil then
    raise ELzNex.Create('RegisterSeed received nil.');

  NewName := AClass.SeedName;
  if Trim(NewName) = '' then
    raise ELzNex.Create('Seed ' + AClass.ClassName + ' has an empty SeedName.');

  for I := 0 to GCount - 1 do
    if SameText(GSeeds[I].SeedName, NewName) then
      raise ELzNex.Create(
        'Duplicate seed name: "' + NewName + '" (' +
        GSeeds[I].ClassName + ' and ' + AClass.ClassName + '). ' +
        'The name defines the order of execution.');

  if GCount >= Length(GSeeds) then
  begin
    if Length(GSeeds) = 0 then
      SetLength(GSeeds, 16)
    else
      SetLength(GSeeds, Length(GSeeds) * 2);
  end;

  { Insercao ordenada: o registry ja sai alfabetico. }
  Slot := GCount;
  for I := 0 to GCount - 1 do
    if CompareText(GSeeds[I].SeedName, NewName) > 0 then
    begin
      Slot := I;
      Break;
    end;
  for I := GCount downto Slot + 1 do
    GSeeds[I] := GSeeds[I - 1];
  GSeeds[Slot] := AClass;
  Inc(GCount);
end;

{ TLzNexSeeder }

constructor TLzNexSeeder.Create(const ADb: ILzNex);
begin
  inherited Create;
  if ADb = nil then
    raise ELzNex.Create('Seeder created without a facade.');
  FDb := ADb;
end;

class function TLzNexSeeder.New(const ADb: ILzNex): ILzNexSeeder;
begin
  Result := TLzNexSeeder.Create(ADb);
end;

function TLzNexSeeder.Db: ILzNex;
begin
  Result := FDb;
end;

function TLzNexSeeder.Log: ILzNexLogger;
var
  Cfg: ILzNexConfig;
begin
  Result := nil;
  Cfg := Db.Config;
  if Cfg <> nil then
    Result := Cfg.GetLogger;
end;

procedure TLzNexSeeder.Execute(const AClass: TLzNexSeedClass);
var
  Seed: TLzNexSeed;
  L: ILzNexLogger;
begin
  L := Log;
  if L <> nil then
    L.LogInfo('seed ' + AClass.SeedName);

  Seed := AClass.Create;
  try
    try
      Seed.Run(Db);
    except
      on E: Exception do
        { Preserva a mensagem original: sem ela o usuario so saberia que
          "uma seed" falhou. }
        raise ELzNex.Create(
          'Seed "' + AClass.SeedName + '" (' + AClass.ClassName +
          ') failed: ' + E.Message);
    end;
  finally
    Seed.Free;
  end;
end;

function TLzNexSeeder.Run: Integer;
var
  Items: TLzNexSeedClassArray;
  I: Integer;
begin
  Items := RegisteredSeeds;
  for I := 0 to High(Items) do
    Execute(Items[I]);
  Result := Length(Items);
end;

function TLzNexSeeder.RunOne(const AName: string): Integer;
var
  Cls: TLzNexSeedClass;
  Known: string;
  I: Integer;
begin
  Cls := FindSeedClass(AName);
  if Cls = nil then
  begin
    Known := '';
    for I := 0 to GCount - 1 do
    begin
      if Known <> '' then
        Known := Known + ', ';
      Known := Known + GSeeds[I].SeedName;
    end;
    if Known = '' then
      Known := '(none -- is the seed unit in the aggregator uses clause?)';
    raise ELzNex.Create(
      'Seed "' + AName + '" is not registered. Registered: ' + Known + '.');
  end;
  Execute(Cls);
  Result := 1;
end;

function TLzNexSeeder.Names: TLzNexStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, GCount);
  for I := 0 to GCount - 1 do
    Result[I] := GSeeds[I].SeedName;
end;

function NewSeeder(const ADb: ILzNex): ILzNexSeeder;
begin
  Result := TLzNexSeeder.New(ADb);
end;

end.
