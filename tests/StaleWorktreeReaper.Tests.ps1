$reaperPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Remove-StaleWorktrees.ps1'
$source = Get-Content -LiteralPath $reaperPath -Raw -Encoding UTF8

Describe 'Stale worktree reaper safety contract' {
    It 'never falls back to raw recursive deletion for a registered worktree' {
        $source | Should Not Match '(?m)\bRemove-Item\b'
    }

    It 'never forces git worktree removal' {
        $source | Should Not Match '(?i)worktree\s+remove\s+--force'
    }

    It 'does not prune Git metadata as a side effect of dry-run or removal' {
        $source | Should Not Match '(?i)worktree\s+prune(?!\s+--dry-run)'
    }

    It 'requires an exact approved path before apply can remove anything' {
        $source | Should Match '\$ApprovedPath'
        $source | Should Match '-Apply requires at least one -ApprovedPath'
    }

    It 'reports eligible and actually removed worktrees separately' {
        $source | Should Match '\$eligible'
        $source | Should Match 'eligible\s+=' 
        $source | Should Match 'removed\s+=' 
    }
}
