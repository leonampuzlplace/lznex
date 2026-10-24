unit LzNex.Migration;

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

  TLzNexMigration = class(TInterfacedObject, ILzNexMigration)
  protected
    function GetMigrationId: string;
    function GetMigrationNameStr: string;
    function ILzNexMigration.Id = GetMigrationId;
    function ILzNexMigration.Name = GetMigrationNameStr;
  public

    class function Id: string; virtual;

    class function MigrationName: string; virtual;

    function UseTransaction: Boolean; virtual;
    procedure Up(const ADb: ILzNex); virtual; abstract;
    procedure Down(const ADb: ILzNex); virtual; abstract;
  end;

procedure RegisterMigration(const AClass: TLzNexMigrationClass);

function RegisteredMigrationCount: Integer;

function RegisteredMigrationAt(const AIndex: Integer): TLzNexMigrationClass;

function RegisteredMigrations: TLzNexMigrationClassArray;

function FindMigrationClass(const AName: string): TLzNexMigrationClass;

procedure ClearMigrations;

function CreateMigration(const AClass: TLzNexMigrationClass): ILzNexMigration;

function MigrationIdOf(const AName: string): string;

implementation

var

  GMigrations: TLzNexMigrationClassArray = nil;
  GCount: Integer = 0;

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
