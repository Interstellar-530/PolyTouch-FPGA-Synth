param(
    [string]$GwSh = '',
    [ValidateSet('debug','standard')][string]$Profile = 'debug'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'profile_helpers.ps1')
$configuration = Get-BuildProfile $Profile
$receipt = Join-Path $PSScriptRoot ('receipts/' + $Profile + '.json')
# An unsuccessful attempt must never leave a previous build as the default.
if (Test-Path -LiteralPath $receipt) { Remove-Item -LiteralPath $receipt }
$inputs = @(Get-BuildInputs $configuration)

if (-not $GwSh) { $GwSh = $env:GOWIN_GW_SH }
if (-not $GwSh) {
    $candidates = @()
    foreach ($drive in @('C:\', 'D:\', 'E:\')) {
        $gowinDirs = Get-ChildItem -LiteralPath $drive -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and ($_.Name -match 'Gowin') }
        foreach ($dir in $gowinDirs) {
            $candidates += Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'gw_sh.exe' -ErrorAction SilentlyContinue |

                Where-Object { -not $_.PSIsContainer }
        }
    }
    $match = $candidates | Select-Object -First 1
    if ($match) { $GwSh = $match.FullName }
}

if (-not $GwSh -or -not (Test-Path -LiteralPath $GwSh -PathType Leaf)) {
    throw "gw_sh.exe not found. Pass -GwSh or set GOWIN_GW_SH."
}

$tcl = Join-Path $PSScriptRoot 'build_profile.tcl'
if (-not (Test-Path -LiteralPath $tcl -PathType Leaf)) {
    throw "Build script not found: $tcl"
}

Write-Output "Project root: $ProjectRoot"
Write-Output "Gowin shell : $GwSh"
$runId = (Get-Date -Format 'yyyyMMddTHHmmssfff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runDir = Join-Path $PSScriptRoot ($configuration.Directory + '/runs/' + $runId)
$fs = Join-Path $runDir 'instrument/impl/pnr/instrument.fs'
$entry = Join-Path $runDir 'entry.tcl'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
# Use a tiny per-run entry instead of mutating the checked-in Tcl scripts.
$tclPath = $tcl.Replace('\','/')
Set-Content -LiteralPath $entry -Encoding ASCII -Value "set profile $Profile`nsource {$tclPath}"
$oldRunDir = $env:FPGA_BUILD_RUN_DIR
try {
    $env:FPGA_BUILD_RUN_DIR = $runDir
    Write-Output "Profile     : $Profile ($($configuration.Top))"
    & $GwSh $entry
    if ($LASTEXITCODE -ne 0) { throw "Gowin build failed: exit $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $fs -PathType Leaf) -or (Get-Item -LiteralPath $fs).Length -eq 0) {
        throw "No bitstream produced by this build: $fs"
    }
    $after = @(Get-BuildInputs $configuration)
    if (($inputs | ConvertTo-Json -Compress) -ne ($after | ConvertTo-Json -Compress)) {
        throw 'Build inputs changed during compilation; rebuild before programming.'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $receipt) -Force | Out-Null
    $bitstream = Get-Item -LiteralPath $fs
    [ordered]@{ Profile=$Profile; Top=$configuration.Top; Bitstream=$fs;
        BitstreamLength=$bitstream.Length; BitstreamModifiedUtc=$bitstream.LastWriteTimeUtc.Ticks;
        CompletedUtc=[DateTime]::UtcNow.ToString('o'); Inputs=$inputs } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receipt -Encoding UTF8
    Write-Output "Bitstream   : $fs"
    Write-Output "Receipt     : $receipt"
} finally { $env:FPGA_BUILD_RUN_DIR = $oldRunDir }
