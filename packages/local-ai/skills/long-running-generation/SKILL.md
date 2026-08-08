---
name: long-running-generation
description: Use when running, monitoring, parallelizing, or resuming a long local generation batch — TTS, image, video, diagram, or embedding jobs that take hours and write expensive artifacts.
---

# Long-running local generation

This skill is about operating a batch that takes hours and produces artifacts
you cannot cheaply reproduce. It is the companion to `local-ai-stack`, which
covers *which* route to use; this one covers *how to run it without losing a
day*.

Read it before starting a job measured in hours, before adding concurrency to
one, and before writing anything that watches one.

## Why this exists

It is written from one measured session against a 753-card corpus on
`D:\ExamPrep`, where the *renders* were reliable and the *instrumentation*
failed four separate times. Every rule below cost something:

| Failure | Cost |
| --- | --- |
| Resident worker pool deadlocked on an undrained pipe | ~3.7 hours of dead GPU |
| A completion waiter that could not detect a hang | the same 3.7 hours went unnoticed |
| A stall detector counting files during an in-place overwrite stage | false alarm; nearly killed a healthy run |
| A `pgrep` guard on a host with no `pgrep` | serialization guard silently absent |
| An anomaly gate with no minimum-input floor | would have destroyed 12 correct clips |
| A 4.7x speedup shipped without an output gate | 5 defective clips in 592, undetected |

The pattern: **the generation was fine; the things watching it were wrong.**
Assume your monitoring is the weakest component, because historically it is.

## Start serial, resumable, and idempotent

The default shape for a long batch:

- **One process per work item.** A fresh process per item throws away whatever
  state accumulates in a resident model. Measured on identical text and voice:
  process-per-item produced 0 anomalies in 399 items; a 3-worker resident pool
  produced 5 in 592.
- **The output file is the completion record.** Before generating item *N*,
  check whether its output already exists and skip it. Do not maintain a
  separate progress ledger as the source of truth — a ledger can disagree with
  the disk, the disk cannot disagree with itself. A job built this way is
  resumable by construction: kill it, restart it, it continues.
- **Write to the final path only on success.** A partially written artifact
  that looks complete is worse than a missing one, because the resume check
  above will skip it forever.

Only after this works do you consider making it faster.

## If you build a resident worker, you own the pipes

A resident GPU worker is the correct optimization when model load time
dominates — but it is a subprocess-lifetime problem, not a model problem, and
it is where the hours were lost.

**Every pipe you open, you must drain continuously.** An OS pipe buffer is
about 64 KB. When it fills, the writing process blocks in `write()` forever.
It does not error, exit, or log. A worker that logs to `stderr` while the
parent only reads `stdout` on demand will wedge silently, mid-job, hours in.

```python
# Drain for the life of the process, on its own thread, for EVERY pipe.
self._err = collections.deque(maxlen=40)      # bounded: keep a tail for diagnosis
threading.Thread(target=self._drain, args=(self.proc.stderr, self._err),
                 daemon=True).start()
```

If you drain `stderr` and leave `stdout` read-on-demand, you have fixed one of
two identical bugs and will deadlock again. That is exactly what happened here:
the second hang was the first hang on the other pipe.

Two more rules for the same code:

- **Never treat the first line of output as a protocol message.** A ready
  handshake that reads one line will consume a stray blank line or a library
  banner and then wait forever for a reply that already arrived. Loop until a
  line that actually parses:

  ```python
  while True:
      line = proc.stdout.readline()
      if not line:
          raise SystemExit("worker died during load:\n" + tail_of(stderr))
      if line.lstrip().startswith("{"):
          break
  ```

- **A dead worker must raise, not block.** An empty read means EOF means the
  process is gone. Surface its stderr tail; do not fall through into a wait.

## Watch the signal that actually moves

A completion waiter — `wait()`, `join()`, "sleep until the done line appears" —
is *structurally incapable* of detecting a hang. A hung job produces no error,
no exit code, and no completion line. The waiter's happy path and its worst
failure mode are byte-identical.

Every long job needs a **stall detector**, separate from its completion path,
that asserts forward progress and alarms on the absence of it.

Choosing the signal is the part that goes wrong. It must be something the
current stage actually changes:

- **Output count is wrong for any stage that overwrites in place.** A repair or
  re-render pass rewrites existing files; the count is flat while the job is
  perfectly healthy. This produced a false alarm that nearly killed a good run.
- **Newest modification time is the general signal.** It moves whether files
  are created or replaced.

