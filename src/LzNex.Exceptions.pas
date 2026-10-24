unit LzNex.Exceptions;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils;

type

  ELzNex = class(Exception);

  ELzNexConfig = class(ELzNex);

  ELzNexConnection = class(ELzNex);

  ELzNexPool = class(ELzNex);

  ELzNexBuilder = class(ELzNex);

  ELzNexCompile = class(ELzNex);

  ELzNexQuery = class(ELzNex)
  private
    FSQL: string;
  public
    constructor CreateFmt(const AMessage, ASQL: string);

    property SQL: string read FSQL;
  end;

  ELzNexSchema = class(ELzNex);

  ELzNexMigration = class(ELzNex);

  ELzNexMigrationLock = class(ELzNexMigration);

  ELzNexTransaction = class(ELzNex);

implementation

constructor ELzNexQuery.CreateFmt(const AMessage, ASQL: string);
begin
  inherited Create(AMessage + sLineBreak + 'SQL: ' + ASQL);
  FSQL := ASQL;
end;

end.
