$currUser  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    ) + $args
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit
}

trap {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo.PositionMessage) { 
        Write-Host "$($_.InvocationInfo.PositionMessage)" -ForegroundColor Yellow 
    }
    Read-Host "Press [Enter] to exit"
    exit 1
}

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'AllowInsecureGuestAuth' -Type DWord -Value 1
$ErrorActionPreference = 'Stop'

Write-Host "Checking WSL2 status"
if (wsl -l -v 2>$null |
    Select-Object -Skip 1 |
    ForEach-Object { ($_ -replace '\x00','' -split '\s+')[-1] } |
    Where-Object { $_ -eq '2' } |
    Select-Object -First 1
) {
    Write-Host "WSL2 present"
} else {
    Write-Host "No WSL2 distros, install it first" -ForegroundColor Yellow
    Read-Host "Press [Enter] to exit"
    exit 1
}

$wsl_cfg = "$env:USERPROFILE\.wslconfig"
if (Test-Path $wsl_cfg) {
    $invalid_wslconfig = $false
    if (-not (Select-String -Path $wsl_cfg -SimpleMatch -Pattern 'networkingMode=mirrored' -Quiet)) {
        Write-Host "Please add 'networkingMode=mirrored' to $wsl_cfg first" -ForegroundColor Yellow
        $invalid_wslconfig = $true
    }
    if (-not (Select-String -Path $wsl_cfg -SimpleMatch -Pattern 'sysctl.vm.max_map_count=262144' -Quiet)) {
        Write-Host "Please add 'sysctl.vm.max_map_count=262144' to $wsl_cfg first" -ForegroundColor Yellow
        $invalid_wslconfig = $true
    }
    if ($invalid_wslconfig) {
        Read-Host "Press [Enter] to exit"
        exit 1
    }
} else {
    "[wsl2]" | Set-Content $wsl_cfg
    "networkingMode=mirrored" | Add-Content $wsl_cfg
    "kernelCommandLine = `"sysctl.vm.max_map_count=262144`"" | Add-Content $wsl_cfg
    Write-Host "Restart WSL for the changes of ~/.wslconfig to take effect" -ForegroundColor Yellow
}

function Enable-SSH-Server-on-Windows {
    Write-Host "Checking SSH server status"
    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server* | Select-Object -First 1
    if ($cap.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name $cap.Name
        Set-Service -Name sshd -StartupType Automatic
    }

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Client* | Select-Object -First 1
    if (-not $cap -or $cap.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name $cap.Name
        Set-Service -Name ssh-agent -StartupType Automatic
    }

    if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
    if ((Get-Service ssh-agent -ErrorAction Stop).Status -ne 'Running') { Start-Service ssh-agent }

    if (-not ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell -match '\\(powershell|pwsh)\.exe$')) {
        New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -PropertyType String -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Force | Out-Null
        Restart-Service sshd -Force
    }

    Start-Sleep -Seconds 1
    $tcp   = Test-NetConnection -ComputerName localhost -Port 22 -WarningAction SilentlyContinue
    $state = if ($tcp.TcpTestSucceeded) { 'LISTENING' } else { 'NOT LISTENING' }
    $sshd  = Get-Service sshd
    "SSH server status: {0} | Startup: {1} | Port 22: {2}" -f $sshd.Status, $sshd.StartType, $state
}

function Disable-SSH-Server-on-Windows-and-Enable-on-WSL {
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "Disable SSH server on Windows"
        Stop-Service -Name sshd -Force
        Set-Service -Name sshd -StartupType Disabled
    }

    Write-Host "Checking SSH server on WSL (ensure Auto-Start)"
    $Action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- true"
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    if (-not (Get-ScheduledTask -TaskName "WSL_Autostart_Ubuntu" -ErrorAction SilentlyContinue)) {
        Register-ScheduledTask -TaskName "WSL_Autostart_Ubuntu" -Action $Action -Trigger $Trigger -RunLevel Highest
    }
}

Disable-SSH-Server-on-Windows-and-Enable-on-WSL

Write-Host "Checking PATH environment variables"
$want = @('C:\Program Files', $env:LOCALAPPDATA.TrimEnd('\'))
$cur  = ($env:Path -split ';') | Where-Object { $_ } | ForEach-Object { $_.Trim('"').TrimEnd('\') }
$miss = $want | ForEach-Object { $_.Trim('"').TrimEnd('\') } | Where-Object { $cur -notcontains $_ }
if ($miss) {
    $env:Path = ($cur + $miss) -join ';'
    $user = ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') |
        Where-Object { $_ } |
        ForEach-Object { $_.Trim('"').TrimEnd('\') }

    $newPath = ($user + ($miss | Where-Object { $user -notcontains $_ })) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}

Write-Host "Checking classic context menu"
$k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
if (-not (Test-Path $k) -or ((Get-Item $k).GetValue('', $null) -ne '')) {
    New-Item $k -Force | Out-Null
    Set-Item  $k -Value ''
    Stop-Process -Name explorer -Force
    Start-Process explorer.exe
}

Write-Host "Allow all users to run .ps1 scripts"
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

Write-Host "Disable 'Only allow Windows Hello sign-in'"
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Type DWord -Value 0

Write-Host "Disable Windows Firewall for all profiles"
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False
Get-NetFirewallProfile | Select-Object Name, Enabled

Write-Host "Checking context menu items"
$root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $true)
foreach ($sub in @('*\shell\WhoLocks','Directory\shell\WhoLocks')) {
    $k = $root.CreateSubKey($sub)
    $k.SetValue('MUIVerb','Who locks me?',[Microsoft.Win32.RegistryValueKind]::String)
    $k.SetValue('Icon','%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',[Microsoft.Win32.RegistryValueKind]::String)
    $k.SetValue('HasLUAShield','',[Microsoft.Win32.RegistryValueKind]::String)
    $cmd = 'cmd.exe /c start "" "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "D:\wanliz\apps\wanliz-utils\who-locks-me.ps1" "%1"'
    ($k.CreateSubKey('command')).SetValue('', $cmd, [Microsoft.Win32.RegistryValueKind]::String)
    $k.Close()
}
$root.Close()

Read-Host "Press [Enter] to exit"