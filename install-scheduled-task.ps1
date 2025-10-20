[CmdletBinding()] param(
    [string]$TaskName = 'AwesomeCopilotSync',
    [string]$Every = '4h',
    [string]$Dest = "$HOME/.awesome-copilot",
    # Default categories now exclude 'collections' (can be re-enabled with -IncludeCollections)
    [string]$Categories = 'chatmodes,instructions,prompts',
    [switch]$IncludeCollections,
    # Allow skipping the combine/publish step if user only wants raw sync
    [switch]$SkipCombine,
    [string]$PwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'sync-awesome-copilot.ps1'),
    [string]$CombineScriptPath = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'combine-and-publish-prompts.ps1'),
    [switch]$Force
)

if (-not $PwshPath) { $PwshPath = (Get-Command powershell | Select-Object -ExpandProperty Source) }
if (-not (Test-Path $ScriptPath)) { throw "Sync script not found at $ScriptPath" }
if (-not $SkipCombine -and -not (Test-Path $CombineScriptPath)) { throw "Combine script not found at $CombineScriptPath (use -SkipCombine to suppress)" }

function Parse-Interval($spec) {
    if ($spec -match '^(\d+)([hm])$') {
        $val = [int]$Matches[1]; $unit = $Matches[2]
        switch ($unit) {
            'h' { return @{ Type = 'HOURLY'; Modifier = $val } }
            'm' { return @{ Type = 'MINUTE'; Modifier = $val } }
        }
    }
    throw "Unsupported interval spec: $spec (use like 4h or 30m)"
}

if ($IncludeCollections -and ($Categories -notmatch 'collections')) {
    $Categories = ($Categories.TrimEnd(',') + ',collections')
}

$int = Parse-Interval $Every

# Primary sync action
$syncArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Dest `"$Dest`" -Categories `"$Categories`" -Quiet"
$actions = @()
$actions += New-ScheduledTaskAction -Execute $PwshPath -Argument $syncArgs

if (-not $SkipCombine) {
    # Combine script runs after sync; no need for -DryRun. Include collections only if requested.
    $combineArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$CombineScriptPath`" -SourceRoot `"$Dest`"" + $(if ($IncludeCollections) { ' -IncludeCollections' } else { '' })
    $actions += New-ScheduledTaskAction -Execute $PwshPath -Argument $combineArgs
}
$Trigger = if ($int.Type -eq 'HOURLY') { New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval ([TimeSpan]::FromHours($int.Modifier)) -RepetitionDuration ([TimeSpan]::FromDays(3650)) } else { New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval ([TimeSpan]::FromMinutes($int.Modifier)) -RepetitionDuration ([TimeSpan]::FromDays(3650)) }
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    if (-not $Force) { Write-Error "Task $TaskName already exists. Use -Force to overwrite."; exit 1 }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $actions -Trigger $Trigger -Settings $Settings -Description "Sync (and combine) Awesome Copilot resources" | Out-Null

$post = if ($SkipCombine) { 'sync only' } else { 'sync + combine/publish' }
Write-Host "Scheduled task '$TaskName' created ($post). First run in ~1 minute, then every $Every." -ForegroundColor Green
