#!/usr/bin/env bash
# Runs on a Daytona box (scripts/daytona-run.mjs --script): capture the synthetic ledger page with the screen stage, compose the
# film, run the gates, and leave everything worth pulling back under /work/out. Never run on the owner's PC.
# Env: PROOF_JOB_FLAGS (extra make-proof-job flags), PROOF_BASE (film base name, default proof)
set -uo pipefail
R=/work/repo/packages/media-studio
J=/work/job
OUT=/work/out
BASE=${PROOF_BASE:-proof}
mkdir -p "$OUT" "$OUT/frames" "$OUT/qa"
t() { date +%s.%N; }
step() { echo "=== $1"; }
T0=$(t)
step "npm ci (kit)"
cd "$R/kit" && npm ci --no-audit --no-fund --silent 2>&1 | tail -3
step "playwright chromium"
npx playwright install chromium 2>&1 | tail -2
T1=$(t)
step "job"
rm -rf "$J"
node "$R/tests/fixtures/screen-stage/make-proof-job.mjs" "$J" ${PROOF_JOB_FLAGS:-}
node "$R/tests/fixtures/screen-stage/serve.mjs" 4811 > "$OUT/serve.log" 2>&1 &
SERVE=$!
sleep 1
step "capture (screen stage)"
cd "$J"
node "$R/kit/screencast/record-job.mjs" "$J" 2>&1 | tee "$OUT/record.log"
RC=$?
T2=$(t)
kill "$SERVE" 2>/dev/null
cp -r "$J/capture/receipt.json" "$J/capture/recordings.json" "$OUT/" 2>/dev/null
ls "$J/capture/raw/S01/frames" 2>/dev/null | head -400 | wc -l | xargs echo "frames captured:"
ffprobe -v error -show_entries stream=width,height,r_frame_rate -show_entries format=duration -of default=nw=1 "$J/capture/clips/S01.mp4" 2>&1 | tee "$OUT/clip-probe.txt"
if [ "$RC" -ne 0 ]; then echo "record-job failed"; exit "$RC"; fi
step "cue sheet (plan)"
node "$R/scripts/build-cue-sheet.mjs" "$J" 2>&1 | tail -5
step "compose (stage render)"
node "$R/kit/screencast/compose-screencast.mjs" "$J" "$BASE" 2>&1 | tee "$OUT/compose.log"
RC=$?
T3=$(t)
cp "$J/output/$BASE-silent.mp4" "$J/output/$BASE-compose-map.json" "$J"/output/$BASE-stage-plan-*.json "$OUT/" 2>/dev/null
if [ "$RC" -ne 0 ]; then echo "compose failed"; exit "$RC"; fi
step "cue sheet (mapped)"
node "$R/scripts/build-cue-sheet.mjs" "$J" 2>&1 | tail -3
step "gates"
for g in validate-pointer-path validate-product-picture; do
  node "$R/scripts/$g.mjs" "$J" > "$OUT/qa/$g.log" 2>&1; echo "$g exit $?"
done
for g in validate-screen-stage validate-encoded-picture validate-sync; do
  [ -f "$R/scripts/$g.mjs" ] || continue
  node "$R/scripts/$g.mjs" "$J" "$J/output/$BASE-silent.mp4" > "$OUT/qa/$g.log" 2>&1; echo "$g exit $?"
done
cp "$J"/qa/*.json "$OUT/qa/" 2>/dev/null
# negative controls: the gate must FAIL on core-v1 style pictures. Files arrive with --put under /work/v1 (the core-v1 renderer).
step "negative controls"
M="$J/output/$BASE-compose-map.json"
if [ -f /work/v1/ScreenStage.tsx ]; then
  rm -rf /work/v1kit && mkdir -p /work/v1kit && (cd "$R/kit" && tar --exclude=node_modules -cf - .) | tar -C /work/v1kit -xf - && ln -s "$R/kit/node_modules" /work/v1kit/node_modules
  cp /work/v1/ScreenStage.tsx /work/v1kit/src/ScreenStage.tsx && cp /work/v1/stage-math.mjs /work/v1kit/screencast/stage-math.mjs
  node "$R/kit/screencast/render-stage.mjs" --kit /work/v1kit --plan "$J/output/$BASE-stage-plan-0.json" --public-dir "$J/capture/raw" --out "$J/output/neg-v1-silent.mp4" > "$OUT/qa/neg-v1-render.log" 2>&1
  cp "$M" "$J/output/neg-v1-compose-map.json"
  node "$R/scripts/validate-screen-stage.mjs" "$J" "$J/output/neg-v1-silent.mp4" --out qa/neg-v1.json > "$OUT/qa/neg-v1.log" 2>&1; echo "negative v1 renderer exit $?"
fi
ffmpeg -hide_banner -loglevel error -y -i "$J/output/$BASE-silent.mp4" -vf "fade=t=in:st=0:d=0.5,format=yuv420p" -r 60 -c:v libx264 -crf 17 "$J/output/neg-fade-silent.mp4"
cp "$M" "$J/output/neg-fade-compose-map.json"
node "$R/scripts/validate-screen-stage.mjs" "$J" "$J/output/neg-fade-silent.mp4" --out qa/neg-fade.json > "$OUT/qa/neg-fade.log" 2>&1; echo "negative fade exit $?"
ffmpeg -hide_banner -loglevel error -y -i "$J/output/$BASE-silent.mp4" -r 30 -c:v libx264 -crf 17 "$J/output/neg-30fps-silent.mp4"
cp "$M" "$J/output/neg-30fps-compose-map.json"
node "$R/scripts/validate-screen-stage.mjs" "$J" "$J/output/neg-30fps-silent.mp4" --out qa/neg-30fps.json > "$OUT/qa/neg-30fps.log" 2>&1; echo "negative 30fps exit $?"
cp "$J"/qa/*.json "$OUT/qa/" 2>/dev/null
cp "$J"/output/neg-*-silent.mp4 "$OUT/" 2>/dev/null
cp "$J"/capture/raw/S01/frames.json "$OUT/frames.json"
# a few source frames for the sharpness comparison against the zoomed stills
cp "$J/capture/raw/S01/frames.json" "$OUT/frames.json"
for f in $(ls "$J/capture/raw/S01/frames" | sed -n '1p;8p;16p;24p;33p'); do cp "$J/capture/raw/S01/frames/$f" "$OUT/frames/"; done
T4=$(t)
python3 -c "import json,sys; a=[float(x) for x in sys.argv[1:]]; print(json.dumps({'setupSeconds':round(a[1]-a[0],1),'captureSeconds':round(a[2]-a[1],1),'composeRenderSeconds':round(a[3]-a[2],1),'gatesSeconds':round(a[4]-a[3],1)}))" "$T0" "$T1" "$T2" "$T3" "$T4" | tee "$OUT/timing.json"
echo "nproc: $(nproc)  mem: $(free -g | awk '/Mem/{print $2}') GiB" | tee -a "$OUT/timing.txt"
tar -C /work -cf /work/out.tar out
ls -la /work/out.tar
