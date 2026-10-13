param(
    [ValidatePattern('^COM[0-9]+$')][string]$Port = 'COM13',
    [string]$LogPath = '',
    [switch]$SelfTest,
    [switch]$SmokeTest
)
$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot 'KeyboardCore.cs'
if ($SelfTest -or $SmokeTest) {
    Add-Type -Path $core -ReferencedAssemblies System.dll,System.Core.dll
    if ($SelfTest) { [PolyTouchPc.KeyboardChecks]::Run(); exit 0 }
    [PolyTouchPc.KeyboardChecks]::Smoke($Port)
    exit 0
}
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Use open-keyboard.cmd or Windows PowerShell -STA to open the keyboard.'
}
Add-Type -Path $core,(Join-Path $PSScriptRoot 'KeyboardWindow.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll
if (-not $LogPath) {
    $folder = Join-Path $PSScriptRoot '..\..\output\serial_keyboard'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $LogPath = Join-Path $folder ('keyboard-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
}
[PolyTouchPc.KeyboardWindow]::Open($Port, $LogPath)
