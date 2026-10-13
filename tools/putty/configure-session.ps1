$ErrorActionPreference = 'Stop'

# PuTTY stores FORCE_ON as 0 for these two tri-state settings.
# Use a dedicated session so other PuTTY connections keep their own settings.
$path = 'HKCU:\Software\SimonTatham\PuTTY\Sessions\PolyTouch-COM13'
if (-not (Test-Path -LiteralPath $path)) {
    New-Item -Path $path -Force | Out-Null
}
$settings = @{
    Protocol           = 'serial'
    HostName           = 'COM13'
    SerialLine         = 'COM13'
    SerialSpeed        = 115200
    SerialDataBits     = 8
    SerialStopHalfbits = 2
    SerialParity       = 0
    SerialFlowControl  = 0
    LocalEcho          = 0
    LocalEdit          = 0
}
foreach ($entry in $settings.GetEnumerator()) {
    $type = if ($entry.Value -is [string]) { 'String' } else { 'DWord' }
    New-ItemProperty -LiteralPath $path -Name $entry.Key -Value $entry.Value -PropertyType $type -Force | Out-Null
}
$saved = Get-ItemProperty -LiteralPath $path
foreach ($entry in $settings.GetEnumerator()) {
    if ($saved.PSObject.Properties[$entry.Key].Value -ne $entry.Value) {
        throw "PuTTY PolyTouch-COM13 session verification failed: $($entry.Key)"
    }
}
Write-Output 'PuTTY PolyTouch-COM13: 115200 8N1, local echo and line editing on'
