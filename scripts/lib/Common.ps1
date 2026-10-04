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
    [DEPRECATED] Wrapper around Out-GridView for Windows GUI selection.
    Will be removed in v3.0 during migration to cross-platform Node / NPM CLI.
    Prefer cross-platform terminal selection via fzf or the numbered console menu.
    #>
    param(
        [Parameter(ValueFromPipeline)][object[]]$InputObject,
        [string]$Title,
        [string]$SearchKey,
        [switch]$PassThru
    )
    begin {
        Write-CopilotLog "[DEPRECATION NOTICE] Out-GridView GUI picker is deprecated and will be removed in v3.0 in favour of cross-platform terminal selection." 'WARN'
        $all = [System.Collections.Generic.List[object]]::new()
    }
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
    Terminal fuzzy multi-select picker using fzf with top-down layout and keyboard navigation header.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Items
    )
    $hasFzf = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $hasFzf) { return $null }

    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Items) {
            $rec = if ($item.IsRecommended) { '★' } else { ' ' }
            $status = ''
            if ($item.AlreadyInstalled) { $status += '[*]' }
            if ($item.UpdateAvailable) { $status += '[↑]' }
            if ($item.LocallyModified) { $status += '[~]' }
            if ($item.UserInstalled) { $status += '[U]' }
            if ($item.RequiresSetup) { $status += '[!]' }
            if (-not $status) { $status = '   ' }

            $titleStr = if ($item.Title -and $item.Title -ne $item.Name) { "$($item.Name) ($($item.Title))" } else { $item.Name }
            $descStr = if ($item.Description) { $item.Description } else { '' }
            # Tab-delimited: 1=Name (hidden ID), 2=Rec, 3=Status, 4=DisplayName, 5=Description
            $lines.Add("$($item.Name)`t$rec`t$status`t$titleStr`t$descStr")
        }

        $headerLines = @(
            "=== $Title ===",
            "  Navigation:  [Up/Down] Move cursor    [PgUp/PgDn] Page scroll    Wrap-around enabled",
            "  Selection:   [TAB] Toggle item (*)    [Ctrl+A] Select all        [Ctrl+D] Deselect all",
            "  Shortcuts:   [Ctrl+R] Show recommended (★)                      Type to fuzzy search",
            "  Action:      [ENTER] Confirm & apply  [ESC] Cancel / skip"
        )
        $headerText = $headerLines -join "`n"

        $selected = ($lines -join "`n") | fzf -m `
            --delimiter="`t" `
            --with-nth=2,3,4,5 `
            --layout=reverse `
            --height=80% `
            --border `
            --header-first `
            --info=inline `
            --cycle `
            --prompt="Search: " `
            --pointer="> " `
            --marker="* " `
            --bind="ctrl-a:select-all,ctrl-d:deselect-all,ctrl-r:change-query(★)" `
            --header="$headerText"
        if ($LASTEXITCODE -gt 1 -and $LASTEXITCODE -ne 130) {
            return $null
        }
        if (-not $selected -or $selected.Trim() -eq '') { return @() }
        $pickedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($line in ($selected -split "`n")) {
            $parts = $line -split "`t"
            if ($parts.Count -ge 1 -and $parts[0].Trim()) {
                [void]$pickedNames.Add($parts[0].Trim())
            }
        }
        return @($Items | Where-Object { $pickedNames.Contains($_.Name) })
    }
    catch {
        return $null
    }
}

