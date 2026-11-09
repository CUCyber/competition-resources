<#
.SYNOPSIS
    Sample triage script for hunting suspected webshells on an IIS server.

.DESCRIPTION
    1. Discovers web roots from applicationHost.config
    2. Scans server-side script files for suspicious content patterns
    3. Flags recently modified/created files and odd extensions
    4. Checks for w3wp.exe spawning suspicious child processes
    5. Greps IIS logs for common webshell request patterns

    This is a heuristic triage tool. Expect false positives, and treat
    a clean result as "nothing obvious," not "clean."

.EXAMPLE
    .\Find-IISWebshells.ps1 -DaysBack 30 -OutputCsv C:\Temp\webshell_hits.csv
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 30,
    [string]$LogPath = "C:\inetpub\logs\LogFiles",
    [string]$OutputCsv = ".\iis_webshell_findings.csv",
    [string[]]$ExtraPaths = @()
)

$ErrorActionPreference = 'SilentlyContinue'
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding($Type, $Path, $Detail, $Severity = 'Medium') {
    $findings.Add([pscustomobject]@{
        Time     = Get-Date -Format s
        Type     = $Type
        Severity = $Severity
        Path     = $Path
        Detail   = $Detail
    })
}

# ---------------------------------------------------------------
# 1. Discover web roots
# ---------------------------------------------------------------
$roots = @()
$appHost = "$env:windir\System32\inetsrv\config\applicationHost.config"
if (Test-Path $appHost) {
    [xml]$cfg = Get-Content $appHost
    foreach ($site in $cfg.configuration.'system.applicationHost'.sites.site) {
        foreach ($app in $site.application) {
            foreach ($vd in $app.virtualDirectory) {
                $p = [Environment]::ExpandEnvironmentVariables($vd.physicalPath)
                if (Test-Path $p) { $roots += $p }
            }
        }
    }
}
$roots += $ExtraPaths
$roots = $roots | Sort-Object -Unique
if (-not $roots) { $roots = @("C:\inetpub\wwwroot") }

Write-Host "[*] Web roots:" -ForegroundColor Cyan
$roots | ForEach-Object { Write-Host "    $_" }

# ---------------------------------------------------------------
# 2. Content signatures (heuristic, not exhaustive)
# ---------------------------------------------------------------
$scriptExt = '*.aspx','*.asp','*.ashx','*.asmx','*.ascx','*.cshtml','*.vbhtml',
             '*.cer','*.asa','*.php','*.jsp','*.config','*.soap','*.svc'

$patterns = @(
    @{ Name='Eval/Execute of request data';  Regex='(?i)\b(eval|execute)\s*\(?\s*request' },
    @{ Name='JScript eval(Request.Item)';    Regex='(?i)eval\s*\(\s*Request\.Item\[' },
    @{ Name='cmd.exe / powershell launch';   Regex='(?i)(cmd\.exe|powershell(\.exe)?)\s*(/c|-enc|-nop|-w\s+hidden)' },
    @{ Name='Process.Start / ProcessStartInfo'; Regex='(?i)(System\.Diagnostics\.)?Process(StartInfo)?\b.*\b(Start|FileName)' },
    @{ Name='WScript.Shell / Shell.Application'; Regex='(?i)(WScript\.Shell|Shell\.Application)' },
    @{ Name='Base64 decode + load/exec';     Regex='(?i)FromBase64String.*(Assembly\.Load|Invoke|Compile)' },
    @{ Name='Assembly.Load of dynamic bytes';Regex='(?i)Assembly\.Load\s*\(' },
    @{ Name='CodeDom runtime compile';       Regex='(?i)(CSharpCodeProvider|CompileAssemblyFromSource)' },
    @{ Name='Reads password/cmd from request'; Regex='(?i)Request(\.Form|\.QueryString|\.Params)?\s*[\[\(]\s*["''](cmd|pass|pwd|exec|c|z0|z1)["'']' },
    @{ Name='Known tool strings';            Regex='(?i)(china\s*chopper|antsword|behinder|godzilla|b374k|c99shell|r57shell|aspxspy|webshell)' },
    @{ Name='Large chr() / obfuscation';     Regex='(?i)(chr\(\d+\)\s*&\s*){6,}' },
    @{ Name='File upload to arbitrary path'; Regex='(?i)(SaveAs|File\.WriteAllBytes)\s*\(.*Request' },
    @{ Name='ViewState/MachineKey abuse';    Regex='(?i)<machineKey[^>]+validationKey=' }
)

