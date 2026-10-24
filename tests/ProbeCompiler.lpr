program ProbeCompiler;

{ Sonda do compiler: monta a AST na mao e confere o SQL exato mais a lista de
  binds NA ORDEM. Nao usa o builder -- e justamente isso que o desenho
  (compiler recebe TLzNexAst, nao ILzNexQuery) permite.

  Dois dialetos exercitados: o ANSI da classe base (TAnsiTestClient, declarado
  aqui) e o MySQL de verdade. }

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
  LzNex.Compiler,
  LzNex.Client.MySQL,
  LzNex.Exceptions;

type
  // Raw de teste: devolve texto e binds fixos. Serve tambem de
  // dubles de subquery, porque o compiler aceita ILzNexRaw onde espera subquery.
  TTestRaw = class(TInterfacedObject, ILzNexRaw)
  private
    FText: string;
    FBinds: TLzNexValues;
  public
    constructor Create(const AText: string; const ABinds: TLzNexValues);
    function Build(const AClient: ILzNexClient): TLzNexFragment;
    function Template: string;
  end;

  // Dialeto ANSI concreto: a classe base e abstrata nas fabricas.
  TAnsiTestClient = class(TLzNexClientBase)
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;
    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

var
  My, Ansi: ILzNexClient;
  MyC, AnsiC: ILzNexCompiler;
  A: TLzNexAst;
  Total: Integer = 0;

{ TTestRaw }

constructor TTestRaw.Create(const AText: string; const ABinds: TLzNexValues);
begin
  inherited Create;
  FText := AText;
  FBinds := Copy(ABinds);
end;

function TTestRaw.Build(const AClient: ILzNexClient): TLzNexFragment;
begin
  Result := TLzNexFragment.Make(FText, TLzNexBindings.FromValues(FBinds));
end;

function TTestRaw.Template: string;
begin
  Result := FText;
end;

{ TAnsiTestClient }

function TAnsiTestClient.DialectName: string;
begin
  Result := 'ansi';
end;

function TAnsiTestClient.ZeosProtocol: string;
begin
  Result := '';
end;

function TAnsiTestClient.NewCompiler: ILzNexCompiler;
begin
  Result := TLzNexCompilerBase.Create(Self);
end;

function TAnsiTestClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := nil;
end;

{ infra da sonda }

procedure Note(const AWhat: string; const ACond: Boolean);
begin
  Inc(Total);
  if ACond then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    ExitCode := 1;
  end;
end;

procedure Same(const AWhat, AGot, AExpected: string);
begin
  Inc(Total);
  if AGot = AExpected then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    Writeln('        esperado [', AExpected, ']');
    Writeln('        obtido   [', AGot, ']');
    ExitCode := 1;
  end;
end;

function BindsOf(const AFrag: TLzNexFragment): string;
var
  I: Integer;
  B: TLzNexBindings;
begin
  Result := '';
  B := AFrag.Bindings;
  for I := 0 to B.Count - 1 do
  begin
    if I > 0 then
      Result := Result + '|';
    if B.Items(I).IsNull then
      Result := Result + '<null>'
    else
      Result := Result + B.Items(I).AsString;
  end;
end;

// Compila e confere texto e binds. Conta como duas asercoes.
procedure CheckQ(const AWhat: string; const ACmp: ILzNexCompiler;
  const ASQL, ABinds: string);
var
  F: TLzNexFragment;
begin
  F := ACmp.Compile(A);
  Same(AWhat + ' [sql]', F.Text, ASQL);
  Same(AWhat + ' [binds]', BindsOf(F), ABinds);
end;

procedure CheckRaise(const AWhat: string; const ACmp: ILzNexCompiler;
  const AExpect: TClass; const AMsgPart: string = '');
var
  F: TLzNexFragment;
begin
  Inc(Total);
  try
    F := ACmp.Compile(A);
    Writeln('  FALHA ', AWhat, ' (nao levantou; saiu [', F.Text, '])');
    ExitCode := 1;
  except
    on E: Exception do
    begin
      if not E.ClassType.InheritsFrom(AExpect) then
      begin
        Writeln('  FALHA ', AWhat, ' (levantou ', E.ClassName, ', esperava ',
          AExpect.ClassName, ')');
        ExitCode := 1;
      end
      else if (AMsgPart <> '') and (Pos(AMsgPart, E.Message) = 0) then
      begin
        Writeln('  FALHA ', AWhat, ' (mensagem sem "', AMsgPart, '"): ', E.Message);
        ExitCode := 1;
      end
      else
        Writeln('  ok   ', AWhat, ' -> ', E.ClassName);
    end;
  end;
end;

// Recria a AST do zero com a tabela informada.
procedure Fresh(const ATable: string);
begin
  if A <> nil then
    FreeAndNil(A);
  A := TLzNexAst.Create;
  if ATable <> '' then
    A.Single.Table := TLzNexValue.Identifier(ATable);
end;

function RawOf(const AText: string; const ABinds: array of const): IInterface;
begin
  Result := TTestRaw.Create(AText, ValueList(ABinds));
end;

function Idents(const ANames: array of string): TLzNexValues;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ANames));
  for I := 0 to High(ANames) do
    Result[I] := TLzNexValue.Identifier(ANames[I]);
end;

function Basic(const AGroup: TLzNexStatementGroup; const ACol, AOp: string;
  const AValue: TLzNexValue): TLzNexBasicStmt;
begin
  Result := TLzNexBasicStmt.Create(AGroup, TLzNexValue.Identifier(ACol), AOp, AValue);
