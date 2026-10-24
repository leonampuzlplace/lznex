unit LzNex.Types;

{ Enums e tipos escalares do LzNex. Nao depende de nada -- e a raiz do grafo de units.
  Prefixo de 2 letras por enum: membros de enum compartilham o escopo da unit em
  Pascal, entao prefixo distinto evita colisao. }

{$MODE DELPHI}{$H+}

interface

type
  // A que secao do SQL um statement pertence.
  // A ordem entre grupos nunca importa; a ordem dentro do grupo importa sempre.
  TLzNexStatementGroup = (
    sgColumns,
    sgFrom,
    sgJoin,
    sgWhere,
    sgGroup,
    sgHaving,
    sgOrder,
    sgUnion,
    sgWith,
    sgHint
  );

  // Discriminante concreto do statement. Usado em `case`
  // no compiler, em vez do despacho por string do knex.
  TLzNexStatementKind = (
    skColumn,
    skColumnRaw,
    skColumnSub,
    skAggregate,
    skDistinct,
    skWhereBasic,
    skWhereColumn,
    skWhereIn,
    skWhereInSub,
    skWhereNull,
    skWhereBetween,
    skWhereLike,
    skWhereExists,
    skWhereRaw,
    skWhereGroup,
    skWhereSub,
    skJoin,
    skGroupBy,
    skGroupByRaw,
    skHavingBasic,
    skHavingIn,
    skHavingNull,
    skHavingBetween,
    skHavingRaw,
    skHavingGroup,
    skOrderBy,
    skOrderByRaw,
    skUnion,
    skWith,
    skHint
  );

  // Conector entre dois predicados.
  TLzNexBoolOp = (boAnd, boOr);

  // Tipo de join. jtRaw deixa o texto cru.
  TLzNexJoinType = (
    jtInner,
    jtLeft,
    jtLeftOuter,
    jtRight,
    jtRightOuter,
    jtOuter,
    jtFullOuter,
    jtCross,
    jtRaw
  );

  // Tipo de cada cláusula ON dentro de um join.
  // onColumns compara identificadores; onValue gera bind. Separar os dois
  // resolve a pegadinha on/onVal do knex em tempo de compilacao.
  TLzNexJoinClauseKind = (
    jcColumns,
    jcValue,
    jcIn,
    jcNull,
    jcBetween,
    jcRaw,
    jcUsing
  );

  // O verbo da query. Decide qual metodo de entrada o compiler usa.
  TLzNexQueryMethod = (
    qmSelect,
    qmFirst,
    qmInsert,
    qmUpdate,
    qmDelete,
    qmTruncate
  );

  // Secao emitida pelo compiler. A LISTA e virtual por dialeto
  // (corrige a const de modulo do knex, que obrigou Oracle/MSSQL a duplicar codigo).
  TLzNexComponent = (
    cpHints,
    cpColumns,
    cpFrom,
    cpJoin,
    cpWhere,
    cpGroup,
    cpHaving,
    cpUnion,
    cpOrder,
    cpLimitPrefix,
    cpLimit,
    cpOffset,
    cpLock
  );
  TLzNexComponents = array of TLzNexComponent;

  // Direcao do ORDER BY.
  TLzNexOrderDir = (odAsc, odDesc);

  // Posicao dos NULL na ordenacao.
  TLzNexNullsOrder = (nlDefault, nlFirst, nlLast);

  // Tag de TLzNexValue.
  // vkUnset e DIFERENTE de vkNull: unset em INSERT vira DEFAULT; em WHERE e erro.
  TLzNexValueKind = (
    vkUnset,
    vkNull,
    vkBoolean,
    vkInteger,
    vkInt64,
    vkFloat,
    vkCurrency,
    vkString,
    vkBytes,
    vkDate,
    vkTime,
    vkDateTime,
    vkIdentifier,
    vkRaw,
    vkSubQuery
  );

  // Funcao de agregacao.
  TLzNexAggregate = (agCount, agMin, agMax, agSum, agAvg);

  // Operador de conjunto.
  TLzNexUnionKind = (ukUnion, ukUnionAll, ukIntersect, ukExcept);

  // Travamento de linha no SELECT.
  TLzNexLockMode = (lkNone, lkForUpdate, lkForShare);

  // Comportamento ao encontrar linha travada.
  TLzNexWaitMode = (wtDefault, wtNoWait, wtSkipLocked);

  // Nivel de isolamento da transacao.
  TLzNexIsolation = (
    ilDefault,
    ilReadUncommitted,
    ilReadCommitted,
    ilRepeatableRead,
    ilSerializable
  );

  // Tipo logico de coluna no schema builder. O dialeto traduz.
  TLzNexColumnType = (
    ctIncrements,
    ctBigIncrements,
    ctTinyInt,
    ctSmallInt,
    ctMediumInt,
    ctInteger,
    ctBigInt,
    ctBoolean,
    ctDecimal,
    ctFloat,
    ctDouble,
    ctChar,
    ctString,
    ctTinyText,
    ctText,
    ctMediumText,
    ctLongText,
    ctBinary,
    ctBlob,
    ctDate,
    ctTime,
    ctDateTime,
    ctTimestamp,
    ctJson,
    ctJsonb,
    ctUuid,
    ctEnum,
    ctSpecific
  );

  // Modificador de coluna. A ORDEM de emissao e definida
  // pelo dialeto, nao pela ordem de chamada do usuario (senao sai DDL invalido).
  TLzNexColumnModifier = (
    mdUnsigned,
    mdNullable,
    mdDefault,
    mdComment,
    mdCollate,
    mdFirst,
    mdAfter,
    mdPrimaryKey,
    mdAutoIncrement
  );
  TLzNexColumnModifiers = array of TLzNexColumnModifier;

  // O que o table builder vai emitir.
  TLzNexTableMethod = (tmCreate, tmAlter);

  // Tipo de indice/constraint. Usado no nome automatico
  // (<tabela>_<colunas>_<tipo>, convencao copiada do knex).
  TLzNexIndexKind = (ixIndex, ixUnique, ixPrimary, ixForeign);

  // O que fazer no conflito de chave no INSERT.
  TLzNexConflictAction = (caNone, caIgnore, caMerge);

  // Sentido da migration.
  TLzNexMigrationDirection = (mdUp, mdDown);

const
  // Operadores aceitos em WHERE/HAVING/ON. Lista FECHADA: operador fora dela
  // levanta excecao, o que fecha a porta para injecao via operador.
  LZNEX_OPERATORS: array[0..27] of string = (
    '=', '<', '>', '<=', '>=', '<>', '!=', '<=>',
    'like', 'not like', 'ilike', 'not ilike',
    'between', 'not between',
    'in', 'not in',
    'is', 'is not',
    'exists', 'not exists',
    'rlike', 'not rlike', 'regexp', 'not regexp',
    '&', '|', '^', '~'
  );

  // Nome default das tabelas de controle de migration (configuravel).
  LZNEX_MIGRATIONS_TABLE = 'migrations';
  LZNEX_MIGRATIONS_LOCK_SUFFIX = '_lock';   // -> migrations_lock

  // Placeholder posicional. O Zeos aceita '?' em MySQL, PostgreSQL e Firebird,
  // mas o hook de reposicionamento existe no client para quem precisar de $n.
  LZNEX_PLACEHOLDER = '?';

implementation

end.
