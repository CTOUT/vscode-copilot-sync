<#
Initialize User-Level Copilot Resources

Installs agents, instructions, and skills into user-level VS Code and Copilot
locations, making them available across all repos and VS Code windows — no .github/ needed.

  Agents       --> %APPDATA%\Code\User\prompts\*.agent.md
  Instructions --> %APPDATA%\Code\User\prompts\*.instructions.md
  Skills       --> ~/.copilot/skills/<skill-name>/

Subscription manifest stored at: ~/.awesome-copilot/user-subscriptions.json

Usage:
  # Interactive (agents + instructions + skills)
  .\init-user.ps1

  # Non-interactive: specify by name (comma-separated)
  .\init-user.ps1 -Agents "beastmode,se-security-reviewer"
  .\init-user.ps1 -Instructions "security-and-owasp,markdown-accessibility"
  .\init-user.ps1 -Skills "refactor,create-readme"

  # Skip specific categories
  .\init-user.ps1 -SkipSkills
  .\init-user.ps1 -SkipAgents -SkipInstructions

  # Target a non-default VS Code installation (e.g. Insiders)
  .\init-user.ps1 -PromptsDir "$env:APPDATA\Code - Insiders\User\prompts"

  # Dry run - show what would be installed
  .\init-user.ps1 -DryRun

  # Remove installed user-level resources
  .\init-user.ps1 -Uninstall

  # Bootstrap: register all already-installed cache-origin files into the manifest
  # without re-installing anything.  Use this when user-subscriptions.json is missing
  # but resources are already on disk (e.g. installed before v2.0.0, or after answering
  # N to the configure.ps1 prompt, or installed manually from the cache).
  .\init-user.ps1 -Bootstrap
  .\init-user.ps1 -Bootstrap -DryRun   # preview what would be registered

Notes:
  - Files are only overwritten if the source is newer/different.
  - The prompts folder and skills folder are created if they don't exist.
  - A subscription manifest (user-subscriptions.json) is written to the cache
    folder (~/.awesome-copilot/). Run update-user.ps1 to check for upstream changes.
  - The selection UI uses Out-GridView where available (Windows GUI, filterable,
    multi-select). Falls back to a numbered console menu automatically.
  - Only script-managed resources (recorded in user-subscriptions.json) are offered
    for removal — user-created files are never touched.
  - Only general-purpose (tech-agnostic) items are starred ★ in the picker.
    Tech-specific items (e.g. azure-, python-, react-) are still available but
    not pre-marked as recommended.
#>
[CmdletBinding()] param(
    [string]$SourceRoot   = "$HOME/.awesome-copilot",
    [string]$PromptsDir   = "$env:APPDATA\Code\User\prompts",
    [string]$SkillsDir    = "$HOME/.copilot/skills",
    [string]$Agents       = '',   # Comma-separated names to pre-select (non-interactive)
    [string]$Instructions = '',
    [string]$Skills       = '',
    [switch]$SkipAgents,
    [switch]$SkipInstructions,
    [switch]$SkipSkills,
    [switch]$DryRun,
    [switch]$Uninstall,  # Show a picker of installed items to remove instead of installing
    [switch]$Bootstrap   # Register all already-installed cache-origin files; no pickers, no file copies
)

#region Initialisation
$ErrorActionPreference = 'Stop'

function Log($m, [string]$level = 'INFO') {
    $ts = (Get-Date).ToString('s')
    $color = switch ($level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'Cyan' } }
    Write-Host "[$ts][$level] $m" -ForegroundColor $color
}

function Show-OGV {
    # Wrapper around Out-GridView that flashes the taskbar button and prints
    # a console hint — the most reliable way to alert the user since Windows
    # prevents focus-stealing from background processes by design.
    param([Parameter(ValueFromPipeline)][object[]]$InputObject, [string]$Title, [string]$SearchKey, [switch]$PassThru)
    begin   { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($i in $InputObject) { $all.Add($i) } }
    end {
        Write-Host "  ► Selection window opening — check your taskbar if it appears behind other apps." -ForegroundColor Yellow
        if ($PassThru) { $result = $all | Out-GridView -Title $Title -PassThru }
        else           { $all | Out-GridView -Title $Title }
        if ($PassThru) { return $result }
    }
}

