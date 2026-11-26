#Requires -Version 7
<#
.SYNOPSIS
  Tests for the unified Daytona inference gateway, GPU lifecycle helper,
  and additive multi-host inference provider rollout.
#>
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$specPath = Join-Path $repoRoot 'registry' 'inference-providers.json'
$catalogPath = Join-Path $repoRoot 'scripts' 'daytona-inference' 'catalog.json'
$syncScript = Join-Path $repoRoot 'scripts' 'Sync-InferenceProviders.ps1'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

# 1. Validate canonical registry & catalog JSON + no embedded secrets/PII
$specRaw = Get-Content -LiteralPath $specPath -Raw -Encoding UTF8
Assert-True ($specRaw -notmatch 'sk-[A-Za-z0-9_-]{12,}|73\.166\.30\.102|0075feb8|11930d76') 'inference-providers.json must not contain secrets, owner IP, sandbox ID, or org ID'
$spec = $specRaw | ConvertFrom-Json
Assert-True ($spec.provider.id -eq 'agenthub-daytona') 'provider id must be agenthub-daytona'
Assert-True ($spec.provider.baseUrl -eq 'https://inference.shtrial.com/v1') 'baseUrl must be https://inference.shtrial.com/v1'
Assert-True (-not $spec.provider.default) 'provider.default must be false'
Assert-True ($spec.provider.preserveExistingDefaults) 'preserveExistingDefaults must be true'
$aliases = @($spec.models | ForEach-Object id)
foreach ($expected in @('qwen3.8-27b-unc-q8', 'inkling2-min-26b-unc-q8-128k')) {
    Assert-True ($aliases -contains $expected) "Missing canonical alias $expected"
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($catalog.policy.maxGpuInstancesTotal -eq 2) 'maxGpuInstancesTotal must be 2'
Assert-True ($catalog.policy.spotOnly -eq $true) 'spotOnly must be true'
Assert-True ($catalog.policy.modelHostingAuthorization.retainedVolumes -contains 'llm-models') 'llm-models must be a retained volume'
Assert-True ($catalog.policy.mediaVolumeName -eq 'agenthub-media-weights') 'mediaVolumeName must be agenthub-media-weights'
Assert-True ($catalog.policy.mediaMountPath -eq '/mnt/media-weights') 'mediaMountPath must be /mnt/media-weights'
Assert-True ($catalog.policy.gatewayMediaUrl -eq 'https://inference.shtrial.com/v1/media') 'gatewayMediaUrl mismatch'
Assert-True ($catalog.roles.specialist.profiles.H200.snapshotName -eq 'agenthub-vllm-cuda-0-24-0-h200') 'H200 specialist snapshotName mismatch'
Assert-True ($catalog.roles.flagship.profiles.H200.snapshotName -eq 'agenthub-llama-cuda-h200') 'H200 flagship snapshotName mismatch'
Assert-True ($catalog.roles.engineering.engine -eq 'dual') 'engineering engine must be dual'
# 8003 since 2026-11-26: that is the port the live gateway alias is registered on. It must be the
# port gpu.py builds the preview link from, or `up` registers a backend nothing listens on.
Assert-True ($catalog.roles.engineering.port -eq 8003 -and $catalog.roles.engineering.flagshipPort -eq 8002) 'engineering ports must be 8003 and 8002'
Assert-True ($catalog.roles.engineering.profiles.MI355X.quantization -eq 'BF16+Q8_0') 'engineering MI355X quantization must record a BF16 primary and a Q8_0 flagship'
Assert-True ($catalog.roles.engineering.toolCallParser -eq 'qwen3_coder' -and $catalog.roles.engineering.reasoningParser -eq 'qwen3') 'engineering must record the vLLM tool-call and reasoning parsers that make agent tool calls work'
Assert-True ($catalog.roles.engineering.profiles.MI355X.maxModelLen -eq 262144 -and $catalog.roles.engineering.profiles.MI355X.ctxSize -eq 131072) 'engineering MI355X context must be 262144/131072'
Assert-True ($catalog.roles.engineering.profiles.MI355X.maxOutputTokens -eq 32768) 'engineering MI355X maxOutputTokens must be 32768'
Assert-True ($catalog.roles.media.engine -eq 'media-lab' -and $catalog.roles.media.port -eq 8189) 'media engine/port mismatch'
Assert-True ($catalog.roles.media.profiles.MI355X.backend -eq 'media-rocm-gfx950') 'media MI355X backend mismatch'

$caddySnippetPath = Join-Path $repoRoot 'scripts' 'daytona-inference' 'gateway' 'Caddyfile.snippet'
$caddySnippetRaw = Get-Content -LiteralPath $caddySnippetPath -Raw -Encoding UTF8
Assert-True ($caddySnippetRaw -notmatch 'sk-[A-Za-z0-9_-]{12,}|\b(?!127\.0\.0\.1\b)\d{1,3}(\.\d{1,3}){3}\b') 'Caddyfile.snippet must not contain secrets or owner IP'
Assert-True ($caddySnippetRaw -match '<OWNER_IP>' -and $caddySnippetRaw -match '<MEDIA_PREVIEW_URL>') 'Caddyfile.snippet must use <OWNER_IP> and <MEDIA_PREVIEW_URL> placeholders'
Assert-True ($caddySnippetRaw -match 'handle_path /v1/media/\*' -and $caddySnippetRaw -match '127\.0\.0\.1:4000') 'Caddyfile.snippet must route /v1/media/* and preserve 127.0.0.1:4000'

foreach ($recipeFile in @('serve-vllm-cuda.sh', 'serve-vllm-rocm-gfx950.sh')) {
    $recipeText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts' 'daytona-inference' 'recipes' $recipeFile) -Raw -Encoding UTF8
    Assert-True ($recipeText -match 'caches/vllm-') "$recipeFile must restore persisted vLLM JIT caches"
    Assert-True ($recipeText -match 'overlay2') "$recipeFile must include Sysbox overlay2 symlink workaround"
}

# 2. Python syntax + unit tests for reasoning_normalizer.py and gpu.py
$pyUnit = @'
import argparse, py_compile, sys, pathlib
repo = pathlib.Path(sys.argv[1])
for rel in [
    "scripts/sync_inference_providers.py",
    "scripts/daytona-inference/gpu.py",
    "scripts/daytona-inference/gateway/reasoning_normalizer.py",
]:
    py_compile.compile(str(repo / rel), doraise=True)

sys.path.insert(0, str(repo / "scripts/daytona-inference/gateway"))
from reasoning_normalizer import normalize_reasoning_payload

p1 = normalize_reasoning_payload({"model": "qwen3.8-27b-unc-q8", "messages": []})
assert p1["reasoning_effort"] == "medium", p1
assert p1["extra_body"]["chat_template_kwargs"]["reasoning_effort"] == "medium"

p2 = normalize_reasoning_payload({"model": "qwen3.8-27b-unc-q8", "reasoning_effort": "high", "messages": []})
assert p2["reasoning_effort"] == "medium", p2
assert p2["extra_body"]["chat_template_kwargs"]["reasoning_effort"] == "medium"

p3 = normalize_reasoning_payload({"model": "qwen3.8-27b-unc-q8", "reasoning_effort": "xhigh", "messages": []})
assert p3["reasoning_effort"] == "xhigh", p3

p4 = normalize_reasoning_payload({"model": "inkling2-min-26b-unc-q8-128k", "messages": []})
assert p4["reasoning_effort"] == "medium", p4
assert "extra_body" not in p4

p5 = normalize_reasoning_payload({"model": "other-model", "reasoning_effort": "high", "messages": []})
assert p5["reasoning_effort"] == "high", p5

p6 = normalize_reasoning_payload(
    {
        "model": "qwen3.8-27b-unc-q8",
        "instructions": "Base inst",
        "input": [
            {"role": "developer", "content": "Dev rule"},
            {"role": "user", "content": "Hi"},
            {"role": "system", "content": [{"type": "input_text", "text": "Late sys"}]},
        ],
    },
    call_type="responses",
)
assert p6["reasoning"]["effort"] == "medium", p6
assert p6["instructions"] == "Base inst\n\nDev rule\n\nLate sys", p6
assert len(p6["input"]) == 1 and p6["input"][0]["role"] == "user", p6

p7 = normalize_reasoning_payload(
    {
        "model": "qwen3.8-27b-unc-q8",
        "messages": [
            {"role": "system", "content": "S1"},
            {"role": "user", "content": "U1"},
            {"role": "developer", "content": "S2"},
        ],
    }
)
assert len(p7["messages"]) == 2 and p7["messages"][0] == {"role": "system", "content": "S1\n\nS2"}, p7
assert p7["messages"][1]["role"] == "user", p7

sys.path.insert(0, str(repo / "scripts/daytona-inference"))
import gpu

cat = gpu.load_catalog()

class FakeSb:
    def __init__(self, sid, name, gpu_count=1, gpu_type="H200", state="STARTED", created_at=None):
        self.created_at = created_at
        self.id = sid
        self.name = name
        self.gpu = gpu_count
        self.gpu_type = gpu_type
        self.state = state

# Authorization checks: no magic sandbox id, only the recorded two AMD roles
for fn, arg in [
    (gpu.protect_sandbox, FakeSb("h1", "unauthorized-box", gpu_type="H200")),
    (gpu.protect_sandbox, FakeSb("u1", "unknown-role", gpu_type="MI355X")),
    (gpu.protect_volume_name, "llm-models"),
]:
    raised = False
    try:
        fn(arg)
    except SystemExit:
        raised = True
    assert raised, f"Expected SystemExit for {fn.__name__}"

two = [FakeSb("1", "agenthub-engineering", gpu_type="MI355X"), FakeSb("2", "agenthub-media", gpu_type="MI355X")]
ok, detail = gpu.check_gpu_authorization(two, cat)
assert ok, detail
raised = False
try:
    gpu.enforce_gpu_limit(two + [FakeSb("3", "agenthub-engineering", gpu_type="MI355X")], {"agenthub-engineering"}, catalog=cat)
except SystemExit:
    raised = True
assert raised, "Expected SystemExit when launching a 3rd GPU instance"

raised = False
try:
    gpu.assert_gpu_authorization([FakeSb("x", "unauthorized-box", gpu_type="H200")], cat)
except SystemExit:
    raised = True
assert raised, "Expected SystemExit when an unauthorized GPU sandbox runs"

# Reusing an existing target sandbox passes cap
gpu.enforce_gpu_limit(two, {"agenthub-engineering"}, catalog=cat)

# Auto GPU selection across NVIDIA + AMD
cap = {"H200": {"spot": 10}, "MI355X": {"spot": 50}, "B200": {"spot": 0}, "B300": {"spot": 0}, "RTX-PRO-6000": {"spot": 20}, "H100": {"spot": 0}}
chosen_spec, prof_spec = gpu.select_gpu_for_role("specialist", "auto", cap, cat)
assert chosen_spec == "H200" and prof_spec["backend"] == "vllm-cuda"

cap_amd = {"H200": {"spot": 0}, "MI355X": {"spot": 12}, "B200": {"spot": 0}, "B300": {"spot": 0}, "RTX-PRO-6000": {"spot": 0}, "H100": {"spot": 0}}
chosen_amd, prof_amd = gpu.select_gpu_for_role("specialist", "auto", cap_amd, cat)
assert chosen_amd == "MI355X" and prof_amd["backend"] == "vllm-rocm-gfx950"

chosen_flag, prof_flag = gpu.select_gpu_for_role("flagship", "auto", cap_amd, cat)
assert chosen_flag == "MI355X" and prof_flag["backend"] == "llama-hip-gfx950" and prof_flag["quantization"] == "Q8_0"

# H200 flagship must NOT silently substitute Q6_K without explicit authorization
raised = False
try:
    gpu.select_gpu_for_role("flagship", "H200", cap, cat)
except SystemExit:
    raised = True
assert raised, "Expected SystemExit on H200 Q8_0 without Q6 fallback flag"

chosen_h200_q6, prof_h200_q6 = gpu.select_gpu_for_role("flagship", "H200", cap, cat, allow_q6_fallback=True)
assert chosen_h200_q6 == "H200" and prof_h200_q6["quantization"] == "Q6_K"
parsed_save = gpu.build_parser().parse_args(["save-cache", "specialist"])
assert parsed_save.command == "save-cache" and parsed_save.role == "specialist"

# Engineering & media roles (MI355X dual-slot + fallback + volume routing)
chosen_eng, prof_eng = gpu.select_gpu_for_role("engineering", "auto", cap_amd, cat)
assert chosen_eng == "MI355X" and prof_eng["backend"] == "engineering-rocm-gfx950"
assert prof_eng["maxModelLen"] == 262144 and prof_eng["ctxSize"] == 131072 and prof_eng["maxOutputTokens"] == 32768

chosen_media, prof_media = gpu.select_gpu_for_role("media", "auto", cap_amd, cat)
assert chosen_media == "MI355X" and prof_media["backend"] == "media-rocm-gfx950"

assert gpu.role_volume_spec("engineering", cat) == ("opencode-agent-weights", "/mnt/opencode-weights")
assert gpu.role_volume_spec("media", cat) == ("agenthub-media-weights", "/mnt/media-weights")

for argv_case, exp_cmd, exp_role in [
    (["up", "engineering", "--gpu", "MI355X"], "up", "engineering"),
    (["up", "media", "--gpu", "auto"], "up", "media"),
    (["down", "engineering"], "down", "engineering"),
    (["down", "media"], "down", "media"),
    (["extend", "engineering", "180"], "extend", "engineering"),
    (["extend", "media", "180"], "extend", "media"),
    (["save-cache", "engineering"], "save-cache", "engineering"),
]:
    parsed = gpu.build_parser().parse_args(argv_case)
    assert parsed.command == exp_cmd and parsed.role == exp_role
assert gpu.build_parser().parse_args(["retire-legacy-turbo", "--dry-run"]).command == "retire-legacy-turbo"
assert gpu.build_parser().parse_args(["caddy-media", "--dry-run"]).command == "caddy-media"

# Gated retire-legacy-turbo refusals + success
from datetime import datetime, timezone
gate_now = datetime(2026, 11, 25, 12, 0, tzinfo=timezone.utc)
raised = False
try:
    gpu.check_retire_legacy_turbo_gates([FakeSb("e1", "agenthub-engineering", state="STOPPED")], "https://inference.shtrial.com/v1", "k")
except SystemExit:
    raised = True
assert raised, "retire-legacy-turbo must refuse when engineering is not STARTED"

def failing_flagship_probe(method, path, body):
    if path == "/models":
        return 200, {"data": [{"id": "qwen3.8-27b-unc-q8"}, {"id": "inkling2-min-26b-unc-q8-128k"}]}
    if body and body.get("model") == "inkling2-min-26b-unc-q8-128k":
        return 503, {"error": "down"}
    return 200, {"choices": [{"message": {"content": "OK"}}]}

raised = False
try:
    gpu.check_retire_legacy_turbo_gates(
        [FakeSb("e1", "agenthub-engineering", state="STARTED", created_at="2026-11-25T01:00:00Z")],
        "https://inference.shtrial.com/v1",
        "k",
        probe_fn=failing_flagship_probe,
        now=gate_now,
    )
except SystemExit:
    raised = True
assert raised, "retire-legacy-turbo must refuse when inkling2-min-26b-unc-q8-128k fails live check"

def passing_probe(method, path, body):
    if path == "/models":
        return 200, {"data": [{"id": "qwen3.8-27b-unc-q8"}, {"id": "inkling2-min-26b-unc-q8-128k"}]}
    return 200, {"choices": [{"message": {"content": "OK"}}]}

# Engineering must also have been up for MIN_ENGINEERING_UPTIME_HOURS: a passing live check on a young box is not enough
assert gpu.MIN_ENGINEERING_UPTIME_HOURS == 6
for label, created in [("5h59m old", "2026-11-25T06:01:00Z"), ("no createdAt", None), ("unreadable createdAt", "yesterday-ish")]:
    try:
        gpu.check_retire_legacy_turbo_gates(
            [FakeSb("e1", "agenthub-engineering", state="STARTED", created_at=created)],
            "https://inference.shtrial.com/v1",
            "k",
            probe_fn=passing_probe,
            now=gate_now,
        )
    except SystemExit as exc:
        assert "retire-legacy-turbo" in str(exc), exc
        continue
    raise AssertionError(f"retire-legacy-turbo must refuse an engineering box that is {label}")

eng_ok = gpu.check_retire_legacy_turbo_gates(
    [FakeSb("e1", "agenthub-engineering", state="STARTED", created_at="2026-11-25T06:00:00+00:00")],
    "https://inference.shtrial.com/v1",
    "k",
    probe_fn=passing_probe,
    now=gate_now,
)
assert eng_ok.id == "e1"

# Caddyfile rendering and site-block upsert preserving unrelated sites
rendered_site = gpu.render_caddyfile_site_block(
    "203.0.113.10",
    "inf-key-test",
    "https://8189-test.daytonaproxy01.net",
    "prev-tok-test",
    "gw-tok-test",
)
assert "handle_path /v1/media/*" in rendered_site
assert "comfy.shtrial.com" in rendered_site and "forward_auth 127.0.0.1:3000" in rendered_site and "rewrite * /comfy{uri}" in rendered_site
assert "x-daytona-preview-token prev-tok-test" in rendered_site
assert 'Authorization "Bearer gw-tok-test"' in rendered_site
assert "reverse_proxy 127.0.0.1:4000" in rendered_site
existing_caddy = "other.example.com {\n  respond \"hi\" 200\n}\n\ninference.shtrial.com {\n  respond \"old\" 200\n}\n"
merged_caddy = gpu.upsert_caddy_site_block(existing_caddy, "inference.shtrial.com", rendered_site)
assert "other.example.com" in merged_caddy and "old" not in merged_caddy and "handle_path /v1/media/*" in merged_caddy

# Spend guards: TTL is always set and capped; media boxes never adopt another sandbox or a snapshot that cannot exist
assert gpu.ttl_minutes("1") == 1 and gpu.ttl_minutes("480") == 480
for bad_ttl in ("0", "-5", "481", "abc"):
    try:
        gpu.ttl_minutes(bad_ttl)
    except argparse.ArgumentTypeError:
        continue
    raise AssertionError(f"ttl {bad_ttl} must be refused")
try:
    gpu.build_parser().parse_args(["up", "media", "--ttl", "0"])
    raise AssertionError("up --ttl 0 must be refused")
except SystemExit:
    pass
assert gpu.build_parser().parse_args(["up", "media"]).ttl == cat["policy"]["defaultTtlMinutes"]
assert cat["roles"]["media"]["legacySandboxNames"] == []
assert all("snapshotName" not in prof for prof in cat["roles"]["media"]["profiles"].values())
for image_key, image_spec in cat["images"].items():
    if "dockerfile" in image_spec:
        assert (pathlib.Path(gpu.__file__).parent / image_spec["dockerfile"]).is_file(), f"{image_key} dockerfile missing"

# Media client: server-chosen names cannot leave the output directory; the Bearer key only goes to https
sys.path.insert(0, str(repo / "packages/media-studio/scripts"))
import tempfile
import daytona_media_client as mc

for bad_name in ("../x.png", "..\\x.png", "/etc/passwd", "C:\\x.png", "a/b.png", "", ".hidden", "x..png"):
    try:
        mc._safe_name(bad_name, "output name")
    except RuntimeError:
        continue
    raise AssertionError(f"unsafe name accepted: {bad_name!r}")
assert mc._safe_name("scene-01_v2.png", "output name") == "scene-01_v2.png"
try:
    mc.MediaApiClient.from_gateway("http://inference.example.test/v1/media", "k")
    raise AssertionError("plain http gateway must be refused")
except RuntimeError:
    pass
assert mc.MediaApiClient.from_gateway("https://inference.example.test/v1/media/", "k").base_url.endswith("/v1/media")

# Transient connection errors are retried; refusals and writes behind a 5xx are not
import io
class FakeHttpResp:
    def __init__(self, body): self.body = body
    def __enter__(self): return self
    def __exit__(self, *exc): return False
    def read(self): return self.body

real_urlopen, real_retry_sleep = mc.urllib.request.urlopen, mc.RETRY_SLEEP_SECONDS
mc.RETRY_SLEEP_SECONDS = 0
retry_client = mc.MediaApiClient("https://inference.example.test/v1/media", "k")
seen = {"n": 0}
def flaky_open(req, timeout=None):
    seen["n"] += 1
    if seen["n"] < 3:
        raise mc.urllib.error.URLError("tls handshake")
    return FakeHttpResp(b'{"ok": true}')
mc.urllib.request.urlopen = flaky_open
assert retry_client.request("POST", "/v1/jobs", {"type": "image"}) == {"ok": True} and seen["n"] == 3
def refused_open(req, timeout=None):
    seen["n"] += 1
    raise mc.urllib.error.HTTPError(req.full_url, 401, "no", {}, io.BytesIO(b"unauthorized"))
seen["n"] = 0
mc.urllib.request.urlopen = refused_open
try:
    retry_client.request("GET", "/v1/info")
    raise AssertionError("401 must raise")
except RuntimeError as exc:
    assert "401" in str(exc) and seen["n"] == 1
def bad_gateway_open(req, timeout=None):
    seen["n"] += 1
    raise mc.urllib.error.HTTPError(req.full_url, 502, "bad", {}, io.BytesIO(b"bad gateway"))
mc.urllib.request.urlopen = bad_gateway_open
seen["n"] = 0
try:
    retry_client.request("GET", "/v1/info")
except RuntimeError:
    pass
assert seen["n"] == mc.REQUEST_ATTEMPTS
seen["n"] = 0
try:
    retry_client.request("POST", "/v1/jobs", {"type": "image"})
except RuntimeError:
    pass
assert seen["n"] == 1
mc.urllib.request.urlopen, mc.RETRY_SLEEP_SECONDS = real_urlopen, real_retry_sleep

class FakeMediaClient:
    def __init__(self, payload):
        self.payload = payload
        self.calls = 0
    def request(self, method, path, body=None, raw=False, timeout=120):
        self.calls += 1
        return self.payload

with tempfile.TemporaryDirectory() as td:
    td_path = pathlib.Path(td)
    good = b"media-bytes"
    import hashlib
    item = {"name": "a.png", "size": len(good), "sha256": hashlib.sha256(good).hexdigest()}
    fake = FakeMediaClient(good)
    job = {"id": "job1", "outputs": [item]}
    accepted = mc.pull_verified_outputs(fake, job, td_path / "o")
    assert (td_path / "o" / "a.png").read_bytes() == good and not list((td_path / "o").glob("*.part"))
    assert mc.scene_is_complete({"status": "done", "files": accepted}, td_path / "o")
    (td_path / "o" / "a.png").write_bytes(b"tampered")
    assert not mc.scene_is_complete({"status": "done", "files": accepted}, td_path / "o")
    # a corrupt download is refused and leaves nothing behind
    bad_fake = FakeMediaClient(b"wrong")
    (td_path / "o" / "a.png").unlink()
    try:
        mc.pull_verified_outputs(bad_fake, job, td_path / "o")
        raise AssertionError("size/hash mismatch must raise")
    except RuntimeError:
        pass
    assert not (td_path / "o" / "a.png").exists()
    try:
        mc.pull_verified_outputs(fake, {"id": "job1", "outputs": [{**item, "name": "../escape.png"}]}, td_path / "o")
        raise AssertionError("traversal name must raise")
    except RuntimeError:
        pass
    assert not (td_path / "escape.png").exists()

# gpu.py prefill media: on-box script logic (offline)
import importlib.util, io, os, types, urllib.request, contextlib, json as _json
spec = importlib.util.spec_from_file_location("prefill_media", repo / "scripts/daytona-inference/recipes/prefill-media.py")
pm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pm)
models_doc = {"installed": [
    {"repo": "a/whole", "revision": "r1", "files": []},
    {"repo": "b/pick", "revision": "r2", "files": [{"path": "x/one.safetensors"}, {"path": "x/two.safetensors"}, {"path": "x/one.safetensors"}]},
    {"repo": "c/mixed", "revision": "r3", "files": [{"path": "f.bin", "repo": "d/other", "revision": "r4"}]},
]}
specs = pm.build_specs(models_doc)
assert specs == [("a/whole", "r1", ""), ("b/pick", "r2", "x/one.safetensors"), ("b/pick", "r2", "x/two.safetensors"), ("d/other", "r4", "f.bin")], specs
picked, missing = pm.select_files("b/pick", {"x/one.safetensors": 5, "extra": 9}, ["x/one.safetensors", "x/two.safetensors"])
assert picked == {"x/one.safetensors": 5} and missing == ["x/two.safetensors"]
whole, none_missing = pm.select_files("Zyphra/ZONOS3-Mini", {"model.safetensors": 1, "web/index.html": 2, "gguf/a.gguf": 3, "old.bin": 4, "autoencoder/heads/full_mr/w": 5}, [""])
assert whole == {"model.safetensors": 1} and none_missing == [], whole
handler = pm.DropAuthOnNewHost()
orig_req = urllib.request.Request("https://huggingface.co/a/b/resolve/r/f", headers={"Authorization": "Bearer secret-token-value"})
cross = handler.redirect_request(orig_req, None, 302, "Found", {}, "https://cdn.example.net/signed?x=1")
assert cross is not None and not any(k.lower() == "authorization" for k in cross.headers)
same = handler.redirect_request(orig_req, None, 302, "Found", {}, "https://huggingface.co/other/path")
assert same is not None and any(k.lower() == "authorization" for k in same.headers)

