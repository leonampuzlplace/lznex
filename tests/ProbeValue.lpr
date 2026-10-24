program ProbeValue;

{ Sonda da fundacao: confirma que class operator Implicit, Default(record),
  TVarRec e as coleccoes genericas compilam e funcionam no FPC 3.2.2. }

{$MODE DELPHI}{$H+}

uses
  SysUtils,
  LzNex.Types,
  LzNex.Exceptions,
  LzNex.Value;

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
  V: TLzNexValue;
  L: TLzNexValues;
  P: TLzNexNamedValues;
begin
  Writeln('=== sonda da fundacao do LzNex ===');

  // conversao implicita
  V := 42;
  Check('Implicit(Integer) -> vkInteger', (V.Kind = vkInteger) and (V.AsInt64 = 42));

  V := 'texto';
  Check('Implicit(string) -> vkString', (V.Kind = vkString) and (V.AsString = 'texto'));

  V := True;
  Check('Implicit(Boolean) -> vkBoolean', (V.Kind = vkBoolean) and V.AsBoolean);

  V := 3.5;
  Check('Implicit(Double) -> vkFloat', (V.Kind = vkFloat) and (Abs(V.AsFloat - 3.5) < 1E-9));

  V := Int64(9007199254740993);
  Check('Implicit(Int64) preserva precisao', V.AsInt64 = 9007199254740993);

  // tags especiais
  Check('Unset e unset e nao bindavel',
    TLzNexValue.Unset.IsUnset and not TLzNexValue.Unset.IsBindable);
  Check('Null e null e E bindavel',
    TLzNexValue.Null.IsNull and TLzNexValue.Null.IsBindable);
  Check('Identifier nao e bindavel',
    not TLzNexValue.Identifier('users.id').IsBindable);
  Check('Identifier guarda o texto',
    TLzNexValue.Identifier('users.id').Text = 'users.id');

  // array of const
  L := ValueList([1, 'dois', True, 4.5]);
  Check('ValueList tamanho', Length(L) = 4);
  Check('ValueList[0] inteiro', L[0].AsInt64 = 1);
  Check('ValueList[1] string', L[1].AsString = 'dois');
  Check('ValueList[2] boolean', L[2].AsBoolean);
  Check('ValueList[3] float (vtExtended via ponteiro)', Abs(L[3].AsFloat - 4.5) < 1E-9);

  P := Vals(['nome', 'Leonam', 'idade', 38]);
  Check('Vals pares', Length(P) = 2);
  Check('Vals preserva ORDEM de insercao', (P[0].Name = 'nome') and (P[1].Name = 'idade'));
  Check('Vals valor 0', P[0].Value.AsString = 'Leonam');
  Check('Vals valor 1', P[1].Value.AsInt64 = 38);

  // numero impar de argumentos tem que levantar
  try
    Vals(['so-a-chave']);
    Check('Vals impar levanta', False);
  except
    on E: ELzNexBuilder do Check('Vals impar levanta ELzNexBuilder', True);
  end;

  // tag errada tem que levantar
  try
    TLzNexValue.FromString('x').AsDateTime;
    Check('AsDateTime em string levanta', False);
  except
    on E: ELzNexBuilder do Check('AsDateTime em string levanta ELzNexBuilder', True);
  end;

  // UTF-8
  V := 'acentuação ✅';
  Check('UTF-8 preservado no record', V.AsString = 'acentuação ✅');

  // whitelist de operadores existe e tem o esperado
  Check('whitelist de operadores populada', Length(LZNEX_OPERATORS) = 28);

  Writeln;
  if ExitCode = 0 then
    Writeln('=== fundacao OK ===')
  else
    Writeln('=== fundacao COM FALHA ===');
  Flush(Output);
end.
