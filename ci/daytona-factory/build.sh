#!/usr/bin/env bash
set -euo pipefail

app=$1
sha=$2
suite=${SUITE:-demo}
probe=${PROBE:-none}
root=/tmp/factory
out=$root/out
evidence=$out/evidence
mkdir -p "$evidence"
cd "$root/source"
tar -xzf "$root/source.tar.gz"
export CI=1 NEXT_TELEMETRY_DISABLED=1
export DEMO_SOURCE_REVISION="$sha" REVOLVA_VERSION="$sha"

# Package caches survive between runs only where the worker mounts a lockfile-keyed volume.
if [[ -n "${FACTORY_CACHE_DIR:-}" ]]; then
  export npm_config_cache=$FACTORY_CACHE_DIR/npm
  export UV_CACHE_DIR=$FACTORY_CACHE_DIR/uv PLAYWRIGHT_BROWSERS_PATH=$FACTORY_CACHE_DIR/ms-playwright
fi
version() { "$@" 2>/dev/null | head -n1 || true; }
python3 - "$out/toolchain.json" <<PY
import json, platform, sys
json.dump({"os": platform.platform(), "node": "$(version node --version)", "npm": "$(version npm --version)",
           "python": platform.python_version(), "uv": "$(version uv --version)",
           "nproc": "$(nproc)", "cache_dir": "${FACTORY_CACHE_DIR:-}", "suite": "$suite",
           "probe": "$probe"}, open(sys.argv[1], "w"), indent=2)
PY
echo "factory: suite=$suite probe=$probe started $(date -u +%FT%TZ)"
case "$probe" in
  fail) echo "factory probe: intentional failure before build"; exit 41 ;;
  hang) echo "factory probe: holding the worker until the deadline or cancellation"; sleep 7200 ;;
esac

# Section 8 journeys against the app's isolated real API and temporary database; every video,
# trace and JUnit report is exported even when a test fails, and failures keep their exit code.
journeys() {
  local status=0
  "$@" || status=$?
  find . -path ./node_modules -prune -o \( -name '*.webm' -o -name 'trace.zip' \) -path '*test-results*' \
    -print | while read -r file; do
      dest="$evidence/videos/$(dirname "$file" | sed 's#^\./##; s#/#__#g')"
      mkdir -p "$dest"; cp "$file" "$dest/"
    done
  tar -czf "$out/journeys.tar.gz" -C "$out" evidence
  echo "factory: journeys exit $status"
  exit "$status"
}

