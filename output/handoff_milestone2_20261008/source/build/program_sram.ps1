<#
    烧录脚本，带仿真门禁。

    默认流程是：先跑 sim\run_simulation.ps1，三个测试台全部通过才调用
    programmer_cli。这是项目规则，不是建议：任何 RTL 改动都必须先过仿真。

    -SkipSimulation 只为极端情况保留（例如仿真器本身不可用），使用时必须
    在调试日志里写明原因。
#>
param(
    [string]$FsFile = '',
    [string]$Device = 'GW2A-18C',
    [int]$Operation = 2,              # 2 = SRAM Program；这块板子不要用 4
    [string]$Programmer = '',
    [string]$Cable = '',
    [switch]$SkipSimulation
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if (-not $SkipSimulation) {
    Write-Output '=== 仿真门禁 ==='
    & (Join-Path $PSScriptRoot '..\sim\run_simulation.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw '仿真未通过，拒绝烧录。修复 RTL 后重跑。'
    }
} else {
    Write-Warning '跳过仿真门禁。按项目规则，这必须在调试日志里说明原因。'
}

if (-not $FsFile) {
    $builtFs = Join-Path $projectRoot 'impl\pnr\instrument.fs'
    $includedFs = Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path 'artifacts\instrument.fs'
    if (Test-Path -LiteralPath $builtFs -PathType Leaf) {
        $FsFile = $builtFs
    } elseif (Test-Path -LiteralPath $includedFs -PathType Leaf) {
        $FsFile = $includedFs
    } else {
        throw 'Bitstream not found. Build first or pass -FsFile.'
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
    throw 'programmer_cli.exe not found. Pass -Programmer or set GOWIN_PROGRAMMER.'
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
