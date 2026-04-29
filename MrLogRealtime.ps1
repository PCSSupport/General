## Outputs all Error Logs as they happen in realtime to powershell. Don't forget to close the script when you are done. ##
  $PollSeconds = 5
$SeenRecords = @{}

Write-Host "Building enabled log list…" -ForegroundColor Cyan

$LogNames = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.IsEnabled -eq $true -and $_.RecordCount -gt 0 } |
    Select-Object -ExpandProperty LogName

Write-Host "Watching $($LogNames.Count) logs for new Error events…" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow

while ($true) {
    foreach ($Log in $LogNames) {
        try {
            $Events = Get-WinEvent -FilterHashtable @{
                LogName   = $Log
                Level     = 2   # Error
                StartTime = (Get-Date).AddSeconds(-($PollSeconds + 2))
            } -ErrorAction Stop
        }
        catch {
            continue
        }

        foreach ($Event in ($Events | Sort-Object TimeCreated)) {
            $Key = "$($Event.LogName)|$($Event.RecordId)"

            if (-not $SeenRecords.ContainsKey($Key)) {
                $SeenRecords[$Key] = $true

                Write-Host ""
                Write-Host "==================== ERROR EVENT ====================" -ForegroundColor Red
                Write-Host "Time      : $($Event.TimeCreated)"
                Write-Host "Log       : $($Event.LogName)"
                Write-Host "Provider  : $($Event.ProviderName)"
                Write-Host "Event ID  : $($Event.Id)"
                Write-Host "Record ID : $($Event.RecordId)"
                Write-Host "Machine   : $($Event.MachineName)"
                Write-Host "Message   : $($Event.Message)"
                Write-Host "====================================================" -ForegroundColor Red
                Write-Host ""
            }
        }
    }

    Start-Sleep -Seconds $PollSeconds
}