# gpu.py prefill media: box lifecycle with a fake Daytona (offline)
class FakeProc:
    def __init__(self, box): self.box = box
    def exec(self, cmd, timeout=None):
        self.box.cmds.append(cmd)
        if self.box.exec_error and cmd.startswith("cat /tmp/prefill.log"):
            raise RuntimeError("exec boom")
        if cmd.startswith("cat /tmp/prefill.log"):
            return types.SimpleNamespace(result=self.box.log, exit_code=0)
        return types.SimpleNamespace(result="", exit_code=0)

class FakeFs:
    def __init__(self, box): self.box = box
    def upload_file(self, data, path): self.box.uploads[path] = data

class FakeBox:
    def __init__(self, log, exec_error=False):
        self.id = "prefill-box-1"
        self.log, self.exec_error = log, exec_error
        self.cmds, self.uploads, self.deleted = [], {}, False
        self.process, self.fs = FakeProc(self), FakeFs(self)
    def delete(self, timeout=None): self.deleted = True

class FakeV0:
    def __init__(self, box):
        self.box, self.params = box, None
        self.volume = types.SimpleNamespace(get=lambda name, create=False: types.SimpleNamespace(name=name, id="vol-1", state="READY"))
    def create(self, params, **kw):
        self.params = params
        return self.box

