# Fonte da documentação

```
docs/site/
  index.html          GERADO pelo build — não edite à mão
  assets/tailwind.js  Tailwind embutido; a doc abre sem internet
  src/
    template.html     CSS, topbar, sidebar, índice, busca e o array NAV
    build.py          monta e valida
    pages/<grupo>/<id>.html
```

## Comandos

```sh
python3 docs/site/src/build.py           # monta docs/site/index.html
python3 docs/site/src/build.py --check   # só valida, não escreve

cd docs/site && python3 -m http.server 8777    # ver em http://localhost:8777
```

O build **falha com exit 1** e não escreve nada se achar: página do NAV sem arquivo,
arquivo duplicado em duas pastas, tag desbalanceada, `<h2>`/`<h3>` sem `id`, id repetido
na mesma página, link interno apontando para página ou âncora inexistente, `style=`
inline, `<section>`/`<script>`/`<style>` dentro do fragmento, ou menção ao knex.

Avisa sem falhar quando o arquivo está numa pasta diferente da do seu grupo, ou quando
sobra arquivo em `pages/` que não está no NAV.

## Página nova

Duas coisas, senão o build quebra de propósito:

1. criar `pages/<pasta-do-grupo>/<id>.html`;
2. registrar `['<id>', 'Título']` no `NAV` de `template.html`, dentro do grupo desejado.

A posição no `NAV` define a ordem da sidebar e os links anterior/próximo. Cada grupo é
`['Título visível', 'pasta-em-pages', [páginas…]]` — o título aparece na sidebar em
português, a pasta é onde o build procura os arquivos:

```js
['Operação', 'operations', [
  ['migrations', 'Migrations'], ['seeds', 'Seeds'], …
]],
```

Nomes de pasta, de arquivo e ids de página são **em inglês**; o que o leitor vê é em
português. O id vira a URL (`#migrations`) e o nome do arquivo (`migrations.html`), então
precisa ser único no site inteiro.

## Esqueleto de um fragmento

Só o miolo — nada de `<section>`, `<html>` ou `<script>`:

```html
<article>
<h1>Título da página</h1>
<p class="subtitle">Uma frase sobre o que a página cobre.</p>

<h2 id="ancora">Seção</h2>
<p>Texto…</p>
</article>
```

Todo `<h2>`/`<h3>` leva `id` em kebab-case sem acento: é o que alimenta o índice lateral.
`<h4>` não leva.

## Vocabulário de classes

**Código** — `data-lang` aceita `pascal`, `sql`, `json`, `sh`, `out`:

```html
<div class="code"><pre data-lang="pascal">Db.Table('users').Where('id', 1)</pre>
<div class="code-out">
  <div class="code-label">SQL</div>
  <pre data-lang="sql">select * from `users` where `id` = ?</pre>
  <p class="code-note">binds: 1</p>
</div>
</div>
```

**Abas de dialeto** — só quando o resultado muda mesmo por banco; o primeiro pane leva `on`:

```html
<div class="code" data-tabs>
  <div class="pane on" data-pane="mysql" data-label="MySQL">
    <pre data-lang="sql">select * from `t` limit ? offset ?</pre>
  </div>
  <div class="pane" data-pane="pg" data-label="PostgreSQL">
    <pre data-lang="sql">select * from "t" limit ? offset ?</pre>
  </div>
</div>
```

**Aviso** — `note` (informação), `warn` (cuidado), `trap` (armadilha silenciosa):

```html
<div class="callout trap">
  <span class="ico">⚠</span>
  <div class="body">
    <span class="t">Título curto</span>
    <p>Texto.</p>
  </div>
</div>
```

**Tabela** — `class="api"` na tabela de referência, com a assinatura completa na primeira
célula (é o que a busca indexa):

```html
<div class="table-wrap">
<table class="api">
<tbody>
<tr><td><code>function Table(const AName: string): ILzNexQuery</code></td><td>Começa uma query.</td></tr>
</tbody>
</table>
</div>
```

Também disponíveis: `.cards` + `a.card`, `.badges` + `.badge`, `<span class="yes">sim</span>`
e `<span class="no">não</span>` em tabelas de capacidade.

**Links** — outra página: `href="#pagina"`; seção de outra página: `href="#pagina/ancora"`.

## Regras de conteúdo

- Prosa em **pt-BR**. Identificadores, SQL e nomes de arquivo em inglês, como no código.
- O SQL dos exemplos é o **texto exato** que a lib gera — extraia de `tests/Test.Query.pas`,
  `tests/Test.Postgres.pas`, `tests/ProbeCompiler.lpr`, `tests/ProbeSchema.lpr`. Não invente.
- Assinaturas vêm de `src/LzNex.Intf.pas`, com os nomes de parâmetro.
- **Nunca** citar a biblioteca knex: dê a razão técnica direta no lugar da comparação.
- Explique o porquê quando não for óbvio, sobretudo armadilhas.
- `&lt;` e `&gt;` escapados em texto, `<code>` e `<pre>`.

## Tema

Escuro é o padrão; o claro só persiste se escolhido no botão. Paleta e layout seguem o
padrão do Supabase Docs. Para mexer em cor, as variáveis estão no `@layer base` de
`template.html`.
