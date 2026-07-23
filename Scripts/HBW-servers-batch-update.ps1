param (
    [Parameter(Mandatory = $true)]
    [string[]]$Servers
)


# -----------------------------
# Configuration
# -----------------------------


#$Servers = @("Server01","Server02","Server03")  # list of servers
Write-Host "Target servers:" ($Servers -join ", ")
Write-Host ""

#$username = "Administrator"                     # remote admin username
#$password = "P@ssw0rd!" | ConvertTo-SecureString -AsPlainText -Force
$Credential = Get-Credential
#$Credential = New-Object System.Management.Automation.PSCredential ($username, $password)

$ScriptBlock = {
    # -----------------------------
    # Windows Update Script
    # -----------------------------
    $StartTime = Get-Date
    Write-Host "===== Windows Update Script Started on $env:COMPUTERNAME at $StartTime =====`n"

    $Result = @{
        ComputerName   = $env:COMPUTERNAME
        StartTime      = $StartTime
        EndTime        = $null
        DurationSec    = 0
        UpdateCount    = 0
        KBs            = @()
        RebootRequired = $false
        Status         = "Unknown"
        Error          = $null
    }

    try {
        # Check admin privileges
        $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $IsAdmin) {
            throw "Script must be run with Administrator privileges."
        }

        Write-Host "Administrator privileges verified.`n"

        # Check and start required services: wuauserv, BITS
        Write-Host "[Step 2] Checking required services..."
        $services = @("wuauserv","BITS")
        foreach ($svcName in $services) {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            try {
                if ($svc.Status -ne 'Running') {
                    Write-Host "$svcName is not running. Starting service..."
                    Start-Service -Name $svcName -ErrorAction Stop
                    $svc.WaitForStatus('Running','00:00:30')
                    Write-Host "$svcName started."
                } else {
                    Write-Host "$svcName is already running."
                }
            } catch {
                Write-Warning "$svcName could not be started: $($_.Exception.Message)"
                $Result.Status = "ServiceStartFailed"
                $Result.Error += "$svcName start error; "
                throw "Required service $svcName is not running."
            }
        }
        Write-Host "All required services are running.`n"





        # Initialize Windows Update Agent
        Write-Host "[Step 3] Initializing Windows Update Agent..."
        $UpdateSession  = New-Object -ComObject Microsoft.Update.Session
        $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

        Write-Host "[Step 4] Searching for available updates..."
        $SearchResult = $UpdateSearcher.Search(
            "IsInstalled=0 and Type='Software' and IsHidden=0"
        )

        if ($SearchResult.Updates.Count -eq 0) {
            $Result.Status = "NoUpdates"
            Write-Host "No new updates found."
            return $Result | ConvertTo-Json -Depth 4
        }

        Write-Host "Found $($SearchResult.Updates.Count) updates. Preparing to install..."

        $UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl


        $i = 1
        foreach ($Update in $SearchResult.Updates) {
            Write-Host "  [$i/$($SearchResult.Updates.Count)] $($Update.Title)"
            if (-not $Update.EulaAccepted) { $Update.AcceptEula() }
            foreach ($kb in $Update.KBArticleIDs) { $Result.KBs += $kb }
            [void]$UpdatesToInstall.Add($Update)
            $i++
        }

        $Result.UpdateCount = $UpdatesToInstall.Count
        Write-Host "`nAll updates added to install collection.`n"

        # Download
        Write-Host "[Step 5] Downloading updates..."
        $Downloader = $UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToInstall
        $DownloadResult = $Downloader.Download()
        if ($DownloadResult.ResultCode -notin 2,3) {
            throw "Download failed. ResultCode=$($DownloadResult.ResultCode)"
        }
        Write-Host "Download completed successfully.`n"

        # Install
        Write-Host "[Step 6] Installing updates..."
        $Installer = $UpdateSession.CreateUpdateInstaller()
        $Installer.Updates = $UpdatesToInstall
        $InstallResult = $Installer.Install()
        if ($InstallResult.ResultCode -notin 2,3) {
            throw "Installation failed. ResultCode=$($InstallResult.ResultCode)"
        }
        Write-Host "Installation completed successfully.`n"

        $Result.RebootRequired = $InstallResult.RebootRequired
        $Result.Status = "Success"


        # Automatically restart if required
        if ($Result.RebootRequired) {
            Write-Warning "[Step 7]A reboot is required. Restarting the system in 1 minute..."
            shutdown /r /t 60 /c "Windows updates installed, system will restart."
        }
        else {
            Write-Host "[Step 7]No reboot required."
        }
    }
    catch {
    # 只有当安装或下载失败才写 Failed
    if ($Result.UpdateCount -eq 0 -or $InstallResult.ResultCode -notin 2,3) {
        $Result.Status = "Failed"
        $Result.Error  = $_.Exception.Message
    } else {
        # Defender 更新或 Download 阶段的 AccessDenied 不算失败
        $Result.Status = "Success"
        Write-Warning "Non-critical error ignored: $($_.Exception.Message)"
    }
}


   finally {
    Write-Host "`n[Cleanup] Releasing COM objects..."
    foreach ($obj in @(
        $Installer,
        $Downloader,
        $UpdatesToInstall,
        $SearchResult,
        $UpdateSearcher,
        $UpdateSession
    )) {
        if ($null -ne $obj) {
            try {
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($obj) | Out-Null
            }
            catch {
                Write-Warning "COM cleanup warning (ignored): $($_.Exception.Message)"
            }
        }
    }

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    $Result.EndTime = Get-Date
    $Result.DurationSec = [int]($Result.EndTime - $Result.StartTime).TotalSeconds

    # 不要在 finally 里修改 $Result.Status
}



    # Output JSON
    $Result | ConvertTo-Json -Depth 4
}

