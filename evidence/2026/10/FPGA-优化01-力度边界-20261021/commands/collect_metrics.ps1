# Temp: extract resource/timing metrics from a debug8usb build receipt (ASCII only).
param([string]$Receipt, [string]$OutFile)
$ErrorActionPreference = 'Stop'
$r = Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json
$pnr = Split-Path -Parent $r.Bitstream
$rpt = Get-Content -LiteralPath (Join-Path $pnr 'instrument.rpt.txt') -Raw
$tim = Get-Content -LiteralPath (Join-Path $pnr 'instrument_tr_content.html') -Raw

function Get-Res([string]$name) {
    $m = [regex]::Match($rpt, '(?m)^\s*' + [regex]::Escape($name) + '\s*\|\s*([\d.]+)')
    if (-not $m.Success) { throw "missing resource $name" }
    return [double]$m.Groups[1].Value
}
function Get-Cells([string]$anchor) {
    $marker = 'name="' + $anchor + '"'
    $i = $tim.IndexOf($marker)
    if ($i -lt 0) { throw "missing timing section $anchor" }
    $sec = $tim.Substring($i)
    $end = $sec.IndexOf('</table>')
    if ($end -ge 0) { $sec = $sec.Substring(0, $end) }
    $rows = @()
    foreach ($row in [regex]::Matches($sec, '(?s)<tr>(.*?)</tr>')) {
        $vals = @()
        foreach ($cell in [regex]::Matches($row.Groups[1].Value, '(?s)<t[dh][^>]*>(.*?)</t[dh]>')) {
            $vals += (($cell.Groups[1].Value -replace '<[^>]*>', '') -replace '\s+', ' ').Trim()
        }
        $rows += ,$vals
    }
    return $rows
}

$inputs = @{}
foreach ($row in $r.Inputs) {
    $inputs[$row.Path] = (Get-FileHash -LiteralPath $row.Path -Algorithm SHA256).Hash.ToLower()
}
$fmax = Get-Cells 'Max_Frequency_Report'
$setup = (Get-Cells 'Setup_Slack_Table')[1]
$hold = (Get-Cells 'Hold_Slack_Table')[1]
$tns = Get-Cells 'Total_Negative_Slack_Report'
$result = [ordered]@{
    profile = 'debug8usb'; part = 'GW2A-LV18PG256C8/I7'; device_version = 'C'
    logic = Get-Res 'Logic'; logic_available = 20736
    registers = Get-Res 'Register'
    bsram = Get-Res 'BSRAM'; bsram_available = 46
    dsp_units = Get-Res 'DSP'
    mult18x18 = Get-Res '--MULT18X18'; mult9x9 = Get-Res '--MULT9X9'; multalu36x18 = Get-Res '--MULTALU36X18'
    clock_mhz = 27.0
    fmax = $fmax
    tns = $tns
    worst_setup = $setup
    worst_hold = $hold
    bitstream = $r.Bitstream
    bitstream_sha256 = (Get-FileHash -LiteralPath $r.Bitstream -Algorithm SHA256).Hash.ToLower()
    inputs_sha256 = $inputs
    build_inputs_checked_during_build = $true
    hardware_programmed = $false
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
