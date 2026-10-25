# Exemplo: API Horse sobre LzNex

Consome o LzNex pelo Boss, sem caminho relativo para o repositorio da lib.

## Trocar a coordenada do Boss

`boss.json` aponta para `github.com/leonampuzlplace/lznex`, que precisa virar a
coordenada real onde o LzNex foi publicado.

O Zeos nao vem pelo Boss: o LzNex nao o vendoriza, e o projeto que consome que o
fornece. Aqui o Dockerfile clona o repositorio oficial em `modules/zeoslib`, e e
para la que o `Api.lpi` aponta. Num projeto seu, vale igual ter o pacote `zdbc`
instalado na IDE -- o que nao vale e ter as duas copias.

Em `Api.lpi` os unit paths usam o nome da pasta que o Boss cria,
`modules/<host>_<org>_<repo>` (ponto e barra viram `_`). Trocar
`github.com/ACME/lznex` exige trocar `github_com_ACME_lznex` no `.lpi`.

No Docker isso e automatico via `--build-arg`:

```sh
docker build -f example/api/Dockerfile \
  --build-arg LZNEX_COORD=github.com/ACME/lznex \
  -t lznex-example-api .
```

Fora do Docker: edite `boss.json` e `Api.lpi`, rode
`bash ../../scripts/boss-install.sh` e `lazbuild --build-mode=Release Api.lpi`.

## Rotas

- `GET /health` -> ping no banco
- `GET /users` -> 20 primeiras linhas de `users`

Config por env: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`, `DB_LIB`.
