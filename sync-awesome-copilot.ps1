[CmdletBinding()] param(
    [string]$Dest = "$HOME/.awesome-copilot",
    # Default now excludes 'collections' (can still be added explicitly via -Categories)
    [string]$Categories = 'chatmodes,instructions,prompts',
    [switch]$Quiet,
    [switch]$NoDelete,
    [switch]$DiffOnly,
    [switch]$Plan,              # Dry-run: compute changes, no file writes / deletions / manifest update
    [switch]$SkipBackup,         # Skip pre-deletion backup snapshot
    [int]$BackupRetention = 5,   # Number of recent backups to retain
    [int]$LogRetentionDays = 14,
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Inquire'

$script:StartTime = Get-Date
$script:Deadline = $script:StartTime.AddSeconds($TimeoutSeconds)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('s')
    $line = "[$ts][$Level] $Message"
    if (-not $Quiet) { Write-Host $line }
    Add-Content -Path $Global:LogFile -Value $line
}

function Check-Timeout {
    if ((Get-Date) -gt $script:Deadline) {
        Write-Log "Timeout reached, aborting." 'ERROR'
        exit 1
    }
}

# Prepare paths
$Root = Resolve-Path -Path . | Select-Object -ExpandProperty Path
$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss')
if (-not (Test-Path logs)) { New-Item -ItemType Directory -Path logs | Out-Null }
$Global:LogFile = Join-Path logs "sync-$RunId.log"

Write-Log "Starting Awesome Copilot scheduled sync. Dest=$Dest Categories=$Categories" 'INFO'

# Ensure destination
if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }

$ManifestPath = Join-Path $Dest 'manifest.json'
$StatusPath = Join-Path $Dest 'status.txt'

# Load previous manifest
$PrevManifest = $null
if (Test-Path $ManifestPath) {
    try { $PrevManifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json } catch { Write-Log "Failed to parse previous manifest: $_" 'WARN' }
}

$CategoriesList = $Categories.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$Repo = 'github/awesome-copilot'
$ApiBase = 'https://api.github.com'
$UserAgent = 'awesome-copilot-scheduled-sync'
$Token = $env:GITHUB_TOKEN

function Invoke-Github {
    param(
        [string]$Url,
        [int]$Attempt = 1
    )
    Check-Timeout
    $Headers = @{ 'User-Agent' = $UserAgent; 'Accept' = 'application/vnd.github.v3+json' }
    if ($Token) { $Headers['Authorization'] = "Bearer $Token" }
    try {
        return Invoke-RestMethod -Uri $Url -Headers $Headers -TimeoutSec 60
    }
    catch {
        # Rate limit detection (403 + Remaining=0)
        try {
            $resp = $_.Exception.Response
            if ($resp -and $resp.StatusCode.value__ -eq 403) {
                $remainingHeader = $resp.Headers['X-RateLimit-Remaining']
                if ($remainingHeader -eq '0') {
                    $script:RateLimitHit = $true
                    Write-Log "Rate limit hit for $Url (Remaining=0)." 'WARN'
                }
            }
        }
        catch {}
        if ($Attempt -lt 3 -and ($_.Exception.Response.StatusCode.value__ -ge 500 -or $_.Exception.Response.StatusCode.value__ -eq 429)) {
            $delay = [math]::Pow(2, $Attempt)
            Write-Log "Transient error on $Url. Retry in $delay s" 'WARN'
            Start-Sleep -Seconds $delay
            return Invoke-Github -Url $Url -Attempt ($Attempt + 1)
        }
        Write-Log "Request failed: $Url :: $_" 'ERROR'
        throw
    }
}

function Get-FileHashSha256String {
    param([byte[]]$Bytes)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($Bytes)
    ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
}

if ($DiffOnly) {
    if (-not $PrevManifest) { Write-Log "No previous manifest; diff-only mode cannot proceed." 'ERROR'; exit 1 }
    Write-Log "Diff-only mode: no network calls. Summarizing previous manifest." 'INFO'
    $summary = $PrevManifest.summary
    $content = @()
    $content += "Diff-only summary (previous run)" 
    $content += "Added:    $($summary.added)"
    $content += "Updated:  $($summary.updated)"
    $content += "Removed:  $($summary.removed)"
    $content += "Unchanged:$($summary.unchanged)"
    Set-Content -Path $StatusPath -Value ($content -join [Environment]::NewLine)
    exit 0
}

