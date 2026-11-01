param([string]$Port='COM13')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$ev=Join-Path $root 'evidence/2026/10/FPGA-板载联调-20261018-v0.1'
$serial=New-Object System.IO.Ports.SerialPort($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.ReadTimeout=2500
$serial.NewLine="`n"
$rows=New-Object System.Collections.Generic.List[string]
function Send-Command([string]$command){
    $serial.Write($command+"`r")
    $reply=$serial.ReadLine().Trim()
    $rows.Add(([DateTime]::UtcNow.ToString('o')+" $command -> $reply"))
    if($reply -ne 'OK'){throw "Unexpected response: $command -> $reply"}
}
try{
    $serial.Open()
    $serial.DiscardInBuffer()
    foreach($command in @('D0','X','M0','T0')){Send-Command $command}
    Send-Command 'M1';Send-Command 'N69'
    Start-Sleep -Seconds 5
    Send-Command 'T255'
    Start-Sleep -Seconds 5
    Send-Command 'T0'
    Start-Sleep -Seconds 5
    Send-Command 'O69'
    Start-Sleep -Seconds 1
    Send-Command 'M0'
}finally{
    if($serial.IsOpen){
        $serial.Write("M0`rX`r")
        $serial.Close()
    }
    $serial.Dispose()
    $rows | Set-Content -LiteralPath (Join-Path $ev 'new-firmware-live-timbre.log') -Encoding UTF8
}
$rows