```bash
newest=$(find "$OUT" -name '*.mp3' -printf '%T@\n' | sort -rn | head -1 | cut -d. -f1)
age=$(( $(date +%s) - newest ))
[ "$age" -gt 600 ] && echo "STALLED: newest artifact is ${age}s old"
```

Set the threshold from the measured per-item time, not from a guess — if items
take 95s, 600s is a stall; if they take 20 minutes, it is normal.

**Verify the alarm before acting on it.** When a detector fires, confirm
against the underlying evidence before killing anything. A monitor that has
never fired is a monitor that has never been tested.

## Shard by stable hash, never by index

To split work across N processes, partition on a hash of the item's own stable
identity:

```python
def shard_owns(guid, n, k):
    return zlib.crc32(guid.encode()) % k == n
```

Index-based striding (`items[n::k]`) is a correctness bug whenever the item
list is derived from a directory listing that the job itself is changing. As
outputs appear, the "remaining" list shrinks, every index shifts, and two
processes converge on the same output path — both writing one file.

Before launching, prove the partition: for the full item set, assert each id is
owned by exactly one shard, at every K you intend to use.

## Speed without an output gate is not speed

A faster path is only faster if its output is as good. Compare the new path
against the old on **the same corpus and the same inputs**, and measure a
defect rate, not a runtime.

Here, a 4.7x speedup (95s → 20-27s per clip) carried a ~1% defect rate the
serial path did not have. The defects were invisible to every structural
check: the files existed, were non-empty, and were simply wrong.

So a batch needs a **content** gate, not just a presence gate. Pick a cheap
invariant that correlates with correctness — for TTS, characters per second of
audio; for images, resolution and file size; for text, length against input.
Anything far outside the corpus norm is a candidate defect.

**Give every ratio gate a minimum-input floor.** A ratio computed over a tiny
input is noise, not signal. Clips with one-word answers (`"4"`, `"user"`) carry
the same fixed leading silence as long ones and score far below the norm; 12
correct clips were flagged this way. Repairing a correct artifact is worse than
the defect being hunted, because the replacement is drawn from the same
distribution that produced the failures.

```python
MIN_CPS, MAX_CPS = 5.0, 25.0   # measured band from a known-good corpus
MIN_CHARS = 30                 # below this the ratio is not a signal
```

Derive the band from a corpus you have reason to trust, and say in a comment
which one.

## Repair is overwrite, and overwrite needs a backup

Automated repair deletes correct work when the detector is wrong, and the
detector has been wrong. So:

- Copy the existing artifact to a backup directory **before** removing it.
- If the re-render fails or produces nothing, restore the original. A suspect
  artifact beats a missing one.
- Repair on the path with the better measured record, not the faster one.
- Never delete the source corpus or the generated tree to "clean up". The tree
  on this machine represents roughly six GPU-hours; one interrupted job already
  cost 198 clips.

## Windows resource and host facts

- **The binding constraint is usually the commit limit, not VRAM.** Commit
  exhaustion while a model is memory-mapped surfaces as a native
  `ACCESS_VIOLATION 0xC0000005`, which reads like a code bug and is not one.
  Check commit headroom before adding a worker, and do not weaken a job's
  commit guard to make it start.
- **`0xC000026B` / exit `3221226091` is `STATUS_DLL_INIT_FAILED_LOGOFF`** — the
  window station is shutting down. It means the session ended, not that the job
  is broken. Verify the corpus, do not re-render on suspicion.
- **Throughput is real-time factor, not GPU utilization percent.** Batch-1
  autoregressive decode is launch-latency-bound; a low utilization number is
  the expected shape of that workload, not evidence of a misconfiguration.
- **Concurrency caps come from the commit limit, not the core count.** A 16-core
  machine does not get 16 renderers if a TTS job alongside holds ~8.7 GB of
  commit.

Host mechanics that have silently produced wrong answers here:

- **`pgrep` does not exist in Git Bash.** A wait loop guarded by it falls
  through instantly and the serialization it was protecting never happens. Use
  the platform's own process query and check the guard fires at least once.
- **A process query matches its own command line.** `Get-CimInstance Win32_Process`
  filtered on a script name matches the PowerShell process running the filter,
  reporting one phantom survivor forever. Exclude the current PID.
- **Run PowerShell through the PowerShell tool.** Routing it through Bash
  mangles `$variables` before PowerShell ever sees them.

## Reporting a long job honestly

- A file count is not a success count until a content gate has run.
- "Complete" means the gate ran and passed, not that the process exited 0.
- State which stages were verified, which were only observed to finish, and
  what you could not check from this machine.
- Nothing about device or hardware behavior is verifiable from the build host.
  Say so plainly rather than implying a run happened.
