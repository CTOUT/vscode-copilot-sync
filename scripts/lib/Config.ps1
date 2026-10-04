<#
.SYNOPSIS
Persistent configuration manager for copilot-sync.
Loads and saves configuration settings from ~/.awesome-copilot/config.json.
#>

$ErrorActionPreference = 'Stop'

$CommonLib = Join-Path $PSScriptRoot 'Common.ps1'
if (Test-Path $CommonLib) { . $CommonLib }

function Get-CopilotConfigPath {
    param([string]$SourceRoot = "$HOME/.awesome-copilot")
    return Join-Path $SourceRoot 'config.json'
}

function Get-DefaultCopilotConfig {
    return [pscustomobject]@{
        version           = 1
        defaultCategories = @('agents', 'instructions', 'skills')
        skipCategories    = @()
        defaultScope      = 'both'
        picker            = 'console'
        promptsDir        = $null
        skillsDir         = $null
        registries        = @(
            [pscustomobject]@{
                name         = 'awesome-copilot'
                type         = 'git'
                url          = 'https://github.com/github/awesome-copilot'
                catalogueUrl = 'https://awesome-copilot.github.com/llms.txt'
                enabled      = $true
            }
        )
    }
}

function Get-CopilotConfig {
    param([string]$SourceRoot = "$HOME/.awesome-copilot")

    $cfgPath = Get-CopilotConfigPath -SourceRoot $SourceRoot
    if (Test-Path $cfgPath) {
        try {
            $raw = Get-Content $cfgPath -Raw -ErrorAction Stop
            $cfg = $raw | ConvertFrom-Json
            if ($cfg) { return $cfg }
        }
        catch {}
    }
    return (Get-DefaultCopilotConfig)
}

function Save-CopilotConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [string]$SourceRoot = "$HOME/.awesome-copilot"
    )

    if (-not (Test-Path $SourceRoot)) {
        New-Item -ItemType Directory -Path $SourceRoot -Force | Out-Null
    }
    $cfgPath = Get-CopilotConfigPath -SourceRoot $SourceRoot
    $Config | ConvertTo-Json -Depth 6 | Set-Content -Path $cfgPath -Encoding UTF8
    return $cfgPath
}
