## Script for collecting ALL logs from a specific timeframe. It outputs in a searchable gridview. ##
function Read-DateInput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$FormatHint = 'MM/dd/yyyy'
    )

    while ($true) {
        $InputString = Read-Host "$Prompt (format: $FormatHint)"

        try {
            return [datetime]::Parse($InputString)
        }
        catch {
            Write-Host "Invalid date entered. Please use format: $FormatHint" -ForegroundColor Yellow
        }
    }
}
Write-Host ""
Write-Host "Select a mode:" -ForegroundColor Cyan
Write-Host "1. Last Hour"
Write-Host "2. Last 24 Hours"
Write-Host "3. Specific Day"
Write-Host "4. Date Range"
Write-Host ""
$Choice = Read-Host "Enter 1, 2, 3, or 4"
switch ($Choice) {
    '1' {
        $Start = (Get-Date).AddHours(-1)
        $End   = Get-Date
        $Title = 'Error events - Last Hour'
    }
    '2' {
        $Start = (Get-Date).AddHours(-24)
        $End   = Get-Date
        $Title = 'Error events - Last 24 Hours'
    }
    '3' {
        $Day   = Read-DateInput -Prompt 'Enter the day to search' -FormatHint 'MM/dd/yyyy'
        $Start = $Day.Date
        $End   = $Start.AddDays(1)
        $Title = "Error events - $($Start.ToString('yyyy-MM-dd'))"
    }
    '4' {
        $StartDate = Read-DateInput -Prompt 'Enter the start date' -FormatHint 'MM/dd/yyyy'
        $EndDate   = Read-DateInput -Prompt 'Enter the end date' -FormatHint 'MM/dd/yyyy'

        $Start = $StartDate.Date
        $End   = $EndDate.Date.AddDays(1)

        if ($End -le $Start) {
            Write-Host "End date must be the same as or later than start date." -ForegroundColor Red
            exit
        }

        $Title = "Error events - $($Start.ToString('yyyy-MM-dd')) to $($End.AddDays(-1).ToString('yyyy-MM-dd'))"
    }

    default {
        Write-Host "Invalid selection. Please run the script again and choose 1, 2, 3, or 4." -ForegroundColor Red
        exit
    }
}
$LogNames = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.IsEnabled -eq $true } |
    Select-Object -ExpandProperty LogName

$Events = foreach ($Log in $LogNames) {
    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = $Log
            Level     = 2   # Error
            StartTime = $Start
            EndTime   = $End
        } -ErrorAction Stop
    }
    catch {
        # Skip logs that cannot be queried
    }
}
$Events |
    Select-Object TimeCreated, Id, LevelDisplayName, LogName, ProviderName, MachineName, Message |
    Sort-Object TimeCreated -Descending |
    Out-GridView -Title $Title