$NewItems = @()
$Added = 0; $Updated = 0; $Removed = 0; $Unchanged = 0
$PrevIndex = @{}
if ($PrevManifest -and $PrevManifest.items) {
    foreach ($it in $PrevManifest.items) { $PrevIndex["$($it.category)|$($it.path)"] = $it }
}

foreach ($cat in $CategoriesList) {
    Write-Log "Fetching category: $cat" 'INFO'
    $url = "$ApiBase/repos/$Repo/contents/$cat"
    try {
        $listing = Invoke-Github -Url $url
    }
    catch {
        Write-Log "Failed to list $cat" 'ERROR'
        continue
    }

    if (-not $script:SuccessfulCategories) { $script:SuccessfulCategories = @() }
    $script:SuccessfulCategories += $cat

    foreach ($entry in $listing) {
        if ($entry.type -ne 'file') { continue }
        if (-not ($entry.name -match '\.(md|markdown|json)$')) { continue }
        Check-Timeout
        $downloadUrl = $entry.download_url
        if (-not $downloadUrl) { continue }
        $rawBytes = $null
        try {
            # Primary attempt: Invoke-WebRequest and derive bytes (ContentBytes is not a valid property in modern PowerShell)
            $resp = Invoke-WebRequest -Uri $downloadUrl -UserAgent $UserAgent -TimeoutSec 60 -ErrorAction Stop
            if ($resp.RawContentStream) {
                $ms = New-Object System.IO.MemoryStream
                $resp.RawContentStream.CopyTo($ms)
                $rawBytes = $ms.ToArray()
            }
            elseif ($resp.Content) {
                # Fallback: encode string content as UTF8 (raw text files like md/json are UTF-8 on GitHub)
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($resp.Content)
            }
            if (-not $rawBytes -or $rawBytes.Length -eq 0) { throw "Empty response body" }
        }
        catch {
            Write-Log "Direct download failed for $($entry.path): $_ (will fallback to contents API)" 'WARN'
            try {
                # Fallback: GitHub contents API returns base64 content
                $fileMeta = Invoke-Github -Url "$ApiBase/repos/$Repo/contents/$($entry.path)"
                if ($fileMeta.content) {
                    $b64 = ($fileMeta.content -replace "\s", '')
                    $rawBytes = [System.Convert]::FromBase64String($b64)
                }
                else {
                    throw "No content field in contents API response"
                }
            }
            catch {
                Write-Log "Failed download $($entry.path): $_" 'ERROR'
                continue
            }
        }
        $hash = Get-FileHashSha256String -Bytes $rawBytes
        $key = "$cat|$($entry.path)"
        $prev = $PrevIndex[$key]
        $relativePath = $entry.path
        $targetFile = Join-Path $Dest $relativePath
        $targetDir = Split-Path $targetFile -Parent
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

        $isChange = $true
        if ($prev -and $prev.sha -eq $entry.sha -and $prev.hash -eq $hash) { $isChange = $false }
        if ($isChange) {
            if ($Plan) {
                Write-Log "[Plan] Would save: $relativePath" 'INFO'
            }
            else {
                # Ensure the file is fully replaced by removing it first if it exists
                if (Test-Path $targetFile) {
                    Remove-Item $targetFile -Force
                }
                [System.IO.File]::WriteAllBytes($targetFile, $rawBytes)
            }
            if ($prev) { $Updated++ } else { $Added++ }
            if (-not $Plan) { Write-Log "Saved: $relativePath" 'INFO' }
        }
        else { $Unchanged++ }

        $NewItems += [pscustomobject]@{
            category    = $cat
            path        = $relativePath
            sha         = $entry.sha
            size        = $entry.size
            lastFetched = (Get-Date).ToString('o')
            hash        = $hash
        }
    }
}

