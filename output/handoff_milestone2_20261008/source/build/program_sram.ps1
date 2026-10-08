param(
    [string]$FsFile = '',
    [string]$Device = 'GW2A-18C',
    [int]$Operation = 4,
    [string]$Programmer = '',
    [string]$Cable = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $FsFile) {
    $builtFs = Join-Path $projectRoot 'impl\pnr\instrument.fs'
    $includedFs = Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path 'artifacts\instrument.fs'
    if (Test-Path -LiteralPath $builtFs -PathType Leaf) {
        $FsFile = $builtFs
    } elseif (Test-Path -LiteralPath $includedFs -PathType Leaf) {
        $FsFile = $includedFs
    } else {
        throw "Bitstream not found. Build first or pass -FsFile."
    }
}
$fs = (Resolve-Path -LiteralPath $FsFile).Path

if (-not $Programmer) { $Programmer = $env:GOWIN_PROGRAMMER }
if (-not $Programmer) {
    $candidates = @()
    foreach ($drive in @('C:\', 'D:\', 'E:\')) {
        $gowinDirs = Get-ChildItem -LiteralPath $drive -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and ($_.Name -match 'Gowin') }
        foreach ($dir in $gowinDirs) {
            $candidates += Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'programmer_cli.exe' -ErrorAction SilentlyContinue |

                Where-Object { -not $_.PSIsContainer }
        }
    }
    $match = $candidates | Select-Object -First 1
    if ($match) { $Programmer = $match.FullName }
}

if (-not $Programmer -or -not (Test-Path -LiteralPath $Programmer -PathType Leaf)) {
    throw "programmer_cli.exe not found. Pass -Programmer or set GOWIN_PROGRAMMER."
}

$programArgs = @(
    '--device', $Device,
    '--operation_index', [string]$Operation,
    '--fsFile', $fs
)
if ($Cable) {
    $programArgs += @('--cable', $Cable)
}

Write-Output "Programmer : $Programmer"
Write-Output "Device     : $Device"
Write-Output "Operation  : $Operation"
Write-Output "Bitstream  : $fs"
& $Programmer @programArgs
exit $LASTEXITCODE