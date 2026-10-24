unit LzNex.Migration.Source.Code;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Exceptions,
  LzNex.Intf,
  LzNex.Migration;

type
  TLzNexCodeMigrationSource = class(TInterfacedObject, ILzNexMigrationSource)
  public
    class function New: ILzNexMigrationSource;
    function All: TLzNexMigrationArray;
    function SourceName: string;
  end;

const
  LZNEX_SOURCE_CODE = 'code';

implementation

class function TLzNexCodeMigrationSource.New: ILzNexMigrationSource;
begin
  Result := TLzNexCodeMigrationSource.Create;
end;

function TLzNexCodeMigrationSource.All: TLzNexMigrationArray;
var
  Classes: TLzNexMigrationClassArray;
  I: Integer;
begin

  Classes := RegisteredMigrations;
  Result := nil;
  SetLength(Result, Length(Classes));
  for I := 0 to High(Classes) do
    Result[I] := CreateMigration(Classes[I]);
end;

function TLzNexCodeMigrationSource.SourceName: string;
begin
  Result := LZNEX_SOURCE_CODE;
end;

end.
