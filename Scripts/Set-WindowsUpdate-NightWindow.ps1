#Requires -RunAsAdministrator

$TaskName   = "Nightly-Windows-Update"
$ScriptPath = "C:\ProgramData\NightlyWindowsUpdate.ps1"
$LogFile    = "C:\ProgramData\NightlyWindowsUpdate.log"

Write-Host "Creating nightly Windows Update task..."

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {
}

$ScriptContent = @'
$LogFile = "C:\ProgramData\NightlyWindowsUpdate.log"

function Write-Log {
    param([string]$Message)
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Time  $Message"
}

Write-Log "===== Task started ====="

try {
    Start-Process usoclient.exe StartScan
    Write-Log "Started scan"

    Start-Sleep -Seconds 60

    Start-Process usoclient.exe StartDownload
    Write-Log "Started download"

    Start-Sleep -Seconds 120

    Start-Process usoclient.exe StartInstall
    Write-Log "Started install"

    Start-Sleep -Seconds 30

    Start-Process usoclient.exe RefreshSettings
    Write-Log "Refreshed settings"
}
catch {
    Write-Log $_.Exception.Message
}

Write-Log "===== Task finished ====="
'@

Set-Content -Path $ScriptPath -Value $ScriptContent -Encoding UTF8

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger `
    -Daily `
    -At "22:00"

$Settings = New-ScheduledTaskSettingsSet `
    -WakeToRun `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4)

$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal `
    -Force | Out-Null

Write-Host ""
Write-Host "================================="
Write-Host "Nightly update task configured."
Write-Host "================================="
Write-Host ""
Write-Host "Task name : $TaskName"
Write-Host "Run as    : SYSTEM"
Write-Host "Time      : Daily at 22:00"
Write-Host "Script    : $ScriptPath"
Write-Host "Log file  : $LogFile"
Write-Host ""
Write-Host "Run once as administrator only."
Write-Host "After that, the task runs automatically."
Write-Host ""