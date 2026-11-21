#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only PII discovery with timestamped console output and optional CSV/object output.
.DESCRIPTION
    Scans text, Office/OpenDocument XML, ZIP/GZIP members, and MIME email bodies/attachments.
    PDFs require an explicitly supplied pdftotext executable; no downloads or Office automation.
    Default roots: user profiles, selected Temp/Outlook caches, local shares, recycle bins,
    system-drive data folders AND loose root files. -Path accepts files, folders and wildcards.
    Other drives, all AppData/ProgramData, mapped drives, links and cloud hydration are opt-in.
    Detection is heuristic. Default Hits is one per type/file; -CountAll counts occurrences.
    Samples are partially masked unless -ShowValues; address street names remain visible.
    Each finding includes line/column, match reason, and an example-data note when applicable.
    -ShowValues also includes a short unmasked context excerpt. Treat that output as sensitive.
    Locations in extracted text are not source page numbers. Recycle Bin $I metadata is skipped;
    the corresponding $R content is scanned normally.
    XML extraction preserves split text runs; spreadsheet styles/shared-string references are not
    reconstructed as records. PDF OCR, legacy Office, PST/OST, databases, 7z/RAR, encrypted content,
    and full RTF interpretation are not supported. Skipped/partial work is included in the summary.
    C# types use a source-derived namespace. Helpers/preferences are scoped; no type-data updates,
    services, registry settings or source files are modified. Run with & or normally, not dot-source.
.PARAMETER Type
    SSN, Phone, Address, CreditCard, Email, DOB, DriversLicense, Passport, IBAN,
    BankAccount, RoutingNumber, TaxID. Account/ID patterns require labels where appropriate.
.PARAMETER AllTextFiles
    Try unknown extensions as text; binary/known unsupported formats are still skipped.
.PARAMETER IncludeUnlabelledNumbers
    Also match bare nine-digit SSNs and ten-digit NANP phones (lower confidence, more noise).
.PARAMETER PdfTextTool
    Full path to a trusted pdftotext executable. Conversion has time/output limits and private temp files.
.PARAMETER OutputPath
    CSV findings path; errors use <name>.errors.csv. Both files have headers even with no results.
    Existing reports are protected unless -Force is specified. Reports are excluded from scanning.
.PARAMETER PassThru
    Emit finding objects as they arrive. Console output remains unless -Quiet/-NoProgress is used.
.PARAMETER Quiet
    Suppress per-finding host lines. Timestamped start, summary and warnings remain visible.
.PARAMETER IncludeAppData
    Add each profile's whole AppData tree and ProgramData to the default roots.
.PARAMETER ExcludePath
    Exact files or directory trees to exclude (literal paths; environment variables supported).
.PARAMETER FollowLinks
    Follow Windows links with canonical-directory deduplication. Unresolvable targets are skipped.
.PARAMETER Force
    Permit replacement of explicitly named CSV reports. No effect on input-file permissions.
.EXAMPLE
    .\Find-PII-Heavy.ps1 -Path C:\Data,D:\Exports -OutputPath C:\WinMaster\pii.csv
.EXAMPLE
    .\Find-PII-Heavy.ps1 -IncludeOtherDrives -IncludeAppData -Threads 4 -Quiet
.EXAMPLE
    .\Find-PII-Heavy.ps1 -Path C:\Data -PassThru | Where-Object Type -eq SSN
.NOTES
    Windows PowerShell 5.1 or PowerShell 7. Explicit paths also support basic non-Windows testing.
    Resource limits are per file/container; adjust them deliberately for large collections.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [ValidateSet('SSN','Phone','Address','CreditCard','Email','DOB','DriversLicense','Passport','IBAN','BankAccount','RoutingNumber','TaxID')]
    [string[]]$Type = @('SSN','Phone','Address','CreditCard','Email','DOB','DriversLicense','Passport','IBAN','BankAccount','RoutingNumber','TaxID'),
    [string[]]$Extension,
    [switch]$AllTextFiles, [switch]$SkipOfficeDocs, [switch]$SkipArchives, [switch]$SkipShares,
    [switch]$IncludeAppData, [switch]$IncludeOtherDrives, [switch]$IncludeMappedDrives,
    [string[]]$ExcludeDirectory = @(), [string[]]$ExcludePath = @(), [switch]$NoDefaultExcludes,
    [switch]$FollowLinks, [switch]$IncludeCloudOnly, [switch]$IncludeUnlabelledNumbers,
    [ValidateRange(1,1048576)][int]$MaxFileSizeMB = 500,
    [ValidateRange(0,32)][int]$Threads = 0,
    [ValidateRange(1,256)][int]$MaxExtractedMB = 16,
    [ValidateRange(1,4096)][int]$MaxArchiveTotalMB = 128,
    [ValidateRange(0,8)][int]$MaxArchiveDepth = 2,
    [ValidateRange(1,100000)][int]$MaxArchiveEntries = 2000,
    [ValidateRange(1,30)][int]$RegexTimeoutSeconds = 2,
    [ValidateRange(1,600)][int]$PdfTimeoutSeconds = 60,
    [string]$PdfTextTool,
    [switch]$CountAll, [switch]$ShowValues, [string]$OutputPath,
    [switch]$PassThru, [switch]$Quiet, [switch]$NoProgress, [switch]$Force
)

