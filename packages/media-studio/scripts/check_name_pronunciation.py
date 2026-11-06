#!/usr/bin/env python3
"""Automated check that a TTS take says named entities correctly. No human listen needed to find a defect.

    check_name_pronunciation.py <jobRoot> --names Sarosh,Penske,Forman [--anchors DIR] [--negative-control]

It reads <jobRoot>/takes/<id>.wav with <id>.receipt.json (Azure word boundaries) and the line each take speaks
(<jobRoot>/qa/lines/<id>.txt, else story/screenplay.json), and runs:

  A  Azure Pronunciation Assessment at phoneme level (IPA) on the WHOLE line against its full text, then reads the
     name's own word result in context. Fails on a miscue, a low word or phoneme score, or when the sound most often
     wrong (lexicon finalPhone) is not the best match for the audio. Whole-line scoring is deliberate: one-word clips
     cut out of a sentence lose their edges and gave false failures (Forman, Penske, 2026-11-06).
  C  Same-recognizer comparison against an anchor clip of the name said correctly (--anchors DIR/<Name>.wav). The
     recognizer's own bias cancels out; skipped, never passed, when no anchor exists.
  N  Negative control (--negative-control): each line is re-scored with the name swapped for another lexicon name and
     the swapped word must fail. This proves check A can fail at all.

Check B (a phone recognizer that is not told the answer) is not implemented: it needs a model, and local AI is off on
this PC, so it would have to run on remote compute. It is listed under notRun in the report.

Verdicts per name: FAIL, CHECK_NOT_DISCRIMINATING, AUTOMATED_PASS_UNCONFIRMED, CONFIRMED. CONFIRMED needs checks A and
C and N to pass AND the lexicon entry to be marked confirmed: automation cannot know what a person's name should sound
like. Credentials come from AZURE_SPEECH_KEY and AZURE_SPEECH_REGION (names only are ever printed). Default is the
Speech free tier used by cloud-ai.mjs align; assessment is billed like speech-to-text, so audio seconds are reported.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading

SCHEMA = "media-studio/name-pronunciation/2"
DEFAULTS = {"word_accuracy_min": 70.0, "phoneme_accuracy_min": 50.0, "pad_seconds": 0.35, "min_clip_seconds": 0.6}
_STRIP = str.maketrans({"ˈ": "", "ˌ": "", "ː": "", "ˑ": "", ".": "", " ": ""})
_PHONE_MAP = {"ɹ": "r", "ʧ": "tʃ", "ʤ": "dʒ", "ɡ": "g"}


def norm_phone(p):
    """Compare phones without stress, length marks or common IPA spelling variants."""
    p = (p or "").translate(_STRIP)
    for a, b in _PHONE_MAP.items():
        p = p.replace(a, b)
    return p


def norm_word(w):
    return re.sub(r"[^a-z0-9']", "", (w or "").casefold())


def find_occurrences(receipts, names):
    """receipts: {take_id: receipt}. Return one dict per spoken occurrence of a name, from the synthesizer's own clock."""
    wanted = {norm_word(n): n for n in names}
    out = []
    for take_id in sorted(receipts):
        for ev in receipts[take_id].get("word_boundaries") or []:
            if "Word" not in str(ev.get("boundary_type", "")):
                continue
            hit = wanted.get(norm_word(ev.get("text")))
            if hit:
                out.append({"take": take_id, "name": hit, "start": float(ev["start_seconds"]),
                            "end": float(ev["start_seconds"]) + float(ev["duration_seconds"]),
                            "takeSeconds": float(receipts[take_id].get("duration_seconds") or 0) or None})
    return out


def clip_window(start, end, take_seconds, pad=DEFAULTS["pad_seconds"], min_len=DEFAULTS["min_clip_seconds"]):
    a = max(0.0, start - pad)
    b = end + pad
    if take_seconds:
        b = min(b, take_seconds)
    if b - a < min_len:
        b = a + min_len if not take_seconds else min(a + min_len, take_seconds)
    return round(a, 3), round(b, 3)


