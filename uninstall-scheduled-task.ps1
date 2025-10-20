[CmdletBinding()] param(
    [string]$TaskName = 'AwesomeCopilotSync'
)
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task $TaskName" -ForegroundColor Yellow
}
else {
    Write-Host "Task $TaskName not found" -ForegroundColor Gray
}
