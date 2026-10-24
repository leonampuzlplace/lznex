program ProbeQuery;

{ Sonda do builder e do raw.

  O compiler e de outro agente, logo aqui se confere a AST PRODUZIDA, nunca o
  SQL. O unico ponto que precisa de dialeto e o Raw.Build, atendido por um
  TLzNexClientBase minimo definido aqui mesmo. }

{$MODE DELPHI}{$H+}

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Client,
  LzNex.Exceptions,
  LzNex.Raw,
  LzNex.Query;

type
  // Dialeto de sonda: so os defaults ANSI da classe base. Sem compiler, porque
  // nenhuma asercao aqui chega a compilar SQL.
  TProbeClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;
    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

function TProbeClient.DialectName: string;
begin
  Result := 'probe';
end;

function TProbeClient.ZeosProtocol: string;
begin
  Result := 'probe';
end;

function TProbeClient.NewCompiler: ILzNexCompiler;
begin
  Result := nil;
end;

function TProbeClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := nil;
end;

var
  Checks: Integer = 0;

procedure Check(const AWhat: string; ACond: Boolean);
begin
  Inc(Checks);
  if ACond then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    ExitCode := 1;
  end;
end;

var
  Cli: ILzNexClient;

// Where de cada familia cai em sgWhere com o Kind certo.
procedure TestWhereFamilies;
var
  Q: ILzNexQuery;
  A: TLzNexAst;
  Sub: ILzNexQuery;
begin
  Writeln('-- familias de where --');
  Sub := NewQuery(Cli).Table('logs');

  Q := NewQuery(Cli).Table('users');
  Q := Q.Where('id', 1);
  Q := Q.Where('age', '>=', 18);
  Q := Q.WhereColumn('a.x', '=', 'b.y');
  Q := Q.WhereIn('status', ValueList(['a', 'b']));
  Q := Q.WhereNull('deleted_at');
  Q := Q.WhereBetween('age', 18, 60);
  Q := Q.WhereLike('nome', '%ana%');
  Q := Q.WhereExists(Sub);
  Q := Q.WhereRaw('x = ?', [9]);
  Q := Q.WhereInSub('tenant_id', Sub);

  A := Q.Ast;
  Check('10 predicados no grupo sgWhere', A.CountOf(sgWhere) = 10);
  Check('todos em sgWhere', A.Group(sgWhere)[0].Group = sgWhere);
  Check('Where -> skWhereBasic', A.Group(sgWhere)[0].Kind = skWhereBasic);
  Check('Where com operador normaliza o op',
    TLzNexBasicStmt(A.Group(sgWhere)[1]).Op = '>=');
  Check('WhereColumn -> basic com AsColumn',
    (A.Group(sgWhere)[2].Kind = skWhereBasic) and
    TLzNexBasicStmt(A.Group(sgWhere)[2]).AsColumn and
    not TLzNexBasicStmt(A.Group(sgWhere)[2]).Value.IsBindable);
  Check('WhereIn -> skWhereIn', A.Group(sgWhere)[3].Kind = skWhereIn);
  Check('WhereIn guarda os 2 valores',
    Length(TLzNexInStmt(A.Group(sgWhere)[3]).Values) = 2);
  Check('WhereNull -> skWhereNull', A.Group(sgWhere)[4].Kind = skWhereNull);
  Check('WhereBetween -> skWhereBetween', A.Group(sgWhere)[5].Kind = skWhereBetween);
  Check('WhereBetween guarda Lo e Hi',
    (TLzNexBetweenStmt(A.Group(sgWhere)[5]).Lo.AsInt64 = 18) and
    (TLzNexBetweenStmt(A.Group(sgWhere)[5]).Hi.AsInt64 = 60));
  Check('WhereLike -> skWhereLike', A.Group(sgWhere)[6].Kind = skWhereLike);
  Check('WhereExists -> skWhereExists', A.Group(sgWhere)[7].Kind = skWhereExists);
  Check('WhereExists guarda a subquery',
    TLzNexExistsStmt(A.Group(sgWhere)[7]).Sub <> nil);
  Check('WhereRaw -> skWhereRaw', A.Group(sgWhere)[8].Kind = skWhereRaw);
  Check('WhereRaw guarda o ILzNexRaw',
    TLzNexRawStmt(A.Group(sgWhere)[8]).Raw <> nil);
  Check('WhereInSub -> skWhereIn com Sub',
    (A.Group(sgWhere)[9].Kind = skWhereIn) and
    (TLzNexInStmt(A.Group(sgWhere)[9]).Sub <> nil));

  // ILike e NotLike compartilham a classe, mudando as flags
  Q := NewQuery(Cli).Table('users').WhereILike('nome', 'x');
  Check('WhereILike marca CaseInsensitive',
    TLzNexLikeStmt(Q.Ast.Group(sgWhere)[0]).CaseInsensitive);
  Q := NewQuery(Cli).Table('users').WhereNotLike('nome', 'x');
  Check('WhereNotLike marca Negated',
    Q.Ast.Group(sgWhere)[0].Negated and
    not TLzNexLikeStmt(Q.Ast.Group(sgWhere)[0]).CaseInsensitive);
