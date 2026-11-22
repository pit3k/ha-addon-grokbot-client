FROM ghcr.io/home-assistant/base:3.24

ARG BUILD_ARCH=amd64
ARG BUILD_VERSION=0.1.0
ARG HA_CLI_VERSION=6.0.0

COPY panel/server.c /tmp/grokbot-panel.c

RUN apk add --no-cache \
        bash \
        curl \
        ca-certificates \
        coreutils \
        tzdata \
        git \
        jq \
        ripgrep \
        openssh-client \
    && apk add --no-cache --virtual .panel-build build-base \
    && gcc -std=c11 -Os -s -Wall -Wextra -Werror -o /usr/bin/grokbot-panel /tmp/grokbot-panel.c \
    && rm /tmp/grokbot-panel.c \
    && apk del .panel-build \
    && curl -fsSL -o /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${HA_CLI_VERSION}/ha_${BUILD_ARCH}" \
    && chmod 0755 /usr/bin/ha \
    && /usr/bin/ha --help >/dev/null

COPY rootfs /

RUN chmod 0755 \
        /usr/lib/grokbot/run.sh \
        /etc/s6-overlay/s6-rc.d/init-grokbot/run \
        /etc/s6-overlay/s6-rc.d/grokbot/run \
        /etc/s6-overlay/s6-rc.d/grokbot/finish \
        /etc/s6-overlay/s6-rc.d/panel/run \
        /etc/s6-overlay/s6-rc.d/panel/finish

LABEL \
    io.hass.name="Grok Bot client" \
    io.hass.description="Connects a Grok Bot agent to this Home Assistant system" \
    io.hass.type="app" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Grok Bot client" \
    org.opencontainers.image.description="Home Assistant app that runs grokbot-tunnel" \
    org.opencontainers.image.source="https://github.com/pit3k/ha-addon-grokbot-client" \
    org.opencontainers.image.licenses="Apache-2.0"

ENV HOME=/data \
    SHELL=/bin/bash \
    GROKBOT_BIN=/data/.local/bin/grokbot-tunnel

# The app linter rejects the old watchdog key. This check is the replacement:
# the panel's status URL answers only after the panel process is up.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8099/api/status >/dev/null || exit 1
