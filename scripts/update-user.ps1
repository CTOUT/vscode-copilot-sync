<#
Update Subscribed User-Level Copilot Resources

Reads the user subscription manifest (~/.awesome-copilot/user-subscriptions.json)
written by init-user.ps1, compares each subscribed resource against the local
awesome-copilot cache, and applies any upstream updates.

Handles all three user-level resource types:
  Agents       -- %APPDATA%\Code\User\prompts\*.agent.md
  Instructions -- %APPDATA%\Code\User\prompts\*.instructions.md
  Skills       -- ~/.copilot/skills/<skill-name>/

Usage:
  # Check for and apply updates (interactive prompt)
  .\update-user.ps1

  # Dry run — show what would be updated without writing any files
  .\update-user.ps1 -DryRun

  # Apply all updates without prompting
  .\update-user.ps1 -Force

  # Target a non-default VS Code installation (e.g. Insiders)
  .\update-user.ps1 -PromptsDir "$env:APPDATA\Code - Insiders\User\prompts"

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
    [string]$PromptsDir = "$env:APPDATA\Code\User\prompts",
    [string]$SkillsDir  = "$HOME/.copilot/skills",
    [switch]$Force,
    [switch]$DryRun
)

#region Initialisation
$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

function Get-DirHash([string]$DirPath) {
    $hashes   = Get-ChildItem $DirPath -Recurse -File | Sort-Object FullName |
                ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    $combined = $hashes -join '|'
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $stream   = [System.IO.MemoryStream]::new($bytes)
    return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}

#endregion # Initialisation

#region Load subscriptions
$ManifestPath = Join-Path $SourceRoot 'user-subscriptions.json'

if (-not (Test-Path $ManifestPath)) {
    Log "No user subscriptions manifest found — run init-user.ps1 first."
    exit 0
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$subs     = @($manifest.subscriptions)

if (-not $subs -or $subs.Count -eq 0) {
    exit 0
}

if (-not (Test-Path $SourceRoot)) {
    Log "Cache not found: $SourceRoot -- run sync-awesome-copilot.ps1 first" 'ERROR'; exit 1
}

Log "Checking $($subs.Count) user-level resource(s) for upstream changes..."
Log "Cache      : $SourceRoot"
Log "Prompts dir: $PromptsDir"
Log "Skills dir : $SkillsDir"

#endregion # Load subscriptions

#region Check for stale resources
$stale = [System.Collections.Generic.List[object]]::new()

foreach ($sub in $subs) {
    $sourcePath = Join-Path $SourceRoot $sub.sourceRelPath

    if (-not (Test-Path $sourcePath)) {
        Log "= Skipping $($sub.name) ($($sub.category)) — no longer in cache." 'WARN'
        continue
    }

    # Route destination by category: skills → SkillsDir, everything else → PromptsDir
    $destPath = if ($sub.type -eq 'directory') {
        Join-Path $SkillsDir $sub.dirName
    } else {
        Join-Path $PromptsDir $sub.fileName
    }

    if (-not (Test-Path $destPath)) {
        Log "= Skipping $($sub.name) ($($sub.category)) — removed from destination folder."
        continue
    }

    $currentHash = if ($sub.type -eq 'file') {
        (Get-FileHash $sourcePath -Algorithm SHA256).Hash
    } else {
        Get-DirHash $sourcePath
    }

    if ($currentHash -ne $sub.hashAtInstall) {
        $stale.Add([pscustomobject]@{
            Sub         = $sub
            SourcePath  = $sourcePath
            DestPath    = $destPath
            CurrentHash = $currentHash
        })
        Log "↑ Stale : $($sub.name) ($($sub.category))"
    } else {
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
            $destDir = Split-Path $item.DestPath -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $item.SourcePath $item.DestPath -Force
        } else {
            # Mirror all files from the source directory into the destination
            Get-ChildItem $item.SourcePath -File -Recurse | ForEach-Object {
                $rel     = $_.FullName.Substring($item.SourcePath.Length).TrimStart('\', '/')
                $dest    = Join-Path $item.DestPath $rel
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item $_.FullName $dest -Force
            }
        }
        $sub | Add-Member -NotePropertyName 'hashAtInstall' -NotePropertyValue $item.CurrentHash       -Force
        $sub | Add-Member -NotePropertyName 'installedAt'   -NotePropertyValue (Get-Date).ToString('o') -Force
        Log "✓ Updated: $($sub.name) ($($sub.category))"
        $updated++
    } catch {
        Log "Failed to update $($sub.name): $_" 'ERROR'
    }
}

# Persist updated hashes back to the manifest
$manifest | Add-Member -NotePropertyName 'updatedAt'     -NotePropertyValue (Get-Date).ToString('o') -Force
$manifest | Add-Member -NotePropertyName 'subscriptions' -NotePropertyValue $subs                    -Force
$manifest | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath -Encoding UTF8

Write-Host ""
Log "$updated user-level resource(s) updated." 'SUCCESS'
Log "Prompts : $PromptsDir"
Log "Skills  : $SkillsDir"

#endregion # Apply updates
