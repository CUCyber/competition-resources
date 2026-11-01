# Author BlueNitrobotX

#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Hunts for tampering with Windows accessibility binaries and related
    persistence / hiding techniques. Compatible with Windows PowerShell 5.1.

.DESCRIPTION
    Checks performed (default run takes a few seconds):
      1. Accessibility binaries (sethc, Utilman, osk, Narrator, Magnify,
         DisplaySwitch, AtBroker): missing, symlinked, hash-identical to a shell
         or script host, bad/non-Microsoft signature, wrong owner, wrong
         version-resource name. Optional sfc verification (-DeepVerify).
      2. Image File Execution Options (x64 + x86): Debugger, GlobalFlag,
         VerifierDlls, filter subkeys; SilentProcessExit MonitorProcess; AeDebug.
      3. Winlogon (Shell, Userinit, Taskman, GinaDLL, UIHost, AppSetup) and
         AppInit_DLLs (x64 + x86).
      4. WMI permanent event subscriptions (filters and consumers).
      5. Hidden files and alternate data streams in the Windows, System,
         System32 and SysWOW64 folders.
      6. (-DeepScan) Parallel Authenticode sweep of every binary in those folders.

    Each flagged item lists the individual sub-reasons, each with its own
    severity (High / Medium / Low / Info). Results are also exported to CSV with a
    SHA256 sidecar file for evidence handling.

.PARAMETER OutputPath
    Folder for the CSV report. Default: .\WinMaster_Evidence

.PARAMETER DeepScan
    Adds a multi-threaded signature sweep of all executables in the system folders.

.PARAMETER DeepVerify
    Also runs 'sfc /verifyfile' on each accessibility binary (slow: several seconds each).

.PARAMETER ShowInfo
    Also display Info-level findings (for example ordinary hidden data files).

.PARAMETER NoExport
    Do not write the CSV report.

.PARAMETER PassThru
    Emit the finding objects to the pipeline.

.EXAMPLE
    .\Find-WindowsTamper.ps1
.EXAMPLE
    .\Find-WindowsTamper.ps1 -DeepScan -ShowInfo
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Get-Location).Path 'WinMaster_Evidence'),
    [switch]$DeepScan,
    [switch]$DeepVerify,
    [switch]$ShowInfo,
    [switch]$NoExport,
    [switch]$PassThru
)

# ---------------------------------------------------------------------------
# Environment sanity
# ---------------------------------------------------------------------------
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Warning '32-bit PowerShell on 64-bit Windows: file system redirection would hide the real System32. Re-run in 64-bit PowerShell.'
    return
}

$script:SevRank  = @{ High = 3; Medium = 2; Low = 1; Info = 0 }
$script:SevColor = @{ High = 'Red'; Medium = 'Yellow'; Low = 'Cyan'; Info = 'DarkGray' }
$script:Findings = New-Object 'System.Collections.Generic.List[object]'
$script:Timer    = [Diagnostics.Stopwatch]::StartNew()

$WinDir  = $env:SystemRoot
$Sys32   = Join-Path $WinDir 'System32'
$SysWow  = Join-Path $WinDir 'SysWOW64'
$ScanDirs = @($WinDir, (Join-Path $WinDir 'System'), $Sys32, $SysWow) |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$script:AccNames   = @('sethc.exe', 'Utilman.exe', 'osk.exe', 'Narrator.exe', 'Magnify.exe', 'DisplaySwitch.exe', 'AtBroker.exe')
$script:ShellHosts = @('cmd.exe', 'powershell.exe', 'pwsh.exe', 'wscript.exe', 'cscript.exe', 'mshta.exe', 'rundll32.exe',
                       'regsvr32.exe', 'msiexec.exe', 'bitsadmin.exe', 'certutil.exe', 'wmic.exe', 'schtasks.exe',
                       'sc.exe', 'net.exe', 'net1.exe', 'curl.exe', 'conhost.exe')
$script:BenignDbg  = '(?i)vsjitdebugger\.exe|procexp(64)?\.exe|windbg(x)?\.exe|drwtsn32\.exe'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function New-Reason {
    param([string]$Severity, [string]$Text)
    [pscustomobject]@{ Severity = $Severity; Text = $Text }
}

function Add-Finding {
    param([string]$Check, [string]$Target, [object[]]$Reasons)
    if (-not $Reasons -or $Reasons.Count -eq 0) { return }
    $sorted = @($Reasons | Sort-Object { -($script:SevRank[$_.Severity]) })
    $script:Findings.Add([pscustomobject]@{
        Severity = $sorted[0].Severity
        Check    = $Check
        Target   = $Target
        Reasons  = $sorted
    })
}