$cutoff = (Get-Date).AddDays(-$DaysBack)

foreach ($root in $roots) {
    Write-Host "[*] Scanning $root ..." -ForegroundColor Cyan
    $files = Get-ChildItem -Path $root -Recurse -File -Include $scriptExt -Force

    foreach ($f in $files) {
        # Recently created/modified script files
        if ($f.LastWriteTime -gt $cutoff -or $f.CreationTime -gt $cutoff) {
            Add-Finding 'RecentScriptFile' $f.FullName `
                "Created=$($f.CreationTime) Modified=$($f.LastWriteTime) Size=$($f.Length)" 'Low'
        }

        # Timestomp heuristic: modified long before created
        if ($f.LastWriteTime -lt $f.CreationTime.AddDays(-30)) {
            Add-Finding 'PossibleTimestomp' $f.FullName `
                "Created=$($f.CreationTime) Modified=$($f.LastWriteTime)" 'Medium'
        }

        # Content scan (skip very large files)
        if ($f.Length -lt 5MB) {
            $content = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                foreach ($p in $patterns) {
                    if ($content -match $p.Regex) {
                        $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
                        Add-Finding 'SuspiciousContent' $f.FullName `
                            "$($p.Name) | SHA256=$hash" 'High'
                    }
                }
            }
        }
    }

    # Double extensions and handler-mapped oddities (e.g., .jpg.aspx, .asp;.jpg)
    Get-ChildItem -Path $root -Recurse -File -Force |
        Where-Object { $_.Name -match '(?i)\.(jpg|jpeg|png|gif|txt|pdf|css|js)\.(aspx?|ashx|asmx|cer|asa|php)$' -or
                       $_.Name -match '(?i)\.(aspx?|cer|asa);' } |
        ForEach-Object { Add-Finding 'DoubleExtension' $_.FullName $_.Name 'High' }

    # Script files in upload/image/content dirs (should usually be static only)
    Get-ChildItem -Path $root -Recurse -File -Force -Include '*.aspx','*.ashx','*.asp','*.php' |
        Where-Object { $_.DirectoryName -match '(?i)\\(uploads?|images?|img|media|files|content|assets|temp)\\' } |
        ForEach-Object { Add-Finding 'ScriptInStaticDir' $_.FullName $_.DirectoryName 'Medium' }
}

# ---------------------------------------------------------------
# 3. Check Temporary ASP.NET Files for compiled shells
#    (useful when the source .aspx has already been deleted)
# ---------------------------------------------------------------
$aspTemp = @("$env:windir\Microsoft.NET\Framework64", "$env:windir\Microsoft.NET\Framework") |
    ForEach-Object { Get-ChildItem "$_\v*\Temporary ASP.NET Files" -Directory -ErrorAction SilentlyContinue }
foreach ($t in $aspTemp) {
    Get-ChildItem $t.FullName -Recurse -File -Include '*.dll','*.compiled' |
        Where-Object { $_.LastWriteTime -gt $cutoff } |
        ForEach-Object { Add-Finding 'RecentCompiledASPNET' $_.FullName "Modified=$($_.LastWriteTime)" 'Low' }
}

# ---------------------------------------------------------------
# 4. Live process check: w3wp.exe spawning suspicious children
# ---------------------------------------------------------------
$suspectChildren = 'cmd.exe','powershell.exe','pwsh.exe','whoami.exe','net.exe','net1.exe',
                   'certutil.exe','bitsadmin.exe','wscript.exe','cscript.exe','mshta.exe',
                   'rundll32.exe','regsvr32.exe','nltest.exe','systeminfo.exe','ipconfig.exe'

$w3wpPids = (Get-CimInstance Win32_Process -Filter "Name='w3wp.exe'").ProcessId
if ($w3wpPids) {
    Get-CimInstance Win32_Process |
        Where-Object { $_.ParentProcessId -in $w3wpPids -and $_.Name -in $suspectChildren } |
        ForEach-Object {
            Add-Finding 'W3WPChildProcess' $_.ExecutablePath `
                "PID=$($_.ProcessId) Parent=$($_.ParentProcessId) Cmd=$($_.CommandLine)" 'High'
        }
}

# Historical: process creation events (requires Sysmon or 4688 w/ cmdline auditing)
$sysmon = Get-WinEvent -FilterHashtable @{
    LogName='Microsoft-Windows-Sysmon/Operational'; Id=1; StartTime=$cutoff
} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'ParentImage:.*\\w3wp\.exe' -and
                   $_.Message -match 'Image:.*\\(cmd|powershell|whoami|net1?|certutil)\.exe' }
foreach ($e in $sysmon) {
    Add-Finding 'SysmonW3WPChild' 'Sysmon EID 1' `
        ($e.Message -replace "\r?\n",' | ').Substring(0,[Math]::Min(400,$e.Message.Length)) 'High'
}

# ---------------------------------------------------------------
# 5. IIS log hunting
# ---------------------------------------------------------------
if (Test-Path $LogPath) {
    Write-Host "[*] Scanning IIS logs in $LogPath ..." -ForegroundColor Cyan
    $logPatterns = '(?i)(cmd=|exec=|whoami|powershell|certutil|%20-enc|/c\+|net\+user|\.\./\.\./|eval\()'
    Get-ChildItem $LogPath -Recurse -Filter *.log |
        Where-Object { $_.LastWriteTime -gt $cutoff } |
        ForEach-Object {
            Select-String -Path $_.FullName -Pattern $logPatterns |
                Select-Object -First 50 |
                ForEach-Object {
                    Add-Finding 'SuspiciousLogEntry' $_.Path `
                        ("L{0}: {1}" -f $_.LineNumber, $_.Line.Substring(0,[Math]::Min(300,$_.Line.Length))) 'Medium'
                }
        }

    # POST-only access to a single script from few IPs is a classic shell pattern
    Get-ChildItem $LogPath -Recurse -Filter *.log |
        Where-Object { $_.LastWriteTime -gt $cutoff } |
        ForEach-Object {
            $fields = $null
            Get-Content $_.FullName | ForEach-Object {
                if ($_ -like '#Fields:*') { $fields = $_.Substring(9).Trim().Split(' '); return }
                if ($_ -like '#*' -or -not $fields) { return }
                $v = $_.Split(' ')
                if ($v.Count -ne $fields.Count) { return }
                $row = @{}; for ($i=0; $i -lt $fields.Count; $i++) { $row[$fields[$i]] = $v[$i] }
                if ($row['cs-method'] -eq 'POST' -and $row['cs-uri-stem'] -match '(?i)\.(aspx|ashx|asmx|asp)$') {
                    [pscustomobject]@{ Uri = $row['cs-uri-stem']; Ip = $row['c-ip'] }
                }
            } | Group-Object Uri | Where-Object { $_.Count -gt 20 } |
              ForEach-Object {
                  $ips = ($_.Group.Ip | Sort-Object -Unique).Count
                  if ($ips -le 3) {
                      Add-Finding 'POSTHeavySingleScript' $_.Name `
                          "POSTs=$($_.Count) UniqueIPs=$ips in $($_.Name)" 'Medium'
                  }
              }
        }
}

# ---------------------------------------------------------------
# Output
# ---------------------------------------------------------------
$sorted = $findings | Sort-Object @{e={switch($_.Severity){'High'{0}'Medium'{1}default{2}}}}, Type
$sorted | Export-Csv -NoTypeInformation -Path $OutputCsv
Write-Host "`n[+] $($findings.Count) findings written to $OutputCsv" -ForegroundColor Green
$sorted | Group-Object Severity | ForEach-Object { Write-Host ("    {0}: {1}" -f $_.Name, $_.Count) }
$sorted | Where-Object Severity -eq 'High' | Format-Table Type, Path, Detail -AutoSize -Wrap