end;

{ ---------------- colunas ---------------- }

procedure TestColumns;
var
  Agg: TLzNexAggregateStmt;
begin
  Writeln('-- colunas');

  Fresh('users');
  CheckQ('select sem coluna vira *', MyC, 'select * from `users`', '');

  Fresh('users');
  A.Add(TLzNexColumnStmt.Create(TLzNexValue.Identifier('id')));
  A.Add(TLzNexColumnStmt.Create(TLzNexValue.Identifier('users.name')));
  CheckQ('colunas qualificadas', MyC,
    'select `id`, `users`.`name` from `users`', '');

  Fresh('users');
  A.Add(TLzNexColumnStmt.Create(TLzNexValue.Identifier('users.name'), 'n'));
  CheckQ('coluna com alias', MyC,
    'select `users`.`name` as `n` from `users`', '');

  Fresh('users');
  A.Add(TLzNexRawStmt.Create(skColumnRaw, sgColumns,
    RawOf('count(*) + ?', [5])));
  CheckQ('coluna raw com bind', MyC, 'select count(*) + ? from `users`', '5');

  Fresh('users');
  A.Add(TLzNexColumnStmt.Create(
    TLzNexValue.SubQuery(RawOf('select max(id) from `t` where x = ?', [7])), 'm'));
  CheckQ('subquery como coluna', MyC,
    'select (select max(id) from `t` where x = ?) as `m` from `users`', '7');

  Fresh('users');
  A.Add(TLzNexDistinctStmt.Create(nil));
  A.Add(TLzNexColumnStmt.Create(TLzNexValue.Identifier('id')));
  CheckQ('distinct simples', MyC, 'select distinct `id` from `users`', '');

  Fresh('users');
  A.Add(TLzNexDistinctStmt.Create(Idents(['id'])));
  CheckRaise('distinct on levanta em mysql', MyC, ELzNexCompile, 'DISTINCT ON');

  Fresh('users');
  A.Add(TLzNexAggregateStmt.Create(agCount, TLzNexValue.Identifier('*')));
  CheckQ('count(*)', MyC, 'select count(*) from `users`', '');

  Fresh('users');
  A.Add(TLzNexAggregateStmt.Create(agCount, TLzNexValue.Unset));
  CheckQ('agregado sem coluna vira *', MyC, 'select count(*) from `users`', '');

  Fresh('users');
  Agg := TLzNexAggregateStmt.Create(agCount, TLzNexValue.Identifier('email'), 'c', True);
  A.Add(Agg);
  A.Add(TLzNexAggregateStmt.Create(agSum, TLzNexValue.Identifier('total'), 't'));
  CheckQ('agregados com distinct e alias', MyC,
    'select count(distinct `email`) as `c`, sum(`total`) as `t` from `users`', '');
end;

{ ---------------- from ---------------- }

procedure TestFrom;
begin
  Writeln('-- from');

  Fresh('users');
  A.Single.TableAlias := 'u';
  CheckQ('from com alias', MyC, 'select * from `users` as `u`', '');

  Fresh('users');
  A.Single.SchemaName := 'app';
  CheckQ('from com schema', MyC, 'select * from `app`.`users`', '');

  Fresh('');
  A.Single.Table := TLzNexValue.SubQuery(RawOf('select 1 as x', []));
  A.Single.TableAlias := 't';
  CheckQ('from subquery com alias', MyC,
    'select * from (select 1 as x) as `t`', '');

  Fresh('');
  A.Single.Table := TLzNexValue.SubQuery(RawOf('select 1', []));
  CheckRaise('from subquery sem alias levanta', MyC, ELzNexCompile, 'alias');

  Fresh('');
  A.Single.Table := TLzNexValue.Raw(RawOf('`users` force index (`pk`)', []));
  CheckQ('from raw', MyC, 'select * from `users` force index (`pk`)', '');

  Fresh('');
  CheckQ('select sem from', MyC, 'select *', '');

  Fresh('we`ird');
  CheckQ('backtick dentro do nome e dobrado', MyC,
    'select * from `we``ird`', '');

  Fresh('we"ird');
  CheckQ('aspa dupla dobrada no ansi', AnsiC, 'select * from "we""ird"', '');
end;

{ ---------------- join ---------------- }

function Clause(const AKind: TLzNexJoinClauseKind): TLzNexJoinClause;
begin
  Result := TLzNexJoinClause.Create;
  Result.ClauseKind := AKind;
  Result.BoolOp := boAnd;
end;

function ColClause(const ALeft, AOp, ARight: string): TLzNexJoinClause;
begin
  Result := Clause(jcColumns);
  Result.Left := TLzNexValue.Identifier(ALeft);
  Result.Op := AOp;
  Result.Right := TLzNexValue.Identifier(ARight);
end;

procedure TestJoins;
var
  J: TLzNexJoinStmt;
  C: TLzNexJoinClause;
