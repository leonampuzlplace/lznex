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

implementation

{ TValueTest }

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
  // vkUnset difere de vkNull: em INSERT vira DEFAULT, em WHERE e erro.
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
  // Acima do maior inteiro exato de um double.
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

{ TArrayOfConstTest }

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
  // vtExtended guarda PONTEIRO no TVarRec: esquecer o ^ devolveria lixo.
  List := ValueList([4.5]);
  AssertTrue('float read correctly', Abs(List[0].AsFloat - 4.5) < 1E-9);
end;

procedure TArrayOfConstTest.ValsKeepsInsertionOrder;
var
  Pairs: TLzNexNamedValues;
begin
  // O knex ordena as colunas do insert alfabeticamente; aqui vale a ordem
  // que o usuario escreveu.
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

{ TBindingsTest }

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
  // Pega variavel nao inicializada antes de ela virar SQL.
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

{ TFragmentTest }

procedure TFragmentTest.TextAndBindingsTravelTogether;
var
  Fragment: TLzNexFragment;
begin
  // Correcao estrutural do knex: nao da para reordenar o texto sem levar os
  // binds junto.
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

initialization
  RegisterTest('core', TValueTest);
  RegisterTest('core', TArrayOfConstTest);
  RegisterTest('core', TBindingsTest);
  RegisterTest('core', TFragmentTest);

end.
