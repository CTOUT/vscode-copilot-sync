<#
Sync Awesome Copilot Resources

Clones (first run) or pulls (subsequent runs) the github/awesome-copilot repository
using sparse checkout — only the categories you need are fetched.

Requires 'gh' (GitHub CLI, preferred) or 'git' to be installed.

Usage:
  # Sync all default categories
  .\sync-awesome-copilot.ps1

  # Dry-run: show what would change without writing files
  .\sync-awesome-copilot.ps1 -Plan

  # Sync specific categories only
  .\sync-awesome-copilot.ps1 -Categories "agents,instructions"

  # Force a specific git tool
  .\sync-awesome-copilot.ps1 -GitTool git
#>
[CmdletBinding()] param(
    [string]$Dest = "$HOME/.awesome-copilot",
    [string]$Categories = 'agents,instructions,workflows,hooks,skills',
    [switch]$Quiet,
    [switch]$Plan,              # Dry-run: show what would change without writing files
    [int]$LogRetentionDays = 14,
    [int]$TimeoutSeconds = 600,
    [ValidateSet('auto', 'gh', 'git')]
    [string]$GitTool = 'auto'
)

#region Initialisation
$ErrorActionPreference = 'Stop'

$script:StartTime = Get-Date
$script:Deadline  = $script:StartTime.AddSeconds($TimeoutSeconds)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = (Get-Date).ToString('s')
    $line = "[$ts][$Level] $Message"
    if (-not $Quiet) { Write-Host $line }
    Add-Content -Path $Global:LogFile -Value $line
}

function Check-Timeout {
    if ((Get-Date) -gt $script:Deadline) {
        Write-Log "Timeout reached ($TimeoutSeconds s), aborting." 'ERROR'
        exit 1
    }
}

# Prepare log — always relative to this script's directory, regardless of CWD
$RunId  = (Get-Date -Format 'yyyyMMdd-HHmmss')
$LogDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$Global:LogFile = Join-Path $LogDir "sync-$RunId.log"

Write-Log "Starting Awesome Copilot sync. Dest=$Dest Categories=$Categories"

#endregion # Initialisation

#region Tool detection
function Resolve-GitTool {
    if ($GitTool -ne 'auto') {
        if (-not (Get-Command $GitTool -ErrorAction SilentlyContinue)) {
            Write-Log "'$GitTool' not found on PATH." 'ERROR'; exit 1
        }
        return $GitTool
    }
    if (Get-Command gh  -ErrorAction SilentlyContinue) { return 'gh'  }
    if (Get-Command git -ErrorAction SilentlyContinue) { return 'git' }
    Write-Log "Neither 'gh' nor 'git' found on PATH. Install one to continue." 'ERROR'
    exit 1
}

$Tool = Resolve-GitTool
Write-Log "Using tool: $Tool"

$RepoSlug       = 'github/awesome-copilot'
$RepoUrl        = 'https://github.com/github/awesome-copilot.git'
$CategoriesList = $Categories.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$ManifestPath   = Join-Path $Dest 'manifest.json'
$StatusPath     = Join-Path $Dest 'status.txt'

# Load previous manifest for change detection
$PrevManifest = $null
$PrevIndex    = @{}
if (Test-Path $ManifestPath) {
    try {
        $PrevManifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        if ($PrevManifest.items) {
            foreach ($it in $PrevManifest.items) {
                $PrevIndex["$($it.category)|$($it.path)"] = $it
            }
        }
    }
    catch { Write-Log "Failed to parse previous manifest: $_" 'WARN' }
}

