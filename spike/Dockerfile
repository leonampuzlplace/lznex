FROM ubuntu:26.04

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

ARG ZEOS_REF=8.0.0-stable
RUN git clone --depth 1 --branch "${ZEOS_REF}" \
        https://github.com/marsupilami79/zeoslib.git /opt/zeos \
    && rm -rf /opt/zeos/.git

RUN echo "== fpc -iV ==" \
    && fpc -iV \
    && echo "== libs mysql/mariadb presentes ==" \
    && ls -la /usr/lib/x86_64-linux-gnu/ | grep -Ei 'maria|mysql' \
    && echo "== plugins do mariadb ==" \
    && ls /usr/lib/x86_64-linux-gnu/libmariadb3/plugin/

WORKDIR /work
