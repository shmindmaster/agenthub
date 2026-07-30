#Requires -Version 5.1

Describe 'Product Demo Studio host-native role adapters' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:syncScript = Join-Path $repoRoot `
            'scripts\Sync-ProductDemoStudioHostAdapters.ps1'
        $script:powerShell = if ($PSVersionTable.PSVersion.Major -lt 6) {
            (Get-Command powershell.exe -ErrorAction Stop).Source
        } else {
            (Get-Command pwsh -ErrorAction Stop).Source
        }
    }

    It 'generates 13 roles and mechanically restricts the six read-only roles' {
        $profile = Join-Path $TestDrive 'profile'
        & $powerShell -NoLogo -NoProfile -NonInteractive -File $syncScript `
            -RegistryRoot $repoRoot -UserProfile $profile
        $LASTEXITCODE | Should -Be 0

        $codex = @(Get-ChildItem (Join-Path $profile '.codex\agents') `
            -Filter 'product-demo-studio-*.toml' -File)
        $openCode = @(Get-ChildItem (Join-Path $profile '.config\opencode\agents') `
            -Filter 'product-demo-studio-*.md' -File)
        $gemini = @(Get-ChildItem (
            Join-Path $profile '.gemini\extensions\agenthub-product-demo-studio\agents'
        ) -Filter 'product-demo-studio-*.md' -File)
        $antigravity = @(Get-ChildItem (
            Join-Path $profile '.gemini\antigravity-cli\plugins\product-demo-studio\agents'
        ) -Filter 'product-demo-studio-*.md' -File)

        $codex.Count | Should -Be 13
        $openCode.Count | Should -Be 13
        $gemini.Count | Should -Be 13
        $antigravity.Count | Should -Be 13

        @($codex | Where-Object {
            (Get-Content $_.FullName -Raw) -match
                '(?m)^sandbox_mode\s*=\s*"read-only"\s*$'
        }).Count | Should -Be 6
        @($openCode | Where-Object {
            $raw = Get-Content $_.FullName -Raw
            $raw -match '(?m)^\s+edit:\s*deny\s*$' -and
                $raw -match '(?m)^\s+bash:\s*deny\s*$'
        }).Count | Should -Be 6
        @($gemini | Where-Object {
            $raw = Get-Content $_.FullName -Raw
            $raw -notmatch '(?m)^\s+-\s+(?:write_file|replace|run_shell_command)\s*$'
        }).Count | Should -BeGreaterOrEqual 6
        @($antigravity | Where-Object {
            (Get-Content $_.FullName -Raw) -match
                '(?m)^commandExecutionPolicy:\s*off\s*$'
        }).Count | Should -Be 6

        $qwenManifestVersion = (
            Get-Content (Join-Path $repoRoot `
                'packages\handoff-plugins\plugins\product-demo-studio\.codex-plugin\plugin.json') `
                -Raw | ConvertFrom-Json
        ).version
        $geminiManifest = Get-Content (
            Join-Path $profile `
                '.gemini\extensions\agenthub-product-demo-studio\gemini-extension.json'
        ) -Raw | ConvertFrom-Json
        $geminiManifest.version | Should -Be $qwenManifestVersion
    }
}
