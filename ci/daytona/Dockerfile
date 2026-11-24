# The general work image for scripts/daytona-run.mjs: Node, Python, PowerShell, ffmpeg, Docker Engine and the
# libraries headless Chrome needs (Remotion and Playwright).
# Docker Engine starts by itself inside a Daytona v2 Linux sandbox; /var/lib/docker must ship empty.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg git ripgrep ffmpeg python3 python3-pip python3-venv python-is-python3 xz-utils unzip jq openssh-client iptables procps \
      libnss3 libnspr4 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxkbcommon0 libdbus-1-3 \
      fonts-liberation fonts-noto-core fonts-noto-color-emoji \
 && install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/ms.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/ms.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main" > /etc/apt/sources.list.d/ms.list \
 && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y --no-install-recommends nodejs powershell docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
 && mkdir -p /usr/share/git-core/templates/hooks && echo "Hooks are added by the repository." > /usr/share/git-core/templates/hooks/README \
 && rm -rf /var/lib/docker /var/lib/containerd /var/lib/apt/lists/*
RUN npm install -g --no-audit --no-fund @anthropic-ai/claude-code@2.1.310 pnpm@11 \
 && mkdir -p /opt/kit-tsc && cd /opt/kit-tsc && npm init -y >/dev/null && npm i --no-audit --no-fund typescript@5.9.3 @types/node@24.10.1 \
 && pip3 install --break-system-packages --no-cache-dir pyyaml jsonschema pillow numpy pytest
