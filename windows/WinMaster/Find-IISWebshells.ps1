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
    .\Find-IISWebshells.ps1 -DaysBack 30
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 30,
    [string]$LogPath = "C:\inetpub\logs\LogFiles",
    [string[]]$ExtraPaths = @(),
    [string]$Action
)

$ErrorActionPreference = 'SilentlyContinue'
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding($Type, $Path, $Detail, $Severity = 'Medium', $ProcessId, $CreationTime) {
    $findings.Add([pscustomobject]@{
        Time     = Get-Date -Format s
        Type     = $Type
        Severity = $Severity
        Path     = $Path
        Detail   = $Detail
        ProcessId = $ProcessId
        CreationTime = $CreationTime
    })
}

Write-Host "`n====== Search for IIS Webshells ======`n"

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
        Where-Object { $_.DirectoryName -match '(?i)\\(uploads?|images?|img|media|files|content|assets|temp)(?:\\|$)' } |
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
                "PID=$($_.ProcessId) Parent=$($_.ParentProcessId) Cmd=$($_.CommandLine)" 'High' $_.ProcessId $_.CreationDate
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
if(-not (Test-Path $LogPath)) { 
    Write-Host -ForegroundColor Yellow "[$(Get-Date -Format 'HH:mm:ss')] Log path not found: $LogPath. Skipping log analysis." 
    $skip1 = $false    
} else {
    $skip1 = $true
}

if((Test-Path $LogPath) -and $skip1) {
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

$sorted | Group-Object Severity | ForEach-Object { Write-Host -ForegroundColor Yellow ("[$(Get-Date -Format 'HH:mm:ss')] {0}: {1}" -f $_.Name, $_.Count) }
$sorted | Where-Object Severity -eq 'High' | Format-Table Type, Path, Detail -AutoSize -Wrap

Write-Host ""


# ---------------------------------------------------------------
# Interactive review � enabled with -Action Review
# ---------------------------------------------------------------
if($Action -eq 'Review') {

    if(-not $sorted) {
        Write-Host "No findings to review." -ForegroundColor Green
    }

    :ReviewFindings foreach($finding in $sorted) {

        # Show the current finding.
        Write-Host "`n====== Review Finding ======" -ForegroundColor Cyan
        Write-Host "Timestamp: [$(Get-Date -Format 'HH:mm:ss')]"
        $finding |
            Format-List Type, Severity, Path, Detail |
            Out-Host

        # Keep prompting until the operator enters a valid choice.
        do {
            $choice = (Read-Host "[R] Remediate | [S] Skip (default) | [Q] Quit").
                Trim().ToUpperInvariant()

            if ($choice -notin @('', 'R', 'S', 'Q')) {
                Write-Host "Enter R, S, or Q." -ForegroundColor Yellow
            }
        } until ($choice -in @('', 'R', 'S', 'Q'))

        if ($choice -eq 'Q') {
            Write-Host "Leaving interactive review."
            break ReviewFindings
        }

        # Enter without a selection also skips the finding.
        if ($choice -ne 'R') {
            Write-Host "Skipped."
            continue ReviewFindings
        }

        try {
            # Choose the appropriate action for this finding type.
            switch ($finding.Type) {

                { $_ -in @('SuspiciousContent', 'DoubleExtension', 'ScriptInStaticDir') } {

                    # Delete the file
                    Remove-Item -LiteralPath $finding.Path -Force -ErrorAction Stop
                }

                'W3WPChildProcess' {
                    $child = Get-Process -Id $finding.ProcessId -ErrorAction Stop
                    # Hold the process handle while verifying the PID still belongs to this finding.
                    $null = $child.Handle
                    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($finding.ProcessId)" -ErrorAction Stop
                    if (-not $finding.CreationTime -or $current.CreationDate -ne $finding.CreationTime) {
                        throw "PID $($finding.ProcessId) no longer identifies the detected process."
                    }
                    Stop-Process -InputObject $child -Force -ErrorAction Stop
                }

                default {
                    # Timestamp, compiled-file, and historical/log findings
                    # require investigation before selecting a concrete fix.
                    Write-Warning (
                        "Manual review required for finding type: {0}" -f
                        $finding.Type
                    )
                }
            }
        }
        catch {
            Write-Warning (
                "Action generically failed for '{0}': {1}" -f
                $finding.Path, $_.Exception.Message
            )
        }
    }
    Write-Host ""
}