# Determine removals (only for categories successfully fetched this run)
if (-not $Plan -and -not $NoDelete -and $PrevManifest) {
    if ($script:RateLimitHit) {
        Write-Log 'Rate limit encountered this run; skipping stale file deletion.' 'WARN'
    }
    else {
        $successful = $script:SuccessfulCategories | Sort-Object -Unique
        if (-not $successful -or $successful.Count -eq 0) {
            Write-Log 'No categories fetched successfully this run; skipping stale file deletion for safety.' 'WARN'
        }
        else {
            # Backup snapshot before deletions
            if (-not $SkipBackup) {
                try {
                    $backupRoot = Join-Path $Dest 'backups'
                    if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot | Out-Null }
                    $backupFile = Join-Path $backupRoot ("pre-delete-" + $RunId + '.zip')
                    Write-Log "Creating backup snapshot: $backupFile" 'INFO'
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    # Zip only successfully fetched category folders (if present)
                    $tempStage = Join-Path $backupRoot ("stage-" + $RunId)
                    New-Item -ItemType Directory -Path $tempStage | Out-Null
                    foreach ($c in $successful) {
                        $cDir = Join-Path $Dest $c
                        if (Test-Path $cDir) { Copy-Item $cDir (Join-Path $tempStage $c) -Recurse -Force }
                    }
                    [IO.Compression.ZipFile]::CreateFromDirectory($tempStage, $backupFile)
                    Remove-Item $tempStage -Recurse -Force -ErrorAction SilentlyContinue
                    # Retention
                    $backups = Get-ChildItem $backupRoot -Filter 'pre-delete-*.zip' | Sort-Object LastWriteTime -Descending
                    if ($backups.Count -gt $BackupRetention) {
                        $toRemove = $backups | Select-Object -Skip $BackupRetention
                        foreach ($oldB in $toRemove) { Remove-Item $oldB.FullName -Force }
                    }
                }
                catch {
                    Write-Log "Backup snapshot failed (continuing without backup): $_" 'WARN'
                }
            }
            $NewKeySet = @{}
            foreach ($ni in $NewItems) { $NewKeySet["$($ni.category)|$($ni.path)"] = $true }
            foreach ($old in $PrevManifest.items) {
                $k = "$($old.category)|$($old.path)"
                # Only consider deletion if the category was fetched this run
                if ($successful -contains $old.category) {
                    if (-not $NewKeySet.ContainsKey($k)) {
                        $Removed++
                        $fileToRemove = Join-Path $Dest $old.path
                        if (Test-Path $fileToRemove) { Remove-Item $fileToRemove -Force }
                        Write-Log "Removed stale file: $($old.path)" 'INFO'
                    }
                }
            }
        }
    }
}

if ($Plan) {
    Write-Log "[Plan] Summary Added=$Added Updated=$Updated Removed=(planned) Unchanged=$Unchanged" 'INFO'
    Write-Log '[Plan] No files written. Exiting without manifest/status update.' 'INFO'
    exit 0
}

# Write manifest
$Manifest = [pscustomobject]@{
    version    = 1
    repo       = $Repo
    fetchedAt  = (Get-Date).ToString('o')
    categories = $CategoriesList
    items      = $NewItems
    summary    = [pscustomobject]@{
        added     = $Added
        updated   = $Updated
        removed   = $Removed
        unchanged = $Unchanged
    }
}
if ($script:SuccessfulCategories -and $script:SuccessfulCategories.Count -gt 0) {
    $Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding UTF8
    # Integrity marker
    try {
        $integrity = [pscustomobject]@{
            fetchedAt            = (Get-Date).ToString('o')
            successfulCategories = ($script:SuccessfulCategories | Sort-Object -Unique)
            summary              = $Manifest.summary
            manifestSha256       = (Get-FileHash -Algorithm SHA256 $ManifestPath).Hash
        }
        $integrity | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Dest 'last-success.json') -Encoding UTF8
    }
    catch { Write-Log "Failed writing integrity marker: $_" 'WARN' }
}
else {
    Write-Log 'No successful categories; manifest not updated this run.' 'WARN'
}

# Status file
$StatusLines = @()
$StatusLines += "Sync run: $(Get-Date -Format o)"
$StatusLines += "Added:    $Added"
$StatusLines += "Updated:  $Updated"
$StatusLines += "Removed:  $Removed"
$StatusLines += "Unchanged:$Unchanged"
$StatusLines += "Total:    $($Manifest.items.Count)"
$StatusLines += "Manifest: manifest.json"
$StatusLines += "Repo:     $Repo"
$StatusLines += "Duration: $([int]((Get-Date)-$script:StartTime).TotalSeconds)s"
$StatusLines | Set-Content -Path $StatusPath -Encoding UTF8

Write-Log "Summary Added=$Added Updated=$Updated Removed=$Removed Unchanged=$Unchanged" 'INFO'

# Log retention
Get-ChildItem logs -Filter 'sync-*.log' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } | ForEach-Object { Remove-Item $_.FullName -Force }

exit 0
