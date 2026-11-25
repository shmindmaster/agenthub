"""
title: Daytona Media Lab
author: AgentHub
description: Self-hosted Daytona AI Media Lab tool for image, image editing, video, talking avatar, TTS, music, and transcription, with safe artifact refs for multi-step chaining.
version: 1.0.0
license: MIT
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import re
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

_SAFE_TOKEN = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
_SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_MAX_JOB_SECONDS = 3600


class Tools:
    """Open WebUI toolset connecting to https://inference.shtrial.com/v1/media."""

    class Valves(BaseModel):
        media_gateway_url: str = Field(
            default="https://inference.shtrial.com/v1/media",
            description="Permanent AgentHub Daytona Media Lab gateway URL.",
        )
        inference_api_key: str = Field(
            default="",
            description="AGENTHUB_INFERENCE_KEY Bearer token used to call /v1/media.",
        )
        default_profile: str = Field(
            default="commercial",
            description="Default authorization_profile: 'commercial' (Apache-2.0/MIT) or 'research' (uncensored).",
        )
        public_media_base_url: str = Field(
            default="https://studio.shtrial.com/media-out",
            description="Public HTTPS prefix mapped to media_out_dir for inline chat previews.",
        )
        public_download_base_url: str = Field(
            default="https://studio.shtrial.com/media-dl",
            description="Public HTTPS prefix with Content-Disposition: attachment for direct local PC downloads.",
        )
        media_out_dir: str = Field(
            default="/app/backend/data/media_out",
            description="Directory inside Open WebUI container where verified outputs are stored.",
        )

    def __init__(self) -> None:
        self.valves = self.Valves()

    def _headers(self, has_json: bool = False) -> dict[str, str]:
        key = (self.valves.inference_api_key or "").strip()
        if not key:
            raise RuntimeError("Daytona Media Lab valve 'inference_api_key' is not configured.")
        headers = {"Authorization": f"Bearer {key}"}
        if has_json:
            headers["Content-Type"] = "application/json"
        return headers

    def _mask(self, text: str) -> str:
        key = (self.valves.inference_api_key or "").strip()
        if key and len(key) >= 4:
            text = text.replace(key, "****" + key[-4:])
        return re.sub(r"(?i)(bearer\s+)[^\s\"',]+", r"\1****", text)

    def _request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        raw: bool = False,
        timeout: int = 120,
    ) -> Any:
        base = self.valves.media_gateway_url.rstrip("/")
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(base + path, data=payload, headers=self._headers(payload is not None), method=method)
        attempts = 3
        for attempt in range(1, attempts + 1):
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    data = resp.read()
                break
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", errors="replace")[:500]
                if exc.code in (502, 503, 504) and method in ("GET", "DELETE") and attempt < attempts:
                    time.sleep(2 * attempt)
                    continue
                if exc.code in (401, 502, 503, 504):
                    raise RuntimeError(
                        f"Media Lab HTTP {exc.code}: the Slot 2 media GPU is offline or expired. "
                        f"Start it with `gpu.py up media --gpu MI355X` (with SH_FORGE_UPDATE=1) or the local AI Media Lab app. "
                        f"Detail: {self._mask(detail)}"
                    ) from exc
                raise RuntimeError(f"Media Lab {method} {path} failed (HTTP {exc.code}): {self._mask(detail)}") from exc
            except (urllib.error.URLError, ConnectionError) as exc:
                if attempt == attempts:
                    raise RuntimeError(f"Media Lab connection failed ({type(exc).__name__}): {self._mask(str(exc))}") from exc
                time.sleep(2 * attempt)
        return data if raw else json.loads(data.decode("utf-8"))

    def _resolve_profile(self, profile: str) -> str:
        chosen = (profile or self.valves.default_profile or "commercial").strip().lower()
        if chosen not in ("commercial", "research"):
            raise ValueError(f"authorization_profile must be 'commercial' or 'research', got {profile!r}")
        return chosen

    def _resolve_ref(self, ref: str) -> tuple[str, bytes]:
        cleaned = (ref or "").strip().strip("/")
        parts = cleaned.split("/")
        if len(parts) != 2 or not _SAFE_TOKEN.match(parts[0]) or not _SAFE_NAME.match(parts[1]) or ".." in parts[1]:
            raise ValueError(f"Invalid artifact ref {ref!r}. Expected '<token>/<filename>' returned by a previous tool step.")
        root = Path(self.valves.media_out_dir).resolve()
        target = (root / parts[0] / parts[1]).resolve()
        if root not in target.parents or not target.is_file():
            raise FileNotFoundError(f"Artifact ref not found: {cleaned}")
        return parts[1], target.read_bytes()

    async def _run_job(self, job_type: str, params: dict[str, Any], profile: str) -> str:
        chosen_profile = self._resolve_profile(profile)
        job = await asyncio.to_thread(
            self._request,
            "POST",
            "/v1/jobs",
            {"type": job_type, "authorization_profile": chosen_profile, "params": params},
        )
        jid = str(job["id"])
        if not _SAFE_NAME.match(jid) or ".." in jid:
            raise RuntimeError(f"Unsafe job id from server: {jid[:80]!r}")

        t0 = time.monotonic()
        while job.get("state") not in ("done", "error"):
            if time.monotonic() - t0 > _MAX_JOB_SECONDS:
                raise RuntimeError(f"Media job {jid} timed out after {_MAX_JOB_SECONDS}s (still {job.get('state')}).")
            await asyncio.sleep(4)
            job = await asyncio.to_thread(self._request, "GET", f"/v1/jobs/{jid}")

        if job.get("state") == "error":
            raise RuntimeError(f"Media job {jid} failed: {job.get('error', 'unknown error')}")

        run_token = secrets.token_hex(12)
        out_dir = Path(self.valves.media_out_dir) / run_token
        out_dir.mkdir(parents=True, exist_ok=True)
        public_base = self.valves.public_media_base_url.rstrip("/")
        dl_base = (self.valves.public_download_base_url or public_base).rstrip("/")

        saved: list[str] = []
        text_previews: list[str] = []
        for item in job.get("outputs", []):
            name = str(item["name"])
            if not _SAFE_NAME.match(name) or ".." in name:
                raise RuntimeError(f"Unsafe output name from server: {name[:80]!r}")
            data = await asyncio.to_thread(
                self._request, "GET", f"/v1/files/{jid}/{urllib.parse.quote(name)}", raw=True, timeout=600
            )
            digest = hashlib.sha256(data).hexdigest()
            if len(data) != int(item["size"]) or digest != item["sha256"]:
                raise RuntimeError(f"Integrity check failed for {name}: size={len(data)} sha256={digest[:12]}")
            (out_dir / name).write_bytes(data)

            ref = f"{run_token}/{name}"
            url = f"{public_base}/{ref}"
            dl_url = f"{dl_base}/{ref}"
            ext = Path(name).suffix.lower()
            if ext in (".png", ".jpg", ".jpeg", ".webp"):
                saved.append(f"![{name}]({url})\n- [Download {name}]({dl_url})\n- ref: `{ref}`")
            else:
                saved.append(f"- [View {name}]({url}) · [Download {name}]({dl_url})\n  ref: `{ref}`")
            if ext in (".txt", ".srt", ".json") and len(data) <= 16384:
                text_previews.append(f"```{ext.lstrip('.')}\n{data.decode('utf-8', errors='replace').strip()}\n```")

        try:
            await asyncio.to_thread(self._request, "DELETE", f"/v1/jobs/{jid}")
        except Exception:
            pass

        header = (
            f"**{job_type}** finished (`model={job.get('model')}`, `profile={chosen_profile}`, "
            f"`seconds={job.get('seconds')}`, `peak_vram_gb={job.get('peak_vram_gb')}`)"
        )
        sections = [header, *saved, *text_previews]
        return "\n\n".join(sections)

    async def media_lab_status(self) -> str:
        """Check whether the Daytona Media Lab GPU is online and list loaded models and VRAM telemetry."""
        try:
            info = await asyncio.to_thread(self._request, "GET", "/v1/info", timeout=15)
            return json.dumps(info, indent=2)
        except Exception as exc:
            return f"Media Lab offline or unreachable: {exc}"

    async def generate_image(
        self,
        prompt: str,
        profile: str = "",
        width: int = 1024,
        height: int = 1024,
        steps: int = 0,
        seed: int = -1,
        negative: str = "",
    ) -> str:
        """Generate an image. Returns an inline image preview URL and an artifact ref for chaining."""
        params: dict[str, Any] = {"prompt": prompt, "width": width, "height": height}
        if negative:
            params["negative"] = negative
        if steps > 0:
            params["steps"] = steps
        if seed >= 0:
            params["seed"] = seed
        return await self._run_job("image", params, profile)

    async def edit_image(
        self,
        prompt: str,
        input_ref: str,
        profile: str = "research",
        steps: int = 0,
        seed: int = -1,
    ) -> str:
        """Edit a previously generated image (pass input_ref as '<token>/<filename>')."""
        fname, raw = self._resolve_ref(input_ref)
        params: dict[str, Any] = {
            "prompt": prompt,
            "input_b64": base64.b64encode(raw).decode("ascii"),
            "input_name": fname,
        }
        if steps > 0:
            params["steps"] = steps
        if seed >= 0:
            params["seed"] = seed
        return await self._run_job("image_edit", params, profile)

    async def generate_video(
        self,
        prompt: str,
        start_image_ref: str,
        profile: str = "",
        width: int = 640,
        height: int = 640,
        frames: int = 81,
        quality: str = "draft",
        steps: int = 0,
        seed: int = -1,
    ) -> str:
        """Animate a starting image into a video clip (pass start_image_ref as '<token>/<filename>')."""
        fname, raw = self._resolve_ref(start_image_ref)
        params: dict[str, Any] = {
            "prompt": prompt,
            "input_b64": base64.b64encode(raw).decode("ascii"),
            "input_name": fname,
            "width": width,
            "height": height,
            "frames": frames,
            "quality": quality,
        }
        if steps > 0:
            params["steps"] = steps
        if seed >= 0:
            params["seed"] = seed
        return await self._run_job("video", params, profile)

    async def generate_talking_video(
        self,
        portrait_ref: str,
        audio_ref: str,
        prompt: str = "a person speaking clearly to the camera",
        profile: str = "",
        subject: str = "synthetic",
        width: int = 512,
        height: int = 512,
        seed: int = -1,
    ) -> str:
        """Generate a lip-synced talking video from portrait_ref ('<token>/<file>') and audio_ref ('<token>/<file>')."""
        img_name, img_raw = self._resolve_ref(portrait_ref)
        aud_name, aud_raw = self._resolve_ref(audio_ref)
        params: dict[str, Any] = {
            "prompt": prompt,
            "input_b64": base64.b64encode(img_raw).decode("ascii"),
            "input_name": img_name,
            "audio_b64": base64.b64encode(aud_raw).decode("ascii"),
            "audio_name": aud_name,
            "subject": subject,
            "width": width,
            "height": height,
        }
        if seed >= 0:
            params["seed"] = seed
        return await self._run_job("talk", params, profile)

    async def generate_tts(
        self,
        text: str,
        speaker: str = "ryan",
        language: str = "English",
        instruct: str = "",
        profile: str = "",
    ) -> str:
        """Synthesize speech audio from text and return its download URL + artifact ref for talking-video chaining."""
        params: dict[str, Any] = {"text": text, "speaker": speaker, "language": language}
        if instruct:
            params["instruct"] = instruct
        return await self._run_job("tts", params, profile)

    async def generate_music(
        self,
        tags: str,
        lyrics: str = "",
        seconds: int = 30,
        bpm: int = 100,
        profile: str = "",
        seed: int = -1,
    ) -> str:
        """Generate background music/song audio from tags and optional lyrics."""
        params: dict[str, Any] = {"tags": tags, "lyrics": lyrics, "seconds": seconds, "bpm": bpm}
        if seed >= 0:
            params["seed"] = seed
        return await self._run_job("music", params, profile)

    async def transcribe_audio(
        self,
        audio_ref: str,
        language: str = "English",
        profile: str = "",
    ) -> str:
        """Transcribe an audio artifact ('<token>/<filename>') and return SRT + JSON transcript."""
        aud_name, aud_raw = self._resolve_ref(audio_ref)
        params: dict[str, Any] = {
            "input_b64": base64.b64encode(aud_raw).decode("ascii"),
            "input_name": aud_name,
            "language": language,
        }
        return await self._run_job("transcribe", params, profile)