def parse_assessment(result):
    """Reduce Azure's JSON result to the first recognized word and its phonemes. None when nothing was recognized."""
    try:
        best = result["NBest"][0]
        word = best["Words"][0]
    except (KeyError, IndexError, TypeError):
        return None
    pa = word.get("PronunciationAssessment") or {}
    phones = []
    for ph in word.get("Phonemes") or []:
        info = ph.get("PronunciationAssessment") or {}
        nbest = [(n.get("Phoneme"), float(n.get("Score", 0))) for n in info.get("NBestPhonemes") or []]
        phones.append({"expected": ph.get("Phoneme"), "score": float(info.get("AccuracyScore", 0)), "nbest": nbest})
    return {"heard": best.get("Lexical") or best.get("Display"), "word": word.get("Word"),
            "accuracy": float(pa.get("AccuracyScore", 0)), "errorType": pa.get("ErrorType", "None"), "phonemes": phones}


def judge_clip(parsed, final_phone=None, thresholds=None):
    """Check A for one occurrence. Returns {ok, reasons[], ...}. Unrecognized speech fails."""
    t = {**DEFAULTS, **(thresholds or {})}
    if not parsed:
        return {"ok": False, "reasons": ["nothing recognized"]}
    reasons = []
    if parsed["errorType"] not in (None, "None"):
        reasons.append(f"miscue: {parsed['errorType']}")
    if parsed["accuracy"] < t["word_accuracy_min"]:
        reasons.append(f"word accuracy {parsed['accuracy']:.0f} below {t['word_accuracy_min']:.0f}")
    low = [p for p in parsed["phonemes"] if p["score"] < t["phoneme_accuracy_min"]]
    if low:
        reasons.append("low phonemes: " + ", ".join(f"{p['expected']}={p['score']:.0f}" for p in low))
    discriminator = None
    if final_phone and parsed["phonemes"]:
        last = parsed["phonemes"][-1]
        top = norm_phone(last["nbest"][0][0]) if last["nbest"] else None
        want = norm_phone(final_phone)
        discriminator = {"want": final_phone, "expectedByAzure": last["expected"], "bestMatchForAudio": last["nbest"][0][0] if last["nbest"] else None}
        ok = (top == want) or (norm_phone(last["expected"]) == want and last["score"] >= t["phoneme_accuracy_min"] and top in (None, want))
        if not ok:
            reasons.append(f"final sound is not {final_phone}: audio best matches {discriminator['bestMatchForAudio']}")
    return {"ok": not reasons, "reasons": reasons, "accuracy": parsed["accuracy"], "heard": parsed["heard"],
            "discriminator": discriminator, "phonemes": [(p["expected"], p["score"]) for p in parsed["phonemes"]]}


def verdict_for_name(clip_results, entry, anchor_results, negative):
    """clip_results: list of judge_clip dicts. anchor_results: list of bools or None when no anchor. negative: dict|None."""
    a_ok = bool(clip_results) and all(c["ok"] for c in clip_results)
    c_state = "skipped" if anchor_results is None else ("pass" if anchor_results and all(anchor_results) else "fail")
    n_state = "not run" if negative is None else ("pass" if negative["attempts"] and negative["correctlyFailed"] == negative["attempts"] else "fail")
    if not clip_results:
        verdict = "FAIL"
    elif not a_ok or c_state == "fail":
        verdict = "FAIL"
    elif n_state == "fail":
        verdict = "CHECK_NOT_DISCRIMINATING"
    elif c_state == "pass" and n_state == "pass" and (entry or {}).get("status") == "confirmed":
        verdict = "CONFIRMED"
    else:
        verdict = "AUTOMATED_PASS_UNCONFIRMED"
    return {"verdict": verdict, "checkA": "pass" if a_ok else "fail", "checkC": c_state, "negativeControl": n_state,
            "lexiconStatus": (entry or {}).get("status", "no entry")}


def name_word(words, name, nth=0):
    """The nth (0-based) result word whose text is `name`, or None."""
    hits = [w for w in words if norm_word(w.get("Word")) == norm_word(name)]
    return hits[nth] if nth < len(hits) else None


def parse_word(word):
    """Reduce one Azure word result to the shape judge_clip reads. None when the word is missing."""
    if not word:
        return None
    return parse_assessment({"NBest": [{"Lexical": word.get("Word"), "Words": [word]}]})


def swap_nth(text, name, other, nth):
    """Replace the nth whole-word occurrence of `name` in `text` with `other`."""
    count = [-1]

    def sub(m):
        count[0] += 1
        return other if count[0] == nth else m.group(0)

    return re.sub(r"(?<![A-Za-z0-9'-])" + re.escape(name) + r"(?![A-Za-z0-9'-])", sub, text)


# ---- runtime (network and ffmpeg) -------------------------------------------------------------------------------

