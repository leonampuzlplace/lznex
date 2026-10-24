program P;
{$MODE DELPHI}{$H+}
uses Foo;
var
  T: TThing;
begin
  T.X := 7;
  Writeln('alias pontuado OK, X=', T.X);
  Flush(Output);
end.
