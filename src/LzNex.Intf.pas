unit LzNex.Intf;

{ TODAS as interfaces publicas do LzNex, numa unit so.

  Por que uma unit so: em Pascal nao se pode ter referencia circular entre
  secoes `interface` de units, e ILzNexQuery precisa de ILzNexResult, que
  precisa de ILzNexValue, que... Reunir tudo aqui resolve isso de uma vez e da
  aos implementadores um unico arquivo de contrato para ler.

  Toda interface e COM refcounted (default do FPC): quem usa a API fluente NUNCA
  escreve try/finally Free. Regra do projeto para nao vazar: referencia de filho
  para pai e sempre referencia de CLASSE, nunca interface (ciclo de refcount
  nunca zera). }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast;

type
  ILzNexRaw = interface;
  ILzNexQuery = interface;
  ILzNexJoin = interface;
  ILzNexOnConflict = interface;
  ILzNexResult = interface;
  ILzNexRow = interface;
  ILzNexSchema = interface;
  ILzNexTable = interface;
  ILzNexConnection = interface;
  ILzNexPool = interface;
  ILzNexTransaction = interface;
  ILzNexClient = interface;
  ILzNexCompiler = interface;
  ILzNexSchemaCompiler = interface;
  ILzNexConfig = interface;
  ILzNexLogger = interface;
  ILzNexMigration = interface;
  ILzNexMigrationSource = interface;
  ILzNexMigrator = interface;
  ILzNexSeeder = interface;
  ILzNexColumnDef = interface;
  ILzNexIndexDef = interface;
  ILzNex = interface;

  // Arrays nomeados em vez de TArray<T>: TArray generico nao e garantido em
  // todo contexto do FPC 3.2.2 e nome proprio documenta melhor.
  TLzNexStringArray = array of string;
  TLzNexRowArray = array of ILzNexRow;
  TLzNexMigrationArray = array of ILzNexMigration;

  // ============================================================
  //  Raw
  // ============================================================

  // Fragmento de SQL cru com binds.
  // '?' = valor (bind), '??' = identificador (quotado), '\?' = '?' literal,
  // ':nome' = valor nomeado, ':nome:' = identificador nomeado.
  ILzNexRaw = interface
    ['{9A1C0E10-0001-4C2E-9B01-6E5B2A7F0001}']
    // Resolve o template contra um dialeto e devolve texto + binds.
    function Build(const AClient: ILzNexClient): TLzNexFragment;
    // O SQL original, sem resolver.
    function Template: string;
  end;

  // ============================================================
  //  Resultado
  // ============================================================

  // Uma linha materializada (independente do cursor).
  ILzNexRow = interface
    ['{9A1C0E10-0002-4C2E-9B01-6E5B2A7F0002}']
    // Valor pelo nome da coluna. Levanta se a coluna nao existe.
    function Field(const AName: string): TLzNexValue;
    // Valor pelo nome, sem levantar.
    function TryField(const AName: string; out AValue: TLzNexValue): Boolean;
    // Valor pelo indice (0-based).
    function FieldAt(const AIndex: Integer): TLzNexValue;
    // Se a coluna existe nesta linha.
    function Has(const AName: string): Boolean;
    // Quantidade de colunas.
    function FieldCount: Integer;
    // Nome da coluna pelo indice.
    function FieldName(const AIndex: Integer): string;
    // A linha como objeto JSON.
    function ToJSON: string;
  end;

  // Cursor forward-only sobre o resultado.
  // Envolve IZResultSet do Zeos: sem o peso do TDataset.
  ILzNexResult = interface
    ['{9A1C0E10-0003-4C2E-9B01-6E5B2A7F0003}']
    // Avanca para a proxima linha. False quando acabou.
    function Next: Boolean;
    // Valor da coluna na linha atual.
    function Field(const AName: string): TLzNexValue;
    // Valor da coluna por indice (0-based) na linha atual.
    function FieldAt(const AIndex: Integer): TLzNexValue;
    // Quantidade de colunas.
    function FieldCount: Integer;
    // Nome da coluna pelo indice.
    function FieldName(const AIndex: Integer): string;
    // Materializa a linha atual (sobrevive ao avanco do cursor).
    function CurrentRow: ILzNexRow;
    // Materializa TODAS as linhas restantes.
    function ToRows: TLzNexRowArray;
    // Array JSON com todas as linhas restantes.
    function ToJSON: string;
    // Fecha o cursor. Tambem ocorre na liberacao da interface.
    procedure Close;
  end;

  // ============================================================
  //  Dialeto (Client) — o ponto de extensao para novos bancos
  // ============================================================

  // Tudo que varia entre bancos.
  // Incluir PostgreSQL ou Firebird = implementar isto (ou descender da classe base).
  ILzNexClient = interface
    ['{9A1C0E10-0004-4C2E-9B01-6E5B2A7F0004}']
    // 'mysql', 'postgresql', 'firebird'...
    function DialectName: string;
    // O Protocol correspondente no Zeos.
    function ZeosProtocol: string;

    // --- lexico ---
    // Quota UM segmento ('id' -> `id`). '*' passa direto.
    function WrapIdentifier(const AName: string): string;
    // Quota nome qualificado e resolve ' as ':
    // 'a.b' -> `a`.`b`;  'x as y' -> `x` as `y`.
    function WrapQualified(const AName: string): string;
    // Junta expressao e alias ('expr as alias'; Oracle usa so espaco).
    function Alias(const AExpr, AAlias: string): string;
    // O placeholder da posicao (1-based). MySQL/Zeos usa '?'.
    function Placeholder(const AIndex: Integer): string;
    // Interpola um valor no SQL. SO para log/ToString,
    // NUNCA para execucao.
    function EscapeForLog(const AValue: TLzNexValue): string;

    // --- capacidades ---
    // Se INSERT/UPDATE/DELETE aceitam RETURNING.
    function SupportsReturning: Boolean;
    // Se o upsert aceita WHERE (PG sim, MySQL nao).
    function SupportsOnConflictWhere: Boolean;
    // Se aceita 'nulls first/last' nativo.
    function SupportsNullsOrdering: Boolean;
    // Se aceita DISTINCT ON (so PG).
    function SupportsDistinctOn: Boolean;
    // Se aceita savepoint para transacao aninhada.
    function SupportsSavepoints: Boolean;
    // MySQL faz COMMIT IMPLICITO em DDL, logo False lá.
    // O migrator usa isso para avisar que o rollback nao vai cobrir o DDL.
    function DdlIsTransactional: Boolean;

    // --- estrutura da compilacao ---
    // A ordem das secoes para o verbo. VIRTUAL de proposito:
    // no knex isso era const de modulo e obrigou Oracle/MSSQL a duplicar codigo.
    function Components(const AMethod: TLzNexQueryMethod): TLzNexComponents;
    // Secoes proibidas no verbo (ex.: HAVING em DELETE).
    function InvalidComponents(const AMethod: TLzNexQueryMethod): TLzNexComponents;

    // --- fabricas ---
    // Compilador de query deste dialeto.
    function NewCompiler: ILzNexCompiler;
    // Compilador de DDL deste dialeto.
    function NewSchemaCompiler: ILzNexSchemaCompiler;
  end;

  // Transforma uma AST numa instrucao SQL + binds.
  //
  // Recebe TLzNexAst, NAO ILzNexQuery: assim o compiler nao depende do builder,
  // e da para testar cada um sozinho (AST montada na mao de um lado, AST
  // produzida conferida do outro).
  ILzNexCompiler = interface
    ['{9A1C0E10-0005-4C2E-9B01-6E5B2A7F0005}']
    // A instrucao completa.
    function Compile(const AAst: TLzNexAst): TLzNexFragment;
    // So o corpo dos predicados de um grupo, SEM o prefixo 'where'/'having'.
    // Existe para grupo aninhado nao precisar recortar string (o knex faz
    // `.slice(6)` para remover o literal 'where ').
    function CompilePredicates(const AGroup: TLzNexStatementGroup;
      const AItems: TLzNexStatementList): TLzNexFragment;
    // O dialeto usado por este compiler.
    function Client: ILzNexClient;
  end;

  // Plano de DDL. Estrutura copiada do generateDdlCommands()
  // do knex, que e a direcao certa; o `output` closure dele nao e copiado.
  TLzNexDdlPlan = record
    // Comandos que precisam rodar antes (ex.: CREATE TYPE do PG).
    Pre: TLzNexFragments;
    // Os comandos principais, na ordem.
    Statements: TLzNexFragments;
    // Comandos de depois (indices, FK, comentarios).
    Post: TLzNexFragments;
    // Pre + Statements + Post, achatado.
    function All: TLzNexFragments;
    // Total de comandos.
    function Count: Integer;
  end;

  // Transforma uma operacao de schema em DDL.
  ILzNexSchemaCompiler = interface
    ['{9A1C0E10-0006-4C2E-9B01-6E5B2A7F0006}']
    // DDL de create/alter de tabela.
    function CompileTable(const ATable: ILzNexTable): TLzNexDdlPlan;
    // Tipo fisico da coluna neste dialeto.
    function ColumnTypeSQL(const AType: TLzNexColumnType;
      const AParam1, AParam2: Integer; const AItems: TLzNexValues): string;
    // ORDEM de emissao dos modificadores. Definida pelo
    // dialeto, nao pela ordem de chamada do usuario (senao sai DDL invalido).
    function ModifierOrder: TLzNexColumnModifiers;
    // DropTableSQL / RenameTableSQL — DDL simples.
    function DropTableSQL(const ATable: string; const AIfExists: Boolean): TLzNexFragment;
    function RenameTableSQL(const AFrom, ATo: string): TLzNexFragment;
    function TruncateTableSQL(const ATable: string): TLzNexFragment;
    // HasTableSQL / HasColumnSQL — consulta de existencia. O chamador le a
    // primeira coluna da primeira linha como contagem.
    function HasTableSQL(const ATable, ASchema: string): TLzNexFragment;
    function HasColumnSQL(const ATable, AColumn, ASchema: string): TLzNexFragment;
    // Nome automatico (<tabela>_<colunas>_<tipo>), convencao do knex.
    function IndexName(const ATable: string; const AColumns: TLzNexValues;
      const AKind: TLzNexIndexKind): string;
  end;

  // ============================================================
  //  Query builder
  // ============================================================

  // O query builder encadeavel.
  //
  // Sem callback: FPC 3.2.2 nao tem funcao anonima (verificado no fonte do
  // compilador). Grupos de predicado usam WhereOpen/WhereClose com pilha.
  ILzNexQuery = interface
    ['{9A1C0E10-0007-4C2E-9B01-6E5B2A7F0007}']

    // --- fonte ---
    // Define a tabela (alias de From).
    function Table(const AName: string): ILzNexQuery;
    // Define a tabela.
    function From(const AName: string): ILzNexQuery;
    // Tabela com alias.
    function FromAs(const AName, AAlias: string): ILzNexQuery;
    // Subquery como fonte, com alias obrigatorio.
    function FromSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;
    // Fonte crua.
    function FromRaw(const ARaw: ILzNexRaw): ILzNexQuery;
    // Prefixa a tabela com o schema.
    function WithSchema(const ASchema: string): ILzNexQuery;
    // Alias desta query quando usada como subquery.
    function AsAlias(const AAlias: string): ILzNexQuery;

    // --- colunas ---
    // Lista de colunas. Aceita 'a.b' e 'x as y'.
    function Select(const AColumns: array of string): ILzNexQuery;
    // Uma coluna.
    function Column(const AColumn: string): ILzNexQuery;
    // Coluna com alias explicito (sem precisar do ' as ' na string).
    function SelectAs(const AColumn, AAlias: string): ILzNexQuery;
    // Expressao crua no SELECT.
    function SelectRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    // Subquery como coluna.
    function SelectSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexQuery;
    // DISTINCT simples.
    function Distinct: ILzNexQuery;
    // DISTINCT ON (so dialetos que suportam; senao levanta).
    function DistinctOn(const AColumns: array of string): ILzNexQuery;

    // --- where ---
    function Where(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function Where(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function WhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function WhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhere(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhere(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhereNot(const AColumn: string; const AValue: TLzNexValue): ILzNexQuery; overload;
    function OrWhereNot(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery; overload;

    // Compara duas COLUNAS (sem bind).
    function WhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;
    function OrWhereColumn(const ALeft, AOp, ARight: string): ILzNexQuery;

    // Lista vazia gera "1 = 0" (semantica do knex).
    function WhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function WhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function OrWhereIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function OrWhereNotIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    // IN com subquery.
    function WhereInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;
    function WhereNotInSub(const AColumn: string; const ASub: ILzNexQuery): ILzNexQuery;

    function WhereNull(const AColumn: string): ILzNexQuery;
    function WhereNotNull(const AColumn: string): ILzNexQuery;
    function OrWhereNull(const AColumn: string): ILzNexQuery;
    function OrWhereNotNull(const AColumn: string): ILzNexQuery;

    function WhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function WhereNotBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function OrWhereBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;

    function WhereLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
    function WhereNotLike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;
    function WhereILike(const AColumn: string; const APattern: TLzNexValue): ILzNexQuery;

    function WhereExists(const ASub: ILzNexQuery): ILzNexQuery;
    function WhereNotExists(const ASub: ILzNexQuery): ILzNexQuery;

    function WhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function OrWhereRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    // Abre um grupo "(". Substitui o callback do knex.
    function WhereOpen: ILzNexQuery;
    // Abre um grupo conectado com OR.
    function OrWhereOpen: ILzNexQuery;
    // Abre um grupo negado "NOT (".
    function WhereNotOpen: ILzNexQuery;
    // Fecha o grupo. ToSQL levanta se sobrar grupo aberto.
    function WhereClose: ILzNexQuery;

    // --- join ---
    // INNER JOIN. Devolve ILzNexJoin, que herda ILzNexQuery: da para
    // encadear On* e continuar a query na mesma expressao.
    function Join(const ATable: string): ILzNexJoin;
    function JoinAs(const ATable, AAlias: string): ILzNexJoin;
    function InnerJoin(const ATable: string): ILzNexJoin;
    function LeftJoin(const ATable: string): ILzNexJoin;
    function LeftOuterJoin(const ATable: string): ILzNexJoin;
    function RightJoin(const ATable: string): ILzNexJoin;
    function RightOuterJoin(const ATable: string): ILzNexJoin;
    function FullOuterJoin(const ATable: string): ILzNexJoin;
    function CrossJoin(const ATable: string): ILzNexJoin;
    function JoinSub(const ASub: ILzNexQuery; const AAlias: string): ILzNexJoin;
    function JoinRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    // --- group / having / order ---
    function GroupBy(const AColumns: array of string): ILzNexQuery;
    function GroupByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    function Having(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
    function OrHaving(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexQuery;
    function HavingIn(const AColumn: string; const AValues: TLzNexValues): ILzNexQuery;
    function HavingNull(const AColumn: string): ILzNexQuery;
    function HavingNotNull(const AColumn: string): ILzNexQuery;
    function HavingBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexQuery;
    function HavingRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;
    function HavingOpen: ILzNexQuery;
    function HavingClose: ILzNexQuery;

    function OrderBy(const AColumn: string): ILzNexQuery; overload;
    function OrderBy(const AColumn: string; const ADir: TLzNexOrderDir): ILzNexQuery; overload;
    function OrderBy(const AColumn: string; const ADir: TLzNexOrderDir;
      const ANulls: TLzNexNullsOrder): ILzNexQuery; overload;
    function OrderByDesc(const AColumn: string): ILzNexQuery;
    function OrderByRaw(const ASQL: string; const AArgs: array of const): ILzNexQuery;

    // --- paginacao e lock ---
    function Limit(const ACount: Int64): ILzNexQuery;
    function Offset(const ACount: Int64): ILzNexQuery;
    // Atalho: pagina 1-based com tamanho fixo.
    function Page(const APage, APerPage: Int64): ILzNexQuery;
    function ForUpdate: ILzNexQuery;
    function ForShare: ILzNexQuery;
    function SkipLocked: ILzNexQuery;
    function NoWait: ILzNexQuery;

    // --- union / cte / hint ---
    function Union(const ASub: ILzNexQuery): ILzNexQuery;
    function UnionAll(const ASub: ILzNexQuery): ILzNexQuery;
    function Intersect(const ASub: ILzNexQuery): ILzNexQuery;
    function Except_(const ASub: ILzNexQuery): ILzNexQuery;
    function With_(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
    function WithRecursive(const AAlias: string; const ASub: ILzNexQuery): ILzNexQuery;
    function HintComment(const AHint: string): ILzNexQuery;

    // --- upsert ---
    // Devolve um builder que SO tem Merge/Ignore. O tipo de retorno
    // ja impede esquecer de completar a clausula (no knex isso era um then()
    // que levantava em runtime).
    function OnConflict(const AColumns: array of string): ILzNexOnConflict;
    // Colunas a devolver (dialetos que suportam).
    function Returning(const AColumns: array of string): ILzNexQuery;

    // --- limpeza / clone ---
    // Remove todos os statements de um grupo.
    function Clear(const AGroup: TLzNexStatementGroup): ILzNexQuery;
    // Copia PROFUNDA e independente.
    function Clone: ILzNexQuery;
    // Amarra esta query a uma transacao.
    function Transacting(const ATrx: ILzNexTransaction): ILzNexQuery;

    // --- compilacao ---
    // Texto + binds, sem executar. Nao precisa de conexao.
    function ToSQL: TLzNexFragment;
    // SQL com os valores interpolados. SO para log.
    function ToSQLString: string;

    // --- terminais (explicitos: nao existe "thenable" aqui) ---
    // Executa o SELECT e devolve o cursor.
    function Get: ILzNexResult;
    // Primeira linha, ou nil se nao houver.
    function First: ILzNexRow;
    // Valor da coluna na primeira linha (escalar).
    function Value(const AColumn: string): TLzNexValue;
    // Primeira coluna da primeira linha.
    function Scalar: TLzNexValue;
    // Uma coluna de todas as linhas.
    function Pluck(const AColumn: string): TLzNexValues;
    // Se existe ao menos uma linha.
    function Exists: Boolean;
    // COUNT(*).
    function Count: Int64;
    // Min/max/sum/avg/count de uma coluna.
    function Aggregate(const AAgg: TLzNexAggregate; const AColumn: string): TLzNexValue;

    // Insere uma linha. Devolve linhas afetadas.
    function Insert(const AValues: TLzNexNamedValues): Int64;
    // Insere e devolve o id gerado.
    function InsertGetId(const AValues: TLzNexNamedValues): Int64;
    // Insere varias linhas num unico comando. Coluna ausente numa
    // linha vira DEFAULT (via vkUnset), nao NULL.
    function InsertMany(const ARows: array of TLzNexNamedValues): Int64;
    // Atualiza. Devolve linhas afetadas.
    function Update(const AValues: TLzNexNamedValues): Int64;
    // Increment / Decrement — "col = col + ?" sem race de leitura.
    function Increment(const AColumn: string; const ABy: Int64 = 1): Int64;
    function Decrement(const AColumn: string; const ABy: Int64 = 1): Int64;
    // Apaga. Devolve linhas afetadas.
    function Delete: Int64;
    // Esvazia a tabela.
    procedure Truncate;

    // --- acesso interno (nao e API de usuario final) ---
    // A AST acumulada. O builder continua DONO dela: nao liberar, nao guardar
    // alem do escopo da query.
    function Ast: TLzNexAst;
    // O dialeto desta query.
    function Client: ILzNexClient;
    // Grupos de predicado ainda abertos. ToSQL exige zero.
    function OpenGroupCount: Integer;
  end;

  // Contexto de um JOIN. Herda ILzNexQuery para dar para encadear
  // On* e seguir a query na mesma expressao, sem precisar de closure.
  ILzNexJoin = interface(ILzNexQuery)
    ['{9A1C0E10-0008-4C2E-9B01-6E5B2A7F0008}']
    // Compara duas COLUNAS (identificadores, sem bind).
    function OnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    // Compara coluna com VALOR (gera bind). Separar de OnColumns
    // evita a pegadinha do knex, onde on('a', true) comparava com "true".
    function OnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function AndOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function OrOnColumns(const ALeft, AOp, ARight: string): ILzNexJoin;
    function AndOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function OrOnValue(const AColumn, AOp: string; const AValue: TLzNexValue): ILzNexJoin;
    function OnIn(const AColumn: string; const AValues: TLzNexValues): ILzNexJoin;
    function OnNull(const AColumn: string): ILzNexJoin;
    function OnNotNull(const AColumn: string): ILzNexJoin;
    function OnBetween(const AColumn: string; const ALo, AHi: TLzNexValue): ILzNexJoin;
    function OnRaw(const ASQL: string; const AArgs: array of const): ILzNexJoin;
    // "USING (a, b)" em vez de ON.
    function Using(const AColumns: array of string): ILzNexJoin;
  end;

  // Clausula de upsert, obrigatoriamente completada.
  ILzNexOnConflict = interface
    ['{9A1C0E10-0009-4C2E-9B01-6E5B2A7F0009}']
    // Ignora o conflito.
    function Ignore: ILzNexQuery;
    // Atualiza todas as colunas do insert no conflito.
    function Merge: ILzNexQuery; overload;
    // Atualiza apenas as colunas informadas.
    function Merge(const AColumns: array of string): ILzNexQuery; overload;
    // Atualiza com valores explicitos.
    function MergeValues(const AValues: TLzNexNamedValues): ILzNexQuery;
  end;

  // ============================================================
  //  Schema builder
  // ============================================================

  // Definicao de uma coluna, lida pelo compiler de DDL.
  ILzNexColumnDef = interface
    ['{9A1C0E10-000A-4C2E-9B01-6E5B2A7F000A}']
    function ColumnName: string;
    function ColumnType: TLzNexColumnType;
    function Param1: Integer;            // length / precision
    function Param2: Integer;            // scale
    function EnumItems: TLzNexValues;
    function SpecificType: string;       // usado quando ColumnType = ctSpecific
    function HasModifier(const AMod: TLzNexColumnModifier): Boolean;
    function DefaultValue: TLzNexValue;
    function CommentText: string;
    function CollateName: string;
    function AfterColumn: string;
    function IsChange: Boolean;          // true em alter: modifica coluna existente
    function IsDrop: Boolean;
  end;

  // Indice, unique, primary ou foreign key.
  ILzNexIndexDef = interface
    ['{9A1C0E10-000B-4C2E-9B01-6E5B2A7F000B}']
    function IndexKind: TLzNexIndexKind;
    function Columns: TLzNexValues;
    function IndexNameOverride: string;
    function RefTable: string;
    function RefColumns: TLzNexValues;
    function OnDeleteAction: string;
    function OnUpdateAction: string;
    function IsDrop: Boolean;
  end;

  // Table builder. Os modificadores aplicam-se a ULTIMA coluna
  // adicionada, o que faz a leitura ficar igual a do knex sem exigir um .Done
  // por coluna. Chamar modificador sem coluna anterior levanta.
  ILzNexTable = interface
    ['{9A1C0E10-000C-4C2E-9B01-6E5B2A7F000C}']

    // --- colunas ---
    function Increments(const AName: string = 'id'): ILzNexTable;
    function BigIncrements(const AName: string = 'id'): ILzNexTable;
    function TinyInt(const AName: string): ILzNexTable;
    function SmallInt(const AName: string): ILzNexTable;
    function Int(const AName: string): ILzNexTable;
    function BigInt(const AName: string): ILzNexTable;
    function Bool(const AName: string): ILzNexTable;
    function Decimal(const AName: string; const APrecision: Integer = 8;
      const AScale: Integer = 2): ILzNexTable;
    function Float(const AName: string): ILzNexTable;
    function Double(const AName: string): ILzNexTable;
    function Char_(const AName: string; const ALength: Integer = 255): ILzNexTable;
    function Str(const AName: string; const ALength: Integer = 255): ILzNexTable;
    function Text(const AName: string): ILzNexTable;
    function MediumText(const AName: string): ILzNexTable;
    function LongText(const AName: string): ILzNexTable;
    function Binary(const AName: string; const ALength: Integer = 0): ILzNexTable;
    function Blob(const AName: string): ILzNexTable;
    function Date(const AName: string): ILzNexTable;
    function Time(const AName: string): ILzNexTable;
    function DateTime(const AName: string): ILzNexTable;
    function Timestamp(const AName: string): ILzNexTable;
    function Json(const AName: string): ILzNexTable;
    function Uuid(const AName: string): ILzNexTable;
    function Enum(const AName: string; const AItems: array of string): ILzNexTable;
    function Specific(const AName, ATypeSQL: string): ILzNexTable;
    // Created_at e updated_at. Default TIMESTAMP (o knex usa
    // DATETIME por default, que surpreende; invertido aqui de proposito).
    function Timestamps(const ADefaultNow: Boolean = True): ILzNexTable;

    // --- modificadores (aplicam-se a ultima coluna) ---
    function NotNull: ILzNexTable;
    function Nullable: ILzNexTable;
    function Unsigned: ILzNexTable;
    function Default_(const AValue: TLzNexValue): ILzNexTable;
    function DefaultRaw(const ASQL: string): ILzNexTable;
    function Comment(const AText: string): ILzNexTable;
    function Collate(const AName: string): ILzNexTable;
    function After(const AColumn: string): ILzNexTable;
    function Primary: ILzNexTable; overload;
    function Unique: ILzNexTable; overload;
    function Index: ILzNexTable; overload;
    // Em alter: a coluna modifica uma existente em vez de adicionar.
    function Change: ILzNexTable;

    // --- chave estrangeira (aplica-se a ultima coluna) ---
    function References(const AColumn: string): ILzNexTable;
    function InTable(const ATable: string): ILzNexTable;
    function OnDelete(const AAction: string): ILzNexTable;
    function OnUpdate(const AAction: string): ILzNexTable;
    function ConstraintName(const AName: string): ILzNexTable;

    // --- indices em varias colunas ---
    function Primary(const AColumns: array of string): ILzNexTable; overload;
    function Unique(const AColumns: array of string): ILzNexTable; overload;
    function Index(const AColumns: array of string): ILzNexTable; overload;
    function DropColumn(const AName: string): ILzNexTable;
    function DropIndex(const AColumns: array of string): ILzNexTable;
    function DropUnique(const AColumns: array of string): ILzNexTable;
    function DropForeign(const AColumns: array of string): ILzNexTable;
    function DropPrimary: ILzNexTable;
    function RenameColumn(const AFrom, ATo: string): ILzNexTable;

    // --- opcoes de tabela ---
    function Engine(const AName: string): ILzNexTable;
    function Charset(const AName: string): ILzNexTable;
    function TableCollate(const AName: string): ILzNexTable;
    function TableComment(const AText: string): ILzNexTable;

    // --- terminais ---
    // O plano de DDL, sem executar.
    function ToSQL: TLzNexDdlPlan;
    // Roda o DDL. Devolve a quantidade de comandos executados.
    function Execute: Integer;

    // --- acesso para o compiler ---
    function TableName: string;
    function SchemaName: string;
    function TableMethod: TLzNexTableMethod;
    function ColumnCount: Integer;
    function ColumnAt(const AIndex: Integer): ILzNexColumnDef;
    function IndexCount: Integer;
    function IndexAt(const AIndex: Integer): ILzNexIndexDef;
    function RenamedColumns: TLzNexNamedValues;   // Name = de, Value = para
    function EngineName: string;
    function CharsetName: string;
    function CollateName: string;
    function CommentText: string;
    function Client: ILzNexClient;
  end;

  // Entrada do schema builder.
  ILzNexSchema = interface
    ['{9A1C0E10-000D-4C2E-9B01-6E5B2A7F000D}']
    // Schema/database alvo das proximas operacoes.
    function WithSchema(const AName: string): ILzNexSchema;
    // Cria tabela. Levanta se ja existir.
    function CreateTable(const AName: string): ILzNexTable;
    // Altera tabela existente.
    function Table(const AName: string): ILzNexTable;
    // HasTable / HasColumn — consulta de existencia.
    function HasTable(const AName: string): Boolean;
    function HasColumn(const ATable, AColumn: string): Boolean;
    // DropTable / DropTableIfExists / RenameTable / Truncate.
    procedure DropTable(const AName: string);
    procedure DropTableIfExists(const AName: string);
    procedure RenameTable(const AFrom, ATo: string);
    procedure Truncate(const AName: string);
    // DDL cru.
    procedure Raw(const ASQL: string; const AArgs: array of const);
  end;

  // ============================================================
  //  Conexao, pool e transacao
  // ============================================================

  // Uma conexao. Envolve IZConnection (camada DBC do Zeos).
  ILzNexConnection = interface
    ['{9A1C0E10-000E-4C2E-9B01-6E5B2A7F000E}']
    // Roda comando sem resultset. Devolve linhas afetadas.
    function Execute(const AFragment: TLzNexFragment): Int64;
    // Roda SELECT e devolve o cursor.
    function Query(const AFragment: TLzNexFragment): ILzNexResult;
    // Roda DDL/comando cru (sem binds).
    function ExecuteScript(const ASQL: string): Int64;
    // Id gerado pelo ultimo INSERT nesta conexao.
    function LastInsertId: Int64;
    // Abre transacao ou savepoint. Devolve o nivel.
    function StartTransaction: Integer;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function TransactionLevel: Integer;
    // Testa se a conexao esta viva.
    function Ping: Boolean;
    function IsClosed: Boolean;
    procedure Close;
    // O IZConnection do Zeos, para uso avancado.
    function Native: IInterface;
    // O dialeto desta conexao.
    function Client: ILzNexClient;
  end;

  // Pool de conexoes.
  // O provider FPC do Horse e multi-thread (um thread por conexao HTTP), logo
  // conexao NAO pode ser compartilhada entre threads: uma por requisicao.
  ILzNexPool = interface
    ['{9A1C0E10-000F-4C2E-9B01-6E5B2A7F000F}']
    // Pega uma conexao. A conexao volta ao pool quando a interface
    // devolvida e liberada (RAII): nao da para esquecer de devolver.
    function Acquire: ILzNexConnection;
    // Size / InUse — tamanho atual e quantas estao emprestadas.
    function Size: Integer;
    function InUse: Integer;
    procedure Shutdown;
  end;

  // ILzNexTransaction e declarada no fim: ela HERDA de ILzNex, e em Pascal o
  // ancestral de uma interface precisa estar totalmente declarado antes.

  // ============================================================
  //  Config e log
  // ============================================================

  // Configuracao fluente (o equivalente do knexfile).
  ILzNexConfig = interface
    ['{9A1C0E10-0011-4C2E-9B01-6E5B2A7F0011}']
    function Client(const AName: string): ILzNexConfig;
    function Host(const AValue: string): ILzNexConfig;
    function Port(const AValue: Integer): ILzNexConfig;
    function Database(const AValue: string): ILzNexConfig;
    function User(const AValue: string): ILzNexConfig;
    function Password(const AValue: string): ILzNexConfig;
    // Caminho da lib cliente. No Ubuntu 26.04 o auto-load do
    // Zeos falha (so existe libmariadb.so.3), entao isso e praticamente obrigatorio.
    function LibraryLocation(const AValue: string): ILzNexConfig;
    function Charset(const AValue: string): ILzNexConfig;
    function Pool(const AMin, AMax: Integer): ILzNexConfig;
    function AcquireTimeout(const AMilliseconds: Integer): ILzNexConfig;
    function MigrationsTable(const AValue: string): ILzNexConfig;
    function MigrationsDir(const AValue: string): ILzNexConfig;
    function SeedsDir(const AValue: string): ILzNexConfig;
    function Prop(const AName, AValue: string): ILzNexConfig;
    function Logger(const AValue: ILzNexLogger): ILzNexConfig;

    function GetClient: string;
    function GetHost: string;
    function GetPort: Integer;
    function GetDatabase: string;
    function GetUser: string;
    function GetPassword: string;
    function GetLibraryLocation: string;
    function GetCharset: string;
    function GetPoolMin: Integer;
    function GetPoolMax: Integer;
    function GetAcquireTimeout: Integer;
    function GetMigrationsTable: string;
    function GetMigrationsDir: string;
    function GetSeedsDir: string;
    function GetProps: TLzNexNamedValues;
    function GetLogger: ILzNexLogger;
    // Levanta ELzNexConfig se faltar algo obrigatorio.
    procedure Validate;
  end;

  // Log de query e de aviso. Substitui o EventEmitter do knex.
  ILzNexLogger = interface
    ['{9A1C0E10-0012-4C2E-9B01-6E5B2A7F0012}']
    procedure LogQuery(const ASQL: string; const ABindings: TLzNexBindings;
      const AElapsedMs: Int64);
    procedure LogError(const ASQL: string; const AError: string);
    procedure LogWarning(const AMessage: string);
    procedure LogInfo(const AMessage: string);
  end;

  // ============================================================
  //  Migrations e seeds
  // ============================================================

  // Uma migration, independente de onde veio (classe ou .sql).
  ILzNexMigration = interface
    ['{9A1C0E10-0013-4C2E-9B01-6E5B2A7F0013}']
    // Timestamp 'YYYYMMDDHHMMSS'. Define a ordem.
    function Id: string;
    // Nome completo, '<id>_<descricao>'. E o que vai na tabela de controle.
    function Name: string;
    // Se o runner deve envolver em transacao.
    function UseTransaction: Boolean;
    // Up / Down — aplica e desfaz.
    procedure Up(const ADb: ILzNex);
    procedure Down(const ADb: ILzNex);
  end;

  // De onde vem a lista de migrations.
  // Permite as duas fontes (classe Pascal e arquivo .sql) convivendo.
  ILzNexMigrationSource = interface
    ['{9A1C0E10-0014-4C2E-9B01-6E5B2A7F0014}']
    // Todas as migrations desta fonte, ordenadas por Id.
    function All: TLzNexMigrationArray;
    // 'code' ou 'sql'. Aparece no status.
    function SourceName: string;
  end;

  // Uma linha do `migrate:status`.
  TLzNexMigrationStatus = record
    Name: string;
    Source: string;
    Applied: Boolean;
    Batch: Integer;
    AppliedAt: TDateTime;
  end;
  TLzNexMigrationStatusList = array of TLzNexMigrationStatus;

  // O runner de migrations.
  ILzNexMigrator = interface
    ['{9A1C0E10-0015-4C2E-9B01-6E5B2A7F0015}']
    // Registra uma fonte de migrations.
    function AddSource(const ASource: ILzNexMigrationSource): ILzNexMigrator;
    // Aplica todas as pendentes num novo batch. Devolve quantas rodaram.
    function Latest: Integer;
    // Desfaz o ultimo batch.
    function Rollback: Integer;
    // Desfaz tudo.
    function RollbackAll: Integer;
    // Aplica a proxima pendente, ou a de nome informado.
    function Up(const AName: string = ''): Integer;
    // Desfaz a ultima aplicada, ou a de nome informado.
    function Down(const AName: string = ''): Integer;
    // Aplica pendentes ate a de nome informado, inclusive.
    function MigrateTo(const AName: string): Integer;
    // Aplicadas e pendentes, em ordem.
    function Status: TLzNexMigrationStatusList;
    // So as pendentes.
    function Pending: TLzNexMigrationArray;
    // O Id da ultima aplicada, ou 'none'.
    function CurrentVersion: string;
    // Libera o lock preso por processo que morreu.
    procedure Unlock;
    // Cria as tabelas de controle se faltarem.
    procedure EnsureTables;
  end;

  // Roda seeds. Sem batch, sem lock, sem transacao (igual knex).
  ILzNexSeeder = interface
    ['{9A1C0E10-0016-4C2E-9B01-6E5B2A7F0016}']
    function Run: Integer;
    function RunOne(const AName: string): Integer;
    function Names: TLzNexStringArray;
  end;

  // ============================================================
  //  Facade
  // ============================================================

  // A facade. Unico uses obrigatorio para quem consome a biblioteca.
  ILzNex = interface
    ['{9A1C0E10-0017-4C2E-9B01-6E5B2A7F0017}']
    // Table / From — comeca uma query.
    function Table(const AName: string): ILzNexQuery;
    function From(const AName: string): ILzNexQuery;
    // Query vazia (para montar subquery).
    function Query: ILzNexQuery;
    // Fragmento cru.
    function Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
    // O schema builder.
    function Schema: ILzNexSchema;
    // Abre transacao. O destrutor faz ROLLBACK se nao houve
    // commit, entao nunca sobra transacao aberta nem conexao vazada.
    function Transaction: ILzNexTransaction; overload;
    function Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction; overload;
    // Migrator / Seeder.
    function Migrator: ILzNexMigrator;
    function Seeder: ILzNexSeeder;
    // Execute / Fetch — atalhos para SQL cru.
    function Execute(const ASQL: string; const AArgs: array of const): Int64;
    function Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
    // Client / Config / Pool.
    function Client: ILzNexClient;
    function Config: ILzNexConfig;
    function Pool: ILzNexPool;
    // A conexao corrente. Fora de transacao, pega uma do pool.
    function Connection: ILzNexConnection;
    // Se esta facade e uma transacao.
    function IsTransaction: Boolean;
    procedure Shutdown;
  end;

  // Transacao. Herda ILzNex para poder fazer Trx.Table('x'),
  // igual ao trx do knex (que e um knex com a conexao fixada).
  // O implementador DEVE fazer ROLLBACK no destrutor se nao houve commit:
  // assim nunca sobra transacao aberta nem conexao vazada.
  ILzNexTransaction = interface(ILzNex)
    ['{9A1C0E10-0010-4C2E-9B01-6E5B2A7F0010}']
    procedure Commit;
    procedure Rollback;
    // Transacao aninhada (savepoint no banco).
    function Savepoint: ILzNexTransaction;
    // Se ja houve commit ou rollback.
    function IsCompleted: Boolean;
    // Nivel de aninhamento (1 = transacao raiz).
    function Level: Integer;
    // A conexao fixada vem de ILzNex.Connection (herdado) -- nao redeclarar.
  end;

implementation

{ TLzNexDdlPlan }

function TLzNexDdlPlan.All: TLzNexFragments;
var
  I, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Pre) + Length(Statements) + Length(Post));
  N := 0;
  for I := 0 to High(Pre) do
  begin
    Result[N] := Pre[I];
    Inc(N);
  end;
  for I := 0 to High(Statements) do
  begin
    Result[N] := Statements[I];
    Inc(N);
  end;
  for I := 0 to High(Post) do
  begin
    Result[N] := Post[I];
    Inc(N);
  end;
end;

function TLzNexDdlPlan.Count: Integer;
begin
  Result := Length(Pre) + Length(Statements) + Length(Post);
end;

end.
