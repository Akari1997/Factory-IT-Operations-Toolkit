$LogFile = Join-Path $PSScriptRoot "PIM_Activation.log"

# =========================
# 日志函数
# =========================
function Write-LogBlock {
    param (
        [string]$UserEmail,
        [string]$Role,
        [string]$Result
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

@"
time stamp: $timestamp
user email: $UserEmail
Role: $Role
Result: $Result
-----------------------------------
"@ | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# =========================
# Graph 错误解析辅助函数
# =========================
function Get-GraphErrorDetail {
    param(
        [Parameter(Mandatory=$true)]
        $ErrorRecord
    )

    $result = [ordered]@{
        StatusCode      = $null
        ErrorCode       = $null
        Message         = $null
        RequestId       = $null
        ClientRequestId = $null
        Raw             = $null
    }

    try {
        $ex = $ErrorRecord.Exception

        # 1) 先拿异常消息
        if ($ex -and $ex.Message) {
            $result.Message = $ex.Message
        }

        # 2) 如果能拿到响应对象（常见于 Graph SDK）
        $resp = $null
        if ($ex -and $ex.Response) {
            $resp = $ex.Response
        } elseif ($ErrorRecord.Exception.PSObject.Properties.Name -contains 'Response') {
            $resp = $ErrorRecord.Exception.Response
        }

        if ($resp) {
            # 状态码
            if ($resp.StatusCode) {
                $result.StatusCode = [int]$resp.StatusCode
            } elseif ($resp.PSObject.Properties.Name -contains 'StatusCode') {
                $result.StatusCode = [int]$resp.StatusCode
            }

            # 请求头里取 request-id / client-request-id
            $headers = $null
            if ($resp.Headers) { $headers = $resp.Headers }
            elseif ($resp.PSObject.Properties.Name -contains 'Headers') { $headers = $resp.Headers }

            if ($headers) {
                if ($headers.ContainsKey("request-id"))      { $result.RequestId       = ($headers["request-id"] | Select-Object -First 1) }
                if ($headers.ContainsKey("client-request-id")){ $result.ClientRequestId = ($headers["client-request-id"] | Select-Object -First 1) }
            }

            # 读取响应体
            $raw = $null
            if ($resp.Content) {
                try { $raw = $resp.Content.ReadAsStringAsync().Result } catch {}
            }
            if (-not $raw -and $resp.GetResponseStream) {
                try {
                    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                    $reader.BaseStream.Position = 0
                    $raw = $reader.ReadToEnd()
                } catch {}
            }
            $result.Raw = $raw

            # 尝试按 Graph 错误 JSON 解析
            if ($raw) {
                try {
                    $json = $raw | ConvertFrom-Json -ErrorAction Stop
                    if ($json.error) {
                        if ($json.error.code)    { $result.ErrorCode = $json.error.code }
                        if ($json.error.message) {
                            # message 可能是对象/字符串
                            if ($json.error.message.value) {
                                $result.Message = $json.error.message.value
                            } else {
                                $result.Message = $json.error.message
                            }
                        }
                    }
                } catch {
                    # 不是标准 JSON，就保留 Raw 文本
                }
            }
        }

        # 3) 如果 ErrorDetails 里有 message，也合并
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            if (-not $result.Message) { $result.Message = $ErrorRecord.ErrorDetails.Message }
            else { $result.Message = "$($result.Message) | $($ErrorRecord.ErrorDetails.Message)" }
        }
    } catch {
        # 兜底，不让辅助函数再抛异常
    }

    return [pscustomobject]$result
}

# =========================
# 角色列表
# =========================
$listRoles = @(
    "sec.intune.users.intune_supporter_dot_fot"
    "Sec.ColleagueDevices.DELTA.Group.Support.User"
    "sec.intune.users.unattendedaccess.mpc2026"
)

# =========================
# 模块检查
# =========================
$modules = @(
    "Microsoft.Graph.Authentication"
    "Microsoft.Graph.Groups"
)

foreach ($m in $modules) {
    if (!(Get-Module -ListAvailable $m)) {
        Install-Module $m -Scope CurrentUser -AllowClobber -Force
    }
    Import-Module $m
}

# =========================
# 连接 Graph
# =========================
Disconnect-MgGraph -ErrorAction SilentlyContinue

if (!(Get-MgContext)) {
    Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory" -ContextScope CurrentUser -NoWelcome
}

# 获取当前用户信息
$me = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me"
$principalId = $me.Id
$userEmail = if ($me.mail) { $me.mail } else { $me.userPrincipalName }

$activeRole_URL = "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests"

$results = @()

# =========================
# 激活逻辑
# =========================
foreach ($role in $listRoles) {

    $group = Get-MgGroup -Filter "displayName eq '$role'"

    if ($group -eq $null) {
        Write-LogBlock -UserEmail $userEmail -Role $role -Result "FAILED - Group not found"
        $results += "$role : FAILED - Group not found"
        continue
    }

    $groupID = $group.Id

    $checkActive = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=principalId eq '$principalId' and groupId eq '$groupID'"

    if ($checkActive.value.Count -gt 0) {
        Write-LogBlock -UserEmail $userEmail -Role $role -Result "SKIPPED - Already active"
        $results += "$role : SKIPPED - Already active"
        continue
    }

    $body = @{
        action        = "selfActivate"
        principalId   = $principalId
        groupId       = $groupID
        accessId      = "member"
        justification = "Daily active for support tasks"
        scheduleInfo  = @{
            startDateTime = (Get-Date).AddMinutes(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            expiration    = @{
                type     = "afterDuration"
                duration = "PT8H"
            }
        }
        ticketInfo = @{
            ticketNumber = ""
            ticketSystem = ""
        }
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-MgGraphRequest -Method POST -Uri $activeRole_URL -Body $body -ContentType "application/json"

        Write-LogBlock -UserEmail $userEmail -Role $role -Result "SUCCESS"
        $results += "$role : SUCCESS"
    }
    
    catch {
        $detail = Get-GraphErrorDetail -ErrorRecord $_

        # 组装一条可读性更强的原因
        $reason = @()
        if ($detail.StatusCode)      { $reason += "HTTP $($detail.StatusCode)" }
        if ($detail.ErrorCode)       { $reason += "Code: $($detail.ErrorCode)" }
        if ($detail.Message)         { $reason += "Msg: $($detail.Message)" }
        if ($detail.RequestId)       { $reason += "RequestId: $($detail.RequestId)" }
        if ($detail.ClientRequestId) { $reason += "ClientRequestId: $($detail.ClientRequestId)" }
        $reasonText = ($reason -join " | ")

        # 将原始响应体也落日志（便于审计/排障）
        $logText = "FAILED - $reasonText"
        if ($detail.Raw) {
            # 控制长度，避免日志爆长；需要可改阈值
            $rawToLog = $detail.Raw
            if ($rawToLog.Length -gt 4000) {
                $rawToLog = $rawToLog.Substring(0, 4000) + "...(truncated)"
            }
            $logText = "$logText`nRaw: $rawToLog"
        }

        Write-LogBlock -UserEmail $userEmail -Role $role -Result $logText
        $results += "$role : FAILED - $reasonText"
    }

}

# =========================
# 发送邮件
# =========================
$emailBody = $results -join "`n"

Send-MailMessage -To "yiqing.wang@lego.com" `
                 -From "active.pim@lego.com" `
                 -Subject "PIM Role Activation Results" `
                 -Body $emailBody `
                 -SmtpServer "smtp1.corp.lego.com"

Exit