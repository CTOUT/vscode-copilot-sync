<#
Configure Copilot Resources

Main entry point for all Copilot resource management operations.
Chains the scripts in the correct order:

  1. sync-awesome-copilot.ps1   -- fetch latest from github/awesome-copilot
  2. init-repo.ps1              -- (prompted) per-repo .github/ setup

Usage:
  # Full interactive run: sync + prompt for init-repo
  .\configure.ps1

  # Sync + go straight to install pickers (skip the Y/N prompt)
  .\configure.ps1 -Install

  # Sync only (skip repo setup)
  .\configure.ps1 -SkipInit

  # Preview without writing any files
  .\configure.ps1 -DryRun

  # Init a specific repo (not the current working directory)
  .\configure.ps1 -SkipSync -RepoPath "C:\Projects\my-app"

  # Remove installed .github/ resources from the current repo
  .\configure.ps1 -Uninstall
#>
[CmdletBinding()] param(
    [switch]$SkipSync,
    [switch]$SkipInit,
    [switch]$Install,       # Skip the Y/N prompt and go straight to init-repo pickers
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

if ($Uninstall) { $SkipSync = $true }
if ($Install)   { $SkipInit = $false }  # ensure -Install always runs init-repo

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

#region Step 2 — Init repo
if (-not $SkipInit) {
    # If a subscriptions manifest exists with entries, check for updates first
    $subscriptionsFile = Join-Path $RepoPath '.github\.copilot-subscriptions.json'
    $subCount = 0
    if (Test-Path $subscriptionsFile) {
        $subCount = try { (@((Get-Content $subscriptionsFile -Raw | ConvertFrom-Json).subscriptions)).Count } catch { 0 }
        if ($subCount -gt 0) {
            Step "Check for updates to subscribed repo resources"
            $updateArgs = @{}
            if ($DryRun)   { $updateArgs['DryRun']   = $true }
            if ($RepoPath) { $updateArgs['RepoPath'] = $RepoPath }
            & (Join-Path $ScriptDir 'update-repo.ps1') @updateArgs
        }
    }

    Step "Init repo"
    if ($Uninstall -and $subCount -eq 0) {
        Log "Nothing to uninstall — no subscriptions recorded for this repo."
    } elseif ($Install -or $Uninstall) {
        # -Install or -Uninstall: skip the Y/N prompt, run directly
        $initArgs = @{}
        if ($DryRun)    { $initArgs['DryRun']    = $true }
        if ($RepoPath)  { $initArgs['RepoPath']  = $RepoPath }
        if ($Uninstall) { $initArgs['Uninstall'] = $true }
        & (Join-Path $ScriptDir 'init-repo.ps1') @initArgs
    } else {
        Write-Host "  Add agents/instructions/hooks/workflows/skills to .github/ in the current repo?" -ForegroundColor Yellow
        Write-Host "  [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
        $answer = (Read-Host).Trim()
        if ($answer -match '^[Yy]') {
            $initArgs = @{}
            if ($DryRun)   { $initArgs['DryRun']   = $true }
            if ($RepoPath) { $initArgs['RepoPath'] = $RepoPath }
            & (Join-Path $ScriptDir 'init-repo.ps1') @initArgs
        } else {
            Log "init-repo skipped."
        }
    }
}

#endregion # Step 2

Write-Host ""
Log "Done." 'SUCCESS'
