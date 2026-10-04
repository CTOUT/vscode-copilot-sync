<#
.SYNOPSIS
Canonical Asset Schema representation and converter functions.
Provides standard model transformations between raw registry assets and the canonical asset schema.
#>

$ErrorActionPreference = 'Stop'

function New-CanonicalAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet('rule', 'instruction', 'agent', 'skill', 'provider', 'registry', 'workflow', 'plugin')][string]$Type,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$Description = '',
        [string]$Version = '1.0.0',
        [bool]$RequiresSetup = $false,
        [string[]]$Platforms = @('copilot'),
        [string[]]$Dependencies = @(),
        [string[]]$Capabilities = @(),
        [string[]]$Provides = @(),
        [string[]]$Tags = @(),
        [string]$Content = '',
        [hashtable]$Metadata = @{}
    )

    return [pscustomobject]@{
        id            = $Id.ToLower()
        type          = $Type.ToLower()
        title         = $Title
        description   = $Description
        source        = $Source
        version       = $Version
        requiresSetup = $RequiresSetup
        platforms     = @($Platforms)
        dependencies  = @($Dependencies)
        capabilities  = @($Capabilities)
        provides      = @($Provides)
        tags          = @($Tags)
        content       = $Content
        metadata      = $Metadata
    }
}

function ConvertTo-CanonicalAsset {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [string]$Source = 'awesome-copilot'
    )

    $typeMap = @{
        'instructions' = 'instruction'
        'agents'       = 'agent'
        'skills'       = 'skill'
        'plugins'      = 'plugin'
        'workflows'    = 'workflow'
        'hooks'        = 'provider'
        'rules'        = 'rule'
    }

    $rawCategory = if ($Item.category) { $Item.category.ToLower() } else { 'instruction' }
    $canonicalType = if ($typeMap.ContainsKey($rawCategory)) { $typeMap[$rawCategory] } else { 'instruction' }

    $name = if ($Item.name) { $Item.name } elseif ($Item.Name) { $Item.Name } else { '' }
    $title = if ($Item.title) { $Item.title } elseif ($Item.Title) { $Item.Title } else { $name }
    $desc = if ($Item.description) { $Item.description } elseif ($Item.Description) { $Item.Description } else { '' }
    $requiresSetup = if ($null -ne $Item.requiresSetup) { [bool]$Item.requiresSetup } elseif ($null -ne $Item.RequiresSetup) { [bool]$Item.RequiresSetup } else { $false }

    $tags = @($name -split '-') | Where-Object { $_ -ne '' }

    return New-CanonicalAsset `
        -Id $name `
        -Type $canonicalType `
        -Title $title `
        -Description $desc `
        -Source $Source `
        -RequiresSetup $requiresSetup `
        -Tags $tags
}
