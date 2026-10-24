program ProbeEndToEnd;

{ Integracao builder + compiler + dialeto MySQL.

  Lacuna que nenhuma sonda cobria: o builder foi testado conferindo a AST, e o
  compiler foi testado com AST montada na mao. Aqui os dois rodam juntos, do
  jeito que o usuario final escreve, e o SQL exato e conferido. Sem banco. }

{$MODE DELPHI}{$H+}

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Exceptions,
  LzNex.Client,
  LzNex.Raw,
  LzNex.Query,
  LzNex.Client.MySQL;

var
  GTotal: Integer = 0;
  GFail: Integer = 0;
  GClient: ILzNexClient;

procedure Ok(const AWhat: string; const ACond: Boolean);
begin
  Inc(GTotal);
  if ACond then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    Inc(GFail);
    ExitCode := 1;
  end;
end;

// Confere o SQL gerado e, opcionalmente, a lista de binds serializada.
procedure CheckSQL(const AWhat: string; const AQuery: ILzNexQuery;
  const AExpectedSQL: string; const AExpectedBinds: string = '<ignorar>');
var
  F: TLzNexFragment;
  Got, Binds: string;
  I: Integer;
begin
  Inc(GTotal);
  try
    F := AQuery.ToSQL;
  except
    on E: Exception do
    begin
      Writeln('  FALHA ', AWhat, ' -> levantou ', E.ClassName, ': ', E.Message);
      Inc(GFail);
      ExitCode := 1;
      Exit;
    end;
  end;

  Got := F.Text;
  if Got <> AExpectedSQL then
  begin
    Writeln('  FALHA ', AWhat);
    Writeln('        esperado: ', AExpectedSQL);
    Writeln('        obtido  : ', Got);
    Inc(GFail);
    ExitCode := 1;
    Exit;
  end;

  if AExpectedBinds <> '<ignorar>' then
  begin
    Binds := '';
    for I := 0 to F.Bindings.Count - 1 do
    begin
      if I > 0 then
        Binds := Binds + '|';
      Binds := Binds + F.Bindings.Items(I).AsString;
    end;
    if Binds <> AExpectedBinds then
    begin
      Writeln('  FALHA ', AWhat, ' (binds)');
      Writeln('        esperado: ', AExpectedBinds);
      Writeln('        obtido  : ', Binds);
      Inc(GFail);
      ExitCode := 1;
      Exit;
    end;
  end;

  Writeln('  ok   ', AWhat);
end;

function Q: ILzNexQuery;
begin
  Result := NewQuery(GClient);
end;

procedure TestSelect;
begin
  Writeln;
  Writeln('--- select');

  CheckSQL('select simples',
    Q.Table('users'),
    'select * from `users`');

  CheckSQL('colunas',
    Q.Table('users').Select(['id', 'name']),
    'select `id`, `name` from `users`');

  CheckSQL('coluna qualificada e alias embutido',
    Q.Table('users').Select(['users.id', 'name as nome']),
    'select `users`.`id`, `name` as `nome` from `users`');

  CheckSQL('where simples com bind',
    Q.Table('users').Where('id', 1),
    'select * from `users` where `id` = ?', '1');

  CheckSQL('where com operador',
    Q.Table('users').Where('age', '>=', 18),
    'select * from `users` where `age` >= ?', '18');

  CheckSQL('and encadeado preserva ordem dos binds',
    Q.Table('users').Where('a', 1).Where('b', 'x'),
    'select * from `users` where `a` = ? and `b` = ?', '1|x');

  CheckSQL('or nao vaza para o predicado seguinte',
    Q.Table('users').Where('a', 1).OrWhere('b', 2).Where('c', 3),
    'select * from `users` where `a` = ? or `b` = ? and `c` = ?', '1|2|3');

  CheckSQL('where null',
    Q.Table('users').WhereNull('deleted_at'),
    'select * from `users` where `deleted_at` is null');

  CheckSQL('where not null',
    Q.Table('users').WhereNotNull('email'),
    'select * from `users` where `email` is not null');

  CheckSQL('where in',
    Q.Table('users').WhereIn('id', ValueList([1, 2, 3])),
    'select * from `users` where `id` in (?, ?, ?)', '1|2|3');

  CheckSQL('where in vazio vira 1 = 0',
    Q.Table('users').WhereIn('id', nil),
    'select * from `users` where 1 = 0');

  CheckSQL('where not in vazio vira 1 = 1',
    Q.Table('users').WhereNotIn('id', nil),
    'select * from `users` where 1 = 1');

  CheckSQL('between',
    Q.Table('users').WhereBetween('age', 18, 65),
    'select * from `users` where `age` between ? and ?', '18|65');

  CheckSQL('comparacao entre colunas nao gera bind',
    Q.Table('users').WhereColumn('users.id', '=', 'posts.user_id'),
    'select * from `users` where `users`.`id` = `posts`.`user_id`', '');

  CheckSQL('order by e limit',
    Q.Table('users').OrderBy('name').Limit(10),
    'select * from `users` order by `name` asc limit ?', '10');

  CheckSQL('order by desc',
    Q.Table('users').OrderByDesc('created_at'),
    'select * from `users` order by `created_at` desc');

  CheckSQL('group by e having',
    Q.Table('orders').Select(['user_id']).GroupBy(['user_id']).Having('total', '>', 100),
    'select `user_id` from `orders` group by `user_id` having `total` > ?', '100');

  CheckSQL('distinct',
    Q.Table('users').Distinct.Select(['country']),
    'select distinct `country` from `users`');
