unit LzNex.Client.Postgres;

{ Dialeto PostgreSQL: o que muda em relacao ao ANSI da classe base.

  Vale registrar o quanto NAO precisou ser escrito aqui. O compiler base ja
  emite `returning`, `on conflict ... do nothing`, `on conflict ... do update
  set ... excluded.`, `distinct on (...)`, `nulls first/last` nativo e
  limit/offset ANSI -- cada um desses ligado por uma CAPACIDADE do client, nao
  por um `if dialeto = ...`. Entao o Postgres entra quase todo por
  configuracao: a unica sobrescrita de compiler e o `restart identity` do
  truncate.

  Herdado de proposito (nao sobrescrito aqui, porque o default da base ja e o
  valor do Postgres):
    QuoteChar          -> aspas duplas, com o caractere dobrado para escapar
    SupportsSavepoints -> True
    DdlIsTransactional -> True (o Postgres faz DDL dentro de transacao; o
                          MySQL e quem sobrescreve para False)
    InvalidComponents  -> ANSI, isto e, sem LIMIT em DELETE (o MySQL aceita
                          LIMIT ali e por isso sobrescreve)
    CompileLimit       -> limit/offset ANSI, sem o teto de 64 bits do MySQL

  Dar `uses` nesta unit registra 'postgresql' e 'postgres' no registry. }

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
    // Sem `restart identity` o truncate esvazia a tabela mas deixa as
    // sequences dos serial onde estavam.
    function CompileTruncate: TLzNexFragment; override;
  end;

  TLzNexPostgresClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;

    function SupportsReturning: Boolean; override;
    function SupportsOnConflictWhere: Boolean; override;
    function SupportsNullsOrdering: Boolean; override;
    function SupportsDistinctOn: Boolean; override;

    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

implementation

uses
  // No implementation para que a unit de DDL possa evoluir sem arrastar
  // dependencia na interface deste dialeto.
  LzNex.Schema.Postgres,
  // Registra o driver 'postgresql' no DriverManager do Zeos pelo
  // initialization dela. Sem esta linha o DriverManager responde
  // "Requested database driver was not found" em runtime -- unit que ninguem
  // referencia nao e linkada, entao o initialization nao roda.
  ZDbcPostgreSql;

{ TLzNexPostgresCompiler }

function TLzNexPostgresCompiler.CompileTruncate: TLzNexFragment;
begin
  Result := inherited CompileTruncate;
  Result := Result.Concat(Txt('restart identity'));
end;

{ TLzNexPostgresClient }

function TLzNexPostgresClient.DialectName: string;
begin
  Result := 'postgresql';
end;

function TLzNexPostgresClient.ZeosProtocol: string;
begin
  Result := 'postgresql';
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
  // Com isto o compiler base emite `nulls first`/`nulls last` nativo, em vez
  // da emulacao com "(col is null)" que o MySQL recebe.
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
  // 'postgres' e o apelido que aparece em DSN e em docker-compose.
  RegisterClient('postgres', TLzNexPostgresClient);

end.
