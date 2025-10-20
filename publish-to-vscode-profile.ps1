[CmdletBinding()] param(
    [string]$SourceRoot = "$HOME/.awesome-copilot",
    [string]$ProfileRoot,
    [switch]$AllProfiles,
    [string]$WorkspaceRoot,
    [switch]$ForceCopyFallback,
    [switch]$Prune,
    [switch]$VerboseLinks
)

$ErrorActionPreference = 'Stop'

function Log($msg, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s'); Write-Host "[$ts][$level] $msg" -ForegroundColor $(if ($level -eq 'ERROR') { 'Red' } elseif ($level -eq 'WARN') { 'Yellow' } else { 'Cyan' })
}

if (-not (Test-Path $SourceRoot)) { Log "Source root not found: $SourceRoot" 'ERROR'; exit 1 }

# Collect target profiles
$profilesBase = Join-Path $env:APPDATA 'Code/User/profiles'
if (-not (Test-Path $profilesBase)) { Log "Profiles base not found: $profilesBase (open VS Code & ensure a profile exists)" 'ERROR'; exit 1 }
$TargetProfiles = @()
if ($AllProfiles) {
    $TargetProfiles = Get-ChildItem $profilesBase -Directory | ForEach-Object { $_.FullName }
    if (-not $TargetProfiles) { Log "No profile directories found under $profilesBase" 'ERROR'; exit 1 }
    Log "Publishing to ALL profiles ($($TargetProfiles.Count))" 'INFO'
}
else {
    if (-not $ProfileRoot) {
        $profileDir = Get-ChildItem $profilesBase -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $profileDir) { Log "No profile directories found under $profilesBase" 'ERROR'; exit 1 }
        $ProfileRoot = $profileDir.FullName
        Log "Detected profile: $ProfileRoot"
    }
    $TargetProfiles = @($ProfileRoot)
}

function Get-MappingsForProfile($pRoot) {
    @(
        @{ Name = 'chatmodes'; Src = (Join-Path $SourceRoot 'chatmodes'); Dst = (Join-Path $pRoot 'chatmodes') }
        @{ Name = 'prompts'; Src = (Join-Path $SourceRoot 'prompts'); Dst = (Join-Path $pRoot 'prompts') }
        @{ Name = 'instructions'; Src = (Join-Path $SourceRoot 'instructions'); Dst = (Join-Path $pRoot 'instructions') }
    )
}

# Helper to link or copy
function Ensure-LinkOrCopy($src, $dst, [string]$label) {
    if (-not (Test-Path $src)) { Log "Skipping $label (missing source: $src)" 'WARN'; return }
    if (Test-Path $dst) {
        $item = Get-Item $dst -Force
        $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($isLink -and -not $ForceCopyFallback) {
            Log "$label already linked: $dst"; return
        }
        elseif (-not $isLink -and -not $ForceCopyFallback) {
            Log "$label exists as normal directory; will update only synced files" 'INFO'
            # Only remove files that exist in source (preserve user-created files)
            if (Test-Path $src) {
                $srcFiles = Get-ChildItem $src -Filter '*.md' -File -Recurse | ForEach-Object { $_.Name }
                Get-ChildItem $dst -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($srcFiles -contains $_.Name) {
                        Log "Removing synced file to update: $($_.Name)" 'INFO'
                        Remove-Item $_.FullName -Force
                    }
                }
            }
            # Now copy the source files (will update/add synced files, leave others alone)
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
            Copy-Item (Join-Path $src '*') $dst -Recurse -Force
            return
        }
        else {
            Log "Removing existing $label at $dst to replace" 'WARN'
            Remove-Item $dst -Recurse -Force
        }
    }
    if ($ForceCopyFallback) {
        Log "Copying $label -> $dst"
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
        Copy-Item (Join-Path $src '*') $dst -Recurse -Force
    }
    else {
        try {
            Log "Creating symlink $dst -> $src"
            New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
        }
        catch {
            Log "Symlink failed ($label): $_ (attempt junction)" 'WARN'
            try {
                cmd /c mklink /J "$dst" "$src" | Out-Null
                Log "Created junction for ${label}: ${dst}"
            }
            catch {
                Log "Junction failed for ${label}: $_ (fallback copy)" 'WARN'
                if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
                Copy-Item (Join-Path $src '*') $dst -Recurse -Force
            }
        }
    }
    if ($VerboseLinks) {
        $preview = Get-ChildItem $dst -File | Select-Object -First 3 | ForEach-Object { $_.Name } | Out-String
        $cleanPreview = ($preview -split "`r?`n" | Where-Object { $_ }) -join ', '
        Log "${label} preview: $cleanPreview"
    }
}

foreach ($p in $TargetProfiles) {
    Log "Processing profile: $p" 'INFO'
    $Mappings = Get-MappingsForProfile -pRoot $p
    foreach ($m in $Mappings) { Ensure-LinkOrCopy -src $m.Src -dst $m.Dst -label $m.Name }

    if ($Prune) {
        foreach ($m in $Mappings) {
            if (-not (Test-Path $m.Dst)) { continue }
            $srcRel = Get-ChildItem $m.Src -Recurse -File | ForEach-Object { $_.FullName.Substring($m.Src.Length).TrimStart('\\') }
            $srcSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$srcRel)
            Get-ChildItem $m.Dst -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($m.Dst.Length).TrimStart('\\')
                if (-not $srcSet.Contains($rel)) {
                    Log "Prune stale: $($m.Name)/$rel" 'WARN'
                    Remove-Item $_.FullName -Force
                }
            }
        }
    }
}

# Mirror into workspace if requested
if ($WorkspaceRoot) {
    $gh = Join-Path $WorkspaceRoot '.github'
    if (-not (Test-Path $gh)) { New-Item -ItemType Directory -Path $gh | Out-Null }
    foreach ($m in $Mappings) {
        if (-not (Test-Path $m.Src)) { continue }
        $dst = Join-Path $gh $m.Name
        if (-not (Test-Path $dst)) {
            Log "Seeding workspace $($m.Name) -> $dst"
            Copy-Item $m.Src $dst -Recurse
        }
        else {
            Log "Workspace already has $($m.Name); skipping" 'INFO'
        }
    }
}

Log "Publish complete. Reload VS Code if new items aren't visible." 'INFO'
