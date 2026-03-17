<#
Configure Copilot Resources

Main entry point for all Copilot resource management operations.
Chains the scripts in the correct order:

  1. sync-awesome-copilot.ps1   -- fetch latest from github/awesome-copilot
  2. publish-global.ps1         -- publish agents + skills globally
  3. init-repo.ps1              -- (prompted) per-repo .github/ setup

Usage:
  # Full interactive run: sync + publish + prompt for init-repo
  .\configure.ps1

  # Sync + publish only (skip init-repo prompt)
  .\configure.ps1 -SkipInit

  # Re-publish only (cache already up to date)
  .\configure.ps1 -SkipSync -SkipInit

  # Preview without writing any files
  .\configure.ps1 -DryRun

  # Init a specific repo (not the current working directory)
  .\configure.ps1 -SkipSync -SkipPublish -RepoPath "C:\Projects\my-app"

  # Remove installed .github/ resources from the current repo
  .\configure.ps1 -Uninstall
#>
[CmdletBinding()] param(
    [switch]$SkipSync,
    [switch]$SkipPublish,
    [switch]$SkipInit,
    [switch]$Uninstall,     # Remove installed .github/ resources via init-repo -Uninstall
    [string]$RepoPath = (Get-Location).Path,
    [switch]$DryRun
)

#region Initialisation
$ErrorActionPreference = 'Stop'
$ScriptDir = Join-Path $PSScriptRoot 'scripts'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

function Step($label) {
    Write-Host ""
    Write-Host "  ── $label ──" -ForegroundColor Magenta
    Write-Host ""
}

# Show cache state
$manifest = "$HOME\.awesome-copilot\manifest.json"
if (Test-Path $manifest) {
    try {
        $m = Get-Content $manifest -Raw | ConvertFrom-Json
        Log "Cache last synced: $($m.fetchedAt)   Items: $($m.items.Count)"
    } catch {}
} else {
    Log "No local cache found — sync will download everything fresh." 'WARN'
}

if ($Uninstall) { $SkipSync = $true; $SkipPublish = $true }

#endregion # Initialisation

#region Step 1 — Sync
if (-not $SkipSync) {
    Step "Sync from github/awesome-copilot"
    $syncArgs = @{}
    if ($DryRun) { $syncArgs['Plan'] = $true }
    & (Join-Path $ScriptDir 'sync-awesome-copilot.ps1') @syncArgs
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "Sync failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
}

#endregion # Step 1

#region Step 2 — Publish globally
if (-not $SkipPublish) {
    Step "Publish agents + skills globally"
    $publishArgs = @{}
    if ($DryRun) { $publishArgs['DryRun'] = $true }
    & (Join-Path $ScriptDir 'publish-global.ps1') @publishArgs
}

#endregion # Step 2

#region Step 3 — Init repo
if (-not $SkipInit) {
    # If a subscriptions manifest exists for the current repo, offer to check for updates first
    $subscriptionsFile = Join-Path $RepoPath '.github\.copilot-subscriptions.json'
    if (Test-Path $subscriptionsFile) {
        Step "Check for updates to subscribed repo resources"
        $updateArgs = @{}
        if ($DryRun)   { $updateArgs['DryRun']   = $true }
        if ($RepoPath) { $updateArgs['RepoPath'] = $RepoPath }
        & (Join-Path $ScriptDir 'update-repo.ps1') @updateArgs
    }

    Step "Init repo"
    $initPrompt = if ($Uninstall) { "Remove agents/instructions/hooks/workflows/skills from .github/?" } else { "Add agents/instructions/hooks/workflows/skills to .github/ in the current repo?" }
    Write-Host "  $initPrompt" -ForegroundColor Yellow
    Write-Host "  [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
    $answer = (Read-Host).Trim()
    if ($answer -match '^[Yy]') {
        $initArgs = @{}
        if ($DryRun)     { $initArgs['DryRun']    = $true }
        if ($RepoPath)   { $initArgs['RepoPath']  = $RepoPath }
        if ($Uninstall)  { $initArgs['Uninstall'] = $true }
        & (Join-Path $ScriptDir 'init-repo.ps1') @initArgs
    } else {
        Log "init-repo skipped."
    }
}

#endregion # Step 3

Write-Host ""
Log "Done." 'SUCCESS'
