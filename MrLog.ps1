$OutDir = 'C:\MrLog'
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

# ---------- Discover all enabled, non-empty logs ----------
Write-Host "Enumerating event logs..." -ForegroundColor Cyan

# Logs to skip — these generate noise from the script's own activity
# (PowerShell logs every Get-WinEvent "no events found" as 4100, which
# would feed back into our realtime stream forever).
$ExcludedLogs = @(
    'Microsoft-Windows-PowerShell/Operational',
    'PowerShellCore/Operational',
    'Windows PowerShell'
)

$AllLogs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.IsEnabled -and $_.RecordCount -gt 0 -and $ExcludedLogs -notcontains $_.LogName } |
    Select-Object -ExpandProperty LogName

Write-Host "Found $($AllLogs.Count) enabled logs with records (excluding $($ExcludedLogs.Count) PowerShell self-noise logs)." -ForegroundColor Green

# ---------- Prompt 1: Time range ----------
Write-Host ""
Write-Host "Select time range:" -ForegroundColor Cyan
Write-Host "  1. Last hour"
Write-Host "  2. Last 24 hours"
Write-Host "  3. Last 7 days"
Write-Host "  4. Custom (enter start/end)"
Write-Host "  5. Realtime (stream new events as they happen)"
$rangeChoice = Read-Host "Enter choice [1-5]"

$Realtime = $false
switch ($rangeChoice) {
    '1' { $Start = (Get-Date).AddHours(-1);  $End = Get-Date; $Label = 'Last1h' }
    '2' { $Start = (Get-Date).AddDays(-1);   $End = Get-Date; $Label = 'Last24h' }
    '3' { $Start = (Get-Date).AddDays(-7);   $End = Get-Date; $Label = 'Last7d' }
    '4' {
        $Start = Get-Date (Read-Host "Start datetime (e.g. 2026-04-30 08:00)")
        $End   = Get-Date (Read-Host "End datetime   (e.g. 2026-04-30 17:00)")
        $Label = 'Custom'
    }
    '5' {
        $Realtime = $true
        $Label    = 'Realtime'
    }
    default { Write-Host "Invalid choice. Exiting." -ForegroundColor Red; return }
}

# ---------- Prompt 2: Severity ----------
Write-Host ""
Write-Host "Select MINIMUM severity (includes anything more severe):" -ForegroundColor Cyan
Write-Host "  1. Critical"
Write-Host "  2. Error        (Critical + Error)"
Write-Host "  3. Warning      (Critical + Error + Warning)"
Write-Host "  4. Information  (Critical + Error + Warning + Info)"
Write-Host "  5. Verbose      (everything)"
$sevChoice = Read-Host "Enter choice [1-5]"

switch ($sevChoice) {
    '1' { $Levels = @(1);             $SevLabel = 'Critical' }
    '2' { $Levels = @(1,2);           $SevLabel = 'Error' }
    '3' { $Levels = @(1,2,3);         $SevLabel = 'Warning' }
    '4' { $Levels = @(1,2,3,4,0);     $SevLabel = 'Info' }   # 0 = LogAlways
    '5' { $Levels = @(1,2,3,4,5,0);   $SevLabel = 'Verbose' }
    default { Write-Host "Invalid choice. Exiting." -ForegroundColor Red; return }
}

# ---------- Prompt 3: Output ----------
Write-Host ""
Write-Host "Select output destination:" -ForegroundColor Cyan
if ($Realtime) {
    Write-Host "  1. Console (live stream)"
    Write-Host "  2. Text file (live append to C:\MrLog)"
    $outChoice = Read-Host "Enter choice [1-2]"
} else {
    Write-Host "  1. Out-GridView (interactive table)"
    Write-Host "  2. Console (formatted list)"
    Write-Host "  3. Text file (saved to C:\MrLog)"
    $outChoice = Read-Host "Enter choice [1-3]"
}

# ---------- File paths ----------
$Stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$BaseName  = "EventLog_${SevLabel}_${Label}_${Stamp}"
$ClixmlPath = Join-Path $OutDir "$BaseName.clixml"
$TextPath   = Join-Path $OutDir "$BaseName.txt"