function Send-UpdateMail {
    param(
        [string]$ComputerName,
        [string]$Status,
        [int]$UpdateCount,
        [bool]$RebootRequired,
        [string[]]$KBs,
        [string]$Error
    )

    $smtpServer = "smtp1.corp.lego.com"
    $from = "HBW.server.update@lego.com"
    $to   = "yiqing.wang@lego.com"

    $subject = "[Windows Update] $ComputerName - $Status"

    $body = @"
Server        : $ComputerName
Status        : $Status
Updates       : $UpdateCount
RebootNeeded  : $RebootRequired
KBs           : $(if ($KBs) { $KBs -join ", " } else { "N/A" })
Error         : $(if ($Error) { $Error } else { "None" })
Time          : $(Get-Date)
"@

    $mail = New-Object System.Net.Mail.MailMessage
    $mail.From = $from
    $mail.To.Add($to)
    $mail.Subject = $subject
    $mail.Body = $body
    $mail.BodyEncoding = [System.Text.Encoding]::UTF8
    $mail.Priority = [System.Net.Mail.MailPriority]::High

    $smtp = New-Object System.Net.Mail.SmtpClient($smtpServer,25)
    $smtp.Send($mail)

    $mail.Dispose()
    $smtp.Dispose()
}


# -----------------------------
# Execute on multiple servers
# -----------------------------
$Results = Invoke-Command -ComputerName $Servers -Credential $Credential -ScriptBlock $ScriptBlock -ThrottleLimit 5

$ParsedResults = $Results | ConvertFrom-Json

foreach ($r in $ParsedResults) {

    Send-UpdateMail `
        -ComputerName   $r.ComputerName `
        -Status         $r.Status `
        -UpdateCount    $r.UpdateCount `
        -RebootRequired $r.RebootRequired `
        -KBs            $r.KBs `
        -Error          $r.Error
}

# Optional: Output all results to console
$Results | ForEach-Object { Write-Host $_ }

# Optional: Save results to CSV for reporting
$Results | ConvertFrom-Json | Export-Csv -Path "C:\Logs\WU_Results.csv" -NoTypeInformation -Force
