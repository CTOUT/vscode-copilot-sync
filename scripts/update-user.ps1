<#
Update Subscribed User-Level Copilot Resources

Reads the user subscription manifest (~/.awesome-copilot/user-subscriptions.json)
written by init-user.ps1, compares each subscribed resource against the local
awesome-copilot cache, and applies any upstream updates.

Handles all three user-level resource types:
    Agents       -- ~/.copilot/agents/*.agent.md
    Instructions -- ~/.copilot/instructions/*.instructions.md
  Skills       -- ~/.copilot/skills/<skill-name>/

    Files from the former prompts directory are migrated automatically before
    subscription checks. Conflicting destination files are never overwritten.

Usage:
  # Check for and apply updates (interactive prompt)
  .\update-user.ps1

  # Dry run — show what would be updated without writing any files
  .\update-user.ps1 -DryRun

  # Apply all updates without prompting
  .\update-user.ps1 -Force

    # Override the user-level agent and instruction directories
    .\update-user.ps1 -AgentsDir "$HOME/.copilot/agents" -InstructionsDir "$HOME/.copilot/instructions"

  # Only check/update specific categories
  .\update-user.ps1 -Category "agents,skills"
  .\update-user.ps1 -Category "instructions" -DryRun

Notes:
  - Only resources present in user-subscriptions.json are checked.
    Run init-user.ps1 to add new subscriptions.
  - Resources whose destination file/directory has been manually deleted are
    skipped (treated as intentionally removed).
  - The subscription manifest is updated with new hashes after each successful update.
  - Requires the local awesome-copilot cache (~/.awesome-copilot/). Run
    sync-awesome-copilot.ps1 first if the cache is stale.
#>
[CmdletBinding()] param(
    [string]$SourceRoot = "$HOME/.awesome-copilot",
    [string]$PromptsDir = '',
    [string]$AgentsDir = '',
    [string]$InstructionsDir = '',
    [string]$SkillsDir = '',
    [switch]$Force,
    [switch]$DryRun,
    [string]$Category = ''  # Comma-separated categories to check (e.g. 'agents,skills'); all checked if omitted
)

#region Initialisation
$ErrorActionPreference = 'Stop'

$CommonLib = Join-Path $PSScriptRoot 'lib\Common.ps1'
if (Test-Path $CommonLib) { . $CommonLib }

if ($PromptsDir) {
    if (-not $AgentsDir) { $AgentsDir = $PromptsDir }
    if (-not $InstructionsDir) { $InstructionsDir = $PromptsDir }
}
if (-not $AgentsDir) { $AgentsDir = Resolve-AgentsDirectory }
if (-not $InstructionsDir) { $InstructionsDir = Resolve-InstructionsDirectory }
$LegacyPromptsDir = Resolve-LegacyPromptsDirectory
if (-not $SkillsDir) { $SkillsDir = Resolve-SkillsDirectory }

$migrationResult = Invoke-LegacyUserCustomizationMigration `
    -LegacyDirectory $LegacyPromptsDir `
    -AgentsDirectory $AgentsDir `
    -InstructionsDirectory $InstructionsDir `
    -DryRun:$DryRun
Write-LegacyUserCustomizationMigrationSummary -Result $migrationResult -DryRun:$DryRun

#endregion # Initialisation

#region Load subscriptions
$ManifestPath = Join-Path $SourceRoot 'user-subscriptions.json'

if (-not (Test-Path $ManifestPath)) {
    Log "No user subscriptions manifest found — run init-user.ps1 first."
    exit 0
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$subs = @($manifest.subscriptions)

if (-not $subs -or $subs.Count -eq 0) {
    exit 0
}

if ($Category) {
    $wantedCats = @($Category.ToLower() -split '\s*,\s*' | Where-Object { $_ -ne '' })
    $subs = @($subs | Where-Object { $_.category.ToLower() -in $wantedCats })
    if ($subs.Count -eq 0) {
        Log "No subscriptions match category filter: $Category"
        exit 0
    }
}

if (-not (Test-Path $SourceRoot)) {
    Log "Cache not found: $SourceRoot -- run sync-awesome-copilot.ps1 first" 'ERROR'; exit 1
}

Log "Checking $($subs.Count) user-level resource(s) for upstream changes..."
Log "Cache      : $SourceRoot"
Log "Agents dir : $AgentsDir"
Log "Instr. dir : $InstructionsDir"
Log "Skills dir : $SkillsDir"

#endregion # Load subscriptions

#region Check for stale resources
$stale = [System.Collections.Generic.List[object]]::new()

foreach ($sub in $subs) {
    $allowedCategories = @('agents', 'instructions', 'skills')
    if ($sub.category -notin $allowedCategories) {
        Log "Skipping subscription with unsupported category '$($sub.category)' for '$($sub.name)'." 'ERROR'
        continue
    }
    $expectedType = if ($sub.category -eq 'skills') { 'directory' } else { 'file' }
    if ($sub.type -ne $expectedType) {
        Log "Skipping subscription with unsupported type '$($sub.type)' for category '$($sub.category)'." 'ERROR'
        continue
    }

    $sourceCategoryRoot = Join-Path $SourceRoot $sub.category
    $sourcePath = Join-Path $SourceRoot $sub.sourceRelPath
    try {
        Assert-PathWithin -Path $sourceCategoryRoot -ParentDirectory $SourceRoot
        Assert-PathWithin -Path $sourcePath -ParentDirectory $sourceCategoryRoot
    }
    catch {
        Log "Skipping subscription with an invalid cache path ('$($sub.sourceRelPath)'): $_" 'ERROR'
        continue
    }

    if (-not (Test-Path $sourcePath)) {
        Log "= Skipping $($sub.name) ($($sub.category)) — no longer in cache." 'WARN'
        continue
    }

    # Resolve subscriptions to the current Copilot harness locations.
    if ($sub.type -eq 'directory') {
        $destPath = Join-Path $SkillsDir $sub.dirName
        $destRoot = $SkillsDir
    }
    else {
        $destRoot = if ($sub.category -eq 'agents') { $AgentsDir } else { $InstructionsDir }
        $destPath = Join-Path $destRoot $sub.fileName
    }

    if (-not (Test-Path $destPath)) {
        Log "= Skipping $($sub.name) ($($sub.category)) — removed from destination folder."
        continue
    }

    $currentHash = if ($sub.type -eq 'file') {
        (Get-FileHash $sourcePath -Algorithm SHA256).Hash
    }
    else {
        Get-DirHash $sourcePath
    }

    if ($currentHash -ne $sub.hashAtInstall) {
        $stale.Add([pscustomobject]@{
                Sub         = $sub
                SourcePath  = $sourcePath
                DestPath    = $destPath
                DestRoot    = $destRoot
                CurrentHash = $currentHash
            })
        Log "↑ Stale : $($sub.name) ($($sub.category))"
    }
    else {
        Log "= Current: $($sub.name) ($($sub.category))"
    }
}

#endregion # Check for stale resources

#region Apply updates
if ($stale.Count -eq 0) {
    Write-Host ""
    Log "All $($subs.Count) user-level resource(s) are up to date." 'SUCCESS'
    exit 0
}

Write-Host ""
Log "$($stale.Count) user-level resource(s) have upstream updates available." 'WARN'

if ($DryRun) {
    Log "[DryRun] Re-run without -DryRun to apply updates." 'WARN'
    exit 0
}

if (-not $Force) {
    Write-Host ""
    Write-Host "  Apply all $($stale.Count) update(s) to user-level resources? [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
    $answer = (Read-Host).Trim()
    if ($answer -notmatch '^[Yy]') {
        Log "Update skipped."
        exit 0
    }
}

$updated = 0
foreach ($item in $stale) {
    $sub = $item.Sub
    try {
        if ($sub.type -eq 'file') {
            Assert-PathWithin -Path $item.DestPath -ParentDirectory $item.DestRoot
            $destDir = Split-Path $item.DestPath -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $item.SourcePath $item.DestPath -Force
        }
        else {
            Assert-PathWithin -Path $item.DestPath -ParentDirectory $item.DestRoot
            # Mirror all files from the source directory into the destination
            Get-ChildItem $item.SourcePath -File -Recurse | ForEach-Object {
                $rel = $_.FullName.Substring($item.SourcePath.Length).TrimStart('\', '/')
                $dest = Join-Path $item.DestPath $rel
                Assert-PathWithin -Path $dest -ParentDirectory $item.DestPath
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item $_.FullName $dest -Force
            }
        }
        $sub | Add-Member -NotePropertyName 'hashAtInstall' -NotePropertyValue $item.CurrentHash       -Force
        $sub | Add-Member -NotePropertyName 'installedAt'   -NotePropertyValue (Get-Date).ToString('o') -Force
        Log "✓ Updated: $($sub.name) ($($sub.category))"
        $updated++
    }
    catch {
        Log "Failed to update $($sub.name): $_" 'ERROR'
    }
}

# Persist updated hashes back to the manifest
$manifest | Add-Member -NotePropertyName 'updatedAt'     -NotePropertyValue (Get-Date).ToString('o') -Force
$manifest | Add-Member -NotePropertyName 'subscriptions' -NotePropertyValue $subs                    -Force
$manifest | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath -Encoding UTF8

Write-Host ""
Log "$updated user-level resource(s) updated." 'SUCCESS'
Log "Agents  : $AgentsDir"
Log "Instr.  : $InstructionsDir"
Log "Skills  : $SkillsDir"

#endregion # Apply updates