def _run(cmd):
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return subprocess.run(cmd, capture_output=True, text=True, creationflags=flags)


def cut_clip(src, dst, a, b):
    r = _run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-ss", f"{a:.3f}", "-to", f"{b:.3f}",
              "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(dst)])
    if r.returncode:
        raise RuntimeError("ffmpeg could not cut the clip")


def _speech(sdk):
    key, region = os.environ.get("AZURE_SPEECH_KEY"), os.environ.get("AZURE_SPEECH_REGION")
    if not key or not region:
        raise RuntimeError("AZURE_SPEECH_KEY and AZURE_SPEECH_REGION must be set")
    cfg = sdk.SpeechConfig(subscription=key, region=region)
    cfg.speech_recognition_language = "en-US"
    return cfg


def assess_line(sdk, wav, reference, timeout=90):
    """Phoneme-level assessment of a whole line; returns Azure's word results in order (miscues included)."""
    pa = sdk.PronunciationAssessmentConfig(
        reference_text=reference, grading_system=sdk.PronunciationAssessmentGradingSystem.HundredMark,
        granularity=sdk.PronunciationAssessmentGranularity.Phoneme, enable_miscue=True)
    pa.phoneme_alphabet = "IPA"
    pa.nbest_phoneme_count = 5
    rec = sdk.SpeechRecognizer(speech_config=_speech(sdk), audio_config=sdk.audio.AudioConfig(filename=str(wav)))
    pa.apply_to(rec)
    words, done = [], threading.Event()

    def got(evt):
        raw = evt.result.properties.get(sdk.PropertyId.SpeechServiceResponse_JsonResult)
        if raw:
            words.extend((json.loads(raw).get("NBest") or [{}])[0].get("Words") or [])

    rec.recognized.connect(got)
    rec.session_stopped.connect(lambda _e: done.set())
    rec.canceled.connect(lambda _e: done.set())
    rec.start_continuous_recognition()
    finished = done.wait(timeout)
    rec.stop_continuous_recognition()
    if not finished:
        raise RuntimeError("Pronunciation assessment timed out")
    return words


def transcribe(sdk, wav):
    rec = sdk.SpeechRecognizer(speech_config=_speech(sdk), audio_config=sdk.audio.AudioConfig(filename=str(wav)))
    res = rec.recognize_once()
    return norm_word(res.text) if res.reason == sdk.ResultReason.RecognizedSpeech else ""


def line_text(job, take):
    p = job / "qa" / "lines" / f"{take}.txt"
    if p.is_file():
        return " ".join(p.read_text(encoding="utf-8").split())
    sp = job / "story" / "screenplay.json"
    if sp.is_file():
        for sc in json.loads(sp.read_text(encoding="utf-8")).get("scenes", []):
            if sc.get("id") == take:
                return " ".join(str(sc.get("narration", "")).split())
    raise RuntimeError(f"No line text for take {take}")


