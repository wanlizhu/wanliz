[CmdletBinding()]
param()

# ===== Execution & error behavior =====
# Convert non-terminating errors into terminating ones so our trap can report line numbers.
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$InformationPreference = 'Continue'
$script:LoadedUserSids = @()   # tracked for cleanup if an error aborts in the middle

# Global error trap: prints message, file, line, the exact command, and cleans loaded hives.
trap {
    $errorRecord = $_
    $invocation  = $errorRecord.InvocationInfo

    Write-Host ""
    Write-Host "====================== ERROR ======================" -ForegroundColor Red
    Write-Host ("Message : {0}" -f $errorRecord.Exception.Message) -ForegroundColor Red

    if ($invocation) {
        Write-Host ("File    : {0}" -f ($invocation.ScriptName)) -ForegroundColor Yellow
        Write-Host ("Line    : {0}" -f ($invocation.ScriptLineNumber)) -ForegroundColor Yellow
        if ($invocation.PositionMessage) {
            Write-Host "-------- Code Context --------" -ForegroundColor DarkGray
            Write-Host $invocation.PositionMessage -ForegroundColor DarkGray
            Write-Host "------------------------------" -ForegroundColor DarkGray
        }
        if ($invocation.Line) {
            Write-Host ("Command : {0}" -f $invocation.Line.Trim()) -ForegroundColor Yellow
        }
    }

    if ($errorRecord.CategoryInfo) {
        Write-Host ("Category: {0}" -f $errorRecord.CategoryInfo) -ForegroundColor DarkRed
    }
    if ($errorRecord.FullyQualifiedErrorId) {
        Write-Host ("FQID    : {0}" -f $errorRecord.FullyQualifiedErrorId) -ForegroundColor DarkRed
    }

    if ($script:LoadedUserSids.Count -gt 0) {
        Write-Host "Unloading user registry hives..." -ForegroundColor Cyan
        foreach ($loadedSid in $script:LoadedUserSids) {
            reg.exe unload "HKU\$loadedSid" | Out-Null
        }
    }

    Write-Host "==================================================" -ForegroundColor Red
    break
}

function EnsureAdmin {
    # If not elevated, relaunch an elevated PowerShell that stays open (-NoExit) and return.
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        $restartArgs = "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $restartArgs -Verb RunAs
        Write-Host "Started elevated PowerShell. Use the new window; this one will remain open." -ForegroundColor Cyan
        return
    }
}

function BlockAndUninstallOneDrive {
    Write-Host "[1/5] Stop processes, apply policy, and uninstall..." -ForegroundColor Cyan

    foreach ($processName in @("OneDrive", "FileCoAuth", "OneDriveStandaloneUpdater", "OneDriveSetup")) {
        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            Get-Process -Name $processName | Stop-Process -Force
        }
    }

    $policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $policyKey)) {
        New-Item -Path $policyKey -Force | Out-Null
    }
    New-ItemProperty -Path $policyKey -Name DisableFileSyncNGSC -Type DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $policyKey -Name DisableLibrariesDefaultSaveToOneDrive -Type DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $policyKey -Name DisableMeteredNetworkFileSync -Type DWord -Value 1 -Force | Out-Null

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Uninstall via WinGet..." -ForegroundColor DarkCyan
        winget uninstall --id Microsoft.OneDrive -e --silent | Out-Null
    }

    foreach ($installerPath in @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe")) {
        if (Test-Path $installerPath) {
            Write-Host ("Uninstall via {0} ..." -f $installerPath) -ForegroundColor DarkCyan
            Start-Process -FilePath $installerPath -ArgumentList "/uninstall" -Wait -WindowStyle Hidden
        }
    }

    Write-Host "Remove Appx package and provisioning (if present)..." -ForegroundColor DarkCyan
    $appx = Get-AppxPackage -AllUsers *OneDrive* -ErrorAction SilentlyContinue
    if ($appx) {
        $appx | Remove-AppxPackage -AllUsers
    }

    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match "OneDrive" }
    if ($prov) {
        $prov | Remove-AppxProvisionedPackage -Online | Out-Null
    }

    Write-Host "Delete OneDrive-related services (if any)..." -ForegroundColor DarkCyan
    $oneDriveServices = Get-Service | Where-Object { $_.Name -like "*OneDrive*" -or $_.DisplayName -like "*OneDrive*" }
    foreach ($service in $oneDriveServices) {
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $service.Name -Force
        }
        sc.exe delete $service.Name | Out-Null
    }
}

