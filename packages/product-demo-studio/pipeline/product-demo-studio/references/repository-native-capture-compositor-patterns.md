# Repository-native capture and compositor patterns

Use these patterns in the external AgentHub workspace when a product needs scripted Playwright
capture or a compositor adapter. The default capture owner is pinned Microsoft Playwright
CLI/core. `playwright-recast` is the required pointer/click/punch-in finisher on captured
WebM (`media-studio` `product-picture.md`). Long many-click clips can fail Recast's ffmpeg
`autoZoom` on Windows — split the take or render without `autoZoom`. That is not permission
to encode PNG stills or skip the cursor overlay and click ripple. Do not reimplement
mechanics already supplied by the selected finisher. Only stable hooks independently useful
to product tests may live in the product repository, and only with explicit authorization.

## Patterns worth retaining

### One timestamped action log

Let the repository-owned Playwright driver emit one monotonic event log for real product actions,
pointer positions, target rectangles, expected state transitions, caption intervals, and declared
compression regions. Map that log into the normalized storyboard and capture manifest; do not
create a competing release schema.

Every event that can affect the render must identify its beat, action kind, stable selector or
product target, source start/end time, target geometry, real action time, result-visible time, and
the evidence/assertion that proves the state change. The compositor may derive motion only from
these recorded facts. Unlogged edits fail provenance.

### Keep the rendered pointer and real pointer in lockstep

The real Playwright action remains the source of truth. A selected finisher may render its cursor
from trace actions and add a held approach plus click effect, but the rendered layer must not
imply an action absent from product evidence. Add custom DOM pointer code only if Recast cannot
represent a proven interaction and record that exception in provenance.

### Treat CDP screencast frames as variable-rate

Chrome DevTools Protocol screencast frames arrive when pixels change, not at a guaranteed constant
rate. Timestamp each acknowledged source frame against one monotonic clock, preserve frame hashes,
then resample deterministically to the declared delivery frame rate. A held source frame is valid
only for a storyboard-declared static interval; duplicate/frozen-frame preflight still applies.

### Mark bounded waits in the driver

Wrap a real, asserted wait and log its exact source interval. The compositor may cut it or map it to
the storyboard's 4–8× treatment. Do not guess a spinner interval in post, accept an unbounded or
overlapping compression region, or accelerate away missing feedback, a timeout, or a product
defect. Meaningful actions and result holds remain 1×.

### Merge camera anchors, not story beats

Nearby actions whose targets remain inside the current framed region may extend the existing hold
instead of triggering another push. This prevents camera pumping. The storyboard still owns beat
boundaries and permits at most one 300–500ms snap-to-region change per beat; a compositor may not
infer a new zoom merely because a click occurred.

### Provide an offline synthetic smoke test

The plugin's external capture/compositor path should include a complete local fixture
that exercises navigation, eased pointer motion, click feedback, text entry treatment, wait
compression, zoom hold/pullback, captions, fixed-rate delivery, and final decode. The fixture must
need no network or credential, declare expected metadata, and fail unless output plus event log,
checksums, and provenance are present. A test that references a missing fixture is not a smoke test.

### Use one narration-aware output timeline

Generate and automatically validate narration before final capture; measured clip and word durations drive the
shot plan. Do not synthesize inside the recorded browser session or speed-ramp provider latency.
After cuts or acceleration, emit one source-to-output time map and place narration, word-level
captions, actions, camera cues, and evidence boundaries through that same map. Reject overlap,
negative/out-of-order intervals, or a mux that shortens the declared video duration.

Use Product Demo Studio's narration provider owner and content-addressed cache rather than adding
direct provider HTTP clients to every product repository. An offline silence/tone timing proxy may
test the compositor without credentials or quota, but it is smoke evidence only and cannot satisfy
audio, caption, synchronization, or release gates.

## Required safeguards

- Use stable product-owned test hooks rather than style classes where available.
- Pin tool and browser versions in the external workspace; do not mutate the product repository's
  lockfile for video tooling or install browsers globally.
- Use reduced motion, fixed locale/timezone/color profile/fonts, synthetic data, a clean context,
  and repository-native readiness assertions.
- Do not rely on `networkidle` as the only readiness signal; assert the exact product state needed
  by the beat.
- Keep source frames and large generated intermediates in the configured external AgentHub video
  work root. Package only accepted candidates and selected evidence to the mapped OneDrive root.
- Emit separate captions/transcript and audio/evidence artifacts required by Product Demo Studio;
  a burned-in caption or silent MP4 alone is not a releasable candidate.
- Route measurable output through Automated Preflight, all four independent reviewers, the Release
  Arbiter, and the mandatory final independent verifier. A compositor smoke pass is not release.

## Rejected shortcuts

Do not vendor a generic `demokit`, auto-zoom every click, bake untracked DOM annotations into the
only source capture, allow 300–900ms cursor timing or a pulse longer than 400ms, disable reduced
motion, synthesize narration during capture, compress provider latency, use a shortest-stream mux
that can truncate the final hold, use manually trimmed waits, or omit browser/console/network,
word-timing, audio, claim, checksum, and render provenance evidence.
