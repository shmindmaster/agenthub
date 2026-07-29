$global:AgentHubReaperPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Remove-StaleWorktrees.ps1'
$global:AgentHubReaperSource = Get-Content -LiteralPath $global:AgentHubReaperPath -Raw -Encoding UTF8

Describe 'Stale worktree reaper safety contract' {
    It 'never falls back to raw recursive deletion for a registered worktree' {
        $global:AgentHubReaperSource | Should -Not -Match '(?m)\bRemove-Item\b'
    }

    It 'never forces git worktree removal' {
        $global:AgentHubReaperSource | Should -Not -Match '(?i)worktree\s+remove\s+--force'
    }

    It 'does not prune Git metadata as a side effect of dry-run or removal' {
        $global:AgentHubReaperSource | Should -Not -Match '(?i)worktree\s+prune(?!\s+--dry-run)'
    }

    It 'requires an exact approved path before apply can remove anything' {
        $global:AgentHubReaperSource | Should -Match '\$ApprovedPath'
        $global:AgentHubReaperSource | Should -Match '-Apply requires at least one -ApprovedPath'
    }

    It 'reports eligible and actually removed worktrees separately' {
        $global:AgentHubReaperSource | Should -Match '\$eligible'
        $global:AgentHubReaperSource | Should -Match 'eligible\s+='
        $global:AgentHubReaperSource | Should -Match 'removed\s+='
    }
}
