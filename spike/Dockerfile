# Imagem de toolchain do spike: FPC + Boss + Zeos + cliente MySQL.
# Nao compila nada aqui de proposito -- a compilacao roda via `docker run`,
# para iterar em erro de compilacao sem rebuildar a imagem.
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# fpc         -> compilador + fcl-db (exigido pelo FCL.lpk que os .lpk do Zeos pedem)
# lcl-utils   -> lazbuild
# lazarus-src -> fornece FCL.lpk e o "Lazarus directory" que o lazbuild exige
# libmariadb3 -> cliente MySQL; traz tambem o plugin caching_sha2_password.so
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

# Zeos 8.0.0-stable. No projeto final isso vira dependencia do Boss apontando
# para o fork com boss.json; aqui e clone direto so para validar a compilacao.
ARG ZEOS_REF=8.0.0-stable
RUN git clone --depth 1 --branch "${ZEOS_REF}" \
        https://github.com/marsupilami79/zeoslib.git /opt/zeos \
    && rm -rf /opt/zeos/.git

# Registra o ambiente real no build (a versao do FPC do apt pode ser 3.2.2 ou 3.2.4,
# e isso muda a assinatura dos comparadores de Generics.Defaults).
RUN echo "== fpc -iV ==" \
    && fpc -iV \
    && echo "== libs mysql/mariadb presentes ==" \
    && ls -la /usr/lib/x86_64-linux-gnu/ | grep -Ei 'maria|mysql' \
    && echo "== plugins do mariadb ==" \
    && ls /usr/lib/x86_64-linux-gnu/libmariadb3/plugin/

WORKDIR /work
