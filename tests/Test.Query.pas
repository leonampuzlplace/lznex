unit Test.Query;

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
  LzNex.Raw,
  LzNex.Query,
  Test.Helper;

type
  TSelectTest = class(TLzNexTestCase)
  published
    procedure SelectWithoutColumns;
    procedure SelectWithColumns;
    procedure QualifiedName;
    procedure InlineAliasInString;
    procedure ExplicitAlias;
    procedure SelectDistinct;
  end;

  TWhereTest = class(TLzNexTestCase)
  published
    procedure Equality;
    procedure ExplicitOperator;
    procedure AndKeepsBindingOrder;
    procedure OrDoesNotLeakIntoNextPredicate;
    procedure Negation;
    procedure NullChecks;
    procedure InList;
    procedure EmptyInListBecomesFalse;
    procedure EmptyNotInListBecomesTrue;
    procedure BetweenRange;
    procedure ColumnComparisonCreatesNoBinding;
    procedure LikePattern;
  end;

  TPredicateGroupTest = class(TLzNexTestCase)
  published
    procedure SimpleGroup;
    procedure NestedGroup;
    procedure LeadingGroup;
    procedure UnclosedGroupRaises;
    procedure ClosingWithoutOpeningRaises;
  end;

  TJoinTest = class(TLzNexTestCase)
  published
    procedure InnerJoinComparesColumns;
    procedure LeftJoinWithValueCreatesBinding;
    procedure TwoChainedJoins;
    procedure JoinFollowedByWhere;
  end;

  TOrderAndPagingTest = class(TLzNexTestCase)
  published
    procedure OrderAscending;
    procedure OrderDescending;
    procedure LimitAndOffset;
    procedure OffsetWithoutLimitUsesMySQLWorkaround;
    procedure GroupByWithHaving;
  end;

  TRawTest = class(TLzNexTestCase)
  published
    procedure ValuePlaceholder;
    procedure IdentifierPlaceholder;
    procedure RawInsideWhere;
    procedure WrongPlaceholderCountRaises;
  end;

  TSecurityTest = class(TLzNexTestCase)
  published
    procedure OperatorOutsideWhitelistRaises;
    procedure UnsetValueRaises;
    procedure BacktickIsEscapedInIdentifier;
    procedure ValueIsNeverInlinedIntoSQL;
  end;

  TCloneTest = class(TLzNexTestCase)
  published
    procedure CloneDoesNotAffectOriginal;
    procedure OriginalDoesNotAffectClone;
  end;

  TDialectTest = class(TLzNexTestCase)
  published
    procedure MySQLIsRegistered;
    procedure MariaDBIsRegistered;
    procedure UnknownDialectRaises;
    procedure MySQLReportsNonTransactionalDdl;
    procedure MySQLDoesNotSupportReturning;
  end;

implementation

{ TSelectTest }

procedure TSelectTest.SelectWithoutColumns;
begin
  AssertSQL('select * from `users`', NewTestQuery.Table('users'));
end;

procedure TSelectTest.SelectWithColumns;
begin
  AssertSQL('select `id`, `name` from `users`',
    NewTestQuery.Table('users').Select(['id', 'name']));
end;

procedure TSelectTest.QualifiedName;
begin
  AssertSQL('select `users`.`id` from `users`',
    NewTestQuery.Table('users').Select(['users.id']));
end;

procedure TSelectTest.InlineAliasInString;
begin
  // Regressao: FindAliasSeparator ja comeu o primeiro caractere do alias.
  AssertSQL('select `name` as `nick` from `users`',
    NewTestQuery.Table('users').Select(['name as nick']));
end;

procedure TSelectTest.ExplicitAlias;
begin
  AssertSQL('select `name` as `nick` from `users`',
    NewTestQuery.Table('users').SelectAs('name', 'nick'));
end;

procedure TSelectTest.SelectDistinct;
begin
  AssertSQL('select distinct `country` from `users`',
    NewTestQuery.Table('users').Distinct.Select(['country']));
end;

