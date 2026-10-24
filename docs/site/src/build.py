#!/usr/bin/env python3
"""Monta docs/site/index.html a partir de template.html e dos fragmentos de pages/.

    python3 docs/site/src/build.py            monta (valida antes)
    python3 docs/site/src/build.py --check    so valida, nao escreve

A ordem das paginas vem do array NAV do proprio template, entao navegacao e
conteudo nunca saem de sincronia. Erro de estrutura derruba o build: um site
quebrado em silencio custa mais caro que um build vermelho.
"""
import pathlib
import re
import sys
from html.parser import HTMLParser

SRC = pathlib.Path(__file__).resolve().parent
SITE = SRC.parent
TEMPLATE = SRC / 'template.html'
PAGES = SRC / 'pages'
OUT = SITE / 'index.html'

FORBIDDEN_WORD = 'knex'
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
        'meta', 'source', 'track', 'wbr'}

errors, warnings = [], []


def fail(page, msg):
    errors.append('%s: %s' % (page, msg))


def warn(page, msg):
    warnings.append('%s: %s' % (page, msg))


# ------------------------------------------------------------------ template

def read_nav(template):
    """[(titulo, pasta, [(id, titulo), ...]), ...] na ordem do NAV.

    Varredura sequencial em vez de um regex aninhado: o NAV tem colchete dentro
    de colchete, e qualquer captura nao-gulosa do corpo do grupo para no `]` da
    ultima pagina, engolindo justamente ela.
    """
    block = re.search(r'var NAV = \[(.*?)\n\];', template, re.S)
    if not block:
        sys.exit('template.html: array NAV nao encontrado')

    groups = []
    token = re.compile(r"\['([^']+)',\s*'([a-z0-9-]+)',\s*\[|\['([a-z0-9-]+)',\s*'([^']*)'\]")
    for m in token.finditer(block.group(1)):
        if m.group(1) is not None:          # grupo: ['Titulo', 'pasta', [
            groups.append((m.group(1), m.group(2), []))
        elif groups:                        # pagina: ['id', 'Titulo']
            groups[-1][2].append((m.group(3), m.group(4)))

    if not groups or not any(pages for _, _, pages in groups):
        sys.exit('template.html: NAV nao tem nenhuma pagina')
    return groups


# ----------------------------------------------------------------- fragmentos

class Fragment(HTMLParser):
    """Confere balanceamento, ids dos titulos e colhe os links internos."""

    def __init__(self, page):
        super().__init__(convert_charrefs=True)
        self.page = page
        self.stack = []
        self.ids = set()
        self.links = []

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag in ('h2', 'h3'):
            if not d.get('id'):
                fail(self.page, '<%s> sem id na linha %d (o indice lateral usa o id)'
                     % (tag, self.getpos()[0]))
            elif d['id'] in self.ids:
                fail(self.page, 'id repetido na pagina: "%s"' % d['id'])
            else:
                self.ids.add(d['id'])
        elif 'id' in d:
            self.ids.add(d['id'])
        href = d.get('href', '')
        if href.startswith('#'):
            self.links.append(href[1:])
        if tag not in VOID:
            self.stack.append((tag, self.getpos()[0]))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack:
            fail(self.page, '</%s> sem abertura na linha %d' % (tag, self.getpos()[0]))
            return
        if self.stack[-1][0] != tag:
            fail(self.page, 'esperava </%s> (aberta na linha %d), veio </%s> na linha %d'
                 % (self.stack[-1][0], self.stack[-1][1], tag, self.getpos()[0]))
            for i in range(len(self.stack) - 1, -1, -1):
                if self.stack[i][0] == tag:
                    del self.stack[i:]
                    return
            return
        self.stack.pop()

    def finish(self):
        for tag, line in self.stack:
            fail(self.page, '<%s> aberta na linha %d e nunca fechada' % (tag, line))


def locate(pid):
    """O fragmento do id, em qualquer subpasta de pages/."""
    found = sorted(p for p in PAGES.rglob(pid + '.html') if not is_draft(p))
    if not found:
        return None
    if len(found) > 1:
        fail(pid, 'existe em mais de um lugar: ' +
             ', '.join(str(f.relative_to(PAGES)) for f in found))
    return found[0]


def check_word(name, src):
    if re.search(FORBIDDEN_WORD, src, re.I):
        fail(name, 'menciona "%s" — proibido no projeto' % FORBIDDEN_WORD)


