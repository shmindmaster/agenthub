# Daytona v2 image factory-node-build-v2. A v2 build stores at most 16384 new files, so it
# starts from the full Debian Python image (compilers and headers included), drops docs and
# removes the pgvector build headers once the extension is installed. uv downloads the
# Python a project pins (abacare: 3.13) on first use instead of baking it in.
FROM python:3.12.10-bookworm
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
 && apt-get update \
 && apt-get install -y --no-install-recommends gcc gfortran build-essential curl git ca-certificates unzip \
    libpq-dev postgresql redis-server postgresql-server-dev-15 \
 && git clone --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector \
 && make -C /tmp/pgvector && make -C /tmp/pgvector install \
 && apt-get purge -y postgresql-server-dev-15 \
 && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g pnpm@11 && npm cache clean --force \
 && pip install --no-cache-dir --upgrade pip \
 && curl -LsSf https://astral.sh/uv/install.sh | sh \
 && ln -sf /root/.local/bin/uv /usr/local/bin/uv && ln -sf /root/.local/bin/uvx /usr/local/bin/uvx \
 && uv cache clean \
 && rm -rf /tmp/pgvector /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