{ TWhereTest }

procedure TWhereTest.Equality;
begin
  AssertQuery('select * from `users` where `id` = ?', '1',
    NewTestQuery.Table('users').Where('id', 1));
end;

procedure TWhereTest.ExplicitOperator;
begin
  AssertQuery('select * from `users` where `age` >= ?', '18',
    NewTestQuery.Table('users').Where('age', '>=', 18));
end;

procedure TWhereTest.AndKeepsBindingOrder;
begin
  AssertQuery('select * from `users` where `a` = ? and `b` = ?', '1|x',
    NewTestQuery.Table('users').Where('a', 1).Where('b', 'x'));
end;

procedure TWhereTest.OrDoesNotLeakIntoNextPredicate;
begin
  // No knex o flag de OR era destrutivo; aqui e parametro explicito.
  AssertSQL('select * from `t` where `a` = ? or `b` = ? and `c` = ?',
    NewTestQuery.Table('t').Where('a', 1).OrWhere('b', 2).Where('c', 3));
end;

procedure TWhereTest.Negation;
begin
  AssertSQL('select * from `t` where not `a` = ?',
    NewTestQuery.Table('t').WhereNot('a', 1));
end;

procedure TWhereTest.NullChecks;
begin
  AssertSQL('select * from `t` where `a` is null',
    NewTestQuery.Table('t').WhereNull('a'));
  AssertSQL('select * from `t` where `a` is not null',
    NewTestQuery.Table('t').WhereNotNull('a'));
end;

procedure TWhereTest.InList;
begin
  AssertQuery('select * from `t` where `id` in (?, ?, ?)', '1|2|3',
    NewTestQuery.Table('t').WhereIn('id', ValueList([1, 2, 3])));
end;

procedure TWhereTest.EmptyInListBecomesFalse;
begin
  // Mesma semantica do knex: IN de lista vazia nao casa com nada.
  AssertSQL('select * from `t` where 1 = 0',
    NewTestQuery.Table('t').WhereIn('id', nil));
end;

procedure TWhereTest.EmptyNotInListBecomesTrue;
begin
  AssertSQL('select * from `t` where 1 = 1',
    NewTestQuery.Table('t').WhereNotIn('id', nil));
end;

procedure TWhereTest.BetweenRange;
begin
  AssertQuery('select * from `t` where `age` between ? and ?', '18|65',
    NewTestQuery.Table('t').WhereBetween('age', 18, 65));
end;

procedure TWhereTest.ColumnComparisonCreatesNoBinding;
begin
  AssertQuery('select * from `t` where `a`.`id` = `b`.`a_id`', '',
    NewTestQuery.Table('t').WhereColumn('a.id', '=', 'b.a_id'));
end;

procedure TWhereTest.LikePattern;
begin
  AssertQuery('select * from `t` where `name` like ?', '%jo%',
    NewTestQuery.Table('t').WhereLike('name', '%jo%'));
end;

{ TPredicateGroupTest }

procedure TPredicateGroupTest.SimpleGroup;
begin
  AssertQuery(
    'select * from `users` where `active` = ? and (`role` = ? or `role` = ?)',
    'True|admin|owner',
    NewTestQuery.Table('users').Where('active', True)
      .WhereOpen.Where('role', 'admin').OrWhere('role', 'owner').WhereClose);
end;

procedure TPredicateGroupTest.NestedGroup;
begin
  AssertQuery(
    'select * from `t` where `a` = ? and (`b` = ? or (`c` = ? and `d` = ?))',
    '1|2|3|4',
    NewTestQuery.Table('t').Where('a', 1)
      .WhereOpen
        .Where('b', 2)
        .OrWhereOpen.Where('c', 3).Where('d', 4).WhereClose
      .WhereClose);
end;

procedure TPredicateGroupTest.LeadingGroup;
begin
  AssertSQL('select * from `t` where (`a` = ? or `b` = ?) and `c` = ?',
    NewTestQuery.Table('t')
      .WhereOpen.Where('a', 1).OrWhere('b', 2).WhereClose.Where('c', 3));
