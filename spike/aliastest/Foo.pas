unit Foo;
{$MODE DELPHI}{$H+}
interface
uses Foo.Bar;
type
  // Alias com nome de unit pontuado, dentro de uma unit cujo nome e prefixo
  // dessa unit. E exatamente o caso de LzNex reexportando LzNex.Value.
  TThing = Foo.Bar.TThing;
  IThing = Foo.Bar.IThing;
implementation
end.