end;

// OrWhere marca boOr; WhereNot marca Negated. Sem flag destrutivo: o OR nao
// pode vazar para o predicado seguinte.
procedure TestBoolOpAndNegation;
var
  Q: ILzNexQuery;
  A: TLzNexAst;
begin
  Writeln('-- conector e negacao --');
  Q := NewQuery(Cli).Table('users');
  Q := Q.Where('a', 1);
  Q := Q.OrWhere('b', 2);
  Q := Q.Where('c', 3);
  Q := Q.WhereNot('d', 4);
  Q := Q.OrWhereNot('e', 5);
  Q := Q.OrWhereNull('f');
  Q := Q.WhereNotNull('g');
  Q := Q.WhereNotIn('h', ValueList([1]));
  Q := Q.OrWhereRaw('i = ?', [6]);
  A := Q.Ast;

  Check('primeiro predicado e AND', A.Group(sgWhere)[0].BoolOp = boAnd);
  Check('OrWhere marca boOr', A.Group(sgWhere)[1].BoolOp = boOr);
  Check('o boOr NAO vaza para o proximo', A.Group(sgWhere)[2].BoolOp = boAnd);
  Check('WhereNot marca Negated e mantem AND',
    A.Group(sgWhere)[3].Negated and (A.Group(sgWhere)[3].BoolOp = boAnd));
  Check('OrWhereNot marca os dois',
    A.Group(sgWhere)[4].Negated and (A.Group(sgWhere)[4].BoolOp = boOr));
  Check('OrWhereNull: boOr sem negacao',
    (A.Group(sgWhere)[5].BoolOp = boOr) and not A.Group(sgWhere)[5].Negated);
  Check('WhereNotNull marca Negated', A.Group(sgWhere)[6].Negated);
  Check('WhereNotIn marca Negated', A.Group(sgWhere)[7].Negated);
  Check('OrWhereRaw marca boOr', A.Group(sgWhere)[8].BoolOp = boOr);
end;

// Lista vazia fica na AST como Values vazio; quem decide "1 = 0" / "1 = 1" pelo
// Negated e o compiler.
procedure TestEmptyIn;
var
  Q: ILzNexQuery;
  S: TLzNexInStmt;
begin
  Writeln('-- in com lista vazia --');
  Q := NewQuery(Cli).Table('users').WhereIn('id', nil).WhereNotIn('id', nil);

  S := TLzNexInStmt(Q.Ast.Group(sgWhere)[0]);
  Check('WhereIn vazio: statement existe com Values vazio',
    (S.Kind = skWhereIn) and (Length(S.Values) = 0) and (S.Sub = nil));
  Check('WhereIn vazio NAO e negado (compiler emite 1 = 0)', not S.Negated);

  S := TLzNexInStmt(Q.Ast.Group(sgWhere)[1]);
  Check('WhereNotIn vazio e negado (compiler emite 1 = 1)',
    (Length(S.Values) = 0) and S.Negated);
