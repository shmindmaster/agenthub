# Daytona v2 image rexa-remotion-4-0-517-v2. A v2 build stores at most 16384 new files, so
# node_modules (with the headless shell) ships as one archive the render step unpacks.
FROM node:24-bookworm
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ffmpeg libnss3 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libpangocairo-1.0-0 libpango-1.0-0 libcairo2 fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
RUN mkdir -p /opt/base && cd /opt/base \
 && echo '{"name":"rexa-render","private":true,"dependencies":{"@remotion/cli":"4.0.517","remotion":"4.0.517","react":"19.2.3","react-dom":"19.2.3"}}' > package.json \
 && npm install --no-audit --no-fund --loglevel=error && npx remotion browser ensure && npm cache clean --force \
 && tar -czf node_modules.tar.gz node_modules && rm -rf node_modules