#endregion # Initialisation

#region Validation
if (-not (Test-Path $SourceRoot)) {
    Log "Cache not found: $SourceRoot -- run sync-awesome-copilot.ps1 first" 'ERROR'; exit 1
}

Log "VS Code user prompts : $PromptsDir"
Log "Copilot skills dir   : $SkillsDir"
Log "Copilot cache        : $SourceRoot"

#endregion # Validation

#region Helpers

function Get-Description([string]$FilePath) {
    try {
        $lines = Get-Content $FilePath -TotalCount 20 -ErrorAction SilentlyContinue
        # YAML frontmatter description field
        $inFrontmatter = $false
        foreach ($line in $lines) {
            if ($line -eq '---') { $inFrontmatter = -not $inFrontmatter; continue }
            if ($inFrontmatter -and $line -match '^description:\s*(.+)') { return $Matches[1].Trim('"''') }
        }
        # First heading line as fallback
        foreach ($line in $lines) {
            if ($line -match '^#{1,3}\s+(.+)') { return $Matches[1] }
        }
    } catch {}
    return ''
}

function Install-File {
    param([string]$Src, [string]$DestDir)
    if (-not $DryRun -and -not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    $dest    = Join-Path $DestDir (Split-Path $Src -Leaf)
    $srcHash = (Get-FileHash $Src -Algorithm SHA256).Hash
    $dstHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { $null }
    if ($srcHash -eq $dstHash) { return 'unchanged' }
    if ($DryRun) { return 'would-copy' }
    Copy-Item $Src $dest -Force
    if ($dstHash) { return 'updated' } else { return 'added' }
}

function Remove-File {
    param([string]$FilePath)
    if ($DryRun) { return 'would-remove' }
    if (Test-Path $FilePath) { Remove-Item $FilePath -Force; return 'removed' }
    return 'not-found'
}

function Get-DirHash([string]$DirPath) {
    $hashes   = Get-ChildItem $DirPath -Recurse -File | Sort-Object FullName |
                ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    $combined = $hashes -join '|'
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $stream   = [System.IO.MemoryStream]::new($bytes)
    return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
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
        $rel      = $_.FullName.Substring($SrcDir.Length).TrimStart('\','/')
        $dest     = Join-Path $destDir $rel
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

function Remove-Directory {
    param([string]$DirPath)
    if ($DryRun) { return 'would-remove' }
    if (Test-Path $DirPath) { Remove-Item $DirPath -Recurse -Force; return 'removed' }
    return 'not-found'
}

function Test-RequiresSetup([string]$FilePath) {
    if (-not $FilePath -or -not (Test-Path $FilePath)) { return $false }
    try {
        $text = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
        return $text -match 'mcp-servers:|_API_KEY\b|COPILOT_MCP_'
    } catch { return $false }
}

function Update-UserSubscriptions {
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
        Log "Updated user subscriptions: $ManifestPath"
    } else {
        Log "[DryRun] Would update user subscriptions: $ManifestPath ($($NewEntries.Count) new/updated entries)"
    }
}

function Remove-UserSubscriptionEntries {
    param([string]$ManifestPath, [string[]]$Keys)  # Keys = "category|name"
    if (-not (Test-Path $ManifestPath)) { return }
    if ($DryRun) { Log "[DryRun] Would remove $($Keys.Count) subscription(s) from user manifest"; return }
    try {
        $subs = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        if (-not $subs.subscriptions) { return }
        $kept = @($subs.subscriptions | Where-Object { $Keys -notcontains "$($_.category)|$($_.name)" })
        $subs | Add-Member -NotePropertyName 'subscriptions' -NotePropertyValue $kept            -Force
        $subs | Add-Member -NotePropertyName 'updatedAt'     -NotePropertyValue (Get-Date).ToString('o') -Force
        $subs | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath -Encoding UTF8
    } catch { Log "Could not update user subscriptions manifest: $_" 'WARN' }
}

#endregion # Helpers

#region General-agent detection

# Name segments that indicate the agent is bound to a specific technology.
# An agent is NOT a general recommendation if any of these appear in its name.
$script:TechSpecificSegments = @(
    # Languages
    'csharp','dotnet','python','java','kotlin','go','rust','ruby','php','swift',
    'typescript','javascript','clojure',
    # Frontend / mobile / platform frameworks
    'react','angular','vue','nextjs','nuxt','svelte','ember','laravel','django',
    'android','ios','maui','winforms','winui','electron',
    'mobile',       # mobile development platform (iOS/Android/cross-platform)
    # Cloud & infrastructure
    'azure','aws','gcp','terraform','bicep','kubernetes','docker',
    'terratest',    # TerraTest — Terraform testing framework
    'kubestellar',  # KubeStellar — Kubernetes multi-cluster federation
    # Vendors & SaaS platforms
    'salesforce','shopify','atlassian','drupal','wordpress','pimcore',
    'amplitude','launchdarkly','comet','apify',
    'pagerduty','datadog','dynatrace','octopus','jfrog',
    'neon','diffblue','stackhawk','taxcore','cast',
    'monday',       # monday.com project management
    'aem',          # Adobe Experience Manager
    'lingodotdev',  # Lingo.dev i18n translation platform
    # Microsoft product & tooling suite
    'power','flowstudio',
    'defender',     # Microsoft Defender security platform
    'foundry',      # Azure AI Foundry
    'context7',     # Context7 MCP documentation server
    # Databases & query engines
    'neo4j','elasticsearch','mongodb','postgres','postgresql','mysql','oracle','redis',
    'kusto','spark',
    'kql',          # Kusto Query Language
    # Specific tooling
    'playwright','linux','github','powerbi','powershell','mcp',
    # Versioned / compound tech names (react18, react19, vuejs, winui3, cpp...)
    'cpp','vuejs','winui3','react18','react19'
)

# Name segments that positively identify a general-purpose, tech-agnostic agent.
# Used to award the ★ recommendation in the user-level picker.
$script:GeneralPositiveSegments = @(
    # Thinking modes & challenge
    'beast','mode','thinking','critical','advocate','devils',
    # Debug / review / quality (base forms + common -er/-ing/-ed derived forms)
    'debug','debugger','review','reviewer','doublecheck','check','critic','sentinel','alchemist',
    # Mentoring / coaching
    'mentor','mentoring','coach',
    # Planning / architecture
    'plan','planner','blueprint','adr','specification','architect','architecture',
    'implementation','task','research','researcher','spike','feature',
    # Language-agnostic engineering practices
    'tdd','devops','swe','qa','security','responsible','governance','owasp',
    'safety',       # agent-safety, AI/system safety practices
    'gitops',       # se-gitops-ci-specialist: GitOps workflows
    # Code quality & process
    'janitor','refine','refactor','debt','remediation','tour','simplifier',
    'modernization',# modernization: language-agnostic code modernisation
    # Engineering roles (new agent families: gem-*, se-*, software-engineer-*)
    'implementer',  # gem-implementer: implements features cross-stack
    'engineer',     # software-engineer-agent-v1: general SE work
    'designer',     # gem-designer: general UX/UI design
    'ux',           # se-ux-ui-designer: user experience design
    'evaluator',    # technical-content-evaluator: general evaluation
    'investigator', # devtools-regression-investigator: root-cause analysis
    'documenter',   # project-documenter: documentation generation
    # Writing & docs
    'writer','documentation',
    'localization', # localization: i18n and l10n practices (any stack)
    # Accessibility & quality standards
    'accessibility','a11y','performance',
    # Memory / cross-session
    'remember',
    'memory',       # memory-bank: AI memory management patterns
    # Understanding / learning
    'understand','understanding',
    # Polyglot / language-agnostic testing
    'polyglot',
    # Roles / orchestration
    'principal','droid','gilfoyle','orchestrator','conductor','advisor',
    # Prompt / addressing work
    'address','prompt','prd'
)

function Measure-GeneralRelevance([string]$ItemName) {
    <#
    .SYNOPSIS
    Returns a relevance score for user-level (repo-agnostic) display.
      0  = tech-specific or unknown — no star
      2+ = clearly general-purpose — show ★
    Handles both hyphenated names (e.g. 'critical-thinking') and CamelCase
    (e.g. 'CSharpExpert') by checking both split segments and, for CamelCase-
    only names, the lowercased-no-separator form.  The Contains() check is
    intentionally restricted to CamelCase names to avoid false positives on
    words like 'modernization' containing 'mode'.
    #>
    $segments   = $ItemName.ToLower() -split '-'
    $fullLow    = ($ItemName.ToLower() -replace '[^a-z0-9]', '')
    $isCamelCase = $ItemName -cmatch '[a-z][A-Z]|[A-Z]{2}[a-z]'  # e.g. CSharpExpert, WinFormsExpert

    foreach ($t in $script:TechSpecificSegments) {
        if ($segments -contains $t) { return 0 }
        if ($isCamelCase -and $fullLow.Contains($t)) { return 0 }
    }

    foreach ($g in $script:GeneralPositiveSegments) {
        if ($segments -contains $g) { return 2 }
        if ($isCamelCase -and $fullLow.Contains($g)) { return 2 }
    }

    return 0  # neutral — available but not starred
}

#endregion # General-agent detection

#region Subscription manifest
$UserManifestPath   = Join-Path $SourceRoot 'user-subscriptions.json'
$script:UserSubIndex = @{}

if (Test-Path $UserManifestPath) {
    try {
        $existingSubs = Get-Content $UserManifestPath -Raw | ConvertFrom-Json
        if ($existingSubs.subscriptions) {
            foreach ($s in $existingSubs.subscriptions) {
                $script:UserSubIndex["$($s.category)|$($s.name)"] = $s
            }
        }
    } catch { Log "Could not parse user subscriptions manifest: $_" 'WARN' }
}

#endregion # Subscription manifest

#region Catalogue builder

function Build-UserCatalogue([string]$CatDir, [string]$Pattern, [string]$Category) {
    if (-not (Test-Path $CatDir)) { return @() }
    Get-ChildItem $CatDir -File | Where-Object { $_.Name -match $Pattern } | ForEach-Object {
        $destFile        = Join-Path $PromptsDir $_.Name
        $itemName        = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.(instructions|agent|prompt|chatmode)$', ''
        $subKey          = "$Category|$itemName"
        $subEntry        = $script:UserSubIndex[$subKey]
        $installed       = Test-Path $destFile
        $updateAvailable = $false
        $locallyModified = $false
        $managedByScript = $null -ne $subEntry

        if ($installed -and $subEntry) {
            $srcHash         = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
            $currentHash     = (Get-FileHash $destFile   -Algorithm SHA256).Hash
            $locallyModified = $currentHash -ne $subEntry.hashAtInstall
            $updateAvailable = $srcHash -ne $currentHash
        }

        $isRec = (-not (Test-RequiresSetup $_.FullName)) -and ((Measure-GeneralRelevance $itemName) -ge 2)
        [pscustomobject]@{
            Name             = $itemName
            FileName         = $_.Name
            FullPath         = $_.FullName
            Description      = Get-Description $_.FullName
            RequiresSetup    = Test-RequiresSetup $_.FullName
            IsRecommended    = $isRec
            AlreadyInstalled = $installed
            ManagedByScript  = $managedByScript
            UpdateAvailable  = $updateAvailable
            LocallyModified  = $locallyModified
        }
    } | Sort-Object Name
}

function Build-UserSkillsCatalogue {
    $catDir = Join-Path $SourceRoot 'skills'
    if (-not (Test-Path $catDir)) { return @() }
    Get-ChildItem $catDir -Directory | ForEach-Object {
        $destSubdir      = Join-Path $SkillsDir $_.Name
        $readmePath      = Join-Path $_.FullName 'README.md'
        if (-not (Test-Path $readmePath)) { $readmePath = Join-Path $_.FullName 'SKILL.md' }
        $subKey          = "skills|$($_.Name)"
        $subEntry        = $script:UserSubIndex[$subKey]
        $installed       = Test-Path $destSubdir
        $updateAvailable = $false
        $locallyModified = $false
        $managedByScript = $null -ne $subEntry

        if ($installed -and $subEntry) {
            $srcHash         = Get-DirHash $_.FullName
            $currentHash     = Get-DirHash $destSubdir
            $locallyModified = $currentHash -ne $subEntry.hashAtInstall
            $updateAvailable = $srcHash -ne $currentHash
        }

        $isRec = (-not (Test-RequiresSetup $_.FullName)) -and ((Measure-GeneralRelevance $_.Name) -ge 2)
        [pscustomobject]@{
            Name             = $_.Name
            FullPath         = $_.FullName
            Description      = if (Test-Path $readmePath) { Get-Description $readmePath } else { '' }
            RequiresSetup    = Test-RequiresSetup $_.FullName
            IsRecommended    = $isRec
            AlreadyInstalled = $installed
            ManagedByScript  = $managedByScript
            UpdateAvailable  = $updateAvailable
            LocallyModified  = $locallyModified
        }
    } | Sort-Object Name
}

#endregion # Catalogue builder

#region Picker helpers

function Select-UserItems {
    param(
        [string]   $Category,
        [object[]] $Items,
        [string]   $PreSelected = ''
    )

    if ($Items.Count -eq 0) {
        Log "No $Category found in cache." 'WARN'
        return @()
    }

    # Non-interactive mode: pre-selection provided
    if ($PreSelected) {
        $names    = $PreSelected.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $selected = $Items | Where-Object { $names -contains $_.Name }
        if (-not $selected) { Log "No matching $Category items for: $PreSelected" 'WARN' }
        return @($selected)
    }

    # Sort: recommended first, then already-installed, then alphabetical
    $Items = $Items | Sort-Object `
        @{ E={ if ($_.IsRecommended)     { 0 } else { 1 } } },
        @{ E={ if ($_.AlreadyInstalled)  { 0 } else { 1 } } },
        Name

    Write-Host ""
    Write-Host "  === User-level $Category (available in all repos) ===" -ForegroundColor Yellow
    Write-Host "  ★=Recommended (general-purpose)  [*]=Installed  [↑]=Update available  [~]=Locally modified  [!]=Setup required" -ForegroundColor DarkGray

    $ogvAvailable = $false
    try { Get-Command Out-GridView -ErrorAction Stop | Out-Null; $ogvAvailable = $true } catch {}

    if ($ogvAvailable) {
        $none    = [pscustomobject]@{ Rec=''; Status=''; Name='-- none / skip --'; Description='Select this (or nothing) to install nothing' }
        $display = @($none) + @($Items | Select-Object `
            @{ N='Rec'; E={ if ($_.IsRecommended) { '★' } else { '' } } },
            @{ N='Status'; E={
                $s = ''
                if ($_.AlreadyInstalled) { $s += '[*]' }
                if ($_.UpdateAvailable)  { $s += '[↑]' }
                if ($_.LocallyModified)  { $s += '[~]' }
                if ($_.RequiresSetup)    { $s += '[!]' }
                $s
            }},
            @{ N='Name';        E={ $_.Name } },
            @{ N='Description'; E={ $_.Description } })

        $picked = $display | Show-OGV -Title "User-level $Category — available in ALL repos  ★=General-purpose  [*]=Installed  [↑]=Update  [~]=Modified  [!]=Setup required" -SearchKey "Select user $Category" -PassThru
        if (-not $picked) { return @() }
        $pickedNames = @($picked | Where-Object { $_.Name -ne '-- none / skip --' } | ForEach-Object { $_.Name })
        return @($Items | Where-Object { $pickedNames -contains $_.Name })
    }

    # Fallback: numbered console menu
    Write-Host ""
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item   = $Items[$i]
        $status = ''
        if ($item.AlreadyInstalled) { $status += '[*]' }
        if ($item.UpdateAvailable)  { $status += '[↑]' }
        if ($item.LocallyModified)  { $status += '[~]' }
        $rec   = if ($item.IsRecommended) { '[★]' } elseif ($item.RequiresSetup) { '[!]' } else { '   ' }
        $color = if ($item.UpdateAvailable) { 'Cyan' } elseif ($item.AlreadyInstalled) { 'DarkCyan' } elseif ($item.IsRecommended) { 'Yellow' } elseif ($item.RequiresSetup) { 'DarkYellow' } else { 'White' }
        Write-Host ("  {0,3}. {1} {2,-6} {3}" -f ($i+1), $rec, $status, $item.Name) -ForegroundColor $color
        if ($item.Description) {
            Write-Host ("             {0}" -f $item.Description) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  Enter numbers to install (e.g. 1,3,5 or 1-3 or 'all' or blank to skip): " -NoNewline -ForegroundColor Yellow
    $rawInput = Read-Host

    if (-not $rawInput -or $rawInput.Trim() -eq '') { return @() }
    if ($rawInput.Trim() -eq 'all') { return $Items }

    $indices = @()
    foreach ($part in $rawInput.Split(',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $indices += ([int]$Matches[1])..[int]$Matches[2]
        } elseif ($part -match '^\d+$') {
            $indices += [int]$part
        }
    }
    return @($Items | Where-Object { $indices -contains ([Array]::IndexOf($Items, $_) + 1) })
}

function Select-UserToRemove {
    param([string]$Category, [object[]]$Items)

    # Only offer items this script installed — never user-created files
    $removable = @($Items | Where-Object { $_.AlreadyInstalled -and $_.ManagedByScript })
    if ($removable.Count -eq 0) {
        Log "No script-managed user-level $Category to remove." 'INFO'
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
        $picked = $display | Show-OGV -Title "Remove user-level $Category   [~]=Locally modified (removal is permanent)" -SearchKey "Remove user $Category" -PassThru
        if (-not $picked) { return @() }
        $pickedNames = @($picked | Where-Object { $_.Name -ne '-- none / skip --' } | ForEach-Object { $_.Name })
        return @($removable | Where-Object { $pickedNames -contains $_.Name })
    }

    # Fallback: numbered console menu
    Write-Host ""
    Write-Host "  === Remove user-level $Category ===" -ForegroundColor Red
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
    $rawInput = Read-Host
    if (-not $rawInput -or $rawInput.Trim() -eq '') { return @() }

    $indices = @()
    foreach ($part in $rawInput.Split(',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $indices += ([int]$Matches[1])..[int]$Matches[2]
        } elseif ($part -match '^\d+$') {
            $indices += [int]$part
        }
    }
    return @($removable | Where-Object { $indices -contains ([Array]::IndexOf($removable, $_) + 1) })
}

#endregion # Picker helpers

#region Bootstrap — register existing installations without re-copying files
if ($Bootstrap) {
    Log "Bootstrap: scanning installed user-level resources against cache..."
    $bootstrapEntries = [System.Collections.Generic.List[object]]::new()

    # Agents
    $agentCacheDir = Join-Path $SourceRoot 'agents'
    if (Test-Path $agentCacheDir) {
        Get-ChildItem $agentCacheDir -File | Where-Object { $_.Name -match '\.agent\.md$' } | ForEach-Object {
            $itemName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.agent$',''
            $destFile = Join-Path $PromptsDir $_.Name
            if ((Test-Path $destFile) -and -not $script:UserSubIndex.ContainsKey("agents|$itemName")) {
                Log "  Register agent: $itemName"
                if (-not $DryRun) {
                    $bootstrapEntries.Add([pscustomobject]@{
                        name          = $itemName
                        category      = 'agents'
                        type          = 'file'
                        fileName      = $_.Name
                        sourceRelPath = "agents/$($_.Name)"
                        hashAtInstall = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                        installedAt   = (Get-Date).ToString('o')
                    })
                }
            }
        }
    }

    # Instructions
    $instrCacheDir = Join-Path $SourceRoot 'instructions'
    if (Test-Path $instrCacheDir) {
        Get-ChildItem $instrCacheDir -File | Where-Object { $_.Name -match '\.instructions\.md$' } | ForEach-Object {
            $itemName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.instructions$',''
            $destFile = Join-Path $PromptsDir $_.Name
            if ((Test-Path $destFile) -and -not $script:UserSubIndex.ContainsKey("instructions|$itemName")) {
                Log "  Register instruction: $itemName"
                if (-not $DryRun) {
                    $bootstrapEntries.Add([pscustomobject]@{
                        name          = $itemName
                        category      = 'instructions'
                        type          = 'file'
                        fileName      = $_.Name
                        sourceRelPath = "instructions/$($_.Name)"
                        hashAtInstall = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                        installedAt   = (Get-Date).ToString('o')
                    })
                }
            }
        }
    }

    # Skills
    $skillCacheDir = Join-Path $SourceRoot 'skills'
    if (Test-Path $skillCacheDir) {
        Get-ChildItem $skillCacheDir -Directory | ForEach-Object {
            $destDir = Join-Path $SkillsDir $_.Name
            if ((Test-Path $destDir) -and -not $script:UserSubIndex.ContainsKey("skills|$($_.Name)")) {
                Log "  Register skill: $($_.Name)"
                if (-not $DryRun) {
                    $bootstrapEntries.Add([pscustomobject]@{
                        name          = $_.Name
                        category      = 'skills'
                        type          = 'directory'
                        dirName       = $_.Name
                        sourceRelPath = "skills/$($_.Name)"
                        hashAtInstall = Get-DirHash $_.FullName
                        installedAt   = (Get-Date).ToString('o')
                    })
                }
            }
        }
    }

    if ($DryRun) {
        # Count what would be registered by re-running without DryRun
        $wouldCount = 0
        foreach ($cat in @('agents','instructions','skills')) {
            $cDir = Join-Path $SourceRoot $cat
            if (-not (Test-Path $cDir)) { continue }
            $isDir = $cat -eq 'skills'
            $items = if ($isDir) { Get-ChildItem $cDir -Directory } else { Get-ChildItem $cDir -File }
            foreach ($item in $items) {
                $n = if ($isDir) { $item.Name } else {
                    [System.IO.Path]::GetFileNameWithoutExtension($item.Name) -replace '\.(agent|instructions)$',''
                }
                $destPath = if ($isDir) { Join-Path $SkillsDir $n } else { Join-Path $PromptsDir $item.Name }
                if ((Test-Path $destPath) -and -not $script:UserSubIndex.ContainsKey("$cat|$n")) { $wouldCount++ }
            }
        }
        Log "[DryRun] Would register $wouldCount untracked installation(s) into user-subscriptions.json" 'WARN'
    } elseif ($bootstrapEntries.Count -gt 0) {
        Update-UserSubscriptions -ManifestPath $UserManifestPath -NewEntries $bootstrapEntries.ToArray()
        Log "Bootstrap complete: registered $($bootstrapEntries.Count) installation(s). Run update-user.ps1 to check for upstream changes." 'SUCCESS'
    } else {
        Log "Bootstrap: nothing to register — all installed resources are already tracked." 'SUCCESS'
    }
    exit 0
}
#endregion # Bootstrap

#region Agents
$totalInstalled = 0
$script:UserSubscriptionEntries = [System.Collections.Generic.List[object]]::new()

if (-not $Uninstall) {
    Write-Host ""
    Write-Host "  ⚠  Resources installed to user-level locations are loaded by Copilot in ALL VS Code" -ForegroundColor Yellow
    Write-Host "     sessions on this machine, regardless of which repo is open." -ForegroundColor Yellow
    Write-Host "     Only install resources from sources you trust." -ForegroundColor DarkGray
    Write-Host ""
}

if (-not $SkipAgents) {
    Log "Loading agents catalogue..."
    $catAgents = Build-UserCatalogue (Join-Path $SourceRoot 'agents') '\.agent\.md$' 'agents'

    if ($Uninstall) {
        $toRemove = Select-UserToRemove -Category 'Agents' -Items $catAgents
        foreach ($item in $toRemove) {
            $result = Remove-File -FilePath (Join-Path $PromptsDir $item.FileName)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  user agent: $($item.FileName)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-UserSubscriptionEntries -ManifestPath $UserManifestPath -Keys @($toRemove | ForEach-Object { "agents|$($_.Name)" })
        }
    } else {
        $selected = Select-UserItems -Category 'Agents' -Items $catAgents -PreSelected $Agents

        foreach ($item in $selected) {
            $result = Install-File -Src $item.FullPath -DestDir $PromptsDir
            $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
            Log "$verb  user agent: $($item.FileName)"
            if ($result -in 'added','updated','would-copy') { $totalInstalled++ }

            $script:UserSubscriptionEntries.Add([pscustomobject]@{
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
    Log "Loading instructions catalogue..."
    $catInstructions = Build-UserCatalogue (Join-Path $SourceRoot 'instructions') '\.instructions\.md$' 'instructions'

    if ($Uninstall) {
        $toRemove = Select-UserToRemove -Category 'Instructions' -Items $catInstructions
        foreach ($item in $toRemove) {
            $result = Remove-File -FilePath (Join-Path $PromptsDir $item.FileName)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  user instruction: $($item.FileName)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-UserSubscriptionEntries -ManifestPath $UserManifestPath -Keys @($toRemove | ForEach-Object { "instructions|$($_.Name)" })
        }
    } else {
        $selected = Select-UserItems -Category 'Instructions' -Items $catInstructions -PreSelected $Instructions

        foreach ($item in $selected) {
            $result = Install-File -Src $item.FullPath -DestDir $PromptsDir
            $verb   = switch ($result) { 'added' { '✓ Added' } 'updated' { '↑ Updated' } 'unchanged' { '= Unchanged' } default { '~ DryRun' } }
            Log "$verb  user instruction: $($item.FileName)"
            if ($result -in 'added','updated','would-copy') { $totalInstalled++ }

            $script:UserSubscriptionEntries.Add([pscustomobject]@{
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

#region Skills
if (-not $SkipSkills) {
    Log "Loading skills catalogue..."
    $catSkills = Build-UserSkillsCatalogue

    if ($Uninstall) {
        $toRemove = Select-UserToRemove -Category 'Skills' -Items $catSkills
        foreach ($item in $toRemove) {
            $result = Remove-Directory -DirPath (Join-Path $SkillsDir $item.Name)
            $verb   = if ($result -eq 'would-remove') { '~ DryRun remove' } else { '✗ Removed' }
            Log "$verb  user skill: $($item.Name)"
        }
        if ($toRemove.Count -gt 0) {
            Remove-UserSubscriptionEntries -ManifestPath $UserManifestPath -Keys @($toRemove | ForEach-Object { "skills|$($_.Name)" })
        }
    } else {
        $selected = Select-UserItems -Category 'Skills' -Items $catSkills -PreSelected $Skills

        foreach ($item in $selected) {
            $r    = Install-Directory -SrcDir $item.FullPath -DestParent $SkillsDir
            $verb = if ($DryRun) { '~ DryRun' } else { '✓ Installed' }
            Log "$verb  user skill: $($item.Name) (added=$($r.Added) updated=$($r.Updated) unchanged=$($r.Unchanged))"
            if (-not $DryRun) { $totalInstalled++ }

            $script:UserSubscriptionEntries.Add([pscustomobject]@{
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
if ($script:UserSubscriptionEntries.Count -gt 0) {
    Update-UserSubscriptions -ManifestPath $UserManifestPath -NewEntries $script:UserSubscriptionEntries.ToArray()
}

Write-Host ""
if ($Uninstall) {
    Log "User-level uninstall complete." 'SUCCESS'
} elseif ($DryRun) {
    Log "Dry run complete. Re-run without -DryRun to apply." 'WARN'
} else {
    Log "$totalInstalled user-level resource(s) installed/updated." 'SUCCESS'
    if ($totalInstalled -gt 0) {
        if (-not $SkipAgents -or -not $SkipInstructions) {
            Log "Agents and instructions are available in all VS Code windows: $PromptsDir"
        }
        if (-not $SkipSkills) {
            Log "Skills are available at: $SkillsDir"
        }
    }
    Log "Tip: run init-user.ps1 -Uninstall to remove user-level resources."
    Log "Tip: run update-user.ps1 to check for and apply upstream changes."
}
#endregion # Summary
