# Browser tools for looking at pages

Read this when you need to look at a web page before scripting a capture, or compare screenshots after a render. Delivered product footage still comes from `skills/capture` (Playwright WebM plus Recast); nothing here replaces it.

## agent-browser (`vercel-labs/agent-browser`, Apache-2.0)

A native CLI that drives its own isolated Chrome one command at a time. Fits the exploratory step and the visual check.

```text
agent-browser --session job1 open <url>
agent-browser --session job1 snapshot -i          # accessibility tree with @e refs
agent-browser --session job1 screenshot job/shot.png
agent-browser --session job1 diff screenshot --baseline job/baseline.png
agent-browser --session job1 record start job/x.webm --cursor --contact-sheet
agent-browser --session job1 close
```

- Use an isolated session. Never pass `--profile` or `--auto-connect`: they copy a signed-in browser profile, and capture uses clean synthetic profiles.
- Add `--allowed-domains` for the page under test.
- Its `record` gives plain WebM or MP4. For delivered footage use capture, so the take is hash-bound and finished by Recast.
- Install: `npm i -g agent-browser && agent-browser install`. Windows: one open issue (2232) reports a failed-logon event per Chrome launch and account lockouts on a local account. Run a single supervised launch on the installed version before relying on it.

## webreel (`vercel-labs/webreel`)

Not used. A Labs experiment (0.1.4) that records scripted JSON demos with a cursor and a key overlay. It overlaps capture without auth, hash binding or animated zoom. Reconsider only for a quick GIF of a public page, after a Windows smoke test.

## Visual explainer

Rules adopted in `visual-bible.md`. Its video renderer (a 1280x720 HTML scene recorded on a virtual clock) is a possible lightweight lane for diagrams as HTML; not wired. If used, vendor the fonts, because its pages call Google Fonts, and pass no `--open` flag in headless runs.
