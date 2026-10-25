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
    FErrorCode: Integer;
    FSQLState: string;
  public
    constructor CreateFmt(const AMessage, ASQL: string);

    constructor CreateDb(const AMessage, ASQL: string; const AErrorCode: Integer;
      const ASQLState: string);

    property SQL: string read FSQL;

    property ErrorCode: Integer read FErrorCode;

    property SQLState: string read FSQLState;
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
  FErrorCode := 0;
  FSQLState := '';
end;

constructor ELzNexQuery.CreateDb(const AMessage, ASQL: string;
  const AErrorCode: Integer; const ASQLState: string);
begin
  CreateFmt(AMessage, ASQL);
  FErrorCode := AErrorCode;
  FSQLState := ASQLState;
end;

end.
