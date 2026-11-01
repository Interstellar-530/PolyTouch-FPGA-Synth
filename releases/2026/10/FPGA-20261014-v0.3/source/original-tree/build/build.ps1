param(
    [string]$GwSh = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

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

$tcl = Join-Path $PSScriptRoot 'build_instrument.tcl'
if (-not (Test-Path -LiteralPath $tcl -PathType Leaf)) {
    throw "Build script not found: $tcl"
}

Write-Output "Project root: $ProjectRoot"
Write-Output "Gowin shell : $GwSh"
& $GwSh $tcl
exit $LASTEXITCODE