# Fast SHA256 using .NET directly (no cmdlet overhead, tolerates locked files)
function Get-FileSha256 {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = $null
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        [BitConverter]::ToString($sha.ComputeHash($fs)).Replace('-', '')
    }
    catch { $null }
    finally {
        if ($fs) { $fs.Dispose() }
        $sha.Dispose()
    }
}

function Get-SigInfo {
    param([string]$Path)
    $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $s) { return [pscustomobject]@{ Status = 'Unknown'; Subject = ''; IsMicrosoft = $false } }
    $subj = ''
    if ($s.SignerCertificate) { $subj = $s.SignerCertificate.Subject }
    [pscustomobject]@{
        Status      = [string]$s.Status
        Subject     = $subj
        IsMicrosoft = [bool]($subj -match 'O=Microsoft Corporation')
    }
}

# Analyses a command line (debugger / monitor process / consumer) and returns sub-reasons
function Get-CommandReasons {
    param([string]$Command, [string]$Label = 'Command')
    $r = New-Object 'System.Collections.Generic.List[object]'
    try {
        $cmd = $Command.Trim()
        if     ($cmd -match '^"([^"]+)"')                                                 { $exe = $Matches[1] }
        elseif ($cmd -match '^(.+?\.(?:exe|com|bat|cmd|scr|vbs|js|ps1|dll))(?:\s|$)')      { $exe = $Matches[1] }
        else                                                                              { $exe = ($cmd -split '\s+')[0] }
        $exe  = [Environment]::ExpandEnvironmentVariables($exe)
        $leaf = [IO.Path]::GetFileName($exe)

        $resolved = $null
        if ([IO.Path]::IsPathRooted($exe)) {
            if (Test-Path -LiteralPath $exe -PathType Leaf) { $resolved = $exe }
        }
        else {
            $c = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($c) { $resolved = $c.Source }
        }

        if ($script:ShellHosts -contains $leaf) {
            $r.Add((New-Reason 'High' "$Label launches '$leaf' (shell / script host / LOLBin)"))
        }
        if (-not $resolved) {
            $r.Add((New-Reason 'Medium' "$Label target not found on disk: $exe"))
        }
        else {
            $sig = Get-SigInfo $resolved
            if ($sig.Status -ne 'Valid') { $r.Add((New-Reason 'High' "$Label target signature status is $($sig.Status): $resolved")) }
            elseif (-not $sig.IsMicrosoft) { $r.Add((New-Reason 'Low' "$Label target is signed by a third party: $($sig.Subject)")) }
        }
        if ("$exe $resolved" -match '(?i)\\(users|programdata|temp|appdata|public|perflogs)\\') {
            $r.Add((New-Reason 'High' "$Label target is in a user-writable location: $exe"))
        }
        if ($cmd -match '(?i)(-enc(odedcommand)?\b|-w(indowstyle)?\s+hidden|-nop\b|frombase64string|downloadstring|\biex\b|https?://)') {
            $r.Add((New-Reason 'High' "$Label command line contains suspicious tokens (encoded/hidden/download)"))
        }
    }
    catch {
        $r.Add((New-Reason 'Low' "$Label could not be fully analysed: $($_.Exception.Message)"))
    }
    ,$r
}

# Debugger-style hijack (IFEO etc.): main reason + command analysis sub-reasons
function Get-DebuggerReasons {
    param([string]$Image, [string]$Command, [string]$Kind)
    $r = New-Object 'System.Collections.Generic.List[object]'
    $extra = Get-CommandReasons -Command $Command -Label 'Debugger'
    $hasHigh = $false
    foreach ($x in $extra) { if ($x.Severity -eq 'High') { $hasHigh = $true } }

    if ($script:AccNames -contains $Image) {
        $r.Add((New-Reason 'High' "$Kind set on accessibility binary '$Image': '$Command' will run as SYSTEM from the logon screen"))
    }
    elseif (($Command -match $script:BenignDbg) -and -not $hasHigh) {
        $r.Add((New-Reason 'Low' "$Kind on '$Image' points to a known debugger/tool: '$Command' (confirm it is intentional)"))
    }
    else {
        $r.Add((New-Reason 'Medium' "$Kind set on '$Image': '$Command' (image hijack / persistence)"))
    }
    foreach ($x in $extra) { $r.Add($x) }
    ,$r
}