end;

// Pilha de grupos: substitui o callback do knex.
procedure TestGroups;
var
  Q: ILzNexQuery;
  A: TLzNexAst;
  G, Inner: TLzNexGroupStmt;
begin
  Writeln('-- grupos de predicado --');
  Q := NewQuery(Cli).Table('users');
  Q := Q.Where('ativo', True);
  Check('sem grupo aberto no inicio', Q.OpenGroupCount = 0);

  Q := Q.OrWhereOpen;
  Check('OrWhereOpen empilha', Q.OpenGroupCount = 1);
  Q := Q.Where('role', 'admin');
  Q := Q.OrWhere('role', 'owner');
  Q := Q.WhereNotOpen;
  Check('grupo aninhado empilha de novo', Q.OpenGroupCount = 2);
  Q := Q.WhereNull('banido_em');
  Q := Q.WhereClose;
  Q := Q.WhereClose;
  Check('OpenGroupCount volta a zero', Q.OpenGroupCount = 0);
  Q := Q.Where('tenant', 7);

  A := Q.Ast;
  Check('nivel raiz tem 3 itens', A.CountOf(sgWhere) = 3);
  Check('o item do meio e um grupo', A.Group(sgWhere)[1].Kind = skWhereGroup);
  Check('o grupo herdou o boOr do OrWhereOpen',
    A.Group(sgWhere)[1].BoolOp = boOr);

  G := TLzNexGroupStmt(A.Group(sgWhere)[1]);
  Check('o grupo tem 3 itens dentro', G.Items.Count = 3);
  Check('segundo item do grupo e OR', G.Items[1].BoolOp = boOr);
  Check('terceiro item do grupo e outro grupo', G.Items[2].Kind = skWhereGroup);
  Check('grupo de WhereNotOpen vem negado', G.Items[2].Negated);

  Inner := TLzNexGroupStmt(G.Items[2]);
  Check('grupo interno tem 1 item', Inner.Items.Count = 1);
  Check('item do grupo interno e o where null', Inner.Items[0].Kind = skWhereNull);
  Check('predicado depois do fechamento volta a raiz',
    A.Group(sgWhere)[2].Kind = skWhereBasic);

  // having tem pilha propria
  Q := NewQuery(Cli).Table('v');
  Q := Q.HavingOpen.Having('n', '>', 1).OrHaving('n', '<', 9).HavingClose;
  Check('having fecha a pilha', Q.OpenGroupCount = 0);
  Check('having virou um grupo em sgHaving',
    (Q.Ast.CountOf(sgHaving) = 1) and
    (Q.Ast.Group(sgHaving)[0].Kind = skHavingGroup));
  Check('itens do grupo de having sao skHavingBasic',
    TLzNexGroupStmt(Q.Ast.Group(sgHaving)[0]).Items[0].Kind = skHavingBasic);
end;

// Erros de uso que o builder tem que recusar.
procedure TestErrors;
var
  Q: ILzNexQuery;
  J: ILzNexJoin;
