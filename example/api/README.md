# Exemplo: API Horse sobre LzNex

Consome o LzNex pelo Boss, sem caminho relativo para o repositorio da lib.

## Trocar a coordenada do Boss

`boss.json` aponta para placeholders que precisam virar os forks reais:

- `github.com/leonampuzlplace/lznex` -> onde o LzNex foi publicado
- `github.com/CHANGEME/zeoslib` -> o fork do Zeos **com `boss.json`** (o Boss
  aborta se uma dependencia nao tiver o manifesto). Vem transitivo pelo lznex,
  por isso nao aparece no `boss.json` daqui.

Em `Api.lpi` os unit paths usam o nome da pasta que o Boss cria,
`modules/<host>_<org>_<repo>` (ponto e barra viram `_`). Trocar
`github.com/ACME/lznex` exige trocar `github_com_ACME_lznex` no `.lpi`.

No Docker isso e automatico via `--build-arg`:

```sh
docker build -f example/api/Dockerfile \
  --build-arg LZNEX_COORD=github.com/ACME/lznex \
  --build-arg ZEOS_COORD=github.com/ACME/zeoslib \
  -t lznex-example-api .
```

Fora do Docker: edite `boss.json` e `Api.lpi`, rode
`bash ../../scripts/boss-install.sh` e `lazbuild --build-mode=Release Api.lpi`.

## Rotas

- `GET /health` -> ping no banco
- `GET /users` -> 20 primeiras linhas de `users`

Config por env: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`, `DB_LIB`.
