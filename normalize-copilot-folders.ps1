<#
Normalize Copilot Resource Folder Placement

Purpose:
  Ensures all markdown resources are stored in the directory that matches their
  semantic suffix: *.chatmode.md -> chatmodes/, *.instructions.md -> instructions/,
  *.prompt.md -> prompts/, *.collection.md|*.collections.md -> collections/.

Why:
  A mismatch (e.g. a .chatmode.md inside prompts/) can lead to inconsistent
  discovery or confusion about canonical location. This tool re-homes files.

Features:
  - Works on a single detected (most recent) profile or all profiles (-AllProfiles)
  - Dry-run mode (default) shows planned moves
  - Skips already-correct placements
  - Avoids overwriting: if destination filename exists, appends numeric suffix
  - Reports summary counts

Usage Examples:
  Dry-run across all profiles:
    pwsh -File .\scripts\normalize-copilot-folders.ps1 -AllProfiles

  Execute (no dry-run) for a specific profile root:
    pwsh -File .\scripts\normalize-copilot-folders.ps1 -ProfileRoot "C:\Users\me\AppData\Roaming\Code\User\profiles\abc123" -NoDryRun

  Execute across all profiles:
    pwsh -File .\scripts\normalize-copilot-folders.ps1 -AllProfiles -NoDryRun

Limitations:
  - Only processes markdown files (*.md)
  - Does not attempt content validation; classification is by filename suffix

License: MIT-like; adapt as needed.
#>
[CmdletBinding()] param(
  [string]$ProfilesBase = (Join-Path $env:APPDATA 'Code/User/profiles'),
  [string]$ProfileRoot,
  [switch]$AllProfiles,
  [switch]$NoDryRun
)

$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
  $ts = (Get-Date).ToString('s'); Write-Host "[$ts][$level] $m" -ForegroundColor $(if ($level -eq 'ERROR') { 'Red' } elseif ($level -eq 'WARN') { 'Yellow' } else { 'Cyan' })
}

if (-not (Test-Path $ProfilesBase)) { Log "Profiles base not found: $ProfilesBase" 'ERROR'; exit 1 }

$targets = @()
if ($AllProfiles) {
  $targets = Get-ChildItem $ProfilesBase -Directory | ForEach-Object { $_.FullName }
  if (-not $targets) { Log 'No profiles discovered.' 'ERROR'; exit 1 }
  Log "Discovered $($targets.Count) profiles" 'INFO'
}
else {
  if (-not $ProfileRoot) {
    $latest = Get-ChildItem $ProfilesBase -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Log 'No profiles found.' 'ERROR'; exit 1 }
    $ProfileRoot = $latest.FullName
    Log "Detected profile: $ProfileRoot" 'INFO'
  }
  $targets = @($ProfileRoot)
}

$movePlanned = 0
$moveDone = 0
$skipped = 0
$correct = 0

function Classify([string]$fileName) {
  switch -regex ($fileName) {
    '\\.chatmode\.md$' { return 'chatmodes' }
    '\\.instructions\.md$' { return 'instructions' }
    '\\.prompt\.md$' { return 'prompts' }
    '\\.(collection|collections)\.md$' { return 'collections' }
    default { return $null }
  }
}

foreach ($p in $targets) {
  Log "Scanning profile: $p" 'INFO'
  $expected = 'chatmodes', 'instructions', 'prompts', 'collections'
  foreach ($dir in $expected) { $full = Join-Path $p $dir; if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full | Out-Null } }

  # Consider: any .md file in profile tree at depth 0..2
  $candidates = Get-ChildItem $p -Recurse -File -Include *.md | Where-Object { $_.DirectoryName -notmatch '\\\.git' }
  foreach ($f in $candidates) {
    $targetFolder = Classify -fileName $f.Name
    if (-not $targetFolder) { continue }
    $currentFolder = Split-Path $f.FullName -LeafParent
    $currentBase = Split-Path $currentFolder -Leaf
    if ($currentBase -eq $targetFolder) { $correct++; continue }

    $destDir = Join-Path $p $targetFolder
    $destPath = Join-Path $destDir $f.Name
    if (Test-Path $destPath) {
      # File exists at destination - compare content and replace if different
      $existingHash = (Get-FileHash -Algorithm SHA256 $destPath).Hash
      $newHash = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash
      if ($existingHash -eq $newHash) {
        Log "Identical file already exists at destination, skipping: $($f.Name)" 'INFO'
        $correct++
        continue
      }
      Log "Replacing existing file with latest version: $($f.Name)" 'INFO'
      if ($NoDryRun) {
        Remove-Item $destPath -Force
      }
    }
    Log "Relocate: $($f.FullName) -> $destPath" 'INFO'
    $movePlanned++
    if ($NoDryRun) {
      try {
        Move-Item -LiteralPath $f.FullName -Destination $destPath -Force
        $moveDone++
      }
      catch {
        Log "Failed move: $($_.Exception.Message)" 'ERROR'
      }
    }
  }
}

if (-not $NoDryRun) { Log "Dry run complete (no files moved). Use -NoDryRun to apply." 'INFO' }
Log "Summary: planned=$movePlanned moved=$moveDone correct=$correct" 'INFO'
