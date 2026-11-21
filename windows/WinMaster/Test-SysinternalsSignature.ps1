param([string]$Path)

if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
try {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    return ($sig.Status -eq 'Valid' -and
        $sig.SignerCertificate.SubjectName.Decode('UseNewLines') -match '(?m)^O=Microsoft Corporation\r?$')
}
catch {
    return $false
}
