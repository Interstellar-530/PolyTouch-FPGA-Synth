# Rebuild the checked-in ROM tables from their sources into a scratch directory
# and compare them byte for byte with the versioned files (ASCII only).
param(
    [string]$Python = '',
    [string]$WorkDir = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
$audio = Join-Path $repo 'output/handoff_milestone2_20261008/source/rtl/audio'
if (-not $Python) { $Python = Join-Path $repo 'tools\.venv-audio-analysis\Scripts\python.exe' }
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw "python not found: $Python" }
if (-not $WorkDir) { $WorkDir = Join-Path $repo 'tmp\regen_verify' }
$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)

$results = [ordered]@{}
$failures = 0

function Compare-Generated {
    param([string]$Name, [string]$Script, [string[]]$Extra, [System.Collections.IDictionary]$Summary)
    $out = Join-Path $WorkDir $Name
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    $log = Join-Path $WorkDir ($Name + '.log')
    $genArgs = @($Script, '--out-dir', $out) + $Extra
    & $Python @genArgs 2>&1 | Set-Content -LiteralPath $log -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        $Summary['exit'] = $LASTEXITCODE
        $Summary['error'] = 'generator failed'
        return 1
    }
    $files = @(Get-ChildItem -LiteralPath $out -File)
    $identical = 0
    $mismatched = @()
    foreach ($file in $files) {
        $reference = Join-Path $audio $file.Name
        if (-not (Test-Path -LiteralPath $reference -PathType Leaf)) {
            $mismatched += ('missing reference: ' + $file.Name)
            continue
        }
        if ((Get-FileHash -LiteralPath $reference -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
            $identical++
        } else {
            $mismatched += $file.Name
        }
    }
    $Summary['files'] = $files.Count
    $Summary['identical'] = $identical
    $Summary['mismatched'] = $mismatched
    $Summary['log'] = $log.Substring($repo.Length + 1)
    return ($mismatched.Count)
}

$results['epiano'] = [ordered]@{ script = 'tools/gen_epiano_bank.py' }
    $failures += Compare-Generated 'epiano' (Join-Path $repo 'tools\gen_epiano_bank.py') @() $results['epiano']

    $results['guitar_samples'] = [ordered]@{ script = 'tools/gen_guitar_samples_bank.py' }
    $failures += Compare-Generated 'guitar_samples' (Join-Path $repo 'tools\gen_guitar_samples_bank.py') @() $results['guitar_samples']

    # Legacy six-band generator: proves the explicit --out-dir path works; its
    # outputs intentionally differ from the versioned 36-table guitar bank.
    $legacy = Join-Path $WorkDir 'guitar_legacy'
    New-Item -ItemType Directory -Path $legacy -Force | Out-Null
    & $Python (Join-Path $repo 'tools\gen_guitar_bank.py') --out-dir $legacy 2>&1 |
        Set-Content -LiteralPath (Join-Path $WorkDir 'guitar_legacy.log') -Encoding UTF8
    $results['guitar_legacy'] = [ordered]@{
        script = 'tools/gen_guitar_bank.py'
        exit = $LASTEXITCODE
        files = @(Get-ChildItem -LiteralPath $legacy -File).Count
    }

    $summary = [ordered]@{
        python = $Python
        audio_dir = 'output/handoff_milestone2_20261008/source/rtl/audio'
        mismatch_count = $failures
        generators = $results
    }
    $summary | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $WorkDir 'summary.json') -Encoding UTF8
    Write-Output ($summary | ConvertTo-Json -Depth 6 -Compress)

    if ($failures -ne 0) {
        Write-Output ("FAIL regenerated tables differ: {0}" -f $failures)
        exit 1
    }
    Write-Output ('PASS regenerated tables are byte-identical: epiano {0}/{0}, guitar {1}/{1}' -f
        $results['epiano']['files'], $results['guitar_samples']['files'])
    exit 0
