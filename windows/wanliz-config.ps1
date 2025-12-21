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

# Disable Windows firewall and enable insecure guest auth
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'AllowInsecureGuestAuth' -Type DWord -Value 1
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Type DWord -Value 0
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False
Get-NetFirewallProfile | Select-Object Name, Enabled


[Console]::Write("Registering scheduled task ... ");
if (Get-ScheduledTask -TaskName "WanlizStartupTasks" -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName WanlizStartupTasks -Confirm:$false
} 
$script = "$PSScriptRoot\windows\wanliz-startup-tasks.ps1"
if (Test-Path $script) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $script"
    $trigger = New-ScheduledTaskTrigger -AtLogOn 
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
    Register-ScheduledTask -TaskName 'WanlizStartupTasks' `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force
    Write-Host "[OK]"
} else {
    Write-Host "[FAILED]"
}


$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
[Console]::Write("Updating $hostsFile ... ");
$hostsToAdd = Get-Content "$PSScriptRoot\hosts.txt"
$newIps = $hostsToAdd | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
        ($line -split '\s+')[0]
    }
} | Where-Object { $_ } | Sort-Object -Unique
$oldLines = if (Test-Path $hostsFile) {
    Get-Content $hostsFile | Where-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $ip = ($line -split '\s+')[0]
            $newIps -notcontains $ip
        } else {
            $true
        }
    }
} else {
    @()
}
Set-Content -Path $hostsFile -Value @($oldLines + $hostsToAdd)
Write-Host "[OK]"


[Console]::Write("Updating $PROFILE ... ")
if (!(Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
} 
$content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = "" }
$content = [regex]::Replace($content,
    '(?ms)^.*wanliz env vars begin.*\r?\n.*?^.*wanliz env vars end.*\r?\n?', ""
).TrimEnd("`r","`n")
Set-Content $PROFILE $content
@'
# wanliz env vars begin
$ExecutionContext.InvokeCommand.CommandNotFoundAction = {
    param(
        [string]$commandName,
        [System.Management.Automation.CommandLookupEventArgs]$eventArgs
    )
    $eventArgs.CommandScriptBlock = {
        $cmd = $commandName.Replace('get-','')
        if ($args.Count -gt 0) {
            $cmd = $cmd + " " + ($args -join " ")
        }
        wsl bash -lic "$cmd"
    }.GetNewClosure()
    $eventArgs.StopSearch = $true
}
# wanliz env vars end
'@ | Add-Content -Path $PROFILE


[Console]::Write("Checking WSL2 status ... ")
if (wsl -l -v 2>$null |
    Select-Object -Skip 1 |
    ForEach-Object { ($_ -replace '\x00','' -split '\s+')[-1] } |
    Where-Object { $_ -eq '2' } |
    Select-Object -First 1
) {
    Write-Host "[OK]"
} else {
    Write-Host "No WSL2 distros, install it first" -ForegroundColor Yellow
    Read-Host "Press [Enter] to exit"
    exit 1
}


[Console]::Write("Updating $env:USERPROFILE\.wslconfig ... ")
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
    Write-Host "[SKIPPED]"
} else {
    "[wsl2]" | Set-Content $wsl_cfg
    "networkingMode=mirrored" | Add-Content $wsl_cfg
    "kernelCommandLine = `"sysctl.vm.max_map_count=262144`"" | Add-Content $wsl_cfg
    Write-Host "[OK]"
    Write-Host "Restart WSL for the changes of ~/.wslconfig to take effect" -ForegroundColor Yellow
}


[Console]::Write("Checking SSH server on WSL ... ")
$sshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshdService -and $sshdService.Status -eq 'Running') {
    Stop-Service -Name sshd -Force
    Set-Service -Name sshd -StartupType Disabled
}
$Action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- true"
$Trigger = New-ScheduledTaskTrigger -AtStartup
if (-not (Get-ScheduledTask -TaskName "WSL_Autostart_Ubuntu" -ErrorAction SilentlyContinue)) {
    Register-ScheduledTask -TaskName "WSL_Autostart_Ubuntu" -Action $Action -Trigger $Trigger -RunLevel Highest
    Write-Host "[OK]"
} else {
    Write-Host "[SKIPPED]"
}


[Console]::Write("Updating PATH environment variables ... ")
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
    Write-Host "[OK]"
} else {
    Write-Host "[SKIPPED]"
}


[Console]::Write("Restoring classic context menu ... ")
$k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
if (-not (Test-Path $k) -or ((Get-Item $k).GetValue('', $null) -ne '')) {
    New-Item $k -Force | Out-Null
    Set-Item  $k -Value ''
    Stop-Process -Name explorer -Force
    Start-Process explorer.exe
    Write-Host "[OK]"
} else {
    Write-Host "[SKIPPED]"
}


Read-Host "Press [Enter] to exit"