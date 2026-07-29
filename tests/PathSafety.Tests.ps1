Describe 'AgentHub write-path safety' {
    BeforeAll {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\PathSafety.ps1')
    }

    It 'rejects an empty write target' {
        { Assert-AgentHubSafeWritePath -Path '' -Purpose 'test fixture' } | Should -Throw
    }

    It 'rejects every drive root before a write can occur' {
        { Assert-AgentHubSafeWritePath -Path 'C:\' -Purpose 'test fixture' } | Should -Throw
        { Assert-AgentHubSafeWritePath -Path 'D:\' -Purpose 'test fixture' } | Should -Throw
    }

    It 'rejects an unapproved top-level C drive target' {
        { Assert-AgentHubSafeWritePath -Path 'C:\agenthub-fixture' -Purpose 'test fixture' } | Should -Throw
    }

    It 'rejects an extended-length device path that bypasses a top-level C drive check' {
        { Assert-AgentHubSafeWritePath -Path '\\?\C:\agenthub-fixture' -Purpose 'test fixture' } | Should -Throw
    }

    It 'permits C:\wt as the sole approved user-created top-level C drive target' {
        Assert-AgentHubSafeWritePath -Path 'C:\wt' -Purpose 'test fixture' |
            Should -Be 'C:\wt'
        { Assert-AgentHubSafeWritePath -Path 'C:\Repos' -Purpose 'test fixture' } | Should -Throw
    }

    It 'permits nested user and C:\wt worktree locations' {
        Assert-AgentHubSafeWritePath -Path 'C:\Users\Synthetic\AppData\Local\AgentHub\runtime' -Purpose 'test fixture' |
            Should -Be 'C:\Users\Synthetic\AppData\Local\AgentHub\runtime'
        Assert-AgentHubSafeWritePath -Path 'C:\wt\repo\task' -Purpose 'test fixture' |
            Should -Be 'C:\wt\repo\task'
    }
}

Describe 'Apply-FullAccessAgentProfile fixture safety' {
    BeforeAll {
        $profileScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Apply-FullAccessAgentProfile.ps1'
        $script:profileSource = Get-Content -LiteralPath $profileScript -Raw -Encoding UTF8
        $script:fixtureTestSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Apply-FullAccessAgentProfile.Tests.ps1') -Raw -Encoding UTF8
    }

    It 'guards the supplied user profile before profile writes' {
        $profileSource | Should -Match 'Assert-AgentHubSafeWritePath\s+-Path\s+\$UserProfile'
    }

    It 'uses an explicit safe fixture directory instead of Pester TestDrive' {
        $fixtureTestSource | Should -Match 'agenthub-profile-tests'
        $fixtureTestSource | Should -Not -Match '\$TestDrive'
    }
}

Describe 'AgentHub root-path validation' {
    BeforeAll {
        $validationScript = Join-Path $PSScriptRoot 'Validate-AgentEcosystem.ps1'
        $script:validationSource = Get-Content -LiteralPath $validationScript -Raw -Encoding UTF8
        $script:policySource = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\worktree-management-policy.md') -Raw -Encoding UTF8
    }

    It 'reports leaked root fixtures and the retired agent-fleet-ops user skill' {
        $script:validationSource | Should -Match 'forbidden-root:'
        $script:validationSource | Should -Match 'C:\\canonical-product-demo-studio'
        $script:validationSource | Should -Match "retired-skill:agent-fleet-ops"
        $script:validationSource | Should -Match '\.agents\\skills\\agent-fleet-ops'
    }

    It 'documents C:\wt as the sole user-created worktree root without mutating host settings' {
        $script:policySource | Should -Match 'sole approved user-created worktree root'
        $script:policySource | Should -Match 'C:\\wt\\<repo>\\<task>'
        $script:policySource | Should -Match 'must not replace the user setting'
    }
}