class FakeApp:
    def __init__(self, box): self.v0, self.closed = FakeV0(box), False
    def close(self): self.closed = True

class Rec:
    def __init__(self, **kw): self.__dict__.update(kw)

fake_v0_mod = types.ModuleType("daytona.v0")
fake_v0_mod.CreateSandboxFromImageParams = Rec
fake_v0_mod.Resources = Rec
fake_v0_mod.VolumeMount = Rec
saved_mods = {k: sys.modules.get(k) for k in ("daytona", "daytona.v0")}
sys.modules["daytona"] = types.ModuleType("daytona")
sys.modules["daytona.v0"] = fake_v0_mod
real_client, real_sleep = gpu.get_daytona_client, gpu.time.sleep
gpu.time.sleep = lambda s: None
secret_value = "hf_synthetic_secret_value_123"
os.environ["HF_TOKEN"] = secret_value
with tempfile.TemporaryDirectory() as media_dir:
    pathlib.Path(media_dir, "models.json").write_text(_json.dumps(models_doc))
    os.environ["MEDIA_GPU_GEN_SERVER_DIR"] = media_dir

    def run_prefill(box):
        app = FakeApp(box)
        gpu.get_daytona_client = lambda: app
        out = io.StringIO()
        err = None
        with contextlib.redirect_stdout(out):
            try:
                gpu.cmd_prefill(gpu.build_parser().parse_args(["prefill", "media", "--ttl", "60"]))
            except BaseException as exc:
                err = exc
        return app, out.getvalue(), err

    ok_box = FakeBox("2 files 0.0 GB\nbad []\nPREFILL_DONE\n")
    app, out, err = run_prefill(ok_box)
    assert err is None and ok_box.deleted and app.closed, (err, out)
    p = app.v0.params
    assert p.ephemeral is True and p.ttl_minutes == 60 and p.labels["owner"] == "agenthub" and p.resources.cpu == 4
    assert not hasattr(p.resources, "gpu") and p.volumes[0].mount_path == "/mnt/media-weights" and p.volumes[0].volume_id == "vol-1"
    assert ok_box.uploads["/tmp/hf.token"].decode() == secret_value and "/tmp/models.json" in ok_box.uploads
    assert secret_value not in out and all(secret_value not in c for c in ok_box.cmds)
    assert any(c.startswith("chmod 600 /tmp/hf.token") for c in ok_box.cmds)

    bad_box = FakeBox("bad [('a/whole', 'r1', 'f')]\nPREFILL_DONE\n")
    app, out, err = run_prefill(bad_box)
    assert isinstance(err, SystemExit) and bad_box.deleted and app.closed, (err, out)

    dead_box = FakeBox("Traceback\nNOT_RUNNING\n")
    app, out, err = run_prefill(dead_box)
    assert isinstance(err, SystemExit) and dead_box.deleted

    boom_box = FakeBox("", exec_error=True)
    app, out, err = run_prefill(boom_box)
    assert isinstance(err, RuntimeError) and boom_box.deleted and app.closed
    assert secret_value not in out

    os.environ.pop("HF_TOKEN")
    real_secret = gpu.read_secret_value
    gpu.read_secret_value = lambda names, file_name=None: ""
    try:
        gpu.cmd_prefill(gpu.build_parser().parse_args(["prefill", "media"]))
        raise AssertionError("prefill without a token must refuse")
    except SystemExit as exc:
        assert "HF_TOKEN" in str(exc)
    finally:
        gpu.read_secret_value = real_secret
