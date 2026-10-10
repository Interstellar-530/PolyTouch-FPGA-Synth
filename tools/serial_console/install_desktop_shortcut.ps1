# Recreate the desktop shortcut for the serial console.
#
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File install_desktop_shortcut.ps1
#
# Note: do not launch the console itself with -WindowStyle Hidden. Windows
# propagates SW_HIDE to the first top level window of the child process, so the
# WinForms window would be created hidden and the user would see nothing.

$ErrorActionPreference = 'Stop'

$consoleCmd = Join-Path $PSScriptRoot 'open_console.cmd'
if (-not (Test-Path -LiteralPath $consoleCmd)) {
    throw "launcher not found: $consoleCmd"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$linkPath = Join-Path $desktop '串口控制台.lnk'

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath       = $consoleCmd
$link.WorkingDirectory = $PSScriptRoot
$link.IconLocation     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
$link.Description      = 'PolyTouch FPGA Synth 串口控制台'
$link.Save()

Write-Output "shortcut created: $linkPath"