# Child scope prevents helper functions and preference changes from leaking to callers.
& {
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$engineSource = @'

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Xml;
using Microsoft.Win32.SafeHandles;

namespace PiiHeavyEngine {
public enum Stat { Dirs, Seen, Attempted, Files, Partial, Failed, Office, Archives, Pdf, Bytes, Findings,
    Errors, SkipExt, SkipBinary, SkipSize, SkipCloud, SkipLink, SkipExcluded, SkipDuplicate, SkipUnsupported, SkipEmpty, SkipMetadata }
public sealed class Finding {
    public string Type, Confidence, File, Location, Sample, ScanStatus, Reason, ReviewNote, Context;
    public long Hits, Size, Line, Column, MatchLength; public DateTime Timestamp, Modified;
}
public sealed class ScanError { public DateTime Timestamp; public string Path, Kind, Message; }
public sealed class Scanner {
    const int ChunkChars = 262144, Overlap = 1024, HeadBytes = 8192, MaxErrors = 5000;
    const FileAttributes CloudFlags = FileAttributes.Offline | (FileAttributes)0x40000 | (FileAttributes)0x400000;
    public string[] Types, Extensions, ExcludeDirectories, ExcludePaths;
    public bool ScanOffice = true, ScanArchives = true, AllTextFiles, FollowLinks, IncludeCloudOnly;
    public bool CountAll, ShowValues, IncludeUnlabelledNumbers;
    public long MaxFileBytes = 500L * 1024 * 1024, MaxExtractBytes = 16L * 1024 * 1024, MaxArchiveBytes = 128L * 1024 * 1024;
    public int ThreadCount = 4, MaxDepth = 2, MaxEntries = 2000, RegexSeconds = 2, PdfSeconds = 60;
    public string PdfTool;
    public readonly ConcurrentQueue<Finding> Findings = new ConcurrentQueue<Finding>();
    public readonly ConcurrentQueue<ScanError> Errors = new ConcurrentQueue<ScanError>();
    readonly long[] stats = new long[Enum.GetValues(typeof(Stat)).Length];
    public long Get(Stat s) { return Interlocked.Read(ref stats[(int)s]); }
    void Inc(Stat s, long n = 1) { Interlocked.Add(ref stats[(int)s], n); }
    public ScanError[] GetErrors() { return Errors.ToArray(); }
    static readonly bool Windows = Environment.OSVersion.Platform == PlatformID.Win32NT;
    static readonly StringComparer PathComparer = Windows ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    static readonly StringComparison PathComparison = Windows ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
    static readonly char[] Digits = "0123456789".ToCharArray();
    static readonly string[] OfficeExt = { ".docx", ".docm", ".dotx", ".dotm", ".xlsx", ".xlsm", ".xltx", ".xltm", ".pptx", ".pptm", ".potx", ".ppsx", ".odt", ".ods", ".odp", ".ott", ".ots", ".otp" };
    static readonly string[] Unsupported = { ".doc", ".xls", ".ppt", ".xlsb", ".pst", ".ost", ".msg", ".7z", ".rar", ".db", ".sqlite", ".mdb", ".accdb", ".png", ".jpg", ".jpeg", ".tif", ".tiff" };
    // type, expression, validation, confidence. All match lengths are bounded below the chunk overlap.
    static readonly string[][] Defs = {
        new[]{"SSN", @"\b(?:ssn|social[ \t]+security(?:[ \t]+(?:no|number))?)\b[\""' :#=\t.-]{0,15}(?<v>(?!000|666|9)[0-9]{3}(?<s>[- .]?)(?!00)[0-9]{2}\k<s>(?!0000)[0-9]{4})(?![0-9])", "", "High"},
        new[]{"SSN", @"(?<![0-9-])(?<v>(?!000|666|9)[0-9]{3}(?<s>[- .])(?!00)[0-9]{2}\k<s>(?!0000)[0-9]{4})(?![0-9-])", "", "Medium"},
        new[]{"SSN", @"(?<![A-Za-z0-9])(?<v>(?!000|666|9)[0-9]{3}(?!00)[0-9]{2}(?!0000)[0-9]{4})(?![A-Za-z0-9])", "Loose", "Low"},
        new[]{"Phone", @"\b(?:phone|tel(?:ephone)?|mobile|cell|fax)\b[\""' :#=\t.-]{0,12}(?<v>\+?[0-9](?:[0-9() .-]{5,26})[0-9])(?=$|[^0-9])", "Phone", "Medium"},
        new[]{"Phone", @"(?<![0-9])(?<v>(?:\+?1[-. ]?)?(?:\([2-9][0-9]{2}\)[-. ]?|[2-9][0-9]{2}[-. ])[2-9][0-9]{2}[-. ][0-9]{4})(?![0-9])", "Phone", "Medium"},
        new[]{"Phone", @"(?<![A-Za-z0-9])(?<v>[2-9][0-9]{2}[2-9][0-9]{6})(?![A-Za-z0-9])", "Loose", "Low"},
        new[]{"Address", @"(?<![\w#$.,/-])(?<v>[0-9]{1,6}[ \t]+(?:(?:[\p{L}][\p{L}'.-]{0,39}|[0-9]{1,3}(?:st|nd|rd|th))[ \t]+){1,5}?(?:avenue|ave|street|st|boulevard|blvd|road|rd|drive|dr|court|ct|highway|hwy|lane|ln|way|place|pl|circle|cir|parkway|pkwy|terrace|ter|trail|trl)\b\.?)", "", "Medium"},
        new[]{"Address", @"\b(?<v>P\.?[ \t]*O\.?[ \t]+Box[ \t]+[A-Z0-9-]{1,12})\b", "", "Medium"},
        new[]{"CreditCard", @"(?<![0-9])(?<v>[0-9](?:[ -]?[0-9]){12,18})(?![ -]?[0-9])", "Card", "High"},
        new[]{"Email", @"(?<![\w.+%-])(?<v>[A-Z0-9._%+-]{1,64}@(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.){1,8}[A-Z]{2,63})\b", "Email", "Medium"},
        new[]{"DOB", @"\b(?:d\.?o\.?b\.?|date[ \t]+of[ \t]+birth|birth[ \t]*date|birthday|born(?:[ \t]+on)?)(?![A-Z])[\""' :#=\t]{0,12}(?<v>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}|[0-9]{1,2}[/.-][0-9]{1,2}[/.-](?:[0-9]{4}|[0-9]{2})|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]{0,6}\.?[ \t]+[0-9]{1,2}(?:st|nd|rd|th)?,?[ \t]+[0-9]{4})(?![0-9])", "Date", "High"},
        new[]{"DriversLicense", @"\b(?:driver['’]?s?[ \t]+licen[sc]e|DLN?)[ \t]*(?:(?:no\.?|num(?:ber)?|#)[ \t]*)?[\""' :#=\t-]{0,8}(?<v>[A-Z0-9][A-Z0-9-]{4,17})(?![A-Z0-9-])", "ID", "Medium"},
        new[]{"Passport", @"\bpassport[ \t]*(?:(?:no\.?|num(?:ber)?|#)[ \t]*)?[\""' :#=\t-]{0,8}(?<v>[A-Z0-9]{6,12})(?![A-Z0-9])", "ID", "Medium"},
        new[]{"IBAN", @"\b(?<v>[A-Z]{2}[0-9]{2}(?:[ ]?[A-Z0-9]){11,30})\b", "IBAN", "High"},
        new[]{"BankAccount", @"\b(?:bank[ \t]+account|account[ \t]*(?:number|no\.?|#)|a/c)[\""' :#=\t-]{0,12}(?<v>[0-9](?:[ -]?[0-9]){5,17})(?![ -]?[0-9])", "", "Medium"},
        new[]{"RoutingNumber", @"\b(?:routing(?:[ \t]+(?:number|no\.?))?|ABA(?:[ \t]+routing)?)[\""' :#=\t-]{0,12}(?<v>[0-9]{9})(?![0-9])", "ABA", "High"},
        new[]{"TaxID", @"\b(?:EIN|employer[ \t]+identification(?:[ \t]+number)?)[\""' :#=\t-]{0,12}(?<v>[0-9]{2}-?[0-9]{7})(?![0-9])", "Nonzero", "Medium"}
    };
    sealed class Rule { public Regex Rx; public int Index; public string Check, Confidence, Reason; }
    sealed class Item { public string Path; public bool Dir; public long Size; public DateTime Modified; public int Kind; }
    sealed class State {
        public long[] Hits, Line, Column, MatchLength; public string[] Sample, Location, Confidence, Reason, ReviewNote, Context; public bool[] Done;
        public bool Incomplete, ReadAny, Skipped; public string Label; public long Budget; public int Entries;
        public State(int n, long budget) {
            Hits=new long[n]; Line=new long[n]; Column=new long[n]; MatchLength=new long[n];
            Sample=new string[n]; Location=new string[n]; Confidence=new string[n]; Reason=new string[n];
            ReviewNote=new string[n]; Context=new string[n]; Done=new bool[n]; Budget=budget;
        }
        public bool AllDone { get { foreach (bool b in Done) if (!b) return false; return true; } }
    }
    sealed class Worker { public char[] Buf = new char[ChunkChars + Overlap]; public byte[] Head = new byte[HeadBytes]; }
    readonly ConcurrentStack<Item> stack = new ConcurrentStack<Item>();
    readonly ConcurrentDictionary<string, byte> visited = new ConcurrentDictionary<string, byte>(PathComparer);
    long pending; volatile bool cancel; Thread[] workers; Rule[] rules; string[] names, excluded; string tempRoot;
    HashSet<string> extSet, officeSet, excludeSet, unsupportedSet;
    static HashSet<string> Set(IEnumerable<string> values) { return new HashSet<string>(values ?? new string[0], StringComparer.OrdinalIgnoreCase); }
    static string Full(string path) { string p=Path.GetFullPath(path); return p.Length>Path.GetPathRoot(p).Length ? p.TrimEnd(Path.DirectorySeparatorChar) : p; }
    bool Excluded(string path) {
        foreach(string p in excluded) if(path.Equals(p,PathComparison) || path.StartsWith(p.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,PathComparison)) return true;
        return false;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string p, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern uint GetFinalPathNameByHandleW(SafeFileHandle h, StringBuilder text, uint size, uint flags);
    static string Canonical(string path, bool dir) {
        using(SafeFileHandle h=CreateFileW(path,0,7,IntPtr.Zero,3,dir?0x02000000u:0u,IntPtr.Zero)) {
            if(h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            StringBuilder b=new StringBuilder(32768); uint n=GetFinalPathNameByHandleW(h,b,(uint)b.Capacity,0);
            if(n==0 || n>=b.Capacity) throw new IOException("Cannot resolve link target.");
            string p=b.ToString(); if(p.StartsWith(@"\\?\UNC\")) p=@"\\"+p.Substring(8); else if(p.StartsWith(@"\\?\")) p=p.Substring(4);
            return Full(p);
        }
    }
    void Error(string path, Exception ex) {
        long n=Interlocked.Increment(ref stats[(int)Stat.Errors]);
        if(n<=MaxErrors) Errors.Enqueue(new ScanError { Timestamp=DateTime.Now, Path=path, Kind=ex.GetType().Name, Message=ex.Message });
    }
    void Partial(State s,string path,string reason) { s.Incomplete=true; Error(path,new InvalidDataException(reason)); }
    static string MatchReason(string[] rule) {
        switch(rule[0]) {
            case "SSN": return rule[2]=="Loose"?"Unlabelled nine-digit SSN-like value.":rule[3]=="High"?"SSN label followed by a valid SSN digit pattern.":"SSN digit groups with matching separators.";
            case "Phone": return rule[2]=="Loose"?"Unlabelled ten-digit NANP phone-like value.":"Phone label or recognizable telephone-number formatting.";
            case "Address": return rule[1].Contains("Box")?"PO box address format.":"House number, street name and recognized street suffix.";
            case "CreditCard": return "Payment-card format and valid Luhn checksum.";
            case "Email": return "Email-address syntax.";
            case "DOB": return "Birth-date label followed by a valid, non-future date.";
            case "DriversLicense": return "Driver-license label followed by an identifier containing digits.";
            case "Passport": return "Passport label followed by an identifier containing digits.";
            case "IBAN": return "IBAN format and valid mod-97 checksum.";
            case "BankAccount": return "Bank/account-number label followed by a numeric identifier.";
            case "RoutingNumber": return "Routing-number label, ABA prefix and valid checksum.";
            default: return "EIN/employer-identification label followed by a tax-ID-like number.";
        }
    }
    void BuildRules() {
        HashSet<string> wanted=Set(Types); List<string> types=new List<string>(); List<Rule> list=new List<Rule>();
        foreach(string[] d in Defs) {
            if(!wanted.Contains(d[0]) || (d[2]=="Loose" && !IncludeUnlabelledNumbers)) continue;
            int i=types.IndexOf(d[0]); if(i<0) { i=types.Count; types.Add(d[0]); }
            list.Add(new Rule { Index=i, Check=d[2], Confidence=d[3], Reason=MatchReason(d), Rx=new Regex(d[1],RegexOptions.Compiled|RegexOptions.CultureInvariant|RegexOptions.IgnoreCase|RegexOptions.ExplicitCapture,TimeSpan.FromSeconds(RegexSeconds)) });
        }
        names=types.ToArray(); rules=list.ToArray(); if(names.Length==0) throw new ArgumentException("No enabled detection rules.");
    }
    int Kind(string ext) {
        if(officeSet.Contains(ext)) return ScanOffice?1:-2;
        if(ext.Equals(".zip",StringComparison.OrdinalIgnoreCase) || ext.Equals(".gz",StringComparison.OrdinalIgnoreCase) || ext.Equals(".gzip",StringComparison.OrdinalIgnoreCase)) return ScanArchives?2:-2;
        if(ext.Equals(".pdf",StringComparison.OrdinalIgnoreCase)) return String.IsNullOrEmpty(PdfTool)?-2:3;
        if(unsupportedSet.Contains(ext)) return -2;
        return AllTextFiles || extSet.Contains(ext) ? 0 : -1;
    }
    void Queue(string path, bool root) {
        try {
            path=Full(path); if(Excluded(path)) { Inc(Stat.SkipExcluded); return; }
            FileAttributes a=File.GetAttributes(path); bool dir=(a&FileAttributes.Directory)!=0;
            if(!root && dir && excludeSet.Contains(Path.GetFileName(path))) { Inc(Stat.SkipExcluded); return; }
            if(!IncludeCloudOnly && (a&CloudFlags)!=0) { Inc(Stat.SkipCloud); return; }
            string key=path;
            if((a&FileAttributes.ReparsePoint)!=0 || (FollowLinks && dir)) {
                // Cloud reparse points are allowed when their data is local; resolve and compare targets.
                if(!Windows) { Inc(Stat.SkipLink); return; }
                key=Canonical(path,dir);
                if(!FollowLinks && !key.Equals(path,PathComparison)) { Inc(Stat.SkipLink); return; }
                if(Excluded(key)) { Inc(Stat.SkipExcluded); return; }
            }
            Item it=new Item { Path=path, Dir=dir };
            if(!dir) {
                Inc(Stat.Seen); string name=Path.GetFileName(path);
                // $I records inherit the deleted file's extension but contain metadata, not its data.
                bool recycle=false;
                foreach(string part in path.Split(new[]{'\\','/'})) if(part.Equals("$Recycle.Bin",StringComparison.OrdinalIgnoreCase)) { recycle=true; break; }
                if(recycle && name.StartsWith("$I",StringComparison.OrdinalIgnoreCase)) { Inc(Stat.SkipMetadata); return; }
                if(name.Equals("NTUSER.DAT",StringComparison.OrdinalIgnoreCase) || name.Equals("UsrClass.dat",StringComparison.OrdinalIgnoreCase) || name.Equals("desktop.ini",StringComparison.OrdinalIgnoreCase) || name.Equals("thumbs.db",StringComparison.OrdinalIgnoreCase)) { Inc(Stat.SkipExcluded); return; }
                it.Kind=Kind(Path.GetExtension(path)); if(it.Kind<0) { Inc(it.Kind==-2?Stat.SkipUnsupported:Stat.SkipExt); return; }
                FileInfo fi=new FileInfo(path); it.Size=fi.Length; it.Modified=fi.LastWriteTimeUtc;
                if(it.Size==0) { Inc(Stat.SkipEmpty); return; } if(it.Size>MaxFileBytes) { Inc(Stat.SkipSize); return; }
            }
            if(!visited.TryAdd((dir?"D:":"F:")+key,0)) { Inc(Stat.SkipDuplicate); return; }
            Interlocked.Increment(ref pending); stack.Push(it);
        } catch(Exception ex) { Error(path,ex); }
    }
    public void Start(string[] roots) {
        BuildRules(); extSet=Set(Extensions); officeSet=Set(OfficeExt); unsupportedSet=Set(Unsupported); excludeSet=Set(ExcludeDirectories);
        List<string> ex=new List<string>(); foreach(string p in ExcludePaths??new string[0]) ex.Add(Full(p));
        if(!String.IsNullOrEmpty(PdfTool)) { tempRoot=Path.Combine(Path.GetTempPath(),"PiiHeavy-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(tempRoot); ex.Add(Full(tempRoot)); }
        excluded=ex.ToArray();
        foreach(string root in roots) Queue(root,true);
        workers=new Thread[Math.Max(1,ThreadCount)];
        try { for(int i=0;i<workers.Length;i++) { workers[i]=new Thread(Loop); workers[i].IsBackground=true; workers[i].Priority=ThreadPriority.BelowNormal; workers[i].Start(); } }
        catch { cancel=true; throw; }
    }
    public bool IsRunning { get { if(workers!=null) foreach(Thread t in workers) if(t!=null && t.IsAlive) return true; return false; } }
    public void Cancel() { cancel=true; }
    public void Cleanup() { if(!IsRunning && tempRoot!=null && Directory.Exists(tempRoot)) { try { Directory.Delete(tempRoot,true); } catch(Exception ex) { Error(tempRoot,ex); } } }
    public bool Wait(int milliseconds) {
        Stopwatch sw=Stopwatch.StartNew(); if(workers!=null) foreach(Thread t in workers) if(t!=null && t.IsAlive) t.Join(Math.Max(0,milliseconds-(int)sw.ElapsedMilliseconds));
        return !IsRunning;
    }
    void Loop() {
        Worker w=new Worker();
        while(!cancel) {
            Item it;
            if(!stack.TryPop(out it)) { if(Interlocked.Read(ref pending)==0) break; Thread.Sleep(10); continue; }
            try { if(it.Dir) Expand(it.Path); else Scan(it,w); }
            catch(Exception ex) { Error(it.Path,ex); }
            finally { Interlocked.Decrement(ref pending); }
        }
    }
    void Expand(string dir) {
        Inc(Stat.Dirs);
        // Queue handles each entry's metadata failures; iterator failures affect only this directory.
        try { foreach(string p in Directory.EnumerateFileSystemEntries(dir)) { if(cancel) break; Queue(p,false); } }
        catch(Exception ex) { Error(dir,new IOException("Directory enumeration incomplete: "+ex.Message,ex)); }
    }
    static FileStream OpenRead(string path) { return new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete,65536,FileOptions.SequentialScan); }
    void Scan(Item it, Worker w) {
        State s=new State(names.Length,MaxArchiveBytes); Inc(Stat.Attempted);
        try {
            if(it.Kind==3) { Inc(Stat.Pdf); Pdf(it,w,s); }
            else using(FileStream fs=OpenRead(it.Path)) { ReadContent(fs,Path.GetFileName(it.Path),it.Path,w,s,0); }
            FileInfo after=new FileInfo(it.Path);
            if(after.Length!=it.Size || after.LastWriteTimeUtc!=it.Modified) Partial(s,it.Path,"File changed during scan; results may be incomplete.");
        } catch(Exception ex) { s.Incomplete=true; Error(it.Path,ex); }
        finally {
            if(cancel) s.Incomplete=true;
            if(s.Incomplete) Inc(s.ReadAny?Stat.Partial:Stat.Failed);
            else if(s.ReadAny) { Inc(Stat.Files); Inc(Stat.Bytes,it.Size); }
            for(int i=0;i<names.Length;i++) if(s.Hits[i]>0) {
                while(!cancel && Findings.Count>=2000) Thread.Sleep(10);
                string loc=s.Location[i]; if(loc.StartsWith(it.Path,PathComparison)) loc=loc.Substring(it.Path.Length).TrimStart(':',' ');
                Findings.Enqueue(new Finding { Timestamp=DateTime.Now, Type=names[i], Confidence=s.Confidence[i], File=it.Path, Location=loc, Hits=s.Hits[i], Sample=s.Sample[i], Size=it.Size, Modified=it.Modified, ScanStatus=s.Incomplete?"Partial":"Completed", Line=s.Line[i], Column=s.Column[i], MatchLength=s.MatchLength[i], Reason=s.Reason[i], ReviewNote=s.ReviewNote[i], Context=s.Context[i] }); Inc(Stat.Findings);
            }
        }
    }
    byte[] Limited(Stream input, State s) {
        using(MemoryStream m=new MemoryStream()) {
            byte[] b=new byte[65536]; int n;
            while((n=input.Read(b,0,b.Length))>0) {
                if(cancel) throw new OperationCanceledException();
                if(m.Length+n>MaxExtractBytes || n>s.Budget) throw new InvalidDataException("Extraction byte limit reached; increase extraction limits to cover this content.");
                s.Budget-=n; m.Write(b,0,n);
            }
            return m.ToArray();
        }
    }
    void ReadContent(Stream input,string name,string label,Worker w,State s,int depth) {
        if(cancel || s.AllDone) return;
        string ext=Path.GetExtension(name).ToLowerInvariant(); int kind=Kind(ext); s.Label=label;
        if(kind<0 || kind==3) { Inc(kind==-1?Stat.SkipExt:Stat.SkipUnsupported); return; }
        if(kind==1 || kind==2) {
            if(depth>MaxDepth) { Inc(Stat.SkipSize); Partial(s,label,"Archive depth limit reached."); return; }
            if(kind==1) Inc(Stat.Office); else Inc(Stat.Archives);
            if(ext==".gz" || ext==".gzip") {
                using(GZipStream gz=new GZipStream(input,CompressionMode.Decompress,true))
                using(MemoryStream data=new MemoryStream(Limited(gz,s))) {
                    string inner=Path.GetFileNameWithoutExtension(name); if(Path.GetExtension(inner)=="") inner+=".txt";
                    ReadContent(data,inner,label+"!"+inner,w,s,depth+1);
                }
            } else Zip(input,label,w,s,depth,kind==1);
            return;
        }
        if(ext==".eml" || ext==".mht" || ext==".mhtml") {
            if(depth>MaxDepth) { Inc(Stat.SkipSize); Partial(s,label,"Attached message nesting limit reached."); return; }
            byte[] data=Limited(input,s); Mail(data,label,w,s,depth,0); return;
        }
        if(ext==".html" || ext==".htm" || ext==".xml") {
            byte[] data=Limited(input,s);
            string extracted=ext==".xml"?XmlText(data):Html(Decode(data));
            s.Label=label+" [extracted text]"; using(StringReader r=new StringReader(extracted)) Reader(r,w.Buf,s); return;
        }
        Plain(input,w,s);
    }
    static Encoding Sniff(byte[] h,int n,out bool binary) {
        binary=false;
        if(n>=4 && h[0]==0 && h[1]==0 && h[2]==254 && h[3]==255) return new UTF32Encoding(true,true);
        if(n>=4 && h[0]==255 && h[1]==254 && h[2]==0 && h[3]==0) return Encoding.UTF32;
        if(n>=3 && h[0]==239 && h[1]==187 && h[2]==191) return Encoding.UTF8;
        if(n>=2 && h[0]==255 && h[1]==254) return Encoding.Unicode;
        if(n>=2 && h[0]==254 && h[1]==255) return Encoding.BigEndianUnicode;
        int nul=0,even=0,control=0;
        for(int i=0;i<n;i++) { byte b=h[i]; if(b==0) { nul++; if(i%2==0) even++; } else if(b<9 || (b>13 && b<32)) control++; }
        if(nul>0) {
            if(nul*4>=n && even*10<=nul) return Encoding.Unicode;
            if(nul*4>=n && even*10>=nul*9) return Encoding.BigEndianUnicode;
            binary=true;
        }
        if(control*10>n) binary=true;
        return new UTF8Encoding(false);
    }
    static string Decode(byte[] data) {
        bool binary; Encoding enc=Sniff(data,Math.Min(data.Length,HeadBytes),out binary);
        if(binary) throw new InvalidDataException("Expected text, but the content appears binary.");
        using(StreamReader r=new StreamReader(new MemoryStream(data),enc,true)) return r.ReadToEnd();
    }
    void Plain(Stream input,Worker w,State s) {
        // All callers supply seekable streams; sniffing never opens a second handle.
        long start=input.Position; int n=0,r;
        while(n<HeadBytes && (r=input.Read(w.Head,n,HeadBytes-n))>0) n+=r;
        bool binary; Encoding enc=Sniff(w.Head,n,out binary);
        if(n==0 || binary) { Inc(binary?Stat.SkipBinary:Stat.SkipEmpty); s.Skipped=true; return; }
        input.Position=start;
        using(StreamReader reader=new StreamReader(input,enc,true,65536,true)) Reader(reader,w.Buf,s);
    }
    static bool OfficePart(string name) {
        string n=name.ToLowerInvariant(); if(!n.EndsWith(".xml")) return false;
        if(n=="content.xml" || n=="meta.xml" || n.StartsWith("docprops/")) return true;
        if(n.StartsWith("word/")) return n=="word/document.xml" || n.StartsWith("word/header") || n.StartsWith("word/footer") || n.StartsWith("word/comments") || n.StartsWith("word/footnotes") || n.StartsWith("word/endnotes");
        if(n.StartsWith("xl/")) return n=="xl/sharedstrings.xml" || n.StartsWith("xl/worksheets/") || n.StartsWith("xl/comments");
        return n.StartsWith("ppt/slides/") || n.StartsWith("ppt/notesslides/") || n.StartsWith("ppt/comments/");
    }
    void Zip(Stream input,string label,Worker w,State s,int depth,bool office) {
        using(ZipArchive zip=new ZipArchive(input,ZipArchiveMode.Read,true)) {
            foreach(ZipArchiveEntry e in zip.Entries) {
                if(cancel || s.AllDone) break; if(e.FullName.EndsWith("/")) continue;
                if(++s.Entries>MaxEntries) { Partial(s,label,"Archive entry limit reached."); break; }
                if(office && !OfficePart(e.FullName)) continue;
                if(!office && Kind(Path.GetExtension(e.FullName))<0) { Inc(Stat.SkipUnsupported); continue; }
                string member=label+"!"+e.FullName;
                try {
                    if(e.Length>MaxExtractBytes || e.Length>s.Budget) { Inc(Stat.SkipSize); Partial(s,member,"Archive member exceeds extraction budget."); continue; }
                    using(Stream es=e.Open()) {
                        byte[] data=Limited(es,s);
                        if(office) { s.Label=member; using(StringReader r=new StringReader(XmlText(data))) Reader(r,w.Buf,s); }
                        else using(MemoryStream ms=new MemoryStream(data)) ReadContent(ms,e.FullName,member,w,s,depth+1);
                    }
                } catch(Exception ex) { s.Incomplete=true; Error(member,ex); }
            }
        }
    }
    string XmlText(byte[] data) {
        XmlReaderSettings cfg=new XmlReaderSettings { DtdProcessing=DtdProcessing.Prohibit, XmlResolver=null, MaxCharactersInDocument=MaxExtractBytes, IgnoreComments=true };
        StringBuilder b=new StringBuilder(); bool sharedIndex=false, skipValue=false;
        using(XmlReader r=XmlReader.Create(new MemoryStream(data),cfg)) {
            while(r.Read()) {
                if(cancel) throw new OperationCanceledException();
                if(r.NodeType==XmlNodeType.Element) {
                    if(r.LocalName=="c") sharedIndex=r.GetAttribute("t")=="s";
                    if(r.LocalName=="v") skipValue=sharedIndex;
                    if(r.LocalName=="br" || r.LocalName=="line-break") b.Append('\n');
                    if(r.LocalName=="tab") b.Append(' ');
                    if(r.LocalName=="s") b.Append(' ');
                } else if(r.NodeType==XmlNodeType.EndElement) {
                    if(r.LocalName=="v") skipValue=false;
                    if(r.LocalName=="p" || r.LocalName=="h" || r.LocalName=="si" || r.LocalName=="c" || r.LocalName=="row" || r.LocalName=="table-cell" || r.LocalName=="table-row") b.Append('\n');
                    if(r.LocalName=="c") sharedIndex=false;
                } else if(!skipValue && (r.NodeType==XmlNodeType.Text || r.NodeType==XmlNodeType.CDATA || r.NodeType==XmlNodeType.SignificantWhitespace)) b.Append(r.Value);
                if(b.Length>MaxExtractBytes) throw new InvalidDataException("Extracted XML text exceeds limit.");
            }
        }
        return b.ToString();
    }
    static string Html(string html) {
        html=Regex.Replace(html,@"</(?:p|div|tr|td|li|h[1-6])\s*>|<br\b[^>]{0,256}>","\n",RegexOptions.IgnoreCase,TimeSpan.FromSeconds(2));
        return WebUtility.HtmlDecode(Regex.Replace(html,@"<[^>]{1,4096}>","",RegexOptions.None,TimeSpan.FromSeconds(2))).Replace('\u00a0',' ');
    }
    // Bounded MIME parsing: common multipart, base64 and quoted-printable text/attachments.
    void Mail(byte[] data,string label,Worker w,State s,int depth,int mimeDepth) {
        if(mimeDepth>12) { Partial(s,label,"MIME nesting limit reached."); return; }
        string raw=Encoding.GetEncoding(28591).GetString(data); int split=raw.IndexOf("\r\n\r\n",StringComparison.Ordinal); int sep=4;
        if(split<0) { split=raw.IndexOf("\n\n",StringComparison.Ordinal); sep=2; }
        if(split<0) { s.Label=label; using(StringReader r=new StringReader(Decode(data))) Reader(r,w.Buf,s); return; }
        string headers=Regex.Replace(raw.Substring(0,split),@"\r?\n[ \t]+"," ",RegexOptions.None,TimeSpan.FromSeconds(2)); string body=raw.Substring(split+sep);
        if(headers.Length>65536) throw new InvalidDataException("MIME headers exceed limit.");
        if(mimeDepth==0) { s.Label=label+" [headers]"; using(StringReader r=new StringReader(headers)) Reader(r,w.Buf,s); }
        Match boundary=Regex.Match(headers,@"\bboundary\s*=\s*(?:""(?<v>[^""\r\n]{1,200})""|(?<v>[^;\s]{1,200}))",RegexOptions.IgnoreCase,TimeSpan.FromSeconds(2));
        if(boundary.Success) {
            string[] parts=Regex.Split(body,@"(?m)^--"+Regex.Escape(boundary.Groups["v"].Value)+@"(?:--)?[ \t]*\r?$",RegexOptions.None,TimeSpan.FromSeconds(2));
            bool closed=Regex.IsMatch(body,@"(?m)^--"+Regex.Escape(boundary.Groups["v"].Value)+@"--[ \t]*\r?$",RegexOptions.None,TimeSpan.FromSeconds(2));
            if(!closed) Partial(s,label,"MIME closing boundary is missing; available parts will still be scanned.");
            for(int i=1;i<parts.Length-(closed?1:0) && !cancel && !s.AllDone;i++) {
                if(++s.Entries>MaxEntries) { Partial(s,label,"MIME part limit reached."); break; }
                try { Mail(Encoding.GetEncoding(28591).GetBytes(parts[i].TrimStart('\r','\n')),label+"!part"+i,w,s,depth,mimeDepth+1); }
                catch(Exception ex) { s.Incomplete=true; Error(label+"!part"+i,ex); }
            }
            return;
        }
        byte[] bytes;
        if(Regex.IsMatch(headers,@"(?im)^Content-Transfer-Encoding:\s*base64",RegexOptions.None,TimeSpan.FromSeconds(2))) bytes=Convert.FromBase64String(body);
        else if(Regex.IsMatch(headers,@"(?im)^Content-Transfer-Encoding:\s*quoted-printable",RegexOptions.None,TimeSpan.FromSeconds(2))) {
            body=Regex.Replace(body,@"=\r?\n","",RegexOptions.None,TimeSpan.FromSeconds(2));
            body=Regex.Replace(body,@"=([0-9A-F]{2})",m=>((char)Convert.ToInt32(m.Groups[1].Value,16)).ToString(),RegexOptions.IgnoreCase,TimeSpan.FromSeconds(2)); bytes=Encoding.GetEncoding(28591).GetBytes(body);
        } else bytes=Encoding.GetEncoding(28591).GetBytes(body);
        if(bytes.Length>MaxExtractBytes || bytes.Length>s.Budget) throw new InvalidDataException("Decoded MIME data exceeds extraction budget."); s.Budget-=bytes.Length;
        Match filename=Regex.Match(headers,@"\b(?:filename|name)\s*=\s*(?:""(?<v>[^""\r\n]{1,255})""|(?<v>[^;\s]{1,255}))",RegexOptions.IgnoreCase,TimeSpan.FromSeconds(2));
        if(filename.Success) { using(MemoryStream ms=new MemoryStream(bytes)) ReadContent(ms,filename.Groups["v"].Value,label+"!"+filename.Groups["v"].Value,w,s,depth+1); return; }
        if(Regex.IsMatch(headers,@"(?im)^Content-Type:\s*message/rfc822",RegexOptions.None,TimeSpan.FromSeconds(2))) { Mail(bytes,label+"!message",w,s,depth+1,mimeDepth+1); return; }
        if(Regex.IsMatch(headers,@"(?im)^Content-Type:\s*(?:image|audio|video|application)/",RegexOptions.None,TimeSpan.FromSeconds(2))) { Inc(Stat.SkipUnsupported); return; }
        Match charset=Regex.Match(headers,@"\bcharset\s*=\s*[""']?(?<v>[A-Za-z0-9_-]{1,40})",RegexOptions.IgnoreCase,TimeSpan.FromSeconds(2));
        string text=charset.Success?Encoding.GetEncoding(charset.Groups["v"].Value).GetString(bytes):Decode(bytes);
        if(Regex.IsMatch(headers,@"(?im)^Content-Type:\s*text/html",RegexOptions.None,TimeSpan.FromSeconds(2))) text=Html(text);
        s.Label=label+" [decoded text]"; using(StringReader r=new StringReader(text)) Reader(r,w.Buf,s);
    }
    static string QuoteArgument(string value) {
        StringBuilder b=new StringBuilder("\""); int slashes=0;
        foreach(char c in value) {
            if(c=='\\') { slashes++; continue; }
            b.Append('\\',c=='"'?slashes*2+1:slashes); b.Append(c); slashes=0;
        }
        b.Append('\\',slashes*2); b.Append('"'); return b.ToString();
    }
    void Pdf(Item it,Worker w,State s) {
        string dir=Path.Combine(tempRoot,Guid.NewGuid().ToString("N")); Directory.CreateDirectory(dir);
        string output=Path.Combine(dir,"text.txt");
        try {
            // Arguments are quoted independently; no shell, global temp names or process-name killing.
            ProcessStartInfo info=new ProcessStartInfo(PdfTool,"-enc UTF-8 -nopgbrk "+QuoteArgument(it.Path)+" "+QuoteArgument(output)) { UseShellExecute=false, CreateNoWindow=true, RedirectStandardError=true, RedirectStandardOutput=true };
            using(Process p=new Process { StartInfo=info }) {
                p.ErrorDataReceived+=(sender,e)=>{}; p.OutputDataReceived+=(sender,e)=>{};
                try {
                    p.Start(); p.BeginErrorReadLine(); p.BeginOutputReadLine(); Stopwatch sw=Stopwatch.StartNew();
                    while(!p.WaitForExit(100)) {
                        if(cancel) throw new OperationCanceledException();
                        if(sw.Elapsed.TotalSeconds>PdfSeconds) throw new TimeoutException("PDF conversion timed out.");
                        if(File.Exists(output) && new FileInfo(output).Length>MaxExtractBytes) throw new InvalidDataException("PDF extracted text exceeds limit.");
                    }
                    if(p.ExitCode!=0) throw new IOException("pdftotext failed with exit code "+p.ExitCode+" (encrypted, unreadable or invalid PDF).");
                } finally { try { if(!p.HasExited) { p.Kill(); p.WaitForExit(2000); } } catch(InvalidOperationException) {} }
            }
            if(!File.Exists(output)) throw new IOException("PDF converter produced no text file.");
            if(new FileInfo(output).Length>MaxExtractBytes) throw new InvalidDataException("PDF extracted text exceeds limit.");
            s.Label=it.Path+" [PDF extracted text]"; using(FileStream fs=OpenRead(output)) Plain(fs,w,s);
        } finally { try { Directory.Delete(dir,true); } catch(Exception ex) { Error(dir,new IOException("Could not remove this scan's PDF temporary directory.",ex)); } }
    }
    void Reader(TextReader reader,char[] buf,State s) {
        int carry=0; long offset=0,lineBase=0,columnBase=1; bool eof=false;
        HashSet<long>[] seen=new HashSet<long>[names.Length]; for(int i=0;i<seen.Length;i++) seen[i]=new HashSet<long>();
        while(!eof && !cancel && !s.AllDone) {
            int n=reader.ReadBlock(buf,carry,ChunkChars); eof=n<ChunkChars; int len=carry+n; if(len==0) break;
            s.ReadAny=true; string text=new string(buf,0,len).Replace('\u00a0',' '); int limit=eof?len:len-Overlap;
            bool digit=text.IndexOfAny(Digits)>=0,at=text.IndexOf('@')>=0;
            foreach(Rule rule in rules) {
                int t=rule.Index; if(s.Done[t] || !(names[t]=="Email"?at:digit)) continue;
                try {
                    for(Match m=rule.Rx.Match(text);m.Success && m.Index<limit;m=m.NextMatch()) {
                        Group g=m.Groups["v"]; string value=g.Value;
                        if(!Valid(rule.Check,ref value) || !seen[t].Add(offset+g.Index)) continue;
                        if(++s.Hits[t]==1) {
                            int previous=g.Index>0?text.LastIndexOf('\n',g.Index-1):-1;
                            s.Line[t]=lineBase+Newlines(text,g.Index)+1;
                            s.Column[t]=previous>=0?g.Index-previous:columnBase+g.Index;
                            s.MatchLength[t]=value.Length; s.Reason[t]=rule.Reason;
                            s.Sample[t]=ShowValues?value:Mask(value,names[t]);
                            s.Location[t]=s.Label+":line "+s.Line[t]+", column "+s.Column[t]; s.Confidence[t]=rule.Confidence;
                            int next=text.IndexOf('\n',g.Index); if(next<0) next=text.Length;
                            int left=Math.Max(previous+1,g.Index-60),right=Math.Min(next,g.Index+Math.Min(value.Length,120)+60);
                            string excerpt=text.Substring(left,right-left).TrimEnd('\r');
                            if(ShowValues) s.Context[t]=(left>previous+1?"...":"")+excerpt+(right<next?"...":"");
                            if(Regex.IsMatch(s.Label??"",@"\.(?:ps1|psm1|psd1|py|js|cs|java|c|cpp|h|md|rst)$",RegexOptions.IgnoreCase) &&
                               Regex.IsMatch(excerpt,@"\b(?:example|sample|dummy|placeholder|test data|shortest possible)\b",RegexOptions.IgnoreCase))
                                s.ReviewNote[t]="Possible example/test data in source or documentation; verify before acting.";
                        }
                        if(!CountAll) { s.Done[t]=true; break; }
                    }
                } catch(RegexMatchTimeoutException) { Partial(s,s.Label,"Regex timeout for "+names[t]+"; other rules continue."); }
            }
            if(eof || s.AllDone) break;
            int lastBreak=text.LastIndexOf('\n',limit-1);
            columnBase=lastBreak>=0?limit-lastBreak:columnBase+limit;
            offset+=limit; lineBase+=Newlines(text,limit); carry=len-limit; Array.Copy(buf,limit,buf,0,carry);
            foreach(HashSet<long> set in seen) set.RemoveWhere(i=>i<offset);
        }
    }
    static int Newlines(string text,int end) { int n=0; for(int i=0;i<end;i++) if(text[i]=='\n') n++; return n; }
    static string Numbers(string s) { StringBuilder b=new StringBuilder(); foreach(char c in s) if(c>='0' && c<='9') b.Append(c); return b.ToString(); }
    static bool Luhn(string s) {
        int total=0; bool alternate=false; for(int i=s.Length-1;i>=0;i--) { int d=s[i]-'0'; if(alternate) { d*=2; if(d>9) d-=9; } total+=d; alternate=!alternate; }
        return total>0 && total%10==0;
    }
    static bool Valid(string check,ref string value) {
        string n=Numbers(value);
        if(check=="ID" || check=="Nonzero") return n.Length>0 && n.Trim('0').Length>0;
        if(check=="Phone") {
            if(value.StartsWith("+")) return n.Length>=8 && n.Length<=15 && n[0]!='0';
            if(n.Length==11 && n[0]=='1') n=n.Substring(1);
            return n.Length==10 && n[0]>='2' && n[3]>='2';
        }
        if(check=="Email") {
            string lower=value.ToLowerInvariant();
            return value.Length<=254 && !value.Contains("..") && !value.StartsWith(".") && !value.Contains(".@") && !Regex.IsMatch(lower,@"\.(?:png|jpg|jpeg|gif|svg|webp|css|js|ico|bmp)$");
        }
        if(check=="Card") {
            if(n.Length<13 || n.Length>19 || !Luhn(n)) return false;
            int first2=Int32.Parse(n.Substring(0,2)),first4=Int32.Parse(n.Substring(0,4));
            return (n[0]=='4' && (n.Length==13 || n.Length==16 || n.Length==19)) ||
                (n.Length==16 && ((first2>=51 && first2<=55) || (first4>=2221 && first4<=2720))) ||
                (n.Length==15 && (first2==34 || first2==37)) || (n.Length>=16 && (n.StartsWith("6011") || first2==65 || (first4>=6440 && first4<=6499) || first2==62 || (first4>=3528 && first4<=3589))) ||
                (n.Length==14 && (first2==36 || first2==38 || first2==39 || (first4>=3000 && first4<=3059)));
        }
        if(check=="ABA") {
            if(n.Length!=9 || n.Trim('0').Length==0) return false; int p=Int32.Parse(n.Substring(0,2));
            int sum=3*(n[0]+n[3]+n[6]-3*'0')+7*(n[1]+n[4]+n[7]-3*'0')+(n[2]+n[5]+n[8]-3*'0');
            return (p<=12 || (p>=21 && p<=32) || (p>=61 && p<=72) || p==80) && sum%10==0;
        }
        if(check=="Date") {
            string v=Regex.Replace(value,@"(?<=[0-9])(?:st|nd|rd|th)\b","",RegexOptions.IgnoreCase);
            DateTime d; bool ok=DateTime.TryParse(v,CultureInfo.GetCultureInfo("en-US"),DateTimeStyles.AllowWhiteSpaces,out d) || DateTime.TryParse(v,CultureInfo.GetCultureInfo("en-GB"),DateTimeStyles.AllowWhiteSpaces,out d);
            return ok && d.Year>=1800 && d.Date<=DateTime.Today;
        }
        if(check=="IBAN") {
            string v=value.Replace(" ","").ToUpperInvariant(); if(v.Length<15 || v.Length>34) return false;
            // Common country lengths prevent a following word from being swallowed by the candidate.
            string[] lengths={"DE22","GB22","FR27","ES24","IT27","NL18","BE16","CH21","AT20","IE22","PT25","PL28","NO15","SE24","FI18","DK18","LU20","GR27","CZ24","SK24","HU28","RO24","BG22","HR21","CY28","MT31","EE20","LV21","LT20","IS26","LI21","TR26","SA24","AE23","IL23","BR29","PK24","UA29"};
            foreach(string entry in lengths) if(v.StartsWith(entry.Substring(0,2))) { int len=Int32.Parse(entry.Substring(2)); if(v.Length<len) return false; if(v.Length>len) { int chars=0,end=0; while(end<value.Length && chars<len) { if(value[end]!=' ') chars++; end++; } if(end<value.Length && value[end]!=' ') return false; value=value.Substring(0,end); v=v.Substring(0,len); } break; }
            string shifted=v.Substring(4)+v.Substring(0,4); int mod=0;
            foreach(char c in shifted) { if(c>='0' && c<='9') mod=(mod*10+c-'0')%97; else if(c>='A' && c<='Z') mod=(mod*100+c-'A'+10)%97; else return false; }
            return mod==1;
        }
        return true;
    }
    static string Mask(string value,string type) {
        if(type=="Address" || type=="DOB") return Regex.Replace(value,"[0-9]","#");
        if(type=="Email") return "***@***";
        char[] c=value.ToCharArray(); int seen=0; for(int i=c.Length-1;i>=0;i--) if(Char.IsLetterOrDigit(c[i]) && ++seen>4) c[i]='*'; return new string(c);
    }
}
}

'@

function Write-PiiMessage {
    param([string]$Message, [ConsoleColor]$Color = 'Gray')
    # Requested console timestamp format; no shared logger or type formatting is installed.
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}
function Safe-Display([string]$Text) { [regex]::Replace($Text, '[\p{Cc}\p{Cf}]', ' ') }
function Write-PiiSection([string]$Title, [ConsoleColor]$Color = 'Cyan') {
    Write-Host ''; Write-PiiMessage $Title $Color
}
function Write-PiiField([string]$Label, $Value, [ConsoleColor]$Color = 'Gray') {
    $prefix='    {0,-18}: ' -f $Label
    $text=Safe-Display ([string]$Value)
    $width=100
    try { if ($Host.UI.RawUI.WindowSize.Width -ge 60) { $width=[Math]::Min(120,$Host.UI.RawUI.WindowSize.Width) } } catch { }
    $available=$width-$prefix.Length-1
    while ($text.Length -gt $available) {
        $cut=$text.LastIndexOf(' ',$available)
        if ($cut -lt ($available/2)) { $cut=$available }
        Write-Host ($prefix+$text.Substring(0,$cut)) -ForegroundColor $Color
        $text=$text.Substring($cut).TrimStart(); $prefix=' '*$prefix.Length
    }
    Write-Host ($prefix+$text) -ForegroundColor $Color
}
$discoveryErrors = New-Object 'System.Collections.Generic.List[object]'
function Add-DiscoveryError([string]$Target, [string]$Message) {
    $discoveryErrors.Add([pscustomobject]@{ Timestamp=Get-Date; Path=$Target; Kind='Discovery'; Message=$Message })
    Write-PiiMessage "[WARN] $(Safe-Display $Target): $(Safe-Display $Message)" Yellow
}

# A source-specific namespace avoids collisions with Light, older Heavy versions and other scripts.
$sha = [Security.Cryptography.SHA256]::Create()
try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($engineSource)))).Replace('-','') }
finally { $sha.Dispose() }
$engineNamespace = 'PiiHeavy_' + $hash.Substring(0,16)
$scannerType = "$engineNamespace.Scanner"
try {
    if (-not ($scannerType -as [type])) {
        $compile = @{ TypeDefinition=$engineSource.Replace('namespace PiiHeavyEngine {', "namespace $engineNamespace {"); Language='CSharp'; ErrorAction='Stop' }
        if ($PSVersionTable.PSEdition -eq 'Desktop') { $compile.ReferencedAssemblies = 'System','System.Core','System.Xml','System.IO.Compression' }
        Add-Type @compile
    }
} catch { throw "[$(Get-Date -Format 'HH:mm:ss')] Scanner compilation failed: $($_.Exception.Message)" }

$noiseFolders = @('AppData','node_modules','.git','.svn','.hg','__pycache__','site-packages','.venv','.nuget','.npm','.cache','.gradle','.m2','.cargo','.rustup','.conda','.vscode','.vs','.docker','.android')
$osFolders = @('Windows','Program Files','Program Files (x86)','ProgramData','Users','Documents and Settings','Recovery','PerfLogs','System Volume Information','$Recycle.Bin','Config.Msi','MSOCache','Boot','Intel','AMD','NVIDIA','Drivers','swsetup','$WinREAgent','$SysReset','$Windows.~BT','$Windows.~WS','ESD')
function Get-DefaultRoots {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $profiles = @()
    try {
        $keys = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop |
            Where-Object PSChildName -Match '^S-1-(5-21|12-1)-')
        foreach ($key in $keys) {
            try {
                $profile = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if ($profile.PSObject.Properties['ProfileImagePath']) { $profiles += [Environment]::ExpandEnvironmentVariables([string]$profile.ProfileImagePath) }
            } catch { Add-DiscoveryError $key.Name $_.Exception.Message }
        }
    } catch { Add-DiscoveryError 'Profile registry' $_.Exception.Message }
    if (-not $profiles) {
        try { $profiles = @(Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction Stop | ForEach-Object FullName) }
        catch { Add-DiscoveryError "$env:SystemDrive\Users" $_.Exception.Message }
    }
    $profiles += $env:PUBLIC
    foreach ($p in $profiles) {
        if (-not $p) { continue }
        $candidates.Add($p)
        if ($IncludeAppData) { $candidates.Add("$p\AppData") }
        else {
            $candidates.Add("$p\AppData\Local\Temp")
            $candidates.Add("$p\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook")
            $candidates.Add("$p\AppData\Local\Microsoft\Olk\Attachments")
        }
    }
    $candidates.Add("$env:SystemRoot\Temp")
    if ($IncludeAppData) { $candidates.Add($env:ProgramData) }
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        try {
            if ($drive.DriveType -eq 'Network') { if ($IncludeMappedDrives) { $candidates.Add($drive.RootDirectory.FullName) }; continue }
            if ($drive.DriveType -notin 'Fixed','Removable') { continue }
            if (-not $drive.IsReady) { continue }
            $root = $drive.RootDirectory.FullName
            if ($drive.DriveType -eq 'Fixed') { $candidates.Add((Join-Path $root '$Recycle.Bin')) }
            if (-not ($root.StartsWith($env:SystemDrive,[StringComparison]::OrdinalIgnoreCase) -or $IncludeOtherDrives)) { continue }
            # Include loose root files as well as selected data directories.
            Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop | ForEach-Object {
                if (-not $_.PSIsContainer -or $_.Name -notin $osFolders) { $candidates.Add($_.FullName) }
            }
        } catch { Add-DiscoveryError $drive.Name $_.Exception.Message }
    }
    if (-not $SkipShares) {
        try {
            foreach ($share in @(Get-CimInstance Win32_Share -Filter 'Type = 0' -ErrorAction Stop)) {
                if ($share.Path -and $share.Name -notlike '*$') { $candidates.Add([string]$share.Path) }
            }
        } catch { Add-DiscoveryError 'Local shares' $_.Exception.Message }
    }
    # Absent optional caches are normal; discovery/access failures have separate diagnostics.
    foreach ($p in $candidates) {
        try { if ($p -and (Test-Path -LiteralPath $p -ErrorAction Stop)) { $p } }
        catch { Add-DiscoveryError $p $_.Exception.Message }
    }
}

if ($onWindows) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-PiiMessage '[WARN] Not elevated; some profiles, shares and recycle bins may be unreadable.' Yellow
        }
    } finally { $identity.Dispose() }
}
Write-PiiMessage 'Preparing scan locations...' Cyan
$roots = New-Object 'System.Collections.Generic.List[string]'
if ($Path) {
    foreach ($p in $Path) {
        try {
            $expanded = [Environment]::ExpandEnvironmentVariables($p)
            # Existing literal paths containing brackets take precedence over wildcard interpretation.
            if (Test-Path -LiteralPath $expanded -ErrorAction Stop) { $resolved = @(Resolve-Path -LiteralPath $expanded -ErrorAction Stop) }
            else { $resolved = @(Resolve-Path -Path $expanded -ErrorAction Stop) }
            foreach ($r in $resolved) {
                if ($r.Provider.Name -ne 'FileSystem') { throw 'Only filesystem paths are supported.' }
                $roots.Add($r.ProviderPath)
            }
        } catch { Add-DiscoveryError $p $_.Exception.Message }
    }
} else {
    if (-not $onWindows) { throw "[$(Get-Date -Format 'HH:mm:ss')] Supply -Path outside Windows." }
    foreach ($p in @(Get-DefaultRoots)) { $roots.Add($p) }
}
if ($roots.Count -eq 0) { throw "[$(Get-Date -Format 'HH:mm:ss')] No valid files or folders to scan." }
if ($PdfTextTool) {
    try {
        $PdfTextTool = (Resolve-Path -LiteralPath $PdfTextTool -ErrorAction Stop).ProviderPath
        if (-not [IO.File]::Exists($PdfTextTool)) { throw 'PdfTextTool must name an existing executable file.' }
    } catch { throw "[$(Get-Date -Format 'HH:mm:ss')] Invalid PDF converter: $($_.Exception.Message)" }
}
if ($Threads -eq 0) { $Threads = [Math]::Min(8,[Math]::Max(2,[Environment]::ProcessorCount)) }
$textExt = @('.txt','.csv','.tsv','.psv','.log','.out','.rpt','.prn','.json','.jsonl','.ndjson','.xml','.html','.htm','.mht','.mhtml','.sql','.md','.rtf','.tex','.ini','.cfg','.conf','.config','.properties','.env','.yaml','.yml','.eml','.mbox','.vcf','.ldif','.ics','.bak','.dat','.tmp','.asc','.ps1','.bat','.cmd','.vbs','.js','.py')
if ($Extension) { $textExt = @($Extension | ForEach-Object { '.' + $_.Trim().TrimStart('.') } | Select-Object -Unique) }
$excludedPaths = @($ExcludePath | ForEach-Object {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([Environment]::ExpandEnvironmentVariables($_))
})
if ($PSCommandPath) { $excludedPaths += $PSCommandPath }
$reportPath = $null; $errorPath = $null
if ($OutputPath) {
    $reportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if ([IO.Path]::GetExtension($reportPath) -ne '.csv') { throw "[$(Get-Date -Format 'HH:mm:ss')] OutputPath must end in .csv." }
    $errorPath = [IO.Path]::ChangeExtension($reportPath,'errors.csv')
    if ($PSCommandPath -and $reportPath -eq $PSCommandPath) { throw "[$(Get-Date -Format 'HH:mm:ss')] The report cannot replace this script." }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($reportPath))) { throw "[$(Get-Date -Format 'HH:mm:ss')] The output directory must already exist." }
    foreach ($p in @($reportPath,$errorPath)) { if (-not $Force -and [IO.File]::Exists($p)) { throw "[$(Get-Date -Format 'HH:mm:ss')] Report already exists: $p. Choose a new path or use -Force." } }
    $excludedPaths += $reportPath,$errorPath
}
$scanner = New-Object $scannerType -Property @{
    Types=[string[]]$Type; Extensions=[string[]]$textExt
    ExcludeDirectories=[string[]](@($ExcludeDirectory) + $(if ($NoDefaultExcludes) { @() } else { $noiseFolders }))
    ExcludePaths=[string[]]$excludedPaths; ScanOffice=(-not $SkipOfficeDocs); ScanArchives=(-not $SkipArchives)
    AllTextFiles=[bool]$AllTextFiles; FollowLinks=[bool]$FollowLinks; IncludeCloudOnly=[bool]$IncludeCloudOnly
    IncludeUnlabelledNumbers=[bool]$IncludeUnlabelledNumbers; CountAll=[bool]$CountAll; ShowValues=[bool]$ShowValues
    MaxFileBytes=([long]$MaxFileSizeMB*1MB); MaxExtractBytes=([long]$MaxExtractedMB*1MB)
    MaxArchiveBytes=([long]$MaxArchiveTotalMB*1MB); MaxDepth=$MaxArchiveDepth; MaxEntries=$MaxArchiveEntries
    ThreadCount=$Threads; RegexSeconds=$RegexTimeoutSeconds; PdfSeconds=$PdfTimeoutSeconds; PdfTool=$PdfTextTool
}

# Per-run report handles: CreateNew protects other scripts' existing files by default.
$findingWriter=$null; $errorWriter=$null; $live=@{ ByType=@{}; Count=0; Files=(New-Object 'System.Collections.Generic.HashSet[string]') }
function Open-CsvWriter([string]$FileName,[string[]]$Columns) {
    $mode = if ($Force) { [IO.FileMode]::Create } else { [IO.FileMode]::CreateNew }
    $stream = New-Object IO.FileStream($FileName,$mode,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $writer = New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($true))); $writer.WriteLine(($Columns -join ',')); return $writer }
    catch { $stream.Dispose(); throw }
}
function Write-CsvRow($Writer,$Object) {
    if ($null -eq $Writer) { return }
    $row=[ordered]@{}
    foreach ($p in $Object.PSObject.Properties) {
        $v=$p.Value
        # Prevent cells derived from source text from becoming spreadsheet formulas.
        if ($v -is [string] -and $v -match '^[\s]*[=+@-]') { $v="'"+$v }
        $row[$p.Name]=$v
    }
    $csv=@([pscustomobject]$row | ConvertTo-Csv -NoTypeInformation); $Writer.WriteLine($csv[1])
}
function Receive-Findings {
    $f=$null
    while ($scanner.Findings.TryDequeue([ref]$f)) {
        $o=[pscustomobject][ordered]@{
            Timestamp=$f.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'); Type=$f.Type; Confidence=$f.Confidence
            File=$f.File; Location=$f.Location; Hits=$f.Hits; Sample=$f.Sample
            SizeKB=[Math]::Round($f.Size/1KB,1); LastModified=$f.Modified.ToString('o'); ScanStatus=$f.ScanStatus
            Line=$f.Line; Column=$f.Column; MatchLength=$f.MatchLength; Reason=$f.Reason; ReviewNote=$f.ReviewNote; Context=$f.Context
        }
        $live.Count++; [void]$live.Files.Add($o.File)
        if (-not $live.ByType.ContainsKey($o.Type)) { $live.ByType[$o.Type]=0 }; $live.ByType[$o.Type]++
        Write-CsvRow $findingWriter $o
        if (-not $Quiet) {
            Write-PiiSection ("FINDING {0} - {1} ({2} confidence)" -f $live.Count,$o.Type,$o.Confidence) Yellow
            Write-PiiField 'File' $o.File
            Write-PiiField 'Location' $o.Location
            Write-PiiField $(if($ShowValues){'Match'}else{'Match (masked)'}) ('"'+$o.Sample+'"') Yellow
            Write-PiiField 'Why it matched' $o.Reason
            if ($CountAll) { Write-PiiField 'Occurrences' "$($o.Hits) (first match shown)" }
            if ($o.ReviewNote) { Write-PiiField 'Review note' $o.ReviewNote Cyan }
            if ($ShowValues -and $o.Context) { Write-PiiField 'Context' $o.Context }
            if ($o.ScanStatus -eq 'Partial') { Write-PiiField 'Coverage' 'Partial; see scan errors.' Yellow }
        }
        if ($PassThru) { $o }
    }
    if ($findingWriter) { $findingWriter.Flush() }
}
$progressId = Get-Random -Minimum 10000 -Maximum 2000000000
$watch=[Diagnostics.Stopwatch]::StartNew(); $finished=$false; $fatal=$null; $started=$false
try {
    if ($reportPath) {
        $findingWriter=Open-CsvWriter $reportPath @('Timestamp','Type','Confidence','File','Location','Hits','Sample','SizeKB','LastModified','ScanStatus','Line','Column','MatchLength','Reason','ReviewNote','Context')
        $errorWriter=Open-CsvWriter $errorPath @('Timestamp','Kind','Path','Message')
    }
    if ($ShowValues) { Write-PiiMessage '[WARN] Exact matches and nearby context will appear in console/CSV output.' Yellow }
    if ($IncludeCloudOnly) { Write-PiiMessage '[WARN] Cloud-only files may be downloaded by their sync provider.' Yellow }
    Write-PiiSection 'STARTING PII SCAN'
    Write-PiiField 'Inputs / workers' "$($roots.Count) / $Threads"
    Write-PiiField 'Checks' ($Type -join ', ')
    Write-PiiField 'Match display' $(if($ShowValues){'Exact values and context'}else{'Partially masked. Use -ShowValues for exact values and context.'})
    Write-PiiField 'Controls' 'Ctrl+C requests cancellation.' DarkGray
    $scanner.Start($roots.ToArray()); $started=$true
    do {
        Start-Sleep -Milliseconds 200; Receive-Findings
        if (-not $NoProgress) { Write-Progress -Id $progressId -Activity 'PII discovery' -Status ("[$(Get-Date -Format 'HH:mm:ss')] {0:N0} completed | {1:N0} partial | {2:N0} findings | {3:N0} errors | {4:hh\:mm\:ss}" -f $scanner.Get('Files'),$scanner.Get('Partial'),$live.Count,$scanner.Get('Errors'),$watch.Elapsed) }
    } while ($scanner.IsRunning)
    Receive-Findings; $finished=$true
} catch { $fatal=$_.Exception.Message; Write-PiiMessage "[ERROR] $(Safe-Display $fatal)" Red }
finally {
    if ($scanner.IsRunning) { $scanner.Cancel(); [void]$scanner.Wait(5000) }
    $scanner.Cleanup()
    $watch.Stop()
    try {
        if ($started) {
            try { Receive-Findings }
            catch { $fatal=$_.Exception.Message; Write-PiiMessage "[ERROR] Final result delivery failed: $(Safe-Display $fatal)" Red }
        }
        if (-not $NoProgress) { Write-Progress -Id $progressId -Activity 'PII discovery' -Completed }
        Write-PiiSection 'SCAN SUMMARY'
        Write-PiiField 'Status' $(if($finished -and -not $fatal){'Finished'}else{'Interrupted or failed; partial results'})
        Write-PiiField 'Elapsed' ('{0:hh\:mm\:ss}' -f $watch.Elapsed)
        Write-PiiField 'Files discovered' ('{0:N0}' -f $scanner.Get('Seen'))
        Write-PiiField 'Read attempts' ('{0:N0}' -f $scanner.Get('Attempted'))
        Write-PiiField 'Searches complete' ('{0:N0}' -f $scanner.Get('Files'))
        Write-PiiField 'Partial / failed' ('{0:N0} / {1:N0}' -f $scanner.Get('Partial'),$scanner.Get('Failed'))
        Write-PiiField 'Findings' ('{0:N0} across {1:N0} file(s)' -f $live.Count,$live.Files.Count)
        foreach ($name in @($live.ByType.Keys | Sort-Object)) { Write-PiiField $name ("$($live.ByType[$name]) file(s)") }
        Write-PiiField 'Counting mode' $(if($CountAll){'All occurrences; first sample per type/file shown.'}else{'First match per type/file.'}) DarkGray
        $skipLabels=[ordered]@{SkipExt='Extension filter';SkipUnsupported='Unsupported';SkipBinary='Binary content';SkipSize='Size/depth limits';SkipCloud='Cloud-only';SkipLink='Links';SkipExcluded='Exclusions';SkipDuplicate='Duplicates';SkipEmpty='Empty';SkipMetadata='Recycle metadata'}
        $hasSkips=$false
        foreach ($key in $skipLabels.Keys) {
            $count=$scanner.Get($key)
            if ($count -gt 0) {
                if (-not $hasSkips) { Write-PiiSection 'SKIPPED ITEMS'; $hasSkips=$true }
                Write-PiiField $skipLabels[$key] ('{0:N0}' -f $count)
            }
        }
        if ($hasSkips) { Write-PiiField 'Counting note' 'Includes folders and archive members; these counts do not add up to files discovered.' DarkGray }
        $errors=@($discoveryErrors.ToArray())+@($scanner.GetErrors())
        if ($errors.Count -gt 0) {
            Write-PiiSection ("SCAN ERRORS - {0:N0} scan, {1:N0} discovery" -f $scanner.Get('Errors'),$discoveryErrors.Count) Yellow
        } else { Write-PiiMessage 'Scan errors: none.' DarkGray }
        try { foreach ($e in $errors) { Write-CsvRow $errorWriter ([pscustomobject][ordered]@{Timestamp=$e.Timestamp.ToString('yyyy-MM-dd HH:mm:ss');Kind=$e.Kind;Path=$e.Path;Message=$e.Message}) } }
        catch { $fatal=$_.Exception.Message; Write-PiiMessage "[ERROR] Error CSV write failed: $(Safe-Display $fatal)" Red }
        foreach ($e in @($errors | Select-Object -First 5)) {
            Write-PiiField 'File / location' $e.Path
            Write-PiiField 'Error' $e.Kind Yellow
            Write-PiiField 'Detail' $e.Message
            Write-Host ''
        }
        if ($errors.Count -gt 5) { Write-PiiMessage 'Only the first five error details are displayed; use -OutputPath for the error CSV.' DarkGray }
        if ($scanner.Get('Errors') -gt 5000) { Write-PiiMessage 'Error details are capped at 5,000 scan errors; totals include the rest.' Yellow }
        if ($scanner.IsRunning) { Write-PiiMessage '[WARN] Some private workers are still waiting on I/O; final coverage/results are incomplete.' Yellow }
        if ($live.Count -eq 0) { Write-PiiMessage 'No matches reported in the examined content. Review skips and errors before interpreting this result.' Cyan }
        if ($reportPath -and $findingWriter) {
            Write-PiiSection 'REPORT FILES'
            Write-PiiField 'Findings CSV' $reportPath
            Write-PiiField 'Errors CSV' $errorPath
        }
    } finally {
        try { if ($findingWriter) { $findingWriter.Dispose() } }
        catch { $fatal=$_.Exception.Message; Write-PiiMessage "[ERROR] Findings CSV close failed: $(Safe-Display $fatal)" Red }
        try { if ($errorWriter) { $errorWriter.Dispose() } }
        catch { $fatal=$_.Exception.Message; Write-PiiMessage "[ERROR] Errors CSV close failed: $(Safe-Display $fatal)" Red }
    }
}
if ($fatal) { throw "[$(Get-Date -Format 'HH:mm:ss')] Scan/report failed: $fatal" }
} # invocation-local scope

