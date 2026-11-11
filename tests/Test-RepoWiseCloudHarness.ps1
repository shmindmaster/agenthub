#Requires -Version 5.1
<#
Behavior coverage for the SH-4410 RepoWise cloud harness pieces under
packages/repowise/cloud/: the context cap, the benchmark table, and the
read-only findings report.

Covers:
  1. context_cap.py truncates an oversized tools/call result with a clear
     marker (byte cap and item cap both proven), caps the WHOLE serialized
     result (an oversized structuredContent is dropped, not passed through),
     caps JSON-RPC batches element by element, truncates multi-byte text
     without emitting invalid UTF-8, and leaves small results untouched.
     Runs the real module through python.
  2. repowise_bridge_capped.py's SSE parser splits streamable-HTTP bodies
     into JSON-RPC messages (unit-level, no network).
  3. Measure-RepoWiseBenefit.ps1 produces the comparison table from the
     shipped synthetic logs (tokens incl. cached, tool calls, time to the
     correct file, stale flag).
  4. New-RepoWiseFindings.ps1 turns synthetic repowise outputs into a
     findings file with reproducible evidence and a cross-check field, and
     the script contains no issue-tracker mutation surface.

Run: pwsh -NoProfile -File tests/Test-RepoWiseCloudHarness.ps1
     powershell.exe -NoProfile -File tests/Test-RepoWiseCloudHarness.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$cloud = Join-Path $repoRoot 'packages\repowise\cloud'
$hostExe = (Get-Process -Id $PID).Path

$failures = [Collections.Generic.List[string]]::new()
$script:reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

