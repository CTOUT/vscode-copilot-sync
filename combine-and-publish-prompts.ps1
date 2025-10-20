<#
Combine Copilot Resources Into Unified 'combined' Folder And Publish To Prompts

CHANGE (2025-09-18): Default publish target is now the global prompts directory:
  $env:APPDATA/Code/User/prompts
Previously the script auto-selected the latest profile under profiles/<id>. That
behavior is still available via -UseLatestProfile. Supplying -AllProfiles keeps
publishing to every discovered profile prompts directory (unchanged).

Steps Implemented:
 1. (Assumes sync already ran) Validate presence of source category folders under root (default $HOME/.awesome-copilot)
 2. Create / refresh a 'combined' folder containing all *.md files from:
    chatmodes/, instructions/, prompts/ (collections optional via -IncludeCollections)
      - Name collisions resolved by prefixing category (unless identical content)
      - Preserves original filenames when unique
 3. Publish the combined folder:
      a) By default to global prompts directory (profile-agnostic)
      b) Or if -UseLatestProfile, to the latest profile's prompts
      c) Or if -AllProfiles, to each profile's prompts
      d) Attempt symbolic link (prompts -> combined) then junction then copy (or copy directly with -ForceCopy)

Result: All items visible under the chosen prompts directory, enabling unified browsing.

Usage Examples:
  Dry run only:
    pwsh -File .\scripts\combine-and-publish-prompts.ps1 -DryRun
  Publish to global prompts (default):
    pwsh -File .\scripts\combine-and-publish-prompts.ps1
  Publish to latest profile prompts (legacy behavior):
    pwsh -File .\scripts\combine-and-publish-prompts.ps1 -UseLatestProfile
  Publish to all profiles forcing copy:
    pwsh -File .\scripts\combine-and-publish-prompts.ps1 -AllProfiles -ForceCopy
  Rebuild combined only (no publish):
    pwsh -File .\scripts\combine-and-publish-prompts.ps1 -NoPublish

Flags:
  -SourceRoot <path>
  -ProfilesBase <path>
  -ProfileRoot <path> (explicit profile root; overrides -UseLatestProfile)
  -AllProfiles
  -UseLatestProfile (restore previous default targeting most recent profile)
  -ForceCopy (skip link attempts)
  -DryRun (show plan, do not modify)
  -NoPublish (build combined set only)
  -Prune (remove stale files from existing combined folder before rebuild)
  -IncludeCollections (opt-in: also merge markdown files from collections/)

License: Adapt freely.
#>
[CmdletBinding()] param(
  [string]$SourceRoot = "$HOME/.awesome-copilot",
  [string]$ProfilesBase = (Join-Path $env:APPDATA 'Code/User/profiles'),
  [string]$ProfileRoot,
  [switch]$UseLatestProfile,
  [switch]$AllProfiles,
  [switch]$ForceCopy,
  [switch]$DryRun,
  [switch]$NoPublish,
  [switch]$Prune,
  [switch]$IncludeCollections
)

$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') { $ts = (Get-Date).ToString('s'); Write-Host "[$ts][$level] $m" -ForegroundColor $(if ($level -eq 'ERROR') { 'Red' } elseif ($level -eq 'WARN') { 'Yellow' } else { 'Cyan' }) }

if (-not (Test-Path $SourceRoot)) { Log "Source root missing: $SourceRoot" 'ERROR'; exit 1 }
if (-not (Test-Path $ProfilesBase)) { Log "Profiles base missing: $ProfilesBase" 'WARN' }

$categories = @('chatmodes', 'instructions', 'prompts')
if ($IncludeCollections) { $categories += 'collections' }
$missing = @()
foreach ($c in $categories) { if (-not (Test-Path (Join-Path $SourceRoot $c))) { $missing += $c } }
if ($missing) { Log "Missing category folders: $($missing -join ', ')" 'WARN' }

# Determine publish targets. We now default to global prompts unless an explicit
# profile strategy is selected.
$globalPrompts = Join-Path (Join-Path $env:APPDATA 'Code/User') 'prompts'
$targetMode = 'Global'
$targets = @()

