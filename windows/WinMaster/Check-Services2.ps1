# Author BlueNitrobotX

<#
.SYNOPSIS
    Scans Windows services for characteristics commonly associated with malicious or
    persistence-related services, and reports the ones whose combined risk score is high enough.

.DESCRIPTION
    Each service is checked for a set of indicators (suspicious path, unsigned binary, script host
    as the executable, odd names, etc.). Every indicator carries a weight, and the weights are
    summed into a score. Services scoring at or above -MinScore are reported.
    Services can be allowlisted by name (wildcards allowed), but an allowlisted service is only
    skipped if its binary has a valid digital signature AND does not run from a suspicious location.

.PARAMETER SkipExtraChecks
    Skip the noisier name-based checks (short names, high-entropy names, unquoted paths).

.PARAMETER IncludeStopped
    Also examine services that are not currently running.

.PARAMETER MinScore
    Minimum combined indicator weight needed for a service to be reported (1 = report any single hit).

.PARAMETER CsvPath
    Optional path to export the findings to a CSV file (UTF-8).

.PARAMETER ExcludeService
    Service names or wildcard patterns to allowlist, e.g. 'Spooler','Wpn*'.

.PARAMETER ExcludeFile
    Optional text file of allowlist patterns, one per line ('#' starts a comment). Must exist.

.PARAMETER PassThru
    Also emit the result objects to the pipeline, so they can be filtered or exported by the caller.

.EXAMPLE
    .\Find-SuspiciousServices.ps1 -MinScore 1 -CsvPath C:\temp\services.csv

.EXAMPLE
    .\Find-SuspiciousServices.ps1 -ExcludeFile .\allowlist.txt -PassThru | Where-Object Score -ge 5
#>

[CmdletBinding()]
param(
    [switch]$SkipExtraChecks,     # Skip the noisier name-based checks
    [switch]$IncludeStopped,      # Also examine services that are not currently running

    # Only report services whose combined indicator weight >= this (1 = original "any hit" behavior)
    # ValidateRange rejects 0 or negative values, which would report every service
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MinScore = 3,

    [string]$CsvPath,             # Optional: export findings to CSV
    [string[]]$ExcludeService,    # Service names or wildcard patterns, e.g. 'Spooler','Wpn*'

    # Optional text file: one name/pattern per line, '#' for comments
    # Validated up front so a typo gives a clear message instead of a raw Get-Content error later
    [ValidateScript({
        if (Test-Path -LiteralPath $_ -PathType Leaf) { $true }
        else { throw "ExcludeFile not found: $_" }
    })]
    [string]$ExcludeFile,

    [switch]$PassThru             # Also emit the result objects to the pipeline (for filtering / automation)
)

# =================================================================================================
# Script constants and setup
# =================================================================================================

# Script-type extensions that should never be the target of a service
$SuspiciousExtensions = @('.vbs', '.js', '.bat', '.cmd', '.scr', '.ps1')

# Built-in Windows programs often abused to run commands/scripts (living-off-the-land binaries)
$ScriptHosts          = @('cmd.exe', 'powershell.exe', 'pwsh.exe', 'wscript.exe', 'cscript.exe', 'mshta.exe', 'rundll32.exe', 'regsvr32.exe')

# Wildcard patterns for user-writable or unusual locations (matched with -like, so case-insensitive)
$SuspiciousPathGlobs  = @('*\Users\*', '*\ProgramData\*', '*\Temp\*', '*\AppData\*', '*\$Recycle.Bin\*', '\\*')

# Cache of "file path -> signature status" so each binary is only verified once
$script:SignatureCache = @{}

# Build the combined allowlist from the command-line list and/or the allowlist file
$excludePatterns = @()
if ($ExcludeService) { $excludePatterns += $ExcludeService }
if ($ExcludeFile) {
    # Read the file, trim whitespace, and drop blank lines and '#' comment lines
    $excludePatterns += Get-Content -LiteralPath $ExcludeFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

# =================================================================================================
# Helper functions
# =================================================================================================

# Returns $true if the service name matches any allowlist pattern (wildcards supported)
function Test-Excluded([string]$Name) {
    foreach ($pattern in $excludePatterns) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Creates one "indicator" record: a human-readable description plus how much it adds to the score
function New-Hit([string]$Text, [int]$Weight) {
    [pscustomobject]@{ Text = $Text; Weight = $Weight }
}

# Returns $true if the path matches any of the suspicious location patterns above
function Test-SuspiciousPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    foreach ($glob in $SuspiciousPathGlobs) {
        if ($Path -like $glob) { return $true }
    }
    return $false
}

# Returns the signature status as a string; cached because many services share one binary (e.g. svchost.exe)
# Possible results: 'Valid', 'NotSigned', 'HashMismatch', 'NotTrusted', etc. (from Get-AuthenticodeSignature),
# plus 'Missing' (file not found) and 'Error' (the check itself failed)
function Get-SignatureStatus([string]$Path) {
    # Fast path: we've already checked this file
    if ($script:SignatureCache.ContainsKey($Path)) { return $script:SignatureCache[$Path] }

    # A service pointing at a file that doesn't exist is worth knowing about
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $status = 'Missing'
    }
    else {
        try {
            # -LiteralPath avoids wildcard interpretation of characters like [ and ]
            # -ErrorAction Stop turns non-terminating errors into ones the catch block can see
            $status = (Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop).Status.ToString()
        }
        catch {
            $status = 'Error'
        }
    }

    # Remember the result for next time
    $script:SignatureCache[$Path] = $status
    return $status
}

