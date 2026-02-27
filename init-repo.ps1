<#
Initialize a Repository with Copilot Resources

Interactively selects and installs non-global Copilot resources from the local
awesome-copilot cache into a target repository's .github/ folder.

Resources installed here are project-specific (opt-in) rather than global:

  Instructions  --> .github/instructions/*.instructions.md
  Hooks         --> .github/hooks/<hook-name>/   (full directory)
  Workflows     --> .github/workflows/*.md

Usage:
  # Interactive - run from within the target repo
  .\init-repo.ps1

  # Specify a repo path explicitly
  .\init-repo.ps1 -RepoPath "C:\Projects\my-app"

  # Skip specific categories
  .\init-repo.ps1 -SkipHooks -SkipWorkflows

  # Non-interactive: specify items by name (comma-separated)
  .\init-repo.ps1 -Instructions "angular,dotnet-framework" -Hooks "session-logger"
  # Dry run - show what would be installed
  .\init-repo.ps1 -DryRun

Notes:
  - Existing files are only overwritten if the source is newer/different.
  - .github/ is created if it doesn't exist.
  - This script does NOT touch global resources (agents, skills).
    Use publish-global.ps1 for those. For skills, point users directly
    at https://github.com/github/awesome-copilot.
  - The selection UI uses Out-GridView where available (Windows GUI, filterable,
    multi-select). Falls back to a numbered console menu automatically.
  - Auto-detects language/framework from repo file signals and pre-marks
    recommended instructions/hooks/workflows with ★ in the picker.
  - For new/empty repos, prompts for intent one question at a time.
#>
[CmdletBinding()] param(
    [string]$RepoPath      = (Get-Location).Path,
    [string]$SourceRoot    = "$HOME/.awesome-copilot",
    [string]$Instructions  = '',   # Comma-separated names to pre-select (non-interactive)
    [string]$Hooks         = '',
    [string]$Workflows     = '',
    [switch]$SkipInstructions,
    [switch]$SkipHooks,
    [switch]$SkipWorkflows,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# Detect language/framework signals from repo files
# ---------------------------------------------------------------------------
function Detect-RepoStack {
    param([string]$RepoPath)

    $recs = [System.Collections.Generic.List[string]]::new()
    $files = Get-ChildItem $RepoPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|\.venv|bin|obj)\\' }

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

    if ($hasDotnet)            { $recs.Add('csharp'); $recs.Add('dotnet-architecture-good-practices') }
    if ($hasPy)                { $recs.Add('python') }
    if ($hasTs)                { $recs.Add('typescript-5-es2022') }
    if ($hasGo)                { $recs.Add('go') }
    if ($hasRs)                { $recs.Add('rust') }
    if ($hasJava -or $hasKt)   { $recs.Add('java') }
    if ($hasTf)                { $recs.Add('terraform') }
    if ($hasBicep)             { $recs.Add('bicep-code-best-practices') }
    if ($hasPs1)               { $recs.Add('powershell') }

    # Docker
    if (($names -contains 'Dockerfile') -or ($names | Where-Object { $_ -match '^docker-compose\.yml$' })) {
        $recs.Add('containerization-docker-best-practices')
    }

    # GitHub Actions workflows
    $ghWorkflows = $files | Where-Object { $_.FullName -match '\\\.github\\workflows\\' -and $_.Extension -eq '.yml' }
    if ($ghWorkflows) { $recs.Add('github-actions-ci-cd-best-practices') }

    # Playwright
    $hasPlaywright = $files | Where-Object { $_.Name -match '^playwright\.config\.' }
    if ($hasPlaywright) {
        if ($hasDotnet)   { $recs.Add('playwright-dotnet') }
        elseif ($hasPy)   { $recs.Add('playwright-python') }
        else              { $recs.Add('playwright-typescript') }
    }

    # package.json framework detection
    $pkgJson = $files | Where-Object { $_.Name -eq 'package.json' } | Select-Object -First 1
    if ($pkgJson) {
        try {
            $pkg = Get-Content $pkgJson.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            $allDeps = @()
            if ($pkg.dependencies)    { $allDeps += $pkg.dependencies.PSObject.Properties.Name }
            if ($pkg.devDependencies) { $allDeps += $pkg.devDependencies.PSObject.Properties.Name }
            if ($allDeps -contains 'react')    { $recs.Add('reactjs') }
            if ($allDeps -contains 'next')     { $recs.Add('nextjs') }
            if ($allDeps | Where-Object { $_ -match '^@angular/' }) { $recs.Add('angular') }
            if ($allDeps -contains 'vue')      { $recs.Add('vuejs3') }
            if ($allDeps -contains 'svelte')   { $recs.Add('svelte') }
            if ($allDeps | Where-Object { $_ -match '^@nestjs/' }) { $recs.Add('nestjs') }
        } catch {}
    }

    $recs.Add('security-and-owasp')
    $recs.Add('code-review-generic')

    return @($recs | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# Prompt for intent when no signals detected (new/empty repo)
# ---------------------------------------------------------------------------
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
        '1' { $recs.Add('csharp'); $recs.Add('dotnet-architecture-good-practices') }
        '2' { $recs.Add('python') }
        '3' { $recs.Add('typescript-5-es2022') }
        '4' { $recs.Add('go') }
        '5' { $recs.Add('java') }
        '6' { $recs.Add('rust') }
        '7' { $recs.Add('powershell') }
        '8' { $recs.Add('terraform'); $recs.Add('bicep-code-best-practices') }
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
    $null = Read-Host  # no mapping yet, reserved for future extensibility

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
                '1' { $recs.Add('security-and-owasp') }
                '2' { $recs.Add('a11y') }
                '3' { $recs.Add('playwright-typescript') }
                '4' { $recs.Add('performance-optimization') }
                '5' { $recs.Add('containerization-docker-best-practices') }
                '6' { $recs.Add('github-actions-ci-cd-best-practices') }
            }
        }
    }

    $recs.Add('code-review-generic')
    return @($recs | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# Validate paths
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Auto-detect stack or prompt for intent
# ---------------------------------------------------------------------------
$script:Recommendations = @()
if (-not ($SkipInstructions -and $SkipHooks -and $SkipWorkflows)) {
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

# ---------------------------------------------------------------------------
# Helper: interactive picker
#   Returns array of selected names.
#   preSelected: comma-separated list for non-interactive mode.
# ---------------------------------------------------------------------------
function Select-Items {
    param(
        [string]$Category,
        [object[]]$Items,          # objects with Name, Description, AlreadyInstalled
        [string]$PreSelected = '',
        [string[]]$Recommended = @()
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

    # Attach IsRecommended and sort: recommended first, then alphabetical within groups
    $Items = $Items | ForEach-Object {
        $_ | Add-Member -NotePropertyName 'IsRecommended' -NotePropertyValue ($Recommended -contains $_.Name) -PassThru -Force
    } | Sort-Object @{ E={ if ($_.IsRecommended) { 0 } else { 1 } } }, Name

    Write-Host ""
    Write-Host "  === $Category ===" -ForegroundColor Yellow
    Write-Host "  Already installed items are marked with [*]" -ForegroundColor DarkGray

    # Try Out-GridView (Windows GUI - filterable, multi-select)
    $ogvAvailable = $false
    try { Get-Command Out-GridView -ErrorAction Stop | Out-Null; $ogvAvailable = $true } catch {}

    if ($ogvAvailable) {
        $display = $Items | Select-Object `
            @{ N='Rec';       E={ if ($_.IsRecommended) { '★' } else { '' } } },
            @{ N='Installed'; E={ if ($_.AlreadyInstalled) { '[*]' } else { '' } } },
            @{ N='Name';      E={ $_.Name } },
            @{ N='Description'; E={ $_.Description } }

        $picked = $display | Out-GridView -Title "Select $Category to install   ★ = Recommended   [*] = Already installed" -PassThru
        if (-not $picked) { return @() }
        $pickedNames = @($picked | ForEach-Object { $_.Name })
        return @($Items | Where-Object { $pickedNames -contains $_.Name })
    }

    # Fallback: numbered console menu
    Write-Host ""
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $mark = if ($Items[$i].AlreadyInstalled) { '[*]' } elseif ($Items[$i].IsRecommended) { '[★]' } else { '   ' }
        Write-Host ("  {0,3}. {1} {2}" -f ($i+1), $mark, $Items[$i].Name) -ForegroundColor $(if ($Items[$i].AlreadyInstalled) { 'DarkCyan' } elseif ($Items[$i].IsRecommended) { 'Yellow' } else { 'White' })
        if ($Items[$i].Description) {
            Write-Host ("       {0}" -f $Items[$i].Description) -ForegroundColor DarkGray
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
    return @($Items | Where-Object { $indices -contains ($Items.IndexOf($_) + 1) })
}

# ---------------------------------------------------------------------------
# Helper: copy a single flat file to a target directory
# ---------------------------------------------------------------------------
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
    return if ($dstHash) { 'updated' } else { 'added' }
}

# ---------------------------------------------------------------------------
# Helper: copy an entire subdirectory (for hooks and skills)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Helper: read description from a file's frontmatter or first heading
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Build catalogue entries for each category
# ---------------------------------------------------------------------------
$totalInstalled = 0

function Build-FlatCatalogue([string]$CatDir, [string]$DestDir, [string]$Pattern) {
    if (-not (Test-Path $CatDir)) { return @() }
    Get-ChildItem $CatDir -File | Where-Object { $_.Name -match $Pattern } | ForEach-Object {
        $destFile = Join-Path $DestDir $_.Name
        [pscustomobject]@{
            Name             = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.(instructions|agent|prompt|chatmode)$',''
            FileName         = $_.Name
            FullPath         = $_.FullName
            Description      = Get-Description $_.FullName
            AlreadyInstalled = (Test-Path $destFile)
        }
    } | Sort-Object Name
}

function Build-DirCatalogue([string]$CatDir, [string]$DestDir) {
    if (-not (Test-Path $CatDir)) { return @() }
    Get-ChildItem $CatDir -Directory | ForEach-Object {
        $destSubdir = Join-Path $DestDir $_.Name
        $readmePath = Join-Path $_.FullName 'README.md'
        if (-not (Test-Path $readmePath)) { $readmePath = Join-Path $_.FullName 'SKILL.md' }
        [pscustomobject]@{
            Name             = $_.Name
            FullPath         = $_.FullName
            Description      = if (Test-Path $readmePath) { Get-Description $readmePath } else { '' }
            AlreadyInstalled = (Test-Path $destSubdir)
        }
    } | Sort-Object Name
}

# ---------------------------------------------------------------------------
# INSTRUCTIONS
# ---------------------------------------------------------------------------
if (-not $SkipInstructions) {
    $destDir  = Join-Path $GithubDir 'instructions'
    $catalogue = Build-FlatCatalogue (Join-Path $SourceRoot 'instructions') $destDir '\.instructions\.md$'
    $selected  = Select-Items -Category 'Instructions' -Items $catalogue -PreSelected $Instructions -Recommended $script:Recommendations

    foreach ($item in $selected) {
        $result = Install-File -Src $item.FullPath -DestDir $destDir
        $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
        Log "$verb  instructions: $($item.FileName)"
        if ($result -in 'added','updated','would-copy') { $totalInstalled++ }
    }
}

# ---------------------------------------------------------------------------
# HOOKS
# ---------------------------------------------------------------------------
if (-not $SkipHooks) {
    $destDir   = Join-Path $GithubDir 'hooks'
    $catalogue  = Build-DirCatalogue (Join-Path $SourceRoot 'hooks') $destDir
    $selected   = Select-Items -Category 'Hooks' -Items $catalogue -PreSelected $Hooks -Recommended $script:Recommendations

    foreach ($item in $selected) {
        $r = Install-Directory -SrcDir $item.FullPath -DestParent $destDir
        $verb = if ($DryRun) { '~ DryRun' } else { '✓ Installed' }
        Log "$verb  hook: $($item.Name) (added=$($r.Added) updated=$($r.Updated) unchanged=$($r.Unchanged))"
        if (-not $DryRun) { $totalInstalled++ }
    }
}

# ---------------------------------------------------------------------------
# WORKFLOWS
# ---------------------------------------------------------------------------
if (-not $SkipWorkflows) {
    $destDir  = Join-Path $GithubDir 'workflows'
    $catalogue = Build-FlatCatalogue (Join-Path $SourceRoot 'workflows') $destDir '\.md$'
    $selected  = Select-Items -Category 'Agentic Workflows' -Items $catalogue -PreSelected $Workflows -Recommended $script:Recommendations

    foreach ($item in $selected) {
        $result = Install-File -Src $item.FullPath -DestDir $destDir
        $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
        Log "$verb  workflow: $($item.FileName)"
        if ($result -in 'added','updated','would-copy') { $totalInstalled++ }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
if ($DryRun) {
    Log "Dry run complete. Re-run without -DryRun to apply." 'WARN'
} else {
    Log "$totalInstalled resource(s) installed/updated in $GithubDir" 'SUCCESS'
    Log "Tip: commit .github/ to share these with your team."
}
