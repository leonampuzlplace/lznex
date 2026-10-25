unit LzNex.Types;

{$MODE DELPHI}{$H+}

interface

type

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
    skOrderByRandom,
    skUnion,
    skWith,
    skHint,
    skWhereDatePart,
    skWhereJson,
    skWhereFullText
  );

  { Parte da data a comparar. Cada banco extrai de um jeito (extract, year(),
    strftime), por isso e o compilador do dialeto que resolve. }
  TLzNexDatePart = (
    dpDate,
    dpTime,
    dpYear,
    dpMonth,
    dpDay,
    dpHour,
    dpMinute,
    dpSecond
  );

  { joPath compara o valor no caminho; joContains pergunta se o documento
    contem o valor; joLength compara o tamanho do array. }
  TLzNexJsonOp = (joPath, joContains, joLength);

  // Natural: as palavras como texto. Boolean: a sintaxe de operadores do banco.
  TLzNexFullTextMode = (ftNatural, ftBoolean);

  TLzNexBoolOp = (boAnd, boOr);

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

  TLzNexJoinClauseKind = (
    jcColumns,
    jcValue,
    jcIn,
    jcNull,
    jcBetween,
    jcRaw,
    jcUsing
  );

  TLzNexQueryMethod = (
    qmSelect,
    qmFirst,
    qmInsert,
    qmUpdate,
    qmDelete,
    qmTruncate
  );

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

  TLzNexOrderDir = (odAsc, odDesc);

  TLzNexNullsOrder = (nlDefault, nlFirst, nlLast);

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

  TLzNexAggregate = (agCount, agMin, agMax, agSum, agAvg);

  TLzNexUnionKind = (ukUnion, ukUnionAll, ukIntersect, ukExcept);

  TLzNexLockMode = (lkNone, lkForUpdate, lkForShare);

  TLzNexWaitMode = (wtDefault, wtNoWait, wtSkipLocked);

  TLzNexIsolation = (
    ilDefault,
    ilReadUncommitted,
    ilReadCommitted,
    ilRepeatableRead,
    ilSerializable
  );

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

  TLzNexTableMethod = (tmCreate, tmAlter);

  TLzNexIndexKind = (ixIndex, ixUnique, ixPrimary, ixForeign, ixFullText);

  TLzNexConflictAction = (caNone, caIgnore, caMerge);

  TLzNexMigrationDirection = (mdUp, mdDown);

const

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

  LZNEX_MIGRATIONS_TABLE = 'migrations';
  LZNEX_MIGRATIONS_LOCK_SUFFIX = '_lock';

  LZNEX_PLACEHOLDER = '?';

implementation

end.
