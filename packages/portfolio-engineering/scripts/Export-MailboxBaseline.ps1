# Read-only operational evidence. Run inside an authenticated Exchange Online
# session; this script neither connects nor requests or changes credentials.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Mailboxes,
    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'AgentHub\portfolio-engineering\operational\exchange')
)
$ErrorActionPreference = 'Stop'
foreach ($address in $Mailboxes) {
    if ($address -notmatch '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { throw 'Each target must be an explicit SMTP address.' }
}
$privateRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'AgentHub\portfolio-engineering\operational'))
$destination = [IO.Path]::GetFullPath($OutputRoot)
if (-not $destination.StartsWith($privateRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Mailbox evidence must remain below the separate AgentHub operational directory.'
}
Import-Module ExchangeOnlineManagement -ErrorAction Stop
$connections = @(Get-ConnectionInformation | Where-Object State -eq 'Connected')
if ($connections.Count -ne 1) { throw 'Exactly one authenticated Exchange Online connection is required; mailbox state was not checked.' }
foreach ($name in @('Get-Recipient', 'Get-Mailbox', 'Get-EXOMailboxPermission', 'Get-RecipientPermission', 'Get-InboxRule', 'Get-RemoteDomain', 'Get-TransportRule', 'Get-HostedOutboundSpamFilterPolicy', 'Get-HostedOutboundSpamFilterRule')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required read-only command unavailable: $name" }
}
function Read-Section([scriptblock]$Read) {
    try { return @{ status = 'checked'; values = @(& $Read) } }
    catch { return @{ status = 'blocked'; error = $_.Exception.Message } }
}
$records = foreach ($address in ($Mailboxes | Sort-Object -Unique)) {
    @{
        address = $address
        recipient = Read-Section { Get-Recipient -Identity $address | Select-Object Identity, ExternalDirectoryObjectId, RecipientTypeDetails, PrimarySmtpAddress, EmailAddresses }
        mailbox = Read-Section { Get-Mailbox -Identity $address | Select-Object Identity, ExchangeGuid, RecipientTypeDetails, DisplayName, PrimarySmtpAddress, EmailAddresses, ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward, HiddenFromAddressListsEnabled }
        fullAccess = Read-Section { Get-EXOMailboxPermission -Identity $address | Select-Object User, AccessRights, Deny, IsInherited }
        sendAs = Read-Section { Get-RecipientPermission -Identity $address | Select-Object Trustee, AccessRights, IsInherited, AccessControlType }
        inboxRules = Read-Section { Get-InboxRule -Mailbox $address -IncludeHidden | Select-Object Identity, Name, Enabled, Priority, ForwardTo, ForwardAsAttachmentTo, RedirectTo, DeleteMessage, StopProcessingRules, Description }
    }
}
$report = @{
    schemaVersion = 1
    observedAt = [DateTimeOffset]::UtcNow.ToString('o')
    stage = 'read-only-inventory'
    mailboxes = @($records)
    remoteDomains = Read-Section { Get-RemoteDomain | Select-Object Identity, DomainName, AutoForwardEnabled }
    transportRules = Read-Section { Get-TransportRule | Select-Object Identity, Name, State, Mode, Priority, Description }
    outboundPolicies = Read-Section { Get-HostedOutboundSpamFilterPolicy | Select-Object Identity, Name, AutoForwardingMode }
    outboundRules = Read-Section { Get-HostedOutboundSpamFilterRule | Select-Object Identity, Name, State, Priority, HostedOutboundSpamFilterPolicy, From, FromMemberOf, SenderDomainIs, ExceptIfFrom, ExceptIfFromMemberOf, ExceptIfSenderDomainIs }
    limitations = @('Group-derived permissions require membership expansion.', 'Gmail forwarding and filters require separate readback.', 'Folder visibility is not an Exchange permission inventory.', 'Blocked sections are not empty or absent configuration.')
}
# Reject links at every existing directory boundary before writing operational data.
$cursor = $destination
while ($cursor) {
    if (Test-Path -LiteralPath $cursor) {
        $item = Get-Item -LiteralPath $cursor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Operational output may not use linked directories.' }
    }
    $parent = Split-Path -Parent $cursor
    if ($parent -eq $cursor) { break }
    $cursor = $parent
}
[IO.Directory]::CreateDirectory($destination) | Out-Null
$file = Join-Path $destination ('exchange-' + [Guid]::NewGuid().ToString('N') + '.json')
$stream = [IO.File]::Open($file, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($report | ConvertTo-Json -Depth 16))
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Output $file
