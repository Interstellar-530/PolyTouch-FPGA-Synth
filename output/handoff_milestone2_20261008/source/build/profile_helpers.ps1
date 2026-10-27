function Get-BuildProfile([string]$Name) {
    $row = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'profiles.tsv') |
        Where-Object { ($_ -split "`t")[0] -eq $Name } | Select-Object -First 1
    if (-not $row) { throw "Unknown build profile: $Name" }
    $parts = $row -split "`t"
    [pscustomobject]@{ Name=$parts[0]; Directory=$parts[1]; Top=$parts[2]; Cst=$parts[3]; Sdc=$parts[4] }
}

function Get-BuildSourceRoot([string]$SourceRoot) {
    if ($SourceRoot) { return (Resolve-Path -LiteralPath $SourceRoot).Path }
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

# Content fingerprint of every file a build depends on: RTL, headers, ROM images,
# constraints, the build scripts themselves and the profile top wrapper.
# Length and timestamps are kept for diagnostics only; identity is SHA256, so a
# same-length edit that preserves the timestamp is still a different input.
function Get-BuildInputs {
    param($Profile, [string]$SourceRoot = '')
    $sourceRoot = Get-BuildSourceRoot $SourceRoot
    $paths = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'sources.list') |
        Where-Object { $_.Trim() -ne '' } | ForEach-Object { Join-Path $sourceRoot $_ })
    # Include ROM data and headers, even when not added as synthesis source files.
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'rtl/audio') -File |
        Where-Object Extension -In '.vh', '.hex', '.mi', '.mif' | ForEach-Object FullName)
    $paths += @('profiles.tsv','sources.list','hdmi_sources.list','build_profile.tcl','profile_helpers.ps1','build.ps1',
        ('isolated/' + $Profile.Top + '.v')) | ForEach-Object { Join-Path $PSScriptRoot $_ }
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'rtl/video') -File | ForEach-Object FullName)
    $paths += Join-Path $sourceRoot ('constraints/' + $Profile.Cst)
    $paths += Join-Path $sourceRoot ('constraints/' + $Profile.Sdc)
    $paths | Sort-Object -Unique | ForEach-Object {
        $item = Get-Item -LiteralPath $_ -ErrorAction Stop
        [pscustomobject]@{
            Path    = $item.FullName
            Length  = $item.Length
            Sha256  = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLower()
        }
    }
}

# One digest for the whole input set, stable across reordering and touch-only edits.
function Get-BuildInputsDigest($Inputs) {
    $lines = @($Inputs | Sort-Object { $_.Path.ToLower() } |
        ForEach-Object { $_.Path.ToLower() + '|' + $_.Sha256 })
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

# Compare two fingerprint lists by path and content only.
function Test-BuildInputsUnchanged {
    param($Expected, $Current)
    $expectedMap = @{}
    foreach ($entry in @($Expected)) { $expectedMap[$entry.Path.ToLower()] = $entry.Sha256 }
    $currentMap = @{}
    foreach ($entry in @($Current)) { $currentMap[$entry.Path.ToLower()] = $entry.Sha256 }
    if ($expectedMap.Count -ne $currentMap.Count) { return $false }
    foreach ($key in $expectedMap.Keys) {
        if (-not $currentMap.ContainsKey($key)) { return $false }
        if ($currentMap[$key] -ne $expectedMap[$key]) { return $false }
    }
    return $true
}

# Gowin writes the exact tool version into the PnR report header.
function Get-GowinToolVersion([string]$ReportPath) {
    if (-not $ReportPath -or -not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { return '' }
    $match = Select-String -LiteralPath $ReportPath -Pattern '<Tool Version>:\s*(.+?)\s*$' |
        Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
    return ''
}