def check_text(pid, src):
    check_word(pid, src)
    if 'style="' in src:
        fail(pid, 'usa style= inline; o estilo mora no template')
    for tag in ('section', 'script', 'style'):
        if '<%s' % tag in src:
            fail(pid, 'contem <%s>; o fragmento e so o miolo da pagina' % tag)
    if src.count('<article>') != 1 or src.count('</article>') != 1:
        fail(pid, 'precisa de exatamente um <article>…</article>')
    if src.count('<h1') != 1:
        fail(pid, 'precisa de exatamente um <h1> (achei %d)' % src.count('<h1'))


def is_draft(path):
    """Arquivo ou pasta comecando com _ e rascunho: fica fora do site."""
    return any(part.startswith(('_', '.')) for part in path.relative_to(PAGES).parts)


# --------------------------------------------------------------------- driver

def main():
    check_only = '--check' in sys.argv
    template = TEMPLATE.read_text(encoding='utf-8')
    check_word('template.html', template)

    # Sem o marcador, o replace vira no-op e o site sai sem pagina nenhuma —
    # com a sidebar montada e todo clique caindo numa pagina vazia.
    marks = template.count('<!-- PAGES -->')
    if marks != 1:
        sys.exit('template.html: esperava exatamente um <!-- PAGES -->, achei %d' % marks)

    if not any(not is_draft(p) for p in PAGES.rglob('*.html')):
        sys.exit('pages/ esta vazia: nada a montar')

    nav = read_nav(template)

    order = [(pid, gname, folder) for gname, folder, pages in nav for pid, _ in pages]
    known = {pid for pid, _, _ in order}

    seen = {}
    for pid, gname, _ in order:
        if pid in seen:
            fail('template.html', 'id "%s" aparece no NAV em "%s" e em "%s": sairiam duas '
                 '<section id="%s"> e a segunda ficaria morta' % (pid, seen[pid], gname, pid))
        seen[pid] = gname

    chunks, ids_by_page, links_by_page = [], {}, {}

    for pid, gname, folder in order:
        path = locate(pid)
        if path is None:
            fail(pid, 'esta no NAV mas nao existe em pages/ (esperado em pages/%s/%s.html)'
                 % (folder, pid))
            continue

        expected = PAGES / folder
        if path.parent != expected:
            warn(pid, 'esta em pages/%s mas o NAV o põe em pages/%s'
                 % (path.parent.relative_to(PAGES), folder))

        body = path.read_text(encoding='utf-8').strip()
        check_text(pid, body)

        frag = Fragment(pid)
        frag.feed(body)
        frag.finish()
        ids_by_page[pid] = frag.ids
        links_by_page[pid] = frag.links

        # Todas as paginas convivem no mesmo DOM, entao o id de cada titulo ganha
        # o prefixo da pagina: sem isso, duas paginas com uma secao "colunas"
        # fariam getElementById devolver a da pagina errada.
        body = re.sub(r'(<h[234][^>]*\sid=")([^"]+)(")',
                      lambda m: m.group(1) + pid + '__' + m.group(2) + m.group(3),
                      body)
        chunks.append('<section class="page hidden" id="%s">\n%s\n</section>' % (pid, body))

    for pid, links in links_by_page.items():
        for link in links:
            if not link:
                continue
            target, _, anchor = link.partition('/')
            if target not in known:
                fail(pid, 'link para pagina inexistente: #%s' % link)
            elif anchor and anchor not in ids_by_page.get(target, ()):
                fail(pid, 'link para ancora inexistente: #%s' % link)

    for path in sorted(PAGES.rglob('*.html')):
        if is_draft(path) or path.stem in known:
            continue
        fail(path.stem, 'pages/%s nao esta no NAV: registre em template.html, ou '
             'renomeie para _%s enquanto for rascunho'
             % (path.relative_to(PAGES).as_posix(), path.name))

    for w in warnings:
        print('aviso   ', w)
    for e in errors:
        print('ERRO    ', e)

    if errors:
        print('\n%d erro(s). %s nao foi escrito.' % (len(errors), OUT.name))
        sys.exit(1)

    if check_only:
        print('ok: %d paginas validas (nada foi escrito)' % len(chunks))
        return

    html = template.replace('<!-- PAGES -->', '\n\n'.join(chunks))
    html = html.replace(
        '<!DOCTYPE html>',
        '<!DOCTYPE html>\n<!-- GERADO por docs/site/src/build.py — nao edite aqui; '
        'edite src/pages/ e rode o build -->', 1)

    # newline fixo: rodado do Windows, o default do Python gravaria CRLF e o
    # diff do index.html viria com as 9 mil linhas trocadas.
    with OUT.open('w', encoding='utf-8', newline='\n') as fh:
        fh.write(html)

    print('ok: %d/%d paginas -> %s (%d KB, %d linhas)'
          % (len(chunks), len(order), OUT.relative_to(SITE.parent),
             len(html) // 1024, html.count('\n') + 1))


main()