# Multi-threaded Authenticode checks (used only by -DeepScan)
function Get-SignaturesParallel {
    param([string[]]$Paths)
    if (-not $Paths -or $Paths.Count -eq 0) { return }
    $threads = [Math]::Max(2, [Math]::Min([Environment]::ProcessorCount, 8))
    $buckets = @()
    for ($i = 0; $i -lt $threads; $i++) { $buckets += ,(New-Object 'System.Collections.Generic.List[string]') }
    for ($i = 0; $i -lt $Paths.Count; $i++) { $buckets[$i % $threads].Add($Paths[$i]) }

    $worker = {
        param([string[]]$List)
        foreach ($p in $List) {
            $s = Get-AuthenticodeSignature -LiteralPath $p -ErrorAction SilentlyContinue
            if ($s) {
                $subj = ''
                if ($s.SignerCertificate) { $subj = $s.SignerCertificate.Subject }
                [pscustomobject]@{ Path = $p; Status = [string]$s.Status; Subject = $subj }
            }
        }
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $threads)
    $pool.Open()
    $jobs = @()
    try {
        foreach ($b in $buckets) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker).AddArgument($b.ToArray())
            $jobs += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
        }
        foreach ($j in $jobs) {
            $j.PS.EndInvoke($j.Handle)
            $j.PS.Dispose()
        }
    }
    finally {
        $pool.Close()
        $pool.Dispose()
    }
}

# Runs one check, times it, and prints a one-line status
function Invoke-Check {
    param([string]$Name, [scriptblock]$Body)
    $before = $script:Findings.Count
    $sw  = [Diagnostics.Stopwatch]::StartNew()
    $err = $null
    try { & $Body } catch { $err = $_.Exception.Message }
    $sw.Stop()

    $added = $script:Findings.Count - $before
    $top = -1
    for ($i = $before; $i -lt $script:Findings.Count; $i++) {
        $rank = $script:SevRank[$script:Findings[$i].Severity]
        if ($rank -gt $top) { $top = $rank }
    }
    $tag = 'OK'; $color = 'Green'
    if ($err)           { $tag = 'ERROR'; $color = 'Magenta' }
    elseif ($top -ge 1) { $tag = 'FLAG';  $color = 'Yellow' }
    elseif ($added -gt 0) { $tag = 'INFO'; $color = 'DarkGray' }

    Write-Host '  [' -NoNewline
    Write-Host ('{0,-5}' -f $tag) -ForegroundColor $color -NoNewline
    Write-Host ('] {0,-40} {1,6:N2}s' -f $Name, $sw.Elapsed.TotalSeconds) -NoNewline
    if ($added -gt 0) { Write-Host ('  {0} item(s)' -f $added) -ForegroundColor $color -NoNewline }
    if ($err)         { Write-Host ('  {0}' -f $err) -ForegroundColor Magenta -NoNewline }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkCyan
Write-Host '  Windows Tamper / Persistence Hunt' -ForegroundColor White
Write-Host ('  Host: {0}    Time: {1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$mode = 'Standard'
if ($DeepScan)   { $mode += ' + DeepScan' }
if ($DeepVerify) { $mode += ' + DeepVerify (sfc)' }
Write-Host ('  Mode: {0}' -f $mode)
Write-Host ('=' * 70) -ForegroundColor DarkCyan
Write-Host ''

# ---------------------------------------------------------------------------
# Check 1: Accessibility binaries
# ---------------------------------------------------------------------------
Invoke-Check 'Accessibility binaries' {
    # Reference hashes of shells / script hosts commonly copied over these files
    $refTargets = @{
        'cmd.exe'        = (Join-Path $Sys32 'cmd.exe')
        'powershell.exe' = (Join-Path $Sys32 'WindowsPowerShell\v1.0\powershell.exe')
        'wscript.exe'    = (Join-Path $Sys32 'wscript.exe')
        'cscript.exe'    = (Join-Path $Sys32 'cscript.exe')
        'mshta.exe'      = (Join-Path $Sys32 'mshta.exe')
        'rundll32.exe'   = (Join-Path $Sys32 'rundll32.exe')
        'regsvr32.exe'   = (Join-Path $Sys32 'regsvr32.exe')
        'explorer.exe'   = (Join-Path $WinDir 'explorer.exe')
    }
    $refHash = @{}
    foreach ($k in $refTargets.Keys) {
        $h = Get-FileSha256 $refTargets[$k]
        if ($h) { $refHash[$h] = $k }
    }

    $paths = @()
    foreach ($n in $script:AccNames) { $paths += (Join-Path $Sys32 $n) }
    if (Test-Path -LiteralPath $SysWow) {
        foreach ($n in $script:AccNames) {
            $p = Join-Path $SysWow $n
            if (Test-Path -LiteralPath $p -PathType Leaf) { $paths += $p }
        }
    }

    foreach ($p in $paths) {
        $reasons = New-Object 'System.Collections.Generic.List[object]'
        $leaf = Split-Path $p -Leaf

        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            $reasons.Add((New-Reason 'Medium' 'File is missing (deleted or renamed; possibly staged for replacement)'))
            Add-Finding 'Accessibility binary' $p $reasons
            continue
        }

        $item = Get-Item -LiteralPath $p -Force

        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $tgt = ''
            try { $tgt = ($item.Target -join ', ') } catch { }
            $reasons.Add((New-Reason 'High' "File is a symbolic link / reparse point -> $tgt"))
        }

        $hash = Get-FileSha256 $p
        if ($hash -and $refHash.ContainsKey($hash)) {
            $reasons.Add((New-Reason 'High' "SHA256 is identical to $($refHash[$hash]) (binary replaced with a shell / script host)"))
        }

        $sig = Get-SigInfo $p
        if     ($sig.Status -eq 'HashMismatch') { $reasons.Add((New-Reason 'High' 'Signature hash mismatch (file modified after signing)')) }
        elseif ($sig.Status -eq 'NotSigned')    { $reasons.Add((New-Reason 'High' 'File is not digitally signed')) }
        elseif ($sig.Status -ne 'Valid')        { $reasons.Add((New-Reason 'Medium' "Signature status is $($sig.Status)")) }
        elseif (-not $sig.IsMicrosoft)          { $reasons.Add((New-Reason 'High' "Signed by a non-Microsoft publisher: $($sig.Subject)")) }

        try {
            $owner = (Get-Acl -LiteralPath $p -ErrorAction Stop).Owner
            if ($owner -notmatch 'TrustedInstaller') {
                $reasons.Add((New-Reason 'Medium' "Owner is '$owner' (expected NT SERVICE\TrustedInstaller)"))
            }
        }
        catch { $reasons.Add((New-Reason 'Low' 'Could not read file owner')) }

        $orig = $item.VersionInfo.OriginalFilename
        if (-not $orig)          { $reasons.Add((New-Reason 'Low' 'No version resource (original file name missing)')) }
        elseif ($orig -ne $leaf) { $reasons.Add((New-Reason 'Medium' "Version resource original name is '$orig' but file is '$leaf'")) }

        if ($DeepVerify) {
            $txt = ((& sfc.exe "/verifyfile=$p" 2>&1) | Out-String) -replace '\0', ''
            if     ($txt -match 'did not find any integrity violations') { }
            elseif ($txt -match 'found integrity violations')            { $reasons.Add((New-Reason 'High' 'sfc /verifyfile reports an integrity violation')) }
            else                                                         { $reasons.Add((New-Reason 'Low' 'sfc result inconclusive (non-English OS or sfc could not run)')) }
        }

        Add-Finding 'Accessibility binary' $p $reasons
    }
}

