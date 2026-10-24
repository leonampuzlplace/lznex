program ProbeAst;

{ Sonda da AST: confirma Generics.Collections, TObjectList dono dos itens,
  clone PROFUNDO e TLzNexQuerySingle. }

{$MODE DELPHI}{$H+}

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast;

procedure Check(const AWhat: string; ACond: Boolean);
begin
  if ACond then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    ExitCode := 1;
  end;
end;

var
  L, L2: TLzNexStatementList;
  G: TLzNexGroupStmt;
  GC: TLzNexGroupStmt;
  B: TLzNexBasicStmt;
  J: TLzNexJoinStmt;
  JC: TLzNexJoinClause;
  Single, SingleC: TLzNexQuerySingle;
  F, F2: TLzNexFragment;
  Bind: TLzNexBindings;
begin
  Writeln('=== sonda da AST do LzNex ===');

  // lista dona dos itens
  L := TLzNexStatementList.Create;
  try
    L.Add(TLzNexBasicStmt.Create(sgWhere, TLzNexValue.Identifier('id'), '=', 1));
    L.Add(TLzNexNullStmt.Create(sgWhere, TLzNexValue.Identifier('deleted_at')));
    Check('lista aceita statements', L.Count = 2);
    Check('kind do basic', L[0].Kind = skWhereBasic);
    Check('kind do null', L[1].Kind = skWhereNull);
    Check('group do basic', L[0].Group = sgWhere);

    // having reusa as classes mudando o Kind.
    // Entra na lista para a lista liberar: criar solto aqui vazaria.
    L.Add(TLzNexBasicStmt.Create(sgHaving, TLzNexValue.Identifier('n'), '>', 1));
    Check('basic em having vira skHavingBasic', L[2].Kind = skHavingBasic);
    L.Delete(2);

    // clone profundo: mutar o clone nao pode afetar o original
    L2 := TLzNexStatementList.Create;
    try
      L.CloneInto(L2);
      Check('clone copiou a quantidade', L2.Count = 2);
      Check('clone gerou INSTANCIAS novas', L2[0] <> L[0]);
      TLzNexBasicStmt(L2[0]).Op := '<>';
      Check('mutar o clone nao afeta o original',
        (TLzNexBasicStmt(L[0]).Op = '=') and (TLzNexBasicStmt(L2[0]).Op = '<>'));
    finally
      L2.Free;
    end;
  finally
    L.Free;
  end;

  // grupo aninhado com clone profundo
  G := TLzNexGroupStmt.Create(sgWhere);
  try
    G.Items.Add(TLzNexBasicStmt.Create(sgWhere, TLzNexValue.Identifier('role'), '=', 'admin'));
    B := TLzNexBasicStmt.Create(sgWhere, TLzNexValue.Identifier('role'), '=', 'owner');
    B.BoolOp := boOr;
    G.Items.Add(B);
    Check('grupo com 2 itens', G.Items.Count = 2);
    Check('segundo item e OR', G.Items[1].BoolOp = boOr);

    GC := TLzNexGroupStmt(G.Clone);
    try
      Check('clone do grupo tem 2 itens', GC.Items.Count = 2);
      Check('clone do grupo e instancia nova', GC.Items[0] <> G.Items[0]);
      TLzNexBasicStmt(GC.Items[0]).Value := 'outro';
      Check('mutar item do clone nao afeta o original',
        TLzNexBasicStmt(G.Items[0]).Value.AsString = 'admin');
    finally
      GC.Free;
    end;
  finally
    G.Free;
  end;

  // join com clausulas
  J := TLzNexJoinStmt.Create(jtLeft, TLzNexValue.Identifier('users'));
  try
    JC := TLzNexJoinClause.Create;
    JC.ClauseKind := jcColumns;
    JC.Left := TLzNexValue.Identifier('posts.user_id');
    JC.Op := '=';
    JC.Right := TLzNexValue.Identifier('users.id');
    J.Clauses.Add(JC);

    JC := TLzNexJoinClause.Create;
    JC.ClauseKind := jcValue;
    JC.Left := TLzNexValue.Identifier('users.active');
    JC.Op := '=';
    JC.Right := True;
    J.Clauses.Add(JC);

    Check('join com 2 clausulas', J.Clauses.Count = 2);
    Check('clausula 0 compara colunas', J.Clauses[0].ClauseKind = jcColumns);
    Check('clausula 1 usa valor (bindavel)',
      (J.Clauses[1].ClauseKind = jcValue) and J.Clauses[1].Right.IsBindable);
    Check('clausula 0 NAO e bindavel (identificador)',
      not J.Clauses[0].Right.IsBindable);
  finally
    J.Free;
  end;

  // single
  Single.Reset;
  Check('single sem limit', not Single.HasLimit);
  Single.LimitValue := 10;
  Check('single com limit', Single.HasLimit and (Single.LimitValue.AsInt64 = 10));
  Single.UpdateValues := Vals(['nome', 'a']);
  SingleC := Single.Clone;
  SingleC.UpdateValues[0].Value := 'b';
  Check('clone do single copia arrays (nao compartilha)',
    (Single.UpdateValues[0].Value.AsString = 'a') and
    (SingleC.UpdateValues[0].Value.AsString = 'b'));

  // fragmento: texto e binds andam juntos
  F := TLzNexFragment.Lit('a = ').Concat(TLzNexFragment.Param(1), '');
  F2 := TLzNexFragment.Lit('b = ').Concat(TLzNexFragment.Param('x'), '');
  F := F.Concat(TLzNexFragment.Lit('and')).Concat(F2);
  Check('fragmento concatenado: texto', F.Text = 'a = ? and b = ?');
  Bind := F.Bindings;
  Check('fragmento concatenado: 2 binds', Bind.Count = 2);
  Check('fragmento: ordem dos binds preservada',
    (Bind.Items(0).AsInt64 = 1) and (Bind.Items(1).AsString = 'x'));
  Check('fragmento vazio e omitido na juncao',
    TLzNexFragment.Empty.Concat(TLzNexFragment.Lit('x')).Text = 'x');
  F := JoinFragments([TLzNexFragment.Lit('select'), TLzNexFragment.Empty,
                      TLzNexFragment.Lit('*')]);
  Check('JoinFragments omite vazios', F.Text = 'select *');

  F := PlaceholderList(ValueList([1, 2, 3]));
  Check('PlaceholderList texto', F.Text = '?, ?, ?');
  Check('PlaceholderList binds', F.Bindings.Count = 3);

  // bind de valor nao informado tem que levantar
  try
    Bind := TLzNexBindings.Empty;
    Bind.Add(TLzNexValue.Unset);
    Check('bind de vkUnset levanta', False);
  except
    on E: Exception do Check('bind de vkUnset levanta', True);
  end;

  Writeln;
  if ExitCode = 0 then
    Writeln('=== AST OK ===')
  else
    Writeln('=== AST COM FALHA ===');
  Flush(Output);
end.
