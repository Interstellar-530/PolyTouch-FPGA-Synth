param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
# Use Windows PowerShell 5.1, matching keyboard.ps1's .NET Framework runtime.
Add-Type -Path (Join-Path $PSScriptRoot 'KeyboardCore.cs'),(Join-Path $PSScriptRoot 'DashboardPanel.cs'),(Join-Path $PSScriptRoot 'KeyboardWindow.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll
$form = New-Object PolyTouchPc.KeyboardWindow('COM13','')
try {
    # Create child handles without Show(): no Shown/ConnectPort event is fired.
    $null = $form.Handle
    foreach ($control in $form.Controls) { $null = $control.Handle }
    $form.PerformLayout()
    $bitmap = New-Object Drawing.Bitmap($form.Width,$form.Height)
    try {
        $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
        $bitmap.Save([IO.Path]::GetFullPath($OutputPath))
    } finally { $bitmap.Dispose() }
    Write-Output 'PASS: GUI compiled and rendered without opening a serial connection.'
} finally { $form.Dispose() }