# A real installed interpreter (the Microsoft Store stub is refused, same as
# the bounded-index test).
$python = Get-Command python.exe -All -CommandType Application | ForEach-Object {
    try { & $_.Source -c 'import sys; print(sys.executable)' 2>$null | Select-Object -Last 1 } catch { }
} | Where-Object { $_ -and $_ -notlike '*\WindowsApps\*' -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1

# --- 1+2. context cap and SSE parse, through the real modules ----------------
if (-not $python) {
    Report 'python interpreter available for cap/bridge unit checks' $false 'no installed (non-Store) python.exe found'
} else {
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('rwcloud-harness-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    try {
        $probe = Join-Path $scratch 'probe.py'
        [IO.File]::WriteAllText($probe, @'
import json, sys
sys.path.insert(0, sys.argv[1])
from context_cap import cap_response, MARKER_PREFIX
from repowise_bridge_capped import parse_sse

# oversized single text item: truncated, marker appended, budget honored
big = "x" * 200000
msg = {"jsonrpc": "2.0", "id": 1, "result": {"content": [{"type": "text", "text": big}]}}
out, stats = cap_response(msg, max_bytes=5000, max_items=10)
assert stats["truncated"], "single oversized item was not truncated"
content = out["result"]["content"]
assert content[-1]["type"] == "text" and MARKER_PREFIX in content[-1]["text"], "no truncation marker"
assert len(content[0]["text"].encode()) <= 5000, "kept text exceeded the byte budget"
assert "kept" in content[-1]["text"] and "of 200000 bytes" in content[-1]["text"], content[-1]["text"]

# item-count cap: many small items, marker explains the drop
many = {"result": {"content": [{"type": "text", "text": "i%d" % i} for i in range(50)]}}
out2, stats2 = cap_response(many, max_bytes=65536, max_items=5)
assert stats2["truncated"] and stats2["kept_items"] == 5 and stats2["total_items"] == 50, stats2
assert "5 of 50 items" in out2["result"]["content"][-1]["text"], out2["result"]["content"][-1]["text"]

# small result passes through untouched
small = {"result": {"content": [{"type": "text", "text": "short"}]}}
out3, stats3 = cap_response(small)
assert not stats3["truncated"] and out3["result"]["content"] == small["result"]["content"], "small result was altered"

# non-tool-result responses are never touched
err = {"jsonrpc": "2.0", "id": 9, "error": {"code": -1, "message": "nope"}}
out4, _ = cap_response(err)
assert out4 == err, "error response was altered"

# the byte budget covers the WHOLE serialized result: a small content array
# with an oversized structuredContent is capped too, not passed through
huge_structured = {"result": {"content": [{"type": "text", "text": "ok"}],
                              "structuredContent": {"data": "y" * 90000}}}
out5, stats5 = cap_response(huge_structured, max_bytes=5000)
assert stats5["truncated"], "oversized structuredContent passed uncapped"
assert "structuredContent" not in out5["result"], "structuredContent was not dropped"
marker5 = out5["result"]["content"][-1]["text"]
assert MARKER_PREFIX in marker5 and "structuredContent" in marker5, marker5
assert len(json.dumps(out5["result"], ensure_ascii=False).encode("utf-8")) <= 5000, "result still over budget"

# an oversized non-text field besides content/structuredContent cannot hide
# either: the whole serialized result is what the budget measures
fat_meta = {"result": {"content": [{"type": "text", "text": "ok"}],
                       "structuredContent": {"blob": "z" * 90000}, "isError": False}}
out6, stats6 = cap_response(fat_meta, max_bytes=5000)
assert len(json.dumps(out6["result"], ensure_ascii=False).encode("utf-8")) <= 5200, out6["result"]

# a JSON-RPC batch is capped element by element, not skipped
batch = [{"jsonrpc": "2.0", "id": 1,
          "result": {"content": [{"type": "text", "text": "x" * 90000}]}},
         {"jsonrpc": "2.0", "id": 2,
          "result": {"content": [{"type": "text", "text": "fine"}]}}]
outb, statsb = cap_response(batch, max_bytes=5000)
assert isinstance(outb, list) and len(outb) == 2, "batch shape changed"
assert statsb["truncated"] and statsb["total_items"] == 2 and statsb["kept_items"] == 2, statsb
assert MARKER_PREFIX in outb[0]["result"]["content"][-1]["text"], "first batch element uncapped"
assert outb[1]["result"]["content"][0]["text"] == "fine", "second batch element altered"

# a single batch element that is an error reply still passes through
outb2, statsb2 = cap_response([{"jsonrpc": "2.0", "id": 3, "error": {"code": -1}}], max_bytes=5000)
assert outb2 == [{"jsonrpc": "2.0", "id": 3, "error": {"code": -1}}] and not statsb2["truncated"]

# mid-text truncation is safe for multi-byte text: no mojibake, budget honored
mb = "\u4e2d" * 4000  # CJK char, 3 UTF-8 bytes each -> 12000 bytes
outm, statsm = cap_response({"result": {"content": [{"type": "text", "text": mb}]}}, max_bytes=3000)
kept_text = outm["result"]["content"][0]["text"]
assert statsm["truncated"] and MARKER_PREFIX in outm["result"]["content"][-1]["text"]
assert len(kept_text.encode("utf-8")) <= 3000, "multi-byte text over budget"
assert "\ufffd" not in kept_text, "truncation emitted a replacement character"
assert kept_text.encode("utf-8").decode("utf-8") == kept_text, "truncated text is not valid UTF-8"

# an oversized non-text item is dropped whole (never byte-sliced into garbage)
res = {"result": {"content": [{"type": "resource",
                               "resource": {"uri": "x://y", "text": "z" * 90000}}]}}
outr, statsr = cap_response(res, max_bytes=5000)
assert statsr["truncated"] and MARKER_PREFIX in outr["result"]["content"][-1]["text"], "non-text item uncapped"

# SSE body split into JSON-RPC messages
sse = 'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}\n\nevent: message\ndata: {"jsonrpc":"2.0","method":"notifications/x"}\n\n'
msgs = parse_sse(sse)
assert len(msgs) == 2 and msgs[0]["id"] == 1 and msgs[1]["method"] == "notifications/x", msgs
print("PROBE-OK")
'@, [Text.UTF8Encoding]::new($false))
        $capOut = & $python $probe ($cloud -replace '\\', '/') 2>&1 | Out-String
        Report 'context_cap bounds the whole result: content, structuredContent, batches, multi-byte safe' `
            ($LASTEXITCODE -eq 0 -and $capOut -match 'PROBE-OK') $capOut
        # Second review: no field (_meta and the like) may carry an uncapped
        # payload, and the size is measured as written on the wire.
        $wireProbe = Join-Path $cloud 'samples\context_cap_probe.py'
        $wireOut = & $python $wireProbe ($cloud -replace '\\', '/') 2>&1 | Out-String
        Report 'context_cap holds the wire size under the cap for every field, non-ASCII text and batches' `
            ($LASTEXITCODE -eq 0 -and $wireOut -match '(?m)^ALL OK' -and $wireOut -notmatch 'BAD') $wireOut
    } finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 3. benchmark harness produces the table from the sample logs ------------
$samples = Join-Path $cloud 'samples\benchmark'
$benchOut = & $hostExe -NoProfile -File (Join-Path $cloud 'Measure-RepoWiseBenefit.ps1') `
    -TaskListPath (Join-Path $samples 'tasks.json') `
    -NativeLogPath (Join-Path $samples 'native.bench.txt') `
    -RepoWiseLogPath (Join-Path $samples 'repowise.bench.txt') 2>&1 | Out-String
$benchOk = $LASTEXITCODE -eq 0
Report 'benchmark harness exits 0 on the sample logs' $benchOk $benchOut
Report 'benchmark table lists every task in the task list' `
    ($benchOut -match 't1-entry-point' -and $benchOut -match 't2-retry-policy' -and $benchOut -match 't3-config-load') $benchOut
Report 'benchmark table carries token totals including cached' `
    ($benchOut -match '48200' -and $benchOut -match '14300' -and $benchOut -match '12100' -and $benchOut -match '6200') $benchOut
Report 'benchmark table reports time-to-correct-file for both modes' `
    ($benchOut -match '181\.2' -and $benchOut -match '41\.5' -and $benchOut -match 'missed') $benchOut
Report 'benchmark table flags the stale-index run' `
    ($benchOut -match 'True' -and $benchOut -match 'stale index') $benchOut
Report 'benchmark table prints the totals row' `
    ($benchOut -match 'TOTAL: native tokens=149850  repowise tokens=46250') $benchOut

# --- 4. findings report -------------------------------------------------------
$findingsScratch = Join-Path ([IO.Path]::GetTempPath()) ('rwcloud-findings-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $findingsScratch | Out-Null
try {
    $outFile = Join-Path $findingsScratch 'findings.json'
    $samplesF = Join-Path $cloud 'samples\findings'
    $findOut = & $hostExe -NoProfile -File (Join-Path $cloud 'New-RepoWiseFindings.ps1') `
        -Repository 'example-repo-a' -Revision 'aaaa1111bbbb2222' -RepoWiseVersion '0.60.1' `
        -HealthPath (Join-Path $samplesF 'health.json') `
        -DeadCodePath (Join-Path $samplesF 'dead-code.json') `
        -RiskPath (Join-Path $samplesF 'risk.json') `
        -OutFile $outFile -IssueId 'SH-0000' 2>&1 | Out-String
    Report 'findings script exits 0 on the sample outputs' ($LASTEXITCODE -eq 0) $findOut
    $doc = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Report 'findings file records the repository and revision' `
        ($doc.repository -eq 'example-repo-a' -and $doc.revision -eq 'aaaa1111bbbb2222') ($doc | ConvertTo-Json -Compress)
    Report 'findings file carries reproducible evidence (command, sha256, itemCount per source)' `
        (@($doc.evidence).Count -eq 3 -and @($doc.evidence | Where-Object { $_.sha256 -match '^[0-9a-f]{64}$' -and $_.command -match '^repowise ' -and $_.itemCount -ge 1 }).Count -eq 3) ($doc.evidence | ConvertTo-Json -Compress)
    Report 'findings file normalizes items from all three sources' `
        (@($doc.findings).Count -eq 6 -and @($doc.findings | Where-Object { $_.source -eq 'dead-code' }).Count -eq 2) (@($doc.findings).Count.ToString())
    Report 'findings file records the cross-check issue id without evaluating it' `
        ($doc.crossCheck.issueId -eq 'SH-0000' -and $doc.crossCheck.evaluation -eq 'not-performed-read-only') ($doc.crossCheck | ConvertTo-Json -Compress)
} finally {
    Remove-Item -LiteralPath $findingsScratch -Recurse -Force -ErrorAction SilentlyContinue
}
$findingsSrc = [IO.File]::ReadAllText((Join-Path $cloud 'New-RepoWiseFindings.ps1'))
Report 'findings script holds no issue-tracker mutation surface (read-only by construction)' `
    ($findingsSrc -notmatch '(?i)\bgh\b|save_issue|New-Issue|Set-Issue|Close-Issue|linear|jira|CreateItem|Invoke-RestMethod|Invoke-WebRequest') 'mutation surface found'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($script:reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $script:reported passed, 0 failed" -ForegroundColor Green
exit 0
