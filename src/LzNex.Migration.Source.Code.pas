unit LzNex.Migration.Source.Code;

{ Fonte de migrations escritas em Pascal: so expoe o registry global de
  LzNex.Migration como ILzNexMigrationSource.

  Instancia na hora de listar, nao na hora de registrar -- o runner costuma
  pedir All() uma vez por comando, e assim nada fica vivo entre comandos. }

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
  { O registry ja se mantem ordenado por Id, entao nao ha o que reordenar. }
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