function Show-ConsoleMenu {
    <#
    .SYNOPSIS
    Paginated, interactive terminal menu with inline search, range selection, and persistent accumulation.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Items,
        [int]$PageSize = 15,
        [switch]$IsRemoval
    )

    if ($Items.Count -eq 0) { return @() }

    # Detect sensible page size based on terminal height if available
    try {
        $rawHeight = $host.UI.RawUI.WindowSize.Height
        if ($rawHeight -gt 0) {
            $avail = [int][Math]::Floor(($rawHeight - 10) / 2)
            if ($avail -ge 5 -and $avail -le 25) { $PageSize = $avail }
        }
    }
    catch {}

    $selectedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $currentPage = 1
    $filter = ''

    while ($true) {
        $filtered = if ($filter) {
            @($Items | Where-Object {
                $_.Name -like "*$filter*" -or
                ($_.Title -and $_.Title -like "*$filter*") -or
                ($_.Description -and $_.Description -like "*$filter*")
            })
        }
        else {
            $Items
        }

        $totalItems = $filtered.Count
        $totalPages = [Math]::Max(1, [int][Math]::Ceiling($totalItems / $PageSize))
        if ($currentPage -gt $totalPages) { $currentPage = $totalPages }
        if ($currentPage -lt 1) { $currentPage = 1 }

        $startIndex = ($currentPage - 1) * $PageSize
        $endIndex = [Math]::Min($startIndex + $PageSize - 1, [Math]::Max(0, $totalItems - 1))

        Write-Host ""
        $headerColor = if ($IsRemoval) { 'Red' } else { 'Yellow' }
        Write-Host ("  === {0} (Page {1} of {2} — Items {3} to {4} of {5}) ===" -f $Title, $currentPage, $totalPages, ($startIndex + 1), ($endIndex + 1), $totalItems) -ForegroundColor $headerColor

        if ($filter) {
            Write-Host ("  [Filter active: '{0}' ({1} matching) — type '/clear' or 'f' to reset]" -f $filter, $totalItems) -ForegroundColor Cyan
        }

        if ($selectedNames.Count -gt 0) {
            $previewList = @($selectedNames | Select-Object -First 5) -join ', '
            if ($selectedNames.Count -gt 5) { $previewList += " (+$($selectedNames.Count - 5) more)" }
            Write-Host ("  [✓ Selected ({0}): {1}]" -f $selectedNames.Count, $previewList) -ForegroundColor Green
        }
        else {
            Write-Host "  [Selected: none]" -ForegroundColor Gray
        }

        if ($IsRemoval) {
            Write-Host "  [~]=Locally modified (removal is permanent)" -ForegroundColor Gray
        }
        else {
            Write-Host "  ★=Recommended  [*]=Installed  [↑]=Update available  [~]=Locally modified  [!]=Setup required" -ForegroundColor Gray
        }
        Write-Host "  ─────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

        if ($totalItems -eq 0) {
            Write-Host "  No items match the current filter." -ForegroundColor Yellow
        }
        else {
            for ($i = $startIndex; $i -le $endIndex; $i++) {
                $item = $filtered[$i]
                $itemNum = $i + 1
                $isChecked = if ($selectedNames.Contains($item.Name)) { '[x]' } else { '[ ]' }
                $rec = if ($item.IsRecommended) { '★' } elseif ($item.RequiresSetup) { '!' } else { ' ' }
                $status = ''
                if ($item.AlreadyInstalled) { $status += '[*]' }
                if ($item.UpdateAvailable) { $status += '[↑]' }
                if ($item.LocallyModified) { $status += '[~]' }
                if ($item.UserInstalled) { $status += '[U]' }

                $color = if ($isChecked -eq '[x]') { 'Green' }
                    elseif ($IsRemoval -and $item.LocallyModified) { 'Yellow' }
                    elseif ($IsRemoval) { 'White' }
                    elseif ($item.UpdateAvailable) { 'Cyan' }
                    elseif ($item.AlreadyInstalled) { 'Gray' }
                    elseif ($item.IsRecommended) { 'Yellow' }
                    elseif ($item.RequiresSetup) { 'Yellow' }
                    else { 'White' }

                $dispName = if ($item.Title -and $item.Title -ne $item.Name) { "$($item.Name) ($($item.Title))" } else { $item.Name }
                Write-Host ("  {0,3}. {1} [{2}] {3,-6} {4}" -f $itemNum, $isChecked, $rec, $status, $dispName) -ForegroundColor $color
                if ($item.Description) {
                    Write-Host ("               {0}" -f $item.Description) -ForegroundColor Gray
                }
            }
        }

        Write-Host "  ─────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  Navigation:  [n]ext / [p]rev page (or press Enter on last page) | Wrap-around enabled" -ForegroundColor Gray
        Write-Host "  Selection:   1,3 or 1-5 (toggle) | rec / r (recommended) | all / a | none / c (clear)" -ForegroundColor Gray
        Write-Host "  Search:      /term or f term (filter catalogue) | /clear (reset filter)" -ForegroundColor Gray
        Write-Host "  Action:      'done' or 'q' to confirm and proceed (or append to numbers: 1,3 done)" -ForegroundColor Gray

        $navHint = if ($currentPage -lt $totalPages) { "Enter for next page, 'done' to finish" } else { "'done' or Enter to finish" }
        Write-Host ("  Action ({0}): " -f $navHint) -NoNewline -ForegroundColor $headerColor
        $raw = Read-Host

        if ($null -eq $raw) { break }
        $trimmed = $raw.Trim()

        if ($trimmed -in 'done', 'q', 'exit') {
            break
        }

        if ($trimmed -eq '') {
            if ($currentPage -lt $totalPages) {
                $currentPage++
            }
            else {
                break
            }
            continue
        }

        if ($trimmed -in 'n', 'next') {
            if ($currentPage -lt $totalPages) { $currentPage++ }
            else { Write-Host "  Already on last page." -ForegroundColor Yellow }
            continue
        }
        if ($trimmed -in 'p', 'prev', 'previous') {
            if ($currentPage -gt 1) { $currentPage-- }
            else { Write-Host "  Already on first page." -ForegroundColor Yellow }
            continue
        }
        if ($trimmed -match '^page\s+(\d+)$') {
            $p = [int]$Matches[1]
            if ($p -ge 1 -and $p -le $totalPages) { $currentPage = $p }
            else { Write-Host "  Invalid page number (1-$totalPages)." -ForegroundColor Yellow }
            continue
        }

        if ($trimmed -match '^/(.*)$') {
            $filter = $Matches[1].Trim()
            $currentPage = 1
            continue
        }
        if ($trimmed -match '^f\s+(.*)$') {
            $filter = $Matches[1].Trim()
            $currentPage = 1
            continue
        }
        if ($trimmed -in 'f', '/clear', 'clear-filter', 'reset') {
            $filter = ''
            $currentPage = 1
            continue
        }

        if ($trimmed -in 'rec', 'recommended', 'r') {
            $recItems = @($Items | Where-Object { $_.IsRecommended })
            if ($recItems.Count -eq 0) {
                Write-Host "  No items marked as recommended (★)." -ForegroundColor Yellow
            }
            else {
                foreach ($r in $recItems) { [void]$selectedNames.Add($r.Name) }
                Write-Host ("  Added {0} recommended items to selection." -f $recItems.Count) -ForegroundColor Green
            }
            if ($totalPages -eq 1) { break }
            continue
        }
        if ($trimmed -in 'all', 'a') {
            foreach ($it in $filtered) { [void]$selectedNames.Add($it.Name) }
            Write-Host ("  Added {0} items to selection." -f $filtered.Count) -ForegroundColor Green
            if ($totalPages -eq 1) { break }
            continue
        }
        if ($trimmed -in 'none', 'clear', 'c') {
            $selectedNames.Clear()
            Write-Host "  Cleared all selections." -ForegroundColor Gray
            continue
        }

        $finishAfterToggle = $false
        if ($trimmed -match '\b(done|q)\b') {
            $finishAfterToggle = $true
            $trimmed = $trimmed -replace '\b(done|q)\b', ''
        }

        $numTokens = $trimmed.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
        $validNumbers = $false
        foreach ($tok in $numTokens) {
            $t = $tok.Trim()
            if ($t -match '^(\d+)-(\d+)$') {
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                for ($k = $start; $k -le $end; $k++) {
                    if ($k -ge 1 -and $k -le $filtered.Count) {
                        $target = $filtered[$k - 1]
                        if ($selectedNames.Contains($target.Name)) { [void]$selectedNames.Remove($target.Name) }
                        else { [void]$selectedNames.Add($target.Name) }
                        $validNumbers = $true
                    }
                }
            }
            elseif ($t -match '^\d+$') {
                $k = [int]$t
                if ($k -ge 1 -and $k -le $filtered.Count) {
                    $target = $filtered[$k - 1]
                    if ($selectedNames.Contains($target.Name)) { [void]$selectedNames.Remove($target.Name) }
                    else { [void]$selectedNames.Add($target.Name) }
                    $validNumbers = $true
                }
                else {
                    Write-Host ("  Number {0} out of range (1-{1})." -f $k, $filtered.Count) -ForegroundColor Yellow
                }
            }
        }

        if ($validNumbers -and ($finishAfterToggle -or $totalPages -eq 1)) {
            break
        }
    }

    return @($Items | Where-Object { $selectedNames.Contains($_.Name) })
}

