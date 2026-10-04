<#
.SYNOPSIS
Common primitives, utilities, and cross-platform helpers for vscode-copilot-sync.
Provides shared path validation, logging, directory hashing, and interactive pickers.
#>

$ErrorActionPreference = 'Stop'

function Assert-PathWithin {
    <#
    .SYNOPSIS
    Asserts that a given file or directory path resides strictly within an authorized base directory.
    Guards against directory traversal attacks (e.g. '../' or absolute path escaping).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ParentDirectory
    )
    $resolvedTarget = [System.IO.Path]::GetFullPath($Path)
    $resolvedParent = [System.IO.Path]::GetFullPath($ParentDirectory)
    if (-not $resolvedParent.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString()) -and
        -not $resolvedParent.EndsWith([System.IO.Path]::AltDirectorySeparatorChar.ToString())) {
        $resolvedParent += [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $resolvedTarget.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase) -and
        ($resolvedTarget -ne $resolvedParent.TrimEnd('\', '/'))) {
        throw "Security validation failed: Target path '$resolvedTarget' traverses outside authorized directory '$resolvedParent'."
    }
}

function Get-DirHash {
    <#
    .SYNOPSIS
    Calculates a single deterministic SHA256 hash for an entire directory based on sorted child file hashes.
    #>
    param([Parameter(Mandatory = $true)][string]$DirPath)
    if (-not (Test-Path $DirPath)) { return $null }
    $hashes = Get-ChildItem $DirPath -Recurse -File |
              Sort-Object FullName |
              ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    $combined = $hashes -join '|'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $stream = [System.IO.MemoryStream]::new($bytes)
    return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}

function Write-CopilotLog {
    <#
    .SYNOPSIS
    Standardized timestamped console and optional file logging with WCAG-compliant colours.
    #>
    param(
        [Parameter(Position = 0, Mandatory = $true)][string]$Message,
        [Parameter(Position = 1)][string]$Level = 'INFO',
        [string]$LogFile = '',
        [switch]$Quiet
    )
    $ts = (Get-Date).ToString('s')
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARN'    { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'Cyan' }
    }
    $line = "[$ts][$Level] $Message"
    if (-not $Quiet) {
        Write-Host $line -ForegroundColor $color
    }
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

function Log {
    <#
    .SYNOPSIS
    Convenience shorthand wrapper for Write-CopilotLog.
    #>
    param(
        [Parameter(Position = 0, Mandatory = $true)][string]$m,
        [Parameter(Position = 1)][string]$level = 'INFO'
    )
    Write-CopilotLog -Message $m -Level $level
}

function Resolve-PromptsDirectory {
    <#
    .SYNOPSIS
    Resolves the standard VS Code user prompts directory across macOS, Linux, and Windows.
    #>
    if ($IsMacOS) {
        return (Join-Path $HOME 'Library/Application Support/Code/User/prompts')
    }
    elseif ($IsLinux) {
        $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
        return (Join-Path $configHome 'Code/User/prompts')
    }
    else {
        $appData = [System.Environment]::GetFolderPath('ApplicationData')
        return (Join-Path $appData 'Code\User\prompts')
    }
}

function Resolve-SkillsDirectory {
    <#
    .SYNOPSIS
    Resolves the standard user-level Copilot skills directory (~/.copilot/skills).
    #>
    return (Join-Path $HOME '.copilot/skills')
}

function Get-FrontmatterDescription {
    <#
    .SYNOPSIS
    Parses the description field from YAML frontmatter in a markdown document, falling back to the first heading.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [int]$MaxLines = 20
    )
    if (-not (Test-Path $FilePath)) { return '' }
    try {
        $lines = Get-Content $FilePath -TotalCount $MaxLines -ErrorAction SilentlyContinue
        $inFrontmatter = $false
        foreach ($line in $lines) {
            if ($line -eq '---') { $inFrontmatter = -not $inFrontmatter; continue }
            if ($inFrontmatter -and $line -match '^description:\s*(.+)') {
                return $Matches[1].Trim('"''')
            }
        }
        foreach ($line in $lines) {
            if ($line -match '^#{1,3}\s+(.+)') {
                return $Matches[1].Trim()
            }
        }
    }
    catch {}
    return ''
}

function Show-OGV {
    <#
    .SYNOPSIS
    Wrapper around Out-GridView that alerts the user when window opens in the background.
    #>
    param(
        [Parameter(ValueFromPipeline)][object[]]$InputObject,
        [string]$Title,
        [string]$SearchKey,
        [switch]$PassThru
    )
    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($i in $InputObject) { $all.Add($i) } }
    end {
        Write-Host "  ► Selection window opening — check your taskbar if it appears behind other apps." -ForegroundColor Yellow
        if ($PassThru) { return ($all | Out-GridView -Title $Title -PassThru) }
        else { $all | Out-GridView -Title $Title }
    }
}

function Show-FzfPicker {
    <#
    .SYNOPSIS
    Terminal fuzzy multi-select picker using fzf with keyboard navigation header.
    #>
    param(
        [string]$Title,
        [object[]]$Items
    )
    $hasFzf = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $hasFzf) { return $null }

    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Items) {
            $rec = if ($item.IsRecommended) { '★' } else { ' ' }
            $status = if ($item.AlreadyInstalled) { '[*]' } elseif ($item.RequiresSetup) { '[!]' } else { '   ' }
            $titleStr = if ($item.Title) { $item.Title } else { $item.Name }
            $descStr = if ($item.Description) { $item.Description } else { '' }
            $lines.Add("$rec`t$status`t$($item.Name)`t$titleStr`t$descStr")
        }

        $headerText = "$Title (TAB: toggle selection | ENTER: confirm | ESC: cancel)"
        $selected = ($lines -join "`n") | fzf -m --delimiter="`t" --with-nth=1,2,3,4,5 --header="$headerText"
        if (-not $selected) { return @() }
        $pickedNames = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($selected -split "`n")) {
            $parts = $line -split "`t"
            if ($parts.Count -ge 3 -and $parts[2].Trim()) {
                $pickedNames.Add($parts[2].Trim())
            }
        }
        return @($Items | Where-Object { $pickedNames.Contains($_.Name) })
    }
    catch {
        return $null
    }
}

function Get-Description {
    <#
    .SYNOPSIS
    Compatibility wrapper around Get-FrontmatterDescription.
    #>
    param([Parameter(Mandatory = $true)][string]$FilePath)
    Get-FrontmatterDescription -FilePath $FilePath
}
