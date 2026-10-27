<#
    [S3-AI | deepseek | 2026-10-14] i2s_tx 隔离综合入口。

    用 Gowin gw_sh 把 i2s_tx_top 作为顶层单独综合 16 位与 24 位两个变体，
    工程与报告写在 tmp/gowin_i2s_tx/，本脚本不烧录、不改生产工程与引脚约束。
    用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\build_i2s_tx.ps1 [-GwSh <gw_sh.exe>]
#>
param(
    [string]$GwSh = ''
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

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
    $match = $candidates | Sort-Object -Property FullName -Descending | Select-Object -First 1
    if ($match) { $GwSh = $match.FullName }
}

if (-not $GwSh -or -not (Test-Path -LiteralPath $GwSh -PathType Leaf)) {
    throw "gw_sh.exe not found. Pass -GwSh or set GOWIN_GW_SH."
}

$tcl = Join-Path $PSScriptRoot 'synth_i2s_tx.tcl'
if (-not (Test-Path -LiteralPath $tcl -PathType Leaf)) { throw "Build script not found: $tcl" }

Write-Output "Source root: $sourceRoot"
Write-Output "Gowin shell: $GwSh"
& $GwSh $tcl
exit $LASTEXITCODE