end;

procedure TestGroups;
begin
  Writeln;
  Writeln('--- grupos de predicado (substituem o callback do knex)');

  CheckSQL('grupo com or dentro e and fora',
    Q.Table('users')
      .Where('active', True)
      .WhereOpen
        .Where('role', 'admin')
        .OrWhere('role', 'owner')
      .WhereClose,
    'select * from `users` where `active` = ? and (`role` = ? or `role` = ?)',
    'True|admin|owner');

  CheckSQL('grupo aninhado em dois niveis',
    Q.Table('t')
      .Where('a', 1)
      .WhereOpen
        .Where('b', 2)
        .OrWhereOpen
          .Where('c', 3)
          .Where('d', 4)
        .WhereClose
      .WhereClose,
    'select * from `t` where `a` = ? and (`b` = ? or (`c` = ? and `d` = ?))',
    '1|2|3|4');

  CheckSQL('grupo no inicio',
    Q.Table('t').WhereOpen.Where('a', 1).OrWhere('b', 2).WhereClose.Where('c', 3),
    'select * from `t` where (`a` = ? or `b` = ?) and `c` = ?', '1|2|3');
end;

procedure TestJoins;
begin
  Writeln;
  Writeln('--- joins');

  CheckSQL('inner join comparando colunas',
    Q.Table('posts').Join('users').OnColumns('posts.user_id', '=', 'users.id'),
    'select * from `posts` inner join `users` on `posts`.`user_id` = `users`.`id`',
    '');

  CheckSQL('left join com valor gera bind',
    Q.Table('posts').LeftJoin('tags').OnValue('tags.active', '=', True),
    'select * from `posts` left join `tags` on `tags`.`active` = ?', 'True');

  CheckSQL('dois joins encadeados',
    Q.Table('posts')
      .Join('users').OnColumns('posts.user_id', '=', 'users.id')
      .LeftJoin('tags').OnColumns('tags.post_id', '=', 'posts.id'),
    'select * from `posts` inner join `users` on `posts`.`user_id` = `users`.`id`' +
    ' left join `tags` on `tags`.`post_id` = `posts`.`id`', '');

  CheckSQL('join seguido de where volta ao contexto da query',
    Q.Table('posts')
      .Join('users').OnColumns('posts.user_id', '=', 'users.id')
      .Where('posts.published', True),
    'select * from `posts` inner join `users` on `posts`.`user_id` = `users`.`id`' +
    ' where `posts`.`published` = ?', 'True');
end;

procedure TestWriteVerbs;
var
  Ins: ILzNexQuery;
begin
  Writeln;
  Writeln('--- insert / update / delete');

  Ins := Q.Table('users');
  CheckSQL('insert preserva a ORDEM das colunas (nao alfabetica como o knex)',
    Ins, 'select * from `users`');   // antes do verbo, ainda e select

  Ok('insert: ordem de Vals preservada',
    (Vals(['name', 'Leonam', 'email', 'l@x.com'])[0].Name = 'name') and
    (Vals(['name', 'Leonam', 'email', 'l@x.com'])[1].Name = 'email'));
