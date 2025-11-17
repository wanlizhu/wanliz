param([Parameter(Mandatory)][string]$Path)
$Path = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$ErrorActionPreference = 'Stop'

trap {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo.PositionMessage) { 
        Write-Host "$($_.InvocationInfo.PositionMessage)" -ForegroundColor Yellow 
    }
    Read-Host "Press [Enter] to exit"
    exit 1
}

if (-not ('RM' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using FILETIME = System.Runtime.InteropServices.ComTypes.FILETIME; 

public static class RM {
    [StructLayout(LayoutKind.Sequential)] struct RP { public int dwProcessId; public FILETIME ft; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PI {
        public RP P;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string n1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]  public string n2;
        public uint t, s, ts;
        [MarshalAs(UnmanagedType.Bool)] public bool r;
    }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmStartSession(out uint h, int f, StringBuilder k);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmRegisterResources(uint h, uint n, string[] files, uint a, IntPtr apps, uint s, string[] svcs);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmGetList(uint h, out uint need, ref uint have, [In, Out] PI[] info, ref uint why);
    [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint h);
    public static int[] Pids(string[] files) {
        uint h; var k = new StringBuilder(33);
        if (RmStartSession(out h, 0, k) != 0) return new int[0];
        try {
            if (RmRegisterResources(h, (uint)files.Length, files, 0, IntPtr.Zero, 0, null) != 0) return new int[0];
            uint need=0, have=0, why=0; PI[] info=null;
            int r = RmGetList(h, out need, ref have, null, ref why);
            if (r == 234) { info = new PI[need]; have = need; r = RmGetList(h, out need, ref have, info, ref why); }
            var list = new List<int>();
            if (info != null) for (int i=0;i<have;i++) list.Add(info[i].P.dwProcessId);
            return list.ToArray();
        } finally { RmEndSession(h); }
    }
}
'@
}

# Collect files (cap recursion if desired)
if (Test-Path -LiteralPath $Path -PathType Container) {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Select-Object -Expand FullName
    if (-not $files) { 
        $files = ,$Path 
    }
} else { 
    $files = ,$Path 
}

$pids = [RM]::Pids($files) | Sort-Object -Unique
if (-not $pids) { 
    Write-Host 'No locking processes.'
    Read-Host 'Press [Enter] to exit' | Out-Null
    exit 
}

$procs   = Get-Process -Id $pids -ErrorAction SilentlyContinue
$explr   = $procs | Where-Object { $_.ProcessName -ieq 'explorer' }
$others  = $procs | Where-Object { $_.ProcessName -ine 'explorer' }
$hasEx   = [bool]$explr
$doKillOthers = $false
$procs | Select-Object Id,ProcessName,Path | Format-Table -AutoSize

if ($hasEx) { 
    Write-Host 'File Explorer is locking the target, will restart it' 
}

if ($others) {
    $doKillOthers = (Read-Host 'Kill all locking processes? (y/N)') -match '^(y|yes)$'
}

if ($doKillOthers) {
    $others | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

if ($hasEx) {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Host 'File Explorer restarted'
}

if ($doKillOthers -or $hasEx) { 
    Write-Host 'Killed all lockers' 
} else { 
    Write-Host 'Canceled' 
}

Read-Host 'Press [Enter] to exit' | Out-Null
