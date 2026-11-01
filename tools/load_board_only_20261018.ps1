param([string]$Port='COM13')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$ev=Join-Path $root 'evidence/2026/10/FPGA-板载联调-20261018-v0.1'
$work=Join-Path $root 'tmp/board-only-20261018'
$summary=Get-Content -LiteralPath (Join-Path $ev 'validation-summary.json') -Raw | ConvertFrom-Json
if($summary.gate_exit -ne 0 -or $summary.board_only_sim_exit -ne 0){throw 'Simulation receipts failed'}
$gateExit=(Get-Content -LiteralPath (Join-Path $ev 'full-gate-exit.txt') -Raw).Trim()
$gateLog=Get-Content -LiteralPath (Join-Path $ev 'full-gate.log') -Raw -Encoding UTF8
if($gateExit -ne '0' -or $gateLog -notmatch '全部 \d+ 台正向测试台与 \d+ 个参数负例通过，允许烧录'){throw 'Complete simulation gate required'}
$bindings=Get-Content -LiteralPath (Join-Path $ev 'source_binding.json') -Raw | ConvertFrom-Json
foreach($binding in $bindings.PSObject.Properties){
    if((Get-FileHash -LiteralPath (Join-Path $root $binding.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $binding.Value){throw "Source changed: $($binding.Name)"}
}
$test=Join-Path $root 'source/sim/tb_audio_capture.v'
if((Get-FileHash -LiteralPath $test -Algorithm SHA256).Hash.ToLowerInvariant() -ne $summary.capture_test_sha256){throw 'Capture test changed'}
$fs=Join-Path $ev 'board_only.fs'
if((Get-FileHash -LiteralPath $fs -Algorithm SHA256).Hash.ToLowerInvariant() -ne $summary.bitstream_sha256){throw 'Bitstream hash mismatch'}
New-Item -ItemType Directory -Path $work -Force | Out-Null
$asciiFs=Join-Path $work 'board_only.fs'
Copy-Item -LiteralPath $fs -Destination $asciiFs
if((Get-FileHash -LiteralPath $asciiFs -Algorithm SHA256).Hash.ToLowerInvariant() -ne $summary.bitstream_sha256){throw 'Working copy mismatch'}
$cli='E:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe'
$programText=(& $cli --device GW2A-18C --operation_index 2 --fsFile $asciiFs 2>&1 | Out-String)
$programExit=$LASTEXITCODE
$programText | Set-Content -LiteralPath (Join-Path $ev 'sram-program.log') -Encoding UTF8
@{exit_code=$programExit;operation_index=2;bitstream_sha256=$summary.bitstream_sha256;time_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ev 'sram-program-result.json') -Encoding UTF8
$programText
if($programExit -ne 0 -or $programText -notmatch 'Finished' -or $programText -match 'Error:'){throw 'SRAM programming did not succeed'}
$live=Get-Content -LiteralPath (Join-Path $ev 'live-results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$live.new_firmware_programmed=$true
$live | Add-Member -NotePropertyName new_firmware_uart_check -NotePropertyValue 'pending' -Force
$live | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ev 'live-results.json') -Encoding UTF8
$serial=New-Object System.IO.Ports.SerialPort($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.ReadTimeout=2500
$serial.NewLine="`n"
$rows=New-Object System.Collections.Generic.List[string]
try{
    $serial.Open()
    $serial.DiscardInBuffer()
    foreach($command in @('D0','M0','X','T0','T255','T0')){
        $serial.Write($command+"`r")
        $reply=$serial.ReadLine().Trim()
        $rows.Add("$command -> $reply")
        if($reply -ne 'OK'){throw "Unexpected response: $command -> $reply"}
    }
}finally{
    if($serial.IsOpen){$serial.Close()};$serial.Dispose()
    $rows | Set-Content -LiteralPath (Join-Path $ev 'new-firmware-uart-check.log') -Encoding UTF8
}
$readText=(& $cli --device GW2A-18C --operation_index 0 2>&1 | Out-String)
$readExit=$LASTEXITCODE
$readText | Set-Content -LiteralPath (Join-Path $ev 'sram-readback.log') -Encoding UTF8
if($readExit -ne 0 -or $readText -notmatch 'Finished'){throw 'JTAG code read failed'}
if($readText -notmatch ('(?im)User\s*Code[^\r\n]*'+[regex]::Escape($summary.expected_user_code)+'\b')){throw 'Device user code does not match the target bitstream'}
$live=Get-Content -LiteralPath (Join-Path $ev 'live-results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$live.new_firmware_programmed=$true
$live | Add-Member -NotePropertyName new_firmware_uart_check -NotePropertyValue 'PASS' -Force
$live | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ev 'live-results.json') -Encoding UTF8
$rows
$readText