begin
  Writeln('-- erros de uso --');

  // grupo aberto bloqueia ToSQL
  Q := NewQuery(Cli).Table('users').WhereOpen.Where('a', 1);
  try
    Q.ToSQL;
    Check('ToSQL com grupo aberto levanta', False);
  except
    on E: ELzNexBuilder do Check('ToSQL com grupo aberto levanta', True);
  end;

  // fechar sem abrir
  Q := NewQuery(Cli).Table('users');
  try
    Q.WhereClose;
    Check('WhereClose sem WhereOpen levanta', False);
  except
    on E: ELzNexBuilder do Check('WhereClose sem WhereOpen levanta', True);
  end;
  try
    Q.HavingClose;
    Check('HavingClose sem HavingOpen levanta', False);
  except
    on E: ELzNexBuilder do Check('HavingClose sem HavingOpen levanta', True);
  end;

  // operador fora da whitelist
  try
    NewQuery(Cli).Table('users').Where('id', '; drop table users --', 1);
    Check('operador fora da whitelist levanta', False);
  except
    on E: ELzNexBuilder do Check('operador fora da whitelist levanta', True);
  end;
  try
    NewQuery(Cli).Table('users').Where('id', 'IS NOT', TLzNexValue.Null);
    Check('operador da whitelist em maiuscula e aceito', True);
  except
    on E: ELzNexBuilder do Check('operador da whitelist em maiuscula e aceito', False);
  end;

  // clone com grupo aberto
  Q := NewQuery(Cli).Table('users').WhereOpen;
  try
    Q.Clone;
    Check('Clone com grupo aberto levanta', False);
  except
    on E: ELzNexBuilder do Check('Clone com grupo aberto levanta', True);
  end;

  // query sem conexao: terminal tem que explicar o motivo
  try
    NewQuery(Cli).Table('users').Delete;
    Check('terminal sem conexao levanta', False);
  except
    on E: ELzNexBuilder do
      Check('terminal sem conexao levanta explicando',
        Pos('not bound to a connection', E.Message) > 0);
  end;

  // On* sem join corrente
  Q := NewQuery(Cli).Table('posts');
  J := Q.Join('users');
  Q.Clear(sgJoin);
  try
    J.OnColumns('a', '=', 'b');
    Check('On* sem join corrente levanta', False);
  except
    on E: ELzNexBuilder do Check('On* sem join corrente levanta', True);
  end;

  // pagina 1-based
  try
    NewQuery(Cli).Table('users').Page(0, 10);
    Check('Page(0, ...) levanta', False);
  except
    on E: ELzNexBuilder do Check('Page(0, ...) levanta', True);
  end;
end;

// Clone profundo e independente.
procedure TestClone;
var
  Q, C: ILzNexQuery;
begin
  Writeln('-- clone --');
  Q := NewQuery(Cli).Table('users').Where('id', 1).Limit(10).Offset(5);
  Q := Q.WhereOpen.Where('a', 1).OrWhere('b', 2).WhereClose;

  C := Q.Clone;
  Check('clone e outro objeto de AST', C.Ast <> Q.Ast);
  Check('clone copiou a quantidade de predicados',
    C.Ast.CountOf(sgWhere) = Q.Ast.CountOf(sgWhere));
  Check('clone copiou o Single',
    (C.Ast.Single.LimitValue.AsInt64 = 10) and
    (C.Ast.Single.OffsetValue.AsInt64 = 5) and
    (C.Ast.Single.Table.Text = 'users'));
  Check('clone gerou statements novos',
    C.Ast.Group(sgWhere)[0] <> Q.Ast.Group(sgWhere)[0]);
  Check('clone copiou o grupo em profundidade',
    TLzNexGroupStmt(C.Ast.Group(sgWhere)[1]).Items[0] <>
    TLzNexGroupStmt(Q.Ast.Group(sgWhere)[1]).Items[0]);

  // mutar um lado nao pode afetar o outro
  C := C.Where('novo', 1);
  Check('acrescentar no clone nao afeta o original',
    (Q.Ast.CountOf(sgWhere) = 2) and (C.Ast.CountOf(sgWhere) = 3));
  TLzNexBasicStmt(C.Ast.Group(sgWhere)[0]).Op := '<>';
  Check('mutar statement do clone nao afeta o original',
    (TLzNexBasicStmt(Q.Ast.Group(sgWhere)[0]).Op = '=') and
    (TLzNexBasicStmt(C.Ast.Group(sgWhere)[0]).Op = '<>'));
  TLzNexGroupStmt(C.Ast.Group(sgWhere)[1]).Items.Clear;
  Check('limpar o grupo do clone nao afeta o original',
    TLzNexGroupStmt(Q.Ast.Group(sgWhere)[1]).Items.Count = 2);
end;

// Join: OnColumns nao gera bind, OnValue gera.
procedure TestJoin;
var
  Q: ILzNexQuery;
  J: TLzNexJoinStmt;
