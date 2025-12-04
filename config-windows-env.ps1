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
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Type DWord -Value 0
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False
Get-NetFirewallProfile | Select-Object Name, Enabled

[Console]::Write("Registering scheduled task ... ");
if (Get-ScheduledTask -TaskName "WanlizStartupTasks" -ErrorAction SilentlyContinue) {
    Write-Host "[SKIPPED]"
} else {
    $script = "D:\wanliz\apps\wanliz-utils\startup-tasks.ps1"
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
}

$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
[Console]::Write("Updating $hostsFile ... ");
$added = 0
$existing = if([System.IO.File]::Exists($hostsFile)) {
    [System.IO.File]::ReadAllLines($hostsFile)
} else {
    @()
}
foreach($line in [System.IO.File]::ReadAllLines("$PSScriptRoot\hosts")) {
    $trim = $line.Trim()
    if($trim.Length.Equals(0)) { continue }
    if($trim.StartsWith("#")) { continue }
    if(!$existing.Contains($line)) {
        for ($i = 0; $i -lt 5; $i++) {
            try {
                Add-Content $hostsFile $line
                $added = 1
                break 
            } catch {
                Start-Sleep -Milliseconds 200
                if ($1 -eq 4) { throw }
            }
        }
    }
}
if($added.Equals(0)) {
    Write-Host "[SKIPPED]"
} else {
    Write-Host "[OK]"
}

[Console]::Write("Updating ~/.ssh/ed25519 ... ")
$ssh = Join-Path $HOME ".ssh"
if (!(Test-Path $ssh)) {
    New-Item -ItemType Directory -Path $ssh | Out-Null
}
$priv = Join-Path $ssh "id_ed25519"
$pub = Join-Path $ssh "id_ed25519.pub"
if (!(Test-Path $priv)) {
@"
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB8e4c/PmyYwYqGt0Zb5mom/KTEndF05kcF8Gsa094RSwAAAJhfAHP9XwBz
/QAAAAtzc2gtZWQyNTUxOQAAACB8e4c/PmyYwYqGt0Zb5mom/KTEndF05kcF8Gsa094RSw
AAAECa55qWiuh60rKkJLljELR5X1FhzceY/beegVBrDPv6yXx7hz8+bJjBioa3Rlvmaib8
pMSd0XTmRwXwaxrT3hFLAAAAE3dhbmxpekBFbnpvLU1hY0Jvb2sBAg==
-----END OPENSSH PRIVATE KEY-----
"@ | Set-Content -Encoding ascii $priv
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL wanliz@Enzo-MacBook" | Set-Content -Encoding ascii $pub
    Write-Host "[OK]"
} else {
    Write-Host "[SKIPPED]"
}


[Console]::Write("Updating powershell profile ... ")
if (!(Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
} 
$currentVersion=2
$content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = "" }
$match = [regex]::Match($content, '(?ms)^#\s*=== WANLIZ VERSION\s+(\d+)\s*===\s*\r?\n.*?^#\s*=== WANLIZ END ===\s*$')
if (-not ($match.Success -and [int]$match.Groups[1].Value -ge $currentVersion)) {
    if ($match.Success) {
        $content = $content.Remove($match.Index, $match.Length).TrimEnd("`r","`n")
        Set-Content $PROFILE $content
    }

    Add-Content $PROFILE ""
    Add-Content $PROFILE "# === WANLIZ VERSION $currentVersion ==="
@'
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
# === WANLIZ END ===
'@ | Add-Content -Path $PROFILE
    Write-Host "[ OK ]"
} else {
    Write-Host "[ SKIPPED ]"
}

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

[Console]::Write("Updating context menu items ... ")
$root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $true)
$psPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$script = 'D:\wanliz\apps\wanliz' + [char]45 + 'utils\who' + [char]45 + 'locks' + [char]45 + 'me.ps1'
$dash = [char]45
$cmd = 'cmd.exe /c start "" "' + $psPath + '" ' +
    $dash + 'NoProfile ' +
    $dash + 'ExecutionPolicy Bypass ' +
    $dash + 'File "' + $script + '" "%1"'
$changed = $false 
foreach ($sub in @('*\shell\WhoLocks', 'Directory\shell\WhoLocks')) {
    $k = $root.CreateSubKey($sub)
    if ([Object]::ReferenceEquals($k.GetValue('MUIVerb'), $null)) {
        $k.SetValue('MUIVerb', 'Who locks me?', [Microsoft.Win32.RegistryValueKind]::String)
        $changed = $true 
    }
    if ([Object]::ReferenceEquals($k.GetValue('Icon'), $null)) {
        $k.SetValue('Icon', '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe', [Microsoft.Win32.RegistryValueKind]::String)
        $changed = $true 
    }
    if ([Object]::ReferenceEquals($k.GetValue('HasLUAShield'), $null)) {
        $k.SetValue('HasLUAShield', '', [Microsoft.Win32.RegistryValueKind]::String)
        $changed = $true 
    }
    $cmdKey = $k.CreateSubKey('command')
    if ([Object]::ReferenceEquals($cmdKey.GetValue(''), $null)) {
        $cmdKey.SetValue('', $cmd, [Microsoft.Win32.RegistryValueKind]::String)
        $changed = $true 
    }
    $cmdKey.Close()
    $k.Close()
}
$root.Close()
if ($changed) {
    Write-Host "[OK]"
} else {
    Write-Host "[SKIPPED]"
}


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

if (Get-Process OneDrive -ErrorAction SilentlyContinue) {
    $answer = Read-Host "Uninstall and disable OneDrive? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Y/y]') {
        Uninstall-OneDrive
    }
}

if (-not (fsutil.exe file queryCaseSensitiveInfo "D:\wanliz_sw_windows" 2>$null | Select-String 'enabled' -Quiet)) {
    fsutil.exe file setCaseSensitiveInfo "D:\wanliz_sw_windows" enable 
    Get-ChildItem -Directory -Recurse "D:\wanliz_sw_windows" | ForEach-Object {
        fsutil.exe file setCaseSensitiveInfo $_.FullName enable
    }
}

Read-Host "Press [Enter] to exit"