#Requires -Version 5.1
<#
Publishable output: replace the invoking user's home directory with '~'.

Used by scripts/AgentHubDemoProfile.ps1 so a recorded terminal never shows
the operator's account name. Only a whole path segment is replaced:
C:\Users\Alex becomes ~ inside C:\Users\Alex\.claude, but C:\Users\Alexis is
left alone. Matching is case-insensitive (Windows paths) and covers both the
backslash and forward-slash spellings of the same home.
#>

function Format-AgentHubDisplayText {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$HomePath = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME })
    )
    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrWhiteSpace($HomePath)) { return $Text }
    $homeRoot = $HomePath.TrimEnd('\', '/')
    $result = $Text
    foreach ($spelling in @($homeRoot, ($homeRoot -replace '\\', '/')) | Select-Object -Unique) {
        $pattern = '(?im)' + [regex]::Escape($spelling) + '(?=[\\/]|$|[\s"''`,;:)\]])'
        $result = [regex]::Replace($result, $pattern, '~')
    }
    return $result
}
