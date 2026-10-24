# LzNex

Query builder, schema builder e migrations para **Lazarus/FPC**, no espírito do
[Knex.js](https://knexjs.org). Usa [ZeosLib](https://zeoslib.sourceforge.io) por baixo
(camada DBC, sem `TDataset`). MySQL pronto; PostgreSQL com SQL/DDL implementados;
arquitetura aberta para Firebird.

Instalável por [Boss](https://github.com/HashLoad/boss) em qualquer projeto Lazarus,
inclusive os que usam [Horse](https://github.com/HashLoad/horse).

## Instalar

```jsonc
// boss.json do seu projeto
"dependencies": {
  "github.com/SEU-USUARIO/lznex": "^1.0.0"
}
```

```sh
boss install
```

O ZeosLib vem junto, como dependência transitiva. A coordenada acima ainda é um
placeholder (`CHANGEME`): enquanto o repositório não for publicado, os Dockerfiles
montam `modules/` com o mesmo layout que o Boss produziria.

## Usar

```pascal
uses LzNex, LzNex.Client.MySQL;   // a unit do dialeto se registra sozinha

var
  Db: ILzNex;
begin
  Db := Connect(NewConfig
    .Client('mysql').Host('mysql').Database('app')
    .User('root').Password('secret')
    .LibraryLocation('/usr/lib/x86_64-linux-gnu/libmariadb.so.3')
    .Pool(2, 10));
```

```pascal
// select * from `users` where `active` = ? and (`role` = ? or `role` = ?) limit ?
Rows := Db.Table('users')
          .Where('active', True)
          .WhereOpen
            .Where('role', 'admin')
            .OrWhere('role', 'owner')
          .WhereClose
          .OrderBy('name').Limit(10).Get;

while Rows.Next do
  Writeln(Rows.Field('name').AsString);

Id    := Db.Table('users').InsertGetId(Vals(['name', 'Leonam', 'email', 'l@x.com']));
Total := Db.Table('users').Where('active', True).Count;
Rows  := Db.Table('posts')
           .Join('users').OnColumns('posts.user_id', '=', 'users.id')
           .LeftJoin('tags').OnValue('tags.active', '=', True)
           .Get;
```

```pascal
Trx := Db.Transaction;
try
  Trx.Table('users').Where('id', 1).Update(Vals(['balance', 0]));
  Trx.Table('audit').Insert(Vals(['action', 'reset']));
  Trx.Commit;
except
  raise;   // sem Commit, o destrutor faz rollback
end;
```

```pascal
Db.Schema.CreateTable('users')
  .Increments('id')
  .Str('email', 191).NotNull.Unique
  .Int('role_id').Unsigned.References('id').InTable('roles').OnDelete('CASCADE')
  .Json('meta').Nullable
  .Timestamps
  .Engine('InnoDB').Charset('utf8mb4')
  .Execute;
```

Migration em Pascal (`database/migrations/M20261024120000_create_users.pas`) ou em
`.sql` (`20261025090000_add_phone.up.sql` + `.down.sql`). As duas formas rodam no mesmo
batch, ordenadas por timestamp. As `.sql` não exigem recompilar.

## CLI

| Comando | O que faz |
|---|---|
| `lznex migrate:latest` | aplica as pendentes num novo batch |
| `lznex migrate:rollback [--all]` | desfaz o último batch (ou tudo) |
| `lznex migrate:up [nome]` / `migrate:down [nome]` | um passo |
| `lznex migrate:to <nome>` | até a migration informada |
| `lznex migrate:status` | aplicadas e pendentes |
| `lznex migrate:unlock` | libera lock de processo que morreu |
| `lznex migrate:make <desc> [--sql]` | cria a migration |
| `lznex seed:run [--only=nome]` / `seed:make <desc>` | seeds |

Config em `database/lznex.json` (com ambientes) ou pelas variáveis `LZNEX_HOST`,
`LZNEX_DATABASE`, `LZNEX_USER`, `LZNEX_PASSWORD`, `LZNEX_LIBRARY`, `LZNEX_PORT`.

## Rodar

```sh
docker compose run --rm tests          # unitários, sem banco
docker compose run --rm tests-it       # integração + concorrência (MySQL real)
docker compose run --rm cli migrate:latest
docker compose up -d api && curl localhost:9000/health
```

Saída observada na última execução:

```
Number of run tests: 146      core 19 | query 38 | security 4 | dialect 5
Number of errors:    0        postgres 66 | integration 9 | concurrency 5
Number of failures:  0

sondas: 870 asserções em 7 binários, todas verdes
heaptrc: 0 unfreed memory blocks (467.958 alocados, 467.958 liberados)
API: {"status":"ok","dialect":"mysql"}
```

## Threads

Pensado para servidor multi-thread (o provider FPC do Horse atende cada conexão HTTP
numa thread):

- pool com seção crítica; **uma conexão por operação**, devolvida por RAII
- `InsertGetId` pega o id na **mesma** conexão do insert — testado com 8 threads, cada
  id conferido contra a linha daquela thread
- transações isoladas entre threads; a conexão volta ao pool no `Commit`/`Rollback`
- um `ILzNexQuery` ou `ILzNexTransaction` **não** pode ser compartilhado entre threads

Programa que usa threads precisa de `cthreads` no início do `uses` (Unix).

## Troubleshooting

- **`Requested database driver was not found`** — falta `uses LzNex.Client.MySQL`. Unit
  não referenciada não é linkada, então o driver não se registra.
- **Migration em Pascal não aparece no `migrate:status`** — mesma causa: acrescente a
  unit ao `uses` de `database/Migrations.All.pas` (o `migrate:make` faz isso).
- **Erro de biblioteca ao conectar** — no Ubuntu 26.04 só existe `libmariadb.so.3` e o
  auto-load do Zeos não a encontra. Informe `LibraryLocation` ou `LZNEX_LIBRARY`.
- **`lazbuild` reclama de `directory lcl not found`** — falta o pacote `lazarus-src`,
  mesmo sem usar LCL.
- **Gate de vazamento inerte** — `-gh` precisa ir em `CustomOptions` do `.lpi`; a tag
  `<UseHeaptrc>` é ignorada pelo lazbuild.
- **DDL em MySQL não faz rollback** — o MySQL dá commit implícito em DDL. O migrator
  avisa; escreva a migration como passo único e reentrante.

## Limitações conhecidas

- PostgreSQL tem SQL e DDL implementados e testados **por texto**, sem banco real no
  compose: conexão, pool e migrator nunca rodaram contra um Postgres.
- `Change` (alterar tipo de coluna) gera DDL que o Postgres recusa — ele exige
  `alter column ... type` e `set not null` em comandos separados.
- `on conflict ... where` e enum nativo do Postgres não são expressáveis hoje.