function Show-ItemPicker {
    <#
    .SYNOPSIS
    Universal interactive resource picker. Dispatches to:
    1. Show-OGV (if -Gui switch is passed on Windows)
    2. Show-FzfPicker (if fzf is installed on PATH)
    3. Show-ConsoleMenu (paginated, searchable terminal menu fallback)
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Items,
        [switch]$Gui,
        [switch]$IsRemoval,
        [int]$PageSize = 15
    )

    if ($Items.Count -eq 0) { return @() }

    # 1. GUI selection via Out-GridView (Windows-only, deprecated)
    if ($Gui) {
        if ($IsLinux -or $IsMacOS) {
            Write-Host "  [DEPRECATION NOTICE] -Gui (Out-GridView) is Windows-only and will be removed in v3.0. Falling back to console picker." -ForegroundColor Yellow
        }
        else {
            $ogvAvailable = $false
            try { Get-Command Out-GridView -ErrorAction Stop | Out-Null; $ogvAvailable = $true } catch {}
            if ($ogvAvailable) {
                Write-Host "  [DEPRECATION NOTICE] -Gui and Out-GridView are deprecated and will be removed in v3.0 for cross-platform Node/NPM parity." -ForegroundColor Yellow
                if ($IsRemoval) {
                    $none = [pscustomobject]@{ Modified = ''; Title = '-- none / skip --'; Name = '-- none / skip --'; Description = 'Select this (or nothing) to remove nothing' }
                    $display = @($none) + @($Items | Select-Object `
                        @{ N = 'Modified'; E = { if ($_.LocallyModified) { '[~] MODIFIED' } else { '' } } },
                        @{ N = 'Title'; E = { if ($_.Title) { $_.Title } else { $_.Name } } },
                        @{ N = 'Name'; E = { $_.Name } },
                        @{ N = 'Description'; E = { $_.Description } })
                }
                else {
                    $none = [pscustomobject]@{ Rec = ''; Status = ''; Title = '-- none / skip --'; Name = '-- none / skip --'; Description = 'Select this (or nothing) to install nothing' }
                    $display = @($none) + @($Items | Select-Object `
                        @{ N = 'Rec'; E = { if ($_.IsRecommended) { '★' } else { '' } } },
                        @{ N = 'Status'; E = {
                                $s = ''
                                if ($_.AlreadyInstalled) { $s += '[*]' }
                                if ($_.UpdateAvailable) { $s += '[↑]' }
                                if ($_.LocallyModified) { $s += '[~]' }
                                if ($_.UserInstalled) { $s += '[U]' }
                                if ($_.RequiresSetup) { $s += '[!]' }
                                $s
                            }
                        },
                        @{ N = 'Title'; E = { if ($_.Title) { $_.Title } else { $_.Name } } },
                        @{ N = 'Name'; E = { $_.Name } },
                        @{ N = 'Description'; E = { $_.Description } })
                }

                $picked = $display | Show-OGV -Title $Title -SearchKey $Title -PassThru
                if (-not $picked) { return @() }
                $pickedNames = @($picked | Where-Object { $_.Name -ne '-- none / skip --' } | ForEach-Object { $_.Name })
                return @($Items | Where-Object { $pickedNames -contains $_.Name })
            }
            else {
                Write-Host "  Out-GridView not available in this PowerShell environment. Falling back to console picker." -ForegroundColor Yellow
            }
        }
    }

    # 2. Try fzf terminal fuzzy multi-select if available
    $fzfPicked = Show-FzfPicker -Title $Title -Items $Items
    if ($null -ne $fzfPicked) { return $fzfPicked }

    # 3. Fallback: Paginated, searchable interactive console menu
    return (Show-ConsoleMenu -Title $Title -Items $Items -PageSize $PageSize -IsRemoval:$IsRemoval)
}

function Get-Description {
    <#
    .SYNOPSIS
    Compatibility wrapper around Get-FrontmatterDescription.
    #>
    param([Parameter(Mandatory = $true)][string]$FilePath)
    Get-FrontmatterDescription -FilePath $FilePath
}
