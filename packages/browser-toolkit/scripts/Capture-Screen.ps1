#Requires -Version 5.1
<#
.SYNOPSIS
    Write a Windows desktop or window screenshot/recording under the AgentHub
    evidence root.

.DESCRIPTION
    Canonical capture helper for desktop-evidence. Default destination:

        %LOCALAPPDATA%\AgentHub\evidence\<task>\

    That directory is the fleet evidence root. Do not write capture blobs into
    a git repository.

    screenshot  - one PNG (FFmpeg gdigrab, or .NET CopyFromScreen if FFmpeg is
                  absent and no -Title is set)
    record      - MP4 via FFmpeg gdigrab (required)
    resolve-dir - create and print the task evidence directory
    windows     - list processes that currently have a main window title

.PARAMETER Action
    screenshot, record, resolve-dir, or windows.

.PARAMETER Task
    Lowercase slug used as the evidence subdirectory. Required except for
    windows.

.PARAMETER Title
    Optional exact window title for FFmpeg gdigrab title= capture.

.PARAMETER Duration
    Recording length in seconds. Default 15, maximum 120.

.PARAMETER Name
    Optional file stem (screenshot.png / recording.mp4 when omitted).

.PARAMETER EvidenceRoot
    Override the evidence root. Tests pass a scratch directory here.

.PARAMETER Output
    Exact output file path. When omitted, a file is named under the task
    directory.

.PARAMETER PlanOnly
    Print the JSON plan and do not capture.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('screenshot', 'record', 'resolve-dir', 'windows')]
    [string]$Action,

    [string]$Task,

    [string]$Title,

    [ValidateRange(1, 120)]
    [int]$Duration = 15,

    [string]$Name,

    [string]$EvidenceRoot,

    [string]$Output,

    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-EvidenceTaskSlug {
    param([Parameter(Mandatory)][string]$Value)
    $component = $Value.Trim()
    $windowsReservedName = '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)'
    if ($component -cne $Value -or $component -cne $component.ToLowerInvariant() -or
        $component -notmatch '^[a-z0-9](?:[a-z0-9._-]*[a-z0-9_-])?$' -or
        $component -match $windowsReservedName) {
        throw "Task must be an unambiguous lowercase slug using only a-z, 0-9, dot, underscore, or hyphen. Got '$Value'."
    }
    return $component
}

function Get-DefaultEvidenceRoot {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($local)) {
        throw 'LocalApplicationData is empty; cannot resolve the evidence root.'
    }
    return Join-Path $local 'AgentHub\evidence'
}

function Invoke-NativeCaptureCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Get-FfmpegPath {
    $cmd = Get-Command -Name ffmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return [string]$cmd.Source }
    return $null
}

function ConvertTo-GdiGrabInput {
    param([string]$WindowTitle)
    if ([string]::IsNullOrWhiteSpace($WindowTitle)) { return 'desktop' }
    if ($WindowTitle -match '[\"\r\n]') {
        throw 'Title must not contain quotes or newlines.'
    }
    return ('title={0}' -f $WindowTitle)
}

function Write-PngFromScreen {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = $null
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        $bmp.Dispose()
    }
}

function Write-PlanJson {
    param([Parameter(Mandatory)]$Plan)
    $json = $Plan | ConvertTo-Json -Compress -Depth 6
    Write-Output $json
}

if ($Action -eq 'windows') {
    $rows = @(
        Get-Process |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.MainWindowTitle) } |
            Sort-Object MainWindowTitle |
            ForEach-Object {
                [ordered]@{
                    process = $_.ProcessName
                    pid     = $_.Id
                    title   = [string]$_.MainWindowTitle
                }
            }
    )
    Write-PlanJson -Plan ([ordered]@{
            action  = 'windows'
            windows = $rows
        })
    return
}

if ([string]::IsNullOrWhiteSpace($Task)) {
    throw 'Task is required for screenshot, record, and resolve-dir.'
}
$taskSlug = ConvertTo-EvidenceTaskSlug -Value $Task
$root = if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    Get-DefaultEvidenceRoot
} else {
    [IO.Path]::GetFullPath($EvidenceRoot)
}
$taskDir = Join-Path $root $taskSlug

if ($Action -eq 'resolve-dir') {
    if (-not $PlanOnly) {
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
    }
    Write-PlanJson -Plan ([ordered]@{
            action      = 'resolve-dir'
            task        = $taskSlug
            directory   = $taskDir
            executed    = (-not $PlanOnly.IsPresent)
        })
    return
}

$extension = if ($Action -eq 'record') { '.mp4' } else { '.png' }
$stem = if ([string]::IsNullOrWhiteSpace($Name)) { $Action } else { $Name.Trim() }
if ($stem -notmatch '^[a-z0-9][a-z0-9._-]*$') {
    throw "Name must be a lowercase file stem. Got '$Name'."
}
$outputPath = if ([string]::IsNullOrWhiteSpace($Output)) {
    Join-Path $taskDir ($stem + $extension)
} else {
    [IO.Path]::GetFullPath($Output)
}

$grabInput = ConvertTo-GdiGrabInput -WindowTitle $Title
$ffmpeg = Get-FfmpegPath
$ffmpegArgs = $null
if ($Action -eq 'screenshot') {
    $ffmpegArgs = @(
        '-y', '-hide_banner', '-loglevel', 'error',
        '-f', 'gdigrab', '-framerate', '1', '-i', $grabInput,
        '-frames:v', '1',
        $outputPath
    )
} else {
    $ffmpegArgs = @(
        '-y', '-hide_banner', '-loglevel', 'error',
        '-f', 'gdigrab', '-framerate', '30', '-i', $grabInput,
        '-t', ([string]$Duration),
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
        $outputPath
    )
}

$plan = [ordered]@{
    action     = $Action
    task       = $taskSlug
    directory  = $taskDir
    output     = $outputPath
    input      = $grabInput
    duration   = if ($Action -eq 'record') { $Duration } else { $null }
    ffmpeg     = $ffmpeg
    command    = if ($ffmpeg) { @($ffmpeg) + $ffmpegArgs } else { @('ffmpeg') + $ffmpegArgs }
    fallback   = $null
    executed   = $false
}

if ($PlanOnly) {
    Write-PlanJson -Plan $plan
    return
}

New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null

if ($Action -eq 'record') {
    if (-not $ffmpeg) {
        throw 'FFmpeg is required for record and was not found on PATH.'
    }
    $run = Invoke-NativeCaptureCommand -FilePath $ffmpeg -Arguments $ffmpegArgs
    if ($run.ExitCode -ne 0) {
        throw "FFmpeg record failed (exit $($run.ExitCode)): $($run.Output -join ' ')"
    }
} elseif ($ffmpeg) {
    $run = Invoke-NativeCaptureCommand -FilePath $ffmpeg -Arguments $ffmpegArgs
    if ($run.ExitCode -ne 0) {
        throw "FFmpeg screenshot failed (exit $($run.ExitCode)): $($run.Output -join ' ')"
    }
} else {
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        throw 'FFmpeg is required for window-title screenshots and was not found on PATH.'
    }
    Write-PngFromScreen -Path $outputPath
    $plan.fallback = 'dotnet-copyfromscreen'
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    throw "Capture finished but '$outputPath' was not created."
}
$plan.executed = $true
$plan.length = (Get-Item -LiteralPath $outputPath).Length
Write-PlanJson -Plan $plan