# ---------------------------------------------------------------------------
# Check 2: IFEO, SilentProcessExit, AeDebug (x64 + x86 registry views)
# ---------------------------------------------------------------------------
Invoke-Check 'IFEO / SilentProcessExit / AeDebug' {
    $cv = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    foreach ($view in 'Registry64', 'Registry32') {
        $arch = 'x64'; if ($view -eq 'Registry32') { $arch = 'x86' }
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
        try {
            # --- Image File Execution Options ---
            $ifeo = $hklm.OpenSubKey("$cv\Image File Execution Options")
            if ($ifeo) {
                foreach ($name in $ifeo.GetSubKeyNames()) {
                    $k = $ifeo.OpenSubKey($name)
                    if (-not $k) { continue }
                    $reasons = New-Object 'System.Collections.Generic.List[object]'

                    $dbg = $k.GetValue('Debugger')
                    if ($dbg) {
                        foreach ($x in (Get-DebuggerReasons -Image $name -Command ([string]$dbg) -Kind 'IFEO Debugger')) { $reasons.Add($x) }
                    }

                    $gf = $k.GetValue('GlobalFlag')
                    if ($null -ne $gf) {
                        $gfv = 0
                        try { $gfv = [int]$gf } catch { }
                        $hex = '0x{0:X}' -f $gfv
                        if ($gfv -band 0x200) {
                            $reasons.Add((New-Reason 'Medium' "GlobalFlag $hex enables silent-process-exit monitoring for '$name' (can launch a monitor process on exit)"))
                        }
                        else {
                            $reasons.Add((New-Reason 'Low' "GlobalFlag $hex set on '$name' (used by gflags / Application Verifier; confirm intentional)"))
                        }
                    }

                    $vd = $k.GetValue('VerifierDlls')
                    if ($vd) { $reasons.Add((New-Reason 'Medium' "VerifierDlls = '$vd' (DLL loaded into '$name')")) }

                    # Filter-based (UseFilter) child keys can carry their own Debugger
                    foreach ($sub in $k.GetSubKeyNames()) {
                        $sk = $k.OpenSubKey($sub)
                        if (-not $sk) { continue }
                        $fd = $sk.GetValue('Debugger')
                        if ($fd) {
                            foreach ($x in (Get-DebuggerReasons -Image $name -Command ([string]$fd) -Kind "IFEO filter Debugger [$sub]")) { $reasons.Add($x) }
                        }
                        $sk.Close()
                    }

                    Add-Finding 'IFEO' "HKLM\...\Image File Execution Options\$name [$arch]" $reasons
                    $k.Close()
                }
                $ifeo.Close()
            }

            # --- SilentProcessExit (MonitorProcess) ---
            $spe = $hklm.OpenSubKey("$cv\SilentProcessExit")
            if ($spe) {
                foreach ($name in $spe.GetSubKeyNames()) {
                    $k = $spe.OpenSubKey($name)
                    if (-not $k) { continue }
                    $mp = $k.GetValue('MonitorProcess')
                    if ($mp) {
                        $reasons = New-Object 'System.Collections.Generic.List[object]'
                        $sev = 'Medium'
                        if ($script:AccNames -contains $name) { $sev = 'High' }
                        $reasons.Add((New-Reason $sev "MonitorProcess '$mp' will run whenever '$name' exits"))
                        foreach ($x in (Get-CommandReasons -Command ([string]$mp) -Label 'MonitorProcess')) { $reasons.Add($x) }
                        Add-Finding 'SilentProcessExit' "HKLM\...\SilentProcessExit\$name [$arch]" $reasons
                    }
                    $k.Close()
                }
                $spe.Close()
            }

            # --- AeDebug (post-mortem debugger for any crashing process) ---
            $ae = $hklm.OpenSubKey("$cv\AeDebug")
            if ($ae) {
                $d = $ae.GetValue('Debugger')
                if ($d) {
                    $reasons = New-Object 'System.Collections.Generic.List[object]'
                    $sev = 'Low'
                    $auto = $ae.GetValue('Auto')
                    if ("$auto" -eq '1') { $sev = 'Medium' }
                    $reasons.Add((New-Reason $sev "AeDebug Debugger = '$d' runs when any process crashes (Auto=$auto)"))
                    foreach ($x in (Get-CommandReasons -Command ([string]$d) -Label 'AeDebug')) { $reasons.Add($x) }
                    Add-Finding 'AeDebug' "HKLM\$cv\AeDebug [$arch]" $reasons
                }
                $ae.Close()
            }
        }
        finally { $hklm.Close() }
    }
}

