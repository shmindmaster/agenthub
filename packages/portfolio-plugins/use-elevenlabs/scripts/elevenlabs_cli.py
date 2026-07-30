#!/usr/bin/env python3
"""Small, dependency-free ElevenLabs capability CLI."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

BASE_URL = "https://api.elevenlabs.io/v1"


def request(path: str, method: str = "GET", body: bytes | None = None, content_type: str | None = None):
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise RuntimeError("ELEVENLABS_API_KEY is not set")
    headers = {"xi-api-key": key, "Accept": "application/json"}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(BASE_URL + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, response.headers.get_content_type(), response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"ElevenLabs API returned HTTP {exc.code}") from None
    except urllib.error.URLError as exc:
        raise RuntimeError("ElevenLabs API request failed") from exc


def health(_: argparse.Namespace) -> int:
    _, _, raw = request("/user")
    data = json.loads(raw)
    subscription = data.get("subscription") or {}
    print(json.dumps({
        "ok": True,
        "has_subscription": bool(subscription),
        "has_character_limit": "character_limit" in subscription,
        "has_voice_limit": "voice_limit" in subscription,
    }))
    return 0


def voices(_: argparse.Namespace) -> int:
    _, _, raw = request("/voices")
    data = json.loads(raw)
    voices = [{"voice_id": v.get("voice_id"), "name": v.get("name")} for v in data.get("voices", [])]
    print(json.dumps({"count": len(voices), "voices": voices}, ensure_ascii=False))
    return 0


def tts(args: argparse.Namespace) -> int:
    voice_id = args.voice_id or os.environ.get("ELEVENLABS_VOICE_ID")
    if not voice_id:
        raise RuntimeError("Provide --voice-id or set ELEVENLABS_VOICE_ID")
    model_id = args.model_id or os.environ.get("ELEVENLABS_MODEL_TTS_DEFAULT", "eleven_multilingual_v2")
    voice_settings = {
        key: value
        for key, value in {
            "stability": args.stability,
            "similarity_boost": args.similarity_boost,
            "style": args.style,
            "speed": args.speed,
            "use_speaker_boost": args.use_speaker_boost,
        }.items()
        if value is not None
    }
    payload_object = {
        "text": args.text,
        "model_id": model_id,
        **({"voice_settings": voice_settings} if voice_settings else {}),
        **({"apply_text_normalization": args.text_normalization} if args.text_normalization else {}),
        **({"previous_text": args.previous_text} if args.previous_text else {}),
        **({"next_text": args.next_text} if args.next_text else {}),
    }
    payload = json.dumps(payload_object).encode("utf-8")
    _, content_type, raw = request(f"/text-to-speech/{voice_id}", method="POST", body=payload, content_type="application/json")
    output = pathlib.Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(raw)
    print(json.dumps({"ok": True, "output": str(output), "content_type": content_type, "model_id": model_id}))
    return 0


def multipart_file(fields: dict[str, str], file_field: str, file_path: pathlib.Path) -> tuple[bytes, str]:
    """Build a multipart payload without adding a third-party dependency."""
    boundary = f"----elevenlabs-{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            value.encode("utf-8"),
            b"\r\n",
        ])
    content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    chunks.extend([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'.encode(),
        f"Content-Type: {content_type}\r\n\r\n".encode(),
        file_path.read_bytes(),
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def is_evidence_drive(path: pathlib.Path) -> bool:
    return str(path).upper().startswith("G:\\")


def transcribe(args: argparse.Namespace) -> int:
    input_path = pathlib.Path(args.input).expanduser().resolve()
    if is_evidence_drive(input_path):
        raise RuntimeError("Refusing cloud transcription for G:\\ evidence. Use an approved local workflow.")
    if not args.approve_cloud:
        raise RuntimeError("Cloud transcription requires --approve-cloud for this explicit non-sensitive input.")
    if not input_path.is_file():
        raise RuntimeError("Input file does not exist or is not a regular file")

    model_id = args.model_id or os.environ.get("ELEVENLABS_MODEL_STT_DEFAULT", "scribe_v2")
    fields = {"model_id": model_id}
    if args.language_code:
        fields["language_code"] = args.language_code
    if args.diarize:
        fields["diarize"] = "true"
    if args.tag_audio_events:
        fields["tag_audio_events"] = "true"
    body, content_type = multipart_file(fields, "file", input_path)
    _, _, raw = request("/speech-to-text", method="POST", body=body, content_type=content_type)
    data = json.loads(raw)

    output = pathlib.Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    provenance = {
        "input_name": input_path.name,
        "input_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "input_bytes": input_path.stat().st_size,
        "provider": "elevenlabs",
        "model_id": model_id,
        "cloud_approved": True,
        "output": str(output),
    }
    output.with_suffix(output.suffix + ".provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"ok": True, "output": str(output), "model_id": model_id, "cloud_approved": True}))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="ElevenLabs capability CLI")
    sub = parser.add_subparsers(dest="command", required=True)
    p_health = sub.add_parser("health")
    p_health.set_defaults(func=health)
    p_voices = sub.add_parser("voices")
    p_voices.set_defaults(func=voices)
    p_tts = sub.add_parser("tts")
    p_tts.add_argument("--text", required=True)
    p_tts.add_argument("--output", required=True)
    p_tts.add_argument("--voice-id")
    p_tts.add_argument("--model-id")
    p_tts.add_argument("--stability", type=float)
    p_tts.add_argument("--similarity-boost", type=float)
    p_tts.add_argument("--style", type=float)
    p_tts.add_argument("--speed", type=float)
    p_tts.add_argument(
        "--use-speaker-boost",
        action=argparse.BooleanOptionalAction,
        default=None,
    )
    p_tts.add_argument("--text-normalization", choices=["auto", "on", "off"])
    p_tts.add_argument("--previous-text")
    p_tts.add_argument("--next-text")
    p_tts.set_defaults(func=tts)
    p_transcribe = sub.add_parser("transcribe", help="Transcribe an explicitly approved, non-sensitive local file")
    p_transcribe.add_argument("--input", required=True)
    p_transcribe.add_argument("--output", required=True)
    p_transcribe.add_argument("--model-id")
    p_transcribe.add_argument("--language-code")
    p_transcribe.add_argument("--diarize", action="store_true")
    p_transcribe.add_argument("--tag-audio-events", action="store_true")
    p_transcribe.add_argument("--approve-cloud", action="store_true", help="Confirm this file is approved for cloud transcription")
    p_transcribe.set_defaults(func=transcribe)
    args = parser.parse_args()
    try:
        return args.func(args)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