begin
  Writeln('-- join');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('posts'));
  J.Clauses.Add(ColClause('posts.user_id', '=', 'users.id'));
  A.Add(J);
  CheckQ('inner join on colunas', MyC,
    'select * from `users` inner join `posts` on `posts`.`user_id` = `users`.`id`', '');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtLeft, TLzNexValue.Identifier('posts'), 'p');
  J.Clauses.Add(ColClause('p.user_id', '=', 'users.id'));
  C := Clause(jcValue);
  C.Left := TLzNexValue.Identifier('p.active');
  C.Op := '=';
  C.Right := 1;
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('left join com alias e clausula de valor', MyC,
    'select * from `users` left join `posts` as `p` on `p`.`user_id` = `users`.`id`' +
    ' and `p`.`active` = ?', '1');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('posts'));
  J.Clauses.Add(ColClause('posts.user_id', '=', 'users.id'));
  C := Clause(jcValue);
  C.BoolOp := boOr;
  C.Left := TLzNexValue.Identifier('posts.public');
  C.Op := '=';
  C.Right := 1;
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('segunda clausula usa o BoolOp', MyC,
    'select * from `users` inner join `posts` on `posts`.`user_id` = `users`.`id`' +
    ' or `posts`.`public` = ?', '1');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('posts'));
  C := Clause(jcIn);
  C.Left := TLzNexValue.Identifier('posts.status');
  C.Values := ValueList(['a', 'b']);
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('join com in', MyC,
    'select * from `users` inner join `posts` on `posts`.`status` in (?, ?)', 'a|b');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtLeft, TLzNexValue.Identifier('posts'));
  C := Clause(jcNull);
  C.Left := TLzNexValue.Identifier('posts.deleted_at');
  C.Negated := True;
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('join com is not null', MyC,
    'select * from `users` left join `posts` on `posts`.`deleted_at` is not null', '');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('posts'));
  C := Clause(jcBetween);
  C.Left := TLzNexValue.Identifier('posts.score');
  C.Values := ValueList([1, 10]);
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('join com between', MyC,
    'select * from `users` inner join `posts` on `posts`.`score` between ? and ?',
    '1|10');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('posts'));
  C := Clause(jcRaw);
  C.Raw := RawOf('`posts`.`x` = ?', [9]);
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('join com clausula raw', MyC,
    'select * from `users` inner join `posts` on `posts`.`x` = ?', '9');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('posts'));
  C := Clause(jcUsing);
  C.UsingColumns := Idents(['user_id', 'tenant_id']);
  J.Clauses.Add(C);
  A.Add(J);
  CheckQ('join com using (sem prefixo on)', MyC,
    'select * from `users` inner join `posts` using (`user_id`, `tenant_id`)', '');

  Fresh('users');
  A.Add(TLzNexJoinStmt.Create(jtCross, TLzNexValue.Identifier('logs')));
  CheckQ('cross join sem clausula', MyC,
    'select * from `users` cross join `logs`', '');

  Fresh('users');
  A.Add(TLzNexJoinStmt.Create(jtFullOuter, TLzNexValue.Identifier('logs')));
  A.Add(TLzNexJoinStmt.Create(jtRightOuter, TLzNexValue.Identifier('tags')));
  CheckQ('full outer e right outer', MyC,
    'select * from `users` full outer join `logs` right outer join `tags`', '');

  Fresh('users');
  A.Add(TLzNexJoinStmt.Create(jtLeftOuter, TLzNexValue.Identifier('a')));
  A.Add(TLzNexJoinStmt.Create(jtRight, TLzNexValue.Identifier('b')));
  A.Add(TLzNexJoinStmt.Create(jtOuter, TLzNexValue.Identifier('c')));
  CheckQ('left outer, right e outer', MyC,
    'select * from `users` left outer join `a` right join `b` outer join `c`', '');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtRaw, TLzNexValue.Unset);
  J.Raw := RawOf('straight_join `x` on 1 = ?', [1]);
  A.Add(J);
  CheckQ('join cru', MyC,
    'select * from `users` straight_join `x` on 1 = ?', '1');

  Fresh('users');
  J := TLzNexJoinStmt.Create(jtLeft,
    TLzNexValue.SubQuery(RawOf('select id from `p` where y = ?', [4])), 'q');
  J.Clauses.Add(ColClause('q.id', '=', 'users.id'));
  A.Add(J);
  CheckQ('join de subquery com alias', MyC,
    'select * from `users` left join (select id from `p` where y = ?) as `q`' +
    ' on `q`.`id` = `users`.`id`', '4');
end;

{ ---------------- where ---------------- }

procedure TestWhere;
var
  B: TLzNexBasicStmt;
  N: TLzNexNullStmt;
  Bt: TLzNexBetweenStmt;
  Lk: TLzNexLikeStmt;
  Ex: TLzNexExistsStmt;
  R: TLzNexRawStmt;
  In_: TLzNexInStmt;
  G: TLzNexGroupStmt;
