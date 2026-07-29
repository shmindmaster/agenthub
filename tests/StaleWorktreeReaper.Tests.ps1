$global:AgentHubReaperPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Remove-StaleWorktrees.ps1'
$global:AgentHubReaperSource = Get-Content -LiteralPath $global:AgentHubReaperPath -Raw -Encoding UTF8
$global:AgentHubWorktreePolicyLibraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\WorktreeRootPolicy.ps1'

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

    It 'discovers orphan candidates only at C:\wt\{repository}\{task} depth' {
        Test-Path -LiteralPath $global:AgentHubWorktreePolicyLibraryPath -PathType Leaf | Should -BeTrue
        . $global:AgentHubWorktreePolicyLibraryPath

        $root = Join-Path $TestDrive 'wt'
        $repositoryContainer = Join-Path $root 'sample-repo'
        $taskWorktree = Join-Path $repositoryContainer 'sample-task'
        $directRepositoryGit = Join-Path $repositoryContainer '.git'
        $taskGit = Join-Path $taskWorktree '.git'
        New-Item -ItemType Directory -Path $taskWorktree -Force | Out-Null
        'repository metadata marker' | Set-Content -LiteralPath $directRepositoryGit -Encoding UTF8
        'gitdir: synthetic' | Set-Content -LiteralPath $taskGit -Encoding UTF8

        $orphans = @(Get-AgentHubOrphanedWorktreeDirectories -ConfiguredRoot $root -KnownPaths @{})
        $orphans | Should -Contain ([System.IO.Path]::GetFullPath($taskWorktree))
        $orphans | Should -Not -Contain ([System.IO.Path]::GetFullPath($repositoryContainer))
    }
}
