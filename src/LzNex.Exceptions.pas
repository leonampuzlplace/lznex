unit LzNex.Exceptions;

{ Hierarquia de excecoes do LzNex. Toda falha previsivel tem classe propria,
  para o chamador poder tratar seletivamente. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils;

type
  // Base de todas as excecoes da biblioteca.
  ELzNex = class(Exception);

  // Configuracao ausente ou invalida (dialeto, host, pool).
  ELzNexConfig = class(ELzNex);

  // Falha ao abrir, validar ou usar conexao.
  ELzNexConnection = class(ELzNex);

  // Pool esgotado ou ja encerrado.
  ELzNexPool = class(ELzNex);

  // Uso invalido da API fluente (grupo nao fechado, clausula
  // incompativel com o verbo, operador fora da whitelist, valor nao informado).
  ELzNexBuilder = class(ELzNex);

  // O builder esta coerente mas o dialeto nao suporta o recurso.
  ELzNexCompile = class(ELzNex);

  // Erro devolvido pelo banco ao executar.
  ELzNexQuery = class(ELzNex)
  private
    FSQL: string;
  public
    constructor CreateFmt(const AMessage, ASQL: string);
    // O comando que falhou, para log.
    property SQL: string read FSQL;
  end;

  // DDL invalido ou recurso de schema nao suportado pelo dialeto.
  ELzNexSchema = class(ELzNex);

  // Migration invalida, faltando ou corrompida.
  ELzNexMigration = class(ELzNex);

  // A tabela de migrations ja esta travada por outro processo.
  ELzNexMigrationLock = class(ELzNexMigration);

  // Commit/rollback fora de transacao, ou aninhamento invalido.
  ELzNexTransaction = class(ELzNex);

implementation

constructor ELzNexQuery.CreateFmt(const AMessage, ASQL: string);
begin
  inherited Create(AMessage + sLineBreak + 'SQL: ' + ASQL);
  FSQL := ASQL;
end;

end.
