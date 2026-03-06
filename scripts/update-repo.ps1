<#
Update Subscribed Per-Repo Copilot Resources

Reads the subscription manifest (.github/.copilot-subscriptions.json) written by
init-repo.ps1, compares each subscribed resource against the local awesome-copilot
cache, and applies any upstream updates.

Resources are updated in place — the same files/directories that were originally
installed to .github/ are refreshed from the cache.

Usage:
  # Check for and apply updates (interactive prompt)
  .\update-repo.ps1

  # Dry run — show what would be updated without writing any files
  .\update-repo.ps1 -DryRun

  # Apply all updates without prompting
  .\update-repo.ps1 -Force

  # Check a specific repo
  .\update-repo.ps1 -RepoPath "C:\Projects\my-app"

Notes:
  - Only resources present in .github/.copilot-subscriptions.json are checked.
    Run init-repo.ps1 to add new subscriptions.
  - Resources whose destination file/directory has been manually deleted are
    skipped (treated as intentionally removed).
  - The subscription manifest is updated with new hashes after each successful update.
  - Requires the local awesome-copilot cache (~/.awesome-copilot/). Run
    sync-awesome-copilot.ps1 first if the cache is stale.
#>
[CmdletBinding()] param(
    [string]$RepoPath   = (Get-Location).Path,
    [string]$SourceRoot = "$HOME/.awesome-copilot",
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
    $hashes = Get-ChildItem $DirPath -Recurse -File |
              Sort-Object FullName |
              ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    $combined = $hashes -join '|'
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $stream   = [System.IO.MemoryStream]::new($bytes)
    return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}

#endregion # Initialisation

#region Load subscriptions
if (-not (Test-Path $RepoPath)) {
    Log "Repo path not found: $RepoPath" 'ERROR'; exit 1
}
$RepoPath = Resolve-Path $RepoPath | Select-Object -ExpandProperty Path

$GithubDir    = Join-Path $RepoPath '.github'
$ManifestPath = Join-Path $GithubDir '.copilot-subscriptions.json'

if (-not (Test-Path $ManifestPath)) {
    Log "No subscriptions manifest found: $ManifestPath" 'WARN'
    Log "Run init-repo.ps1 first to subscribe to resources."
    exit 0
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$subs     = @($manifest.subscriptions)

if (-not $subs -or $subs.Count -eq 0) {
    Log "No subscriptions recorded in manifest." 'WARN'
    exit 0
}

if (-not (Test-Path $SourceRoot)) {
    Log "Cache not found: $SourceRoot -- run sync-awesome-copilot.ps1 first" 'ERROR'; exit 1
}

Log "Checking $($subs.Count) subscribed resource(s) for upstream changes..."
Log "Cache : $SourceRoot"
Log "Repo  : $RepoPath"

#endregion # Load subscriptions

#region Check for stale resources
$stale = [System.Collections.Generic.List[object]]::new()

foreach ($sub in $subs) {
    $sourcePath = Join-Path $SourceRoot $sub.sourceRelPath

    if (-not (Test-Path $sourcePath)) {
        Log "= Skipping $($sub.name) ($($sub.category)) — no longer in cache." 'WARN'
        continue
    }

    # Destination: .github/<sourceRelPath>  e.g. .github/agents/foo.agent.md
    $destPath = Join-Path $GithubDir $sub.sourceRelPath

    if (-not (Test-Path $destPath)) {
        Log "= Skipping $($sub.name) ($($sub.category)) — destination removed locally."
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
    Log "All $($subs.Count) subscribed resource(s) are up to date." 'SUCCESS'
    exit 0
}

Write-Host ""
Log "$($stale.Count) resource(s) have upstream updates available." 'WARN'

if ($DryRun) {
    Log "[DryRun] Re-run without -DryRun to apply updates." 'WARN'
    exit 0
}

if (-not $Force) {
    Write-Host ""
    Write-Host "  Apply all $($stale.Count) update(s)? [Y] Yes   [N] No (default): " -NoNewline -ForegroundColor Yellow
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

        $sub | Add-Member -NotePropertyName 'hashAtInstall' -NotePropertyValue $item.CurrentHash  -Force
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
Log "$updated resource(s) updated in $GithubDir" 'SUCCESS'
Log "Tip: commit .github/ to share the updates with your team."

#endregion # Apply updates
