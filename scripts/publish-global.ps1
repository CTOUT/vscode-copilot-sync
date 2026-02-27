<#
Publish Global Copilot Resources

Publishes two categories of resources from the local awesome-copilot cache to
global locations where they are always available across all workspaces/repos:

  Agents  --> VS Code user agents folder (available in Copilot Chat globally)
              Default: %APPDATA%\Code\User\prompts\
              Strategy: symlink / junction first, then file-copy fallback

  Skills  --> Personal skills directory (loaded on-demand by VS Code Agent mode / Copilot CLI)
              Default: ~\.copilot\skills\
              Strategy: mirror each skill subdirectory (incremental copy)

Usage:
  # Publish both agents and skills (default)
  .\publish-global.ps1

  # Publish only agents
  .\publish-global.ps1 -SkipSkills

  # Publish only skills
  .\publish-global.ps1 -SkipAgents

  # Override VS Code agents folder (e.g. for a named profile)
  .\publish-global.ps1 -AgentsTarget "$env:APPDATA\Code\User\profiles\MyProfile\prompts"

  # Dry run - show what would happen
  .\publish-global.ps1 -DryRun

Notes:
  - Agents are linked (not copied) where possible so that sync updates are
    immediately reflected in VS Code without re-running this script.
  - Skills are copied individually so each skill directory is self-contained
    under ~/.copilot/skills/<skill-name>/.
  - Run after sync-awesome-copilot.ps1, or add to the scheduled task via
    install-scheduled-task.ps1.
#>
[CmdletBinding()] param(
    [string]$SourceRoot   = "$HOME/.awesome-copilot",
    [string]$AgentsTarget = (Join-Path $env:APPDATA 'Code\User\prompts'),
    [string]$SkillsTarget = (Join-Path $HOME '.copilot\skills'),
    [switch]$SkipAgents,
    [switch]$SkipSkills,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

$AgentsSource = Join-Path $SourceRoot 'agents'
$SkillsSource = Join-Path $SourceRoot 'skills'

# ---------------------------------------------------------------------------
# AGENTS
# ---------------------------------------------------------------------------
if (-not $SkipAgents) {
    if (-not (Test-Path $AgentsSource)) {
        Log "Agents source not found: $AgentsSource (run sync-awesome-copilot.ps1 first)" 'WARN'
    }
    else {
        Log "Publishing agents: $AgentsSource --> $AgentsTarget"

        if ($DryRun) {
            Log "[DryRun] Would link/copy agents folder to $AgentsTarget"
        }
        else {
            # Attempt junction first (no elevation required on Windows), then symlink, then copy
            $linked = $false

            if (Test-Path $AgentsTarget) {
                $item = Get-Item $AgentsTarget -Force
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    Log "Agents already linked at $AgentsTarget - skipping"
                    $linked = $true
                }
                else {
                    # Exists as a real directory - update files in place rather than replacing
                    Log "Agents folder exists as real directory; updating files in place"
                    Get-ChildItem $AgentsSource -File | ForEach-Object {
                        $dest = Join-Path $AgentsTarget $_.Name
                        $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                        $dstHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { $null }
                        if ($srcHash -ne $dstHash) {
                            Copy-Item $_.FullName $dest -Force
                            Log "  Updated: $($_.Name)"
                        }
                    }
                    $linked = $true
                }
            }

            if (-not $linked) {
                $parent = Split-Path $AgentsTarget -Parent
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

                try {
                    cmd /c mklink /J `"$AgentsTarget`" `"$AgentsSource`" | Out-Null
                    Log "Created junction: $AgentsTarget --> $AgentsSource"
                }
                catch {
                    Log "Junction failed ($($_.Exception.Message)); trying symlink" 'WARN'
                    try {
                        New-Item -ItemType SymbolicLink -Path $AgentsTarget -Target $AgentsSource -Force | Out-Null
                        Log "Created symlink: $AgentsTarget --> $AgentsSource"
                    }
                    catch {
                        Log "Symlink failed; copying files instead" 'WARN'
                        New-Item -ItemType Directory -Path $AgentsTarget -Force | Out-Null
                        Copy-Item (Join-Path $AgentsSource '*') $AgentsTarget -Force
                        Log "Copied agents to $AgentsTarget"
                    }
                }
            }
        }
        Log "Agents: done. Restart VS Code if agents do not appear immediately."
    }
}

# ---------------------------------------------------------------------------
# SKILLS
# ---------------------------------------------------------------------------
if (-not $SkipSkills) {
    if (-not (Test-Path $SkillsSource)) {
        Log "Skills source not found: $SkillsSource (run sync-awesome-copilot.ps1 first)" 'WARN'
    }
    else {
        Log "Publishing skills: $SkillsSource --> $SkillsTarget"

        if (-not $DryRun -and -not (Test-Path $SkillsTarget)) {
            New-Item -ItemType Directory -Path $SkillsTarget -Force | Out-Null
        }

        $added = 0; $updated = 0; $unchanged = 0

        Get-ChildItem $SkillsSource -Directory | ForEach-Object {
            $skillName = $_.Name
            $skillSrc  = $_.FullName
            $skillDest = Join-Path $SkillsTarget $skillName

            if ($DryRun) {
                Log "[DryRun] Would publish skill: $skillName"
                $added++
                return
            }

            if (-not (Test-Path $skillDest)) {
                New-Item -ItemType Directory -Path $skillDest -Force | Out-Null
            }

            Get-ChildItem $skillSrc -File -Recurse | ForEach-Object {
                $rel  = $_.FullName.Substring($skillSrc.Length).TrimStart('\','/')
                $dest = Join-Path $skillDest $rel
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

                $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                $dstHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { $null }
                if ($srcHash -ne $dstHash) {
                    Copy-Item $_.FullName $dest -Force
                    if ($dstHash) { $updated++ } else { $added++ }
                }
                else { $unchanged++ }
            }
        }

        Log "Skills: added=$added updated=$updated unchanged=$unchanged --> $SkillsTarget"

        # Ensure VS Code is configured to discover skills
        $vsCodeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
        if (Test-Path $vsCodeSettings) {
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
}

if ($DryRun) { Log "[DryRun] No changes made." }
else { Log "Global publish complete." }