end;

procedure TPredicateGroupTest.UnclosedGroupRaises;
begin
  try
    NewTestQuery.Table('t').WhereOpen.Where('a', 1).ToSQL;
    Fail('expected ELzNexBuilder for unclosed group');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TPredicateGroupTest.ClosingWithoutOpeningRaises;
begin
  try
    NewTestQuery.Table('t').WhereClose;
    Fail('expected ELzNexBuilder when closing a group that was never opened');
  except
    on E: ELzNexBuilder do ;
  end;
end;

{ TJoinTest }

procedure TJoinTest.InnerJoinComparesColumns;
begin
  AssertQuery(
    'select * from `posts` inner join `users` on `posts`.`user_id` = `users`.`id`', '',
    NewTestQuery.Table('posts').Join('users')
      .OnColumns('posts.user_id', '=', 'users.id'));
end;

procedure TJoinTest.LeftJoinWithValueCreatesBinding;
begin
  // OnValue e OnColumns sao separados de proposito: no knex, on('a', true)
  // comparava com o IDENTIFICADOR "true".
  AssertQuery('select * from `posts` left join `tags` on `tags`.`active` = ?', 'True',
    NewTestQuery.Table('posts').LeftJoin('tags').OnValue('tags.active', '=', True));
end;

procedure TJoinTest.TwoChainedJoins;
begin
  AssertSQL(
    'select * from `posts` inner join `users` on `posts`.`user_id` = `users`.`id`' +
    ' left join `tags` on `tags`.`post_id` = `posts`.`id`',
    NewTestQuery.Table('posts')
      .Join('users').OnColumns('posts.user_id', '=', 'users.id')
      .LeftJoin('tags').OnColumns('tags.post_id', '=', 'posts.id'));
end;

procedure TJoinTest.JoinFollowedByWhere;
begin
  AssertSQL(
    'select * from `posts` inner join `users` on `posts`.`user_id` = `users`.`id`' +
    ' where `posts`.`published` = ?',
    NewTestQuery.Table('posts')
      .Join('users').OnColumns('posts.user_id', '=', 'users.id')
      .Where('posts.published', True));
end;

{ TOrderAndPagingTest }

procedure TOrderAndPagingTest.OrderAscending;
begin
  AssertSQL('select * from `t` order by `name` asc',
    NewTestQuery.Table('t').OrderBy('name'));
end;

procedure TOrderAndPagingTest.OrderDescending;
begin
  AssertSQL('select * from `t` order by `name` desc',
    NewTestQuery.Table('t').OrderByDesc('name'));
end;

procedure TOrderAndPagingTest.LimitAndOffset;
begin
  AssertQuery('select * from `t` limit ? offset ?', '10|20',
    NewTestQuery.Table('t').Limit(10).Offset(20));
end;

procedure TOrderAndPagingTest.OffsetWithoutLimitUsesMySQLWorkaround;
begin
  // O MySQL exige LIMIT quando ha OFFSET; o valor e o maximo de 64 bits.
  AssertSQL('select * from `t` limit 18446744073709551615 offset ?',
    NewTestQuery.Table('t').Offset(20));
end;

procedure TOrderAndPagingTest.GroupByWithHaving;
begin
  AssertQuery(
    'select `user_id` from `orders` group by `user_id` having `total` > ?', '100',
    NewTestQuery.Table('orders').Select(['user_id']).GroupBy(['user_id'])
      .Having('total', '>', 100));
end;

{ TRawTest }

procedure TRawTest.ValuePlaceholder;
var
  Fragment: TLzNexFragment;
begin
  Fragment := LzNexRaw('select * from t where id = ?', [7]).Build(FClient);
  AssertEquals('select * from t where id = ?', Fragment.Text);
  AssertEquals('7', BindingsOf(Fragment));
end;

procedure TRawTest.IdentifierPlaceholder;
var
  Fragment: TLzNexFragment;