begin
  Writeln('-- where');

  Fresh('users');
  A.Add(Basic(sgWhere, 'id', '=', 1));
  CheckQ('where basico', MyC, 'select * from `users` where `id` = ?', '1');

  Fresh('users');
  A.Add(Basic(sgWhere, 'age', '>=', 18));
  CheckQ('where com operador', MyC, 'select * from `users` where `age` >= ?', '18');

  Fresh('users');
  B := Basic(sgWhere, 'id', '=', 1);
  B.Negated := True;
  A.Add(B);
  CheckQ('where negado', MyC, 'select * from `users` where not `id` = ?', '1');

  Fresh('users');
  B := Basic(sgWhere, 'a', '=', TLzNexValue.Identifier('users.ref'));
  B.AsColumn := True;
  A.Add(B);
  CheckQ('where comparando colunas (sem bind)', MyC,
    'select * from `users` where `a` = `users`.`ref`', '');

  Fresh('users');
  A.Add(Basic(sgWhere, 'a', '=', 1));
  B := Basic(sgWhere, 'b', '=', 2);
  B.BoolOp := boOr;
  A.Add(B);
  CheckQ('dois predicados com or', MyC,
    'select * from `users` where `a` = ? or `b` = ?', '1|2');

  Fresh('users');
  A.Add(TLzNexInStmt.Create(sgWhere, Idents(['id']), ValueList([1, 2, 3])));
  CheckQ('where in', MyC, 'select * from `users` where `id` in (?, ?, ?)', '1|2|3');

  Fresh('users');
  A.Add(TLzNexInStmt.Create(sgWhere, Idents(['id']), nil));
  CheckQ('where in vazio vira 1 = 0', MyC, 'select * from `users` where 1 = 0', '');

  Fresh('users');
  In_ := TLzNexInStmt.Create(sgWhere, Idents(['id']), nil);
  In_.Negated := True;
  A.Add(In_);
  CheckQ('where not in vazio vira 1 = 1', MyC,
    'select * from `users` where 1 = 1', '');

  Fresh('users');
  In_ := TLzNexInStmt.Create(sgWhere, Idents(['id']), ValueList([1, 2]));
  In_.Negated := True;
  A.Add(In_);
  CheckQ('where not in', MyC,
    'select * from `users` where `id` not in (?, ?)', '1|2');

  // O caso que o desenho de fragmento existe para garantir: bind antes e
  // depois da subquery, com os binds dela no meio.
  Fresh('users');
  A.Add(Basic(sgWhere, 'a', '=', 10));
  In_ := TLzNexInStmt.Create(sgWhere, Idents(['id']), nil);
  In_.Sub := RawOf('select id from `t` where z = ?', [20]);
  A.Add(In_);
  A.Add(Basic(sgWhere, 'b', '=', 30));
  CheckQ('subquery no meio: binds na posicao textual', MyC,
    'select * from `users` where `a` = ? and `id` in (select id from `t` where z = ?)' +
    ' and `b` = ?', '10|20|30');

  Fresh('users');
  In_ := TLzNexInStmt.Create(sgWhere, Idents(['a', 'b']), nil);
  SetLength(In_.Tuples, 2);
  In_.Tuples[0] := ValueList([1, 2]);
  In_.Tuples[1] := ValueList([3, 4]);
  A.Add(In_);
  CheckQ('in de tupla', MyC,
    'select * from `users` where (`a`, `b`) in ((?, ?), (?, ?))', '1|2|3|4');

  Fresh('users');
  A.Add(TLzNexNullStmt.Create(sgWhere, TLzNexValue.Identifier('deleted_at')));
  CheckQ('where is null', MyC,
    'select * from `users` where `deleted_at` is null', '');

  Fresh('users');
  N := TLzNexNullStmt.Create(sgWhere, TLzNexValue.Identifier('deleted_at'));
  N.Negated := True;
  A.Add(N);
  CheckQ('where is not null', MyC,
    'select * from `users` where `deleted_at` is not null', '');

  Fresh('users');
  A.Add(TLzNexBetweenStmt.Create(sgWhere, TLzNexValue.Identifier('age'), 18, 65));
  CheckQ('where between', MyC,
    'select * from `users` where `age` between ? and ?', '18|65');

  Fresh('users');
  Bt := TLzNexBetweenStmt.Create(sgWhere, TLzNexValue.Identifier('age'), 18, 65);
  Bt.Negated := True;
  A.Add(Bt);
  CheckQ('where not between', MyC,
    'select * from `users` where `age` not between ? and ?', '18|65');

  Fresh('users');
  A.Add(TLzNexLikeStmt.Create(sgWhere, TLzNexValue.Identifier('name'), '%jo%', False));
  CheckQ('where like', MyC, 'select * from `users` where `name` like ?', '%jo%');

  Fresh('users');
  Lk := TLzNexLikeStmt.Create(sgWhere, TLzNexValue.Identifier('name'), '%jo%', False);
  Lk.Negated := True;
  A.Add(Lk);
  CheckQ('where not like', MyC,
    'select * from `users` where `name` not like ?', '%jo%');

  Fresh('users');
  A.Add(TLzNexLikeStmt.Create(sgWhere, TLzNexValue.Identifier('name'), '%jo%', True));
  CheckQ('ilike no mysql cai para like', MyC,
    'select * from `users` where `name` like ?', '%jo%');

  Fresh('users');
  A.Add(TLzNexLikeStmt.Create(sgWhere, TLzNexValue.Identifier('name'), '%jo%', True));
  CheckQ('ilike no ansi usa ilike', AnsiC,
    'select * from "users" where "name" ilike ?', '%jo%');

  Fresh('users');
  A.Add(TLzNexExistsStmt.Create(sgWhere,
    RawOf('select 1 from `p` where `p`.`u` = `users`.`id` and `p`.`k` = ?', [8])));
  CheckQ('where exists', MyC,
    'select * from `users` where exists (select 1 from `p` where `p`.`u` =' +
    ' `users`.`id` and `p`.`k` = ?)', '8');

  Fresh('users');
  Ex := TLzNexExistsStmt.Create(sgWhere, RawOf('select 1', []));
  Ex.Negated := True;
  A.Add(Ex);
  CheckQ('where not exists', MyC,
    'select * from `users` where not exists (select 1)', '');

  Fresh('users');
  A.Add(TLzNexRawStmt.Create(skWhereRaw, sgWhere,
    RawOf('json_extract(`d`, ?) = ?', ['$.a', 5])));
  CheckQ('where raw com binds', MyC,
    'select * from `users` where json_extract(`d`, ?) = ?', '$.a|5');

  Fresh('users');
  R := TLzNexRawStmt.Create(skWhereRaw, sgWhere, RawOf('`x` = 1', []));
  R.Negated := True;
  A.Add(R);
  CheckQ('where raw negado', MyC, 'select * from `users` where not (`x` = 1)', '');

  // Grupo aninhado: OR dentro, AND fora -- sem recortar string.
  Fresh('users');
  A.Add(Basic(sgWhere, 'tenant', '=', 7));
  G := TLzNexGroupStmt.Create(sgWhere);
  G.Items.Add(Basic(sgWhere, 'role', '=', 'admin'));
  B := Basic(sgWhere, 'role', '=', 'owner');
  B.BoolOp := boOr;
  G.Items.Add(B);
  A.Add(G);
  A.Add(Basic(sgWhere, 'active', '=', 1));
  CheckQ('grupo aninhado: or dentro, and fora', MyC,
    'select * from `users` where `tenant` = ? and (`role` = ? or `role` = ?)' +
    ' and `active` = ?', '7|admin|owner|1');

  Fresh('users');
  G := TLzNexGroupStmt.Create(sgWhere);
  G.Items.Add(Basic(sgWhere, 'a', '=', 1));
  G.Negated := True;
  A.Add(G);
  CheckQ('grupo negado', MyC, 'select * from `users` where not (`a` = ?)', '1');

  Fresh('users');
  G := TLzNexGroupStmt.Create(sgWhere);
  A.Add(G);
  CheckQ('grupo vazio desaparece', MyC, 'select * from `users`', '');

  // CompilePredicates devolve so o corpo: e o que permite o grupo acima.
  Fresh('users');
  A.Add(Basic(sgWhere, 'id', '=', 1));
  Same('CompilePredicates nao inclui o prefixo where',
    MyC.CompilePredicates(sgWhere, A.Group(sgWhere)).Text, '`id` = ?');
