# Render lane
Renders and encodes run on sh-forge (`ssh forge`), never on this PC. Capture stays local. Report the lane and the job's cost.

1. `node scripts/pack-render-bundle.mjs <job>/render` copies `render-program.mjs` and every module it loads.
2. Copy the job's kit, props, public assets and the bundle to `/srv/work/jobs/<job>/` on sh-forge, then run there:
   `node render/scripts/render-program.mjs --kit <kit> --composition <Name> --props <props> --out <out.mp4> --voice-seconds <n> --cli <remotion-cli.js>`.
   Reuse the Remotion install already on sh-forge; do not install a second copy per job.
3. Pull the rendered MP4 back, then master loudness and mux locally (`Finish-Media.ps1`).
4. Delete `/srv/work/jobs/<job>/` once the output is back and verified.

Never start another droplet, VM or cloud job for a render. If sh-forge is unreachable, stop and report it.
