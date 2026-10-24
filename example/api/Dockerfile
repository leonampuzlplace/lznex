# API Horse de exemplo. Build a partir da RAIZ do repositorio, porque reusa
# scripts/boss-install.sh:
#
#   docker build -f example/api/Dockerfile -t lznex-example-api .
#
# De proposito NAO copia o src/ do LzNex: a lib tem que chegar pelo
# `boss install`, senao o exemplo nao prova nada.
ARG UBUNTU_VERSION=26.04

FROM ubuntu:${UBUNTU_VERSION} AS builder

ENV DEBIAN_FRONTEND=noninteractive

# fpc         -> compilador + fcl-db (o Horse e o Zeos dependem do FCL)
# lcl-utils   -> lazbuild
# lazarus-src -> obrigatorio mesmo sem LCL: sem ele o lazbuild aborta com
#                "Invalid Lazarus directory: directory lcl not found"
# libmariadb3 -> cliente MySQL (o libmysqlclient21 nao existe no 26.04)
# git         -> o Boss resolve dependencia clonando
# curl + ca-certificates -> baixar o Boss e falar HTTPS com os hosts dos pacotes
RUN apt-get update && apt-get install -y --no-install-recommends \
        fpc \
        lcl-utils \
        lazarus-src \
        libmariadb3 \
        git \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

ARG BOSS_VERSION=3.0.17
RUN curl -fsSL "https://github.com/HashLoad/boss/releases/download/v${BOSS_VERSION}/boss_Linux_x86_64.tar.gz" \
      | tar -xz -C /usr/local/bin boss \
    && chmod +x /usr/local/bin/boss

WORKDIR /app
COPY scripts/ ./scripts/
COPY example/api/ ./

# Fonte do LzNex e do Zeos, usada SO no modo prova-local (ver abaixo). Fica
# num diretorio separado de proposito: o build nunca poe /app/src no unit path,
# entao a lib so chega pela arvore modules/, que e o que o Boss montaria.
COPY src/ /vendor/lznex/src/
COPY boss.json /vendor/lznex/boss.json

# Coordenada do LzNex publicado. O Boss so aceita coordenada HTTPS: ele monta
# sempre https://<nome>/info/refs?service=git-upload-pack.
ARG LZNEX_COORD=github.com/CHANGEME/lznex
ARG LZNEX_VERSION=^1.0.0
# O zeoslib nao esta no boss.json (vem transitivo pelo lznex), mas o .lpi
# referencia a pasta dele, que leva o nome da coordenada.
ARG ZEOS_COORD=github.com/CHANGEME/zeoslib
ARG ZEOS_MIRROR=https://github.com/marsupilami79/zeoslib.git
ARG ZEOS_REF=8.0.0-stable

RUN set -eu; \
    sed -i "s|\"github.com/CHANGEME/lznex\": \"[^\"]*\"|\"${LZNEX_COORD}\": \"${LZNEX_VERSION}\"|" boss.json; \
    grep -q "\"${LZNEX_COORD}\"" boss.json; \
    sed -i "s|github_com_CHANGEME_lznex|$(echo "${LZNEX_COORD}" | tr './' '__')|g" Api.lpi; \
    sed -i "s|github_com_CHANGEME_zeoslib|$(echo "${ZEOS_COORD}" | tr './' '__')|g" Api.lpi

# Enquanto a coordenada for o placeholder, monta modules/ com o MESMO layout que
# o `boss install` produziria -- inclusive a dependencia transitiva do Zeos.
# Prova que o pacote e consumivel nesse formato; quando o repo for publicado,
# passar --build-arg LZNEX_COORD=... troca para o boss install de verdade.
ARG HORSE_COORD=github.com/HashLoad/horse
ARG HORSE_VERSION=^3.3.15

RUN set -eu; \
    LZDIR="$(echo "${LZNEX_COORD}" | tr './' '__')"; \
    ZEDIR="$(echo "${ZEOS_COORD}" | tr './' '__')"; \
    case "${LZNEX_COORD}" in \
      *CHANGEME*) \
        echo "== modo prova-local: Horse vem do Boss de verdade; LzNex e Zeos"; \
        echo "   sao montados com o MESMO layout que o boss install produziria."; \
        cp boss.json /tmp/boss.json.orig; \
        cp Api.lpi /tmp/Api.lpi.orig; \
        printf '%s\n' \
          '{' \
          '  "name": "lznex-example-api",' \
          '  "version": "1.0.0",' \
          '  "mainsrc": "src/",' \
          '  "projects": ["Api.lpi"],' \
          '  "dependencies": { "'"${HORSE_COORD}"'": "'"${HORSE_VERSION}"'" }' \
          '}' > boss.json; \
        bash scripts/boss-install.sh; \
        cp /tmp/boss.json.orig boss.json; \
        cp /tmp/Api.lpi.orig Api.lpi; \
        mkdir -p "modules/${LZDIR}"; \
        cp -a /vendor/lznex/src "modules/${LZDIR}/src"; \
        cp /vendor/lznex/boss.json "modules/${LZDIR}/boss.json"; \
        git clone --depth 1 --branch "${ZEOS_REF}" "${ZEOS_MIRROR}" "modules/${ZEDIR}"; \
        rm -rf "modules/${ZEDIR}/.git"; \
        ;; \
      *) \
        echo "== boss install de verdade (${LZNEX_COORD})"; \
        bash scripts/boss-install.sh; \
        ;; \
    esac; \
    ls -d "modules/${LZDIR}/src" "modules/${ZEDIR}/src/dbc"; \
    ls -d modules/*horse*/src

RUN set -eu; \
    mkdir -p bin lib; \
    for mode in Release Debug; do \
      echo "== lazbuild Api.lpi ($mode)"; \
      lazbuild --build-mode="$mode" Api.lpi; \
    done


FROM ubuntu:${UBUNTU_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# libmariadb3     -> a lib que o Zeos carrega em runtime; traz tambem o
#                    plugin caching_sha2_password.so que o MySQL 8 exige
# ca-certificates -> TLS para o banco
RUN apt-get update && apt-get install -y --no-install-recommends \
        libmariadb3 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --shell /usr/sbin/nologin api

COPY --from=builder /app/bin/ /usr/local/bin/

# O auto-load do Zeos falha no 26.04; o Api.lpr le isto e passa para
# LibraryLocation.
ENV DB_LIB=/usr/lib/x86_64-linux-gnu/libmariadb.so.3

USER api
WORKDIR /home/api
EXPOSE 9000
# O provider FPC do Horse ja escuta em 0.0.0.0:9000.
ENTRYPOINT ["/usr/local/bin/api"]