end;

{ ---------------- group / having / order ---------------- }

procedure TestGroupHavingOrder;
var
  G: TLzNexGroupStmt;
  B: TLzNexBasicStmt;
begin
  Writeln('-- group by / having / order by');

  Fresh('users');
  A.Add(TLzNexGroupByStmt.Create(TLzNexValue.Identifier('dept')));
  A.Add(TLzNexGroupByStmt.Create(
    TLzNexValue.Raw(RawOf('year(`created_at`)', [])), True));
  CheckQ('group by com item raw', MyC,
    'select * from `users` group by `dept`, year(`created_at`)', '');

  Fresh('users');
  A.Add(TLzNexGroupByStmt.Create(TLzNexValue.Identifier('dept')));
  A.Add(Basic(sgHaving, 'total', '>', 100));
  CheckQ('having basico', MyC,
    'select * from `users` group by `dept` having `total` > ?', '100');

  Fresh('users');
  A.Add(TLzNexInStmt.Create(sgHaving, Idents(['n']), ValueList([1, 2])));
  CheckQ('having in', MyC, 'select * from `users` having `n` in (?, ?)', '1|2');

  Fresh('users');
  A.Add(TLzNexNullStmt.Create(sgHaving, TLzNexValue.Identifier('x')));
  CheckQ('having null', MyC, 'select * from `users` having `x` is null', '');

  Fresh('users');
  A.Add(TLzNexBetweenStmt.Create(sgHaving, TLzNexValue.Identifier('n'), 1, 9));
  CheckQ('having between', MyC,
    'select * from `users` having `n` between ? and ?', '1|9');

  Fresh('users');
  A.Add(TLzNexRawStmt.Create(skHavingRaw, sgHaving,
    RawOf('sum(`v`) > ?', [10])));
  CheckQ('having raw', MyC, 'select * from `users` having sum(`v`) > ?', '10');

  Fresh('users');
  G := TLzNexGroupStmt.Create(sgHaving);
  G.Items.Add(Basic(sgHaving, 'a', '>', 1));
  B := Basic(sgHaving, 'b', '>', 2);
  B.BoolOp := boOr;
  G.Items.Add(B);
  A.Add(G);
  CheckQ('having com grupo aninhado', MyC,
    'select * from `users` having (`a` > ? or `b` > ?)', '1|2');

  // Like e Exists mantem o Kind skWhere* mesmo no grupo having: o prefixo
  // vem do Group, nao do Kind.
  Fresh('users');
  A.Add(TLzNexLikeStmt.Create(sgHaving, TLzNexValue.Identifier('n'), 'a%', False));
  CheckQ('like no grupo having (Kind continua skWhereLike)', MyC,
    'select * from `users` having `n` like ?', 'a%');

  Fresh('users');
  A.Add(TLzNexExistsStmt.Create(sgHaving, RawOf('select 1', [])));
  CheckQ('exists no grupo having', MyC,
    'select * from `users` having exists (select 1)', '');

  Fresh('users');
  A.Add(TLzNexOrderByStmt.Create(TLzNexValue.Identifier('name'), odAsc));
  A.Add(TLzNexOrderByStmt.Create(TLzNexValue.Identifier('id'), odDesc));
  CheckQ('order by com direcao', MyC,
    'select * from `users` order by `name` asc, `id` desc', '');

  Fresh('users');
  A.Add(TLzNexOrderByStmt.Create(TLzNexValue.Identifier('due'), odAsc, nlLast));
  CheckQ('nulls last emulado com (col is null)', MyC,
    'select * from `users` order by (`due` is null) asc, `due` asc', '');

  Fresh('users');
  A.Add(TLzNexOrderByStmt.Create(TLzNexValue.Identifier('due'), odDesc, nlFirst));
  CheckQ('nulls first emulado', MyC,
    'select * from `users` order by (`due` is null) desc, `due` desc', '');

  Fresh('users');
  A.Add(TLzNexOrderByStmt.Create(
    TLzNexValue.Raw(RawOf('field(`s`, ?)', ['a'])), odAsc, nlDefault, True));
  CheckQ('order by raw', MyC,
    'select * from `users` order by field(`s`, ?) asc', 'a');