begin
  Writeln('-- join --');
  Q := NewQuery(Cli).Table('posts');
  Q := Q.LeftJoin('users')
        .OnColumns('posts.user_id', '=', 'users.id')
        .OnValue('users.active', '=', True)
        .OrOnColumns('posts.autor', '=', 'users.login')
        .OnNull('users.banido_em')
        .OnIn('users.role', ValueList(['admin', 'owner']))
        .OnBetween('users.idade', 18, 60)
        .Where('posts.publicado', True);

  Check('join e where convivem na mesma expressao',
    (Q.Ast.CountOf(sgJoin) = 1) and (Q.Ast.CountOf(sgWhere) = 1));

  J := TLzNexJoinStmt(Q.Ast.Group(sgJoin)[0]);
  Check('tipo do join', J.JoinType = jtLeft);
  Check('tabela do join', J.Table.Text = 'users');
  Check('6 clausulas on', J.Clauses.Count = 6);

  Check('OnColumns -> jcColumns com Right NAO bindavel',
    (J.Clauses[0].ClauseKind = jcColumns) and
    not J.Clauses[0].Right.IsBindable and
    (J.Clauses[0].Right.Kind = vkIdentifier));
  Check('OnValue -> jcValue com Right bindavel',
    (J.Clauses[1].ClauseKind = jcValue) and J.Clauses[1].Right.IsBindable);
  Check('OrOnColumns marca boOr',
    (J.Clauses[2].ClauseKind = jcColumns) and (J.Clauses[2].BoolOp = boOr));
  Check('OnNull -> jcNull', J.Clauses[3].ClauseKind = jcNull);
  Check('OnIn -> jcIn com 2 valores',
    (J.Clauses[4].ClauseKind = jcIn) and (Length(J.Clauses[4].Values) = 2));
  Check('OnBetween -> jcBetween com Lo e Hi em Values',
    (J.Clauses[5].ClauseKind = jcBetween) and
    (Length(J.Clauses[5].Values) = 2) and
    (J.Clauses[5].Values[0].AsInt64 = 18));

  // operador do ON tambem passa pela whitelist
  try
    NewQuery(Cli).Table('a').Join('b').OnColumns('a.x', 'drop', 'b.y');
    Check('operador invalido no ON levanta', False);
  except
    on E: ELzNexBuilder do Check('operador invalido no ON levanta', True);
  end;

  // join cru nao vira join corrente
  Q := NewQuery(Cli).Table('a').JoinRaw('join b on b.id = ?', [1]);
  Check('JoinRaw cria statement de join com jtRaw',
    (Q.Ast.CountOf(sgJoin) = 1) and
    (TLzNexJoinStmt(Q.Ast.Group(sgJoin)[0]).JoinType = jtRaw) and
    (TLzNexJoinStmt(Q.Ast.Group(sgJoin)[0]).Raw <> nil));

  Q := NewQuery(Cli).Table('a').JoinSub(NewQuery(Cli).Table('b'), 'sub');
  Check('JoinSub guarda subquery e alias',
    (TLzNexJoinStmt(Q.Ast.Group(sgJoin)[0]).Table.Kind = vkSubQuery) and
    (TLzNexJoinStmt(Q.Ast.Group(sgJoin)[0]).Alias = 'sub'));
  Check('Using preenche UsingColumns',
    Length(TLzNexJoinStmt(
      NewQuery(Cli).Table('a').Join('b').Using(['id', 'tenant'])
        .Ast.Group(sgJoin)[0]).Clauses[0].UsingColumns) = 2);
end;

// Limit / Offset / Page e o resto do Single.
procedure TestSingle;
var
  Q: ILzNexQuery;
