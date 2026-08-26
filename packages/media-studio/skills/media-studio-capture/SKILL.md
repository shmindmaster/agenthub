---
name: media-studio-capture
description: Use when a live product workflow needs deterministic screen capture, walkthrough recording, screenshots, or Recast pointer/click/zoom plates for a media-studio screencast.
---

# Media studio capture

Capture the real product. This is the screencast lane of media-studio (Playwright + Recast). It replaces the retired `product-demo-studio-capture` skill.

```powershell
$Pds = Join-Path ($(if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' })) 'packages\product-demo-studio'
```

Engine procedure: `$Pds\pipeline\product-demo-studio-capture\SKILL.md` and `$Pds\scripts`. Do not copy product UI with diffusion.

1. Verify deployed commit, role, seed/reset, clean browser profile.
2. Playwright CLI or Playwright Test. Preserve trace + high-resolution WebM outside the product repo.
3. Recast (`playwright-recast`) for cursor approach, click ripple, punch-in zoom.
4. One beat per action: start → locator → pointer lead → action → visible result hold.
5. Validate with `$Pds\scripts\validate-storyboard.mjs` and `validate-capture-manifest.mjs`.
