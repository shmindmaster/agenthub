# Render lanes

Pick from measured CPU, free RAM and GPU encoder load. When speed matters and several lanes have room, split the queue. Report lane and cost per job. Local AI is off in every lane; FFmpeg, Remotion and Recast are ordinary tools.

| Lane | Use when | How |
| --- | --- | --- |
| Local RTX 5060 Ti | CPU under 70%, free RAM over 8 GB, at most 2 encodes | `ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i in.mp4 -c:v h264_nvenc -preset p4 -cq 26 out.mp4`. Keep CPU-bound steps off a taxed PC |
| Azure job `caj-media-render` | PC taxed, or parallel work | `kit/cloud/cloud-render.mjs`, about $0.0072 per job-minute at 4 vCPU, 8 GiB; about 1 minute to start |
| Daytona | Fan-out beyond one Azure job, with the orchestrator's OK | Caps $150 a day, $500 total. Label `owner` and `purpose`, TTL 120 min, delete when done, never touch Codex sandboxes |
| DigitalOcean, AWS (`--profile abacare`) | Per the orchestrator's placement rule | Per job, destroyed after |

```powershell
node $cr ffmpeg --name <job> -- <ffmpeg args...> <job>/out.mp4
node $cr remotion --comp Briefing --props <job>/scenes.json --public-dir <job>/public --out <job>/briefing.mp4
node $cr recast --raw <job>/capture/take-01 --out <job>/capture/take-01/recast.webm
```

`$cr` is `<kit>/cloud/cloud-render.mjs`; the last ffmpeg argument is the local output. `kit/cloud/README.md` has path-rewriting limits and fonts.