# Calculates Shannon entropy (in bits per character) of a string.
# Higher values mean the characters look more random; used to spot randomly generated names.
function Get-Entropy([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return 0.0 }

    # Count how many times each character appears
    $freq = @{}
    foreach ($c in $Text.ToCharArray()) { $freq[$c]++ }

    # Entropy = -sum( p * log2(p) ) over every distinct character, where p is its frequency
    $entropy = 0.0
    foreach ($count in $freq.Values) {
        $p = $count / $Text.Length
        $entropy -= $p * [Math]::Log($p, 2)
    }
    return $entropy
}

# Service names only (display names are natural-language and almost always "high entropy").
# Strips the per-user suffix Windows adds (e.g. CDPUserSvc_3b7d9) and ignores short names.
function Test-HighEntropyName([string]$Name) {
    # Remove a trailing "_<4-8 hex chars>" suffix so per-user service instances aren't penalized
    $core = $Name -replace '_[0-9a-f]{4,8}$', ''

    # Skip short names and names containing whitespace (i.e. readable phrases)
    if ($core.Length -lt 8 -or $core -match '\s') { return $false }

    $entropy = Get-Entropy $core

    # Entropy can never exceed log2(length), so a 3.5 threshold is only reachable by names of 12+ characters
    if ($core.Length -ge 12) { return ($entropy -gt 3.5) }

    # 8-11 characters: entropy alone can't separate random names from legitimate ones
    # (e.g. 'EventSystem' scores ~3.1), so also require a mix of letters and digits.
    # 2.9 means "nearly every character is unique". This is a heuristic - tune it against your environment.
    $hasLetter = $core -match '[a-z]'     # -match is case-insensitive, so this covers A-Z too
    $hasDigit  = $core -match '\d'
    return ($hasLetter -and $hasDigit -and $entropy -ge 2.9)
}

# Windows will launch "C:\Foo\bar" as "C:\Foo\bar.exe" when a service path has no extension.
# Mimic that: if the path has no extension and the .exe version exists, return that instead.
function Resolve-ExeExtension([string]$Path) {
    if ($Path -notmatch '\.[^.\\/]+$' -and (Test-Path -LiteralPath "$Path.exe" -PathType Leaf)) {
        return "$Path.exe"
    }
    return $Path
}

# Extract the executable from a service command line
# e.g. '"C:\Program Files\App\svc.exe" -k group'  ->  'C:\Program Files\App\svc.exe'
function Get-ServiceExecutablePath([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }

    # Resolve any %VARIABLES% and trim surrounding whitespace
    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())

    # Case 1: path is quoted -> take everything between the first pair of quotes
    if ($expanded -match '^"([^"]+)"') { return Resolve-ExeExtension $Matches[1] }

    # Case 2: unquoted -> take everything up to the first known extension that is followed by a space or end of string
    # (the lazy .+? lets this work even when the path itself contains spaces)
    if ($expanded -match '^(.+?\.(?:exe|com|bat|cmd|vbs|js|scr|ps1))(?:\s|$)') { return $Matches[1] }

    # Fallback: first whitespace-delimited token, with ".exe" added if that's what Windows would run
    return Resolve-ExeExtension (($expanded -split '\s+', 2)[0])
}

# =================================================================================================
# Step 1: Collect services
# =================================================================================================

# Query Win32_Service through CIM; by default ask only for running services (filtered at the source)
$cimArgs = @{ ClassName = 'Win32_Service' }
if (-not $IncludeStopped) { $cimArgs.Filter = "State = 'Running'" }
$services = Get-CimInstance @cimArgs

# =================================================================================================
# Step 2: Analyze each service
# =================================================================================================

