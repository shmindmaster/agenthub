"""
title: Cloud Media APIs
author: AgentHub
description: Entity-routed cloud media & telemetry APIs (OpenAI, Azure Foundry, Deepgram Flux/Nova, AssemblyAI Clones/STT, Runware API, ElevenLabs exception-only) saving verified outputs with direct download links and chaining refs.
version: 1.0.0
license: MIT
"""

from __future__ import annotations

import asyncio
import base64
import json
import re
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import date
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

_SAFE_TOKEN = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
_SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_OPENAI_ABACARE_GRANT_UNTIL = date(2026, 11, 26)
_ASSEMBLYAI_CLONES = {
    "sarosh": "01a205c1-f84a-72aa-b55d-b8f07c21ffc1",
    "sarosh-hussain": "01a205c1-f84a-72aa-b55d-b8f07c21ffc1",
    "syeda": "01a205c0-1d0d-72a1-bc74-867a26d905a6",
    "syeda-fatima-abidi": "01a205c0-1d0d-72a1-bc74-867a26d905a6",
}


class Tools:
    """Entity-routed cloud media generation & balance checks matching Film Desk & Linear BIZ-22 rules."""

    class Valves(BaseModel):
        openai_api_key: str = Field(default="", description="OPENAI_API_KEY (ABACare org grant / fallback).")
        azure_ai_services_endpoint: str = Field(
            default="https://mt-foundary-resource.openai.azure.com",
            description="MahumTech Azure Foundry resource endpoint.",
        )
        azure_ai_services_key: str = Field(default="", description="AZURE_AI_SERVICES_KEY for mt-foundary-resource.")
        deepgram_api_key: str = Field(default="", description="DEEPGRAM_API_KEY (MahumTech project, stock voices default).")
        assemblyai_api_key: str = Field(default="", description="ASSEMBLYAI_API_KEY (ABACare AI LLC + consented clones).")
        runware_api_key: str = Field(default="", description="RUNWARE_API_KEY (ABACare Startup API credit).")
        elevenlabs_api_key: str = Field(default="", description="ELEVENLABS_API_KEY (exception-only with written reason).")
        openrouter_api_key: str = Field(default="", description="OPENROUTER_API_KEY for OpenRouter image models.")
        deepseek_api_key: str = Field(default="", description="DEEPSEEK_API_KEY for live balance readback.")
        pexels_api_key: str = Field(default="", description="PEXELS_API_KEY for free stock photos and videos.")
        reducto_api_key: str = Field(default="", description="REDUCTO_API_KEY (ABACare) for complex PDF/document parsing.")
        default_entity: str = Field(
            default="personal",
            description="Default billing/routing entity: 'personal', 'mahumtech', or 'abacare'.",
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
            description="Shared artifact directory inside Open WebUI container.",
        )

    def __init__(self) -> None:
        self.valves = self.Valves()

    def _mask(self, text: str) -> str:
        secrets_list = [
            self.valves.openai_api_key,
            self.valves.azure_ai_services_key,
            self.valves.deepgram_api_key,
            self.valves.assemblyai_api_key,
            self.valves.runware_api_key,
            self.valves.elevenlabs_api_key,
            self.valves.openrouter_api_key,
            self.valves.deepseek_api_key,
            self.valves.pexels_api_key,
            self.valves.reducto_api_key,
        ]
        for s in secrets_list:
            sv = (s or "").strip()
            if len(sv) >= 8:
                text = text.replace(sv, "****" + sv[-4:])
        return re.sub(r"(?i)((?:bearer|token)\s+)[^\s\"',]+", r"\1****", text)

    def _http(
        self,
        url: str,
        method: str = "GET",
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        timeout: int = 180,
    ) -> tuple[int, bytes, dict[str, str]]:
        req = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read(), {k.lower(): v for k, v in r.headers.items()}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:500]
            raise RuntimeError(f"HTTP {exc.code} from {urllib.parse.urlparse(url).netloc}: {self._mask(detail)}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            raise RuntimeError(f"Request failed ({type(exc).__name__}): {self._mask(str(exc))}") from None

    def _http_json(
        self,
        url: str,
        method: str = "GET",
        headers: dict[str, str] | None = None,
        payload: Any = None,
        timeout: int = 180,
    ) -> Any:
        hdrs = dict(headers or {})
        body: bytes | None = None
        if payload is not None:
            hdrs.setdefault("Content-Type", "application/json")
            body = json.dumps(payload).encode("utf-8")
        _, raw, _ = self._http(url, method=method, headers=hdrs, body=body, timeout=timeout)
        return json.loads(raw.decode("utf-8"))

    def _save_output(self, filename: str, data: bytes, run_token: str | None = None) -> tuple[str, str, str]:
        if not _SAFE_NAME.match(filename) or ".." in filename:
            raise ValueError(f"Unsafe filename: {filename!r}")
        token = run_token or secrets.token_hex(12)
        out_dir = Path(self.valves.media_out_dir) / token
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / filename).write_bytes(data)
        ref = f"{token}/{filename}"
        view_url = f"{self.valves.public_media_base_url.rstrip('/')}/{ref}"
        dl_url = f"{(self.valves.public_download_base_url or self.valves.public_media_base_url).rstrip('/')}/{ref}"
        return ref, view_url, dl_url

    def _resolve_ref(self, ref: str) -> tuple[str, bytes, str]:
        cleaned = (ref or "").strip().strip("/")
        parts = cleaned.split("/")
        if len(parts) != 2 or not _SAFE_TOKEN.match(parts[0]) or not _SAFE_NAME.match(parts[1]) or ".." in parts[1]:
            raise ValueError(f"Invalid artifact ref {ref!r}. Expected '<token>/<filename>'.")
        root = Path(self.valves.media_out_dir).resolve()
        target = (root / parts[0] / parts[1]).resolve()
        if root not in target.parents or not target.is_file():
            raise FileNotFoundError(f"Artifact ref not found: {cleaned}")
        ext = target.suffix.lower()
        mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".wav": "audio/wav", ".mp3": "audio/mpeg", ".mp4": "video/mp4"}.get(ext, "application/octet-stream")
        return parts[1], target.read_bytes(), mime

    def _norm_entity(self, entity: str) -> str:
        val = (entity or self.valves.default_entity or "personal").strip().lower()
        if val not in ("abacare", "mahumtech", "personal"):
            raise ValueError(f"entity must be 'abacare', 'mahumtech', or 'personal', got {entity!r}")
        return val

    async def cloud_media_balances(self) -> str:
        """Read live available balances/accounts across Runware, ElevenLabs, Deepgram, and AssemblyAI (zero spend)."""
        report: dict[str, Any] = {
            "routing_rules": {
                "stock_voice_non_abacare": "deepgram (MahumTech, Flux expressivity=0)",
                "voice_abacare_and_clones": "assemblyai (ABACare, clones sarosh-hussain / syeda-fatima-abidi valid to 2027-01-22)",
                "images_abacare": f"openai gpt-image-2.6-flare until {_OPENAI_ABACARE_GRANT_UNTIL.isoformat()}, then runware",
                "images_other": "azure mt-foundary-resource gpt-image-2.5-flare",
                "video_music_cloud": "runware API credit (not Runware Serverless)",
                "elevenlabs": "exception-only with explicit written reason",
                "frozen": ["gemini_ai_studio (paused until 2026-12-01)", "runway", "higgsfield"],
            },
            "providers": {},
        }

        def _probe_all() -> None:
            rk = (self.valves.runware_api_key or "").strip()
            if rk:
                try:
                    rw = self._http_json(
                        "https://api.runware.ai/v1",
                        method="POST",
                        headers={"Authorization": f"Bearer {rk}"},
                        payload=[{"taskType": "accountManagement", "operation": "getDetails", "taskUUID": str(uuid.uuid4())}],
                        timeout=20,
                    )
                    row = (rw.get("data") or [{}])[0]
                    report["providers"]["runware"] = {
                        "org": row.get("organizationName"),
                        "api_credit_usd": row.get("balance"),
                    }
                except Exception as exc:
                    report["providers"]["runware"] = {"error": str(exc)}

            ek = (self.valves.elevenlabs_api_key or "").strip()
            if ek:
                try:
                    el = self._http_json(
                        "https://api.elevenlabs.io/v1/user/subscription",
                        headers={"xi-api-key": ek},
                        timeout=20,
                    )
                    used = el.get("character_count")
                    limit = el.get("character_limit")
                    report["providers"]["elevenlabs"] = {
                        "tier": el.get("tier"),
                        "status": el.get("status"),
                        "credits_remaining": (limit - used) if isinstance(used, int) and isinstance(limit, int) else None,
                        "character_limit": limit,
                    }
                except Exception as exc:
                    report["providers"]["elevenlabs"] = {"error": str(exc)}

            dk = (self.valves.deepgram_api_key or "").strip()
            if dk:
                try:
                    dg = self._http_json(
                        "https://api.deepgram.com/v1/projects",
                        headers={"Authorization": f"Token {dk}"},
                        timeout=20,
                    )
                    report["providers"]["deepgram"] = {
                        "projects": [p.get("name") for p in dg.get("projects", [])],
                        "note": "API key lacks billing:read scope; console snapshot recorded $2,111.89 non-expiring credit.",
                    }
                except Exception as exc:
                    report["providers"]["deepgram"] = {"error": str(exc)}

            ak = (self.valves.assemblyai_api_key or "").strip()
            if ak:
                try:
                    av = self._http_json(
                        "https://tts.us.assemblyai.com/v1/voices",
                        headers={"Authorization": ak},
                        timeout=20,
                    )
                    report["providers"]["assemblyai"] = {
                        "cloned_voices": [
                            {"slug": v.get("slug"), "id": v.get("id"), "status": v.get("status"), "expires_at": (v.get("retention") or {}).get("expires_at")}
                            for v in av.get("voices", [])
                        ],
                        "note": "Dashboard billing balance read in BIZ-22 on 2026-11-25 at $295.52 (autopay off).",
                    }
                except Exception as exc:
                    report["providers"]["assemblyai"] = {"error": str(exc)}

            report["providers"]["azure_foundry"] = {
                "endpoint": self.valves.azure_ai_services_endpoint,
                "key_configured": bool((self.valves.azure_ai_services_key or "").strip()),
            }
            report["providers"]["openai"] = {
                "key_configured": bool((self.valves.openai_api_key or "").strip()),
            }

            ork = (self.valves.openrouter_api_key or "").strip()
            if ork:
                try:
                    or_res = self._http_json(
                        "https://openrouter.ai/api/v1/auth/key",
                        headers={"Authorization": f"Bearer {ork}"},
                        timeout=20,
                    )
                    d = or_res.get("data") or {}
                    report["providers"]["openrouter"] = {
                        "limit_monthly": d.get("limit"),
                        "limit_remaining": d.get("limit_remaining"),
                    }
                except Exception as exc:
                    report["providers"]["openrouter"] = {"error": str(exc)}

            dsk = (self.valves.deepseek_api_key or "").strip()
            if dsk:
                try:
                    ds_res = self._http_json(
                        "https://api.deepseek.com/user/balance",
                        headers={"Authorization": f"Bearer {dsk}"},
                        timeout=20,
                    )
                    report["providers"]["deepseek"] = {
                        "is_available": ds_res.get("is_available"),
                        "balances": ds_res.get("balance_infos"),
                    }
                except Exception as exc:
                    report["providers"]["deepseek"] = {"error": str(exc)}

            report["providers"]["pexels"] = {
                "key_configured": bool((self.valves.pexels_api_key or "").strip()),
                "cost": "free stock photos & videos",
            }
            report["providers"]["reducto"] = {
                "key_configured": bool((self.valves.reducto_api_key or "").strip()),
            }

        await asyncio.to_thread(_probe_all)
        return json.dumps(report, indent=2)

    async def cloud_generate_image(
        self,
        prompt: str,
        entity: str = "",
        provider: str = "auto",
        size: str = "1024x1024",
        quality: str = "medium",
        model: str = "",
    ) -> str:
        """Generate an image using entity credit routing (azure|openai|runware|openrouter)."""
        ent = self._norm_entity(entity)
        chosen = (provider or "auto").strip().lower()
        if chosen == "auto":
            if ent == "abacare":
                chosen = "openai" if date.today() <= _OPENAI_ABACARE_GRANT_UNTIL else "runware"
            else:
                chosen = "azure"
        if chosen not in ("azure", "openai", "runware", "openrouter"):
            raise ValueError(f"provider must be auto|azure|openai|runware|openrouter, got {provider!r}")

        def _work() -> tuple[bytes, str, str]:
            if chosen == "azure":
                ep = (self.valves.azure_ai_services_endpoint or "").strip().rstrip("/")
                ak = (self.valves.azure_ai_services_key or "").strip()
                if not ep or not ak:
                    raise RuntimeError("Azure Foundry endpoint/key valves not configured.")
                dep = model.strip() or "gpt-image-2.5-flare"
                q = quality if quality in ("low", "medium", "high") else "medium"
                url = f"{ep}/openai/deployments/{urllib.parse.quote(dep, safe='')}/images/generations?api-version=2025-04-01-preview"
                res = self._http_json(url, method="POST", headers={"api-key": ak}, payload={"prompt": prompt, "size": size, "quality": q, "n": 1}, timeout=240)
                b64 = ((res.get("data") or [{}])[0]).get("b64_json")
                if not b64:
                    raise RuntimeError("Azure returned no image data.")
                return base64.b64decode(b64), f"azure/{dep}", "image.png"

            if chosen == "openai":
                ok = (self.valves.openai_api_key or "").strip()
                if not ok:
                    raise RuntimeError("OPENAI_API_KEY valve not configured.")
                mdl = model.strip() or "gpt-image-2.6-flare"
                res = self._http_json(
                    "https://api.openai.com/v1/images/generations",
                    method="POST",
                    headers={"Authorization": f"Bearer {ok}"},
                    payload={"model": mdl, "prompt": prompt, "size": size, "quality": quality, "n": 1, "output_format": "png"},
                    timeout=240,
                )
                b64 = ((res.get("data") or [{}])[0]).get("b64_json")
                if not b64:
                    raise RuntimeError("OpenAI returned no image data.")
                return base64.b64decode(b64), f"openai/{mdl}", "image.png"

            if chosen == "openrouter":
                ork = (self.valves.openrouter_api_key or "").strip()
                if not ork:
                    raise RuntimeError("OPENROUTER_API_KEY valve not configured.")
                mdl = model.strip() or "google/gemini-nano-banana-2.1"
                res = self._http_json(
                    "https://openrouter.ai/api/v1/chat/completions",
                    method="POST",
                    headers={"Authorization": f"Bearer {ork}"},
                    payload={"model": mdl, "messages": [{"role": "user", "content": prompt}], "modalities": ["image", "text"]},
                    timeout=240,
                )
                msg = ((res.get("choices") or [{}])[0].get("message") or {})
                imgs = msg.get("images") or []
                img_url = ""
                if imgs and isinstance(imgs[0], dict):
                    img_url = (imgs[0].get("image_url") or {}).get("url") or imgs[0].get("url") or ""
                if not img_url and isinstance(msg.get("content"), list):
                    for part in msg["content"]:
                        if isinstance(part, dict) and part.get("type") in ("image_url", "output_image"):
                            img_url = (part.get("image_url") or {}).get("url") or part.get("url") or ""
                            if img_url:
                                break
                if not img_url:
                    raise RuntimeError(f"OpenRouter {mdl} returned no image payload.")
                if img_url.startswith("data:"):
                    _, b64_part = img_url.split(",", 1)
                    return base64.b64decode(b64_part), f"openrouter/{mdl}", "image.png"
                _, img_raw, _ = self._http(img_url, timeout=180)
                return img_raw, f"openrouter/{mdl}", "image.png"

            rk = (self.valves.runware_api_key or "").strip()
            if not rk:
                raise RuntimeError("RUNWARE_API_KEY valve not configured.")
            mdl = model.strip() or "runware:z-image@0"
            w_s, h_s = size.lower().split("x")
            task = {
                "taskType": "imageInference",
                "taskUUID": str(uuid.uuid4()),
                "model": mdl,
                "positivePrompt": prompt,
                "width": int(w_s),
                "height": int(h_s),
                "steps": 8,
                "numberResults": 1,
                "outputType": "base64Data",
                "outputFormat": "PNG",
                "includeCost": True,
                "safety": {"checkContent": True},
            }
            res = self._http_json("https://api.runware.ai/v1", method="POST", headers={"Authorization": f"Bearer {rk}"}, payload=[task], timeout=240)
            if res.get("errors"):
                raise RuntimeError(f"Runware error: {res['errors'][0]}")
            row = (res.get("data") or [{}])[0]
            b64 = row.get("imageBase64Data")
            if not b64:
                raise RuntimeError("Runware returned no image data.")
            cost = row.get("cost")
            extra = f"runware/{mdl}" + (f" (cost=${cost})" if cost is not None else "")
            return base64.b64decode(b64), extra, "image.png"

        img_bytes, used_model, fname = await asyncio.to_thread(_work)
        ref, view_url, dl_url = self._save_output(fname, img_bytes)
        return (
            f"**cloud_generate_image** finished (`entity={ent}`, `model={used_model}`, `size={size}`, `bytes={len(img_bytes)}`)\n\n"
            f"![{fname}]({view_url})\n- [Download {fname}]({dl_url})\n- ref: `{ref}`"
        )

    async def cloud_generate_video(
        self,
        prompt: str,
        entity: str = "abacare",
        image_ref: str = "",
        model: str = "alibaba:wan@3.0",
        duration: int = 5,
        width: int = 1280,
        height: int = 720,
    ) -> str:
        """Generate video via Runware videoInference API credit (optional image_ref '<token>/<file>' for I2V)."""
        ent = self._norm_entity(entity)
        rk = (self.valves.runware_api_key or "").strip()
        if not rk:
            raise RuntimeError("RUNWARE_API_KEY valve not configured.")
        tid = str(uuid.uuid4())
        task: dict[str, Any] = {
            "taskType": "videoInference",
            "taskUUID": tid,
            "model": model.strip() or "alibaba:wan@3.0",
            "positivePrompt": prompt,
            "duration": int(duration),
            "width": int(width),
            "height": int(height),
            "outputType": "URL",
            "outputFormat": "MP4",
            "deliveryMethod": "async",
            "includeCost": True,
        }
        if image_ref.strip():
            _, raw, mime = self._resolve_ref(image_ref)
            task["frameImages"] = [{"inputImage": f"data:{mime};base64,{base64.b64encode(raw).decode('ascii')}", "frame": "first"}]

        await asyncio.to_thread(
            self._http_json,
            "https://api.runware.ai/v1",
            "POST",
            {"Authorization": f"Bearer {rk}"},
            [task],
            120,
        )
        t0 = time.monotonic()
        row: dict[str, Any] = {}
        while time.monotonic() - t0 < 900:
            await asyncio.sleep(5)
            poll = await asyncio.to_thread(
                self._http_json,
                "https://api.runware.ai/v1",
                "POST",
                {"Authorization": f"Bearer {rk}"},
                [{"taskType": "getResponse", "taskUUID": tid}],
                60,
            )
            if poll.get("errors"):
                raise RuntimeError(f"Runware video error: {poll['errors'][0]}")
            data = poll.get("data") or []
            if data and data[0].get("status") == "success" and data[0].get("videoURL"):
                row = data[0]
                break
        if not row.get("videoURL"):
            raise RuntimeError(f"Runware video task {tid} did not return a videoURL within 900s.")

        _, vid_bytes, _ = await asyncio.to_thread(self._http, row["videoURL"], "GET", None, None, 300)
        ref, view_url, dl_url = self._save_output("video.mp4", vid_bytes)
        cost = row.get("cost")
        return (
            f"**cloud_generate_video** finished (`entity={ent}`, `model={task['model']}`, `cost={cost}`, `bytes={len(vid_bytes)}`)\n\n"
            f"- [View video.mp4]({view_url}) · [Download video.mp4]({dl_url})\n  ref: `{ref}`"
        )

    async def cloud_generate_speech(
        self,
        text: str,
        entity: str = "",
        provider: str = "auto",
        voice: str = "",
        reason: str = "",
    ) -> str:
        """Synthesize speech using entity routing (non-ABACare->Deepgram Flux, ABACare/clones->AssemblyAI, OpenAI gpt-audio-1.5, or ElevenLabs with explicit reason)."""
        ent = self._norm_entity(entity)
        chosen = (provider or "auto").strip().lower()
        req_voice = voice.strip()
        if chosen == "auto":
            if req_voice.lower() in _ASSEMBLYAI_CLONES or ent == "abacare":
                chosen = "assemblyai"
            else:
                chosen = "deepgram"
        if chosen not in ("deepgram", "assemblyai", "openai", "elevenlabs"):
            raise ValueError(f"provider must be auto|deepgram|assemblyai|openai|elevenlabs, got {provider!r}")

        if chosen == "elevenlabs" and not reason.strip():
            raise RuntimeError("ElevenLabs requires an explicit non-empty 'reason' explaining why Deepgram/AssemblyAI cannot serve this request.")

        def _work() -> tuple[bytes, str, str]:
            if chosen == "deepgram":
                dk = (self.valves.deepgram_api_key or "").strip()
                if not dk:
                    raise RuntimeError("DEEPGRAM_API_KEY valve not configured.")
                v = req_voice or "flux-sienna-en"
                if v.startswith("aura-"):
                    q = urllib.parse.urlencode({"model": v, "encoding": "mp3"})
                    url = f"https://api.deepgram.com/v1/speak?{q}"
                    fname = "speech.mp3"
                else:
                    q = urllib.parse.urlencode({"model": v, "encoding": "linear16", "container": "wav", "sample_rate": 48000, "expressivity": 0, "mip_opt_out": "true"})
                    url = f"https://api.deepgram.com/v2/speak?{q}"
                    fname = "speech.wav"
                _, audio_bytes, _ = self._http(
                    url,
                    method="POST",
                    headers={"Authorization": f"Token {dk}", "Content-Type": "application/json"},
                    body=json.dumps({"text": text}).encode("utf-8"),
                    timeout=180,
                )
                return audio_bytes, f"deepgram/{v}", fname

            if chosen == "assemblyai":
                ak = (self.valves.assemblyai_api_key or "").strip()
                if not ak:
                    raise RuntimeError("ASSEMBLYAI_API_KEY valve not configured.")
                v = _ASSEMBLYAI_CLONES.get(req_voice.lower(), req_voice or "aai-jane")
                _, audio_bytes, _ = self._http(
                    "https://tts.us.assemblyai.com/v1/openai/audio/speech",
                    method="POST",
                    headers={"Authorization": ak, "Content-Type": "application/json"},
                    body=json.dumps({"model": "assemblyai-tts-1", "input": text, "voice": v, "response_format": "wav"}).encode("utf-8"),
                    timeout=180,
                )
                return audio_bytes, f"assemblyai/{req_voice or v}", "speech.wav"

            if chosen == "openai":
                ok = (self.valves.openai_api_key or "").strip()
                if not ok:
                    raise RuntimeError("OPENAI_API_KEY valve not configured.")
                v = req_voice or "alloy"
                res = self._http_json(
                    "https://api.openai.com/v1/chat/completions",
                    method="POST",
                    headers={"Authorization": f"Bearer {ok}"},
                    payload={
                        "model": "gpt-audio-1.5",
                        "modalities": ["text", "audio"],
                        "audio": {"voice": v, "format": "wav"},
                        "messages": [
                            {"role": "system", "content": "Read the user's exact text aloud naturally without adding or removing words."},
                            {"role": "user", "content": text},
                        ],
                    },
                    timeout=180,
                )
                b64 = (((res.get("choices") or [{}])[0].get("message") or {}).get("audio") or {}).get("data")
                if not b64:
                    raise RuntimeError("OpenAI gpt-audio-1.5 returned no audio payload.")
                return base64.b64decode(b64), f"openai/gpt-audio-1.5({v})", "speech.wav"

            ek = (self.valves.elevenlabs_api_key or "").strip()
            if not ek:
                raise RuntimeError("ELEVENLABS_API_KEY valve not configured.")
            if not req_voice:
                raise ValueError("ElevenLabs requires an explicit voice ID in 'voice'.")
            url = f"https://api.elevenlabs.io/v1/text-to-speech/{urllib.parse.quote(req_voice, safe='')}?output_format=mp3_44100_192"
            _, audio_bytes, _ = self._http(
                url,
                method="POST",
                headers={"xi-api-key": ek, "Content-Type": "application/json"},
                body=json.dumps({"text": text, "model_id": "eleven_v4", "voice_settings": {"stability": 0.5, "similarity_boost": 0.75}}).encode("utf-8"),
                timeout=180,
            )
            return audio_bytes, f"elevenlabs/eleven_v4({req_voice})", "speech.mp3"

        audio_bytes, used_model, fname = await asyncio.to_thread(_work)
        ref, view_url, dl_url = self._save_output(fname, audio_bytes)
        note = f", `reason={reason.strip()}`" if reason.strip() else ""
        return (
            f"**cloud_generate_speech** finished (`entity={ent}`, `model={used_model}`{note}, `bytes={len(audio_bytes)}`)\n\n"
            f"- [Play {fname}]({view_url}) · [Download {fname}]({dl_url})\n  ref: `{ref}`"
        )

    async def cloud_generate_music_or_sfx(
        self,
        prompt: str,
        kind: str = "music",
        provider: str = "runware",
        duration_seconds: int = 20,
        reason: str = "",
    ) -> str:
        """Generate music or SFX via Runware audioInference (default) or ElevenLabs (requires explicit written reason)."""
        chosen = (provider or "runware").strip().lower()
        knd = (kind or "music").strip().lower()
        if chosen == "elevenlabs" and not reason.strip():
            raise RuntimeError("ElevenLabs music/SFX requires a non-empty 'reason'.")
        if chosen not in ("runware", "elevenlabs"):
            raise ValueError(f"provider must be runware|elevenlabs, got {provider!r}")

        def _work() -> tuple[bytes, str, str]:
            if chosen == "runware":
                rk = (self.valves.runware_api_key or "").strip()
                if not rk:
                    raise RuntimeError("RUNWARE_API_KEY valve not configured.")
                tid = str(uuid.uuid4())
                task = {
                    "taskType": "audioInference",
                    "taskUUID": tid,
                    "positivePrompt": prompt,
                    "duration": int(duration_seconds),
                    "outputType": "URL",
                    "outputFormat": "MP3",
                    "includeCost": True,
                }
                res = self._http_json("https://api.runware.ai/v1", method="POST", headers={"Authorization": f"Bearer {rk}"}, payload=[task], timeout=240)
                if res.get("errors"):
                    raise RuntimeError(f"Runware audio error: {res['errors'][0]}")
                row = (res.get("data") or [{}])[0]
                if row.get("audioBase64Data"):
                    return base64.b64decode(row["audioBase64Data"]), "runware/audioInference", "audio.mp3"
                aurl = row.get("audioURL")
                if not aurl:
                    deadline = time.monotonic() + 300
                    while time.monotonic() < deadline:
                        time.sleep(4)
                        poll = self._http_json("https://api.runware.ai/v1", method="POST", headers={"Authorization": f"Bearer {rk}"}, payload=[{"taskType": "getResponse", "taskUUID": tid}], timeout=60)
                        rows = poll.get("data") or []
                        if rows and rows[0].get("audioURL"):
                            aurl = rows[0]["audioURL"]
                            break
                if not aurl:
                    raise RuntimeError("Runware audioInference returned no audioURL.")
                _, raw, _ = self._http(aurl, timeout=180)
                return raw, "runware/audioInference", "audio.mp3"

            ek = (self.valves.elevenlabs_api_key or "").strip()
            if not ek:
                raise RuntimeError("ELEVENLABS_API_KEY valve not configured.")
            if knd == "sfx":
                _, raw, _ = self._http(
                    "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_192",
                    method="POST",
                    headers={"xi-api-key": ek, "Content-Type": "application/json"},
                    body=json.dumps({"text": prompt, "model_id": "eleven_text_to_sound_v3", "duration_seconds": float(duration_seconds)}).encode("utf-8"),
                    timeout=180,
                )
                return raw, "elevenlabs/eleven_text_to_sound_v3", "sfx.mp3"
            _, raw, _ = self._http(
                "https://api.elevenlabs.io/v1/music?output_format=mp3_44100_192",
                method="POST",
                headers={"xi-api-key": ek, "Content-Type": "application/json"},
                body=json.dumps({"prompt": prompt, "model_id": "music_v2_5", "force_instrumental": True, "music_length_ms": max(3000, int(duration_seconds) * 1000)}).encode("utf-8"),
                timeout=240,
            )
            return raw, "elevenlabs/music_v2_5", "music.mp3"

        raw, used_model, fname = await asyncio.to_thread(_work)
        ref, view_url, dl_url = self._save_output(fname, raw)
        return (
            f"**cloud_generate_music_or_sfx** finished (`model={used_model}`, `bytes={len(raw)}`)\n\n"
            f"- [Play {fname}]({view_url}) · [Download {fname}]({dl_url})\n  ref: `{ref}`"
        )

    async def cloud_transcribe_audio(
        self,
        audio_ref: str,
        provider: str = "deepgram",
        language: str = "en",
    ) -> str:
        """Transcribe an audio artifact ('<token>/<filename>') via Deepgram Nova-3 or AssemblyAI universal-3-pro."""
        fname, raw, mime = self._resolve_ref(audio_ref)
        chosen = (provider or "deepgram").strip().lower()
        if chosen not in ("deepgram", "assemblyai"):
            raise ValueError(f"provider must be deepgram|assemblyai, got {provider!r}")

        def _work() -> tuple[str, bytes, bytes | None]:
            if chosen == "deepgram":
                dk = (self.valves.deepgram_api_key or "").strip()
                if not dk:
                    raise RuntimeError("DEEPGRAM_API_KEY valve not configured.")
                q = urllib.parse.urlencode({"model": "nova-3", "smart_format": "true", "utterances": "true", "language": language})
                _, dg_raw, _ = self._http(
                    f"https://api.deepgram.com/v1/listen?{q}",
                    method="POST",
                    headers={"Authorization": f"Token {dk}", "Content-Type": mime},
                    body=raw,
                    timeout=180,
                )
                res = json.loads(dg_raw.decode("utf-8"))
                txt = ((((res.get("results") or {}).get("channels") or [{}])[0].get("alternatives") or [{}])[0]).get("transcript", "")
                return txt, json.dumps(res, indent=2).encode("utf-8"), None

            ak = (self.valves.assemblyai_api_key or "").strip()
            if not ak:
                raise RuntimeError("ASSEMBLYAI_API_KEY valve not configured.")
            _, up_raw, _ = self._http(
                "https://api.assemblyai.com/v2/upload",
                method="POST",
                headers={"Authorization": ak, "Content-Type": "application/octet-stream"},
                body=raw,
                timeout=180,
            )
            upload_url = json.loads(up_raw.decode("utf-8"))["upload_url"]
            job = self._http_json(
                "https://api.assemblyai.com/v2/transcript",
                method="POST",
                headers={"Authorization": ak},
                payload={"audio_url": upload_url, "speech_model": "universal-3-pro", "language_code": language},
                timeout=60,
            )
            tid = job["id"]
            deadline = time.monotonic() + 300
            while job.get("status") not in ("completed", "error"):
                if time.monotonic() > deadline:
                    raise RuntimeError(f"AssemblyAI transcript {tid} timed out.")
                time.sleep(3)
                job = self._http_json(f"https://api.assemblyai.com/v2/transcript/{tid}", headers={"Authorization": ak}, timeout=30)
            if job.get("status") == "error":
                raise RuntimeError(f"AssemblyAI transcript failed: {job.get('error')}")
            _, srt_raw, _ = self._http(f"https://api.assemblyai.com/v2/transcript/{tid}/srt", headers={"Authorization": ak}, timeout=30)
            return job.get("text", ""), json.dumps(job, indent=2).encode("utf-8"), srt_raw

        transcript_text, json_bytes, srt_bytes = await asyncio.to_thread(_work)
        tok = secrets.token_hex(12)
        t_ref, _, t_dl = self._save_output("transcript.txt", transcript_text.encode("utf-8"), tok)
        _, _, j_dl = self._save_output("transcript.json", json_bytes, tok)
        links = f"- [Download transcript.txt]({t_dl}) (`{t_ref}`)\n- [Download transcript.json]({j_dl})"
        if srt_bytes is not None:
            s_ref, _, s_dl = self._save_output("transcript.srt", srt_bytes, tok)
            links += f"\n- [Download transcript.srt]({s_dl}) (`{s_ref}`)"
        return f"**cloud_transcribe_audio** finished (`provider={chosen}`, `source={fname}`)\n\n```text\n{transcript_text}\n```\n\n{links}"

    async def search_stock_media(
        self,
        query: str,
        media_type: str = "photo",
        count: int = 4,
    ) -> str:
        """Search free high-resolution stock photos or videos via Pexels API."""
        pk = (self.valves.pexels_api_key or "").strip()
        if not pk:
            raise RuntimeError("PEXELS_API_KEY valve not configured.")
        mtype = (media_type or "photo").strip().lower()
        per_page = max(1, min(10, int(count)))
        if mtype not in ("photo", "video"):
            raise ValueError(f"media_type must be 'photo' or 'video', got {media_type!r}")

        def _work() -> list[dict[str, Any]]:
            q = urllib.parse.urlencode({"query": query, "per_page": per_page})
            ep = "https://api.pexels.com/v1/search" if mtype == "photo" else "https://api.pexels.com/videos/search"
            res = self._http_json(f"{ep}?{q}", headers={"Authorization": pk, "User-Agent": "AgentHub-Studio/1.0"}, timeout=30)
            out: list[dict[str, Any]] = []
            if mtype == "photo":
                for ph in res.get("photos", []):
                    src = ph.get("src") or {}
                    out.append({
                        "id": ph.get("id"),
                        "photographer": ph.get("photographer"),
                        "alt": ph.get("alt"),
                        "url": src.get("large2x") or src.get("original"),
                        "pexels_page": ph.get("url"),
                    })
            else:
                for vid in res.get("videos", []):
                    files = sorted((vid.get("video_files") or []), key=lambda f: int(f.get("width") or 0), reverse=True)
                    best = next((f for f in files if f.get("link") and int(f.get("width") or 0) <= 1920), files[0] if files else {})
                    out.append({
                        "id": vid.get("id"),
                        "duration": vid.get("duration"),
                        "width": best.get("width"),
                        "height": best.get("height"),
                        "url": best.get("link"),
                        "pexels_page": vid.get("url"),
                    })
            return out

        items = await asyncio.to_thread(_work)
        return json.dumps({"query": query, "media_type": mtype, "results": items}, indent=2)

    async def download_stock_media(
        self,
        url: str,
        filename: str = "stock.jpg",
    ) -> str:
        """Download a stock photo/video from an allowlisted Pexels CDN URL so it gets a local /media-dl/ link and artifact ref."""
        parsed = urllib.parse.urlparse((url or "").strip())
        host = (parsed.hostname or "").lower()
        if parsed.scheme != "https" or not (host == "pexels.com" or host.endswith(".pexels.com")):
            raise ValueError(f"Only https://*.pexels.com URLs are allowed, got {url!r}")
        if not _SAFE_NAME.match(filename) or ".." in filename:
            raise ValueError(f"Unsafe filename {filename!r}")

        def _work() -> bytes:
            _, raw, _ = self._http(parsed.geturl(), headers={"User-Agent": "AgentHub-Studio/1.0"}, timeout=180)
            return raw

        raw = await asyncio.to_thread(_work)
        ref, view_url, dl_url = self._save_output(filename, raw)
        ext = Path(filename).suffix.lower()
        preview = f"![{filename}]({view_url})\n" if ext in (".png", ".jpg", ".jpeg", ".webp") else f"- [View {filename}]({view_url})\n"
        return f"**download_stock_media** saved (`bytes={len(raw)}`)\n\n{preview}- [Download {filename}]({dl_url})\n- ref: `{ref}`"

    async def parse_document_url(self, url: str) -> str:
        """Parse a public PDF or document URL into structured markdown/tables using Reducto."""
        rk = (self.valves.reducto_api_key or "").strip()
        if not rk:
            raise RuntimeError("REDUCTO_API_KEY valve not configured.")
        parsed = urllib.parse.urlparse((url or "").strip())
        if parsed.scheme not in ("https", "http") or not parsed.netloc:
            raise ValueError(f"Valid http(s) URL required, got {url!r}")

        def _work() -> dict[str, Any]:
            return self._http_json(
                "https://platform.reducto.ai/parse",
                method="POST",
                headers={"Authorization": f"Bearer {rk}"},
                payload={"document_url": parsed.geturl()},
                timeout=180,
            )

        res = await asyncio.to_thread(_work)
        chunks = ((res.get("result") or {}).get("chunks") or [])
        text = "\n\n".join(str(c.get("content") or "") for c in chunks[:20] if isinstance(c, dict)).strip()
        ref, _, dl_url = self._save_output("reducto-parse.json", json.dumps(res, indent=2).encode("utf-8"))
        excerpt = text[:4000] + ("\n...(truncated)..." if len(text) > 4000 else "")
        return f"**parse_document_url** finished (`chunks={len(chunks)}`)\n\n{excerpt}\n\n- [Download reducto-parse.json]({dl_url}) (`{ref}`)"
