#Requires -Version 5.1
# Encryption: Unicode + DPAPI CurrentUser (same as mstsc / RedAndBlueEraser rdp-file-password-encryptor).
<#
.SYNOPSIS
    Writes username, DPAPI-encrypted password (password 51:b:), and prompt for credentials into an .rdp file.

.DESCRIPTION
    Edit the CONFIG section right after param(). Run as the same Windows user that opens the .rdp in mstsc.
    Do not commit a copy of this script with real secrets to git.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# CONFIG — edit here (plain text; insecure by design)
# =============================================================================
$RdpPath         = ''   # empty = same folder as this script, file Obsidian_RemoteApp_Workgroup.rdp
$RdpUsername     = ''   # e.g. 'SERVER\obsidian' or 'obsidian'
$RdpPassword     = ''
$RdpOutputPath   = ''   # empty = overwrite $RdpPath
$ForceOverwrite  = $true  # if $RdpOutputPath exists and differs from $RdpPath, overwrite without prompt
# =============================================================================

if ([string]::IsNullOrWhiteSpace($RdpPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Set $RdpPath in CONFIG, or run: powershell -File .\Patch-RdpPassword.ps1'
    }
    $RdpPath = Join-Path $PSScriptRoot 'Obsidian_RemoteApp_Workgroup.rdp'
}
if (-not (Test-Path -LiteralPath $RdpPath -PathType Leaf)) { throw "RDP file not found: $RdpPath" }
if ([string]::IsNullOrWhiteSpace($RdpUsername)) { throw 'Set $RdpUsername in CONFIG.' }
if ($null -eq $RdpPassword -or [string]::IsNullOrWhiteSpace([string]$RdpPassword)) { throw 'Set $RdpPassword in CONFIG.' }

$Path = $RdpPath
if ([string]::IsNullOrWhiteSpace($RdpOutputPath)) {
    $OutputPath = $Path
}
else {
    $OutputPath = $RdpOutputPath
}

if (-not $ForceOverwrite -and (Test-Path -LiteralPath $OutputPath) -and ($OutputPath -ne $Path)) {
    if (-not $PSCmdlet.ShouldContinue("File already exists: $OutputPath", 'Overwrite?')) {
        throw 'Cancelled.'
    }
}

Add-Type -AssemblyName System.Security

function Protect-RdpPasswordBlob {
    param([string] $Plain)
    $bytes = [Text.Encoding]::Unicode.GetBytes($Plain)
    $protected = [Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    -join ($protected | ForEach-Object { $_.ToString('X2') })
}

function Get-FileEncodingForRdp {
    param([string] $LiteralPath)
    $fs = [IO.File]::OpenRead($LiteralPath)
    try {
        $bom = New-Object byte[] 4
        $n = $fs.Read($bom, 0, 4)
        if ($n -ge 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) {
            return [Text.Encoding]::Unicode
        }
        if ($n -ge 3 -and $bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) {
            return New-Object System.Text.UTF8Encoding $true
        }
    }
    finally { $fs.Dispose() }
    New-Object System.Text.UTF8Encoding $false
}

$hex = Protect-RdpPasswordBlob -Plain ([string]$RdpPassword)
$RdpPassword = $null

$enc = Get-FileEncodingForRdp -LiteralPath $Path
$lines = [IO.File]::ReadAllLines($Path, $enc)

$usernameLine = "username:s:$RdpUsername"
$passwordLine = "password 51:b:$hex"
$replacedUsername = $false
$replacedPassword = $false
$replacedPrompt = $false

$newLines = for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^(?i)\s*username\s*:') {
        $replacedUsername = $true
        $usernameLine
    }
    elseif ($line -match '^(?i)\s*password\s*51\s*:\s*b\s*:') {
        $replacedPassword = $true
        $passwordLine
    }
    elseif ($line -match '^(?i)\s*prompt\s+for\s+credentials\s*:') {
        $replacedPrompt = $true
        'prompt for credentials:i:0'
    }
    else {
        $line
    }
}

if (-not $replacedUsername) {
    $insertAt = -1
    for ($j = 0; $j -lt $newLines.Count; $j++) {
        if ($newLines[$j] -match '^(?i)\s*full address\s*:') {
            $insertAt = $j + 1
            break
        }
    }
    if ($insertAt -lt 0) { $insertAt = 0 }
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in $newLines) { [void]$list.Add($x) }
    if ($insertAt -gt $list.Count) { $insertAt = $list.Count }
    $list.Insert($insertAt, $usernameLine)
    $newLines = $list.ToArray()
}

if (-not $replacedPassword) {
    $unameIdx = -1
    for ($j = 0; $j -lt $newLines.Count; $j++) {
        if ($newLines[$j] -match '^(?i)\s*username\s*:') {
            $unameIdx = $j
            break
        }
    }
    if ($unameIdx -lt 0) { throw 'Internal error: no username line in output.' }
    $insertAt = $unameIdx + 1
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in $newLines) { [void]$list.Add($x) }
    if ($insertAt -gt $list.Count) { $insertAt = $list.Count }
    $list.Insert($insertAt, $passwordLine)
    $newLines = $list.ToArray()
}

if (-not $replacedPrompt) {
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in $newLines) { [void]$list.Add($x) }
    [void]$list.Add('prompt for credentials:i:0')
    $newLines = $list.ToArray()
}

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write .rdp with username and encrypted password')) {
    [IO.File]::WriteAllLines($OutputPath, [string[]]@($newLines), $enc)
    Write-Host "Done: $OutputPath"
    Write-Host 'Open with mstsc as the same Windows user that ran this script.'
}
