# LzNex

Query builder, schema builder e migrations para **Lazarus/FPC**, com API fluente e
encadeável. Usa [ZeosLib](https://zeoslib.sourceforge.io) por baixo (camada DBC, sem
`TDataset`). Quatro dialetos: **MySQL/MariaDB, PostgreSQL, Firebird** (3 e 5) e
**SQLite** — a mesma suíte de integração roda contra os cinco bancos.

Instalável pela IDE (`lznex.lpk`) ou por [Boss](https://github.com/HashLoad/boss) em
qualquer projeto Lazarus, inclusive os que usam
[Horse](https://github.com/HashLoad/horse).

## Instalar

Pré-requisito: **ZeosLib 8**. O LzNex **não** traz o Zeos junto — quem instala é que o
fornece. É de propósito: vendorizar uma segunda cópia duplicaria as units de quem já tem
o Zeos instalado na IDE, e aí o build quebra.

**Pela IDE** — abra `lznex.lpk`, compile e adicione como dependência do seu projeto. O
`.lpk` requer o pacote `zdbc` ≥ 8, então a IDE resolve pelo Zeos que você já tem.

**Pelo Boss:**

```jsonc
// boss.json do seu projeto
"dependencies": {
  "github.com/leonampuzlplace/lznex": "^1.0.0"
}
```

```sh
boss install
```

O Boss resolve a versão pelas tags do repositório: cada entrega em `production` publica
uma tag `vX.Y.Z` pela GitHub Action, e é dela que sai o `^1.0.0` acima.

Projeto sem Zeos escolhe **uma** fonte: o pacote `zdbc` na IDE, ou a coordenada de um
fork do Zeos **com `boss.json`** no seu próprio `boss.json` (o repositório oficial não
tem manifesto, e o Boss aborta sem ele), ou um clone seu no unit path. Uma só.

## Usar

A unit do dialeto se registra sozinha — mas só se estiver no `uses` do **programa**:
`LzNex.Client.MySQL` (`mysql`, `mariadb`), `LzNex.Client.Postgres` (`postgresql`,
`postgres`), `LzNex.Client.Firebird` (`firebird`, serve ao 3 e ao 5) ou
`LzNex.Client.SQLite` (`sqlite`, `sqlite3`).

```pascal
uses LzNex, LzNex.Client.MySQL;

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

Três paginações, cada uma com o seu custo — e varredura em lotes para processar tabela
grande sem carregá-la na memória:

```pascal
// com total: duas queries (count num clone + janela), sabe quantas paginas existem
Page   := Db.Table('users').OrderBy('name').Paginate(2, 10);
Writeln(Page.Total, ' linhas em ', Page.LastPage, ' paginas');

// sem total: uma query (limit 11), responde apenas "ha proxima"
Simple := Db.Table('users').OrderBy('name').SimplePaginate(2, 10);

// por cursor (keyset): sem offset, nao repete nem perde linha se o conjunto mudar
Cursor := Db.Table('users').OrderBy('id').CursorPaginate(10, Token);
Token  := Cursor.NextCursor;   // texto opaco, url-safe

// varredura: lotes por chave, cursor fechado entre eles
Chunks := Db.Table('users').ChunkById(500);
while Chunks.Next do
  for I := 0 to High(Chunks.Rows) do
    Export(Chunks.Rows[I]);
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
`LZNEX_DATABASE`, `LZNEX_USER`, `LZNEX_PASSWORD`, `LZNEX_LIBRARY`, `LZNEX_PORT`,
`LZNEX_CHARSET`.

## Rodar

```sh
docker compose run --rm tests             # unitários, sem banco
docker compose run --rm tests-it          # integração + concorrência (MySQL real)
docker compose run --rm tests-it-pg       # a mesma suíte, contra PostgreSQL real
docker compose run --rm tests-it-fb3      # idem, Firebird 3
docker compose run --rm tests-it-fb5      # idem, Firebird 5
docker compose run --rm tests-it-sqlite   # idem, SQLite (arquivo no container)
docker compose run --rm cli migrate:latest
docker compose up -d api && curl localhost:9000/health
```

Saída observada na última execução, a mesma suíte contra cada banco:

```
tests-it         (MySQL)        468 testes · 0 erros · 0 falhas ·   1 ignorado  · exit 0
tests-it-pg      (PostgreSQL)   468 testes · 0 erros · 0 falhas ·   1 ignorado  · exit 0
tests-it-fb3     (Firebird 3)   468 testes · 0 erros · 0 falhas ·   8 ignorados · exit 0
tests-it-fb5     (Firebird 5)   468 testes · 0 erros · 0 falhas ·   8 ignorados · exit 0
tests-it-sqlite  (SQLite)       468 testes · 0 erros · 0 falhas ·   4 ignorados · exit 0
tests            (sem banco)    468 testes · 0 erros · 0 falhas · 100 ignorados · exit 0

sondas: 870 asserções em 7 binários, todas verdes
heaptrc: 0 unfreed memory blocks
API: {"status":"ok","dialect":"mysql"}
```

`exit 0` é o que prova que nada vazou: com `HEAPTRC=haltonnotreleased` o processo sai **203**
se sobrar bloco não liberado. Os ignorados são declarados por **capacidade do dialeto** (JSON
e texto completo no Firebird, texto completo e lock de linha no SQLite, upsert de várias
linhas), nunca por falta de banco.

As tabelas de teste nascem pelo schema builder, então cada execução também põe o DDL
daquele dialeto sob teste. O dialeto da integração sai de `LZNEX_CLIENT`.

Biblioteca cliente por dialeto, no Ubuntu (o auto-load do Zeos não acerta sozinho — use
`LibraryLocation` ou `LZNEX_LIBRARY`):

| Dialeto | `LibraryLocation` | Pacote |
|---|---|---|
| MySQL / MariaDB | `/usr/lib/x86_64-linux-gnu/libmariadb.so.3` | `libmariadb3` |
| PostgreSQL | `/usr/lib/x86_64-linux-gnu/libpq.so.5` | `libpq5` |
| Firebird | `/usr/lib/x86_64-linux-gnu/libfbclient.so.2` | `libfbclient2` |
| SQLite | `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0` | `libsqlite3-0` |

SQLite é banco em arquivo: `Database` é o caminho do arquivo e `Host` não se aplica. O
charset default do pacote (`utf8mb4`) é nome do MySQL — quando não é escolhido à mão, a
camada de conexão traduz para `UTF8` no Firebird e `UTF-8` no SQLite.

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

- **`Dialect "x" is not registered`** (ou `Requested database driver was not found`) —
  falta a unit do dialeto no `uses` do programa. Unit não referenciada não é linkada, então
  o `initialization` que registra o driver não roda.
- **Migration em Pascal não aparece no `migrate:status`** — mesma causa: acrescente a
  unit ao `uses` de `database/Migrations.All.pas` (o `migrate:make` faz isso).
- **`Can't find unit ZDbcIntfs`** — falta o Zeos. Instale o pacote `zdbc` na IDE ou
  aponte o unit path para a cópia do seu projeto (ver *Instalar*).
- **`Duplicate unit` ou `.ppu` incompatível numa unit do Zeos** — duas cópias no search
  path, em geral a da IDE e uma em `modules/`. Deixe uma.
- **Erro de biblioteca ao conectar** — o auto-load do Zeos não acerta o nome no Ubuntu, em
  nenhum dos quatro. Informe `LibraryLocation` ou `LZNEX_LIBRARY` (tabela acima).
- **Firebird: uma conexão não vê o commit de outra** — o default do servidor é snapshot. O
  LzNex abre em read committed e passa `hard_commit=True`; se você sobrescreveu um dos dois
  por `Prop`, é aí.
- **SQLite: `database is locked`** — o lock é do arquivo inteiro, um escritor por vez. O
  LzNex já aplica `busytimeout=5000` e `journal_mode=wal`; acima disso, serialize os
  escritores.
- **`lazbuild` reclama de `directory lcl not found`** — falta o pacote `lazarus-src`,
  mesmo sem usar LCL.
- **Gate de vazamento inerte** — `-gh` precisa ir em `CustomOptions` do `.lpi`; a tag
  `<UseHeaptrc>` é ignorada pelo lazbuild.
- **DDL em MySQL não faz rollback** — o MySQL dá commit implícito em DDL. O migrator
  avisa; escreva a migration como passo único e reentrante.

## Limitações conhecidas

- Fora da suíte automatizada: o CLI em si (o binário `lznex` e o parsing de subcomando) e
  as migrations em `.sql` — escritas para um dialeto só, não dariam para rodar nos cinco
  bancos. O runner de migrations por baixo está testado contra banco real nos cinco.
- `on conflict ... where` e enum nativo do Postgres não são expressáveis hoje. Seed em
  `.sql` é criada mas não executada.
- DDL não é transacional no MySQL (commit implícito): migration que falha no meio deixa
  atrás o que já executou.
- **Firebird** levanta erro claro em: `Intersect`/`Except_`, `OnConflict(...).Ignore`,
  `Merge` com lista de colunas ou valores explícitos, upsert de mais de uma linha,
  `NoWait`, `ForShare`, `DistinctOn`, `Limit`/`Join` em `update`/`delete`,
  `LastInsertId` (use `InsertGetId`) e renomear tabela. `SkipLocked` compila para
  `with lock skip locked`, que só existe a partir do Firebird 5.
- **SQLite** levanta erro claro em: `Returning` (use `InsertGetId`), `ForUpdate`/`ForShare`
  (o lock é do arquivo inteiro), `Change` (não há `ALTER COLUMN`), `add column ... not null`
  sem default, e `Primary`/chave estrangeira em tabela existente (não há
  `ADD CONSTRAINT`). `Comment` é ignorado em silêncio, e `WhereILike` sai igual a
  `WhereLike` — o `like` do SQLite ignora caixa só em ASCII.
- `Truncate` vira `delete from` em Firebird e SQLite; nenhum dos dois tem `TRUNCATE`.
- **JSON** em consulta (`WhereJsonPath`, `WhereJsonContains`, `WhereJsonLength`) existe em
  MySQL, PostgreSQL e SQLite; no Firebird não há tipo nem função de JSON, e o builder
  recusa com mensagem. **Texto completo** (`WhereFullText`, `ILzNexTable.FullText`) existe
  em MySQL e PostgreSQL; no SQLite seria tabela virtual FTS5 e no Firebird não há
  equivalente.
- **`CursorPaginate`** exige `OrderBy` e recusa `OrderByRaw`, ordem de nulos explícita,
  coluna de ordenação fora do `Select` e valor nulo na chave. A única condição que ele
  **não** detecta é a última chave não ser única — ordene por uma coluna única no fim (em
  geral a chave primária), ou linhas empatadas podem ser puladas.
- **Réplica de leitura** (`ReadReplica`) não tem *sticky*: leitura logo depois de escrita
  pode não ver o dado se a replicação estiver atrasada. Use `UsePrimary` ou uma transação.