# ---------------------------------------------------------------------------
# Check 3: Winlogon values and AppInit_DLLs
# ---------------------------------------------------------------------------
Invoke-Check 'Winlogon / AppInit_DLLs' {
    $cv = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    try {
        $wl = $hklm.OpenSubKey("$cv\Winlogon")
        if ($wl) {
            $reasons = New-Object 'System.Collections.Generic.List[object]'

            $shell = $wl.GetValue('Shell')
            if ($shell -and ([string]$shell).Trim() -ne 'explorer.exe') {
                $reasons.Add((New-Reason 'High' "Shell is '$shell' (expected 'explorer.exe')"))
            }

            $ui = $wl.GetValue('Userinit')
            if ($ui) {
                $expected = Join-Path $Sys32 'userinit.exe'
                foreach ($e in (([string]$ui) -split ',')) {
                    $e = $e.Trim()
                    if ($e -and $e -ne $expected) { $reasons.Add((New-Reason 'High' "Userinit launches an unexpected program: '$e'")) }
                }
            }

            $tm = $wl.GetValue('Taskman')
            if ($tm) { $reasons.Add((New-Reason 'High' "Taskman = '$tm' (replaces Task Manager; not present on a default install)")) }
            $gina = $wl.GetValue('GinaDLL')
            if ($gina) { $reasons.Add((New-Reason 'High' "GinaDLL = '$gina' (custom logon DLL; not used on modern Windows)")) }
            $uih = $wl.GetValue('UIHost')
            if ($uih -and ([string]$uih).Trim() -ne 'logonui.exe') { $reasons.Add((New-Reason 'High' "UIHost is '$uih' (expected 'logonui.exe')")) }
            $setup = $wl.GetValue('AppSetup')
            if ($setup) { $reasons.Add((New-Reason 'Medium' "AppSetup = '$setup' (legacy logon launch point)")) }

            Add-Finding 'Winlogon' "HKLM\$cv\Winlogon" $reasons
            $wl.Close()
        }
    }
    finally { $hklm.Close() }

    foreach ($view in 'Registry64', 'Registry32') {
        $arch = 'x64'; if ($view -eq 'Registry32') { $arch = 'x86' }
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
        try {
            $w = $hklm.OpenSubKey("$cv\Windows")
            if ($w) {
                $reasons = New-Object 'System.Collections.Generic.List[object]'
                $dlls = [string]$w.GetValue('AppInit_DLLs')
                $load = $w.GetValue('LoadAppInit_DLLs')
                $req  = $w.GetValue('RequireSignedAppInit_DLLs')

                if ($dlls -and $dlls.Trim()) {
                    $sev = 'Medium'
                    if ("$load" -eq '1') { $sev = 'High' }
                    $reasons.Add((New-Reason $sev "AppInit_DLLs = '$($dlls.Trim())' is injected into processes loading user32.dll (LoadAppInit_DLLs=$load)"))
                    if ("$req" -eq '0') { $reasons.Add((New-Reason 'Medium' 'RequireSignedAppInit_DLLs = 0 (unsigned DLLs allowed)')) }
                }
                elseif ("$load" -eq '1') {
                    $reasons.Add((New-Reason 'Low' 'LoadAppInit_DLLs = 1 although AppInit_DLLs is empty (pre-staged?)'))
                }
                foreach ($legacy in 'Load', 'Run') {
                    $v = $w.GetValue($legacy)
                    if ($v -and ([string]$v).Trim()) { $reasons.Add((New-Reason 'Medium' "Legacy win.ini-style value '$legacy' = '$v'")) }
                }
                Add-Finding 'AppInit_DLLs' "HKLM\$cv\Windows [$arch]" $reasons
                $w.Close()
            }
        }
        finally { $hklm.Close() }
    }
}