begin
  Writeln('-- single --');
  Q := NewQuery(Cli).Table('users');
  Check('sem limit no inicio', not Q.Ast.Single.HasLimit);
  Q := Q.Limit(25).Offset(50);
  Check('Limit preenche o Single',
    Q.Ast.Single.HasLimit and (Q.Ast.Single.LimitValue.AsInt64 = 25));
  Check('Offset preenche o Single',
    Q.Ast.Single.HasOffset and (Q.Ast.Single.OffsetValue.AsInt64 = 50));

  Q := NewQuery(Cli).Table('users').Page(3, 20);
  Check('Page(3, 20) -> limit 20', Q.Ast.Single.LimitValue.AsInt64 = 20);
  Check('Page(3, 20) -> offset 40', Q.Ast.Single.OffsetValue.AsInt64 = 40);
  Q := NewQuery(Cli).Table('users').Page(1, 20);
  Check('Page(1, ...) -> offset 0', Q.Ast.Single.OffsetValue.AsInt64 = 0);

  Q := NewQuery(Cli).Table('users').WithSchema('loja').AsAlias('u').ForUpdate.SkipLocked;
  Check('WithSchema', Q.Ast.Single.SchemaName = 'loja');
  Check('AsAlias', Q.Ast.Single.QueryAlias = 'u');
  Check('ForUpdate', Q.Ast.Single.Lock = lkForUpdate);
  Check('SkipLocked', Q.Ast.Single.Wait = wtSkipLocked);

  Q := NewQuery(Cli).Table('users').FromAs('users', 'u');
  Check('FromAs guarda o alias da tabela', Q.Ast.Single.TableAlias = 'u');

  Q := NewQuery(Cli).Table('users')
        .Select(['id', 'nome'])
        .SelectAs('criado_em', 'criado')
        .SelectRaw('count(*) as n', [])
        .Distinct
        .GroupBy(['id'])
        .OrderByDesc('id')
        .OrderByRaw('field(id, ?)', [1]);
  Check('Select/SelectAs/SelectRaw/Distinct somam 5 colunas',
    Q.Ast.CountOf(sgColumns) = 5);
  Check('SelectRaw -> skColumnRaw', Q.Ast.Group(sgColumns)[3].Kind = skColumnRaw);
  Check('Distinct -> skDistinct', Q.Ast.Group(sgColumns)[4].Kind = skDistinct);
  Check('GroupBy -> skGroupBy', Q.Ast.Group(sgGroup)[0].Kind = skGroupBy);
  Check('OrderByDesc -> odDesc',
    TLzNexOrderByStmt(Q.Ast.Group(sgOrder)[0]).Dir = odDesc);
  Check('OrderByRaw -> skOrderByRaw', Q.Ast.Group(sgOrder)[1].Kind = skOrderByRaw);

  Q := NewQuery(Cli).Table('a').Union(NewQuery(Cli).Table('b'))
        .With_('cte', NewQuery(Cli).Table('c')).HintComment('MAX_EXECUTION_TIME(1)');
  Check('Union -> sgUnion', Q.Ast.Group(sgUnion)[0].Kind = skUnion);
  Check('With_ -> sgWith', Q.Ast.Group(sgWith)[0].Kind = skWith);
  Check('HintComment -> sgHint', Q.Ast.Group(sgHint)[0].Kind = skHint);

  // Clear esvazia o grupo
  Q := Q.Clear(sgUnion);
  Check('Clear esvazia o grupo', not Q.Ast.Has(sgUnion));

  // upsert
  Q := NewQuery(Cli).Table('users').OnConflict(['email']).Merge(['nome']);
  Check('OnConflict guarda o alvo',
    Length(Q.Ast.Single.ConflictTargets) = 1);
  Check('Merge com colunas -> caMerge',
    (Q.Ast.Single.Conflict = caMerge) and
    (Length(Q.Ast.Single.ConflictMerge) = 1) and
    (Q.Ast.Single.ConflictMerge[0].Name = 'nome'));
  Q := NewQuery(Cli).Table('users').OnConflict(['email']).Ignore;
  Check('Ignore -> caIgnore', Q.Ast.Single.Conflict = caIgnore);
end;

// Raw: template, binds e validacao de contagem.
procedure TestRaw;
var
  R, Inner: ILzNexRaw;
  F: TLzNexFragment;
