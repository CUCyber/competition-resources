#Requires -Version 5.1
<#
.SYNOPSIS
    Lightweight PII file finder. Output: the full path of every file that appears to contain PII.

.DESCRIPTION
    Looks for SSNs, phone numbers, street addresses and credit card numbers (Luhn-checked) in
    plain-text-style files. A file is reported as soon as ONE match is found (then scanning of that
    file stops), and each file is reported at most once.

    Output streams
      * Success stream : one file path per line, nothing else (no banners, progress or summary).
      * Error stream   : access failures and similar, as non-terminating errors ("Kind: path - message").
                         The script never throws on unreadable files/folders; it keeps going.

    Default locations (when -Path is omitted)
      * Every user profile (found via the registry) plus Public - whole tree except AppData and
        developer/cache folders - plus the Outlook attachment caches inside AppData.
      * Every top-level folder on the system drive except OS/program folders.
      * The system drive's Recycle Bin.
    C:\WinMaster is always excluded (see $excludePaths below).

    What this version leaves out compared with the heavy one: Office/ZIP documents, email/DOB/
    driver's-license/passport patterns, other drives and shares, value masking, line numbers,
    progress/summary output.

.PARAMETER Path
    Folders to scan instead of the default locations.
.PARAMETER Threads
    Worker threads. Default: CPU cores, clamped to 2..8.

.EXAMPLE
    .\Find-PII-Light.ps1 | Out-File C:\WinMaster\pii-files.txt
.EXAMPLE
    .\Find-PII-Light.ps1 -Path D:\Exports -ErrorVariable scanErrors
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [ValidateRange(1, 64)][int]$Threads = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount))
)

# Errors must be reported, never allowed to terminate the run (even if the caller set 'Stop').
$ErrorActionPreference = 'Continue'

# ---------------- settings (edit here) ----------------
$excludePaths = @('C:\WinMaster')          # these folders (and everything under them) are never scanned
$maxFileMB    = 100                        # larger files are skipped
$textExt = '.txt', '.csv', '.tsv', '.log', '.json', '.xml', '.html', '.htm', '.sql', '.md', '.rtf', '.eml', '.vcf', '.dat', '.bak'
# Folder NAMES skipped anywhere: AppData plus dev tooling/caches (huge, rarely hold personal data).
$noiseFolders = @('AppData', 'node_modules', '.git', '.svn', '__pycache__', '.cache', '.nuget', '.npm', '.vscode', '.gradle', '.m2')
# Top-level system-drive folders that are OS/program data, never user data.
$osFolders = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Documents and Settings', 'Recovery',
    'PerfLogs', 'System Volume Information', '$Recycle.Bin', 'Config.Msi', 'MSOCache', 'Boot', 'Intel', 'AMD', 'NVIDIA',
    'Drivers', '$WinREAgent', '$SysReset', '$Windows.~BT', '$Windows.~WS')

