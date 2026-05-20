<#
Configure Copilot Resources

Main entry point for all Copilot resource management operations.
Chains the scripts in the correct order:

  1. sync-awesome-copilot.ps1   -- fetch latest from github/awesome-copilot
  2. init-user.ps1              -- (prompted) user-level agents → %APPDATA%\Code\User\prompts\
  3. init-repo.ps1              -- (prompted) per-repo .github/ setup

Usage:
  # Full interactive run: sync + prompt for both steps
  .\configure.ps1

  # Sync + prompt for user and repo pickers
  .\configure.ps1 -Install

  # Sync + go straight to pickers without prompting — use -Scope to target a specific scope
  .\configure.ps1 -Install -Scope repo   # repo only, no prompt
  .\configure.ps1 -Install -Scope user   # user only, no prompt
  .\configure.ps1 -Install -Scope both   # both, no prompts

  # Sync only (skip repo setup)
  .\configure.ps1 -SkipInit

  # Preview without writing any files
  .\configure.ps1 -DryRun

  # Init a specific repo (not the current working directory)
  .\configure.ps1 -SkipSync -RepoPath "C:\Projects\my-app"

  # Remove installed resources — use -Scope to target a specific scope
  .\configure.ps1 -Uninstall              # removes both user + repo
  .\configure.ps1 -Uninstall -Scope repo  # repo .github/ only
  .\configure.ps1 -Uninstall -Scope user  # user-level only

  # Skip a specific step
  .\configure.ps1 -SkipUser
  .\configure.ps1 -SkipInit
#>
[CmdletBinding()] param(
    [switch]$SkipSync,
    [switch]$SkipInit,
    [switch]$SkipUser,      # Skip user-level resource setup
    [switch]$Install,       # Sync + run pickers; add -Scope to skip prompts and target a specific scope
    [switch]$Uninstall,     # Remove installed resources; add -Scope to target a specific scope
    [ValidateSet('repo', 'user', 'both')]
    [string]$Scope = '',    # Scope for -Install or -Uninstall: 'repo', 'user', or 'both'
    [switch]$User,          # Backwards-compat alias for: -Install -Scope user
    [Parameter(Position = 0)]
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

# -User backwards-compat alias: maps to -Install -Scope user
if ($User -and -not $Install) { $Install = $true; if ($Scope -eq '') { $Scope = 'user' } }

# -Scope restricts which steps run (applies to both -Install and -Uninstall)
if ($Scope -eq 'repo') { $SkipUser = $true }   # repo scope: skip user step entirely
if ($Scope -eq 'user') { $SkipInit = $true }   # user scope: skip repo step entirely
# 'both' or '' : neither step is skipped by scope

# -Uninstall never needs to sync
if ($Uninstall) { $SkipSync = $true }

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
    } else {
        # Manifest missing — check whether cache-origin files are already installed on disk.
        # This happens when resources were installed before v2.0.0 (which introduced the
        # manifest), or when configure.ps1 was run but the user-level step was skipped.
        # Auto-bootstrap registers all installed cache-origin files so update-user.ps1
        # can manage them going forward.
        $cacheRoot   = "$HOME\.awesome-copilot"
        $promptsDir  = [System.Environment]::GetFolderPath('ApplicationData') + '\Code\User\prompts'
        $skillsDir   = "$HOME\.copilot\skills"
        $untrackedCount = 0
        foreach ($cat in @('agents','instructions','skills')) {
            $cDir = Join-Path $cacheRoot $cat
            if (-not (Test-Path $cDir)) { continue }
            if ($cat -eq 'skills') {
                $untrackedCount += (Get-ChildItem $cDir -Directory -EA SilentlyContinue |
                    Where-Object { Test-Path (Join-Path $skillsDir $_.Name) }).Count
            } else {
                $pattern = if ($cat -eq 'agents') { '*.agent.md' } else { '*.instructions.md' }
                $untrackedCount += (Get-ChildItem $cDir -Filter $pattern -EA SilentlyContinue |
                    Where-Object { Test-Path (Join-Path $promptsDir $_.Name) }).Count
            }
        }
        if ($untrackedCount -gt 0) {
            Log "Detected $untrackedCount user-level resource(s) installed from the cache with no tracking record." 'WARN'
            Log "Bootstrapping user-subscriptions.json so update-user.ps1 can manage them..." 'WARN'
            $bootstrapArgs = @{ Bootstrap = $true }
            if ($DryRun) { $bootstrapArgs['DryRun'] = $true }
            & (Join-Path $ScriptDir 'init-user.ps1') @bootstrapArgs
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "Bootstrap failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
            # Reload count so the update step fires on next configure run
            if (Test-Path $userManifestFile) {
                $userSubCount = try { (@((Get-Content $userManifestFile -Raw | ConvertFrom-Json).subscriptions)).Count } catch { 0 }
            }
        }
    }

    Step "User-level resources (agents, instructions & skills — available in all repos)"
    if ($Uninstall -or ($Install -and $Scope -in @('user','both'))) {
        # Uninstall (always explicit) or install scoped to user/both: skip the Y/N prompt
        $userArgs = @{}
        if ($DryRun)      { $userArgs['DryRun']    = $true }
        if ($Uninstall)   { $userArgs['Uninstall'] = $true }
        & (Join-Path $ScriptDir 'init-user.ps1') @userArgs
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "init-user failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
    } else {
        Write-Host "  Add/update user-level resources (agents, instructions & skills)?" -ForegroundColor Yellow
        Write-Host "  These are available in ALL repos — no .github/ needed." -ForegroundColor DarkGray
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
    $doRepoUninstall = [bool]$Uninstall
    if ($doRepoUninstall -and $subCount -eq 0) {
        Log "Nothing to uninstall — no subscriptions recorded for this repo."
    } elseif ($doRepoUninstall -or ($Install -and $Scope -in @('repo','both'))) {
        # Uninstall (always explicit) or install scoped to repo/both: skip the Y/N prompt
        $initArgs = @{}
        if ($DryRun)           { $initArgs['DryRun']    = $true }
        if ($RepoPath)         { $initArgs['RepoPath']  = $RepoPath }
        if ($doRepoUninstall)  { $initArgs['Uninstall'] = $true }
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
