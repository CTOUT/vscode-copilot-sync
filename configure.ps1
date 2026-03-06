<#
Configure Copilot Resources

Main entry point for all Copilot resource management operations.
Chains the scripts in the correct order:

  1. sync-awesome-copilot.ps1       -- fetch latest from github/awesome-copilot
  2. publish-global.ps1             -- publish agents + skills globally
  3. init-repo.ps1                  -- (prompted) per-repo .github/ setup
  4. install/uninstall-scheduled-task.ps1  -- (explicit) automate sync + publish

Usage:
  # Full interactive run: sync + publish + prompt for init-repo
  .\configure.ps1

  # Sync + publish only (skip init-repo prompt)
  .\configure.ps1 -SkipInit

  # Re-publish only (cache already up to date)
  .\configure.ps1 -SkipSync -SkipInit

  # Install scheduled task (sync every 4h + publish globally)
  .\configure.ps1 -SkipInit -InstallTask

  # Install task with custom interval
  .\configure.ps1 -SkipInit -InstallTask -Every "2h"

  # Uninstall scheduled task
  .\configure.ps1 -SkipSync -SkipPublish -SkipInit -UninstallTask

  # Preview without writing any files
  .\configure.ps1 -DryRun
#>
[CmdletBinding()] param(
    [switch]$SkipSync,
    [switch]$SkipPublish,
    [switch]$SkipInit,
    [switch]$InstallTask,
    [switch]$UninstallTask,
    [string]$Every = '4h',      # Interval for -InstallTask (e.g. 4h, 30m)
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

if ($InstallTask -and $UninstallTask) {
    Log "-InstallTask and -UninstallTask cannot both be set." 'ERROR'; exit 1
}
# Task management implies no interactive repo setup
if ($InstallTask -or $UninstallTask) { $SkipInit = $true }

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
    $subscriptionsFile = Join-Path (Get-Location).Path '.github\.copilot-subscriptions.json'
    if (Test-Path $subscriptionsFile) {
        Step "Check for updates to subscribed repo resources"
        Write-Host "  Subscriptions found. Check for upstream updates to .github/ resources?" -ForegroundColor Yellow
        Write-Host "  [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
        $updateAnswer = (Read-Host).Trim()
        if ($updateAnswer -match '^[Yy]') {
            $updateArgs = @{}
            if ($DryRun) { $updateArgs['DryRun'] = $true }
            & (Join-Path $ScriptDir 'update-repo.ps1') @updateArgs
        } else {
            Log "Update check skipped."
        }
    }

    Step "Init repo"
    Write-Host "  Add agents/instructions/hooks/workflows/skills to .github/ in the current repo?" -ForegroundColor Yellow
    Write-Host "  [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
    $answer = (Read-Host).Trim()
    if ($answer -match '^[Yy]') {
        $initArgs = @{}
        if ($DryRun) { $initArgs['DryRun'] = $true }
        & (Join-Path $ScriptDir 'init-repo.ps1') @initArgs
    } else {
        Log "init-repo skipped."
    }
}

#endregion # Step 3

#region Step 4 — Scheduled task
if ($InstallTask) {
    Step "Install scheduled task"
    if ($DryRun) {
        Log "[DryRun] Would install scheduled task (every $Every): sync + publish-global"
    } else {
        $taskArgs = @{ Every = $Every }
        $taskName = 'AwesomeCopilotSync'
        $proceed  = $true
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Log "Scheduled task '$taskName' already exists." 'WARN'
            Write-Host "  Overwrite existing task? [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
            if ((Read-Host).Trim() -match '^[Yy]') {
                $taskArgs['Force'] = $true
            } else {
                Log "Task install skipped."
                $proceed = $false
            }
        }
        if ($proceed) { & (Join-Path $ScriptDir 'install-scheduled-task.ps1') @taskArgs }
    }
}

if ($UninstallTask) {
    Step "Uninstall scheduled task"
    if ($DryRun) {
        Log "[DryRun] Would uninstall scheduled task"
    } else {
        & (Join-Path $ScriptDir 'uninstall-scheduled-task.ps1')
    }
}

#endregion # Step 4

Write-Host ""
Log "Done." 'SUCCESS'