# =====================================================================================
#  SCAN ENGINE (C#, C# 5 syntax so Windows PowerShell 5.1's compiler accepts it)
# =====================================================================================
$engineSource = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace PiiEngine {

public sealed class PiiScanError { public string Path, Kind, Message; }

public sealed class PiiScanner
{
    // Files are regex-scanned in 256K-char chunks that overlap by 1K chars, so a match straddling a chunk
    // edge is still seen whole in the next chunk.
    private const int ChunkChars = 1 << 18, Overlap = 1024, HeadBytes = 4096, MaxQueuedErrors = 5000;
    private const long MinFileBytes = 6;   // shortest possible hit ("1 A St")
    // Cloud-sync placeholder flags: reading such a file would make OneDrive etc. download it.
    private const FileAttributes CloudFlags =
        FileAttributes.Offline | (FileAttributes)0x00040000 /*RECALL_ON_OPEN*/ | (FileAttributes)0x00400000 /*RECALL_ON_DATA_ACCESS*/;

    // ---------- configuration (set before Start) ----------
    public string[] Extensions, ExcludeNames, ExcludePaths;
    public long MaxFileBytes = 100L * 1024 * 1024;
    public int ThreadCount = 4;

    // ---------- output ----------
    public readonly ConcurrentQueue<string> Hits = new ConcurrentQueue<string>();           // paths of files with PII
    public readonly ConcurrentQueue<PiiScanError> Errors = new ConcurrentQueue<PiiScanError>();
    private long errorCount;
    public long ErrorCount { get { return Interlocked.Read(ref errorCount); } }

    // ---------- patterns (the first LuhnFrom patterns need no checksum; the rest are card numbers) ----------
    private const int LuhnFrom = 3;
    private static readonly string[] Patterns = {
        // SSN: valid area/group/serial ranges, same separator twice, no digits/hyphens glued on.
        @"(?<![\d-])(?!000|666|9\d\d)\d{3}(?<s>[- .])(?!00)\d{2}\k<s>(?!0000)\d{4}(?![\d-])",
        // Phone (NANP): area code and exchange start 2-9; (555)123-4567, +1 555.123.4567 ...
        @"(?<![\d-])(?:\+?1[-. ]?)?(?:\([2-9]\d{2}\)|[2-9]\d{2})[-. ]?[2-9]\d{2}[-. ]\d{4}(?![\d-])",
        // Street address: house number + capitalised street words + street suffix. [ \t] (not \s) keeps it on one line.
        @"(?<![\w#$.,/-])\d{1,6}(?:[ \t]+(?:[NSEW]|[NS][EW])\.?)?[ \t]+(?:(?:[A-Z][A-Za-z'.-]*|\d{1,3}(?:st|nd|rd|th))[ \t]+){1,4}?(?i:Avenue|Ave|Street|St|Boulevard|Blvd|Road|Rd|Drive|Dr|Court|Ct|Highway|Hwy|Lane|Ln|Way|Place|Pl|Circle|Cir|Parkway|Pkwy|Terrace|Ter|Trail|Trl)\b\.?",
        // Credit cards (Visa/MC/Discover/JCB 16 digits, Amex 15), consistent separator, Luhn-checked in code.
        @"(?<![\d-])(?:4\d{3}|5[1-5]\d{2}|2[2-7]\d{2}|6011|65\d{2}|35\d{2})(?<s>[- ]?)\d{4}\k<s>\d{4}\k<s>\d{4}(?![\d-])",
        @"(?<![\d-])3[47]\d{2}(?<s>[- ]?)\d{6}\k<s>\d{5}(?![\d-])"
    };

    // ---------- internals ----------
    private sealed class Item { public string Path; public bool IsDir; }
    private sealed class WorkerCtx { public char[] Buf = new char[ChunkChars + Overlap]; public byte[] Head = new byte[HeadBytes]; }

    private static readonly char[] Digits = "0123456789".ToCharArray();
    private static readonly char Sep = Path.DirectorySeparatorChar;

    // Shared work list: folders to expand and files to scan. LIFO keeps the walk depth-first (small memory);
    // `pending` counts items not yet fully processed, so workers know when everything is finished.
    private readonly ConcurrentStack<Item> stack = new ConcurrentStack<Item>();
    private long pending;
    private volatile bool cancel;
    private Thread[] workers;
    private Regex[] rx;
    private HashSet<string> extSet, nameSet;
    private string[] excluded;

    // ---------- Win32: tell real links from cloud reparse points ----------
    // OneDrive folders carry the ReparsePoint attribute but are NOT links; only symlinks/junctions are skipped.
    // The reparse tag lives in WIN32_FIND_DATA.dwReserved0.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct FindData
    {
        public uint dwFileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftCreationTime, ftLastAccessTime, ftLastWriteTime;
        public uint nFileSizeHigh, nFileSizeLow, dwReserved0, dwReserved1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string cFileName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string cAlternateFileName;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindFirstFile(string name, out FindData data);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FindClose(IntPtr handle);

    private static bool IsLink(string path)
    {
        try
        {
            FindData d;
            IntPtr h = FindFirstFile(path, out d);
            if (h == new IntPtr(-1)) return true;
            FindClose(h);
            return d.dwReserved0 == 0xA000000C /*SYMLINK*/ || d.dwReserved0 == 0xA0000003 /*junction*/;
        }
        catch (Exception) { return true; }   // can't classify -> skip it (safe)
    }

    // ---------- setup ----------
    private static HashSet<string> ToSet(string[] items)
    {
        HashSet<string> s = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (items != null) { foreach (string i in items) s.Add(i); }
        return s;
    }

    // True if path is, or lies inside, an excluded folder.
    private bool Excluded(string path)
    {
        foreach (string e in excluded)
        {
            if (path.Equals(e, StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith(e + Sep, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    public void Start(string[] roots)
    {
        rx = new Regex[Patterns.Length];
        for (int i = 0; i < rx.Length; i++)   // timeout = guard against pathological backtracking
            rx[i] = new Regex(Patterns[i], RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.ExplicitCapture, TimeSpan.FromSeconds(15));

        extSet = ToSet(Extensions);
        nameSet = ToSet(ExcludeNames);
        List<string> ex = new List<string>();
        if (ExcludePaths != null) { foreach (string p in ExcludePaths) ex.Add(System.IO.Path.GetFullPath(p).TrimEnd(Sep)); }
        excluded = ex.ToArray();

        HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string r in roots)
        {
            string p = System.IO.Path.GetFullPath(r);
            if (Excluded(p.TrimEnd(Sep)) || !seen.Add(p)) continue;   // skip excluded and duplicate roots
            Interlocked.Increment(ref pending);
            stack.Push(new Item { Path = p, IsDir = true });
        }

        workers = new Thread[Math.Max(1, ThreadCount)];
        for (int i = 0; i < workers.Length; i++)
        {
            workers[i] = new Thread(WorkerLoop);
            workers[i].IsBackground = true;                       // never keep the host process alive
            workers[i].Priority = ThreadPriority.BelowNormal;     // stay out of the user's way
            workers[i].Start();
        }
    }

    public bool IsRunning
    {
        get { if (workers == null) return false; foreach (Thread t in workers) { if (t.IsAlive) return true; } return false; }
    }
    public void Cancel() { cancel = true; }

    private void RecordError(string path, Exception ex)
    {
        if (Interlocked.Increment(ref errorCount) <= MaxQueuedErrors)
            Errors.Enqueue(new PiiScanError { Path = path, Kind = ex.GetType().Name, Message = ex.Message });
    }

    // ---------- worker ----------
    private void WorkerLoop()
    {
        WorkerCtx w = new WorkerCtx();
        while (!cancel)
        {
            Item it;
            if (stack.TryPop(out it))
            {
                try { if (it.IsDir) ExpandDir(it.Path); else ScanFile(it.Path, w); }
                catch (Exception ex) { RecordError(it.Path, ex); }   // one bad item must never stop the scan
                finally { Interlocked.Decrement(ref pending); }      // children were already counted in ExpandDir
            }
            else
            {
                if (Interlocked.Read(ref pending) == 0) break;        // nothing queued and nobody producing: done
                Thread.Sleep(1);                                      // others are still expanding folders
            }
        }
    }

    // List one folder: queue sub-folders and any file worth scanning. Cheap rejects (extension, size,
    // cloud-only, excluded) are decided from the directory listing, before a file is ever opened.
    private void ExpandDir(string dir)
    {
        List<Item> batch = new List<Item>();
        try
        {
            foreach (FileSystemInfo fsi in new DirectoryInfo(dir).EnumerateFileSystemInfos())
            {
                if (cancel) break;
                FileAttributes a = fsi.Attributes;
                if ((a & FileAttributes.Directory) != 0)
                {
                    if (nameSet.Contains(fsi.Name) || Excluded(fsi.FullName)) continue;
                    if ((a & FileAttributes.ReparsePoint) != 0 && IsLink(fsi.FullName)) continue;   // no symlink/junction loops
                    batch.Add(new Item { Path = fsi.FullName, IsDir = true });
                }
                else
                {
                    FileInfo fi = fsi as FileInfo;
                    if (fi == null || (a & CloudFlags) != 0 || !extSet.Contains(fi.Extension)) continue;
                    long len = fi.Length;
                    if (len >= MinFileBytes && len <= MaxFileBytes) batch.Add(new Item { Path = fi.FullName });
                }
            }
        }
        finally
        {
            // Queue whatever was listed even if enumeration threw part-way (e.g. access denied). `pending` is
            // raised BEFORE the push so it can never read 0 while work still exists.
            if (batch.Count > 0) { Interlocked.Add(ref pending, batch.Count); stack.PushRange(batch.ToArray()); }
        }
    }

    // ---------- file scanning ----------
    private void ScanFile(string path, WorkerCtx w)
    {
        // FileShare.ReadWrite|Delete lets us read files other programs have open.
        using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 4096, FileOptions.SequentialScan))
        {
            int n = 0, r;   // sniff the first 4 KB: choose the text encoding, or reject the file as binary
            while (n < HeadBytes && (r = fs.Read(w.Head, n, HeadBytes - n)) > 0) n += r;
            bool binary;
            Encoding enc = Sniff(w.Head, n, out binary);
            if (n == 0 || binary) return;
            fs.Position = 0;
            using (StreamReader sr = new StreamReader(fs, enc, true, 65536))   // `true` also honours a BOM
            {
                if (ScanReader(sr, w.Buf)) Hits.Enqueue(path);
            }
        }
    }

    // BOM => that encoding. Otherwise NUL bytes decide: all on one byte parity = BOM-less UTF-16 (what
    // PowerShell 5.1's Out-File writes); scattered NULs or many control bytes = binary.
    private static Encoding Sniff(byte[] h, int n, out bool binary)
    {
        binary = false;
        if (n >= 3 && h[0] == 0xEF && h[1] == 0xBB && h[2] == 0xBF) return Encoding.UTF8;
        if (n >= 4 && h[0] == 0xFF && h[1] == 0xFE && h[2] == 0 && h[3] == 0) return Encoding.UTF32;
        if (n >= 2 && h[0] == 0xFF && h[1] == 0xFE) return Encoding.Unicode;
        if (n >= 2 && h[0] == 0xFE && h[1] == 0xFF) return Encoding.BigEndianUnicode;
        int nul = 0, even = 0, ctrl = 0;
        for (int i = 0; i < n; i++)
        {
            byte b = h[i];
            if (b == 0) { nul++; if ((i & 1) == 0) even++; }
            else if (b < 9 || (b > 13 && b < 32 && b != 27)) ctrl++;
        }
        if (nul > 0)
        {
            if (nul * 4 >= n && even * 10 <= nul) return Encoding.Unicode;               // NULs on odd bytes
            if (nul * 4 >= n && even * 10 >= nul * 9) return Encoding.BigEndianUnicode;   // NULs on even bytes
            binary = true; return Encoding.UTF8;
        }
        if (ctrl * 10 > n) binary = true;
        return new UTF8Encoding(false);   // invalid bytes become U+FFFD instead of throwing
    }

    // Streams the file in overlapping chunks; stops at the first confirmed hit. A match counts only if it
    // STARTS before the overlap zone; ones starting inside it are re-tested at the head of the next chunk.
    private bool ScanReader(TextReader reader, char[] buf)
    {
        int carry = 0;
        bool eof = false;
        while (!eof && !cancel)
        {
            int read = reader.ReadBlock(buf, carry, ChunkChars);
            eof = read < ChunkChars;
            int len = carry + read;
            if (len == 0) break;
            int limit = eof ? len : len - Overlap;
            if (Found(new string(buf, 0, len), limit)) return true;
            carry = len - limit;
            Array.Copy(buf, limit, buf, 0, carry);
        }
        return false;
    }

    private bool Found(string text, int limit)
    {
        if (text.IndexOfAny(Digits) < 0) return false;   // every pattern needs a digit: cheap early exit
        for (int i = 0; i < rx.Length; i++)
        {
            for (Match m = rx[i].Match(text); m.Success && m.Index < limit; m = m.NextMatch())
                if (i < LuhnFrom || Luhn(m.Value)) return true;
        }
        return false;
    }

    // Luhn checksum: weeds out random 16-digit numbers that merely look like card numbers.
    private static bool Luhn(string s)
    {
        int sum = 0, n = 0; bool alt = false;
        for (int i = s.Length - 1; i >= 0; i--)
        {
            if (s[i] < '0' || s[i] > '9') continue;
            int d = s[i] - '0';
            if (alt) { d *= 2; if (d > 9) d -= 9; }
            sum += d; alt = !alt; n++;
        }
        return n >= 13 && sum % 10 == 0;
    }
}

} // namespace
'@

# A compiled type can't be unloaded from a PowerShell session, so the engine lives in a namespace named after
# a hash of its own source: re-running the same script reuses it, while an edited/older copy gets a fresh one.
$hash = ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($engineSource)) |
    ForEach-Object { $_.ToString('x2') }) -join ''
$engineNs = 'PiiEngineLight_' + $hash.Substring(0, 12)
$scannerType = "$engineNs.PiiScanner"
try {
    if (-not ($scannerType -as [type])) {
        $compile = @{ TypeDefinition = $engineSource.Replace('namespace PiiEngine {', "namespace $engineNs {"); Language = 'CSharp' }
        if ($PSVersionTable.PSEdition -eq 'Desktop') { $compile.ReferencedAssemblies = 'System.Core' }   # 5.1 only
        Add-Type @compile
    }
} catch {
    Write-Error "Engine failed to compile: $($_.Exception.Message)"
    return
}

# =====================================================================================
#  SCAN LOCATIONS
# =====================================================================================
function Get-DefaultScanRoot {
    $roots = New-Object System.Collections.Generic.List[string]
    $sys = $env:SystemDrive

    # User profiles from the registry (local, domain S-1-5-21, Entra ID S-1-12-1) - correct even when profiles
    # live outside C:\Users. Fall back to listing C:\Users if the registry yields nothing.
    $profiles = @()
    try {
        $pl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $profiles = @(Get-ItemProperty "$pl\S-1-5-21-*", "$pl\S-1-12-1-*" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProfileImagePath } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_.ProfileImagePath) })
    } catch { }
    if (-not $profiles) {
        $profiles = @(Get-ChildItem "$sys\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
    }
    $profiles += $env:PUBLIC

    foreach ($p in $profiles) {
        if (-not $p) { continue }
        $roots.Add($p)                                                                   # whole profile (AppData pruned by name)
        $roots.Add("$p\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook")       # attachments opened from Outlook
        $roots.Add("$p\AppData\Local\Microsoft\Olk\Attachments")                         # same, new Outlook
    }

    # Top-level system-drive folders (C:\Data, C:\Exports ...) minus OS/program folders and links.
    Get-ChildItem "$sys\" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $osFolders -and ([int]$_.Attributes -band 0x400) -eq 0 } |
        ForEach-Object { $roots.Add($_.FullName) }
    $roots.Add("$sys\`$Recycle.Bin")
    return $roots.ToArray()
}

