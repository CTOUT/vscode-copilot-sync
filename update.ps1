<#
Interactive Update — Sync, Publish, and Initialise

Chains the three main scripts for interactive use:
  1. sync-awesome-copilot.ps1   -- fetch latest from github/awesome-copilot
  2. publish-global.ps1         -- publish agents + skills globally
  3. init-repo.ps1              -- (prompted) per-repo setup for .github/

Usage:
  # Full update: sync + publish + prompt for init-repo
  .\update.ps1

  # Skip sync (reuse existing cache, e.g. already ran today)
  .\update.ps1 -SkipSync

  # Skip sync and publish (init-repo only)
  .\update.ps1 -SkipSync -SkipPublish

  # Skip the init-repo prompt (sync + publish only)
  .\update.ps1 -SkipInit

  # Dry run throughout
  .\update.ps1 -DryRun
#>
[CmdletBinding()] param(
    [switch]$SkipSync,
    [switch]$SkipPublish,
    [switch]$SkipInit,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

function Step($n, $total, $label) {
    Write-Host ""
    Write-Host "  ── Step $n/$total : $label ──" -ForegroundColor Magenta
    Write-Host ""
}

$totalSteps = 3 - [int]$SkipSync.IsPresent - [int]$SkipPublish.IsPresent - [int]$SkipInit.IsPresent
$step = 0

# Show last sync info if cache exists
$manifest = "$HOME\.awesome-copilot\manifest.json"
if (Test-Path $manifest) {
    try {
        $m = Get-Content $manifest -Raw | ConvertFrom-Json
        Log "Cache last synced: $($m.fetchedAt)   Items: $($m.items.Count)"
    } catch {}
}

# ---------------------------------------------------------------------------
# STEP 1: Sync
# ---------------------------------------------------------------------------
if (-not $SkipSync) {
    $step++
    Step $step $totalSteps "Sync from github/awesome-copilot"
    $syncScript = Join-Path $ScriptDir 'sync-awesome-copilot.ps1'
    $syncArgs = @{}
    if ($DryRun) { $syncArgs['Plan'] = $true }
    & $syncScript @syncArgs
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "Sync failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
}

# ---------------------------------------------------------------------------
# STEP 2: Publish globally
# ---------------------------------------------------------------------------
if (-not $SkipPublish) {
    $step++
    Step $step $totalSteps "Publish agents + skills globally"
    $publishScript = Join-Path $ScriptDir 'publish-global.ps1'
    $publishArgs = @{}
    if ($DryRun) { $publishArgs['DryRun'] = $true }
    & $publishScript @publishArgs
}

# ---------------------------------------------------------------------------
# STEP 3: Init repo (prompted)
# ---------------------------------------------------------------------------
if (-not $SkipInit) {
    $step++
    Write-Host ""
    Write-Host "  ── Step $step/$totalSteps : Init repo (optional) ──" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Run init-repo.ps1 to add agents/instructions/hooks/workflows to .github/ in the current repo?" -ForegroundColor Yellow
    Write-Host "  [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
    $answer = (Read-Host).Trim()
    if ($answer -match '^[Yy]') {
        $initScript = Join-Path $ScriptDir 'init-repo.ps1'
        $initArgs = @{}
        if ($DryRun) { $initArgs['DryRun'] = $true }
        & $initScript @initArgs
    } else {
        Log "init-repo skipped."
    }
}

Write-Host ""
Log "Update complete." 'SUCCESS'
