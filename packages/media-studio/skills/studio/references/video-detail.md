# Workflow detail


## Pipeline

Copy into job notes; pass each gate before the next. A finished render proves nothing.

```text
1. Brief: `brief` skill, approved brief.md; then job.json, thesis, one promise (story.md)
2. Script: locked facts; validate-narration.mjs passes (story.md)
3. Beat sheet, then storyboard with a picture per line (`plan`, `visuals`), visual bible, direction (scenes.md); gates: check_picture_relevance and check_visual_variety pass
4. Voice lock: ASR round trip passes (generate)
5. Word clock (review)
6. Capture or plates (capture, generate)
7. Cue sheet from the word clock (compose)
8. Compose the candidate (compose)
9. Two-pass loudness master, ducked from stems (compose)
10. Review the encoded file (review); loop on failures
11. Deliver (compose)
```
