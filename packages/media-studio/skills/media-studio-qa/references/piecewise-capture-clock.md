# Piecewise capture picture clock

`build-cue-sheet.mjs` accepts a compose group's retained
`actualCaptureWindow.piecewise_time_map` for receipt-to-picture timing. Each
anchor has a strictly increasing integer `output_frame` and source-clock
`source_seconds`. Frames are shot-relative; the first anchor need not be zero.
The complete window must span `output_frames`, match the declared source
bounds, and agree with the group's start and duration through
`output_frames / output_seconds`. Source file bytes and capture receipt SHA-256
must both equal `source_sha256`; the clip identifiers must match.

The builder interpolates only between adjacent real anchors. Events outside
the captured window remain unmappable. Malformed or unbound maps fail the
builder, even when a legacy linear `edit` is present. Exact anchors remain in
the cue sheet's `picture_clock` and EDL; `action_time_natural` is null because
an alternate linear clock would misrepresent the edit.

This is a declared renderer picture transform, not proof the candidate
actually renders it, and not a new speech alignment. Source speech precision,
encoded correspondence, action/result timing thresholds, full candidate
audiovisual review and release gates remain unchanged. The capture receipt
must independently establish its source clip clock. Never invent receipt
events or clock offsets to obtain a mapped action.

`validate-pointer-path.mjs` currently refuses these piecewise cue sheets. Its
legacy no-edit heuristic cannot establish retained source events or beat
ownership for a piecewise transform. That refusal is a release blocker until
the pointer gate independently supports and validates the exact mapping.