begin
  Writeln('-- raw --');

  R := LzNexRaw('?? = ? and ?? <> ?', ['a.b', 1, 'c', 'x']);
  F := R.Build(Cli);
  Check('?? quota identificador e ? gera placeholder',
    F.Text = '"a"."b" = ? and "c" <> ?');
  Check('?? NAO gera bind: sobram 2 binds', F.Bindings.Count = 2);
  Check('ordem dos binds preservada',
    (F.Bindings.Items(0).AsInt64 = 1) and (F.Bindings.Items(1).AsString = 'x'));
  Check('Template devolve o SQL original', R.Template = '?? = ? and ?? <> ?');

  R := LzNexRaw('json_extract(dados, ''$.a\?b'') = ?', ['v']);
  F := R.Build(Cli);
  Check('\? vira ? literal e nao consome argumento',
    F.Text = 'json_extract(dados, ''$.a?b'') = ?');
  Check('\? nao virou bind', F.Bindings.Count = 1);

  R := LzNexRawNamed('select * from :tabela: where id = :id and dono = :id',
    Vals(['tabela', 'users', 'id', 42]));
  F := R.Build(Cli);
  Check(':nome: quota e :nome gera bind',
    F.Text = 'select * from "users" where id = ? and dono = ?');
  Check(':nome repetido gera dois binds',
    (F.Bindings.Count = 2) and (F.Bindings.Items(1).AsInt64 = 42));

  R := LzNexRaw('now()', []);
  F := R.Build(Cli);
  Check('raw sem parametro', (F.Text = 'now()') and (F.Bindings.Count = 0));

  // contagem: faltando
  try
    LzNexRaw('? and ?', [1]).Build(Cli);
    Check('argumento faltando levanta', False);
  except
    on E: ELzNexBuilder do
      Check('argumento faltando levanta dizendo os numeros',
        (Pos('2', E.Message) > 0) and (Pos('1', E.Message) > 0));
  end;

  // contagem: sobrando
  try
    LzNexRaw('?', [1, 2]).Build(Cli);
    Check('argumento sobrando levanta', False);
  except
    on E: ELzNexBuilder do Check('argumento sobrando levanta', True);
  end;

  // nomeado ausente
  try
    LzNexRawNamed('id = :id', Vals(['outro', 1])).Build(Cli);
    Check('nomeado ausente levanta', False);
  except
    on E: ELzNexBuilder do Check('nomeado ausente levanta', True);
  end;

  // nomeado sobrando
  try
    LzNexRawNamed('id = :id', Vals(['id', 1, 'sobra', 2])).Build(Cli);
    Check('nomeado nao usado levanta', False);
  except
    on E: ELzNexBuilder do Check('nomeado nao usado levanta', True);
  end;

  // raw aninhado num '?': texto e binds entram na posicao certa
  Inner := LzNexRaw('coalesce(??, ?)', ['x', 0]);
  R := LzNexRawValues('select ? + ?',
    [TLzNexValue.Raw(Inner), TLzNexValue.FromInteger(5)]);
  F := R.Build(Cli);
  Check('raw aninhado concatena o texto',
    F.Text = 'select coalesce("x", ?) + ?');
  Check('raw aninhado concatena os binds na ordem',
    (F.Bindings.Count = 2) and (F.Bindings.Items(0).AsInt64 = 0) and
    (F.Bindings.Items(1).AsInt64 = 5));

  // identificador entregue num '?' sai quotado, sem bind
  R := LzNexRawValues('order by ?', [TLzNexValue.Identifier('u.nome')]);
  F := R.Build(Cli);
  Check('identificador num ? sai quotado e sem bind',
    (F.Text = 'order by "u"."nome"') and (F.Bindings.Count = 0));
end;

// Caminhos de erro em que a excecao sobe NO MEIO da montagem. O que importa
// aqui nao e a mensagem, e nao sobrar objeto sem dono: sob -gh qualquer
// alocacao orfa aparece no dump do heaptrc.
procedure TestNoLeakOnErrorPaths;
var
  Bad: Pointer;
  Q: ILzNexQuery;
