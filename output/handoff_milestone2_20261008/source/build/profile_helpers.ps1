function Get-BuildProfile([string]$Name) {
    $row = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'profiles.tsv') |
        Where-Object { ($_ -split "`t")[0] -eq $Name } | Select-Object -First 1
    if (-not $row) { throw "Unknown build profile: $Name" }
    $parts = $row -split "`t"
    [pscustomobject]@{ Name=$parts[0]; Directory=$parts[1]; Top=$parts[2]; Cst=$parts[3]; Sdc=$parts[4] }
}

function Get-BuildInputs($Profile) {
    $sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $paths = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'sources.list') |
        ForEach-Object { Join-Path $sourceRoot $_ })
    # Include ROM data and headers, even when not added as synthesis source files.
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'rtl/audio') -File |
        Where-Object Extension -In '.vh', '.hex', '.mi', '.mif' | ForEach-Object FullName)
    $paths += @('profiles.tsv','sources.list','build_profile.tcl','profile_helpers.ps1','build.ps1',
        ('isolated/' + $Profile.Top + '.v')) | ForEach-Object { Join-Path $PSScriptRoot $_ }
    $paths += Join-Path $sourceRoot ('constraints/' + $Profile.Cst)
    $paths += Join-Path $sourceRoot ('constraints/' + $Profile.Sdc)
    $paths | Sort-Object -Unique | ForEach-Object {
        $item = Get-Item -LiteralPath $_ -ErrorAction Stop
        [pscustomobject]@{ Path=$item.FullName; Length=$item.Length; ModifiedUtc=$item.LastWriteTimeUtc.Ticks }
    }
}
