ARG UBUNTU_VERSION=26.04

FROM ubuntu:${UBUNTU_VERSION} AS builder

ENV DEBIAN_FRONTEND=noninteractive

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

COPY src/ /vendor/lznex/src/
COPY boss.json /vendor/lznex/boss.json

ARG LZNEX_COORD=github.com/leonampuzlplace/lznex
ARG LZNEX_VERSION=^1.0.0
# vendor = monta modules/ a partir do fonte deste repositorio (nao depende de tag
# publicada); boss = instala de verdade pelo Boss, usando a tag do repositorio.
ARG LZNEX_SOURCE=vendor
ARG ZEOS_COORD=github.com/CHANGEME/zeoslib
ARG ZEOS_MIRROR=https://github.com/marsupilami79/zeoslib.git
ARG ZEOS_REF=8.0.0-stable

RUN set -eu; \
    sed -i "s|\"github.com/leonampuzlplace/lznex\": \"[^\"]*\"|\"${LZNEX_COORD}\": \"${LZNEX_VERSION}\"|" boss.json; \
    grep -q "\"${LZNEX_COORD}\"" boss.json; \
    sed -i "s|github_com_leonampuzlplace_lznex|$(echo "${LZNEX_COORD}" | tr './' '__')|g" Api.lpi; \
    sed -i "s|github_com_CHANGEME_zeoslib|$(echo "${ZEOS_COORD}" | tr './' '__')|g" Api.lpi

ARG HORSE_COORD=github.com/HashLoad/horse
ARG HORSE_VERSION=^3.3.15

RUN set -eu; \
    LZDIR="$(echo "${LZNEX_COORD}" | tr './' '__')"; \
    ZEDIR="$(echo "${ZEOS_COORD}" | tr './' '__')"; \
    case "${LZNEX_SOURCE}" in \
      vendor) \
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

RUN apt-get update && apt-get install -y --no-install-recommends \
        libmariadb3 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --shell /usr/sbin/nologin api

COPY --from=builder /app/bin/ /usr/local/bin/

ENV DB_LIB=/usr/lib/x86_64-linux-gnu/libmariadb.so.3

USER api
WORKDIR /home/api
EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/api"]