# Anything the loop outputs (one object per flagged service) is collected into $results
$results = foreach ($svc in $services) {
    $hits = [System.Collections.Generic.List[object]]::new()   # indicators found for this service
    $rawPath = [string]$svc.PathName                           # full command line as stored in the service
    $exe = Get-ServiceExecutablePath $rawPath                  # just the executable portion

    # Allowlist: skip this service entirely only if ALL of these hold:
    #   - we found its executable (a null path would break the signature check)
    #   - its name matches the allowlist
    #   - its binary has a valid signature (stops a malicious service hiding behind an allowlisted name)
    #   - it is not running from a suspicious location (a validly signed binary can still be copied somewhere bad)
    if ($exe -and
        (Test-Excluded $svc.Name) -and
        ((Get-SignatureStatus $exe) -eq 'Valid') -and
        -not (Test-SuspiciousPath $exe)) { continue }

    # --- Checks based on the executable ---
    if (-not $exe) {
        $hits.Add((New-Hit 'Could not determine executable path' 2))
    }
    else {
        $leaf = ($exe -split '[\\/]')[-1]                                      # file name only, e.g. svchost.exe
        $ext  = if ($leaf -match '(\.[^.]+)$') { $Matches[1] } else { '' }     # extension, e.g. .exe (-contains below ignores case)

        if (Test-SuspiciousPath $exe)             { $hits.Add((New-Hit 'Runs from a potentially suspicious path' 2)) }
        if ($SuspiciousExtensions -contains $ext) { $hits.Add((New-Hit "Suspicious file extension ($ext)" 3)) }
        if ($ScriptHosts -contains $leaf)         { $hits.Add((New-Hit "Launches script host / LOLBin ($leaf)" 3)) }

        # Anything other than a valid signature is suspicious; a hash mismatch (file modified after signing) is the worst.
        # 'Missing' and 'Error' score lower because they may be extraction/permission problems rather than tampering.
        $sig = Get-SignatureStatus $exe
        if ($sig -ne 'Valid') {
            $weight = switch ($sig) {
                'HashMismatch' { 5 }
                'Missing'      { 2 }
                'Error'        { 2 }
                default        { 3 }   # NotSigned, NotTrusted, UnknownError, etc.
            }
            $hits.Add((New-Hit "Signature status: $sig" $weight))
        }

        # Unquoted path with spaces: a classic privilege-escalation weakness (Windows may run a shorter, attacker-placed path)
        if (-not $SkipExtraChecks -and $rawPath -notmatch '^\s*"' -and $exe -match '\s') {
            $hits.Add((New-Hit 'Unquoted executable path containing spaces' 1))
        }
    }

    # --- Checks based on service metadata (low weight: common for legitimate services too) ---
    # LocalSystem can be reported as 'LocalSystem', '.\LocalSystem' or 'NT AUTHORITY\SYSTEM'
    if ($svc.StartName -match '^(\.\\)?LocalSystem$|^NT AUTHORITY\\SYSTEM$') { $hits.Add((New-Hit 'Runs as LocalSystem' 1)) }
    if ([string]::IsNullOrWhiteSpace($svc.Description))    { $hits.Add((New-Hit 'No description provided' 1)) }

    # --- Name-based checks (noisier, so they can be turned off with -SkipExtraChecks) ---
    if (-not $SkipExtraChecks) {
        if ($svc.Name.Length -le 5)                        { $hits.Add((New-Hit 'Very short service name' 1)) }
        if (([string]$svc.DisplayName).Length -le 5)       { $hits.Add((New-Hit 'Very short display name' 1)) }
        if (Test-HighEntropyName $svc.Name)                { $hits.Add((New-Hit 'High-entropy service name' 2)) }
    }

    # Add up the weights; only services meeting the threshold are emitted into $results
    # The [int] cast turns a $null sum (no indicators found) into 0 so the comparison below is reliable
    $score = [int](($hits | Measure-Object -Property Weight -Sum).Sum)
    if ($score -ge $MinScore) {
        [pscustomobject]@{
            Score       = $score
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            State       = $svc.State
            StartMode   = $svc.StartMode
            StartName   = $svc.StartName
            Description = $svc.Description
            PathName    = $rawPath
            Indicators  = ($hits | ForEach-Object Text) -join '; '   # flat text version, used for the CSV
            HitList     = $hits                                      # full list, used for the on-screen report
        }
    }
}

# Wrap in @() so $results is always an array (even for 0 or 1 results), then list highest scores first
$results = @($results | Sort-Object Score -Descending)

# =================================================================================================
# Step 3: Report
# =================================================================================================
if ($results.Count -gt 0) {
    Write-Host "Potentially suspicious services detected: $($results.Count)" -ForegroundColor Yellow
    Write-Host ('-' * 50)

    foreach ($r in $results) {
        # Summary line, then description and path, then one bullet per indicator
        Write-Host "[RISK SCORE: $($r.Score)] Name: $($r.Name) - Display Name: $($r.DisplayName) - State: $($r.State)"
        Write-Host "    Description: $($r.Description)"
        Write-Host "    Binary Path: $($r.PathName)"
        foreach ($h in $r.HitList) { Write-Host "`t- $($h.Text)" }
        Write-Host ''
    }

    # Optional CSV export (HitList is dropped because it doesn't flatten well; Indicators has the same info as text)
    # -Encoding UTF8 prevents non-ASCII characters in descriptions being mangled (Windows PowerShell 5.1 defaults to ASCII)
    if ($CsvPath) {
        $results | Select-Object * -ExcludeProperty HitList | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported to $CsvPath"
    }
}
else {
    Write-Host 'No potentially suspicious services detected.'
}

# Optionally hand the full result objects back to the caller (Write-Host output above can't be captured)
if ($PassThru) { $results }