# ---------------------------------------------------------------------------
# Check 4: WMI permanent event subscriptions
# ---------------------------------------------------------------------------
Invoke-Check 'WMI event subscriptions' {
    $ns = 'root\subscription'

    foreach ($cls in 'CommandLineEventConsumer', 'ActiveScriptEventConsumer', 'NTEventLogEventConsumer', 'SMTPEventConsumer', 'LogFileEventConsumer') {
        $items = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction SilentlyContinue
        foreach ($i in $items) {
            if ($i.Name -eq 'SCM Event Log Consumer') { continue }   # default Windows consumer
            $reasons = New-Object 'System.Collections.Generic.List[object]'
            if ($cls -eq 'CommandLineEventConsumer') {
                $cmd = $i.CommandLineTemplate
                if (-not $cmd) { $cmd = $i.ExecutablePath }
                $reasons.Add((New-Reason 'High' "Permanent consumer '$($i.Name)' executes: $cmd"))
                if ($cmd) { foreach ($x in (Get-CommandReasons -Command ([string]$cmd) -Label 'Consumer')) { $reasons.Add($x) } }
            }
            elseif ($cls -eq 'ActiveScriptEventConsumer') {
                $reasons.Add((New-Reason 'High' "Permanent consumer '$($i.Name)' runs a $($i.ScriptingEngine) script (file: '$($i.ScriptFileName)')"))
            }
            else {
                $reasons.Add((New-Reason 'Medium' "Non-default permanent $cls '$($i.Name)'"))
            }
            Add-Finding 'WMI consumer' "$ns : $cls : $($i.Name)" $reasons
        }
    }

    $filters = Get-CimInstance -Namespace $ns -ClassName '__EventFilter' -ErrorAction SilentlyContinue
    foreach ($f in $filters) {
        if ($f.Name -eq 'SCM Event Log Filter') { continue }
        $reasons = New-Object 'System.Collections.Generic.List[object]'
        $reasons.Add((New-Reason 'Medium' "Permanent event filter '$($f.Name)' with query: $($f.Query)"))
        Add-Finding 'WMI filter' "$ns : __EventFilter : $($f.Name)" $reasons
    }
}

