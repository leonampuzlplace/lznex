ARG UBUNTU_VERSION=26.04

FROM ubuntu:${UBUNTU_VERSION} AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        fpc \
        lcl-utils \
        lazarus-src \
        libmariadb3 \
        libpq5 \
        git \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

ARG BOSS_VERSION=3.0.17
RUN curl -fsSL "https://github.com/HashLoad/boss/releases/download/v${BOSS_VERSION}/boss_Linux_x86_64.tar.gz" \
      | tar -xz -C /usr/local/bin boss \
    && chmod +x /usr/local/bin/boss

WORKDIR /src
COPY . .

ARG ZEOS_COORD=github.com/CHANGEME/zeoslib
ARG ZEOS_VERSION=^8.0.0
ARG ZEOS_MIRROR=https://github.com/marsupilami79/zeoslib.git
ARG ZEOS_REF=8.0.0-stable

RUN set -eu; \
    DIR="$(echo "${ZEOS_COORD}" | tr './' '__')"; \
    sed -i "s|\"github.com/CHANGEME/zeoslib\": \"[^\"]*\"|\"${ZEOS_COORD}\": \"${ZEOS_VERSION}\"|" boss.json; \
    grep -q "\"${ZEOS_COORD}\"" boss.json; \
    for f in tools/LzNexCli.lpi tests/LzNexTests.lpi; do \
      [ -e "$f" ] && sed -i "s|github_com_CHANGEME_zeoslib|${DIR}|g" "$f"; \
    done; \
    echo "${ZEOS_COORD}" > /tmp/zeos-coord

RUN set -eu; \
    DIR="$(echo "${ZEOS_COORD}" | tr './' '__')"; \
    case "${ZEOS_COORD}" in \
      *CHANGEME*) \
        echo "== Zeos via clone direto (${ZEOS_REF}) -- coordenada ainda e placeholder"; \
        git clone --depth 1 --branch "${ZEOS_REF}" "${ZEOS_MIRROR}" "modules/${DIR}"; \
        rm -rf "modules/${DIR}/.git"; \
        ;; \
      *) \
        echo "== Zeos via boss install (${ZEOS_COORD})"; \
        bash scripts/boss-install.sh; \
        ;; \
    esac; \
    ls -d "modules/${DIR}/src/core"

RUN set -eu; \
    mkdir -p bin lib; \
    for p in tools/LzNexCli.lpi tests/LzNexTests.lpi; do \
      [ -e "$p" ] || continue; \
      for mode in Release Debug; do \
        echo "== lazbuild $p ($mode)"; \
        lazbuild --build-mode="$mode" "$p"; \
      done; \
    done; \
    ls -la bin

FROM ubuntu:${UBUNTU_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        libmariadb3 \
        libpq5 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --shell /usr/sbin/nologin lznex

COPY --from=builder /src/bin/ /usr/local/lib/lznex/
RUN ln -s /usr/local/lib/lznex/lznex /usr/local/bin/lznex

ENV LZNEX_LIBRARY=/usr/lib/x86_64-linux-gnu/libmariadb.so.3

USER lznex
WORKDIR /home/lznex
ENTRYPOINT ["/usr/local/bin/lznex"]
CMD ["--help"]
