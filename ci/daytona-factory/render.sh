#!/usr/bin/env bash
set -euo pipefail

props=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration \
  -of json public/capture.webm | node -e '
  const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const {width, height} = data.streams[0];
  const frames = Math.floor(Number(data.format.duration) * 25);
  if (!frames || width < 2 || height < 2 || width % 2 || height % 2) process.exit(1);
  console.log(JSON.stringify({frames, width, height}));
')
./node_modules/.bin/remotion render index.tsx Capture demo.mp4 \
  --props="$props" --concurrency=2 --x264-threads=2
ffmpeg -v error -xerror -i demo.mp4 -f null -
