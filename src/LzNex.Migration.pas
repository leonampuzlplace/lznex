unit LzNex.Migration;

{ Base das migrations escritas em Pascal e o registry global de metaclasses.

  O registry guarda METACLASSE, nao instancia: a migration so e instanciada
  quando o runner vai de fato aplica-la, e o custo de ter 300 migrations no
  projeto e 300 ponteiros.

  ARMADILHA ESTRUTURAL DO PASCAL -- leia antes de criar migration:
  o linker descarta unit que ninguem referencia em `uses`. Unit descartada nao
  tem seu `initialization` executado, logo a migration NAO se registra e
  simplesmente nao existe para o runner, sem erro nenhum. Por isso cada
  migration precisa aparecer no `uses` de uma unit agregadora (ou do programa);
  e o gerador do CLI que insere essa linha. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Exceptions,
  LzNex.Intf;

type
  TLzNexMigration = class;
  TLzNexMigrationClass = class of TLzNexMigration;
  TLzNexMigrationClassArray = array of TLzNexMigrationClass;

  { Id e MigrationName sao de CLASSE para o registry conseguir ordenar e
    detectar duplicata sem instanciar nada. A interface ILzNexMigration pede
    metodos de instancia, entao as duas vias convivem pelas clausulas de
    resolucao abaixo. }
  TLzNexMigration = class(TInterfacedObject, ILzNexMigration)
  protected
    function GetMigrationId: string;
    function GetMigrationNameStr: string;
    function ILzNexMigration.Id = GetMigrationId;
    function ILzNexMigration.Name = GetMigrationNameStr;
  public
    // Timestamp 'YYYYMMDDHHMMSS'. Default: o prefixo de MigrationName.
    class function Id: string; virtual;
    // Nome completo '<id>_<descricao>'. Toda subclasse sobrescreve.
    class function MigrationName: string; virtual;

    function UseTransaction: Boolean; virtual;
    procedure Up(const ADb: ILzNex); virtual; abstract;
    procedure Down(const ADb: ILzNex); virtual; abstract;
  end;

// Acrescenta a classe ao registry, mantendo a ordem por Id. Chamar no
// `initialization` da unit da migration.
procedure RegisterMigration(const AClass: TLzNexMigrationClass);

// Quantas estao registradas.
function RegisteredMigrationCount: Integer;

// A classe na posicao, na ordem de Id (0-based).
function RegisteredMigrationAt(const AIndex: Integer): TLzNexMigrationClass;

// Copia do registry inteiro, ordenado por Id.
function RegisteredMigrations: TLzNexMigrationClassArray;

// A classe de um nome completo, ou nil.
function FindMigrationClass(const AName: string): TLzNexMigrationClass;

// Esvazia o registry. Existe para teste; em producao ninguem chama.
procedure ClearMigrations;

// Instancia e devolve como interface.
function CreateMigration(const AClass: TLzNexMigrationClass): ILzNexMigration;

// O prefixo de id de '20240101120000_create_users' -> '20240101120000'.
// Sem '_' o nome inteiro e o id.
function MigrationIdOf(const AName: string): string;

implementation

var
  // Ordenado por Id em todo momento: insercao ordenada custa O(n) por
  // migration registrada e dispensa comparador de generic (restricao do FPC).
  GMigrations: TLzNexMigrationClassArray = nil;
  GCount: Integer = 0;

{ TLzNexMigration }

class function TLzNexMigration.Id: string;
begin
  Result := MigrationIdOf(MigrationName);
end;

class function TLzNexMigration.MigrationName: string;
begin
  Result := '';
  raise ELzNexMigration.Create(
    'Migration ' + ClassName + ' did not override MigrationName. ' +
    'Return the full name in the format ''<YYYYMMDDHHMMSS>_<description>''.');
end;

function TLzNexMigration.GetMigrationId: string;
begin
  Result := TLzNexMigrationClass(ClassType).Id;
end;

function TLzNexMigration.GetMigrationNameStr: string;
begin
  Result := TLzNexMigrationClass(ClassType).MigrationName;
end;

function TLzNexMigration.UseTransaction: Boolean;
begin
  Result := True;
end;

{ Registry }

function MigrationIdOf(const AName: string): string;
var
  P: Integer;
begin
  P := Pos('_', AName);
  if P <= 1 then
    Result := AName
  else
    Result := Copy(AName, 1, P - 1);
end;

function RegisteredMigrationCount: Integer;
begin
  Result := GCount;
end;

function RegisteredMigrationAt(const AIndex: Integer): TLzNexMigrationClass;
begin
  if (AIndex < 0) or (AIndex >= GCount) then
    raise ELzNexMigration.CreateFmt(
      'Migration index out of range: %d (registered: %d).',
      [AIndex, GCount]);
  Result := GMigrations[AIndex];
end;

function RegisteredMigrations: TLzNexMigrationClassArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, GCount);
  for I := 0 to GCount - 1 do
    Result[I] := GMigrations[I];
end;

function FindMigrationClass(const AName: string): TLzNexMigrationClass;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to GCount - 1 do
    if GMigrations[I].MigrationName = AName then
      Exit(GMigrations[I]);
end;

procedure ClearMigrations;
begin
  GMigrations := nil;
  GCount := 0;
end;

procedure RegisterMigration(const AClass: TLzNexMigrationClass);
var
  NewId, NewName: string;
  I, Slot: Integer;
begin
  if AClass = nil then
    raise ELzNexMigration.Create('RegisterMigration received nil.');

  NewId := AClass.Id;
  NewName := AClass.MigrationName;

  if Trim(NewId) = '' then
    raise ELzNexMigration.Create(
      'Migration ' + AClass.ClassName + ' has an empty Id.');

  for I := 0 to GCount - 1 do
    if GMigrations[I].Id = NewId then
      raise ELzNexMigration.Create(
        'Duplicate migration id: "' + NewId + '".' + sLineBreak +
        '  already registered: ' + GMigrations[I].MigrationName +
        ' (' + GMigrations[I].ClassName + ')' + sLineBreak +
        '  trying to register: ' + NewName + ' (' + AClass.ClassName + ')' +
        sLineBreak +
        'The Id defines the order of application, so two equal ones have no ' +
        'order.');

  if GCount >= Length(GMigrations) then
  begin
    if Length(GMigrations) = 0 then
      SetLength(GMigrations, 16)
    else
      SetLength(GMigrations, Length(GMigrations) * 2);
  end;

  { Insercao ordenada: acha o lugar e empurra o resto. }
  Slot := GCount;
  for I := 0 to GCount - 1 do
    if GMigrations[I].Id > NewId then
    begin
      Slot := I;
      Break;
    end;
  for I := GCount downto Slot + 1 do
    GMigrations[I] := GMigrations[I - 1];
  GMigrations[Slot] := AClass;
  Inc(GCount);
end;

function CreateMigration(const AClass: TLzNexMigrationClass): ILzNexMigration;
begin
  if AClass = nil then
    raise ELzNexMigration.Create('CreateMigration received nil.');
  Result := AClass.Create as ILzNexMigration;
end;

end.
