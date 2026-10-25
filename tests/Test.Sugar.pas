unit Test.Sugar;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Client,
  LzNex.Query,
  Test.Helper;

type
  TWhereGroupSugarTest = class(TLzNexTestCase)
  published
    procedure AnyBuildsAClosedOrGroup;
    procedure AllBuildsAClosedAndGroup;
    procedure GroupsDoNotLeakIntoSurroundingPredicates;
    procedure AnyWithNoColumnsRaises;
    procedure AllWithNoColumnsRaises;
  end;

  TSelectAggregateSugarTest = class(TLzNexTestCase)
  published
    procedure SelectCountAddsTheColumnWithoutRunning;
    procedure SelectAggregateAddsTheColumnWithoutRunning;
  end;

  TWithCountSugarTest = class(TLzNexTestCase)
  published
    procedure AddsTheSubqueryAsACountColumn;
    procedure OriginalSubqueryIsNotMutated;
    procedure EmptyAliasRaises;
  end;

  TPagingSugarTest = class(TLzNexTestCase)
  published
    procedure ClearPagingRemovesPagingButKeepsTheRest;
  end;

  TDumpSugarTest = class(TLzNexTestCase)
  published
    procedure IsChainableAndDoesNotChangeTheSQL;
  end;

  TUpsertValidationSugarTest = class(TLzNexTestCase)
  published
    procedure NoRowsRaises;
    procedure NoUniqueByRaises;
  end;

  TUpdateOrInsertValidationSugarTest = class(TLzNexTestCase)
  published
    procedure NoMatchColumnsRaises;
  end;

implementation

procedure TWhereGroupSugarTest.AnyBuildsAClosedOrGroup;
begin
  AssertQuery('select * from `t` where (`a` = ? or `b` = ?)', '1|1',
    NewTestQuery.Table('t').WhereAny(['a', 'b'], '=', 1));
end;

procedure TWhereGroupSugarTest.AllBuildsAClosedAndGroup;
begin
  AssertQuery('select * from `t` where (`a` = ? and `b` = ?)', '1|1',
    NewTestQuery.Table('t').WhereAll(['a', 'b'], '=', 1));
end;

procedure TWhereGroupSugarTest.GroupsDoNotLeakIntoSurroundingPredicates;
begin
  // O grupo fecha sozinho: o Where que vem depois volta a ser um "and" normal,
  // nao contaminado pelo "or" de dentro do grupo.
  AssertQuery(
    'select * from `t` where (`a` = ? or `b` = ?) and (`c` = ? and `d` = ?) and `e` = ?',
    '1|1|2|2|3',
    NewTestQuery.Table('t')
      .WhereAny(['a', 'b'], '=', 1)
      .WhereAll(['c', 'd'], '=', 2)
      .Where('e', 3));
end;

procedure TWhereGroupSugarTest.AnyWithNoColumnsRaises;
begin
  try
    NewTestQuery.Table('t').WhereAny([], '=', 1);
    Fail('expected ELzNexBuilder for an empty column list');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TWhereGroupSugarTest.AllWithNoColumnsRaises;
begin
  try
    NewTestQuery.Table('t').WhereAll([], '=', 1);
    Fail('expected ELzNexBuilder for an empty column list');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TSelectAggregateSugarTest.SelectCountAddsTheColumnWithoutRunning;
begin
  AssertSQL('select count(*) from `t`',
    NewTestQuery.Table('t').SelectCount);
  AssertSQL('select count(*) as `total` from `t`',
    NewTestQuery.Table('t').SelectCount('*', 'total'));
  AssertSQL('select count(`id`) as `n` from `t`',
    NewTestQuery.Table('t').SelectCount('id', 'n'));
end;

procedure TSelectAggregateSugarTest.SelectAggregateAddsTheColumnWithoutRunning;
begin
  AssertSQL('select sum(`score`) as `total` from `t`',
    NewTestQuery.Table('t').SelectAggregate(agSum, 'score', 'total'));
  AssertSQL('select avg(`score`) from `t`',
    NewTestQuery.Table('t').SelectAggregate(agAvg, 'score', ''));
end;

procedure TWithCountSugarTest.AddsTheSubqueryAsACountColumn;
var
  Sub: ILzNexQuery;
begin
  Sub := NewTestQuery.Table('comments').Where('post_id', 1);
  AssertQuery(
    'select (select count(*) from `comments` where `post_id` = ?) as `comment_count` from `posts`',
    '1',
    NewTestQuery.Table('posts').WithCount(Sub, 'comment_count'));
end;

procedure TWithCountSugarTest.OriginalSubqueryIsNotMutated;
var
  Sub: ILzNexQuery;
begin
  Sub := NewTestQuery.Table('comments').Select(['id', 'body']).Where('post_id', 1);
  NewTestQuery.Table('posts').WithCount(Sub, 'comment_count');

  // WithCount usa um clone sem colunas por dentro; a subquery de quem chamou
  // continua devolvendo as colunas e o where originais.
  AssertQuery('select `id`, `body` from `comments` where `post_id` = ?', '1', Sub);
end;

procedure TWithCountSugarTest.EmptyAliasRaises;
var
  Sub: ILzNexQuery;
begin
  Sub := NewTestQuery.Table('comments');
  try
    NewTestQuery.Table('posts').WithCount(Sub, '');
    Fail('expected ELzNexBuilder for an empty alias');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPagingSugarTest.ClearPagingRemovesPagingButKeepsTheRest;
begin
  AssertQuery('select * from `t` where `a` = ? order by `a` asc', '1',
    NewTestQuery.Table('t').Where('a', 1).OrderBy('a').Limit(10).Offset(5).ClearPaging);
end;

procedure TDumpSugarTest.IsChainableAndDoesNotChangeTheSQL;
var
  Query, Chained: ILzNexQuery;
begin
  Query := NewTestQuery.Table('t').Where('a', 1);
  Chained := Query.Dump;

  // Mesmo SQL de antes do Dump.
  AssertSQL('select * from `t` where `a` = ?', Chained);

  // E a mesma query (nao uma copia): encadear depois do Dump afeta o original.
  Chained.Where('b', 2);
  AssertSQL('select * from `t` where `a` = ? and `b` = ?', Query);
end;

procedure TUpsertValidationSugarTest.NoRowsRaises;
begin
  try
    NewTestQuery.Table('t').Upsert([], ['tag'], []);
    Fail('expected ELzNexBuilder for an empty row list');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TUpsertValidationSugarTest.NoUniqueByRaises;
begin
  try
    NewTestQuery.Table('t').Upsert([Vals(['tag', 'a'])], [], []);
    Fail('expected ELzNexBuilder for an empty unique-by column list');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TUpdateOrInsertValidationSugarTest.NoMatchColumnsRaises;
begin
  try
    NewTestQuery.Table('t').UpdateOrInsert(nil, Vals(['score', 1]));
    Fail('expected ELzNexBuilder for an empty match-column list');
  except
    on E: ELzNexBuilder do ;
  end;
end;

initialization
  RegisterTest('sugar', TWhereGroupSugarTest);
  RegisterTest('sugar', TSelectAggregateSugarTest);
  RegisterTest('sugar', TWithCountSugarTest);
  RegisterTest('sugar', TPagingSugarTest);
  RegisterTest('sugar', TDumpSugarTest);
  RegisterTest('sugar', TUpsertValidationSugarTest);
  RegisterTest('sugar', TUpdateOrInsertValidationSugarTest);

end.
