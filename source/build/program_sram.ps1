<#
    烧录脚本，带仿真门禁。

    默认流程是：先跑 sim\run_simulation.ps1，所选门禁（默认Quick，可选Full）通过才调用
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
    [switch]$SkipSimulation,
    [ValidateSet('Quick','Full')][string]$SimulationSuite = 'Quick',
    [ValidateSet('IdleOnly','Strict')][string]$HostTimeoutPolicy = 'IdleOnly',
    [ValidateSet('debug','standard','standard27','debug8','debug8g','debug8usb')][string]$Profile = 'debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'profile_helpers.ps1')

if (-not $SkipSimulation) {
    Write-Output '=== 仿真门禁 ==='
    & (Join-Path $PSScriptRoot '..\sim\run_simulation.ps1') -Suite $SimulationSuite
    if ($LASTEXITCODE -ne 0) {
        throw '仿真未通过，拒绝烧录。修复 RTL 后重跑。'
    }
} else {
    Write-Warning '跳过仿真门禁。按项目规则，这必须在调试日志里说明原因。'
}

if (-not $FsFile) {
    $receiptSuffix = '.json'
    if ($HostTimeoutPolicy -eq 'Strict') { $receiptSuffix = '.strict.json' }
    $receiptPath = Join-Path $PSScriptRoot ('receipts/' + $Profile + $receiptSuffix)
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "No successful $Profile build receipt. Run build.ps1 -Profile $Profile first, or explicitly pass -FsFile."
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $configuration = Get-BuildProfile $Profile
    if ($receipt.TimeoutPolicy -ne $HostTimeoutPolicy) { throw 'Timeout policy differs from the build receipt; rebuild/select the matching policy.' }
    if ($receipt.GeneratedWrapper) {
        if ((Get-FileHash -LiteralPath $receipt.GeneratedWrapper -Algorithm SHA256).Hash.ToLower() -ne $receipt.GeneratedWrapperSha256) {
            throw 'Generated wrapper changed after build; rebuild first.'
        }
    }
    $inputs = @(Get-BuildInputs $configuration)
    if ($receipt.Profile -ne $Profile -or $receipt.Top -ne $configuration.Top -or
        -not (Test-BuildInputsUnchanged -Expected $receipt.Inputs -Current $inputs)) {
        throw "Build inputs differ from the successful $Profile build; rebuild first."
    }
    $FsFile = $receipt.Bitstream
    $bitstream = Get-Item -LiteralPath $FsFile -ErrorAction Stop
    if ($receipt.BitstreamSha256) {
        if ((Get-FileHash -LiteralPath $FsFile -Algorithm SHA256).Hash.ToLower() -ne
            $receipt.BitstreamSha256.ToLower()) {
            throw 'Bitstream changed after the successful build; rebuild first or explicitly pass -FsFile.'
        }
    } elseif ($bitstream.Length -ne $receipt.BitstreamLength -or
        $bitstream.LastWriteTimeUtc.Ticks -ne $receipt.BitstreamModifiedUtc) {
        throw 'Bitstream changed after the successful build; rebuild first or explicitly pass -FsFile.'
    }
} else {
    Write-Warning 'Explicit -FsFile selected; confirm its audio profile and physical wiring.'
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