begin
  // '??' vira identificador quotado e NAO gera bind.
  Fragment := LzNexRaw('select ?? from ??', ['name', 'users']).Build(FClient);
  AssertEquals('select `name` from `users`', Fragment.Text);
  AssertEquals(0, Fragment.Bindings.Count);
end;

procedure TRawTest.RawInsideWhere;
begin
  AssertQuery('select * from `t` where age > ? and active = ?', '18|True',
    NewTestQuery.Table('t').WhereRaw('age > ? and active = ?', [18, True]));
end;

procedure TRawTest.WrongPlaceholderCountRaises;
begin
  try
    LzNexRaw('? ?', [1]).Build(FClient);
    Fail('expected an exception for wrong placeholder count');
  except
    on E: ELzNex do ;
  end;
end;

{ TSecurityTest }

procedure TSecurityTest.OperatorOutsideWhitelistRaises;
begin
  // A whitelist e fechada para operador vindo de entrada do usuario nao virar
  // injecao.
  try
    NewTestQuery.Table('t').Where('a', '; drop table users; --', 1);
    Fail('expected ELzNexBuilder for invalid operator');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TSecurityTest.UnsetValueRaises;
begin
  try
    NewTestQuery.Table('t').Where('a', TLzNexValue.Unset).ToSQL;
    Fail('expected an exception for unset value');
  except
    on E: ELzNex do ;
  end;
end;

procedure TSecurityTest.BacktickIsEscapedInIdentifier;
begin
  AssertEquals('`we``ird`', FClient.WrapIdentifier('we`ird'));
end;

procedure TSecurityTest.ValueIsNeverInlinedIntoSQL;
var
  Fragment: TLzNexFragment;
begin
  Fragment := NewTestQuery.Table('users')
    .Where('name', '''; drop table users; --').ToSQL;
  AssertEquals('select * from `users` where `name` = ?', Fragment.Text);
  AssertEquals(1, Fragment.Bindings.Count);
  AssertEquals('''; drop table users; --', Fragment.Bindings.Items(0).AsString);
end;

{ TCloneTest }

procedure TCloneTest.CloneDoesNotAffectOriginal;
var
  Original: ILzNexQuery;
begin
  Original := NewTestQuery.Table('users').Where('a', 1);
  Original.Clone.Where('b', 2);
  AssertSQL('select * from `users` where `a` = ?', Original);
end;

procedure TCloneTest.OriginalDoesNotAffectClone;
var
  Original, Copy: ILzNexQuery;
begin
  Original := NewTestQuery.Table('users').Where('a', 1);
  Copy := Original.Clone;
  Original.Where('b', 2);
  AssertSQL('select * from `users` where `a` = ?', Copy);
end;

{ TDialectTest }

procedure TDialectTest.MySQLIsRegistered;
begin
  AssertTrue(IsClientRegistered('mysql'));
end;

procedure TDialectTest.MariaDBIsRegistered;
begin
  AssertTrue(IsClientRegistered('mariadb'));
end;

procedure TDialectTest.UnknownDialectRaises;
begin
  try
    CreateClient('oracle-ish');
    Fail('expected ELzNexConfig for unregistered dialect');
  except
    on E: ELzNexConfig do ;
  end;
end;

procedure TDialectTest.MySQLReportsNonTransactionalDdl;
begin
  // MySQL faz COMMIT IMPLICITO em DDL: o migrator usa isso para avisar.
  AssertFalse(FClient.DdlIsTransactional);
end;

procedure TDialectTest.MySQLDoesNotSupportReturning;
begin
  AssertFalse(FClient.SupportsReturning);
end;

initialization
  RegisterTest('query', TSelectTest);
  RegisterTest('query', TWhereTest);
  RegisterTest('query', TPredicateGroupTest);
  RegisterTest('query', TJoinTest);
  RegisterTest('query', TOrderAndPagingTest);
  RegisterTest('query', TRawTest);
  RegisterTest('query', TCloneTest);
  RegisterTest('security', TSecurityTest);
  RegisterTest('dialect', TDialectTest);

end.