# ---------------------------------------------------------------------------
# Check 5: Hidden files + alternate data streams
# ---------------------------------------------------------------------------
Invoke-Check 'Hidden files & alternate data streams' {
    $peExt     = @('.exe', '.dll', '.sys', '.scr', '.cpl', '.ocx', '.com', '.drv')
    $scriptExt = @('.bat', '.cmd', '.ps1', '.vbs', '.vbe', '.js', '.jse', '.wsf', '.hta', '.lnk')

    # Hidden attribute (single .NET enumeration per folder, no cmdlet overhead)
    foreach ($d in $ScanDirs) {
        try {
            foreach ($f in (New-Object IO.DirectoryInfo $d).EnumerateFiles()) {
                if (-not ($f.Attributes -band [IO.FileAttributes]::Hidden)) { continue }
                $ext = $f.Extension.ToLowerInvariant()
                $reasons = New-Object 'System.Collections.Generic.List[object]'

                if ($peExt -contains $ext) {
                    $reasons.Add((New-Reason 'Medium' 'Hidden attribute set on an executable / binary file'))
                    $sig = Get-SigInfo $f.FullName
                    if     ($sig.Status -ne 'Valid')  { $reasons.Add((New-Reason 'High' "Signature status is $($sig.Status)")) }
                    elseif (-not $sig.IsMicrosoft)    { $reasons.Add((New-Reason 'Low' "Signed by a third party: $($sig.Subject)")) }
                }
                elseif ($scriptExt -contains $ext) {
                    $reasons.Add((New-Reason 'Medium' 'Hidden attribute set on a script / shortcut file'))
                }
                else {
                    $reasons.Add((New-Reason 'Info' 'Hidden attribute set (data file)'))
                }
                if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    $reasons.Add((New-Reason 'Medium' 'File is a reparse point (symlink / junction-style)'))
                }
                Add-Finding 'Hidden file' $f.FullName $reasons
            }
        }
        catch { }
    }

    # Alternate data streams: one 'dir /r' per folder is far faster than Get-Item -Stream per file
    $streamMap = @{}
    foreach ($d in $ScanDirs) {
        $lines = & cmd.exe /d /c dir /r /a-d $d 2>$null
        foreach ($line in $lines) {
            if ($line -match '^\s*[\d,.\s]+\s(\S.*?):([^:\\]+):\$DATA\s*$') {
                $full = Join-Path $d $Matches[1]
                $stream = $Matches[2]
                if (-not $streamMap.ContainsKey($full)) {
                    $streamMap[$full] = New-Object 'System.Collections.Generic.List[object]'
                }
                if ($stream -eq 'Zone.Identifier') {
                    $streamMap[$full].Add((New-Reason 'Low' 'Zone.Identifier stream present (file came from outside the system; unexpected in a system folder)'))
                }
                else {
                    $streamMap[$full].Add((New-Reason 'Medium' "Alternate data stream '$stream' attached (can hide a payload)"))
                }
            }
        }
    }
    foreach ($full in $streamMap.Keys) { Add-Finding 'Alternate data stream' $full $streamMap[$full] }
}

