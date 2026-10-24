# Verified edit maps

For deterministic silence cuts and declared mutes of an already aligned film,
the canonical validators can retain the original native clock without claiming
a new forced alignment. This route does not apply to replacement speech,
time stretching, reordered speech, or cuts intersecting aligned words.

Write `plan/edit-map.json` with schema `media-studio/edit-map/1`, immutable
`{path, sha256}` references for `candidate`, `source.candidate`,
`source.alignment`, and `source.script`, ordered `cuts` and `mutes` arrays of
`[startSeconds, endSeconds]`, and `verifyPicture: true` when picture is retained
through the same cuts. The complete graph starts at source time zero and
preserves the source tail. Missing graphs and overlapping/invalid cuts fail.

Run from the owning package's scripts or its deployed kit:

```powershell
node validate-edit-map.mjs <jobRoot> <candidate.mp4> <jobRoot>/plan/edit-map.json
node validate-word-sync.mjs <jobRoot> <candidate.mp4>
node validate-viewer-release.mjs <jobRoot> <candidate.mp4>
```

The first command decodes the complete declared source graph and the candidate
to 16 kHz mono float PCM. Every quarter-second block, including silence and the
tail, must match the canonical correlation and RMS error floors. Sample counts
must agree exactly. These are decoded signal correspondence checks allowing
lossy codec differences; they are not bit-identical source-audio assertions.
Picture verification checks every 2 fps luma sample and the final native frame.
It complements full final-file visual review; it does not replace it.

The proof binds the original candidate, native alignment, locked script, complete
edit graph and exact final candidate. Word-sync records method
`verified-preserved-pcm-edit-map`, no new grid, the original 80 ms uncertainty,
actual median offset, drift and p95 absolute error. Canonical 40 ms median
offset/drift floors remain unchanged. A mute overlapping an uncertain source
word interval is explicitly reported for independent final-file acoustic
review. This proof alone cannot approve pronunciation, content, or clarity.

The viewer validator rechecks immutable inputs, graph mapping, coverage,
thresholds and current cue measurements. Editing any input requires rerunning
the proof. A failed or absent proof never falls back to the old alignment.
