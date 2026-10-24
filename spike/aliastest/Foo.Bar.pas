unit Foo.Bar;
{$MODE DELPHI}{$H+}
interface
type
  TThing = record
    X: Integer;
  end;
  IThing = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function Go: Integer;
  end;
implementation
end.
