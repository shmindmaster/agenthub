#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Get-ChildItem .\registry, .\profiles -Filter *.json -File -Recurse | ForEach-Object {
  Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
}

$forbidden = @(git ls-files | Where-Object {
  (Split-Path $_ -Leaf) -match '^(\.env|auth\.json|secrets?\.json|credentials?\.json)$' -or
  $_ -match '^(reports|state/cross-agent)/(?!README\.md$)'
})
if ($forbidden.Count) {
  throw "Forbidden runtime or secret-state files are tracked: $($forbidden -join ', ')"
}
