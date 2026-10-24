unit Foo;
{$MODE DELPHI}{$H+}
interface
uses Foo.Bar;
type

  TThing = Foo.Bar.TThing;
  IThing = Foo.Bar.IThing;
implementation
end.