# =====================================================================================
#  MAIN
# =====================================================================================
if ($Path) {
    $candidates = @($Path | ForEach-Object {
        if ($_ -match '[\*\?\[]') { Resolve-Path -Path $_ -ErrorAction SilentlyContinue | ForEach-Object ProviderPath } else { $_ }
    })
} else {
    $candidates = @(Get-DefaultScanRoot)
}
$roots = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique)
if ($Path) { $candidates | Where-Object { $_ -and ($roots -notcontains $_) } | ForEach-Object { Write-Error "Not a folder / not found: $_" } }
if ($roots.Count -eq 0) { Write-Error 'No valid folders to scan.'; return }

$scanner = New-Object $scannerType -Property @{
    Extensions    = [string[]]$textExt
    ExcludeNames  = [string[]]$noiseFolders
    ExcludePaths  = [string[]]$excludePaths
    MaxFileBytes  = [long]$maxFileMB * 1MB
    ThreadCount   = $Threads
}

# Moves finished results out of the engine. Hits go to the success stream (the script's ONLY normal output);
# errors go to the error stream. Bounded by the engine's error cap, with one note if errors were dropped.
$errorsShown = 0
function Receive-Result {
    $item = $null
    while ($scanner.Hits.TryDequeue([ref]$item)) { $item }
    $e = $null
    while ($scanner.Errors.TryDequeue([ref]$e)) {
        $script:errorsShown++
        Write-Error ("{0}: {1} - {2}" -f $e.Kind, $e.Path, $e.Message)
    }
}

try {
    $scanner.Start([string[]]$roots)
    do { Start-Sleep -Milliseconds 250; Receive-Result } while ($scanner.IsRunning)
    Receive-Result
    if ($scanner.ErrorCount -gt $errorsShown) { Write-Error ("{0} additional access errors were not listed." -f ($scanner.ErrorCount - $errorsShown)) }
}
finally {
    $scanner.Cancel()   # on Ctrl+C / stop: tell workers to wind down (no-op after a normal finish)
}