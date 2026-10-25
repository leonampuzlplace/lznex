# LzNex

Query builder, schema builder e migrations para Lazarus/FPC sobre ZeosLib.
Uma API fluente só, com interfaces e contagem de referência, para
MySQL/MariaDB, PostgreSQL, Firebird (3 e 5) e SQLite — com pool de conexões,
transações com savepoint, três modos de paginação e um CLI de migrations.

## Requisitos

- FPC 3.2+ e Lazarus (unidades em `{$MODE DELPHI}`)
- ZeosLib 8 — o pacote `zdbc`, instalado na IDE; não é vendorizado aqui
- A client library do banco: `libmariadb`, `libpq`, `libfbclient` ou `libsqlite3`

## Instalação

Pelo Boss, no `boss.json` do seu projeto:

```json
{
  "dependencies": {
    "github.com/leonampuzlplace/lznex": "^1.0.0"
  }
}
```

```sh
boss install
```

Ou abra `lznex.lpk` na IDE e adicione o pacote ao seu projeto.

## Uso

```pascal
uses
  LzNex, LzNex.Intf, LzNex.Value,
  LzNex.Client.MySQL;   // registra o dialeto: um use por banco que você usa

var
  Db: ILzNex;
  Rows: ILzNexResult;
begin
  Db := Connect(NewConfig
    .Client('mysql')
    .Host('localhost').Port(3306)
    .Database('app').User('root').Password('secret')
    .LibraryLocation('/usr/lib/x86_64-linux-gnu/libmariadb.so.3')
    .Pool(2, 10));
  try
    Rows := Db.Table('users')
      .Select(['id', 'name'])
      .Where('active', True)
      .WhereIn('role', ValueList(['admin', 'staff']))
      .OrderByDesc('id')
      .Limit(20)
      .Get;

    Writeln(Rows.ToJSON);
  finally
    Db.Shutdown;
  end;
end;
```

Nomes de dialeto aceitos: `mysql`/`mariadb`, `postgresql`/`postgres`,
`firebird`, `sqlite`/`sqlite3`.

Escrita, schema e transação:

```pascal
Id := Db.Table('users').InsertGetId(Vals(['name', 'Ana', 'email', 'ana@x.com']));

Db.Schema.CreateTable('posts')
  .BigIncrements('id')
  .BigInt('user_id').Unsigned.NotNull
    .References('users.id').OnDelete('cascade')
  .Str('title', 160).NotNull
  .Text('body').Nullable
  .Timestamps
  .Execute;

Trx := Db.Transaction;
try
  Trx.Table('posts').Where('user_id', Id).Delete;
  Trx.Table('users').Where('id', Id).Delete;
  Trx.Commit;
except
  Trx.Rollback;
  raise;
end;
```

`Paginate` devolve total e última página, `SimplePaginate` evita o `count`,
`CursorPaginate` pagina por cursor; `Chunk`/`ChunkById`/`Each` varrem em lotes.
`ToSQLString` mostra o SQL gerado sem executar nada.

## Configuração

Em código (`NewConfig`), por arquivo JSON ou por ambiente:

```pascal
Db := ConnectFromFile('database/lznex.json', 'development');
```

```sh
LZNEX_CLIENT=postgresql LZNEX_HOST=localhost LZNEX_DATABASE=app \
LZNEX_USER=postgres LZNEX_PASSWORD=secret ./bin/lznex migrate:status
```

Veja `database/lznex.json` para o formato do arquivo (um bloco por ambiente,
com `pool`, `migrations` e `seeds`). `LZNEX_ENV` escolhe o ambiente e
`LZNEX_CONFIG` o caminho do arquivo.

## CLI

```sh
lznex migrate:latest              # roda todas as migrations pendentes num novo batch
lznex migrate:rollback [--all]    # desfaz o último batch (ou tudo)
lznex migrate:up|down [nome]
lznex migrate:to <nome>
lznex migrate:status
lznex migrate:version
lznex migrate:unlock              # libera lock deixado por processo morto
lznex migrate:make <desc> [--sql] # gera migration em Pascal, ou par .up/.down.sql
lznex seed:run [--only=nome]
lznex seed:make <desc>
```

Migrations em Pascal se registram sozinhas (`RegisterMigration`) e entram pela
unit `database/Migrations.All.pas`; as `.sql` saem do diretório configurado em
`migrations.directory`.

## Testes

Tudo num binário só (`bin/lznex-tests`, fpcunit); os casos de integração ficam
ignorados a menos que `LZNEX_IT` esteja setado.

```sh
docker compose build tests
docker compose run --rm tests                  # unitários, sem banco

docker compose up -d mysql postgres firebird3 firebird5
docker compose run --rm tests-it               # MySQL
docker compose run --rm tests-it-pg            # PostgreSQL
docker compose run --rm tests-it-fb3           # Firebird 3
docker compose run --rm tests-it-fb5           # Firebird 5
docker compose run --rm tests-it-sqlite        # SQLite (arquivo no container)
```

Observado nessas execuções:

- `HEAPTRC=haltonnotreleased` é o gate de vazamento: sobrou bloco não liberado,
  o processo sai com 203 e o CI falha. `scripts/run-tests.sh` reporta
  `pass/fail/leak` e avisa quando o binário foi compilado sem `-gh`.
- O healthcheck do Firebird usa `isql` com `localhost:` no caminho; sem isso o
  arquivo abre em modo embedded, o engine recusa os dois acessos e a suíte cai
  de forma intermitente.
- Compilar a imagem (FPC, Lazarus, Zeos, dois build modes) leva minutos, então
  o CI compila uma vez e roda todas as suítes sobre a mesma imagem.

## Estrutura

- `src/` — a biblioteca: `LzNex.pas` é a fachada, `LzNex.Intf.pas` tem todos os
  contratos, `LzNex.Client.*` e `LzNex.Schema.*` são os dialetos
- `tools/` — o CLI (`bin/lznex`)
- `tests/` — a suíte fpcunit e as probes
- `database/` — exemplo de config, migrations e a unit que as agrega
- `example/api/` — API Horse mínima com `/health` e `/users`
  (`docker compose up api`, porta 9000)
- `docs/site/` — documentação em HTML estático; abra `docs/site/index.html`
- `spike/` — scripts e probes de investigação, fora do build

## Troubleshooting

- `configuration error: ...` — falta host/database/user: passe pelo
  `database/lznex.json` ou pelas `LZNEX_*`
- `Duplicate unit` ao compilar — Zeos aparecendo duas vezes (pacote na IDE mais
  uma cópia em `modules/`); deixe só um
- Conexão que não abre sem erro claro — confira `LibraryLocation`: o caminho da
  client library precisa existir no host onde o binário roda
