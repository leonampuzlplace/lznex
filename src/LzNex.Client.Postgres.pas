unit LzNex.Client.Postgres;

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
  LzNex.Client,
  LzNex.Compiler,
  LzNex.Exceptions;

type
  TLzNexPostgresCompiler = class(TLzNexCompilerBase)
  protected

    function CompileTruncate: TLzNexFragment; override;
  end;

  TLzNexPostgresClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;

    // O booleano do ANSI sai como 1/0, que o PostgreSQL recusa numa coluna
    // boolean. Vale para o DEFAULT do DDL, que e interpolado por aqui.
    function EscapeForLog(const AValue: TLzNexValue): string; override;

    function SupportsReturning: Boolean; override;
    function SupportsOnConflictWhere: Boolean; override;
    function SupportsNullsOrdering: Boolean; override;
    function SupportsDistinctOn: Boolean; override;

    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

implementation

uses

  LzNex.Schema.Postgres,

  ZDbcPostgreSql;

function TLzNexPostgresCompiler.CompileTruncate: TLzNexFragment;
begin
  Result := inherited CompileTruncate;
  Result := Result.Concat(Txt('restart identity'));
end;

function TLzNexPostgresClient.DialectName: string;
begin
  Result := 'postgresql';
end;

function TLzNexPostgresClient.ZeosProtocol: string;
begin
  Result := 'postgresql';
end;

function TLzNexPostgresClient.EscapeForLog(const AValue: TLzNexValue): string;
begin
  if AValue.Kind = vkBoolean then
  begin
    if AValue.AsBoolean then
      Result := 'true'
    else
      Result := 'false';
    Exit;
  end;
  Result := inherited EscapeForLog(AValue);
end;

function TLzNexPostgresClient.SupportsReturning: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.SupportsOnConflictWhere: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.SupportsNullsOrdering: Boolean;
begin

  Result := True;
end;

function TLzNexPostgresClient.SupportsDistinctOn: Boolean;
begin
  Result := True;
end;

function TLzNexPostgresClient.NewCompiler: ILzNexCompiler;
begin
  Result := TLzNexPostgresCompiler.Create(Self);
end;

function TLzNexPostgresClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := NewPostgresSchemaCompiler(Self);
end;

initialization
  RegisterClient('postgresql', TLzNexPostgresClient);

  RegisterClient('postgres', TLzNexPostgresClient);

end.
