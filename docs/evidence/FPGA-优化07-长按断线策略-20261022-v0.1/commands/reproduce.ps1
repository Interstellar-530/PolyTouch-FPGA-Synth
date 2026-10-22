param(
    [string]$Iverilog = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe',
    [string]$Vvp = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe',
    [string]$GwSh = 'D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe',
    [switch]$RunBuild,
    [switch]$KeepTemp
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'output\handoff_milestone2_20261008\source')).Path
$tempRoot = Join-Path $repoRoot 'tmp\optimization07-repro'
if (Test-Path -LiteralPath $tempRoot) {
    if (-not $tempRoot.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean outside repository: $tempRoot"
    }
    Write-Output "Cleaning prior temp directory: $tempRoot"
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$env:PATH = (Split-Path -Parent $Iverilog) + ';' + $env:PATH
Push-Location $sourceRoot
try {
    $hostSrc = @('rtl\audio\kbd_uart_rx.v','rtl\audio\ch9350_rx.v','rtl\audio\hid_keymap.v','rtl\audio\host_kbd_input.v')
    $out = Join-Path $tempRoot 'tb_host_kbd_timeout.vvp'
    & $Iverilog -g2012 -s tb_host_kbd_timeout -I . -o $out sim\tb_host_kbd_timeout.v @hostSrc
    if ($LASTEXITCODE -ne 0) { throw 'tb_host_kbd_timeout compile failed' }
    & $Vvp $out
    if ($LASTEXITCODE -ne 0) { throw 'tb_host_kbd_timeout run failed' }

    $out = Join-Path $tempRoot 'tb_host_kbd.vvp'
    & $Iverilog -g2012 -s tb_host_kbd -I . -o $out sim\tb_host_kbd.v @hostSrc
    if ($LASTEXITCODE -ne 0) { throw 'tb_host_kbd compile failed' }
    & $Vvp $out
    if ($LASTEXITCODE -ne 0) { throw 'tb_host_kbd run failed' }

    $audioSources = @(Get-ChildItem -LiteralPath 'rtl/audio' -Filter '*.v' | ForEach-Object FullName)
    $out = Join-Path $tempRoot 'tb_top_host_ctrl.vvp'
    $args = @('-g2012','-s','tb_top_host_ctrl','-I','.','-o',$out,'sim\tb_top_host_ctrl.v') + $audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v')
    & $Iverilog @args
    if ($LASTEXITCODE -ne 0) { throw 'tb_top_host_ctrl compile failed' }
    & $Vvp $out
    if ($LASTEXITCODE -ne 0) { throw 'tb_top_host_ctrl run failed' }

    if ($RunBuild) {
        & '.\build\build.ps1' -Profile standard27 -GwSh $GwSh
        if ($LASTEXITCODE -ne 0) { throw 'standard27 build failed' }
        & '.\build\build.ps1' -Profile debug8usb -GwSh $GwSh
        if ($LASTEXITCODE -ne 0) { throw 'debug8usb build failed' }
    }
}
finally {
    Pop-Location
    if (-not $KeepTemp) {
        if (-not $tempRoot.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean outside repository: $tempRoot"
        }
        Write-Output "Cleaning temp directory: $tempRoot"
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
