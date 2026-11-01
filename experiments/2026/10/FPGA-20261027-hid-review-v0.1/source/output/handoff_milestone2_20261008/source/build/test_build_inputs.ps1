# Self-checking test for the build input fingerprint (ASCII only).
# Proves that build identity is content-based: a same-length edit with the
# original timestamp preserved changes the fingerprint, while a touch-only
# change (new timestamp, same bytes) does not.
param([string]$WorkDir = '')

$ErrorActionPreference = 'Stop'
$buildDir = $PSScriptRoot
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $buildDir '..')).Path
. (Join-Path $buildDir 'profile_helpers.ps1')

if (-not $WorkDir) {
    $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-build-fp-' + [guid]::NewGuid().ToString('N'))
    $createdWorkDir = $true
} else {
    $createdWorkDir = $false
}
$scratch = Join-Path $WorkDir 'source'
$checks = 0
$failures = @()

function Assert-True([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) {
        $script:failures += $Message
        Write-Output ("FAIL {0}" -f $Message)
    }
}

function New-ScratchFile([string]$Root, [string]$Relative, [string]$Content) {
    $path = Join-Path $Root $Relative
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

try {
    $profile = Get-BuildProfile 'debug8usb'
    # Mirror the real input layout with dummy content so the test never touches
    # tracked sources.
    $rels = @(Get-Content -LiteralPath (Join-Path $buildDir 'sources.list') |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($rel in $rels) { New-ScratchFile $scratch $rel ("// scratch " + $rel + "`n") }
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'rtl/audio') -File |
             Where-Object Extension -In '.vh', '.hex', '.mi', '.mif') {
        New-ScratchFile $scratch ('rtl/audio/' + $item.Name) ("scratch " + $item.Name + "`n")
    }
    New-ScratchFile $scratch ('constraints/' + $profile.Cst) "scratch cst`n"
    New-ScratchFile $scratch ('constraints/' + $profile.Sdc) "scratch sdc`n"

    $before = @(Get-BuildInputs $profile $scratch)
    Assert-True ($before.Count -gt 100) ("fingerprint covers the whole input set (got {0})" -f $before.Count)
    Assert-True (@($before | Where-Object { $_.Sha256 -notmatch '^[0-9a-f]{64}$' }).Count -eq 0) `
        'every input carries a SHA256'

    $digestBefore = Get-BuildInputsDigest $before
    $again = @(Get-BuildInputs $profile $scratch)
    Assert-True (Test-BuildInputsUnchanged -Expected $before -Current $again) 'unchanged tree reports unchanged'
    Assert-True ((Get-BuildInputsDigest $again) -eq $digestBefore) 'digest is stable across scans'

    # Touch-only change: new timestamp, identical bytes. Content binding means
    # this must NOT invalidate the build.
    $touch = Join-Path $scratch 'rtl/top.v'
    (Get-Item -LiteralPath $touch).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(5)
    $touched = @(Get-BuildInputs $profile $scratch)
    Assert-True (Test-BuildInputsUnchanged -Expected $before -Current $touched) 'touch-only change keeps build valid'
    Assert-True ((Get-BuildInputsDigest $touched) -eq $digestBefore) 'touch-only change keeps the digest'

    # Same length, original timestamp, different bytes. This is the regression
    # that size+mtime checks used to miss.
    $path = Join-Path $scratch 'rtl/audio/shared_wavetable_engine.v'
    $original = [System.IO.File]::ReadAllBytes($path)
    $originalItem = Get-Item -LiteralPath $path
    $originalLength = $originalItem.Length
    $originalStamp = $originalItem.LastWriteTimeUtc
    $mutated = [byte[]]$original.Clone()
    $mutated[$mutated.Length - 2] = $mutated[$mutated.Length - 2] -bxor 0x01
    [System.IO.File]::WriteAllBytes($path, $mutated)
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = $originalStamp
    $afterItem = Get-Item -LiteralPath $path
    Assert-True ($afterItem.Length -eq $originalLength) 'mutation keeps the file length'
    Assert-True ($afterItem.LastWriteTimeUtc.Ticks -eq $originalStamp.Ticks) 'mutation keeps the timestamp'

    $mutatedInputs = @(Get-BuildInputs $profile $scratch)
    Assert-True (-not (Test-BuildInputsUnchanged -Expected $before -Current $mutatedInputs)) `
        'same-length same-timestamp edit is detected'
    Assert-True ((Get-BuildInputsDigest $mutatedInputs) -ne $digestBefore) 'same-length edit changes the digest'

    # Restoring the bytes must also restore the identity.
    [System.IO.File]::WriteAllBytes($path, $original)
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = $originalStamp
    $restored = @(Get-BuildInputs $profile $scratch)
    Assert-True (Test-BuildInputsUnchanged -Expected $before -Current $restored) 'restoring the bytes restores identity'

    if ($failures.Count -eq 0) {
        Write-Output ("PASS test_build_inputs: {0} checks, content-bound fingerprints" -f $checks)
        exit 0
    }
    Write-Output ("FAIL test_build_inputs: {0} of {1} checks failed" -f $failures.Count, $checks)
    exit 1
} finally {
    if ($createdWorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