function DisableAutoruns {
    Write-Host "[2/5] Remove scheduled tasks and startup hooks..." -ForegroundColor Cyan

    $tasks = Get-ScheduledTask | Where-Object {
        $_.TaskName -like "*OneDrive*" -or
        $_.TaskPath -like "\Microsoft\OneDrive\*" -or
        $_.TaskPath -like "\Microsoft\Windows\OneDrive\*"
    }
    foreach ($task in $tasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
    }

    foreach ($registryPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )) {
        foreach ($startupEntryName in @("OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater")) {
            if (Get-ItemProperty -Path $registryPath -Name $startupEntryName -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $registryPath -Name $startupEntryName
            }
        }
    }

    if (-not (Get-PSDrive HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
    }

    $userProfiles = Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -and $_.SID -and -not $_.Special }

    foreach ($profile in $userProfiles) {
        $userSid = $profile.SID
        $userHivePath = "HKU:\$userSid"

        if (-not (Test-Path $userHivePath)) {
            $ntUserDatPath = Join-Path $profile.LocalPath "NTUSER.DAT"
            if (Test-Path $ntUserDatPath) {
                reg.exe load "HKU\$userSid" "$ntUserDatPath" | Out-Null
                $script:LoadedUserSids += $userSid
            }
        }

        $userRunKey = "HKU:\$userSid\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $userRunKey) {
            foreach ($startupEntryName in @("OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater")) {
                if (Get-ItemProperty -Path $userRunKey -Name $startupEntryName -ErrorAction SilentlyContinue) {
                    Remove-ItemProperty -Path $userRunKey -Name $startupEntryName
                }
            }
        }

        if ($script:LoadedUserSids -contains $userSid) {
            reg.exe unload "HKU\$userSid" | Out-Null
            $script:LoadedUserSids = $script:LoadedUserSids | Where-Object { $_ -ne $userSid }
        }
    }
}

