"""Runs on the throwaway CPU box that `gpu.py prefill media` starts (python:3.12-slim, standard library only).

Streams every file pinned in models.json from Hugging Face straight onto the media weights volume, so a later GPU boot
copies from the volume instead of downloading. The volume is an S3 mount: files are written once, front to back, and
never renamed or rewritten. A `ready-<revision>.json` size manifest is written per repo only after every file arrived;
serve-media-rocm-gfx950.sh trusts a volume copy only when that manifest matches.

Inputs: /tmp/hf.token, /tmp/models.json (uploaded by gpu.py). Prints progress, never the token. The last line is
PREFILL_DONE, preceded by `bad [...]` listing any file that failed.
"""
from __future__ import annotations

import fnmatch
import json
import pathlib
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

VOLUME = pathlib.Path("/mnt/media-weights/weights")
TOKEN_FILE = pathlib.Path("/tmp/hf.token")
MODELS_FILE = pathlib.Path("/tmp/models.json")
WHOLE_REPO_IGNORE = ["*.bin", "*.msgpack", "*.h5", "*.ot"]
REPO_EXTRA_IGNORE = {"Zyphra/ZONOS3-Mini": ["web/*", "gguf/*.gguf", "gguf/edit/*", "autoencoder/heads/full_mr/*"]}


def build_specs(models: dict) -> list[tuple[str, str, str]]:
    """(repo, revision, path) for every pinned file; an empty path means the whole repo."""
    specs: list[tuple[str, str, str]] = []
    for model in models["installed"]:
        if model.get("files"):
            specs += [(f.get("repo", model["repo"]), f.get("revision", model["revision"]), f["path"]) for f in model["files"]]
        else:
            specs.append((model["repo"], model["revision"], ""))
    return list(dict.fromkeys(specs))


def select_files(repo: str, listing: dict[str, int], wanted: list[str]) -> tuple[dict[str, int], list[str]]:
    """Files to fetch from a repo listing ({path: size}) and the pinned paths the listing lacks."""
    if all(wanted):
        missing = [path for path in wanted if path not in listing]
        return {path: listing[path] for path in wanted if path in listing}, missing
    ignore = WHOLE_REPO_IGNORE + REPO_EXTRA_IGNORE.get(repo, [])
    return {name: size for name, size in listing.items() if not any(fnmatch.fnmatch(name, pat) for pat in ignore)}, []


class DropAuthOnNewHost(urllib.request.HTTPRedirectHandler):
    """Hugging Face redirects downloads to a signed CDN URL; the token stays with huggingface.co."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.parse.urlparse(newurl).netloc != urllib.parse.urlparse(req.full_url).netloc:
            new.headers = {k: v for k, v in new.headers.items() if k.lower() != "authorization"}
        return new


def main() -> int:
    token = TOKEN_FILE.read_text().strip()
    opener = urllib.request.build_opener(DropAuthOnNewHost)

    def get(url: str):
        return opener.open(urllib.request.Request(url, headers={"Authorization": "Bearer " + token}), timeout=120)

    specs = build_specs(json.loads(MODELS_FILE.read_text()))
    repos: dict[tuple[str, str], list[str]] = {}
    for repo, rev, rel in specs:
        repos.setdefault((repo, rev), []).append(rel)
    jobs: list[tuple[str, str, str, int]] = []
    wants: dict[tuple[str, str], dict[str, int]] = {}
    for (repo, rev), rels in repos.items():
        tree: list[dict] = []
        url: str | None = f"https://huggingface.co/api/models/{repo}/tree/{rev}?recursive=true&limit=1000"
        while url:
            resp = get(url)
            tree += json.load(resp)
            link = resp.headers.get("Link") or ""
            url = link.split(";")[0].strip(" <>") if 'rel="next"' in link else None
        listing = {f["path"]: f["size"] for f in tree if f["type"] == "file"}
        want, missing = select_files(repo, listing, rels)
        if missing:
            print("MISSING", repo, rev, missing, flush=True)
        wants[(repo, rev)] = want
        jobs += [(repo, rev, name, size) for name, size in want.items()]
    print(len(jobs), "files", round(sum(j[3] for j in jobs) / 1e9, 1), "GB", flush=True)

    def one(job: tuple[str, str, str, int]) -> bool:
        repo, rev, name, size = job
        dst = VOLUME / repo / name
        if dst.is_file() and dst.stat().st_size == size:
            return True
        for _attempt in range(4):
            try:
                dst.parent.mkdir(parents=True, exist_ok=True)
                if dst.exists():
                    dst.unlink()
                started = time.time()
                with get(f"https://huggingface.co/{repo}/resolve/{rev}/{urllib.parse.quote(name)}") as resp, open(dst, "wb") as out:
                    while chunk := resp.read(8 << 20):
                        out.write(chunk)
                if dst.stat().st_size == size:
                    if size > 5e8:
                        print(f"{size / 1e9:.1f} GB {time.time() - started:.0f}s {repo}/{name}", flush=True)
                    return True
            except Exception as exc:
                print("retry", repo, name, type(exc).__name__, str(exc)[:100], flush=True)
                time.sleep(5)
        return False

    with ThreadPoolExecutor(8) as pool:
        done = dict(zip([(j[0], j[1], j[2]) for j in jobs], pool.map(one, jobs)))
    for (repo, rev), want in wants.items():
        ready = VOLUME / repo / f"ready-{rev}.json"
        if want and all(done[(repo, rev, name)] for name in want) and not ready.exists():
            ready.write_text(json.dumps(want))
    print("bad", [key for key, ok in done.items() if not ok], flush=True)
    print("PREFILL_DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
