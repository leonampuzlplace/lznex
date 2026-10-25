unit Test.Core;

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
  LzNex.Migration.Source.Sql,
  LzNex.Exceptions;

type
  TValueTest = class(TTestCase)
  published
    procedure ImplicitConversion;
    procedure UnsetIsNotBindable;
    procedure NullIsBindable;
    procedure IdentifierIsNotBindable;
    procedure Int64KeepsPrecision;
    procedure WrongTagRaises;
  end;

  TArrayOfConstTest = class(TTestCase)
  published
    procedure BuildsValueList;
    procedure FloatComesThroughPointer;
    procedure ValsKeepsInsertionOrder;
    procedure ValsWithOddCountRaises;
  end;

  TBindingsTest = class(TTestCase)
  published
    procedure KeepsOrder;
    procedure AppendConcatenatesInOrder;
    procedure RejectsUnsetValue;
    procedure OutOfRangeIndexRaises;
  end;

  TFragmentTest = class(TTestCase)
  published
    procedure TextAndBindingsTravelTogether;
    procedure EmptyFragmentIsSkipped;
    procedure JoinSkipsEmptyFragments;
    procedure WrapKeepsBindings;
    procedure BuildsPlaceholderList;
  end;

  // O split de script .sql: o separador e o ";", menos onde ele nao separa.
  TSqlSplitTest = class(TTestCase)
  published
    procedure SplitsOnSemicolon;
    procedure IgnoresSemicolonInsideALiteral;
    procedure IgnoresSemicolonInsideAComment;
    procedure KeepsADollarQuotedBodyWhole;
    procedure KeepsATaggedDollarBodyWhole;
    procedure UnclosedDollarBodyRaises;
    procedure ALoneDollarIsNotAQuote;
  end;

implementation

procedure TValueTest.ImplicitConversion;
var
  Value: TLzNexValue;
begin
  Value := 42;
  AssertTrue('integer', Value.Kind = vkInteger);
  AssertEquals(42, Value.AsInt64);

  Value := 'text';
  AssertTrue('string', Value.Kind = vkString);
  AssertEquals('text', Value.AsString);

  Value := True;
  AssertTrue('boolean', Value.Kind = vkBoolean);
  AssertTrue(Value.AsBoolean);

  Value := 3.5;
  AssertTrue('float', Value.Kind = vkFloat);
end;

procedure TValueTest.UnsetIsNotBindable;
begin

  AssertTrue(TLzNexValue.Unset.IsUnset);
  AssertFalse(TLzNexValue.Unset.IsBindable);
end;

procedure TValueTest.NullIsBindable;
begin
  AssertTrue(TLzNexValue.Null.IsNull);
  AssertTrue(TLzNexValue.Null.IsBindable);
end;

procedure TValueTest.IdentifierIsNotBindable;
begin
  AssertFalse(TLzNexValue.Identifier('users.id').IsBindable);
  AssertEquals('users.id', TLzNexValue.Identifier('users.id').Text);
end;

procedure TValueTest.Int64KeepsPrecision;
var
  Value: TLzNexValue;
begin

  Value := Int64(9007199254740993);
  AssertEquals(Int64(9007199254740993), Value.AsInt64);
end;

procedure TValueTest.WrongTagRaises;
begin
  try
    TLzNexValue.FromString('x').AsDateTime;
    Fail('expected ELzNexBuilder when reading a string as date');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TArrayOfConstTest.BuildsValueList;
var
  List: TLzNexValues;
begin
  List := ValueList([1, 'two', True]);
  AssertEquals(3, Length(List));
  AssertEquals(1, List[0].AsInt64);
  AssertEquals('two', List[1].AsString);
  AssertTrue(List[2].AsBoolean);
end;

procedure TArrayOfConstTest.FloatComesThroughPointer;
var
  List: TLzNexValues;
begin

  List := ValueList([4.5]);
  AssertTrue('float read correctly', Abs(List[0].AsFloat - 4.5) < 1E-9);
end;

procedure TArrayOfConstTest.ValsKeepsInsertionOrder;
var
  Pairs: TLzNexNamedValues;
begin

  Pairs := Vals(['name', 'Leonam', 'age', 38]);
  AssertEquals('name', Pairs[0].Name);
  AssertEquals('age', Pairs[1].Name);
end;

procedure TArrayOfConstTest.ValsWithOddCountRaises;
begin
  try
    Vals(['only-the-key']);
    Fail('expected ELzNexBuilder for odd argument count');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TBindingsTest.KeepsOrder;
var
  Bindings: TLzNexBindings;
begin
  Bindings := TLzNexBindings.Empty;
  Bindings.Add(1);
  Bindings.Add('x');
  AssertEquals(2, Bindings.Count);
  AssertEquals(1, Bindings.Items(0).AsInt64);
  AssertEquals('x', Bindings.Items(1).AsString);
end;

procedure TBindingsTest.AppendConcatenatesInOrder;
var
  First, Second: TLzNexBindings;
begin
  First := TLzNexBindings.Empty;
  First.Add(1);
  Second := TLzNexBindings.Empty;
  Second.Add(2);
  First.Append(Second);
  AssertEquals(2, First.Count);
  AssertEquals(2, First.Items(1).AsInt64);
end;

procedure TBindingsTest.RejectsUnsetValue;
var
  Bindings: TLzNexBindings;
begin

  Bindings := TLzNexBindings.Empty;
  try
    Bindings.Add(TLzNexValue.Unset);
    Fail('expected ELzNexBuilder when binding an unset value');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TBindingsTest.OutOfRangeIndexRaises;