begin
  Writeln('-- caminhos de erro sem vazamento --');
  // Ponteiro nao nulo: ValueOf recusa, entao LzNexRaw levanta na construcao.
  Bad := @Checks;

  try
    NewQuery(Cli).Table('a').Join('b').OnValue('x', 'nope', 1);
    Check('OnValue com operador invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('OnValue com operador invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').Join('b').OrOnColumns('a.x', 'nope', 'b.y');
    Check('OrOnColumns com operador invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('OrOnColumns com operador invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').Join('b').OrOnValue('x', 'nope', 1);
    Check('OrOnValue com operador invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('OrOnValue com operador invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').Having('n', 'nope', 1);
    Check('Having com operador invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('Having com operador invalido levanta', True);
  end;

  // argumento de tipo recusado: o raw levanta antes de existir statement
  try
    NewQuery(Cli).Table('a').Join('b').OnRaw('x = ?', [Bad]);
    Check('OnRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('OnRaw com argumento invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').JoinRaw('join b on b.id = ?', [Bad]);
    Check('JoinRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('JoinRaw com argumento invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').SelectRaw('?', [Bad]);
    Check('SelectRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('SelectRaw com argumento invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').WhereRaw('x = ?', [Bad]);
    Check('WhereRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('WhereRaw com argumento invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').HavingRaw('x = ?', [Bad]);
    Check('HavingRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('HavingRaw com argumento invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').GroupByRaw('?', [Bad]);
    Check('GroupByRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('GroupByRaw com argumento invalido levanta', True);
  end;

  try
    NewQuery(Cli).Table('a').OrderByRaw('?', [Bad]);
    Check('OrderByRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('OrderByRaw com argumento invalido levanta', True);
  end;

  try
    LzNexRaw('x = ?', [Bad]);
    Check('LzNexRaw com argumento invalido levanta', False);
  except
    on E: ELzNexBuilder do Check('LzNexRaw com argumento invalido levanta', True);
  end;

  // builder sem dialeto: o construtor levanta depois do inherited Create
  try
    NewQuery(nil);
    Check('NewQuery(nil) levanta', False);
  except
    on E: ELzNexBuilder do Check('NewQuery(nil) levanta', True);
  end;

  try
    NewBoundQuery(nil, nil);
    Check('NewBoundQuery(nil, nil) levanta', False);
  except
    on E: ELzNexBuilder do Check('NewBoundQuery(nil, nil) levanta', True);
  end;

  // query descartada com grupos ainda abertos: a AST e dona dos grupos e
  // precisa liberar os dois niveis
  Q := NewQuery(Cli).Table('a').WhereOpen.Where('x', 1).WhereNotOpen.WhereNull('y');
  Check('query com 2 grupos abertos antes do descarte', Q.OpenGroupCount = 2);
  Q := nil;
  Check('descartar query com grupo aberto nao vaza', True);

  // Build que levanta no meio: o TStringBuilder interno tem que ser liberado
  try
    LzNexRaw('? ? ?', [1]).Build(Cli);
    Check('Build com contagem errada levanta sem vazar o builder interno', False);
  except
    on E: ELzNexBuilder do
      Check('Build com contagem errada levanta sem vazar o builder interno', True);
  end;
end;

begin
  Writeln('=== sonda do query builder do LzNex ===');
  Cli := TProbeClient.Create as ILzNexClient;

  TestWhereFamilies;
  TestBoolOpAndNegation;
  TestEmptyIn;
  TestGroups;
  TestErrors;
  TestClone;
  TestJoin;
  TestSingle;
  TestRaw;
  TestNoLeakOnErrorPaths;

  Writeln;
  Writeln('asercoes: ', Checks);
  if ExitCode = 0 then
    Writeln('=== QUERY OK ===')
  else
    Writeln('=== QUERY COM FALHA ===');
  Flush(Output);
end.
