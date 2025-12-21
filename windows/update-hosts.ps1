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

$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
[Console]::Write("Updating $hostsFile ... ")
$marker = "# wanliz utils hosts"
if ((Test-Path $hostsFile) -and (Select-String -Path $hostsFile -SimpleMatch -Quiet "wanliz utils hosts")) {
    Write-Host "[SKIPPED]"
} else {
    $hostsToAdd = Get-Content "$PSScriptRoot\..\hosts.txt"
    Add-Content -Path $hostsFile -Value $marker
    Add-Content -Path $hostsFile -Value $hostsToAdd
    Write-Host "[OK]"
}

Read-Host "Press [Enter] to exit"