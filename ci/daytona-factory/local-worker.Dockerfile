# Local stand-in for the Daytona build snapshot: same OS family, Node 24, Python 3.12 via uv, ffmpeg,
# plus the PostgreSQL, Redis and Corepack-managed pnpm that the ABACare setup in build.sh starts.
FROM mirror.gcr.io/library/node:24-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg git python3 python3-venv \
    postgresql redis-server \
 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.9.5 /uv /usr/local/bin/uv
# pnpm resolves to the version each repository pins in packageManager.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable pnpm
RUN npx -y playwright@1.57.0 install-deps chromium && rm -rf /root/.npm