end;

{ ---------------- paginacao, lock, conjuntos, cte, hint ---------------- }

procedure TestTail;
begin
  Writeln('-- limit / offset / lock / union / with / hint');

  Fresh('users');
  A.Single.LimitValue := 10;
  A.Single.OffsetValue := 20;
  CheckQ('limit e offset com bind', MyC,
    'select * from `users` limit ? offset ?', '10|20');

  Fresh('users');
  A.Single.OffsetValue := 5;
  CheckQ('mysql: offset sem limit usa o teto do bigint', MyC,
    'select * from `users` limit 18446744073709551615 offset ?', '5');

  Fresh('users');
  A.Single.OffsetValue := 5;
  CheckQ('ansi: offset sem limit nao inventa limit', AnsiC,
    'select * from "users" offset ?', '5');

  Fresh('users');
  A.Single.Method := qmFirst;
  CheckQ('first garante limit 1', MyC, 'select * from `users` limit ?', '1');

  Fresh('users');
  A.Single.Lock := lkForUpdate;
  CheckQ('for update', MyC, 'select * from `users` for update', '');

  Fresh('users');
  A.Single.Lock := lkForUpdate;
  A.Single.Wait := wtSkipLocked;
  CheckQ('for update skip locked', MyC,
    'select * from `users` for update skip locked', '');

  Fresh('users');
  A.Single.Lock := lkForShare;
  A.Single.Wait := wtNoWait;
  CheckQ('for share nowait', MyC, 'select * from `users` for share nowait', '');

  Fresh('users');
  A.Add(TLzNexUnionStmt.Create(ukUnionAll,
    RawOf('select * from `old` where y = ?', [3]), True));
  CheckQ('union all com parenteses', MyC,
    'select * from `users` union all (select * from `old` where y = ?)', '3');

  Fresh('users');
  A.Add(TLzNexUnionStmt.Create(ukUnion, RawOf('select * from `old`', []), False));
  CheckQ('union sem parenteses', MyC,
    'select * from `users` union select * from `old`', '');

  Fresh('users');
  A.Add(TLzNexUnionStmt.Create(ukIntersect, RawOf('select 1', []), True));
  A.Add(TLzNexUnionStmt.Create(ukExcept, RawOf('select 2', []), True));
  CheckQ('intersect e except', MyC,
    'select * from `users` intersect (select 1) except (select 2)', '');

  Fresh('users');
  A.Add(TLzNexUnionStmt.Create(ukUnion, RawOf('select 1', []), True));
  A.Add(TLzNexOrderByStmt.Create(TLzNexValue.Identifier('id'), odAsc));
  CheckQ('union vem antes do order by', MyC,
    'select * from `users` union (select 1) order by `id` asc', '');

  Fresh('users');
  A.Add(TLzNexWithStmt.Create('recent', nil,
    RawOf('select * from `logs` where d > ?', ['2024-01-01'])));
  CheckQ('cte simples', MyC,
    'with `recent` as (select * from `logs` where d > ?) select * from `users`',
    '2024-01-01');

  Fresh('users');
  A.Add(TLzNexWithStmt.Create('recent', Idents(['a', 'b']),
    RawOf('select 1, 2', [])));
  CheckQ('cte com colunas', MyC,
    'with `recent` (`a`, `b`) as (select 1, 2) select * from `users`', '');

  Fresh('users');
  A.Add(TLzNexWithStmt.Create('tree', nil, RawOf('select 1', []), True));
  A.Add(TLzNexWithStmt.Create('other', nil, RawOf('select 2', [])));
  CheckQ('cte recursiva e multipla', MyC,
    'with recursive `tree` as (select 1), `other` as (select 2) select * from `users`',
    '');

  Fresh('users');
  A.Add(TLzNexHintStmt.Create('max_execution_time(1000)'));
  CheckQ('hint depois do select', MyC,
    'select /*+ max_execution_time(1000) */ * from `users`', '');

  Fresh('users');
  A.Add(TLzNexHintStmt.Create('ruim */ union select 1'));
  CheckRaise('hint que fecha o comentario levanta', MyC, ELzNexBuilder,
    'comment delimiter');
end;

{ ---------------- insert ---------------- }

