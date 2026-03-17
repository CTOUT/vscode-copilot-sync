<#
Initialize a Repository with Copilot Resources

Interactively selects and installs non-global Copilot resources from the local
awesome-copilot cache into a target repository's .github/ folder.

Resources installed here are project-specific (opt-in) rather than global:

  Agents        --> .github/agents/*.agent.md
  Instructions  --> .github/instructions/*.instructions.md
  Hooks         --> .github/hooks/<hook-name>/   (full directory)
  Workflows     --> .github/workflows/*.md
  Skills        --> .github/skills/<skill-name>/  (full directory)

Usage:
  # Interactive - run from within the target repo
  .\init-repo.ps1

  # Specify a repo path explicitly
  .\init-repo.ps1 -RepoPath "C:\Projects\my-app"

  # Skip specific categories
  .\init-repo.ps1 -SkipAgents -SkipHooks
  .\init-repo.ps1 -SkipHooks -SkipWorkflows -SkipSkills

  # Non-interactive: specify items by name (comma-separated)
  .\init-repo.ps1 -Instructions "angular,dotnet-framework" -Hooks "session-logger"
  .\init-repo.ps1 -Agents "devops-expert,se-security-reviewer"
  .\init-repo.ps1 -Skills "my-custom-skill"
  # Dry run - show what would be installed
  .\init-repo.ps1 -DryRun

  # Remove installed resources (uninstall mode)
  .\init-repo.ps1 -Uninstall
  .\init-repo.ps1 -Uninstall -SkipInstructions -SkipHooks

Notes:
  - Existing files are only overwritten if the source is newer/different.
  - .github/ is created if it doesn't exist.
  - Skills are installed to .github/skills/ for version control with the project,
    alongside all other per-repo resources.
  - A subscription manifest (.github/.copilot-subscriptions.json) is written on
    each run. Use update-repo.ps1 to check for and apply upstream changes.
  - The selection UI uses Out-GridView where available (Windows GUI, filterable,
    multi-select). Falls back to a numbered console menu automatically.
  - Auto-detects language/framework from repo file signals and pre-marks
    recommended (config-free) resources with ★ in the picker.
    Items requiring additional setup (MCP server, API key, etc.) are marked [!].
  - For new/empty repos, prompts for intent one question at a time.
#>
[CmdletBinding()] param(
    [string]$RepoPath      = (Get-Location).Path,
    [string]$SourceRoot    = "$HOME/.awesome-copilot",
    [string]$Instructions  = '',   # Comma-separated names to pre-select (non-interactive)
    [string]$Agents        = '',
    [string]$Hooks         = '',
    [string]$Workflows     = '',
    [string]$Skills        = '',   # Comma-separated names to pre-select (non-interactive)
    [switch]$SkipInstructions,
    [switch]$SkipAgents,
    [switch]$SkipHooks,
    [switch]$SkipWorkflows,
    [switch]$SkipSkills,
    [switch]$DryRun,
    [switch]$Uninstall   # show a picker of installed items to remove instead of installing
)

#region Initialisation
$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

function Show-OGV {
    # Wrapper around Out-GridView that activates the window via WScript.Shell.AppActivate,
    # which bypasses UIPI restrictions that block SetForegroundWindow from runspaces.
    param([Parameter(ValueFromPipeline)][object[]]$InputObject, [string]$Title, [switch]$PassThru)
    begin   { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($i in $InputObject) { $all.Add($i) } }
    end {
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        $null = $ps.AddScript({
            param($t)
            $wsh = New-Object -ComObject WScript.Shell
            for ($i = 0; $i -lt 50; $i++) {   # poll up to 5 s
                Start-Sleep -Milliseconds 100
                if ($wsh.AppActivate($t)) { break }
            }
        }).AddArgument($Title)
        $handle = $ps.BeginInvoke()

        if ($PassThru) { $result = $all | Out-GridView -Title $Title -PassThru }
        else           { $all | Out-GridView -Title $Title }

        $null = $ps.EndInvoke($handle)
        $ps.Dispose(); $rs.Close()
        if ($PassThru) { return $result }
    }
}

#endregion # Initialisation

#region Stack detection
function Detect-RepoStack {
    param([string]$RepoPath)

    $recs = [System.Collections.Generic.List[string]]::new()
    $files = Get-ChildItem $RepoPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|\.venv|bin|obj)\\' } |
        Where-Object { $_.Name -notmatch '\.(instructions|agent|prompt|chatmode)\.md$' }  # exclude installed awesome-copilot files

    $exts      = $files | ForEach-Object { $_.Extension.ToLower() } | Sort-Object -Unique
    $names     = $files | ForEach-Object { $_.Name } | Sort-Object -Unique
    $hasDotnet = $exts -contains '.cs' -or ($names | Where-Object { $_ -match '\.(csproj|sln)$' })
    $hasPy     = $exts -contains '.py' -or ($names -contains 'requirements.txt') -or ($names -contains 'pyproject.toml')
    $hasTs     = $exts -contains '.ts' -or ($names -contains 'tsconfig.json')
    $hasGo     = $exts -contains '.go' -or ($names -contains 'go.mod')
    $hasRs     = $exts -contains '.rs' -or ($names -contains 'Cargo.toml')
    $hasJava   = $exts -contains '.java' -or ($names -contains 'pom.xml') -or ($names | Where-Object { $_ -eq 'build.gradle' })
    $hasKt     = $exts -contains '.kt'
    $hasTf     = $exts -contains '.tf'
    $hasBicep  = $exts -contains '.bicep'
    $hasPs1    = $exts -contains '.ps1'
    $hasJs     = $exts -contains '.js' -or $exts -contains '.jsx' -or ($names -contains 'package.json')

    # Language/platform keywords — used for content-based scoring across all categories
    if ($hasDotnet)            { $recs.Add('csharp'); $recs.Add('dotnet') }
    if ($hasPy)                { $recs.Add('python') }
    if ($hasTs)                { $recs.Add('typescript') }
    if ($hasJs)                { $recs.Add('javascript') }
    if ($hasGo)                { $recs.Add('go') }
    if ($hasRs)                { $recs.Add('rust') }
    if ($hasJava)              { $recs.Add('java') }
    if ($hasKt)                { $recs.Add('kotlin') }
    if ($hasTf)                { $recs.Add('terraform') }
    if ($hasBicep)             { $recs.Add('bicep'); $recs.Add('azure') }
    if ($hasPs1)               { $recs.Add('powershell') }

    # Docker / containers
    $hasDocker = ($names -contains 'Dockerfile') -or ($names | Where-Object { $_ -match '^docker-compose\.yml$' })
    if ($hasDocker)            { $recs.Add('docker'); $recs.Add('container') }

    # GitHub Actions
    $ghWorkflows = $files | Where-Object { $_.FullName -match '\\\.github\\workflows\\' -and $_.Extension -eq '.yml' }
    if ($ghWorkflows)          { $recs.Add('github-actions') }

    # Playwright
    $hasPlaywright = $files | Where-Object { $_.Name -match '^playwright\.config\.' }
    if ($hasPlaywright)        { $recs.Add('playwright') }

    # package.json framework detection
    $pkgJson = $files | Where-Object { $_.Name -eq 'package.json' } | Select-Object -First 1
    if ($pkgJson) {
        try {
            $pkg = Get-Content $pkgJson.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            $allDeps = @()
            if ($pkg.dependencies)    { $allDeps += $pkg.dependencies.PSObject.Properties.Name }
            if ($pkg.devDependencies) { $allDeps += $pkg.devDependencies.PSObject.Properties.Name }
            if ($allDeps -contains 'react')                          { $recs.Add('react') }
            if ($allDeps -contains 'next')                           { $recs.Add('nextjs') }
            if ($allDeps | Where-Object { $_ -match '^@angular/' })  { $recs.Add('angular') }
            if ($allDeps -contains 'vue')                            { $recs.Add('vue') }
            if ($allDeps -contains 'svelte')                         { $recs.Add('svelte') }
            if ($allDeps | Where-Object { $_ -match '^@nestjs/' })   { $recs.Add('nestjs') }
        } catch {}
    }

    # Always recommend security-focused resources for every repo
    $recs.Add('owasp')

    return @($recs | Sort-Object -Unique)
}

#endregion # Stack detection

#region Intent prompt
function Prompt-RepoIntent {
    $recs = [System.Collections.Generic.List[string]]::new()

    Write-Host ""
    Write-Host "  Q1: What is the primary language or stack?" -ForegroundColor Yellow
    Write-Host "    1. C# / .NET"
    Write-Host "    2. Python"
    Write-Host "    3. TypeScript / JavaScript"
    Write-Host "    4. Go"
    Write-Host "    5. Java / Kotlin"
    Write-Host "    6. Rust"
    Write-Host "    7. PowerShell"
    Write-Host "    8. Terraform / Bicep (Infrastructure)"
    Write-Host "    9. Other"
    Write-Host "  Enter number: " -NoNewline -ForegroundColor Yellow
    $q1 = (Read-Host).Trim()
    switch ($q1) {
        '1' { $recs.Add('csharp'); $recs.Add('dotnet') }
        '2' { $recs.Add('python') }
        '3' { $recs.Add('typescript'); $recs.Add('javascript') }
        '4' { $recs.Add('go') }
        '5' { $recs.Add('java'); $recs.Add('kotlin') }
        '6' { $recs.Add('rust') }
        '7' { $recs.Add('powershell') }
        '8' { $recs.Add('terraform'); $recs.Add('bicep'); $recs.Add('azure') }
    }

    Write-Host ""
    Write-Host "  Q2: What type of project is this?" -ForegroundColor Yellow
    Write-Host "    1. Web API / REST service"
    Write-Host "    2. Web application (frontend)"
    Write-Host "    3. CLI tool"
    Write-Host "    4. Library / SDK"
    Write-Host "    5. Data pipeline / ML"
    Write-Host "    6. Infrastructure / DevOps"
    Write-Host "    7. Documentation / Content"
    Write-Host "  Enter number: " -NoNewline -ForegroundColor Yellow
    $q2 = (Read-Host).Trim()
    switch ($q2) {
        '1' { $recs.Add('api'); $recs.Add('rest') }
        '2' { $recs.Add('frontend') }
        '3' { $recs.Add('cli') }
        '5' { $recs.Add('data') }
        '6' { $recs.Add('docker'); $recs.Add('terraform'); $recs.Add('github-actions') }
        '7' { $recs.Add('markdown'); $recs.Add('documentation') }
    }

    Write-Host ""
    Write-Host "  Q3: Any specific concerns? (comma-separated, e.g. 1,3)" -ForegroundColor Yellow
    Write-Host "    1. Security / OWASP"
    Write-Host "    2. Accessibility (a11y)"
    Write-Host "    3. Testing / Playwright"
    Write-Host "    4. Performance"
    Write-Host "    5. Docker / Containers"
    Write-Host "    6. CI/CD / GitHub Actions"
    Write-Host "    7. None"
    Write-Host "  Enter numbers: " -NoNewline -ForegroundColor Yellow
    $q3 = (Read-Host).Trim()
    if ($q3 -and $q3 -ne '7') {
        foreach ($part in $q3.Split(',')) {
            switch ($part.Trim()) {
                '1' { $recs.Add('security'); $recs.Add('owasp') }
                '2' { $recs.Add('accessibility'); $recs.Add('a11y') }
                '3' { $recs.Add('playwright'); $recs.Add('testing') }
                '4' { $recs.Add('performance') }
                '5' { $recs.Add('docker'); $recs.Add('container'); $recs.Add('kubernetes') }
                '6' { $recs.Add('github-actions') }
            }
        }
    }

    $recs.Add('owasp')
    return @($recs | Sort-Object -Unique)
}

#endregion # Intent prompt

#region Path validation and stack detection
if (-not (Test-Path $RepoPath)) {
    Log "Repo path not found: $RepoPath" 'ERROR'; exit 1
}
$RepoPath = Resolve-Path $RepoPath | Select-Object -ExpandProperty Path

if (-not (Test-Path $SourceRoot)) {
    Log "Cache not found: $SourceRoot -- run sync-awesome-copilot.ps1 first" 'ERROR'; exit 1
}

$GithubDir = Join-Path $RepoPath '.github'
Log "Target repo  : $RepoPath"
Log "Copilot cache: $SourceRoot"

# Auto-detect stack or prompt for intent
$script:Recommendations = @()
if (-not ($SkipInstructions -and $SkipHooks -and $SkipWorkflows -and $SkipAgents -and $SkipSkills)) {
    $repoFileCount = (Get-ChildItem $RepoPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|\.venv|bin|obj)\\' } |
        Measure-Object).Count

    if ($repoFileCount -gt 3) {
        Log "Scanning repo for language/framework signals..."
        $script:Recommendations = Detect-RepoStack -RepoPath $RepoPath
        if ($script:Recommendations.Count -gt 0) {
            Log "Detected: $($script:Recommendations -join ', ')"
        } else {
            Log "No signals detected." 'WARN'
            $script:Recommendations = Prompt-RepoIntent
        }
    } else {
        Log "New or empty repo detected — prompting for intent."
        $script:Recommendations = Prompt-RepoIntent
    }
}

#endregion # Path validation and stack detection

#region Helpers
function Select-Items {
    param(
        [string]$Category,
        [object[]]$Items,          # objects with Name, Description, AlreadyInstalled
        [string]$PreSelected = '',
        [string[]]$Tags = @()      # tech keywords used for content-based relevance scoring
    )

    if ($Items.Count -eq 0) {
        Log "No $Category found in cache." 'WARN'
        return @()
    }

    # Non-interactive mode: pre-selection provided
    if ($PreSelected) {
        $names = $PreSelected.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $selected = $Items | Where-Object { $names -contains $_.Name }
        if (-not $selected) { Log "No matching $Category items for: $PreSelected" 'WARN' }
        return @($selected)
    }

    # Score each item against the detected tech keywords; recommended = score >= 2 AND no setup required.
    $Items = $Items | ForEach-Object {
        $score = Measure-ItemRelevance -ItemName $_.Name -FilePath $_.FullPath -Tags $Tags
        $isRec = ($score -ge 2) -and (-not $_.RequiresSetup)
        $_ | Add-Member -NotePropertyName 'IsRecommended' -NotePropertyValue $isRec  -PassThru -Force |
             Add-Member -NotePropertyName 'Score'         -NotePropertyValue $score  -PassThru -Force
    } | Sort-Object @{ E={ if ($_.IsRecommended) { 0 } else { 1 } } }, @{ E={ if ($_.AlreadyInstalled) { 0 } else { 1 } } }, Name

    Write-Host ""
    Write-Host "  === $Category ===" -ForegroundColor Yellow
    Write-Host "  [*]=Installed  [↑]=Update available  [~]=Locally modified  ★=Recommended  [!]=Setup required" -ForegroundColor DarkGray

    # Try Out-GridView (Windows GUI - filterable, multi-select)
    $ogvAvailable = $false
    try { Get-Command Out-GridView -ErrorAction Stop | Out-Null; $ogvAvailable = $true } catch {}

    if ($ogvAvailable) {
        $none = [pscustomobject]@{ Rec=''; Status=''; Name='-- none / skip --'; Description='Select this (or nothing) to install nothing' }
        $display = @($none) + @($Items | Select-Object `
            @{ N='Rec';    E={ if ($_.IsRecommended) { '★' } else { '' } } },
            @{ N='Status'; E={
                $s = ''
                if ($_.AlreadyInstalled)  { $s += '[*]' }
                if ($_.UpdateAvailable)   { $s += '[↑]' }
                if ($_.LocallyModified)   { $s += '[~]' }
                if ($_.RequiresSetup)     { $s += '[!]' }
                $s
            }},
            @{ N='Name';        E={ $_.Name } },
            @{ N='Description'; E={ $_.Description } })

        $picked = $display | Show-OGV -Title "Select $Category   ★=Recommended (config-free)  [*]=Installed  [↑]=Update  [~]=Modified  [!]=Setup required" -PassThru
        if (-not $picked) { return @() }
        $pickedNames = @($picked | Where-Object { $_.Name -ne '-- none / skip --' } | ForEach-Object { $_.Name })
        return @($Items | Where-Object { $pickedNames -contains $_.Name })
    }

    # Fallback: numbered console menu
    Write-Host ""
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        $status = ''
        if ($item.AlreadyInstalled) { $status += '[*]' }
        if ($item.UpdateAvailable)  { $status += '[↑]' }
        if ($item.LocallyModified)  { $status += '[~]' }
        $rec  = if ($item.IsRecommended) { '[★]' } elseif ($item.RequiresSetup) { '[!]' } else { '   ' }
        $color = if ($item.UpdateAvailable) { 'Cyan' } elseif ($item.AlreadyInstalled) { 'DarkCyan' } elseif ($item.IsRecommended) { 'Yellow' } elseif ($item.RequiresSetup) { 'DarkYellow' } else { 'White' }
        Write-Host ("  {0,3}. {1} {2,-6} {3}" -f ($i+1), $rec, $status, $item.Name) -ForegroundColor $color
        if ($item.Description) {
            Write-Host ("             {0}" -f $item.Description) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  Enter numbers to install (e.g. 1,3,5 or 1-3 or 'all' or blank to skip): " -NoNewline -ForegroundColor Yellow
    $input = Read-Host

    if (-not $input -or $input.Trim() -eq '') { return @() }
    if ($input.Trim() -eq 'all') { return $Items }

    $indices = @()
    foreach ($part in $input.Split(',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $indices += ([int]$Matches[1])..[int]$Matches[2]
        } elseif ($part -match '^\d+$') {
            $indices += [int]$part
        }
    }
    return @($Items | Where-Object { $indices -contains ([Array]::IndexOf($Items, $_) + 1) })
}

function Select-ToRemove {
    <#
    .SYNOPSIS
    Shows a picker of script-managed installed items and returns those the user wants to remove.
    Only items recorded in .copilot-subscriptions.json are offered — never user-created files.
    Locally-modified items are flagged with [~] as a removal warning.
    #>
    param(
        [string]$Category,
        [object[]]$Items    # full catalogue with ManagedByScript, LocallyModified flags
    )

    # Only offer items this script installed — never user-created files
    $removable = @($Items | Where-Object { $_.AlreadyInstalled -and $_.ManagedByScript })
    if ($removable.Count -eq 0) {
        Log "No script-managed $Category to remove." 'INFO'
        return @()
    }

    $ogvAvailable = $false
    try { Get-Command Out-GridView -ErrorAction Stop | Out-Null; $ogvAvailable = $true } catch {}

    if ($ogvAvailable) {
        $none    = [pscustomobject]@{ Modified=''; Name='-- none / skip --'; Description='Select this (or nothing) to remove nothing' }
        $display = @($none) + @($removable | Select-Object `
            @{ N='Modified';    E={ if ($_.LocallyModified) { '[~] MODIFIED' } else { '' } } },
            @{ N='Name';        E={ $_.Name } },
            @{ N='Description'; E={ $_.Description } })
        $picked = $display | Show-OGV -Title "Select $Category to REMOVE   [~]=Locally modified (removal is permanent)" -PassThru
        if (-not $picked) { return @() }
        $pickedNames = @($picked | Where-Object { $_.Name -ne '-- none / skip --' } | ForEach-Object { $_.Name })
        return @($removable | Where-Object { $pickedNames -contains $_.Name })
    }

    Write-Host ""
    Write-Host "  === Remove $Category ===" -ForegroundColor Red
    Write-Host "  [~] = locally modified — removal is permanent" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $removable.Count; $i++) {
        $mod   = if ($removable[$i].LocallyModified) { '[~]' } else { '   ' }
        $color = if ($removable[$i].LocallyModified) { 'Yellow' } else { 'DarkCyan' }
        Write-Host ("  {0,3}. {1} {2}" -f ($i+1), $mod, $removable[$i].Name) -ForegroundColor $color
        if ($removable[$i].Description) {
            Write-Host ("           {0}" -f $removable[$i].Description) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  Enter numbers to REMOVE (e.g. 1,3 or blank to skip): " -NoNewline -ForegroundColor Red
    $input = Read-Host
    if (-not $input -or $input.Trim() -eq '') { return @() }

    $indices = @()
    foreach ($part in $input.Split(',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $indices += ([int]$Matches[1])..[int]$Matches[2]
        } elseif ($part -match '^\d+$') {
            $indices += [int]$part
        }
    }
    return @($removable | Where-Object { $indices -contains ([Array]::IndexOf($removable, $_) + 1) })
}

function Remove-File {
    param([string]$FilePath)
    if ($DryRun) { return 'would-remove' }
    if (Test-Path $FilePath) { Remove-Item $FilePath -Force; return 'removed' }
    return 'not-found'
}

function Remove-Directory {
    param([string]$DirPath)
    if ($DryRun) { return 'would-remove' }
    if (Test-Path $DirPath) { Remove-Item $DirPath -Recurse -Force; return 'removed' }
    return 'not-found'
}

function Install-File {
    param([string]$Src, [string]$DestDir)
    if (-not $DryRun -and -not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    $dest = Join-Path $DestDir (Split-Path $Src -Leaf)
    $srcHash = (Get-FileHash $Src -Algorithm SHA256).Hash
    $dstHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { $null }
    if ($srcHash -eq $dstHash) { return 'unchanged' }
    if ($DryRun) { return 'would-copy' }
    Copy-Item $Src $dest -Force
    if ($dstHash) { return 'updated' } else { return 'added' }
}

function Install-Directory {
    param([string]$SrcDir, [string]$DestParent)
    $name    = Split-Path $SrcDir -Leaf
    $destDir = Join-Path $DestParent $name
    if (-not $DryRun -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    $added = 0; $updated = 0; $unchanged = 0
    Get-ChildItem $SrcDir -File -Recurse | ForEach-Object {
        $rel     = $_.FullName.Substring($SrcDir.Length).TrimStart('\','/')
        $dest    = Join-Path $destDir $rel
        $destDir2 = Split-Path $dest -Parent
        if (-not $DryRun -and -not (Test-Path $destDir2)) {
            New-Item -ItemType Directory -Path $destDir2 -Force | Out-Null
        }
        $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $dstHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { $null }
        if ($srcHash -ne $dstHash) {
            if (-not $DryRun) { Copy-Item $_.FullName $dest -Force }
            if ($dstHash) { $updated++ } else { $added++ }
        } else { $unchanged++ }
    }
    return [pscustomobject]@{ Added = $added; Updated = $updated; Unchanged = $unchanged }
}

function Get-Description([string]$FilePath) {
    try {
        $lines = Get-Content $FilePath -TotalCount 20 -ErrorAction SilentlyContinue
        # YAML frontmatter description field
        $inFrontmatter = $false
        foreach ($line in $lines) {
            if ($line -eq '---') { $inFrontmatter = -not $inFrontmatter; continue }
            if ($inFrontmatter -and $line -match '^description:\s*(.+)') { return $Matches[1].Trim('"''') }
        }
        # First non-heading markdown line
        foreach ($line in $lines) {
            if ($line -match '^#{1,3}\s+(.+)') { return $Matches[1] }
        }
    } catch {}
    return ''
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

function Measure-ItemRelevance {
    <#
    .SYNOPSIS
    Scores an item's relevance against detected tech keywords.
    .DESCRIPTION
    Checks both the item's name (stronger signal, weight 2) and the first 30 lines of
    its content or README.md (for directories) against each keyword using word-boundary
    matching.  Returns a total score; 0 means no relevance detected.
    #>
    param(
        [string]   $ItemName,
        [string]   $FilePath,
        [string[]] $Tags
    )

    if (-not $Tags -or $Tags.Count -eq 0) { return 0 }

    $score    = 0
    $nameLower = $ItemName.ToLower()

    foreach ($tag in $Tags) {
        $pattern = "(?i)\b$([regex]::Escape($tag.ToLower()))\b"
        if ($nameLower -match $pattern) { $score += 2 }
    }

    # For directories, score against README.md / SKILL.md content
    $contentFile = $FilePath
    if ($FilePath -and (Test-Path $FilePath -PathType Container)) {
        $readme = Join-Path $FilePath 'README.md'
        if (-not (Test-Path $readme)) { $readme = Join-Path $FilePath 'SKILL.md' }
        $contentFile = if (Test-Path $readme) { $readme } else { $null }
    }

    if ($contentFile -and (Test-Path $contentFile -PathType Leaf)) {
        try {
            $text = ((Get-Content $contentFile -TotalCount 30 -ErrorAction SilentlyContinue) -join ' ').ToLower()
            foreach ($tag in $Tags) {
                $pattern = "(?i)\b$([regex]::Escape($tag.ToLower()))\b"
                if ($text -match $pattern) { $score++ }
            }
        } catch {}
    }

    return $score
}

function Update-Subscriptions {
    param([string]$ManifestPath, [object[]]$NewEntries)
    if (-not $NewEntries -or $NewEntries.Count -eq 0) { return }

    $subs = $null
    if (Test-Path $ManifestPath) {
        try { $subs = Get-Content $ManifestPath -Raw | ConvertFrom-Json } catch {}
    }
    if (-not $subs) {
        $subs = [pscustomobject]@{ version = 1; updatedAt = ''; subscriptions = @() }
    }

    $existing = [System.Collections.Generic.List[object]]::new()
    if ($subs.subscriptions) { $existing.AddRange([object[]]$subs.subscriptions) }

    foreach ($entry in $NewEntries) {
        $idx = -1
        for ($i = 0; $i -lt $existing.Count; $i++) {
            if ($existing[$i].name -eq $entry.name -and $existing[$i].category -eq $entry.category) {
                $idx = $i; break
            }
        }
        if ($idx -ge 0) { $existing[$idx] = $entry } else { $existing.Add($entry) }
    }

    $subs | Add-Member -NotePropertyName 'updatedAt'     -NotePropertyValue (Get-Date).ToString('o') -Force
    $subs | Add-Member -NotePropertyName 'subscriptions' -NotePropertyValue $existing.ToArray()      -Force

    if (-not $DryRun) {
        $dir = Split-Path $ManifestPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $subs | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath -Encoding UTF8
        Log "Updated subscriptions: $ManifestPath"
    } else {
        Log "[DryRun] Would update subscriptions: $ManifestPath ($($NewEntries.Count) new/updated entries)"
    }
}

#endregion # Helpers

#region Catalogue builders
$totalInstalled = 0

function Test-RequiresSetup([string]$FilePath) {
    # Returns $true if the file/dir requires external setup (MCP server, API key, etc.)
    # These items are never starred as recommendations.
    $contentFile = $FilePath
    if (Test-Path $FilePath -PathType Container) {
        $readme = Join-Path $FilePath 'README.md'
        if (-not (Test-Path $readme)) { $readme = Join-Path $FilePath 'SKILL.md' }
        $contentFile = if (Test-Path $readme) { $readme } else { $null }
    }
    if (-not $contentFile -or -not (Test-Path $contentFile)) { return $false }
    try {
        $text = (Get-Content $contentFile -Raw -ErrorAction SilentlyContinue)
        return $text -match 'mcp-servers:|_API_KEY\b|COPILOT_MCP_'
    } catch { return $false }
}

function Build-FlatCatalogue([string]$CatDir, [string]$DestDir, [string]$Pattern, [string]$Category) {
    if (-not (Test-Path $CatDir)) { return @() }
    Get-ChildItem $CatDir -File | Where-Object { $_.Name -match $Pattern } | ForEach-Object {
        $destFile  = Join-Path $DestDir $_.Name
        $itemName  = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.(instructions|agent|prompt|chatmode)$',''
        $subKey    = "$Category|$itemName"
        $subEntry  = $script:SubIndex[$subKey]
        $installed = Test-Path $destFile

        $updateAvailable  = $false
        $locallyModified  = $false
        $managedByScript  = $null -ne $subEntry

        if ($installed -and $subEntry) {
            $srcHash     = (Get-FileHash $_.FullName   -Algorithm SHA256).Hash
            $currentHash = (Get-FileHash $destFile     -Algorithm SHA256).Hash
            $locallyModified  = $currentHash -ne $subEntry.hashAtInstall
            $updateAvailable  = $srcHash -ne $currentHash
        }

        [pscustomobject]@{
            Name             = $itemName
            FileName         = $_.Name
            FullPath         = $_.FullName
            Description      = Get-Description $_.FullName
            RequiresSetup    = Test-RequiresSetup $_.FullName
            AlreadyInstalled = $installed
            ManagedByScript  = $managedByScript
            UpdateAvailable  = $updateAvailable
            LocallyModified  = $locallyModified
        }
    } | Sort-Object Name
}

function Build-DirCatalogue([string]$CatDir, [string]$DestDir, [string]$Category) {
    if (-not (Test-Path $CatDir)) { return @() }
    Get-ChildItem $CatDir -Directory | ForEach-Object {
        $destSubdir = Join-Path $DestDir $_.Name
        $readmePath = Join-Path $_.FullName 'README.md'
        if (-not (Test-Path $readmePath)) { $readmePath = Join-Path $_.FullName 'SKILL.md' }
        $subKey   = "$Category|$($_.Name)"
        $subEntry = $script:SubIndex[$subKey]
        $installed = Test-Path $destSubdir

        $updateAvailable = $false
        $locallyModified = $false
        $managedByScript = $null -ne $subEntry

        if ($installed -and $subEntry) {
            $srcHash     = Get-DirHash $_.FullName
            $currentHash = Get-DirHash $destSubdir
            $locallyModified  = $currentHash -ne $subEntry.hashAtInstall
            $updateAvailable  = $srcHash -ne $currentHash
        }

        [pscustomobject]@{
            Name             = $_.Name
            FullPath         = $_.FullName
            Description      = if (Test-Path $readmePath) { Get-Description $readmePath } else { '' }
            RequiresSetup    = Test-RequiresSetup $_.FullName
            AlreadyInstalled = $installed
            ManagedByScript  = $managedByScript
            UpdateAvailable  = $updateAvailable
            LocallyModified  = $locallyModified
        }
    } | Sort-Object Name
}

#endregion # Catalogue builders

#region Subscription manifest
$script:SubscriptionEntries   = [System.Collections.Generic.List[object]]::new()
$SubscriptionManifestPath     = Join-Path $GithubDir '.copilot-subscriptions.json'

# Load existing manifest into a lookup: "category|name" -> subscription entry
$script:SubIndex = @{}
if (Test-Path $SubscriptionManifestPath) {
    try {
        $existingSubs = Get-Content $SubscriptionManifestPath -Raw | ConvertFrom-Json
        if ($existingSubs.subscriptions) {
            foreach ($s in $existingSubs.subscriptions) {
                $script:SubIndex["$($s.category)|$($s.name)"] = $s
            }
        }
    } catch { Log "Could not parse subscriptions manifest: $_" 'WARN' }
}

function Remove-SubscriptionEntries {
    param([string]$ManifestPath, [string[]]$Keys)  # Keys = "category|name"
    if (-not (Test-Path $ManifestPath)) { return }
    if ($DryRun) { Log "[DryRun] Would remove $($Keys.Count) subscription(s) from manifest"; return }
    try {
        $subs = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        if (-not $subs.subscriptions) { return }
        $kept = @($subs.subscriptions | Where-Object { $Keys -notcontains "$($_.category)|$($_.name)" })
        $subs | Add-Member -NotePropertyName 'subscriptions' -NotePropertyValue $kept   -Force
        $subs | Add-Member -NotePropertyName 'updatedAt'     -NotePropertyValue (Get-Date).ToString('o') -Force
        $subs | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath -Encoding UTF8
    } catch { Log "Could not update subscriptions manifest: $_" 'WARN' }
}

#endregion # Subscription manifest

#region Pre-load all catalogues
$script:AllCatalogues = [System.Collections.Generic.List[object]]::new()

# When uninstalling, skip building catalogues for categories with nothing installed
function Should-LoadCatalogue([string]$Category, [string]$DestDir, [switch]$IsSkipped) {
    if ($IsSkipped) { return $false }
    if ($Uninstall) { return (Test-Path $DestDir) -and ((Get-ChildItem $DestDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) }
    return $true
}

Log "Loading resource catalogues..."
$catAgents       = if (Should-LoadCatalogue 'agents'       (Join-Path $GithubDir 'agents')       -IsSkipped:$SkipAgents)       { Build-FlatCatalogue (Join-Path $SourceRoot 'agents')       (Join-Path $GithubDir 'agents')       '\.agent\.md$'        'agents'       } else { @() }
$catInstructions = if (Should-LoadCatalogue 'instructions' (Join-Path $GithubDir 'instructions') -IsSkipped:$SkipInstructions) { Build-FlatCatalogue (Join-Path $SourceRoot 'instructions') (Join-Path $GithubDir 'instructions') '\.instructions\.md$' 'instructions' } else { @() }
$catHooks        = if (Should-LoadCatalogue 'hooks'        (Join-Path $GithubDir 'hooks')        -IsSkipped:$SkipHooks)        { Build-DirCatalogue  (Join-Path $SourceRoot 'hooks')        (Join-Path $GithubDir 'hooks')                               'hooks'        } else { @() }
$catWorkflows    = if (Should-LoadCatalogue 'workflows'    (Join-Path $GithubDir 'workflows')    -IsSkipped:$SkipWorkflows)    { Build-FlatCatalogue (Join-Path $SourceRoot 'workflows')    (Join-Path $GithubDir 'workflows')    '\.md$'               'workflows'    } else { @() }
$catSkills       = if (Should-LoadCatalogue 'skills'       (Join-Path $GithubDir 'skills')       -IsSkipped:$SkipSkills)       { Build-DirCatalogue  (Join-Path $SourceRoot 'skills')       (Join-Path $GithubDir 'skills')                              'skills'       } else { @() }
Log "Catalogues loaded. Opening pickers..."

#endregion # Pre-load all catalogues

#region Agents

if (-not $SkipAgents) {
    $destDir   = Join-Path $GithubDir 'agents'
    $catalogue = $catAgents
    $script:AllCatalogues.Add([pscustomobject]@{ Category='agents'; Type='file'; Items=$catalogue; DestDir=$destDir })

    if ($Uninstall) {
        $toRemove = Select-ToRemove -Category 'Agents' -Items $catalogue
        foreach ($item in $toRemove) {
            $result = Remove-File -FilePath (Join-Path $destDir $item.FileName)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  agent: $($item.FileName)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-SubscriptionEntries -ManifestPath $SubscriptionManifestPath -Keys @($toRemove | ForEach-Object { "agents|$($_.Name)" })
        }
    } else {
        # Agents: also score on 'security' since security-reviewer agents are universally useful
        $agentTags = @($script:Recommendations) + 'security' | Sort-Object -Unique
        $selected  = Select-Items -Category 'Agents' -Items $catalogue -PreSelected $Agents -Tags $agentTags

        foreach ($item in $selected) {
            $result = Install-File -Src $item.FullPath -DestDir $destDir
            $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
            Log "$verb  agent: $($item.FileName)"
            if ($result -in 'added','updated','would-copy') { $totalInstalled++ }
            $script:SubscriptionEntries.Add([pscustomobject]@{
                name          = $item.Name
                category      = 'agents'
                type          = 'file'
                fileName      = $item.FileName
                sourceRelPath = "agents/$($item.FileName)"
                hashAtInstall = (Get-FileHash $item.FullPath -Algorithm SHA256).Hash
                installedAt   = (Get-Date).ToString('o')
            })
        }
    }
}

#endregion # Agents

#region Instructions
if (-not $SkipInstructions) {
    $destDir  = Join-Path $GithubDir 'instructions'
    $catalogue = $catInstructions
    $script:AllCatalogues.Add([pscustomobject]@{ Category='instructions'; Type='file'; Items=$catalogue; DestDir=$destDir })

    if ($Uninstall) {
        $toRemove = Select-ToRemove -Category 'Instructions' -Items $catalogue
        foreach ($item in $toRemove) {
            $result = Remove-File -FilePath (Join-Path $destDir $item.FileName)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  instructions: $($item.FileName)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-SubscriptionEntries -ManifestPath $SubscriptionManifestPath -Keys @($toRemove | ForEach-Object { "instructions|$($_.Name)" })
        }
    } else {
        $selected  = Select-Items -Category 'Instructions' -Items $catalogue -PreSelected $Instructions -Tags $script:Recommendations

        foreach ($item in $selected) {
            $result = Install-File -Src $item.FullPath -DestDir $destDir
            $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
            Log "$verb  instructions: $($item.FileName)"
            if ($result -in 'added','updated','would-copy') { $totalInstalled++ }
            $script:SubscriptionEntries.Add([pscustomobject]@{
                name          = $item.Name
                category      = 'instructions'
                type          = 'file'
                fileName      = $item.FileName
                sourceRelPath = "instructions/$($item.FileName)"
                hashAtInstall = (Get-FileHash $item.FullPath -Algorithm SHA256).Hash
                installedAt   = (Get-Date).ToString('o')
            })
        }
    }
}

#endregion # Instructions

#region Hooks
if (-not $SkipHooks) {
    $destDir   = Join-Path $GithubDir 'hooks'
    $catalogue  = $catHooks
    $script:AllCatalogues.Add([pscustomobject]@{ Category='hooks'; Type='directory'; Items=$catalogue; DestDir=$destDir })

    if ($Uninstall) {
        $toRemove = Select-ToRemove -Category 'Hooks' -Items $catalogue
        foreach ($item in $toRemove) {
            $result = Remove-Directory -DirPath (Join-Path $destDir $item.Name)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  hook: $($item.Name)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-SubscriptionEntries -ManifestPath $SubscriptionManifestPath -Keys @($toRemove | ForEach-Object { "hooks|$($_.Name)" })
        }
    } else {
        $selected   = Select-Items -Category 'Hooks' -Items $catalogue -PreSelected $Hooks -Tags $script:Recommendations

        foreach ($item in $selected) {
            $r = Install-Directory -SrcDir $item.FullPath -DestParent $destDir
            $verb = if ($DryRun) { '~ DryRun' } else { '✓ Installed' }
            Log "$verb  hook: $($item.Name) (added=$($r.Added) updated=$($r.Updated) unchanged=$($r.Unchanged))"
            if (-not $DryRun) { $totalInstalled++ }
            $script:SubscriptionEntries.Add([pscustomobject]@{
                name          = $item.Name
                category      = 'hooks'
                type          = 'directory'
                dirName       = $item.Name
                sourceRelPath = "hooks/$($item.Name)"
                hashAtInstall = Get-DirHash $item.FullPath
                installedAt   = (Get-Date).ToString('o')
            })
        }
    }
}

#endregion # Hooks

#region Workflows
if (-not $SkipWorkflows) {
    $destDir  = Join-Path $GithubDir 'workflows'
    $catalogue = $catWorkflows
    $script:AllCatalogues.Add([pscustomobject]@{ Category='workflows'; Type='file'; Items=$catalogue; DestDir=$destDir })

    if ($Uninstall) {
        $toRemove = Select-ToRemove -Category 'Agentic Workflows' -Items $catalogue
        foreach ($item in $toRemove) {
            $result = Remove-File -FilePath (Join-Path $destDir $item.FileName)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  workflow: $($item.FileName)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-SubscriptionEntries -ManifestPath $SubscriptionManifestPath -Keys @($toRemove | ForEach-Object { "workflows|$($_.Name)" })
        }
    } else {
        $selected  = Select-Items -Category 'Agentic Workflows' -Items $catalogue -PreSelected $Workflows -Tags $script:Recommendations

        foreach ($item in $selected) {
            $result = Install-File -Src $item.FullPath -DestDir $destDir
            $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
            Log "$verb  workflow: $($item.FileName)"
            if ($result -in 'added','updated','would-copy') { $totalInstalled++ }
            $script:SubscriptionEntries.Add([pscustomobject]@{
                name          = $item.Name
                category      = 'workflows'
                type          = 'file'
                fileName      = $item.FileName
                sourceRelPath = "workflows/$($item.FileName)"
                hashAtInstall = (Get-FileHash $item.FullPath -Algorithm SHA256).Hash
                installedAt   = (Get-Date).ToString('o')
            })
        }
    }
}

#endregion # Workflows

#region Skills
if (-not $SkipSkills) {
    $destDir   = Join-Path $GithubDir 'skills'
    $catalogue = $catSkills
    $script:AllCatalogues.Add([pscustomobject]@{ Category='skills'; Type='directory'; Items=$catalogue; DestDir=$destDir })

    if ($Uninstall) {
        $toRemove = Select-ToRemove -Category 'Skills' -Items $catalogue
        foreach ($item in $toRemove) {
            $result = Remove-Directory -DirPath (Join-Path $destDir $item.Name)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  skill: $($item.Name)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-SubscriptionEntries -ManifestPath $SubscriptionManifestPath -Keys @($toRemove | ForEach-Object { "skills|$($_.Name)" })
        }
    } else {
        $selected  = Select-Items -Category 'Skills' -Items $catalogue -PreSelected $Skills -Tags $script:Recommendations

        foreach ($item in $selected) {
            $r = Install-Directory -SrcDir $item.FullPath -DestParent $destDir
            $verb = if ($DryRun) { '~ DryRun' } else { '✓ Installed' }
            Log "$verb  skill: $($item.Name) (added=$($r.Added) updated=$($r.Updated) unchanged=$($r.Unchanged))"
            if (-not $DryRun) { $totalInstalled++ }
            $script:SubscriptionEntries.Add([pscustomobject]@{
                name          = $item.Name
                category      = 'skills'
                type          = 'directory'
                dirName       = $item.Name
                sourceRelPath = "skills/$($item.Name)"
                hashAtInstall = Get-DirHash $item.FullPath
                installedAt   = (Get-Date).ToString('o')
            })
        }
    }
}

#endregion # Skills

#region Summary

# Auto-adopt items that are already installed in .github/ but not yet in the manifest
# (e.g. installed by a previous version of this script before tracking was added).
# Uses the current installed file hash as hashAtInstall — they'll show [↑] if upstream has moved on.
if (-not $Uninstall -and -not $DryRun) {
    foreach ($cat in $script:AllCatalogues) {
        $untracked = @($cat.Items | Where-Object { $_.AlreadyInstalled -and -not $_.ManagedByScript })
        foreach ($item in $untracked) {
            $installedPath = if ($cat.Type -eq 'file') {
                Join-Path $cat.DestDir $item.FileName
            } else {
                Join-Path $cat.DestDir $item.Name
            }
            $adoptedHash = if ($cat.Type -eq 'file') {
                (Get-FileHash $installedPath -Algorithm SHA256).Hash
            } else {
                Get-DirHash $installedPath
            }
            $entry = [pscustomobject]@{
                name          = $item.Name
                category      = $cat.Category
                type          = $cat.Type
                installedAt   = (Get-Item $installedPath).LastWriteTime.ToString('o')
                hashAtInstall = $adoptedHash
                adopted       = $true   # flag so we know this was auto-adopted not explicitly chosen
            }
            if ($cat.Type -eq 'file') {
                $entry | Add-Member -NotePropertyName 'fileName'      -NotePropertyValue $item.FileName                              -Force
                $entry | Add-Member -NotePropertyName 'sourceRelPath' -NotePropertyValue "$($cat.Category)/$($item.FileName)"        -Force
            } else {
                $entry | Add-Member -NotePropertyName 'dirName'       -NotePropertyValue $item.Name                                  -Force
                $entry | Add-Member -NotePropertyName 'sourceRelPath' -NotePropertyValue "$($cat.Category)/$($item.Name)"            -Force
            }
            $script:SubscriptionEntries.Add($entry)
            Log "Adopted existing install into manifest: $($cat.Category)/$($item.Name)"
        }
    }
}

if ($script:SubscriptionEntries.Count -gt 0) {
    Update-Subscriptions -ManifestPath $SubscriptionManifestPath -NewEntries $script:SubscriptionEntries.ToArray()
}

Write-Host ""
if ($Uninstall) {
    Log "Uninstall complete." 'SUCCESS'
} elseif ($DryRun) {
    Log "Dry run complete. Re-run without -DryRun to apply." 'WARN'
} else {
    Log "$totalInstalled resource(s) installed/updated in $GithubDir" 'SUCCESS'
    Log "Tip: commit .github/ to share Copilot resources with your team (agents, instructions, hooks, workflows, skills)."
    Log "Tip: run update-repo.ps1 to check for and apply upstream changes to your subscribed resources."
    Log "Tip: run init-repo.ps1 -Uninstall to remove any installed resources."
}
#endregion # Summary