var
  Bindings: TLzNexBindings;
begin
  Bindings := TLzNexBindings.Empty;
  try
    Bindings.Items(0);
    Fail('expected ELzNexBuilder for out of range index');
  except
    on E: ELzNexBuilder do ;
  end;
end;

procedure TFragmentTest.TextAndBindingsTravelTogether;
var
  Fragment: TLzNexFragment;
begin

  Fragment := TLzNexFragment.Lit('a = ').Concat(TLzNexFragment.Param(1), '');
  Fragment := Fragment.Concat(TLzNexFragment.Lit('and'));
  Fragment := Fragment.Concat(
    TLzNexFragment.Lit('b = ').Concat(TLzNexFragment.Param('x'), ''));

  AssertEquals('a = ? and b = ?', Fragment.Text);
  AssertEquals(2, Fragment.Bindings.Count);
  AssertEquals(1, Fragment.Bindings.Items(0).AsInt64);
  AssertEquals('x', Fragment.Bindings.Items(1).AsString);
end;

procedure TFragmentTest.EmptyFragmentIsSkipped;
begin
  AssertEquals('x', TLzNexFragment.Empty.Concat(TLzNexFragment.Lit('x')).Text);
  AssertEquals('x', TLzNexFragment.Lit('x').Concat(TLzNexFragment.Empty).Text);
end;

procedure TFragmentTest.JoinSkipsEmptyFragments;
var
  Fragment: TLzNexFragment;
begin
  Fragment := JoinFragments([TLzNexFragment.Lit('select'), TLzNexFragment.Empty,
                             TLzNexFragment.Lit('*')]);
  AssertEquals('select *', Fragment.Text);
end;

procedure TFragmentTest.WrapKeepsBindings;
var
  Fragment: TLzNexFragment;
begin
  Fragment := TLzNexFragment.Param(9).Wrap('(', ')');
  AssertEquals('(?)', Fragment.Text);
  AssertEquals(1, Fragment.Bindings.Count);
end;

procedure TFragmentTest.BuildsPlaceholderList;
var
  Fragment: TLzNexFragment;
begin
  Fragment := LzNex.Fragment.PlaceholderList(ValueList([1, 2, 3]));
  AssertEquals('?, ?, ?', Fragment.Text);
  AssertEquals(3, Fragment.Bindings.Count);
end;

procedure TSqlSplitTest.SplitsOnSemicolon;
var
  Parts: TLzNexStringArray;
begin
  Parts := SplitSqlStatements('create table a (id int); insert into a values (1);');
  AssertEquals('two statements', 2, Length(Parts));
  AssertEquals('create table a (id int)', Parts[0]);
  AssertEquals('insert into a values (1)', Parts[1]);
end;

procedure TSqlSplitTest.IgnoresSemicolonInsideALiteral;
var
  Parts: TLzNexStringArray;
begin
  Parts := SplitSqlStatements('insert into a values (''x; y'')');
  AssertEquals('one statement', 1, Length(Parts));
  AssertEquals('insert into a values (''x; y'')', Parts[0]);
end;

procedure TSqlSplitTest.IgnoresSemicolonInsideAComment;
var
  Parts: TLzNexStringArray;
begin
  Parts := SplitSqlStatements('select 1 -- a; b' + sLineBreak + '; select 2');
  AssertEquals('two statements', 2, Length(Parts));
end;

{ O corpo de uma funcao PL/pgSQL tem ";" dentro; cortar ali geraria pedacos
  invalidos e a migration morreria no meio. }
procedure TSqlSplitTest.KeepsADollarQuotedBodyWhole;
var
  Parts: TLzNexStringArray;
begin
  Parts := SplitSqlStatements(
    'create function f() returns int as $$ begin return 1; end; $$ language plpgsql;' +
    sLineBreak + 'select f();');
  AssertEquals('two statements', 2, Length(Parts));
  AssertEquals(
    'create function f() returns int as $$ begin return 1; end; $$ language plpgsql',
    Parts[0]);
  AssertEquals('select f()', Parts[1]);
end;

procedure TSqlSplitTest.KeepsATaggedDollarBodyWhole;
var
  Parts: TLzNexStringArray;
begin
  Parts := SplitSqlStatements(
    'do $body$ begin perform 1; perform 2; end $body$;' + sLineBreak +
    'select 3;');
  AssertEquals('two statements', 2, Length(Parts));
  AssertEquals('do $body$ begin perform 1; perform 2; end $body$', Parts[0]);
end;

procedure TSqlSplitTest.UnclosedDollarBodyRaises;
begin
  try
    SplitSqlStatements('create function f() as $$ begin return 1;');
    Fail('expected ELzNexMigration for an unclosed dollar body');
  except
    on E: ELzNexMigration do ;
  end;
end;

// Um "$" solto (variavel de sessao, identificador) nao abre dollar-quote.
procedure TSqlSplitTest.ALoneDollarIsNotAQuote;
var
  Parts: TLzNexStringArray;
begin
  Parts := SplitSqlStatements('select ''a$b''; select 2;');
  AssertEquals('two statements', 2, Length(Parts));
  AssertEquals('select ''a$b''', Parts[0]);
end;

initialization
  RegisterTest('core', TValueTest);
  RegisterTest('core', TArrayOfConstTest);
  RegisterTest('core', TBindingsTest);
  RegisterTest('core', TFragmentTest);
  RegisterTest('core', TSqlSplitTest);

end.