function CleanupShell {
    Write-Host "[3/5] CleanupShell: start $(Get-Date -Format 'u')" -ForegroundColor Cyan
    $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # 1) Shell icon overlays (safe enumeration)
    Write-Host "  [1/6] Shell icon overlays..." -ForegroundColor DarkCyan
    $overlayRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers"
    )
    foreach ($overlayRootPath in $overlayRoots) {
        Write-Host "    Root: $overlayRootPath" -ForegroundColor DarkGray
        if (Test-Path -Path $overlayRootPath) {
            $overlayKeys = Get-ChildItem -Path $overlayRootPath -ErrorAction SilentlyContinue |
                           Where-Object { $_.PSChildName -like "OneDrive*" -or $_.PSChildName -like "SkyDrive*" }
            Write-Host ("    Found overlays: {0}" -f ($overlayKeys | Measure-Object | Select-Object -ExpandProperty Count)) -ForegroundColor DarkGray
            foreach ($overlayKey in $overlayKeys) {
                Write-Host ("      Removing: {0}" -f $overlayKey.PSChildName) -ForegroundColor DarkGray
                Remove-Item -Path $overlayKey.PSPath -Recurse -Force
            }
        } else {
            Write-Host "    Root not present." -ForegroundColor DarkGray
        }
    }
    Write-Host ("  [1/6] done in {0:N2}s" -f $stageTimer.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    $stageTimer.Restart()

    # 2) Context menu handlers (NO enumeration; literal paths only where '*' is part of the key name)
    Write-Host "  [2/6] Context menu handlers..." -ForegroundColor DarkCyan
    if (-not (Get-PSDrive HKCR -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
        Write-Host "    Mounted HKCR:" -ForegroundColor DarkGray
    }

    $contextMenuRoots = @(
        "HKCR:\*\shellex\ContextMenuHandlers",            # literal '*' key
        "HKCR:\Directory\shellex\ContextMenuHandlers",
        "HKCR:\Directory\Background\shellex\ContextMenuHandlers",
        "HKCR:\Drive\shellex\ContextMenuHandlers"
    )

    foreach ($contextMenuRootPath in $contextMenuRoots) {
        Write-Host "    Root: $contextMenuRootPath" -ForegroundColor DarkGray

        # Use -LiteralPath only for these HKCR paths to prevent wildcard expansion
        $rootExists = Test-Path -LiteralPath $contextMenuRootPath
        Write-Host ("      Exists: {0}" -f $rootExists) -ForegroundColor DarkGray
        if (-not $rootExists) { continue }

        foreach ($contextHandlerName in @("OneDrive", "SkyDrive")) {
            $contextKeyPath = "$contextMenuRootPath\$contextHandlerName"
            Write-Host ("      Check: {0}" -f $contextKeyPath) -ForegroundColor DarkGray

            if (Test-Path -LiteralPath $contextKeyPath) {
                Write-Host ("      Removing: {0}" -f $contextKeyPath) -ForegroundColor DarkGray
                Remove-Item -LiteralPath $contextKeyPath -Recurse -Force
            } else {
                Write-Host "      Not present." -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ("  [2/6] done in {0:N2}s" -f $stageTimer.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    $stageTimer.Restart()

    # 3) Unpin OneDrive from Explorer namespace
    Write-Host "  [3/6] Explorer namespace unpin..." -ForegroundColor DarkCyan
    $oneDriveClsid = '{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    $namespaceKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\$oneDriveClsid",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\$oneDriveClsid"
    )
    foreach ($namespaceKeyPath in $namespaceKeys) {
        if (Test-Path -Path $namespaceKeyPath) {
            Write-Host ("    Removing: {0}" -f $namespaceKeyPath) -ForegroundColor DarkGray
            Remove-Item -Path $namespaceKeyPath -Recurse -Force
        } else {
            Write-Host ("    Not present: {0}" -f $namespaceKeyPath) -ForegroundColor DarkGray
        }
    }
    Write-Host ("  [3/6] done in {0:N2}s" -f $stageTimer.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    $stageTimer.Restart()

    # 4) ShellFolder ACL and unpin flag
    Write-Host "  [4/6] ShellFolder ACL and pin state..." -ForegroundColor DarkCyan
    $clsidKey = "HKCR:\CLSID\$oneDriveClsid"
    $shellFolderKeyPath = Join-Path $clsidKey "ShellFolder"

    if (-not (Test-Path -Path $clsidKey)) {
        Write-Host ("    Creating: {0}" -f $clsidKey) -ForegroundColor DarkGray
        New-Item -Path $clsidKey -Force | Out-Null
    }
    if (-not (Test-Path -Path $shellFolderKeyPath)) {
        Write-Host ("    Creating: {0}" -f $shellFolderKeyPath) -ForegroundColor DarkGray
        New-Item -Path $shellFolderKeyPath -Force | Out-Null
    }

    # Use -Path (not -LiteralPath) with ACL cmdlets for broad compatibility
    $shellFolderAcl = Get-Acl -Path $shellFolderKeyPath
    $adminHasFullControl =
        $shellFolderAcl.Access |
        Where-Object {
            $_.IdentityReference -match 'Administrators' -and
            ($_.RegistryRights -band [System.Security.AccessControl.RegistryRights]::FullControl)
        }

    if (-not $adminHasFullControl) {
        Write-Host "    Granting Administrators FullControl..." -ForegroundColor DarkGray
        $accessControlRule = New-Object System.Security.AccessControl.RegistryAccessRule(
            "Administrators",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $shellFolderAcl.SetAccessRule($accessControlRule)
        Set-Acl -Path $shellFolderKeyPath -AclObject $shellFolderAcl
    } else {
        Write-Host "    ACL already OK; skipping Set-Acl." -ForegroundColor DarkGray
    }

    $pinnedValue = Get-ItemProperty -Path $clsidKey -Name "System.IsPinnedToNameSpaceTree" -ErrorAction SilentlyContinue |
                   Select-Object -ExpandProperty "System.IsPinnedToNameSpaceTree" -ErrorAction SilentlyContinue
    if ($pinnedValue -ne 0) {
        Write-Host "    Setting System.IsPinnedToNameSpaceTree=0..." -ForegroundColor DarkGray
        New-ItemProperty -Path $clsidKey -Name "System.IsPinnedToNameSpaceTree" -Type DWord -Value 0 -Force | Out-Null
    } else {
        Write-Host "    Already unpinned." -ForegroundColor DarkGray
    }
    Write-Host ("  [4/6] done in {0:N2}s" -f $stageTimer.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    $stageTimer.Restart()

    # 5) Known Folders repoint (per-user; bounded enumeration)
    Write-Host "  [5/6] Known Folders repoint..." -ForegroundColor DarkCyan
    if (-not (Get-PSDrive HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
        Write-Host "    Mounted HKU:" -ForegroundColor DarkGray
    }

    $userProfiles = Get-CimInstance Win32_UserProfile |
                    Where-Object { $_.SID -and $_.LocalPath -and -not $_.Special }
    Write-Host ("    Profiles found: {0}" -f ($userProfiles | Measure-Object | Select-Object -ExpandProperty Count)) -ForegroundColor DarkGray

    foreach ($userProfile in $userProfiles) {
        $userSid = $userProfile.SID
        $userBasePath = $userProfile.LocalPath
        $userHivePath = "HKU:\$userSid"
        Write-Host ("    SID: {0}" -f $userSid) -ForegroundColor DarkGray

        $loadedThisSid = $false
        if (-not (Test-Path -Path $userHivePath)) {
            $ntUserDatPath = Join-Path $userBasePath "NTUSER.DAT"
            if (Test-Path -Path $ntUserDatPath) {
                Write-Host ("      Loading hive: {0}" -f $ntUserDatPath) -ForegroundColor DarkGray
                reg.exe load "HKU\$userSid" "$ntUserDatPath" | Out-Null
                $script:LoadedUserSids += $userSid
                $loadedThisSid = $true
            } else {
                Write-Host "      NTUSER.DAT not found; skipping user." -ForegroundColor DarkGray
                continue
            }
        }

        $userShellFoldersKey = "HKU:\$userSid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        if (Test-Path -Path $userShellFoldersKey) {
            $folderTargets = @(
                @{ Name = "Desktop";  Default = "$userBasePath\Desktop" },
                @{ Name = "Personal"; Default = "$userBasePath\Documents" },
                @{ Name = "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"; Default = "$userBasePath\Documents" },
                @{ Name = "My Pictures"; Default = "$userBasePath\Pictures" },
                @{ Name = "My Music"; Default = "$userBasePath\Music" },
                @{ Name = "My Video"; Default = "$userBasePath\Videos" },
                @{ Name = "{374DE290-123F-4565-9164-39C4925E467B}"; Default = "$userBasePath\Downloads" }
            )

            $changedCount = 0
            foreach ($target in $folderTargets) {
                $currentPath = (Get-ItemProperty -Path $userShellFoldersKey -Name $target.Name -ErrorAction SilentlyContinue).$($target.Name)
                if ($currentPath -and $currentPath -match "OneDrive") {
                    Write-Host ("      Repoint {0} -> {1}" -f $target.Name, $target.Default) -ForegroundColor DarkGray
                    Set-ItemProperty -Path $userShellFoldersKey -Name $target.Name -Value $target.Default
                    $changedCount++
                }
            }
            Write-Host ("      Updated entries: {0}" -f $changedCount) -ForegroundColor DarkGray
        } else {
            Write-Host "      User Shell Folders key not found; skipping." -ForegroundColor DarkGray
        }

        if ($loadedThisSid) {
            Write-Host ("      Unloading hive for SID: {0}" -f $userSid) -ForegroundColor DarkGray
            reg.exe unload "HKU\$userSid" | Out-Null
            $script:LoadedUserSids = $script:LoadedUserSids | Where-Object { $_ -ne $userSid }
        }
    }
    Write-Host ("  [5/6] done in {0:N2}s" -f $stageTimer.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    $stageTimer.Restart()

    # 6) Summary
    Write-Host "  [6/6] CleanupShell complete." -ForegroundColor DarkCyan
    Write-Host ("CleanupShell total duration: {0:N2}s" -f $stageTimer.Elapsed.TotalSeconds) -ForegroundColor Cyan
}

function PurgeFiles {
    Write-Host "[4/5] Remove leftover files and folders..." -ForegroundColor Cyan

    # Add MoveFileEx P/Invoke once (correct MemberDefinition: only members, fully-qualified types)
    if (-not ('Native.Win32' -as [type])) {
        Add-Type -Namespace Native -Name Win32 -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);
"@
    }
    $MOVEFILE_DELAY_UNTIL_REBOOT = 4

    # Likely lockers
    $lockerProcessNames = @(
        "OneDrive","OneDriveStandaloneUpdater","FileCoAuth",
        "winword","excel","powerpnt","onenote","onenoteim","outlook","teams"
    )

    foreach ($lockerName in $lockerProcessNames) {
        $procs = Get-Process -Name $lockerName -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host ("  Stopping process: {0}" -f $lockerName) -ForegroundColor DarkGray
            $procs | Stop-Process -Force
        }
    }

    # Machine-level paths
    $machinePaths = @(
        "$env:ProgramData\Microsoft OneDrive",
        "$env:ProgramFiles\Microsoft OneDrive",
        "$env:ProgramFiles(x86)\Microsoft OneDrive",
        "$env:LocalAppData\Microsoft\OneDrive"
    ) | Where-Object { $_ -and (Test-Path -Path $_) }

    foreach ($machinePath in $machinePaths) {
        Write-Host ("  Processing: {0}" -f $machinePath) -ForegroundColor DarkCyan

        takeown /F "$machinePath" /A /R /D Y | Out-Null
        icacls "$machinePath" /grant Administrators:F /T /C | Out-Null

        Write-Host "    Clearing file attributes..." -ForegroundColor DarkGray
        Get-ChildItem -Path $machinePath -Force -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }

        # Coauthoring DLLs commonly locked
        $coauthDlls = Get-ChildItem -Path $machinePath -Filter "FileCoAuthLib*.dll" -Recurse -ErrorAction SilentlyContinue
        $lockedParents = @()

        foreach ($dll in $coauthDlls) {
            Write-Host ("    Found coauthoring DLL: {0}" -f $dll.FullName) -ForegroundColor DarkGray

            $pendingName = ($dll.FullName + ".pendingdelete")
            Rename-Item -Path $dll.FullName -NewName $pendingName -ErrorAction SilentlyContinue

            if (Test-Path -Path $pendingName) {
                Write-Host "      Renamed to .pendingdelete" -ForegroundColor DarkGray
            } else {
                Write-Host "      Rename blocked; scheduling delete on reboot..." -ForegroundColor DarkGray
                $ok = [Native.Win32]::MoveFileEx($dll.FullName, $null, $MOVEFILE_DELAY_UNTIL_REBOOT)
                if ($ok) {
                    Write-Host "      Scheduled for delete on reboot." -ForegroundColor DarkGray
                } else {
                    $winErr = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Write-Host ("      MoveFileEx failed, Win32Error={0}" -f $winErr) -ForegroundColor Red
                }
            }

            $lockedParents += $dll.DirectoryName
        }

        $lockedParents = $lockedParents | Select-Object -Unique

        if ($lockedParents.Count -gt 0) {
            Write-Host "    Preserving directories that still contain locked DLLs..." -ForegroundColor Yellow

            $topLevelItems = Get-ChildItem -Path $machinePath -Force -ErrorAction SilentlyContinue
            foreach ($item in $topLevelItems) {
                $skip = $false
                foreach ($parentDir in $lockedParents) {
                    if ($item.FullName -eq $parentDir -or $item.FullName -like ($parentDir + "*")) {
                        $skip = $true
                        break
                    }
                }
                if (-not $skip) {
                    if ($item.PSIsContainer) {
                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            foreach ($parentDir in $lockedParents) {
                if (Test-Path -Path $parentDir) {
                    Write-Host ("    Cleaning inside locked parent: {0}" -f $parentDir) -ForegroundColor DarkGray
                    $dllNames = (Get-ChildItem -Path $parentDir -Filter "FileCoAuthLib*.dll" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                    $childItems = Get-ChildItem -Path $parentDir -Force -ErrorAction SilentlyContinue
                    foreach ($child in $childItems) {
                        if ($dllNames -contains $child.Name) { continue }
                        if ($child.PSIsContainer) {
                            Remove-Item -Path $child.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        } else {
                            Remove-Item -Path $child.FullName -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            Write-Host "    Locked files remain (renamed or scheduled). They will disappear after reboot." -ForegroundColor Yellow
        } else {
            Write-Host "    No locked DLLs detected; removing folder tree..." -ForegroundColor DarkGray
            Remove-Item -Path $machinePath -Recurse -Force
        }
    }

    # Per-user cleanups
    $userDirectories = Get-ChildItem "C:\Users" -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -notin @('Default','Default User','Public','All Users') }

    foreach ($userDirectory in $userDirectories) {
        $userProfilePath = $userDirectory.FullName
        Write-Host ("  Cleaning user: {0}" -f $userProfilePath) -ForegroundColor DarkCyan

        foreach ($userAppDataPath in @(
            (Join-Path $userProfilePath "AppData\Local\Microsoft\OneDrive"),
            (Join-Path $userProfilePath "AppData\Local\OneDrive"),
            (Join-Path $userProfilePath "AppData\Roaming\Microsoft\OneDrive")
        )) {
            if (Test-Path -Path $userAppDataPath) {
                takeown /F "$userAppDataPath" /A /R /D Y | Out-Null
                icacls "$userAppDataPath" /grant Administrators:F /T /C | Out-Null
                Get-ChildItem -Path $userAppDataPath -Recurse -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.Attributes = 'Normal' }
                Remove-Item -Path $userAppDataPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $candidateDeleteList = @()
        $primaryOneDrivePath = Join-Path $userProfilePath "OneDrive"
        if (Test-Path -Path $primaryOneDrivePath) {
            $candidateDeleteList += $primaryOneDrivePath
        }
        $tenantSuffixedDirs = Get-ChildItem -Path $userProfilePath -Filter "OneDrive*" -Directory -ErrorAction SilentlyContinue |
                              Select-Object -ExpandProperty FullName
        if ($tenantSuffixedDirs) {
            $candidateDeleteList += $tenantSuffixedDirs
        }

        $uniqueDirectories = $candidateDeleteList | Select-Object -Unique
        foreach ($directoryToDelete in $uniqueDirectories) {
            takeown /F "$directoryToDelete" /A /R /D Y | Out-Null
            icacls "$directoryToDelete" /grant Administrators:F /T /C | Out-Null
            Get-ChildItem -Path $directoryToDelete -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Attributes = 'Normal' }
            Remove-Item -Path $directoryToDelete -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "PurgeFiles completed. If any DLLs were scheduled for removal, reboot to finish cleanup." -ForegroundColor Green
}

function ApplyPolicyAndRestartShell {
    Write-Host "[5/5] Refresh policies and restart Explorer..." -ForegroundColor Cyan

    gpupdate /force | Out-Null

    $explorers = Get-Process explorer -ErrorAction SilentlyContinue
    if ($explorers) {
        $explorers | Stop-Process -Force
    }

    Start-Process explorer.exe
}

EnsureAdmin
# If we launched an elevated instance, the call above returns (without exiting) and leaves this window open.
# Only continue if we are already elevated:
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Disabling and removing OneDrive..." -ForegroundColor Green
    BlockAndUninstallOneDrive
    DisableAutoruns
    CleanupShell
    PurgeFiles
    ApplyPolicyAndRestartShell
    Write-Host "OneDrive has been disabled, uninstalled, and cleaned up. Reboot is recommended." -ForegroundColor Green
} else {
    Write-Host "Waiting in non-admin window; elevated instance is running in a separate window." -ForegroundColor Yellow
}
