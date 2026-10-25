ARG UBUNTU_VERSION=26.04

FROM ubuntu:${UBUNTU_VERSION} AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        fpc \
        lcl-utils \
        lazarus-src \
        libmariadb3 \
        libpq5 \
        libfbclient2 \
        libsqlite3-0 \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

# O Zeos e dependencia do host, nao do pacote: o boss.json do LzNex nao o
# vendoriza, para nao duplicar units com um Zeos ja instalado na IDE. Aqui nao
# existe IDE, entao o container traz a propria copia -- e os .lpi apontam para
# modules/zeoslib.
ARG ZEOS_MIRROR=https://github.com/marsupilami79/zeoslib.git
ARG ZEOS_REF=8.0.0-stable

RUN set -eu; \
    echo "== Zeos ${ZEOS_REF} de ${ZEOS_MIRROR}"; \
    git clone --depth 1 --branch "${ZEOS_REF}" "${ZEOS_MIRROR}" modules/zeoslib; \
    rm -rf modules/zeoslib/.git; \
    ls -d modules/zeoslib/src/core

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
        libfbclient2 \
        libsqlite3-0 \
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
