#Requires -Version 7
<#
.SYNOPSIS
  Tests for the unified Daytona inference gateway, GPU lifecycle helper,
  and additive multi-host inference provider rollout.
#>
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$specPath = Join-Path $repoRoot 'registry\inference-providers.json'
$catalogPath = Join-Path $repoRoot 'scripts\daytona-inference\catalog.json'
$syncScript = Join-Path $repoRoot 'scripts\Sync-InferenceProviders.ps1'

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
foreach ($expected in @('agent-fast', 'agent-specialist', 'agent-vision', 'agent-turbo', 'agent-flagship')) {
    Assert-True ($aliases -contains $expected) "Missing canonical alias $expected"
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($catalog.policy.maxGpuInstancesTotal -eq 2) 'maxGpuInstancesTotal must be 2'
Assert-True ($catalog.policy.spotOnly -eq $true) 'spotOnly must be true'
Assert-True ($catalog.policy.protectedVolumeName -eq 'llm-models') 'protectedVolumeName must be llm-models'
Assert-True ($catalog.roles.specialist.profiles.H200.snapshotName -eq 'agenthub-vllm-cuda-0-24-0-h200') 'H200 specialist snapshotName mismatch'
Assert-True ($catalog.roles.flagship.profiles.H200.snapshotName -eq 'agenthub-llama-cuda-h200') 'H200 flagship snapshotName mismatch'

foreach ($recipeFile in @('serve-vllm-cuda.sh', 'serve-vllm-rocm-gfx950.sh')) {
    $recipeText = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\daytona-inference\recipes\$recipeFile") -Raw -Encoding UTF8
    Assert-True ($recipeText -match 'caches/vllm-') "$recipeFile must restore persisted vLLM JIT caches"
    Assert-True ($recipeText -match 'overlay2') "$recipeFile must include Sysbox overlay2 symlink workaround"
}

# 2. Python syntax + unit tests for reasoning_normalizer.py and gpu.py
$pyUnit = @'
import py_compile, sys, pathlib
repo = pathlib.Path(sys.argv[1])
for rel in [
    "scripts/sync_inference_providers.py",
    "scripts/daytona-inference/gpu.py",
    "scripts/daytona-inference/gateway/reasoning_normalizer.py",
]:
    py_compile.compile(str(repo / rel), doraise=True)

sys.path.insert(0, str(repo / "scripts/daytona-inference/gateway"))
from reasoning_normalizer import normalize_reasoning_payload

p1 = normalize_reasoning_payload({"model": "agent-fast", "messages": []})
assert p1["reasoning_effort"] == "low", p1
assert p1["extra_body"]["chat_template_kwargs"]["reasoning_effort"] == "low"

p2 = normalize_reasoning_payload({"model": "agent-specialist", "reasoning_effort": "high", "messages": []})
assert p2["reasoning_effort"] == "medium", p2
assert p2["extra_body"]["chat_template_kwargs"]["reasoning_effort"] == "medium"

p3 = normalize_reasoning_payload({"model": "agent-specialist", "reasoning_effort": "xhigh", "messages": []})
assert p3["reasoning_effort"] == "xhigh", p3

p4 = normalize_reasoning_payload({"model": "agent-turbo", "reasoning_effort": "high", "messages": []})
assert p4["reasoning_effort"] == "medium", p4
assert "extra_body" not in p4

p5 = normalize_reasoning_payload({"model": "other-model", "reasoning_effort": "high", "messages": []})
assert p5["reasoning_effort"] == "high", p5

p6 = normalize_reasoning_payload(
    {
        "model": "agent-turbo",
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
        "model": "agent-turbo",
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
    def __init__(self, sid, name, gpu_count=1, gpu_type="H200", state="STARTED"):
        self.id = sid
        self.name = name
        self.gpu = gpu_count
        self.gpu_type = gpu_type
        self.state = state

# Protected sandbox/volume checks
for fn, arg in [
    (gpu.protect_sandbox, FakeSb(gpu.PROTECTED_SANDBOX_ID, "other")),
    (gpu.protect_sandbox, FakeSb("other-id", gpu.PROTECTED_SANDBOX_NAME)),
    (gpu.protect_volume_name, "llm-models"),
]:
    raised = False
    try:
        fn(arg)
    except SystemExit:
        raised = True
    assert raised, f"Expected SystemExit for {fn.__name__}"

# 2-GPU instance cap
two = [FakeSb("1", "qwen38-turbo-q6k"), FakeSb("2", "agenthub-specialist")]
raised = False
try:
    gpu.enforce_gpu_limit(two, {"agenthub-flagship"}, 2)
except SystemExit:
    raised = True
assert raised, "Expected SystemExit when launching 3rd GPU instance"

# Reusing an existing target sandbox passes cap
gpu.enforce_gpu_limit(two, {"agenthub-specialist"}, 2)

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
print("PY_UNIT_PASS")
'@

$pyOut = $pyUnit | python - $repoRoot
Assert-True ($LASTEXITCODE -eq 0 -and ($pyOut -match 'PY_UNIT_PASS')) "Python unit tests failed: $pyOut"

# 3. Synthetic UserProfile end-to-end test for Sync-InferenceProviders.ps1
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-inf-test-" + [Guid]::NewGuid().ToString('N'))
$fakeHome = Join-Path $tmpRoot 'home'
$fakeRoaming = Join-Path $tmpRoot 'roaming'
$sentinelKey = 'sk-synthetic-test-key-never-print-9999'

try {
    $dirs = @(
        "$fakeHome\.config\opencode",
        "$fakeHome\.codex",
        "$fakeHome\.factory",
        "$fakeHome\.grok",
        "$fakeHome\.copilot",
        "$fakeRoaming\Code - Insiders\User",
        "$fakeHome\.config\kilo",
        "$fakeHome\.cline\data\settings",
        "$fakeHome\.zcode\v2"
    )
    foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

    [IO.File]::WriteAllText("$fakeHome\.config\opencode\opencode.json", (@{
        model = 'qwen-token-plan/qwen3.8-max'
        small_model = 'qwen-token-plan/qwen3.8-flash'
        providers = @{ 'qwen-token-plan' = @{ name = 'Qwen Token Plan' } }
        agents = @{ title = @{ model = 'qwen-token-plan/qwen3.8-flash' } }
    } | ConvertTo-Json -Depth 10))

    [IO.File]::WriteAllText("$fakeHome\.codex\config.toml", "forced_login_method = `"chatgpt`"`nmodel = `"gpt-6.2-sol`"`n")
    [IO.File]::WriteAllText("$fakeHome\.factory\settings.json", (@{ model = $null; customModels = @(@{ model = 'qwen4-max-preview'; baseUrl = 'https://example.invalid/v1' }) } | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome\.grok\config.toml", "[models]`ndefault = `"grok-4`"`n`n[model.daytona-specialist]`nmodel = `"agent-specialist`"`nname = `"Old Daytona Specialist`"`n")
    [IO.File]::WriteAllText("$fakeRoaming\Code - Insiders\User\chatLanguageModels.json", (@(@{ name = 'Copilot'; vendor = 'copilot' }, @{ name = 'Daytona H200'; vendor = 'customendpoint'; models = @() }) | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome\.config\kilo\kilo.jsonc", (@{ model = 'mimo/mimo-v2.6-pro'; provider = @{ mimo = @{ name = 'MiMo' } } } | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome\.cline\data\settings\providers.json", (@{ version = 1; lastUsedProvider = 'cline'; providers = @{ cline = @{ settings = @{ auth = @{ accessToken = 'tok-keep' } } } } } | ConvertTo-Json -Depth 10))
    [IO.File]::WriteAllText("$fakeHome\.zcode\v2\provider_config.json", (@{ schemaVersion = 1; config = @{ providerOrder = @('account:zai-start-plan', 'daytona-turbo-heretic-q6'); providerConfigRules = @{ providerRules = @(@{ providerId = 'account:zai-start-plan'; config = @{ modelOrder = @('GLM-5.4') } }, @{ providerId = 'daytona-turbo-heretic-q6'; config = @{ modelOrder = @('old') } }) } } } | ConvertTo-Json -Depth 10))

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

        # Verify preserved defaults
        $oc = Get-Content "$fakeHome\.config\opencode\opencode.json" -Raw | ConvertFrom-Json
        Assert-True ($oc.model -eq 'qwen-token-plan/qwen3.8-max') 'OpenCode default model changed'
        Assert-True ($oc.small_model -eq 'qwen-token-plan/qwen3.8-flash') 'OpenCode small_model changed'

        $codexCfg = Get-Content "$fakeHome\.codex\config.toml" -Raw
        Assert-True ($codexCfg -notmatch '\[profiles\.daytona-') 'Codex config.toml must not contain inline [profiles.daytona-*]'
        foreach ($p in @('daytona-fast', 'daytona-specialist', 'daytona-vision', 'daytona-turbo', 'daytona-flagship')) {
            Assert-True (Test-Path -LiteralPath "$fakeHome\.codex\$p.config.toml") "Missing standalone Codex profile $p.config.toml"
        }

        $cl = Get-Content "$fakeHome\.cline\data\settings\providers.json" -Raw | ConvertFrom-Json
        Assert-True ($cl.lastUsedProvider -eq 'cline') 'Cline lastUsedProvider changed'
        Assert-True ($cl.providers.cline.settings.auth.accessToken -eq 'tok-keep') 'Cline OAuth token altered'
        Assert-True ($cl.providers.'openai-compatible'.settings.baseUrl -eq 'https://inference.shtrial.com/v1') 'Cline openai-compatible baseUrl mismatch'

        $grokCfg = Get-Content "$fakeHome\.grok\config.toml" -Raw
        Assert-True ($grokCfg -notmatch '\[model\.daytona-specialist\]') 'Legacy Grok [model.daytona-specialist] must be pruned'
        Assert-True ($grokCfg -match 'Qwen3\.8 27B Uncensored FP8') 'Grok display names must include uncensored checkpoint label'

        $vscCfg = Get-Content "$fakeRoaming\Code - Insiders\User\chatLanguageModels.json" -Raw | ConvertFrom-Json
        Assert-True (@($vscCfg | Where-Object { $_.name -eq 'Daytona H200' }).Count -eq 0) 'Legacy VS Code Daytona H200 group must be pruned'
        Assert-True (@($vscCfg | Where-Object { $_.name -eq 'Copilot' }).Count -eq 1) 'Copilot group in VS Code must be preserved'

        $zcCfg = Get-Content "$fakeHome\.zcode\v2\provider_config.json" -Raw | ConvertFrom-Json
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