def _sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("job")
    ap.add_argument("--names", required=True, help="comma-separated lexicon names to check")
    ap.add_argument("--anchors", help="folder holding <Name>.wav, a clip of the name said correctly")
    ap.add_argument("--negative-control", action="store_true")
    ap.add_argument("--out", default="qa/name-pronunciation.json")
    ap.add_argument("--word-min", type=float, default=DEFAULTS["word_accuracy_min"])
    ap.add_argument("--phoneme-min", type=float, default=DEFAULTS["phoneme_accuracy_min"])
    args = ap.parse_args(argv)
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here))
    import governed_azure_speech as speech
    import azure.cognitiveservices.speech as sdk

    job = Path(args.job).resolve()
    names = [n.strip() for n in args.names.split(",") if n.strip()]
    lexicon = json.loads(speech.LEXICON_PATH.read_text(encoding="utf-8"))
    entries = lexicon["entries"]
    unknown = [n for n in names if n not in entries]
    if unknown:
        raise RuntimeError("Not in the pronunciation lexicon: " + ", ".join(unknown))
    thresholds = {"word_accuracy_min": args.word_min, "phoneme_accuracy_min": args.phoneme_min}
    receipts = {p.name[: -len(".receipt.json")]: json.loads(p.read_text(encoding="utf-8"))
                for p in sorted((job / "takes").glob("*.receipt.json"))}
    occurrences = find_occurrences(receipts, names)
    seconds = 0.0
    line_words, line_texts = {}, {}
    for take in sorted({o["take"] for o in occurrences}):
        line_texts[take] = line_text(job, take)
        line_words[take] = assess_line(sdk, job / "takes" / f"{take}.wav", line_texts[take])
        seconds += float(receipts[take].get("duration_seconds") or 0)
    seen, found = {}, []
    for occ in occurrences:
        nth = seen.get((occ["take"], occ["name"]), 0)
        seen[(occ["take"], occ["name"])] = nth + 1
        judged = judge_clip(parse_word(name_word(line_words[occ["take"]], occ["name"], nth)),
                            entries[occ["name"]].get("finalPhone"), thresholds)
        found.append({"take": occ["take"], "name": occ["name"], "occurrence": nth, "start": occ["start"], "end": occ["end"],
                      "checkA": judged})
    anchors = {}
    if args.anchors:
        for n in names:
            p = Path(args.anchors) / f"{n}.wav"
            if p.is_file():
                anchors[n] = (p, transcribe(sdk, p))
    if anchors:
        clip_dir = job / "qa" / "pronunciation" / "clips"
        clip_dir.mkdir(parents=True, exist_ok=True)
        for c in found:
            if c["name"] in anchors:
                a, b = clip_window(c["start"], c["end"], receipts[c["take"]].get("duration_seconds"))
                dst = clip_dir / f"{c['take']}-{c['name']}-{c['occurrence'] + 1}.wav"
                cut_clip(job / "takes" / f"{c['take']}.wav", dst, a, b)
                seconds += b - a
                heard = transcribe(sdk, dst)
                c["checkC"] = {"clip": dst.name, "clipSha256": _sha(dst), "clipHeard": heard,
                               "anchorHeard": anchors[c["name"]][1], "ok": bool(heard) and heard == anchors[c["name"]][1]}
    negative = None
    if args.negative_control:
        attempts = failed = 0
        detail = []
        for c in found:
            for other in names:
                if other == c["name"]:
                    continue
                swapped = swap_nth(line_texts[c["take"]], c["name"], other, c["occurrence"])
                words = assess_line(sdk, job / "takes" / f"{c['take']}.wav", swapped)
                seconds += float(receipts[c["take"]].get("duration_seconds") or 0)
                judged = judge_clip(parse_word(name_word(words, other, 0)), entries[other].get("finalPhone"), thresholds)
                attempts += 1
                failed += 0 if judged["ok"] else 1
                detail.append({"take": c["take"], "spoken": c["name"], "assessedAs": other, "failedAsExpected": not judged["ok"]})
        negative = {"attempts": attempts, "correctlyFailed": failed, "detail": detail}
    per_name = {}
    for n in names:
        mine = [c for c in found if c["name"] == n]
        anchor_results = [c["checkC"]["ok"] for c in mine if "checkC" in c] if n in anchors else None
        per_name[n] = {**verdict_for_name([c["checkA"] for c in mine], entries[n], anchor_results, negative),
                       "occurrences": len(mine)}
    report = {
        "schema": SCHEMA, "method": "whole-line assessment, name read in context",
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "lexicon": {"revision": lexicon["revision"], "sha256": _sha(speech.LEXICON_PATH)},
        "thresholds": {**DEFAULTS, **thresholds}, "takes": {t: _sha(job / "takes" / f"{t}.wav") for t in sorted(line_words)},
        "names": per_name, "occurrences": found, "negativeControl": negative,
        "notRun": ["check B: phone recognizer without the expected answer (needs a model; local AI is off, so remote compute only)",
                   "a human listen: automation cannot decide how a person's own name should sound"],
        "cost": {"audioSecondsSent": round(seconds, 1), "basis": "Speech-to-text list rate, about 1 USD per hour; the free tier is used by default. Not an invoice."},
        "credentials": "read from environment variables AZURE_SPEECH_KEY and AZURE_SPEECH_REGION; never written",
    }
    out = job / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for n, v in per_name.items():
        print(f"{n}: {v['verdict']}  (A {v['checkA']}, C {v['checkC']}, negative control {v['negativeControl']}, lexicon {v['lexiconStatus']})")
    return 0 if all(v["verdict"] in ("CONFIRMED", "AUTOMATED_PASS_UNCONFIRMED") for v in per_name.values()) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as error:
        print(json.dumps({"stage": "stopped", "detail": str(error)}))
        sys.exit(2)
    except Exception as error:  # provider exceptions can carry headers; print the type only
        print(json.dumps({"stage": "stopped", "error_type": type(error).__name__}))
        sys.exit(2)
