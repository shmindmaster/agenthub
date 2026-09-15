"""write-story-review.py — pre-capture story-review gate for one media-studio job.

Applies media-studio's story-review-rubric.md to story/screenplay.json + story/storyboard.json with NO render, capture
or audio required, and writes qa/story-review.json in the story-experience-review schema (status, candidateId, score,
pass, missingEvidence, reason, checks, findings, reviseSceneIds). It is a screenplay lint, not a craft pass. It does not authorize capture, compose, or delivery.
Product-screencast still requires validate-product-picture.mjs (WebM + Recast) and PDS review of the
encoded file. The encoded-file critic (the PDS story-experience-reviewer agent for screencasts,
media-story-experience-reviewer for the rest) still runs on the candidate after the master exists and
supersedes this file with qa/story-experience-review.json.

Usage:
    python write-story-review.py <jobRoot> [--judgments qa/story-judgments.json] [--out qa/story-review.json]
                                 [--min 85] [--print]

Two kinds of check, and the tool never blurs them:

  MECHANICAL (computed from the files, evidence cites scene ids):
    hook               S01 is a `hook`, no greeting/agenda opener, first sentence <= 25 words (~8 s at 150 wpm);
                       26-35 words is a 5-point rhythm miss, beyond 35 (or wrong role / greeting) the hook is missing (-20)
    one-hero           exactly one scene has heroMoment=true, it matches screenplay.heroSceneId and
                       storyboard.protectedHeroBeatId, it is not in the first 3 scenes, holdAfterSeconds >= 1.0
    silence-hero       the hero scene has silenceOnReveal or a silence/sting/duck music cue
    before-state       a `before`/`problem` scene precedes the hero
    trust              passes mechanically when a `trust`/`proof` scene sits within 3 scenes after the hero; otherwise
                       it becomes a judgment (the labels cannot prove where the control or limit sits)
    archetype-diversity consecutive scenes with the same visualArchetype AND the same visual kind (same archetype with
                       a different picture is a build, not a repeat); a run of `screen-in-context` (one continuous
                       procedure on real screens) is allowed; any other repeat needs a judgments.deliberateRepeats entry
    designed-frames    first scene is a card (or an explicit `cold-open` screen); last scene is a card held >= 1.0 s
    filler             every sceneRole is in the rubric vocabulary (hook before bridge tension reveal proof trust hero
                       payoff mechanism explain problem close cta)
    narration-vs-type  a card whose sentence rows (>= 4 content words; labels do not count) are read back by the voice
                       (>= 60 % of such rows with >= 70 % of their content words in the narration; needs >= 3 such rows)
    type-density       a card with >= 8 rows or >= 60 words of on-card text (minor miss, -5 each); rows a visual
                       carries over from the previous scene (visual.revealFrom = N, a build) are not new type and
                       are not counted again, so a long table split across two consecutive builds passes
                       code, still, hero, cta, quote and chip visuals are exempt from both (a code reveal is dense by design)
    platform           deliveryProfile declared (job.json or storyboard); frame/mute/vertical checks wait for the encode
    mix / ai-control   n/a before audio; ai-control becomes a judgment when programForm is ai-in-action / ai-trust

  JUDGMENT (a person or the critic records verdict + scene-cited evidence in qa/story-judgments.json):
    audience  outcome  wiifm  progressive  one-idea  one-promise  studio-picture  (ai-control when applicable)
    A judgment check without an entry is MISSING EVIDENCE: the review is written with status MALFORMED_INPUT,
    no score and pass=false. The tool never turns an unassessed criterion into a pass.

qa/story-judgments.json shape:
    {"schema": "media-studio/story-judgments/1", "reviewer": "<who judged>",
     "judgments": {"audience": {"verdict": "pass|fail", "evidence": "S01 ... S46 ..."}, ...},
     "deliberateRepeats": ["S09-S10"],
     "findings": [{"id": "J-1", "severity": "minor|major|block", "location": "S25", "evidence": "...",
                   "fix": "...", "owner": "media-storyboard", "points": 5}]}

Scoring follows the rubric, in the open: start 100; -20 missing hook / missing hero / greeting or feature-tour opening;
-15 no before-state; -10 per filler beat or accidental consecutive repeat; -10 once when narration reads on-screen
type; -5 per type-density miss; judgment findings deduct their `points` (default minor 5, major 15; block forces
fail). A failed check the rubric gives no arithmetic for (trust, designed-frames, platform, or a failed judgment)
costs 15, the rubric's "structural miss" class; that rule is this tool's and is named in `reason`.

Provenance (method, thresholds, input hashes, rubric hash) goes to qa/story-review.provenance.json so the review
itself stays schema-clean.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

TOOL_VERSION = "2026-09-15.2"
ROLE_VOCAB = {"hook", "before", "bridge", "tension", "reveal", "proof", "trust", "hero", "payoff", "mechanism",
              "explain", "problem", "close", "cta"}
GREETING_RE = re.compile(r"\b(welcome|hello|hi there|hey everyone|my name is|in this (video|episode|film)|"
                         r"today (we|i)('ll| will| am|'re)|agenda|let'?s (get started|begin|dive in))\b", re.I)
HOOK_MAX_WORDS = 25
HOOK_LONG_WORDS = 35   # beyond this the hook is judged missing, not merely long
HERO_MIN_HOLD = 1.0
LAST_MIN_HOLD = 1.0
DENSE_ROWS = 8
DENSE_WORDS = 60
READ_ROW_SHARE = 0.6
READ_WORD_SHARE = 0.7
READ_MIN_ROWS = 3
READ_MIN_ROW_WORDS = 4
NON_ROW_KINDS = {"code", "still", "hero", "cta", "quote", "chip"}
JUDGMENT_CHECKS = ["audience", "outcome", "wiifm", "progressive", "one-idea", "one-promise", "studio-picture"]
STRUCTURAL_MISS = 15
NON_TEXT_KEYS = {"kind", "src", "accent", "mark", "at", "color", "id", "align"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def words(text: str) -> list[str]:
    return re.findall(r"[A-Za-z0-9][A-Za-z0-9'\-]*", text or "")


def content_words(text: str) -> set[str]:
    return {w.lower().strip("'-") for w in words(text) if len(w) >= 4}


def first_sentence(text: str) -> str:
    return re.split(r"(?<=[.!?])[\"'”’)\]]*\s+", (text or "").strip(), maxsplit=1)[0]


def visual_text(visual) -> tuple[list[str], int]:
    """(row texts, on-card word count) for any visual shape: rows = the elements of the largest list of strings/dicts,
    each row's text = its string leaves; word count = every string leaf outside NON_TEXT_KEYS."""
    if not isinstance(visual, dict):
        return [], 0

    def leaves(o, key=None):
        if isinstance(o, str):
            return [] if key in NON_TEXT_KEYS else [o]
        if isinstance(o, dict):
            return [s for k, v in o.items() for s in leaves(v, k)]
        if isinstance(o, list):
            return [s for v in o for s in leaves(v, key)]
        return []

    lists: list[list] = []

    def collect(o):
        if isinstance(o, dict):
            for v in o.values():
                collect(v)
        elif isinstance(o, list):
            if o and all(isinstance(x, (str, dict, list)) for x in o):
                lists.append(o)
            for v in o:
                collect(v)

    collect(visual)
    biggest = max(lists, key=len) if lists else []
    rows = [" ".join(leaves(x)) for x in biggest]
    rows = [r for r in rows if r.strip()]
    return rows, len(words(" ".join(leaves(visual))))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("job_root")
    ap.add_argument("--judgments", default=None, help="default qa/story-judgments.json when it exists")
    ap.add_argument("--out", default=None, help="default qa/story-review.json")
    ap.add_argument("--min", type=int, default=None, help="craftScoreMin; default job.json.craftScoreMin or 85")
    ap.add_argument("--print", action="store_true", help="print the full review JSON")
    args = ap.parse_args()

    root = Path(args.job_root).resolve()
    job_p, sp_p, sb_p = root / "job.json", root / "story" / "screenplay.json", root / "story" / "storyboard.json"
    out_p = Path(args.out) if args.out else root / "qa" / "story-review.json"
    if not out_p.is_absolute():
        out_p = root / out_p
    jd_p = Path(args.judgments) if args.judgments else root / "qa" / "story-judgments.json"
    if not jd_p.is_absolute():
        jd_p = root / jd_p

    missing_inputs = [str(p.relative_to(root)) for p in (job_p, sp_p, sb_p) if not p.exists()]
    job = load(job_p) if job_p.exists() else {}
    craft_min = args.min or job.get("craftScoreMin") or 85
    slug = root.name
    if missing_inputs:
        review = {"status": "MALFORMED_INPUT", "candidateId": f"{slug}@pre-capture", "pass": False,
                  "missingEvidence": missing_inputs,
                  "reason": "Required inputs are missing; a criterion without evidence is never a pass."}
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(review, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({"status": review["status"], "missingEvidence": missing_inputs}))
        return 1

    sp, sb = load(sp_p), load(sb_p)
    scenes = sp.get("scenes") or []
    ids = [s["id"] for s in scenes]
    judgments = load(jd_p) if jd_p.exists() else {}
    jmap = judgments.get("judgments") or {}
    deliberate = set(judgments.get("deliberateRepeats") or [])
    program_form = sp.get("programForm") or job.get("programForm") or ""
    judgment_checks = JUDGMENT_CHECKS + (["ai-control"] if program_form in ("ai-in-action", "ai-trust") else [])

    checks: dict[str, str] = {}
    findings: list[dict] = []
    evidence: dict[str, str] = {}
    deductions: list[tuple[str, int]] = []
    revise: list[str] = []
    fid = [0]

    def finding(sev, loc, ev, fix, owner, points):
        fid[0] += 1
        findings.append({"id": f"SR-{fid[0]}", "severity": sev, "location": loc, "evidence": ev, "fix": fix, "owner": owner})
        if points:
            deductions.append((f"SR-{fid[0]}", points))

    # ---- hook --------------------------------------------------------------------------------------------------
    s1 = scenes[0] if scenes else {}
    fs = first_sentence(s1.get("narration", ""))
    n_hook = len(words(fs))
    greeting = bool(GREETING_RE.search(s1.get("narration", "")))
    hook_missing = s1.get("sceneRole") != "hook" or greeting or n_hook > HOOK_LONG_WORDS
    hook_long = not hook_missing and n_hook > HOOK_MAX_WORDS
    checks["hook"] = "fail" if hook_missing else "pass"
    evidence["hook"] = (f"{s1.get('id')} role={s1.get('sceneRole')} first sentence {n_hook} words: \"{fs[:120]}\""
                        + (" (greeting/agenda opener)" if greeting else "") + (f" (over {HOOK_MAX_WORDS}: rhythm miss)" if hook_long else ""))
    if hook_missing:
        finding("major", s1.get("id", "S01"), evidence["hook"],
                "Open on the payoff or the pain in one sentence of <= 25 words; no greeting, logo or agenda.", "media-writer", 20)
        revise.append(s1.get("id", "S01"))
    elif hook_long:
        finding("minor", s1.get("id", "S01"), evidence["hook"], f"Trim the opening sentence to <= {HOOK_MAX_WORDS} words (~8 s).", "media-writer", 5)

    # ---- hero -----------------------------------------------------------------------------------------------------
    heroes = [s for s in scenes if s.get("heroMoment")]
    hero = heroes[0] if len(heroes) == 1 else None
    declared = sp.get("heroSceneId"), sb.get("protectedHeroBeatId")
    hero_idx = ids.index(hero["id"]) if hero else -1
    hero_problems = []
    if len(heroes) != 1:
        hero_problems.append(f"{len(heroes)} scenes carry heroMoment ({[h['id'] for h in heroes]})")
    else:
        for label, d in zip(("screenplay.heroSceneId", "storyboard.protectedHeroBeatId"), declared):
            if d and d != hero["id"]:
                hero_problems.append(f"{label}={d} but heroMoment is on {hero['id']}")
        if hero_idx < 3:
            hero_problems.append(f"hero {hero['id']} is scene {hero_idx + 1}; no room for anticipation")
    checks["one-hero"] = "pass" if not hero_problems else "fail"
    evidence["one-hero"] = (f"hero {hero['id']} at scene {hero_idx + 1}/{len(scenes)}, hold {hero.get('holdAfterSeconds')} s"
                            if hero and not hero_problems else "; ".join(hero_problems))
    if hero_problems:
        finding("major", hero["id"] if hero else "screenplay", "; ".join(hero_problems),
                "Exactly one protected hero moment, declared identically in screenplay and storyboard, placed after the setup.",
                "media-storyboard", 20)
    elif float(hero.get("holdAfterSeconds") or 0) < HERO_MIN_HOLD:
        finding("minor", hero["id"], f"hero hold {hero.get('holdAfterSeconds')} s < {HERO_MIN_HOLD} s",
                "Hold the payoff frame for at least a second before the next cut.", "media-director", 5)

    # ---- silence on the hero --------------------------------------------------------------------------------------
    if hero:
        quiet = bool(hero.get("silenceOnReveal")) or str(hero.get("musicCue", "")).lower() in ("silence", "sting", "duck", "ducked")
        checks["silence-hero"] = "pass" if quiet else "fail"
        evidence["silence-hero"] = f"{hero['id']} silenceOnReveal={hero.get('silenceOnReveal')} musicCue={hero.get('musicCue')}"
        if not quiet:
            finding("minor", hero["id"], evidence["silence-hero"], "Cut the bed or use a sting on the hero reveal.", "media-director", 5)
    else:
        checks["silence-hero"] = "fail"
        evidence["silence-hero"] = "no single hero to judge"

    # ---- before-state ---------------------------------------------------------------------------------------------
    before = [s["id"] for i, s in enumerate(scenes) if s.get("sceneRole") in ("before", "problem") and (hero_idx < 0 or i < hero_idx)]
    checks["before-state"] = "pass" if before else "fail"
    evidence["before-state"] = f"before/problem scenes ahead of the hero: {before}" if before else "no before/problem scene precedes the hero"
    if not before:
        finding("major", "screenplay", evidence["before-state"], "Give the viewer the current cost before the solution.", "media-writer", 15)

    # ---- trust ----------------------------------------------------------------------------------------------------
    trust_ids = [s["id"] for s in scenes if s.get("sceneRole") == "trust"]
    near = [s["id"] for s in scenes[hero_idx + 1: hero_idx + 4] if s.get("sceneRole") in ("trust", "proof")] if hero_idx >= 0 else []
    trust_ok = bool(trust_ids) and (bool(near) or hero_idx < 0)
    if trust_ok:
        checks["trust"] = "pass"
        evidence["trust"] = f"trust scenes {trust_ids}; trust/proof within 3 scenes after the hero: {near}"
    else:
        # the role labels do not prove adjacency; a person must say where the control/limit sits (or that it is absent)
        judgment_checks.append("trust")
        evidence["trust"] = f"role labels inconclusive (trust scenes {trust_ids}; trust/proof within 3 scenes after the hero: {near}); judged"

    # ---- archetype diversity --------------------------------------------------------------------------------------
    repeats, accidental = [], []
    def kind(s):
        return ((s.get("production") or {}).get("visual") or {}).get("kind") if s.get("visualMode") != "screen" else "screen"
    for a, b in zip(scenes, scenes[1:]):
        if a.get("visualArchetype") == b.get("visualArchetype") and kind(a) == kind(b):
            pair = f"{a['id']}-{b['id']}"
            repeats.append(pair)
            if a.get("visualArchetype") != "screen-in-context" and pair not in deliberate:
                accidental.append(pair)
    checks["archetype-diversity"] = "pass" if not accidental else "fail"
    evidence["archetype-diversity"] = (f"consecutive same-archetype+same-kind repeats {repeats or 'none'}; screen-in-context runs allowed; "
                                       f"declared deliberate {sorted(deliberate) or 'none'}; accidental {accidental or 'none'}")
    for pair in accidental:
        finding("major", pair, f"consecutive {scenes[ids.index(pair.split('-')[0])].get('visualArchetype')} with no deliberateRepeats entry",
                "Change the archetype of one of the two scenes, or declare the repeat deliberate with its reason.", "media-storyboard", 10)
        revise.append(pair.split("-")[1])

    # ---- designed frames ------------------------------------------------------------------------------------------
    last = scenes[-1] if scenes else {}
    first_card = s1.get("visualMode") == "card" or s1.get("visualArchetype") == "cold-open"
    last_ok = last.get("visualMode") == "card" and float(last.get("holdAfterSeconds") or 0) >= LAST_MIN_HOLD
    checks["designed-frames"] = "pass" if first_card and last_ok else "fail"
    evidence["designed-frames"] = (f"first {s1.get('id')} {s1.get('visualMode')}/{s1.get('visualArchetype')}; "
                                   f"last {last.get('id')} {last.get('visualMode')}/{last.get('visualArchetype')} hold {last.get('holdAfterSeconds')} s")
    if not (first_card and last_ok):
        finding("major", f"{s1.get('id')}, {last.get('id')}", evidence["designed-frames"],
                "Open and close on a stable designed card; hold the last frame >= 1 s.", "media-storyboard", STRUCTURAL_MISS)

    # ---- filler (vocabulary) --------------------------------------------------------------------------------------
    odd = [(s["id"], s.get("sceneRole")) for s in scenes if s.get("sceneRole") not in ROLE_VOCAB]
    checks["filler"] = "pass" if not odd else "fail"
    evidence["filler"] = f"roles outside the vocabulary: {odd}" if odd else f"all {len(scenes)} scene roles are in the rubric vocabulary"
    for sid, role in odd:
        finding("major", sid, f"sceneRole {role!r} is not a rubric beat", "Name the beat (hook/before/tension/reveal/proof/trust/hero/bridge/cta) or cut it.", "media-writer", 10)
        revise.append(sid)

    # ---- narration reads the slide; type density -------------------------------------------------------------------
    reads, dense = [], []
    for s in scenes:
        if s.get("visualMode") != "card":
            continue
        p = s.get("production") or {}
        if (p.get("visual") or {}).get("kind") in NON_ROW_KINDS:
            continue
        rows, vwords = visual_text(p.get("visual"))
        # A visual that continues the previous scene's card (visual.revealFrom = N) carries its first N rows over;
        # only the rows this scene reveals are new type for the viewer, so density counts those (a build).
        # Read-back still looks at every visible row: the voice can read a carried row as easily as a new one.
        carried = int((p.get("visual") or {}).get("revealFrom") or 0)
        new_rows = rows[carried:] if carried else rows
        vwords_new = len(words(" ".join(new_rows))) if carried else vwords
        card_words = vwords_new + len(words(p.get("title", ""))) + len(words(p.get("subtitle", "")))
        if len(new_rows) >= DENSE_ROWS or card_words >= DENSE_WORDS:
            dense.append((s["id"], len(new_rows), card_words))
        sentence_rows = [r for r in rows if len(content_words(r)) >= READ_MIN_ROW_WORDS]  # labels cannot be "read"
        if len(sentence_rows) >= READ_MIN_ROWS:
            nw = content_words(s.get("narration", ""))
            read_rows = sum(1 for r in sentence_rows if len(content_words(r) & nw) / len(content_words(r)) >= READ_WORD_SHARE)
            if read_rows / len(sentence_rows) >= READ_ROW_SHARE:
                reads.append((s["id"], read_rows, len(sentence_rows)))
    checks["narration-vs-type"] = "pass" if not reads else "fail"
    evidence["narration-vs-type"] = ("no card is read back by the voice" if not reads else
                                     "voice reads the card rows: " + ", ".join(f"{i} ({r}/{n} rows)" for i, r, n in reads))
    if reads:
        finding("minor", ", ".join(i for i, _, _ in reads), evidence["narration-vs-type"],
                "Cut each row to an owner + noun and let the voice carry the qualifier, or voice only the rows that change the decision.",
                "media-storyboard", 10)
    checks["type-density"] = "pass" if not dense else "fail"
    evidence["type-density"] = ("no card at or above the density thresholds" if not dense else
                                "dense cards: " + ", ".join(f"{i} ({r} rows, {w} words)" for i, r, w in dense))
    for i, r, w in dense:
        finding("minor", i, f"{r} rows, {w} on-card words (thresholds {DENSE_ROWS} rows / {DENSE_WORDS} words)",
                "Split the card into two builds or drop the qualifiers.", "media-storyboard", 5)

    # ---- platform / mix / ai-control --------------------------------------------------------------------------------
    profile = job.get("deliveryProfile") or sb.get("deliveryProfile")
    checks["platform"] = "pass" if profile else "fail"
    evidence["platform"] = f"deliveryProfile={profile}; frame/mute-safe/vertical checks wait for the encoded file"
    if not profile:
        finding("major", "job.json", "no deliveryProfile declared", "Set deliveryProfile (briefing-board by default).", "media-director", STRUCTURAL_MISS)
    checks["mix"] = "n/a"
    evidence["mix"] = "no audio before TTS; judged by the encoded critic"
    if "ai-control" not in judgment_checks:
        checks["ai-control"] = "n/a"
        evidence["ai-control"] = f"programForm={program_form!r} is not ai-in-action/ai-trust"

    # ---- judgment checks ---------------------------------------------------------------------------------------------
    missing_evidence = []
    for name in judgment_checks:
        j = jmap.get(name) or {}
        verdict, ev = j.get("verdict"), (j.get("evidence") or "").strip()
        if verdict not in ("pass", "fail", "n/a") or (verdict != "n/a" and not ev):
            missing_evidence.append(f"judgment '{name}' (verdict + scene-cited evidence) in {jd_p.name}")
            continue
        checks[name] = verdict
        evidence[name] = f"[{judgments.get('reviewer', 'judgment')}] {ev}"
        if verdict == "fail":
            finding("major", j.get("location", "screenplay"), ev, j.get("fix", "Revise the scenes named in the evidence."),
                    j.get("owner", "media-writer"), int(j.get("points", STRUCTURAL_MISS)))
            revise += j.get("reviseSceneIds") or []
    for jf in judgments.get("findings") or []:
        pts = int(jf.get("points", {"minor": 5, "major": 15, "block": 0}.get(jf.get("severity"), 5)))
        finding(jf.get("severity", "minor"), jf.get("location", "screenplay"), jf.get("evidence", ""), jf.get("fix", ""),
                jf.get("owner", "media-storyboard"), pts)

    # ---- assemble ----------------------------------------------------------------------------------------------------
    total_words = sum(len(words(s.get("narration", ""))) for s in scenes)
    est = round(total_words / 150 * 60 + sum(float(s.get("pauseBeforeSeconds") or 0) + float(s.get("holdAfterSeconds") or 0) for s in scenes))
    target = job.get("durationTargetSeconds")
    duration_note = (f"estimated {est} s from {total_words} words at 150 wpm plus pauses; target {target} s"
                     + (f" ({'within' if target and abs(est - target) <= 0.1 * target else 'outside'} +/-10 %)" if target else ""))
    candidate = f"{slug}@screenplay+storyboard:sha256:{hashlib.sha256((sha(sp_p) + sha(sb_p)).encode()).hexdigest()[:16]}"
    blocks = [f for f in findings if f["severity"] == "block"]
    score = max(0, 100 - sum(p for _, p in deductions))
    revise = sorted(set(revise), key=lambda x: ids.index(x) if x in ids else 999)
    out_p.parent.mkdir(parents=True, exist_ok=True)

    if missing_evidence:
        review = {"status": "MALFORMED_INPUT", "candidateId": candidate, "pass": False, "missingEvidence": missing_evidence,
                  "reason": ("Mechanical checks ran (" + "; ".join(f"{k}={v}" for k, v in checks.items()) +
                             ") but the judgment checks have no recorded verdict/evidence, so no score is issued. "
                             "Record them in qa/story-judgments.json and rerun. " + duration_note),
                  "checks": checks, "findings": findings, "reviseSceneIds": revise}
    else:
        passed = not blocks and score >= craft_min
        reason = (f"Pre-capture structural lint ({TOOL_VERSION}) on screenplay + storyboard; does not authorize compose or delivery; encoded-file critic pending. "
                  f"Score {score} = 100 - {sum(p for _, p in deductions)} ({', '.join(f'{i} -{p}' for i, p in deductions) or 'no deductions'}); "
                  f"craftScoreMin {craft_min}. Checks without rubric arithmetic (trust, designed-frames, platform, failed judgments) cost {STRUCTURAL_MISS}. "
                  + " | ".join(f"{k}: {evidence.get(k, '')}" for k in checks) + f" | duration: {duration_note}")
        review = {"status": "COMPLETE", "candidateId": candidate, "score": score, "pass": passed, "reason": reason,
                  "checks": checks, "findings": findings, "reviseSceneIds": revise}
    out_p.write_text(json.dumps(review, indent=2, ensure_ascii=False), encoding="utf-8")

    rubric = sorted(Path.home().glob(".claude/plugins/cache/agenthub/media-studio/*/skills/media-studio/references/story-review-rubric.md"))
    prov = {"tool": "write-story-review.py", "toolVersion": TOOL_VERSION, "method": "pre-capture structural gate + recorded judgments",
            "inputs": {"screenplay": sha(sp_p), "storyboard": sha(sb_p), "job": sha(job_p) if job_p.exists() else None,
                       "judgments": sha(jd_p) if jd_p.exists() else None},
            "rubric": {"path": str(rubric[-1]) if rubric else None, "sha256": sha(rubric[-1]) if rubric else None},
            "thresholds": {"hookMaxWords": HOOK_MAX_WORDS, "heroMinHold": HERO_MIN_HOLD, "lastMinHold": LAST_MIN_HOLD, "denseRows": DENSE_ROWS,
                           "denseWords": DENSE_WORDS, "readRowShare": READ_ROW_SHARE, "readWordShare": READ_WORD_SHARE, "readMinRowWords": READ_MIN_ROW_WORDS, "revealFromCarriesRows": True, "nonRowKinds": sorted(NON_ROW_KINDS), "structuralMiss": STRUCTURAL_MISS},
            "judgmentChecks": judgment_checks, "durationEstimate": duration_note, "deductions": deductions, "evidence": evidence,
            "authorizesDelivery": False, "authorizesCompose": False}
    out_p.with_name(out_p.stem + ".provenance.json").write_text(json.dumps(prov, indent=2, ensure_ascii=False), encoding="utf-8")

    summary = {k: review.get(k) for k in ("status", "score", "pass", "reviseSceneIds")}
    summary["findings"] = len(findings)
    if review["status"] == "MALFORMED_INPUT":
        summary["missingEvidence"] = len(missing_evidence)
    print(json.dumps(review if args.print else summary, indent=2 if args.print else None, ensure_ascii=False))
    return 0 if review.get("pass") else 1


if __name__ == "__main__":
    sys.exit(main())