os.environ.pop("MEDIA_GPU_GEN_SERVER_DIR", None)
gpu.get_daytona_client, gpu.time.sleep = real_client, real_sleep
for name, mod in saved_mods.items():
    if mod is None:
        sys.modules.pop(name, None)
    else:
        sys.modules[name] = mod
assert gpu.build_parser().parse_args(["prefill", "media"]).ttl == 90

# Caddy snippet: /v1/media needs the inference key even from the owner IP
snippet_text = (repo / "scripts/daytona-inference/gateway/Caddyfile.snippet").read_text(encoding="utf-8")
media_block = snippet_text.split("handle_path /v1/media/*", 1)[1].split("reverse_proxy", 1)[0]
assert "not header Authorization" in media_block and "remote_ip" not in media_block, media_block

print("PY_UNIT_PASS")
'@

$pyUnitFile = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-inf-unit-" + [Guid]::NewGuid().ToString('N') + '.py')
try {
    [IO.File]::WriteAllText($pyUnitFile, $pyUnit)
    $pyOut = & python -I $pyUnitFile $repoRoot 2>&1 | Out-String
} finally {
    Remove-Item -LiteralPath $pyUnitFile -Force -ErrorAction SilentlyContinue
}
Assert-True ($LASTEXITCODE -eq 0 -and ($pyOut -match 'PY_UNIT_PASS')) "Python unit tests failed: $pyOut"