procedure TestInsert;
begin
  Writeln('-- insert');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  CheckQ('insert de uma linha preserva a ordem de insercao', MyC,
    'insert into `users` (`name`, `age`) values (?, ?)', 'ana|30');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 2);
  A.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  A.Single.InsertRows[1] := Vals(['name', 'bob']);
  CheckQ('insert multiplo: coluna ausente vira default', MyC,
    'insert into `users` (`name`, `age`) values (?, ?), (?, default)',
    'ana|30|bob');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 2);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.InsertRows[1] := Vals(['name', 'bob', 'age', 40]);
  CheckQ('coluna nova numa linha posterior entra no fim', MyC,
    'insert into `users` (`name`, `age`) values (?, default), (?, ?)',
    'ana|bob|40');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.InsertRows[0][0].Value := TLzNexValue.Raw(RawOf('upper(?)', ['ana']));
  CheckQ('insert com valor raw', MyC,
    'insert into `users` (`name`) values (upper(?))', 'ana');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.Conflict := caIgnore;
  CheckQ('mysql: insert ignore into', MyC,
    'insert ignore into `users` (`name`) values (?)', 'ana');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  A.Single.Conflict := caMerge;
  CheckQ('mysql: on duplicate key update', MyC,
    'insert into `users` (`name`, `age`) values (?, ?) on duplicate key update' +
    ' `name` = values(`name`), `age` = values(`age`)', 'ana|30');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  A.Single.Conflict := caMerge;
  A.Single.ConflictMerge := Vals(['age', 99]);
  CheckQ('mysql: merge com valores explicitos', MyC,
    'insert into `users` (`name`, `age`) values (?, ?) on duplicate key update' +
    ' `age` = ?', 'ana|30|99');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana', 'age', 30]);
  A.Single.Conflict := caMerge;
  SetLength(A.Single.ConflictMerge, 1);
  A.Single.ConflictMerge[0].Name := 'age';
  A.Single.ConflictMerge[0].Value := TLzNexValue.Unset;
  CheckQ('mysql: merge com vkUnset reaproveita o valor do insert', MyC,
    'insert into `users` (`name`, `age`) values (?, ?) on duplicate key update' +
    ' `age` = values(`age`)', 'ana|30');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.Conflict := caIgnore;
  A.Single.ConflictTargets := Idents(['email']);
  CheckQ('ansi: on conflict do nothing', AnsiC,
    'insert into "users" ("name") values (?) on conflict ("email") do nothing',
    'ana');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.Conflict := caMerge;
  A.Single.ConflictTargets := Idents(['email']);
  CheckQ('ansi: on conflict do update set excluded', AnsiC,
    'insert into "users" ("name") values (?) on conflict ("email") do update set' +
    ' "name" = excluded."name"', 'ana');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.Conflict := caMerge;
  A.Single.ConflictTargets := Idents(['email']);
  A.Single.ConflictMerge := Vals(['name', 'fixo']);
  CheckQ('ansi: merge com valor explicito gera bind', AnsiC,
    'insert into "users" ("name") values (?) on conflict ("email") do update set' +
    ' "name" = ?', 'ana|fixo');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.Conflict := caMerge;
  CheckRaise('ansi: merge sem coluna de conflito levanta', AnsiC,
    ELzNexCompile, 'ON CONFLICT');

  Fresh('users');
  A.Single.Method := qmInsert;
  SetLength(A.Single.InsertRows, 1);
  A.Single.InsertRows[0] := Vals(['name', 'ana']);
  A.Single.Returning := Idents(['id']);
  CheckRaise('mysql: returning levanta', MyC, ELzNexCompile, 'RETURNING');
end;

{ ---------------- update / delete / truncate ---------------- }

procedure TestWrite;
var
  J: TLzNexJoinStmt;
begin
  Writeln('-- update / delete / truncate');

  Fresh('users');
  A.Single.Method := qmUpdate;
  A.Single.UpdateValues := Vals(['name', 'x', 'email', 'y']);
  A.Add(Basic(sgWhere, 'id', '=', 7));
  CheckQ('update com set', MyC,
    'update `users` set `name` = ?, `email` = ? where `id` = ?', 'x|y|7');

  Fresh('users');
  A.Single.Method := qmUpdate;
  A.Single.UpdateValues := Vals(['name', 'x']);
  A.Single.Counters := Vals(['hits', 1]);
  A.Add(Basic(sgWhere, 'id', '=', 7));
  CheckQ('update com counter (increment)', MyC,
    'update `users` set `name` = ?, `hits` = `hits` + ? where `id` = ?', 'x|1|7');

  Fresh('users');
  A.Single.Method := qmUpdate;
  A.Single.Counters := Vals(['stock', -2]);
  CheckQ('decrement e counter com delta negativo', MyC,
    'update `users` set `stock` = `stock` + ?', '-2');

  Fresh('users');
  A.Single.Method := qmUpdate;
  A.Single.TableAlias := 'u';
  A.Single.UpdateValues := Vals(['name', 'x']);
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('tenants'), 't');
  J.Clauses.Add(ColClause('t.id', '=', 'u.tenant_id'));
  A.Add(J);
  A.Single.LimitValue := 5;
  CheckQ('update com join, alias e limit', MyC,
    'update `users` as `u` inner join `tenants` as `t` on `t`.`id` = `u`.`tenant_id`' +
    ' set `name` = ? limit ?', 'x|5');

  Fresh('users');
  A.Single.Method := qmUpdate;
  CheckRaise('update sem set levanta', MyC, ELzNexCompile, 'SET');

  Fresh('users');
  A.Single.Method := qmDelete;
  A.Add(Basic(sgWhere, 'id', '=', 3));
  CheckQ('delete', MyC, 'delete from `users` where `id` = ?', '3');

  Fresh('users');
  A.Single.Method := qmDelete;
  A.Add(Basic(sgWhere, 'id', '=', 3));
  A.Single.LimitValue := 5;
  CheckQ('mysql aceita limit em delete', MyC,
    'delete from `users` where `id` = ? limit ?', '3|5');

  Fresh('users');
  A.Single.Method := qmDelete;
  A.Single.LimitValue := 5;
  CheckRaise('ansi recusa limit em delete', AnsiC, ELzNexCompile, 'limit');

  Fresh('users');
  A.Single.Method := qmDelete;
  A.Single.TableAlias := 'u';
  J := TLzNexJoinStmt.Create(jtInner, TLzNexValue.Identifier('tenants'), 't');
  J.Clauses.Add(ColClause('t.id', '=', 'u.tenant_id'));
  A.Add(J);
  CheckQ('mysql: delete com join repete o alvo', MyC,
    'delete `u` from `users` as `u` inner join `tenants` as `t`' +
    ' on `t`.`id` = `u`.`tenant_id`', '');

  Fresh('users');
  A.Single.Method := qmTruncate;
  CheckQ('truncate', MyC, 'truncate `users`', '');
