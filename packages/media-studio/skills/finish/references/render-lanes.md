# Render lane
Renders and encodes run on Daytona, never on this PC. Capture stays local. Report the lane, the box size, the minutes and the job's cost.

Use the AgentHub command `node <AgentHub>/scripts/daytona-run.mjs` (Daytona v2, Linux). Its box has Node, Python, ffmpeg and the libraries headless Chrome needs, and it is deleted when the command ends.

1. `node scripts/pack-render-bundle.mjs <job>/render` copies `render-program.mjs` and every module it loads.
2. Pack the job's props, public assets and the bundle into one tar file (no credentials, customer data or PHI).
3. Render, and pull the file back with a hash check:
   `node <AgentHub>/scripts/daytona-run.mjs --owner <project> --cpu 8 --memory 16 --minutes 60 --put job.tar=/work/job.tar --get /work/job/out.mp4=<job>/out/candidate.mp4 --script render.sh`
   where `render.sh` unpacks the tar to `/work/job`, runs `npm ci` in `packages/media-studio/kit`, then
   `node /work/job/render/scripts/render-program.mjs --kit <kit> --composition <Name> --props <props> --out /work/job/out.mp4 --voice-seconds <n> --cli <remotion-cli.js>`.
   The command sends the committed revision only. A kit change that is not committed is not on the box.
4. Master loudness and mux as before (`Finish-Media.ps1`).

Split a long program across boxes by scene and join the parts; each part is accepted only when its hash matches. A job that already has a Daytona v1 snapshot and driver may keep using it.

The kit's Briefing composition was rendered this way on 2026-11-24 (90 frames at 1600x1000 in 3 s on 8 cores). A full program with narration and product clips has not been.

If Daytona is unavailable, stop and report it. Do not start a droplet or VM, and do not render on this PC.
