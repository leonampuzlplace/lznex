unit Migrations.All;

{ Agregador das migrations escritas em Pascal.

  Existe por uma restricao do FPC: unit que nao aparece em nenhum `uses` nao e
  linkada, entao o `initialization` dela nao roda e a migration nao se registra.
  O `lznex migrate:make` acrescenta a unit nova aqui -- se editar a mao, nao
  esqueca desta lista.

  Migrations em .sql nao precisam entrar aqui: sao lidas do disco em runtime. }

{$MODE DELPHI}{$H+}

interface

uses
  M20261024120000_create_users;

implementation

end.