# ---------------------------------------------------------------------------
# Check 6 (optional): parallel signature sweep
# ---------------------------------------------------------------------------
if ($DeepScan) {
    Invoke-Check 'Deep signature sweep (parallel)' {
        $ext  = @{ '.exe' = 1; '.dll' = 1; '.sys' = 1; '.scr' = 1; '.cpl' = 1; '.ocx' = 1; '.com' = 1; '.drv' = 1 }
        $list = New-Object 'System.Collections.Generic.List[string]'
        foreach ($d in $ScanDirs) {
            try {
                foreach ($f in (New-Object IO.DirectoryInfo $d).EnumerateFiles()) {
                    if ($ext.ContainsKey($f.Extension.ToLowerInvariant())) { $list.Add($f.FullName) }
                }
            }
            catch { }
        }
        foreach ($s in (Get-SignaturesParallel -Paths $list.ToArray())) {
            if ($s.Status -eq 'Valid' -and $s.Subject -match 'O=Microsoft Corporation') { continue }
            $reasons = New-Object 'System.Collections.Generic.List[object]'
            if     ($s.Status -eq 'HashMismatch') { $reasons.Add((New-Reason 'High' 'Signature present but file hash mismatch (modified after signing)')) }
            elseif ($s.Status -eq 'NotSigned')    { $reasons.Add((New-Reason 'Medium' 'No digital signature')) }
            elseif ($s.Status -ne 'Valid')        { $reasons.Add((New-Reason 'Medium' "Signature status is $($s.Status)")) }
            else                                  { $reasons.Add((New-Reason 'Info' "Signed by a third party: $($s.Subject)")) }
            Add-Finding 'Signature sweep' $s.Path $reasons
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$sorted = @($script:Findings | Sort-Object @{ Expression = { $script:SevRank[$_.Severity] }; Descending = $true }, Check, Target)
$count  = @{ High = 0; Medium = 0; Low = 0; Info = 0 }
foreach ($f in $sorted) { $count[$f.Severity]++ }

Write-Host ''
Write-Host ('-' * 70) -ForegroundColor DarkCyan
Write-Host '  FINDINGS' -ForegroundColor White
Write-Host ('-' * 70) -ForegroundColor DarkCyan

$shown = 0
foreach ($f in $sorted) {
    if ($f.Severity -eq 'Info' -and -not $ShowInfo) { continue }
    $shown++
    Write-Host ''
    Write-Host ('[{0}]' -f $f.Severity.ToUpper()) -ForegroundColor ($script:SevColor[$f.Severity]) -NoNewline
    Write-Host (' {0}' -f $f.Check) -ForegroundColor White -NoNewline
    Write-Host (' | {0}' -f $f.Target)
    foreach ($r in $f.Reasons) {
        if ($r.Severity -eq 'Info' -and -not $ShowInfo) { continue }
        Write-Host '     - ' -NoNewline
        Write-Host ('{0,-6} ' -f $r.Severity.ToUpper()) -ForegroundColor ($script:SevColor[$r.Severity]) -NoNewline
        Write-Host $r.Text
    }
}
if ($shown -eq 0) {
    Write-Host ''
    Write-Host '  No suspicious findings.' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Export (CSV + SHA256 sidecar)
# ---------------------------------------------------------------------------
$csvPath = $null
if (-not $NoExport -and $sorted.Count -gt 0) {
    try {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
        $csvPath = Join-Path $OutputPath ('TamperScan_{0}_{1}.csv' -f $env:COMPUTERNAME, $stamp)
        $now     = Get-Date -Format 'o'
        $rows = foreach ($f in $sorted) {
            foreach ($r in $f.Reasons) {
                [pscustomobject]@{
                    Timestamp       = $now
                    ComputerName    = $env:COMPUTERNAME
                    Check           = $f.Check
                    FindingSeverity = $f.Severity
                    Target          = $f.Target
                    ReasonSeverity  = $r.Severity
                    Reason          = $r.Text
                }
            }
        }
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -NoClobber
        $csvHash = Get-FileSha256 $csvPath
        ('{0}  {1}' -f $csvHash, (Split-Path $csvPath -Leaf)) | Set-Content -LiteralPath ($csvPath + '.sha256') -Encoding ASCII
    }
    catch {
        Write-Warning "Could not write report: $($_.Exception.Message)"
        $csvPath = $null
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$script:Timer.Stop()
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkCyan
Write-Host '  SUMMARY  ' -ForegroundColor White -NoNewline
Write-Host ('High: {0}' -f $count.High) -ForegroundColor Red -NoNewline
Write-Host '  ' -NoNewline
Write-Host ('Medium: {0}' -f $count.Medium) -ForegroundColor Yellow -NoNewline
Write-Host '  ' -NoNewline
Write-Host ('Low: {0}' -f $count.Low) -ForegroundColor Cyan -NoNewline
Write-Host '  ' -NoNewline
Write-Host ('Info: {0}' -f $count.Info) -ForegroundColor DarkGray
if ($count.Info -gt 0 -and -not $ShowInfo) {
    Write-Host '  (Info items are hidden; use -ShowInfo to display them. They are included in the CSV.)' -ForegroundColor DarkGray
}
if ($csvPath) {
    Write-Host ('  Report: {0}' -f $csvPath)
    Write-Host ('  SHA256: {0}' -f $csvHash)
}
Write-Host ('  Elapsed: {0:N2}s' -f $script:Timer.Elapsed.TotalSeconds)
Write-Host ('=' * 70) -ForegroundColor DarkCyan
Write-Host ''

# 2 = High findings, 1 = Medium findings, 0 = otherwise
$global:LASTEXITCODE = 0
if     ($count.High   -gt 0) { $global:LASTEXITCODE = 2 }
elseif ($count.Medium -gt 0) { $global:LASTEXITCODE = 1 }

if ($PassThru) { $sorted }
