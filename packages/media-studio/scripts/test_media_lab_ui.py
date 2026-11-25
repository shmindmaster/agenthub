"""Offline tests for media_lab_ui.py against a fake gateway and a fake gpu.py (no network, no GPU, no paid call)."""
import base64, hashlib, http.client, json, os, struct, sys, tempfile, threading, time, unittest, zlib
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import daytona_media_client as mc
import media_lab_ui as ui

KEY = "sk-test-0123456789abcdef-SECRETKEY"


def png(w=8, h=8) -> bytes:
    raw = b"".join(b"\x00" + bytes(v for x in range(w) for v in (x * 30 % 256, y * 30 % 256, 128)) for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


def model(id, jobs, commercial):
    return {"id": id, "jobs": jobs, "commercial": commercial}


REGISTRY = {
    "authorizationProfiles": {
        "commercial": {"defaults": {"image": "qwen-image-2512", "video": "wan2.2-i2v-a14b", "talk": "wan2.2-s2v-14b", "music": "ace-step-1.5-turbo",
                                    "tts": "qwen3-tts-1.7b-customvoice", "transcribe": "sov-transcribe-1"}},
        "research": {"defaults": {"image": "qwen-image-2.1-omni", "image_edit": "qwen-image-2.1-omni", "video": "ltx-2.5-uncensored", "talk": "ltx-2.5-uncensored",
                                  "music": "ace-step-1.5-turbo", "tts": "lfm3-omni-2b-heretic", "transcribe": "lfm3-omni-2b-heretic"}}},
    "installed": [model("qwen-image-2.1-omni", ["image", "image_edit"], False), model("ltx-2.5-uncensored", ["video", "talk"], False),
                  model("lfm3-omni-2b-heretic", ["tts", "transcribe"], False), model("qwen-image-2512", ["image"], True), model("z-image-turbo", ["image"], True),
                  model("wan2.2-i2v-a14b", ["video"], True), model("wan2.2-s2v-14b", ["talk"], True), model("ace-step-1.5-turbo", ["music"], True),
                  model("qwen3-tts-1.7b-customvoice", ["tts", "speakers"], True), model("sov-transcribe-1", ["transcribe"], True),
                  model("whisper-large-v3-turbo", ["transcribe"], True)]}
OUTPUT_NAME = {"image": "image.png", "image_edit": "edit.png", "video": "video.mp4", "talk": "talk.mp4", "tts": "tts-ryan.wav", "music": "music.wav", "transcribe": "transcript.json"}


class FakeGateway:
    """Just enough of the media gateway: auth, /v1/info, the job API and files. `assets` maps a suffix to output bytes."""

    def __init__(self):
        self.down, self.posted, self.deleted, self.jobs = False, [], [], {}
        self.release = threading.Event()
        self.release.set()
        self.assets = {".png": png(), ".mp4": b"fake-mp4-bytes", ".wav": b"RIFF-fake-wav", ".json": json.dumps({"text": "hello from the lab"}).encode()}
        gw = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def send(self, code, obj=None, raw=None):
                body = raw if raw is not None else json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def authed(self):
                if self.headers.get("Authorization") != f"Bearer {KEY}":
                    self.send(401, {"error": "unauthorized"})
                    return False
                return True

            def do_GET(self):
                if not self.authed():
                    return
                if gw.down:
                    return self.send(503, {"error": "box is down"})
                parts = self.path.strip("/").split("/")
                if self.path == "/v1/info":
                    return self.send(200, {"gpu": "fake MI355X", "queue": 0, "models": REGISTRY, "missing_weights": {}})
                if parts[:2] == ["v1", "jobs"] and len(parts) == 3 and parts[2] in gw.jobs:
                    j = gw.jobs[parts[2]]
                    j["polls"] += 1
                    if j["polls"] < 2 or not gw.release.is_set():
                        return self.send(200, {"id": j["id"], "state": "running", "progress": "sampling"})
                    if "FAIL" in str(j["params"].get("prompt")):
                        return self.send(200, {"id": j["id"], "state": "error", "error": f"worker crashed; header was Authorization: Bearer {KEY}"})
                    return self.send(200, {k: j[k] for k in ("id", "state", "model", "outputs", "seconds")})
                if parts[:2] == ["v1", "files"] and len(parts) == 4 and parts[2] in gw.jobs:
                    return self.send(200, raw=gw.jobs[parts[2]]["data"][parts[3]])
                self.send(404, {"error": "not found"})

            def do_POST(self):
                if not self.authed():
                    return
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                gw.posted.append(body)
                if "BADREQ" in str(body["params"].get("prompt")):
                    return self.send(400, {"error": f"rejected, key {KEY} echoed"})
                jid = f"job-{len(gw.posted):03d}"
                name = OUTPUT_NAME[body["type"]]
                data = gw.assets[Path(name).suffix]
                gw.jobs[jid] = {"id": jid, "state": "done", "model": body["params"].get("model"), "params": body["params"], "polls": 0, "seconds": 1.5,
                                "outputs": [{"name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}], "data": {name: data}}
                self.send(201, {"id": jid, "state": "queued"})

            def do_DELETE(self):
                gw.deleted.append(self.path.rsplit("/", 1)[-1])
                self.send(200, {"deleted": True})

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


FAKE_GPU = '''import json, pathlib, sys
here = pathlib.Path(__file__).parent
cfg = json.loads((here / "cfg.json").read_text())
with (here / "argv.log").open("a") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\\n")
if sys.argv[1] == "status":
    print(cfg["status"])
else:
    print("Authorization: Bearer " + cfg["key"], "and bare", cfg["key"], flush=True)
    print("working on", sys.argv[1])
    sys.exit(cfg.get("rc", 0))
'''


def status_text(boxes, n=None, cap=2):
    rows = "".join(f"  {i}-id {name} STARTED gpu={gpu} spot=True destroy_at={when}\n" for i, (name, gpu, when) in enumerate(boxes))
    return f"state_file x\ngpu_instances {len(boxes) if n is None else n}/{cap}\n{rows}gateway_models unavailable (offline)"


class Stack:
    """A fake gateway, a fake gpu.py and a running Lab server on a free loopback port."""

    def __init__(self, status=None, idle_minutes=30, key=KEY):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.gw = FakeGateway()
        self.gpu_dir = root / "gpu"
        self.gpu_dir.mkdir()
        (self.gpu_dir / "gpu.py").write_text(FAKE_GPU, encoding="utf-8")
        self.set_gpu(status if status is not None else status_text([]))
        self.env = mock.patch.dict(os.environ, {"AGENTHUB_INFERENCE_KEY": key})
        self.env.start()
        self.args = SimpleNamespace(port=0, gateway_url=self.gw.url, out=str(root / "out"), gpu_py=str(self.gpu_dir / "gpu.py"), idle_minutes=idle_minutes, poll=0.02)
        self.httpd, self.lab = ui.make_server(self.args)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.seen = []
        self.out = Path(self.args.out)

    def set_gpu(self, status, rc=0):
        (self.gpu_dir / "cfg.json").write_text(json.dumps({"status": status, "key": KEY, "rc": rc}), encoding="utf-8")

    def argv(self, status=False):
        """gpu.py calls so far; the `status` reads that follow every box command are left out unless asked for."""
        log = self.gpu_dir / "argv.log"
        rows = log.read_text(encoding="utf-8").split("\n")[:-1] if log.exists() else []
        return rows if status else [r for r in rows if r != "status"]

    def call(self, method, path, body=None, cookie=True, origin=True, host=None, extra=None, timeout=30):
        c = http.client.HTTPConnection("127.0.0.1", self.lab.port, timeout=timeout)
        port = self.lab.port
        h = {"Host": host or f"127.0.0.1:{port}", **(extra or {})}
        if cookie:
            h["Cookie"] = f"medialab={self.lab.token}"
        if origin and method == "POST":
            h["Origin"] = f"http://127.0.0.1:{port}"
        data = json.dumps(body).encode() if body is not None else None
        if data:
            h["Content-Type"] = "application/json"
        c.request(method, path, body=data, headers=h)
        r = c.getresponse()
        raw = r.read()
        self.seen.append(raw + str(r.getheaders()).encode())
        return r.status, dict(r.getheaders()), raw

    def api(self, method, path, body=None, **kw):
        code, _, raw = self.call(method, path, body, **kw)
        return code, json.loads(raw) if raw[:1] in (b"{", b"[") else raw

    def wait(self, what, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            v = what()
            if v:
                return v
            time.sleep(0.05)
        raise AssertionError("timed out waiting")

    def job(self, mode, params=None, inputs=None, profile="commercial", model=None, ok=True):
        code, r = self.api("POST", "/api/jobs", {"mode": mode, "profile": profile, "model": model, "params": params or {}, "inputs": inputs or {}})
        if not ok:
            return code, r
        self.assertion = code
        j = self.lab.jobs[r["id"]]
        self.wait(lambda: j["state"] in ("done", "error"))
        return j

    def close(self):
        self.lab.stop.set()
        self.httpd.shutdown()
        self.httpd.server_close()
        self.gw.close()
        self.env.stop()
        self.wait_runner()
        try:
            self.tmp.cleanup()
        except OSError:
            pass

    def wait_runner(self):
        end = time.time() + 10
        while self.lab.runner and self.lab.runner["running"] and time.time() < end:
            time.sleep(0.05)


class Base(unittest.TestCase):
    def setUp(self):
        mc.RETRY_SLEEP_SECONDS, self._sleep = 0, mc.RETRY_SLEEP_SECONDS
        self.s = None

    def stack(self, **kw):
        self.s = Stack(**kw)
        self.s.lab.refresh(gpu=False)
        self.addCleanup(self.s.close)
        return self.s

    def tearDown(self):
        mc.RETRY_SLEEP_SECONDS = self._sleep


class Access(Base):
    def test_every_route_refuses_without_the_session(self):
        s = self.stack()
        for path in ("/", "/api/state", "/api/files/job-001/image.png"):
            self.assertEqual(s.call("GET", path, cookie=False)[0], 403, path)
        self.assertEqual(s.call("POST", "/api/jobs", {}, cookie=False)[0], 403)
        self.assertEqual(s.call("GET", "/api/state", extra={"Cookie": "medialab=wrong"}, cookie=False)[0], 403)

    def test_launch_url_sets_a_strict_http_only_cookie_once(self):
        s = self.stack()
        code, h, _ = s.call("GET", f"/?t={s.lab.token}", cookie=False)
        self.assertEqual((code, h["Location"]), (302, "/"))
        self.assertIn("HttpOnly", h["Set-Cookie"])
        self.assertIn("SameSite=Strict", h["Set-Cookie"])
        self.assertEqual(s.call("GET", "/?t=nope", cookie=False)[0], 403)
        code, _, page = s.call("GET", "/")
        self.assertEqual(code, 200)
        self.assertIn(b"<title>AI Media Lab</title>", page)

    def test_host_and_origin_are_checked(self):
        s = self.stack()
        for host in ("evil.example", f"evil.example:{s.lab.port}", "127.0.0.1", "127.0.0.1:1"):
            self.assertEqual(s.call("GET", "/api/state", host=host)[0], 403, host)
        self.assertEqual(s.call("GET", "/api/state", host=f"localhost:{s.lab.port}")[0], 200)
        self.assertEqual(s.call("GET", "/api/state", extra={"Origin": "http://evil.example"})[0], 403)
        self.assertEqual(s.call("POST", "/api/jobs", {}, origin=False)[0], 403)
        self.assertEqual(s.call("POST", "/api/jobs", {}, extra={"Origin": "http://evil.example"}, origin=False)[0], 403)
        self.assertEqual(s.call("POST", "/api/box/stop", {"confirm": True}, extra={"Origin": "http://127.0.0.1:9"}, origin=False)[0], 403)
        self.assertEqual(s.argv(), [])

    def test_binds_loopback_only(self):
        self.assertEqual(self.stack().httpd.server_address[0], "127.0.0.1")

    def test_path_traversal_is_refused(self):
        s = self.stack()
        (s.out.parent / "secret.txt").write_text("TOPSECRETCONTENT")
        s.job("image", {"prompt": "x"})
        for path in ("/api/files/..%2f..%2f/secret.txt", "/api/files/job-001/..%5csecret.txt", "/api/files/%2e%2e/image.png", "/api/files/job-001/%2e%2e%2fsecret.txt"):
            code, _, raw = s.call("GET", path)
            self.assertIn(code, (400, 404), path)
            self.assertNotIn(b"TOPSECRETCONTENT", raw)
        for ref in ({"job": "../x", "name": "y.png"}, {"job": "job-001", "name": "../../secret.txt"}, {"job": "job-001", "name": "/etc/passwd"}):
            code, r = s.api("POST", "/api/jobs", {"mode": "video", "profile": "commercial", "params": {"prompt": "p"}, "inputs": {"input": ref}})
            self.assertEqual(code, 400, ref)
        self.assertEqual(s.api("POST", "/api/open", {"job": "job-001", "name": "../x"})[0], 400)


class Secrets(Base):
    def test_the_key_never_reaches_a_response_or_a_log(self):
        s = self.stack(status=status_text([]))
        out = []
        with mock.patch("sys.stdout.write", side_effect=out.append), mock.patch("sys.stderr.write", side_effect=out.append):
            j = s.job("image", {"prompt": "FAIL this"})
            self.assertEqual(j["state"], "error")
            self.assertIn("worker crashed", j["error"])
            code, r = s.job("image", {"prompt": "BADREQ"}, ok=False)
            self.assertEqual(code, 201)
            s.wait(lambda: [x for x in s.lab.jobs.values() if "echoed" in x["error"]])
            s.api("POST", "/api/box/start", {"confirm": True})
            s.wait_runner()
            state = s.api("GET", "/api/state")[1]
        log = "\n".join(state["box"]["log"])
        self.assertIn("Authorization: Bearer ****", log)
        self.assertIn("****" + KEY[-4:], log)
        self.assertNotIn("GET /api", "".join(out))
        self.assertNotIn(KEY, "".join(out))
        blob = b"".join(s.seen) + json.dumps(state).encode()
        self.assertNotIn(KEY.encode(), blob)
        self.assertNotIn(KEY[:-4].encode(), blob)
        self.assertNotIn(b"sk-test", blob)

    def test_a_missing_key_is_reported_plainly(self):
        with mock.patch.object(mc, "_secret_file_candidates", return_value=[]):
            s = Stack(key="")
        self.addCleanup(s.close)
        s.lab.refresh(gpu=False)
        state = s.api("GET", "/api/state")[1]
        self.assertIn("Missing AGENTHUB_INFERENCE_KEY", state["gateway_error"])
        self.assertEqual(s.job("image", {"prompt": "x"}, ok=False)[0], 409)


class Modes(Base):
    def test_each_mode_sends_its_payload_and_saves_a_verified_output(self):
        s = self.stack()
        up = base64.b64encode(png()).decode()
        wav = base64.b64encode(b"RIFFwav").decode()
        cases = [
            ("image", {"prompt": "a boat", "width": "512", "height": "768", "steps": "20", "seed": "7", "negative": "blur"}, {}, "commercial",
             {"prompt": "a boat", "width": 512, "height": 768, "steps": 20, "seed": 7, "negative": "blur", "model": "qwen-image-2512"}),
            ("image_edit", {"prompt": "make it blue", "seed": "3"}, {"input": {"name": "in me.png", "b64": up}}, "research",
             {"prompt": "make it blue", "seed": 3, "input_b64": up, "input_name": "in_me.png", "model": "qwen-image-2.1-omni"}),
            ("video", {"prompt": "drift", "width": "640", "height": "640", "frames": "33"}, {"input": {"name": "s.png", "b64": up}}, "commercial",
             {"prompt": "drift", "width": 640, "height": 640, "frames": 33, "input_b64": up, "input_name": "s.png", "model": "wan2.2-i2v-a14b"}),
            ("talk", {"prompt": "speaks", "subject": "synthetic", "width": "512", "height": "512"}, {"input": {"name": "p.png", "b64": up}, "audio": {"name": "a.wav", "b64": wav}}, "commercial",
             {"prompt": "speaks", "subject": "synthetic", "width": 512, "height": 512, "input_b64": up, "input_name": "p.png", "audio_b64": wav, "audio_name": "a.wav", "model": "wan2.2-s2v-14b"}),
            ("tts", {"text": "Hello", "speaker": "ryan", "language": "English", "instruct": ""}, {}, "commercial",
             {"text": "Hello", "speaker": "ryan", "language": "English", "model": "qwen3-tts-1.7b-customvoice"}),
            ("transcribe", {"language": "English"}, {"input": {"name": "a.wav", "b64": wav}}, "commercial",
             {"language": "English", "input_b64": wav, "input_name": "a.wav", "model": "sov-transcribe-1"}),
            ("music", {"tags": "calm piano", "seconds": "10", "bpm": "90", "lyrics": ""}, {}, "commercial",
             {"tags": "calm piano", "seconds": 10, "bpm": 90, "model": "ace-step-1.5-turbo"}),
        ]
        for mode, params, inputs, profile, expect in cases:
            j = s.job(mode, params, inputs, profile)
            self.assertEqual(j["state"], "done", (mode, j["error"]))
            sent = s.gw.posted[-1]
            self.assertEqual((sent["type"], sent["authorization_profile"], sent["params"]), (mode, profile, expect), mode)
            folder = s.out / time.strftime("%Y-%m-%d") / j["dir"]
            meta = json.loads((folder / f"{j['dir']}.json").read_text(encoding="utf-8"))
            out = meta["files"][0]
            self.assertEqual(hashlib.sha256((folder / out["name"]).read_bytes()).hexdigest(), out["sha256"])
            self.assertEqual((meta["mode"], meta["model"], meta["profile"]), (mode, expect["model"], profile))
            self.assertEqual(meta["prompt"], params.get("prompt") or params.get("text") or params.get("tags") or "")
            self.assertFalse(any(k.endswith("_b64") for k in meta["params"]), "inputs must not be stored in the JSON")
        self.assertEqual(sorted(s.gw.deleted), sorted(s.gw.jobs))
        self.assertEqual(len(list(s.out.glob("*/*/*.part"))), 0)

    def test_research_only_fields_are_dropped_under_commercial_and_kept_under_research(self):
        s = self.stack()
        ref = {"name": "r.wav", "b64": base64.b64encode(b"RIFFref").decode()}
        s.job("tts", {"text": "hi", "speaker": "ryan", "subject": "consented"}, {"ref_audio": ref}, "commercial")
        self.assertNotIn("ref_audio_b64", s.gw.posted[-1]["params"])
        self.assertNotIn("subject", s.gw.posted[-1]["params"])
        s.job("tts", {"text": "hi", "subject": "consented"}, {"ref_audio": ref}, "research")
        p = s.gw.posted[-1]["params"]
        self.assertEqual((p["subject"], p["ref_audio_name"], p["model"]), ("consented", "r.wav", "lfm3-omni-2b-heretic"))

    def test_commercial_image_edit_is_disabled_and_nothing_is_sent(self):
        s = self.stack()
        modes = s.api("GET", "/api/state")[1]["modes"]
        self.assertIsNone(modes["image_edit"]["commercial"]["default"])
        self.assertEqual(modes["image_edit"]["research"]["models"], ["qwen-image-2.1-omni"])
        self.assertEqual(modes["image"]["commercial"]["models"][0], "qwen-image-2512")
        self.assertEqual(sorted(modes["image"]["commercial"]["models"]), ["qwen-image-2512", "z-image-turbo"])
        self.assertNotIn("qwen-image-2.1-omni", modes["image"]["commercial"]["models"])
        code, r = s.job("image_edit", {"prompt": "x"}, {"input": {"name": "a.png", "b64": base64.b64encode(png()).decode()}}, ok=False)
        self.assertEqual(code, 409)
        self.assertIn("no commercial model for image_edit", r["error"])
        self.assertEqual(s.gw.posted, [])

    def test_bad_input_is_refused_before_anything_is_sent(self):
        s = self.stack()
        good = {"input": {"name": "a.png", "b64": base64.b64encode(png()).decode()}}
        for mode, params, inputs, msg in (("image", {}, {}, "Prompt is required"), ("video", {"prompt": "x"}, {}, "Start image is required"),
                                          ("image", {"prompt": "x", "steps": "many"}, {}, "whole number"), ("talk", {"prompt": "x", "subject": "me"}, {**good, "audio": {"name": "a.wav", "b64": "UklGRg=="}}, "Subject must be"),
                                          ("video", {"prompt": "x"}, {"input": {"name": "a.png", "b64": "!!not base64"}}, ""), ("nope", {}, {}, "unknown mode")):
            code, r = s.job(mode, params, inputs, ok=False)
            self.assertEqual(code, 400, (mode, r))
            self.assertIn(msg, r["error"])
        self.assertEqual(s.job("image", {"prompt": "x"}, model="not-a-model", ok=False)[0], 400)
        self.assertEqual(s.gw.posted, [])

    def test_an_output_is_reused_as_input_by_job_and_name(self):
        s = self.stack()
        first = s.job("image", {"prompt": "a boat"})
        ref = {"job": first["dir"], "name": "image.png"}
        s.job("video", {"prompt": "drift"}, {"input": ref})
        self.assertEqual(base64.b64decode(s.gw.posted[-1]["params"]["input_b64"]), s.gw.assets[".png"])
        self.assertEqual(s.gw.posted[-1]["params"]["input_name"], "image.png")
        s.job("image_edit", {"prompt": "blue"}, {"input": ref}, "research")
        self.assertEqual(s.gw.posted[-1]["type"], "image_edit")
        tts = s.job("tts", {"text": "hello"})
        s.job("transcribe", {}, {"input": {"job": tts["dir"], "name": "tts-ryan.wav"}})
        self.assertEqual(base64.b64decode(s.gw.posted[-1]["params"]["input_b64"]), s.gw.assets[".wav"])
        self.assertEqual(s.api("POST", "/api/jobs", {"mode": "video", "profile": "commercial", "params": {"prompt": "p"}, "inputs": {"input": {"job": "job-999", "name": "x.png"}}})[0], 404)

    def test_files_are_served_with_ranges_and_history_survives_a_restart(self):
        s = self.stack()
        j = s.job("image", {"prompt": "a boat"})
        code, h, raw = s.call("GET", f"/api/files/{j['dir']}/image.png")
        self.assertEqual((code, h["Content-Type"], raw), (200, "image/png", s.gw.assets[".png"]))
        code, h, raw = s.call("GET", f"/api/files/{j['dir']}/image.png", extra={"Range": "bytes=2-5"})
        self.assertEqual((code, raw, h["Content-Range"]), (206, s.gw.assets[".png"][2:6], f"bytes 2-5/{len(s.gw.assets['.png'])}"))
        self.assertIn("attachment", s.call("GET", f"/api/files/{j['dir']}/image.png?dl=1")[1]["Content-Disposition"])
        again = ui.Lab(s.args)
        self.assertEqual([(x["id"], x["mode"], x["state"]) for x in again.jobs.values()], [(j["dir"], "image", "done")])

    def test_open_folder_uses_the_opener_for_a_saved_job_only(self):
        s = self.stack()
        j = s.job("image", {"prompt": "a boat"})
        s.lab.opener = mock.Mock()
        self.assertEqual(s.api("POST", "/api/open", {"job": j["dir"], "name": "image.png"})[0], 200)
        s.lab.opener.assert_called_once_with(str(s.out / time.strftime("%Y-%m-%d") / j["dir"]))


class Box(Base):
    def soon(self, minutes):
        return (datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat()

    def box(self, s):
        return s.api("GET", "/api/state")[1]["box"]

    def test_states_off_ready_lost_and_starting(self):
        s = self.stack()
        s.gw.down = True
        s.lab.status, s.lab.was_ready = None, False
        s.lab.refresh()
        self.assertEqual(self.box(s)["state"], "off")
        s.gw.down = False
        s.set_gpu(status_text([("agenthub-media", "MI355X", self.soon(90))]))
        s.lab.refresh()
        b = self.box(s)
        self.assertEqual((b["state"], b["queue"], b["usd_per_hour"] > 0), ("ready", 0, True))
        self.assertIn(b["left_min"], (89, 90))
        s.gw.down = True
        s.lab.refresh()
        self.assertEqual(self.box(s)["state"], "lost")
        s.set_gpu(status_text([]))
        s.lab.refresh()
        self.assertEqual(self.box(s)["state"], "lost")
        s.lab.was_ready = False
        s.set_gpu(status_text([("agenthub-media", "MI355X", self.soon(90))]))
        s.lab.refresh()
        self.assertEqual(self.box(s)["state"], "starting")

    def test_start_refuses_when_two_of_two_gpus_run_and_names_them(self):
        s = self.stack(status=status_text([("agenthub-engineering", "MI355X", "None"), ("qwen38-turbo-q6k", "H200", "None")]))
        code, r = s.api("POST", "/api/box/start", {"confirm": True})
        self.assertEqual(code, 409)
        for text in ("2/2", "agenthub-engineering", "qwen38-turbo-q6k"):
            self.assertIn(text, r["error"])
        self.assertEqual(s.argv(status=True), ["status"])
        self.assertEqual(s.argv(), [])

    def test_start_runs_up_media_then_caddy_media_and_nothing_else(self):
        s = self.stack(status=status_text([("qwen38-turbo-q6k", "H200", "None")]))
        spy = mock.Mock(wraps=ui.subprocess.Popen)
        with mock.patch.object(ui.subprocess, "Popen", spy):
            self.assertEqual(s.api("POST", "/api/box/start", {"confirm": True})[0], 202)
            s.wait_runner()
        self.assertEqual(s.argv(), ["up media --gpu MI355X --ttl 120", "caddy-media"])
        for call in spy.call_args_list:
            self.assertIsInstance(call.args[0], list)
            self.assertFalse(call.kwargs.get("shell"))
            self.assertEqual(call.kwargs["creationflags"], ui.NOWIN)
        self.assertEqual(s.lab.runner["result"], "ok")

    def test_a_failed_up_skips_caddy_and_shows_the_error(self):
        s = self.stack()
        s.set_gpu(status_text([]), rc=3)
        s.api("POST", "/api/box/start", {"confirm": True})
        s.wait_runner()
        self.assertEqual(s.argv(), ["up media --gpu MI355X --ttl 120"])
        b = self.box(s)
        self.assertEqual(b["result"], "failed")
        self.assertIn("exit code 3", b["log"])

    def test_start_and_stop_need_confirmation_and_stop_only_touches_media(self):
        s = self.stack(status=status_text([("agenthub-media", "MI355X", self.soon(60))]))
        for action in ("start", "stop"):
            self.assertEqual(s.api("POST", f"/api/box/{action}", {})[0], 400)
            self.assertEqual(s.api("POST", f"/api/box/{action}", {"confirm": "yes"})[0], 400)
        self.assertEqual(s.argv(), [])
        self.assertEqual(s.api("POST", "/api/box/start", {"confirm": True})[0], 409)
        s.argv()
        s.gw.down = True
        self.assertEqual(s.api("POST", "/api/box/stop", {"confirm": True})[0], 202)
        s.wait_runner()
        self.assertEqual(s.argv()[-1], "down media")
        self.assertEqual(s.api("POST", "/api/box/reboot", {"confirm": True})[0], 404)
        self.assertFalse(s.lab.was_ready)

    def test_extend_adds_sixty_minutes_to_the_time_left_and_never_past_the_cap(self):
        s = self.stack(status=status_text([("agenthub-media", "MI355X", self.soon(30))]))
        self.assertEqual(s.api("POST", "/api/box/extend", {})[0], 202)
        s.wait_runner()
        self.assertIn(s.argv()[-1], ("extend media 90", "extend media 91"))
        s.set_gpu(status_text([("agenthub-media", "MI355X", self.soon(470))]))
        s.api("POST", "/api/box/extend", {})
        s.wait_runner()
        self.assertEqual(s.argv()[-1], "extend media 480")
        s.set_gpu(status_text([]))
        self.assertEqual(s.api("POST", "/api/box/extend", {})[0], 409)

    def test_only_one_box_command_runs_at_a_time(self):
        s = self.stack()
        s.lab.runner = {"name": "start", "running": True, "result": ""}
        self.assertEqual(s.api("POST", "/api/box/stop", {"confirm": True})[0], 409)
        s.lab.runner["running"] = False

    def test_price_comes_from_the_catalog_when_it_has_one(self):
        s = self.stack()
        self.assertEqual(s.lab.usd, ui.APPROX_USD_PER_HOUR)
        (s.gpu_dir / "catalog.json").write_text(json.dumps({"policy": {"approxHourlyUsd": 4.5}, "roles": {"media": {"sandboxName": "m1"}}}), encoding="utf-8")
        again = ui.Lab(s.args)
        self.assertEqual((again.usd, again.sandbox), (4.5, "m1"))

    def test_shortcut_is_created_windowless_and_removed(self):
        with tempfile.TemporaryDirectory() as td:
            lnk = Path(td) / "Programs" / "AI Media Lab.lnk"
            with mock.patch.object(ui, "SHORTCUT", lnk), mock.patch.object(ui.subprocess, "run") as run:
                ui.install_shortcut(True)
            argv, kw = run.call_args.args[0], run.call_args.kwargs
            self.assertEqual((argv[0], kw["creationflags"], kw.get("shell")), ("powershell.exe", ui.NOWIN, None))
            self.assertTrue(kw["env"]["ML_EXE"].lower().endswith("pythonw.exe"))
            self.assertTrue(kw["env"]["ML_ARGS"].endswith("media_lab_ui.py\" --open"))
            lnk.write_bytes(b"x")
            with mock.patch.object(ui, "SHORTCUT", lnk):
                ui.install_shortcut(False)
            self.assertFalse(lnk.exists())


class Idle(Base):
    def serve(self, s, idle_s):
        ui.start_threads(s.httpd, s.lab, idle_s)

    def test_exits_after_the_idle_time_with_no_request(self):
        s = self.stack(idle_minutes=0.01)
        self.serve(s, 0.5)
        s.thread.join(8)
        self.assertFalse(s.thread.is_alive())

    def test_requests_and_running_jobs_keep_it_alive(self):
        s = self.stack()
        s.gw.release.clear()
        self.serve(s, 0.6)
        code, r = s.job("image", {"prompt": "slow"}, ok=False)
        self.assertEqual(code, 201)
        s.wait(lambda: s.lab.jobs[r["id"]]["state"] == "running")
        time.sleep(1.8)
        self.assertTrue(s.thread.is_alive(), "a running job must keep the server up")
        s.gw.release.set()
        s.wait(lambda: s.lab.jobs[r["id"]]["state"] == "done")
        s.thread.join(8)
        self.assertFalse(s.thread.is_alive())

    def test_requests_without_the_session_do_not_count_as_activity(self):
        s = self.stack()
        self.serve(s, 0.8)
        end = time.time() + 6
        while s.thread.is_alive() and time.time() < end:
            try:
                s.call("GET", "/api/state", cookie=False, timeout=1)
            except OSError:  # includes the timeout of a request that landed after the server stopped
                break
            time.sleep(0.1)
        self.assertFalse(s.thread.is_alive())


class Parsing(unittest.TestCase):
    def test_status_and_minutes_left(self):
        st = ui.parse_status(status_text([("a", "MI355X", "2026-11-25T20:00:00Z"), ("b", "H200", "None")]))
        self.assertEqual((st["n"], st["max"], [b["name"] for b in st["boxes"]]), (2, 2, ["a", "b"]))
        self.assertFalse(ui.parse_status("Traceback: no key")["ok"])
        self.assertIsNone(ui.minutes_left("None"))
        self.assertEqual(ui.minutes_left("2000-01-01 00:00:00+00:00"), 0)


if __name__ == "__main__":
    unittest.main()