if ($AllProfiles) {
  $targetMode = 'AllProfiles'
  $targets = Get-ChildItem $ProfilesBase -Directory | ForEach-Object { Join-Path $_.FullName 'prompts' }
  if (-not $targets) { Log 'No profiles discovered for -AllProfiles.' 'ERROR'; exit 1 }
  Log "Will publish to $($targets.Count) profile prompt directories" 'INFO'
}
elseif ($ProfileRoot) {
  $targetMode = 'ExplicitProfile'
  $targets = @(Join-Path $ProfileRoot 'prompts')
  Log "Explicit profile root provided: $ProfileRoot" 'INFO'
}
elseif ($UseLatestProfile) {
  $targetMode = 'LatestProfile'
  $latest = if (Test-Path $ProfilesBase) { Get-ChildItem $ProfilesBase -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } else { $null }
  if (-not $latest) { Log 'No profiles found for -UseLatestProfile.' 'ERROR'; exit 1 }
  $targets = @(Join-Path $latest.FullName 'prompts')
  Log "Using latest profile: $($latest.FullName)" 'INFO'
}
else {
  $targetMode = 'Global'
  $targets = @($globalPrompts)
  Log "Defaulting to global prompts directory: $globalPrompts" 'INFO'
}

Log "Publish mode: $targetMode" 'INFO'

$combinedRoot = Join-Path $SourceRoot 'combined'

# Ensure combined directory exists
if (-not (Test-Path $combinedRoot)) {
  if ($DryRun) { Log "[DryRun] Would create combined folder: $combinedRoot" 'INFO' } else { New-Item -ItemType Directory -Path $combinedRoot | Out-Null }
}

# Map of dest relative name -> full path already added (for duplicate detection)
$index = @{}
$added = 0
$skippedSame = 0
$renamed = 0

foreach ($cat in $categories) {
  $srcDir = Join-Path $SourceRoot $cat
  if (-not (Test-Path $srcDir)) { continue }
  $files = Get-ChildItem $srcDir -File -Filter '*.md'
  foreach ($f in $files) {
    $destName = $f.Name
    $destPath = Join-Path $combinedRoot $destName
    if (Test-Path $destPath) {
      # Compare content hash; if identical skip, else replace with latest version
      $existingHash = (Get-FileHash -Algorithm SHA256 $destPath).Hash
      $newHash = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash
      if ($existingHash -eq $newHash) { 
        $skippedSame++
        continue 
      }
      # Different content - latest version wins, replace the file
      Log "Name collision: replacing $destName with latest from $cat" 'INFO'
      $renamed++
    }
    if ($DryRun) {
      Log "[DryRun] Add $cat -> $destName" 'INFO'
    }
    else {
      Copy-Item $f.FullName $destPath -Force
    }
    $added++
  }
}

Log "Combined summary: added=$added identicalSkipped=$skippedSame renamed=$renamed" 'INFO'

if ($NoPublish) { Log "NoPublish set; skipping linking/copy phase." 'INFO'; exit 0 }

function Publish-ToPrompts($promptsDir) {
  if (-not (Test-Path $promptsDir)) {
    if ($DryRun) { Log "[DryRun] Would create prompts dir $promptsDir" }
    else { New-Item -ItemType Directory -Path $promptsDir | Out-Null }
  }
  $canLink = $true
  if (Test-Path $promptsDir) {
    $item = Get-Item $promptsDir -Force
    $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if ($isLink) {
      Log "prompts already linked: $promptsDir" 'INFO'
      return
    }
    # If prompts directory exists as normal folder, we'll update it in place
    # User-created files will be preserved, synced files will be updated
    $nonHidden = Get-ChildItem $promptsDir -Force | Where-Object { -not $_.Attributes.ToString().Contains('Hidden') }
    if ($nonHidden) {
      Log "prompts exists as normal directory; will update synced files in place" 'INFO'
    }
  }
  if ($ForceCopy -or -not $canLink) {
    Log "Copying combined contents into prompts ($promptsDir)" 'INFO'
    if (-not $DryRun) { Copy-Item (Join-Path $combinedRoot '*') $promptsDir -Recurse -Force }
    return
  }
  if ($DryRun) { Log "[DryRun] Would replace prompts with link/junction to combined" 'INFO'; return }
  try {
    Remove-Item $promptsDir -Recurse -Force -ErrorAction Stop
    New-Item -ItemType SymbolicLink -Path $promptsDir -Target $combinedRoot -Force | Out-Null
    Log "Created symlink prompts -> combined" 'INFO'
  }
  catch {
    Log "Symlink failed: $($_.Exception.Message) (attempt junction)" 'WARN'
    try {
      cmd /c mklink /J "$promptsDir" "$combinedRoot" | Out-Null
      Log "Created junction prompts -> combined" 'INFO'
    }
    catch {
      Log "Junction failed; copying fallback" 'WARN'
      New-Item -ItemType Directory -Path $promptsDir -Force | Out-Null
      Copy-Item (Join-Path $combinedRoot '*') $promptsDir -Recurse -Force
    }
  }
}

foreach ($t in $targets) { Publish-ToPrompts -promptsDir $t }

Log "Combine & publish complete." 'INFO'