# 3. Synthetic UserProfile end-to-end test for Sync-InferenceProviders.ps1
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-inf-test-" + [Guid]::NewGuid().ToString('N'))
$fakeHome = Join-Path $tmpRoot 'home'
$fakeRoaming = Join-Path $tmpRoot 'roaming'
$sentinelKey = 'synthetic-sentinel-key-never-print-9999'

try {
    $dirs = @(
        "$fakeHome/.config/opencode",
        "$fakeHome/.codex",
        "$fakeHome/.factory",
        "$fakeHome/.grok",
        "$fakeHome/.copilot",
        "$fakeRoaming/Code - Insiders/User",
        "$fakeHome/.config/kilo",
        "$fakeHome/.cline/data/settings",
        "$fakeHome/.zcode/v2"
    )
    foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

    [IO.File]::WriteAllText("$fakeHome/.config/opencode/opencode.json", (@{
        model = 'qwen-token-plan/qwen3.8-max'
        small_model = 'qwen-token-plan/qwen3.8-flash'
        providers = @{ 'qwen-token-plan' = @{ name = 'Qwen Token Plan' } }
        agents = @{ title = @{ model = 'qwen-token-plan/qwen3.8-flash' } }
    } | ConvertTo-Json -Depth 10))

    [IO.File]::WriteAllText("$fakeHome/.codex/config.toml", "forced_login_method = `"chatgpt`"`nmodel = `"gpt-6.2-sol`"`n")
    [IO.File]::WriteAllText("$fakeHome/.factory/settings.json", (@{ model = $null; customModels = @(@{ model = 'qwen4-max-preview'; baseUrl = 'https://example.invalid/v1' }) } | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome/.grok/config.toml", "[models]`ndefault = `"grok-4`"`n`n[model.daytona-specialist]`nmodel = `"qwen3.8-27b-unc-q8`"`nname = `"Old Daytona Specialist`"`n")
    [IO.File]::WriteAllText("$fakeRoaming/Code - Insiders/User/chatLanguageModels.json", (@(@{ name = 'Copilot'; vendor = 'copilot' }, @{ name = 'Daytona H200'; vendor = 'customendpoint'; models = @() }) | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome/.config/kilo/kilo.jsonc", (@{ model = 'mimo/mimo-v2.6-pro'; provider = @{ mimo = @{ name = 'MiMo' } } } | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome/.cline/data/settings/providers.json", (@{ version = 1; lastUsedProvider = 'cline'; providers = @{ cline = @{ settings = @{ auth = @{ accessToken = 'tok-keep' } } } } } | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome/.zcode/v2/provider_config.json", (@{ schemaVersion = 1; config = @{ providerOrder = @('account:zai-start-plan', 'daytona-turbo-heretic-q6'); providerConfigRules = @{ providerRules = @(@{ providerId = 'account:zai-start-plan'; config = @{ modelOrder = @('GLM-5.4') } }, @{ providerId = 'daytona-turbo-heretic-q6'; config = @{ modelOrder = @('old') } }) } } } | ConvertTo-Json -Depth 10))

    $prevKey = $env:AGENTHUB_INFERENCE_KEY
    $env:AGENTHUB_INFERENCE_KEY = $sentinelKey
    try {
        $applyOut = (& pwsh -NoProfile -File $syncScript -Apply -UserProfile $fakeHome -RoamingConfig $fakeRoaming -Json | Out-String)
        Assert-True ($LASTEXITCODE -eq 0) "Sync -Apply failed: $applyOut"
        Assert-True ($applyOut -notmatch [regex]::Escape($sentinelKey)) 'Sync output leaked API key'

        $auditOut = (& pwsh -NoProfile -File $syncScript -Audit -UserProfile $fakeHome -RoamingConfig $fakeRoaming -Json | Out-String)
        Assert-True ($LASTEXITCODE -eq 0) "Sync -Audit failed: $auditOut"
        Assert-True ($auditOut -notmatch [regex]::Escape($sentinelKey)) 'Audit output leaked API key'

        $auditRows = $auditOut | ConvertFrom-Json
        foreach ($h in @('opencode', 'codex', 'factory', 'grok', 'copilot', 'vscode-insiders', 'kilo', 'cline', 'zcode')) {
            $row = $auditRows | Where-Object { $_.host -eq $h } | Select-Object -First 1
            Assert-True ($null -ne $row -and $row.status -eq 'current') "Expected host $h status=current after apply, got $($row.status)"
        }

        # Verify preserved defaults and the two model contexts
        $oc = Get-Content "$fakeHome/.config/opencode/opencode.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($oc.model -eq 'qwen-token-plan/qwen3.8-max') 'OpenCode default model changed'
        Assert-True ($oc.small_model -eq 'qwen-token-plan/qwen3.8-flash') 'OpenCode small_model changed'
        $qm = $oc.providers.'agenthub-daytona'.models.'qwen3.8-27b-unc-q8'
        Assert-True ($null -ne $qm -and $qm.limit.context -eq 262144 -and $qm.limit.output -eq 32768) 'Qwen context/output limit mismatch'
        $im = $oc.providers.'agenthub-daytona'.models.'inkling2-min-26b-unc-q8-128k'
        Assert-True ($null -ne $im -and $im.limit.context -eq 131072 -and $im.limit.output -eq 32768) 'Inkling context/output limit mismatch'

        $codexCfg = Get-Content "$fakeHome/.codex/config.toml" -Raw -Encoding UTF8
        Assert-True ($codexCfg -notmatch '\[profiles\.daytona-') 'Codex config.toml must not contain inline [profiles.daytona-*]'
        foreach ($p in @('qwen3.8-27b-unc-q8', 'inkling2-min-26b-unc-q8-128k')) {
            Assert-True (Test-Path -LiteralPath "$fakeHome/.codex/$p.config.toml") "Missing standalone Codex profile $p.config.toml"
        }

        $cl = Get-Content "$fakeHome/.cline/data/settings/providers.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($cl.lastUsedProvider -eq 'cline') 'Cline lastUsedProvider changed'
        Assert-True ($cl.providers.cline.settings.auth.accessToken -eq 'tok-keep') 'Cline OAuth token altered'
        Assert-True ($cl.providers.'openai-compatible'.settings.baseUrl -eq 'https://inference.shtrial.com/v1') 'Cline openai-compatible baseUrl mismatch'

        $grokCfg = Get-Content "$fakeHome/.grok/config.toml" -Raw -Encoding UTF8
        Assert-True ($grokCfg -notmatch '\[model\.daytona-specialist\]') 'Legacy Grok [model.daytona-specialist] must be pruned'
        Assert-True ($grokCfg -match 'Qwen 3\.8 27B Uncensored \(BF16\)') 'Grok display names must include the model label the registry actually serves'

        $vscCfg = Get-Content "$fakeRoaming/Code - Insiders/User/chatLanguageModels.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True (@($vscCfg | Where-Object { $_.name -eq 'Daytona H200' }).Count -eq 0) 'Legacy VS Code Daytona H200 group must be pruned'
        Assert-True (@($vscCfg | Where-Object { $_.name -eq 'Copilot' }).Count -eq 1) 'Copilot group in VS Code must be preserved'

        $zcCfg = Get-Content "$fakeHome/.zcode/v2/provider_config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($zcCfg.config.providerOrder -notcontains 'daytona-turbo-heretic-q6') 'Legacy ZCode providerOrder entry must be pruned'
        Assert-True ($zcCfg.config.providerOrder -contains 'account:zai-start-plan') 'ZCode account:zai-start-plan must be preserved'
    }
    finally {
        $env:AGENTHUB_INFERENCE_KEY = $prevKey
    }
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'PASS: Test-InferenceProviders.ps1'
