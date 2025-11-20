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

Write-Host "Allow current user to run .ps1 scripts"
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

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

function Uninstall-OneDrive {
    Write-Host "Stopping OneDrive processes..."
    Get-Process |
        Where-Object { $_.Name -like "OneDrive*" } -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "Killing OneDrive.exe if still running..."
    Start-Process -FilePath "taskkill.exe" -ArgumentList "/f /im OneDrive.exe" -NoNewWindow -Wait -ErrorAction SilentlyContinue

    Write-Host "Uninstalling OneDrive via setup executables..."
    $setupPaths = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    )

    foreach ($p in $setupPaths) {
        if (Test-Path $p) {
            Write-Host "Running: $p /uninstall"
            Start-Process -FilePath $p -ArgumentList "/uninstall" -NoNewWindow -Wait -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Trying winget uninstall if available..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget uninstall "Microsoft OneDrive"
        } catch {
            Write-Host "winget uninstall failed or not applicable, continuing..."
        }
    }

    Write-Host "Disabling OneDrive sync by policy..."
    $policyKey = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $policyKey)) {
        New-Item -Path $policyKey -Force | Out-Null
    }
    New-ItemProperty -Path $policyKey -Name "DisableFileSyncNGSC" -PropertyType DWord -Value 1 -Force | Out-Null

    Write-Host "Removing OneDrive from explorer navigation pane..."
    $clsidPaths = @(
        "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
        "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    )

    foreach ($k in $clsidPaths) {
        if (-not (Test-Path $k)) {
            New-Item -Path $k -Force | Out-Null
        }
        New-ItemProperty -Path $k -Name "System.IsPinnedToNameSpaceTree" -PropertyType DWord -Value 0 -Force | Out-Null
    }

    Write-Host "Cleaning run entries so OneDrive does not auto start..."
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    foreach ($name in "OneDrive", "OneDriveSetup") {
        Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
    }

    Write-Host "Disabling OneDrive related scheduled tasks..."
    $oneDriveTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like "*OneDrive*" }

    foreach ($t in $oneDriveTasks) {
        try {
            Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
        } catch {
        }
    }

    Write-Host "Removing leftover OneDrive folders for current user..."
    $pathsToRemove = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:PROGRAMDATA\Microsoft OneDrive"
    )

    foreach ($p in $pathsToRemove) {
        if (Test-Path $p) {
            Write-Host "Removing $p"
            Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Removing per user OneDrive folders under C:\Users..."
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $od = Join-Path $_.FullName "OneDrive"
        if (Test-Path $od) {
            Write-Host "Removing $od"
            Remove-Item -Path $od -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$answer = Read-Host "Uninstall and disable OneDrive? [Y/n]"
if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Y/y]') {
    Uninstall-OneDrive
}

Read-Host "Press [Enter] to exit"