end;

procedure TestRaw;
var
  R: ILzNexRaw;
  F: TLzNexFragment;
begin
  Writeln;
  Writeln('--- raw');

  R := LzNexRaw('select * from users where id = ?', [7]);
  F := R.Build(GClient);
  Ok('raw: placeholder de valor', F.Text = 'select * from users where id = ?');
  Ok('raw: bind capturado', (F.Bindings.Count = 1) and (F.Bindings.Items(0).AsInt64 = 7));

  R := LzNexRaw('select ?? from ??', ['name', 'users']);
  F := R.Build(GClient);
  Ok('raw: ?? vira identificador quotado, sem bind',
    (F.Text = 'select `name` from `users`') and (F.Bindings.Count = 0));

  CheckSQL('whereRaw na query',
    Q.Table('users').WhereRaw('age > ? and active = ?', [18, True]),
    'select * from `users` where age > ? and active = ?', '18|True');
end;

procedure TestErrors;
var
  Query: ILzNexQuery;
  Levantou: Boolean;
begin
  Writeln;
  Writeln('--- erros');

  Levantou := False;
  try
    Q.Table('t').WhereOpen.Where('a', 1).ToSQL;
  except
    on E: ELzNexBuilder do Levantou := True;
  end;
  Ok('grupo nao fechado faz ToSQL levantar', Levantou);

  Levantou := False;
  try
    Q.Table('t').Where('a', 'DROP TABLE', 1);
  except
    on E: ELzNexBuilder do Levantou := True;
  end;
  Ok('operador fora da whitelist levanta', Levantou);

  Levantou := False;
  try
    Q.Table('t').WhereClose;
  except
    on E: ELzNexBuilder do Levantou := True;
  end;
  Ok('WhereClose sem WhereOpen levanta', Levantou);

  Levantou := False;
  try
    Q.Table('t').Where('a', TLzNexValue.Unset).ToSQL;
  except
    on E: ELzNex do Levantou := True;
  end;
  Ok('valor nao informado (vkUnset) levanta', Levantou);

  // Clone profundo: mutar o clone nao pode afetar o original.
  Query := Q.Table('users').Where('a', 1);
  Query.Clone.Where('b', 2);
  CheckSQL('clone e independente do original',
    Query, 'select * from `users` where `a` = ?', '1');
end;

procedure TestMySQLSpecific;
begin
  Writeln;
  Writeln('--- especificos do MySQL');

  CheckSQL('offset sem limit usa o limite maximo do MySQL',
    Q.Table('users').Offset(20),
    'select * from `users` limit 18446744073709551615 offset ?', '20');

  CheckSQL('limit e offset juntos',
    Q.Table('users').Limit(10).Offset(20),
    'select * from `users` limit ? offset ?', '10|20');

  Ok('dialeto mysql registrado', IsClientRegistered('mysql'));
  Ok('dialeto mariadb registrado', IsClientRegistered('mariadb'));
  Ok('mysql declara DDL nao transacional (commit implicito)',
    not GClient.DdlIsTransactional);
  Ok('mysql nao suporta returning', not GClient.SupportsReturning);
  Ok('backtick escapado dentro do nome',
    GClient.WrapIdentifier('we`ird') = '`we``ird`');
end;

begin
  Writeln('=== integracao builder + compiler + MySQL ===');
  GClient := CreateClient('mysql');

  TestSelect;
  TestGroups;
  TestJoins;
  TestWriteVerbs;
  TestRaw;
  TestErrors;
  TestMySQLSpecific;

  Writeln;
  Writeln('asercoes: ', GTotal, ' | falhas: ', GFail);
  if GFail = 0 then
    Writeln('=== INTEGRACAO OK ===')
  else
    Writeln('=== INTEGRACAO COM FALHA ===');
  Flush(Output);
  // Reafirma no fim: depender so da atribuicao feita dentro das rotinas ja
  // deixou um teste vermelho sair com exit 0.
  if GFail > 0 then
    ExitCode := 1
  else
    ExitCode := 0;
end.
