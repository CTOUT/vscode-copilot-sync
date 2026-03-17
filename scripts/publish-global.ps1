<#
Publish Global Copilot Resources

Publishes all resource categories from the local awesome-copilot cache to
global locations via junctions (no file duplication — always in sync with
the cache after a pull).

  Agents        --> %APPDATA%\Code\User\prompts\
  Skills        --> ~/.copilot/skills/
  Instructions  --> ~/.copilot/instructions/
  Hooks         --> ~/.copilot/hooks/
  Workflows     --> ~/.copilot/workflows/

Each category is linked (junction/symlink) so that running sync-awesome-copilot.ps1
immediately reflects everywhere — no re-publish needed after a cache update.

Usage:
  .\publish-global.ps1

  # Skip specific categories
  .\publish-global.ps1 -SkipSkills -SkipHooks

  # Override VS Code agents folder (e.g. for a named profile)
  .\publish-global.ps1 -AgentsTarget "$env:APPDATA\Code\User\profiles\MyProfile\prompts"

  # Dry run
  .\publish-global.ps1 -DryRun

Notes:
  - Existing real directories are replaced with a junction automatically.
  - Falls back to symlink, then full copy if junction creation fails.
#>
[CmdletBinding()] param(
    [string]$SourceRoot          = "$HOME/.awesome-copilot",
    [string]$AgentsTarget        = (Join-Path $env:APPDATA 'Code\User\prompts'),
    [string]$SkillsTarget        = (Join-Path $HOME '.copilot\skills'),
    [string]$InstructionsTarget  = (Join-Path $HOME '.copilot\instructions'),
    [string]$HooksTarget         = (Join-Path $HOME '.copilot\hooks'),
    [string]$WorkflowsTarget     = (Join-Path $HOME '.copilot\workflows'),
    [switch]$SkipAgents,
    [switch]$SkipSkills,
    [switch]$SkipInstructions,
    [switch]$SkipHooks,
    [switch]$SkipWorkflows,
    [switch]$DryRun
)

#region Initialisation
$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

#endregion # Initialisation

#region Junction helper
function Publish-Junction {
    param([string]$Category, [string]$Source, [string]$Target)

    if (-not (Test-Path $Source)) {
        Log "$Category source not found: $Source (run sync-awesome-copilot.ps1 first)" 'WARN'
        return
    }

    Log "Publishing $Category`: $Source --> $Target"

    if ($DryRun) {
        Log "[DryRun] Would link $Category to $Target"
        return
    }

    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Log "$Category already linked at $Target - skipping"
            return
        }
        # Real directory — remove so we can replace with a junction
        Log "Replacing existing $Category directory with junction..." 'WARN'
        Remove-Item $Target -Recurse -Force
    }

    $parent = Split-Path $Target -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    try {
        cmd /c mklink /J `"$Target`" `"$Source`" | Out-Null
        Log "Created junction: $Target --> $Source"
    }
    catch {
        Log "Junction failed ($($_.Exception.Message)); trying symlink" 'WARN'
        try {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
            Log "Created symlink: $Target --> $Source"
        }
        catch {
            Log "Symlink failed; copying files instead" 'WARN'
            New-Item -ItemType Directory -Path $Target -Force | Out-Null
            Copy-Item (Join-Path $Source '*') $Target -Recurse -Force
            Log "Copied $Category to $Target"
        }
    }
}

#endregion # Junction helper

if (-not $SkipAgents)       { Publish-Junction 'Agents'       (Join-Path $SourceRoot 'agents')       $AgentsTarget }
if (-not $SkipSkills)       { Publish-Junction 'Skills'       (Join-Path $SourceRoot 'skills')       $SkillsTarget }
if (-not $SkipInstructions) { Publish-Junction 'Instructions' (Join-Path $SourceRoot 'instructions') $InstructionsTarget }
if (-not $SkipHooks)        { Publish-Junction 'Hooks'        (Join-Path $SourceRoot 'hooks')        $HooksTarget }
if (-not $SkipWorkflows)    { Publish-Junction 'Workflows'    (Join-Path $SourceRoot 'workflows')    $WorkflowsTarget }

#region VS Code settings — ensure skills discovery is configured
if (-not $SkipSkills -and -not $DryRun) {
    $vsCodeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (-not (Test-Path $vsCodeSettings)) {
        Log "VS Code settings.json not found — skills discovery not configured. Open VS Code once then re-run." 'WARN'
    }
    else {
        try {
            $s = Get-Content $vsCodeSettings -Raw | ConvertFrom-Json
            $changed = $false
            if (-not $s.'chat.useAgentSkills') {
                $s | Add-Member -NotePropertyName 'chat.useAgentSkills' -NotePropertyValue $true -Force
                $changed = $true
            }
            $loc = '~/.copilot/skills/**'
            if (-not $s.'chat.agentSkillsLocations' -or -not $s.'chat.agentSkillsLocations'.$loc) {
                $locs = if ($s.'chat.agentSkillsLocations') { $s.'chat.agentSkillsLocations' } else { [pscustomobject]@{} }
                $locs | Add-Member -NotePropertyName $loc -NotePropertyValue $true -Force
                $s | Add-Member -NotePropertyName 'chat.agentSkillsLocations' -NotePropertyValue $locs -Force
                $changed = $true
            }
            if ($changed) {
                $s | ConvertTo-Json -Depth 5 | Set-Content $vsCodeSettings -Encoding UTF8
                Log "Configured chat.useAgentSkills and chat.agentSkillsLocations in VS Code settings"
            }
        }
        catch { Log "Could not update VS Code settings: $_" 'WARN' }
    }
}
#endregion # VS Code settings

if ($DryRun) { Log "[DryRun] No changes made." }
else { Log "Global publish complete." }