function Get-Sha256 {
    param([string]$FilePath)
    return (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLower()
}

#endregion # Tool detection

#region Clone or pull
$IsFirstRun = -not (Test-Path (Join-Path $Dest '.git'))

if ($Plan) {
    if ($IsFirstRun) {
        Write-Log "[Plan] Would clone $RepoSlug → $Dest  (sparse: $($CategoriesList -join ', '))" 'INFO'
    } else {
        Write-Log "[Plan] Would pull latest changes from $RepoSlug into $Dest" 'INFO'
    }
    Write-Log "[Plan] No files written. Exiting." 'INFO'
    exit 0
}

if ($IsFirstRun) {
    Write-Log "First run — cloning $RepoSlug (sparse, shallow)..."

    # Migrate: if a non-git directory already exists (e.g. from the old API-based sync),
    # rename it so git can clone into a clean destination.
    if ((Test-Path $Dest) -and (Get-ChildItem $Dest -Force | Measure-Object).Count -gt 0) {
        $backupPath = "${Dest}-backup-$RunId"
        Write-Log "Existing non-git cache found — moving to $backupPath before cloning." 'WARN'
        Move-Item $Dest $backupPath
    }

    if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }

    if ($Tool -eq 'gh') {
        & gh repo clone $RepoSlug $Dest -- --depth 1 --filter=blob:none --sparse 2>&1 |
            ForEach-Object { Write-Log $_ }
    } else {
        & git clone --depth 1 --filter=blob:none --sparse $RepoUrl $Dest 2>&1 |
            ForEach-Object { Write-Log $_ }
    }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Write-Log "Clone failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }

    # Set which directories to check out, then materialise them
    & git -C $Dest sparse-checkout set @CategoriesList 2>&1 | Out-Null
    Write-Log "Repository cloned successfully." 'SUCCESS'
} else {
    Write-Log "Pulling latest changes from $RepoSlug..."

    # Re-apply sparse-checkout in case -Categories changed since last run
    & git -C $Dest sparse-checkout set @CategoriesList 2>&1 | Out-Null

    $pullOutput = & git -C $Dest pull 2>&1
    $pullOutput | ForEach-Object { Write-Log $_ }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        $pullText = $pullOutput -join "`n"
        if ($pullText -match 'unrelated histories') {
            Write-Log "Unrelated histories detected — fetching and resetting to remote HEAD..." 'WARN'
            & git -C $Dest fetch origin 2>&1 | ForEach-Object { Write-Log $_ }
            & git -C $Dest reset --hard origin/HEAD 2>&1 | ForEach-Object { Write-Log $_ }
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Write-Log "Reset failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
        } elseif ($pullText -match 'unmerged files|unresolved conflict|merge conflict') {
            # Local cache has conflicts — safe to discard since this directory is read-only managed by this script
            Write-Log "Unmerged files detected in local cache — resetting to remote HEAD..." 'WARN'
            & git -C $Dest fetch origin 2>&1 | ForEach-Object { Write-Log $_ }
            & git -C $Dest reset --hard origin/HEAD 2>&1 | ForEach-Object { Write-Log $_ }
            & git -C $Dest clean -fd 2>&1 | ForEach-Object { Write-Log $_ }
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Write-Log "Reset failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE }
        } else {
            Write-Log "Pull failed (exit $LASTEXITCODE)" 'ERROR'; exit $LASTEXITCODE
        }
    }
}

Check-Timeout

#endregion # Clone or pull

#region File scan and change detection
$NewItems  = @()
$Added = 0; $Updated = 0; $Unchanged = 0; $Removed = 0
$DestResolved = (Resolve-Path $Dest).Path

foreach ($cat in $CategoriesList) {
    $catDir = Join-Path $DestResolved $cat
    if (-not (Test-Path $catDir)) { Write-Log "Category folder not found after sync: $cat" 'WARN'; continue }

    $files = Get-ChildItem -Path $catDir -Recurse -File |
             Where-Object { $_.Name -match '\.(md|markdown|json|sh)$' }

    foreach ($file in $files) {
        Check-Timeout
        $relativePath = $file.FullName.Substring($DestResolved.Length + 1) -replace '\\', '/'
        $hash = Get-Sha256 -FilePath $file.FullName
        $key  = "$cat|$relativePath"
        $prev = $PrevIndex[$key]

        if     ($prev -and $prev.hash -eq $hash) { $Unchanged++ }
        elseif ($prev)                            { $Updated++;  Write-Log "Updated: $relativePath" }
        else                                      { $Added++;    Write-Log "Added:   $relativePath" }

        $NewItems += [pscustomobject]@{
            category    = $cat
            path        = $relativePath
            size        = $file.Length
            lastFetched = (Get-Date).ToString('o')
            hash        = $hash
        }
    }
}

# Count removals (files present in previous manifest but gone after pull)
$NewKeySet = @{}; foreach ($ni in $NewItems) { $NewKeySet["$($ni.category)|$($ni.path)"] = $true }
if ($PrevManifest -and $PrevManifest.items) {
    foreach ($old in $PrevManifest.items) {
        if (-not $NewKeySet.ContainsKey("$($old.category)|$($old.path)")) {
            $Removed++
            Write-Log "Removed: $($old.path)"
        }
    }
}

#endregion # File scan

#region Write manifest and status
$Manifest = [pscustomobject]@{
    version    = 1
    repo       = $RepoSlug
    fetchedAt  = (Get-Date).ToString('o')
    categories = $CategoriesList
    items      = $NewItems
    summary    = [pscustomobject]@{ added=$Added; updated=$Updated; removed=$Removed; unchanged=$Unchanged }
}
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding UTF8

@(
    "Sync run: $(Get-Date -Format o)"
    "Added:    $Added"
    "Updated:  $Updated"
    "Removed:  $Removed"
    "Unchanged:$Unchanged"
    "Total:    $($NewItems.Count)"
    "Manifest: manifest.json"
    "Repo:     $RepoSlug"
    "Duration: $([int]((Get-Date)-$script:StartTime).TotalSeconds)s"
) | Set-Content -Path $StatusPath -Encoding UTF8

Write-Log "Summary Added=$Added Updated=$Updated Removed=$Removed Unchanged=$Unchanged" 'SUCCESS'

#endregion # Write manifest

#region Log retention
Get-ChildItem $LogDir -Filter 'sync-*.log' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
    ForEach-Object { Remove-Item $_.FullName -Force }

#endregion # Log retention

exit 0
