# Local stand-in for the Daytona build snapshot: same OS family, Node 24, Python 3.12 via uv, ffmpeg.
FROM mirror.gcr.io/library/node:24-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg git python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.9.5 /uv /usr/local/bin/uv
RUN npx -y playwright@1.57.0 install-deps chromium && rm -rf /root/.npm