end;

{ ---------------- erros de contrato ---------------- }

procedure TestErrors;
var
  B: TLzNexBasicStmt;
begin
  Writeln('-- erros');

  Fresh('users');
  A.Single.Method := qmDelete;
  A.Add(Basic(sgHaving, 'n', '>', 1));
  CheckRaise('having em delete levanta', MyC, ELzNexCompile, 'having');

  Fresh('users');
  A.Single.Method := qmDelete;
  A.Add(TLzNexGroupByStmt.Create(TLzNexValue.Identifier('d')));
  CheckRaise('group by em delete levanta', MyC, ELzNexCompile, 'group by');

  Fresh('users');
  A.Single.Method := qmUpdate;
  A.Single.UpdateValues := Vals(['a', 1]);
  A.Add(Basic(sgHaving, 'n', '>', 1));
  CheckRaise('having em update levanta', MyC, ELzNexCompile, 'having');

  Fresh('users');
  A.Single.Method := qmTruncate;
  A.Add(Basic(sgWhere, 'id', '=', 1));
  CheckRaise('where em truncate levanta', MyC, ELzNexCompile, 'where');

  Fresh('users');
  B := TLzNexBasicStmt.Create(sgWhere, TLzNexValue.Identifier('status'), '=',
    TLzNexValue.Unset);
  A.Add(B);
  CheckRaise('vkUnset no where levanta citando a coluna', MyC, ELzNexBuilder,
    'status');

  Fresh('users');
  A.Add(Basic(sgWhere, 'id', 'drop table', 1));
  CheckRaise('operador fora da whitelist levanta', MyC, ELzNexBuilder,
    'not allowed');

  Fresh('users');
  A.Single.Method := qmUpdate;
  SetLength(A.Single.UpdateValues, 1);
  A.Single.UpdateValues[0].Name := 'nome';
  A.Single.UpdateValues[0].Value := TLzNexValue.Unset;
  CheckRaise('vkUnset no set do update levanta', MyC, ELzNexBuilder, 'nome');

  Fresh('');
  A.Single.Method := qmDelete;
  CheckRaise('delete sem tabela levanta', MyC, ELzNexCompile, 'table');

  Fresh('users');
  A.Add(TLzNexExistsStmt.Create(sgWhere, nil));
  CheckRaise('exists sem subquery levanta', MyC, ELzNexCompile, 'Subquery');
end;

{ ---------------- dialeto ---------------- }

procedure TestClient;
var
  C: ILzNexClient;
begin
  Writeln('-- dialeto mysql');

  Note('mysql registrado', IsClientRegistered('mysql'));
  Note('mariadb registrado', IsClientRegistered('mariadb'));
  C := CreateClient('mariadb');
  Same('mariadb usa o dialeto mysql', C.DialectName, 'mysql');
  Same('protocolo do zeos', C.ZeosProtocol, 'mysql');
  Same('quoting com backtick', C.WrapIdentifier('id'), '`id`');
  Same('backtick dobrado no escape', C.WrapIdentifier('we`ird'), '`we``ird`');
  Same('nome qualificado', C.WrapQualified('a.b'), '`a`.`b`');
  Note('sem returning', not C.SupportsReturning);
  Note('sem where no upsert', not C.SupportsOnConflictWhere);
  Note('sem nulls ordering nativo', not C.SupportsNullsOrdering);
  Note('sem distinct on', not C.SupportsDistinctOn);
  Note('com savepoints', C.SupportsSavepoints);
  Note('DDL NAO e transacional (commit implicito)', not C.DdlIsTransactional);
  Note('limit nao e proibido em delete', Length(C.InvalidComponents(qmDelete)) = 2);
  Note('compiler do dialeto e o do mysql',
    C.NewCompiler.Client.DialectName = 'mysql');
  Note('schema compiler do dialeto ja e entregue',
    C.NewSchemaCompiler <> nil);
  Same('schema compiler sabe o tipo fisico do mysql',
    C.NewSchemaCompiler.ColumnTypeSQL(ctString, 100, 0, nil), 'varchar(100)');
end;

begin
  Writeln('=== sonda do compiler do LzNex ===');

  My := CreateClient('mysql');
  Ansi := TAnsiTestClient.Create;
  MyC := My.NewCompiler;
  AnsiC := Ansi.NewCompiler;

  try
    TestColumns;
    TestFrom;
    TestJoins;
    TestWhere;
    TestGroupHavingOrder;
    TestTail;
    TestInsert;
    TestWrite;
    TestErrors;
    TestClient;
  finally
    if A <> nil then
      FreeAndNil(A);
  end;

  Writeln;
  Writeln('asercoes: ', Total);
  if ExitCode = 0 then
    Writeln('=== COMPILER OK ===')
  else
    Writeln('=== COMPILER COM FALHA ===');
  Flush(Output);
end.
