<#
Configure Copilot Resources

Main entry point for all Copilot resource management operations.
Chains the scripts in the correct order:

  1. sync-awesome-copilot.ps1   -- fetch latest from github/awesome-copilot
  2. init-user.ps1              -- (prompted) user-level agents → %APPDATA%\Code\User\prompts\
  3. init-repo.ps1              -- (prompted) per-repo .github/ setup

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

  # Install user-level agents (available in all repos, stored in %APPDATA%\Code\User\prompts\)
  .\configure.ps1 -User

  # Skip the user-level step
  .\configure.ps1 -SkipUser

  # Remove installed user-level agents
  .\configure.ps1 -UninstallUser
#>
[CmdletBinding()] param(
    [switch]$SkipSync,
    [switch]$SkipInit,
    [switch]$SkipUser,      # Skip user-level resource setup
    [switch]$Install,       # Skip the Y/N prompt and go straight to init-repo pickers
    [switch]$Uninstall,     # Remove installed .github/ resources via init-repo -Uninstall
    [switch]$User,          # Skip the Y/N prompt and go straight to init-user pickers
    [switch]$UninstallUser, # Remove user-level resources via init-user -Uninstall
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

if ($Uninstall)     { $SkipSync = $true; $SkipUser = $true  }  # repo uninstall: skip sync + skip user-level prompt
if ($UninstallUser) { $SkipSync = $true; $SkipInit = $true  }  # user uninstall: skip sync + skip repo prompt
if ($Install)       { $SkipInit = $false }  # ensure -Install always runs init-repo
if ($User)          { $SkipUser = $false }  # ensure -User always runs init-user

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

#region Step 1.5 — User-level resources
if (-not $SkipUser) {
    # If user subscriptions exist, check for updates first
    $userManifestFile = "$HOME\.awesome-copilot\user-subscriptions.json"
    $userSubCount     = 0
    if (Test-Path $userManifestFile) {
        $userSubCount = try { (@((Get-Content $userManifestFile -Raw | ConvertFrom-Json).subscriptions)).Count } catch { 0 }
        if ($userSubCount -gt 0) {
            Step "Check for updates to user-level resources"
            $updateArgs = @{}
            if ($DryRun) { $updateArgs['DryRun'] = $true }
            & (Join-Path $ScriptDir 'update-user.ps1') @updateArgs
        }
    }

    Step "User-level agents (available in all repos)"
    if ($User -or $UninstallUser) {
        # -User or -UninstallUser: skip the Y/N prompt, run directly
        $userArgs = @{}
        if ($DryRun)        { $userArgs['DryRun']    = $true }
        if ($UninstallUser) { $userArgs['Uninstall'] = $true }
        & (Join-Path $ScriptDir 'init-user.ps1') @userArgs
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "init-user failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
    } else {
        Write-Host "  Add user-level agents to VS Code? (available in all repos — no .github/ needed)" -ForegroundColor Yellow
        Write-Host "  [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
        $answer = (Read-Host).Trim()
        if ($answer -match '^[Yy]') {
            $userArgs = @{}
            if ($DryRun) { $userArgs['DryRun'] = $true }
            & (Join-Path $ScriptDir 'init-user.ps1') @userArgs
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "init-user failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
        } else {
            Log "init-user skipped."
        }
    }
}

#endregion # Step 1.5

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
