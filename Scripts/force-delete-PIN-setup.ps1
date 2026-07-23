# 停止相关服务
Stop-Service -Name NgcSvc -Force -ErrorAction SilentlyContinue
Stop-Service -Name KeyIso -Force -ErrorAction SilentlyContinue

# 获取 NGC 文件夹权限
$Path = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"

takeown /f $Path /r /d y
icacls $Path /grant administrators:F /t

# 删除 NGC 文件夹
Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue

# 重置 TPM (可选，如果上面失败再执行)
# Clear-Tpm

Write-Host "PIN has been removed, pleae restart your PC."