# Video library layout and names

The library should read like a catalog: someone browsing `F:/My Drive/Videos` finds a film by who it is for and what it shows, without opening an index.

## Layout

`F:/My Drive/Videos/<Area>/<Customer or company>/<file>`

Two folder levels at most. Take the area from `reviewRoot` in `registry/product-video-delivery.json`, and check what already exists before creating a folder.

| Level | What it names | Examples |
|---|---|---|
| Area | A product, a client, or a purpose | `Revolva`, `Duckie`, `Interview Prep`, `Sarosh - Portfolio` |
| Customer or company | One customer, company, account or engagement inside that area | `ABACare/<Customer>`, `Interview Prep/<Company>` |

- Use the second level when the videos serve one customer or company: prep for a call, demos for a prospect, onboarding for one account.
- A person, a call or a rehearsal goes inside its company folder. Use a person's name as the folder only when there is no company.
- Everything for a whole product or purpose sits directly in the area.
- Stop at two levels. Separate things further with the file name.

Folders never name a file type, a stage or a state: no training, notes, evidence, recordings, version or archive folders. QA evidence and editable project files stay in the job workspace under `D:/Media-Studio`.

## Folder names

- Use the name people say out loud, spelled the way the company spells it.
- Title case with spaces. No dates, versions, status words or underscores.
- Reuse the existing spelling. Never create a near-duplicate of a folder.

## File names

| Case | Pattern | Example |
|---|---|---|
| Series | `NN - Title.mp4` | `03 - Claims Intake Demo.mp4` |
| Two or more series in one folder | `<Series> - NN - Title.mp4` | `First Round - 02 - Mock Interview Rehearsal.mp4` |
| One-off call or meeting | `YYYY-MM-DD - Title.mp4` | `2026-11-04 - Milestone Review Briefing.mp4` |
| Another shape of the same film | `NN - Title - 9x16.mp4` | `03 - Claims Intake Demo - 9x16.mp4` |

- `NN` is two digits and sets the viewing order. A replacement keeps its number.
- The title says what the viewer gets. End it with a kind word from the list below, so the same word finds every film of that kind.
- Leave out the product name, because the folder already says it, and leave out versions, takes, render ids and words like `final`.
- Companion files share the video's name: `.srt` captions and `.md` notes.
- A warning label goes in the name when one applies: `NEEDS EDIT`, `NEEDS REDO`, `HISTORICAL`, `OUTDATED` or `REVIEW NEEDED`.

## Kind words

| Word | Use it for |
|---|---|
| Demo | A product shown working |
| Walkthrough | A guided tour of a screen or process |
| Training | Teaching someone to do a task |
| Explainer | Why something works the way it does |
| Briefing | Prep or a summary for a meeting or decision |
| Rehearsal | Interview or presentation practice |
| Case Study | A result told start to finish |
| Introduction | Who someone is or what a product does |

## Index

Each folder that holds videos has one `README.md`, with one row per video: number, title, kind, audience, length and status. The library's own `README.md` lists the areas.

## Existing folders

The whole library follows this layout since the 2026-11-04 cleanup, and `AGENTS.md` at its root repeats these rules. Change them here first, then there. Move or rename a delivered film only when the owner asks, and update every README and playlist that names it.
