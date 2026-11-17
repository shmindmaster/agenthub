# Retained-host authority contract (Linear SH-4409 / SH-4669; Kiro retired 2026-11-17,
# leaving five). Every registered host carries one fleetRole. Exactly the product
# families listed below are retained; other hosts are pending retirement, retired, or non-agent surfaces.
# Returns error strings; an empty list means the registry satisfies the contract.
$script:AhRetainedHostIds = @('claude', 'codex', 'opencode', 'kilo', 'factory')
$script:AhFleetRoles = @('retained', 'companion', 'editor', 'terminal-preserved', 'pending-retirement', 'retired')

function Test-AgentFleetRoles {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Agents)
  $errors = [Collections.Generic.List[string]]::new()
  $active = @($Agents.activeAgents)
  $inactive = @($Agents.inactiveAgents)
  $all = @($active) + @($inactive)
  $ids = @($all | ForEach-Object { [string]$_.id })
  foreach ($h in $all) {
    $id = [string]$h.id
    $role = [string]$h.fleetRole
    if ([string]::IsNullOrWhiteSpace($role)) { $errors.Add("host has no fleetRole: $id"); continue }
    if ($role -notin $script:AhFleetRoles) { $errors.Add("host has unknown fleetRole '$role': $id"); continue }
    if ($role -eq 'retained' -and $id -notin $script:AhRetainedHostIds) { $errors.Add("host is retained but is not one of the six families: $id") }
    if ($role -ne 'retained' -and $id -in $script:AhRetainedHostIds) { $errors.Add("one of the six families is not marked retained: $id") }
    if ($role -eq 'companion') {
      $owner = [string]$h.fleetOwner
      if ($owner -notin $script:AhRetainedHostIds) { $errors.Add("companion surface must name a retained fleetOwner: $id -> '$owner'") }
    }
  }
  foreach ($r in $script:AhRetainedHostIds) {
    if ($r -notin $ids) { $errors.Add("retained host missing from registry: $r") }
  }
  return $errors.ToArray()
}