case "$app" in
  abacare)
    service postgresql start
    service redis-server start
    su postgres -c 'createuser -s abacare_qa'
    su postgres -c 'createdb -O abacare_qa abacare_qa'
    su postgres -c "psql -c \"ALTER USER abacare_qa WITH PASSWORD 'abacare_qa'\""
    export DATABASE_URL=postgresql://abacare_qa:abacare_qa@127.0.0.1:5432/abacare_qa
    export VALKEY_URL=redis://127.0.0.1:6379/0
    export ABACARE_RUNTIME_PROFILE=local ABACARE_TEST_USE_DATABASE_URL=1
    pnpm install --frozen-lockfile
    (
      cd apps/api
      uv sync --extra dev
      uv run alembic upgrade head
      uv run --extra dev python -m pytest -q -p no:warnings \
        tests/services/demo/test_public_voice.py tests/routers/test_public_voice_socket.py
    )
    ABACARE_DISABLE_SENTRY_UPLOAD=1 VITE_AUTH_DISABLED=1 VITE_API_URL=/api \
      pnpm --filter @abacare/web build:docker
    pnpm --filter @abacare/web exec playwright install --with-deps chromium
    preview_dir="$PWD/apps/web/dist"
    ;;
  empowera)
    uv venv "$root/empowera-python" --python 3.12
    export PATH="$root/empowera-python/bin:$PATH"
    uv pip install -r apps/api/requirements-readiness-dev.txt
    npm install --prefix "$root/empowera-pnpm" --no-audit --no-fund pnpm@10.30.3
    export PATH="$root/empowera-pnpm/node_modules/.bin:$PATH"
    if [[ -n "${FACTORY_CACHE_DIR:-}" ]]; then pnpm config set store-dir "$FACTORY_CACHE_DIR/pnpm-store"; fi
    node scripts/ci/check-config-payloads.mjs --root .
    pnpm install --frozen-lockfile
    pnpm --filter @empowera/web build
    python scripts/release/test_standalone_output.py --build-root "$PWD"
    pnpm exec playwright install --with-deps chromium
    if [[ "$suite" == journey ]]; then
      sed -i 's/video: "off"/video: "on"/' playwright.config.ts
      PLAYWRIGHT_JUNIT_OUTPUT_NAME="$evidence/junit.xml" journeys pnpm exec playwright test \
        tests/readiness/workflow.spec.ts tests/readiness/procedure-revision.spec.ts \
        tests/readiness/bound-learner.spec.ts --project=chromium-desktop-1440 --retries=0 \
        --reporter=list,junit
    fi
    sed -i 's/video: "off"/video: "on"/' playwright.config.ts
    pnpm exec playwright test tests/readiness/film-path.spec.ts --project=chromium-desktop-1440 --reporter=list
    pnpm exec playwright test tests/readiness/film-path.spec.ts --project=chromium-desktop-1440 \
      --grep "an action.s outcome" --output "$root/capture" --reporter=list
    capture=$(find "$root/capture" -name video.webm -type f -print -quit)
    test -n "$capture"
    cp "$capture" "$out/capture.webm"
    nohup python scripts/test/readiness_e2e_api.py >"$out/preview.log" 2>&1 </dev/null &
    READINESS_API_BASE=http://127.0.0.1:8094 \
      nohup pnpm --filter @empowera/web exec next start --hostname 0.0.0.0 --port 4173 >>"$out/preview.log" 2>&1 </dev/null &
    ;;
  revolva)
    npm ci
    npm run build
    npx playwright install --with-deps chromium
    if [[ "$suite" == journey ]]; then
      sed -i 's/trace: "retain-on-failure"/trace: "retain-on-failure", video: "on"/' \
        playwright.config.ts playwright.rehearsal.config.ts
      PLAYWRIGHT_JUNIT_OUTPUT_NAME="$evidence/junit.xml" journeys bash -c '
        npx playwright test e2e/mobility-workspace.spec.ts e2e/mobility-guest-entry.spec.ts \
          --retries=0 --reporter=list,junit --output test-results-journeys \
          --grep "new assignment saves real uploaded values|keyboard amendment reopens approval|invalid guest link opened|guest links opened before earlier replies" &&
        PLAYWRIGHT_JUNIT_OUTPUT_NAME='"$evidence"'/junit-rehearsal.xml npm run test:rehearsal -- \
          e2e-rehearsal/enterprise-imports.spec.ts --retries=0 --reporter=list,junit'
    fi
    sed -i 's/trace: "retain-on-failure"/trace: "retain-on-failure", video: "on"/' playwright.rehearsal.config.ts
    npm run test:rehearsal -- --reporter=list
    capture=$(find test-results -path '*enterprise-imports*' -name video.webm -type f -print -quit)
    test -n "$capture"
    cp "$capture" "$out/capture.webm"
    preview_dir="$PWD/dist"
    ;;
  *)
    exit 2
    ;;
esac

if [[ -v preview_dir ]]; then
  nohup python3 -m http.server 4173 --bind 0.0.0.0 --directory "$preview_dir" >"$out/preview.log" 2>&1 </dev/null &
fi
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:4173/ >/dev/null; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:4173/ >/dev/null

case "$app" in
  abacare)
    node scripts/ci/daytona_capture.mjs
    cp /tmp/abacare-demo/{capture.webm,claim.png} "$out/"
    ;;
esac