# =====================================================================
#  REALTIME MODE
# =====================================================================
if ($Realtime) {
    Write-Host ""
    Write-Host "Streaming $SevLabel+ events from $($AllLogs.Count) logs..." -ForegroundColor Green
    Write-Host "CliXML  : $ClixmlPath" -ForegroundColor DarkGray
    if ($outChoice -eq '2') {
        Write-Host "Text log: $TextPath" -ForegroundColor DarkGray
    }
    Write-Host "Press Ctrl+C to stop."
    Write-Host ""

    # Track most recent RecordId per log so we don't repeat
    $LastSeen = @{}
    foreach ($l in $AllLogs) {
        $latest = Get-WinEvent -LogName $l -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($latest) { $LastSeen[$l] = $latest.RecordId } else { $LastSeen[$l] = 0 }
    }

    $allEvents = New-Object System.Collections.Generic.List[object]

    try {
        while ($true) {
            foreach ($l in $AllLogs) {
                $batch = Get-WinEvent -FilterHashtable @{
                    LogName   = $l
                    Level     = $Levels
                    StartTime = (Get-Date).AddMinutes(-2)
                } -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.RecordId -gt $LastSeen[$l] -and
                        -not ($_.Id -eq 4100 -and $_.ProviderName -like '*PowerShell*')
                    } |
                    Sort-Object RecordId

                if ($batch) {
                    foreach ($evt in $batch) {
                        $LastSeen[$l] = [Math]::Max($LastSeen[$l], $evt.RecordId)
                        $allEvents.Add($evt)

                        $line = "{0}  [{1}/{2}]  ID {3}  {4}  :: {5}" -f `
                            $evt.TimeCreated, $evt.LogName, $evt.LevelDisplayName,
                            $evt.Id, $evt.ProviderName,
                            ($evt.Message -split "`r?`n")[0]

                        switch ($evt.LevelDisplayName) {
                            'Critical' { Write-Host $line -ForegroundColor Magenta }
                            'Error'    { Write-Host $line -ForegroundColor Red }
                            'Warning'  { Write-Host $line -ForegroundColor Yellow }
                            default    { Write-Host $line -ForegroundColor Gray }
                        }

                        if ($outChoice -eq '2') {
                            Add-Content -Path $TextPath -Value $line
                            Add-Content -Path $TextPath -Value ($evt.Message)
                            Add-Content -Path $TextPath -Value ('-' * 80)
                        }
                    }
                }
            }
            Start-Sleep -Seconds 3
        }
    }
    finally {
        if ($allEvents.Count -gt 0) {
            $allEvents | Export-Clixml -Path $ClixmlPath
            Write-Host ""
            Write-Host "Captured $($allEvents.Count) events." -ForegroundColor Green
            Write-Host "CliXML saved: $ClixmlPath" -ForegroundColor Green
            Write-Host "Re-import with: Import-Clixml '$ClixmlPath'" -ForegroundColor DarkGray
        } else {
            Write-Host ""
            Write-Host "No matching events captured." -ForegroundColor Yellow
        }
    }
    return
}

# =====================================================================
#  HISTORICAL MODE
# =====================================================================
Write-Host ""
Write-Host "Collecting $SevLabel+ events from $($AllLogs.Count) logs..." -ForegroundColor Green
Write-Host "Range: $Start  ->  $End"
Write-Host "(this can take a minute on a busy server)"

$Events = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($l in $AllLogs) {
    $i++
    Write-Progress -Activity "Querying event logs" -Status $l `
        -PercentComplete ([int](($i / $AllLogs.Count) * 100))
    $found = Get-WinEvent -FilterHashtable @{
        LogName   = $l
        Level     = $Levels
        StartTime = $Start
        EndTime   = $End
    } -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Id -eq 4100 -and $_.ProviderName -like '*PowerShell*') }
    if ($found) { foreach ($e in $found) { $Events.Add($e) } }
}
Write-Progress -Activity "Querying event logs" -Completed

$Events = $Events | Sort-Object TimeCreated -Descending
Write-Host "Found $($Events.Count) events across $($AllLogs.Count) logs." -ForegroundColor Green

# Always save CliXML
$Events | Export-Clixml -Path $ClixmlPath
Write-Host "CliXML saved: $ClixmlPath" -ForegroundColor DarkGray
Write-Host "Re-import with: Import-Clixml '$ClixmlPath'" -ForegroundColor DarkGray

# Output per user choice
switch ($outChoice) {
    '1' {
        $Events | Select-Object TimeCreated, LogName, LevelDisplayName, Id, ProviderName, Message |
            Out-GridView -Title "Event Logs - $SevLabel+ - $Label - all logs"
    }
    '2' {
        $Events | Format-List TimeCreated, LogName, LevelDisplayName, Id, ProviderName, Message
    }
    '3' {
        $Events | Format-List TimeCreated, LogName, LevelDisplayName, Id, ProviderName, Message |
            Out-File -FilePath $TextPath -Encoding UTF8
        Write-Host "Text file saved: $TextPath" -ForegroundColor Green
    }
    default { Write-Host "Invalid output choice." -ForegroundColor Red }
}
