param([string]$OutputPath)
$results=[ordered]@{
 uart_115200_ms=110.0/115200*1000
 uart_300000_ms=110.0/300000*1000
 uart_saving_ms=(110.0/115200-110.0/300000)*1000
 target_keyboard_path_ms=0.5+1.0+(110.0/300000*1000)+0.1+(3.5/48000*1000)+([Math]::Ceiling(0.9*65535/3072)/48000*1000)+0.35
}
foreach($sampleRate in @(46875,48000)){
 $results["dac_${sampleRate}_normal_ms"]=20.0/$sampleRate*1000
 $results["dac_${sampleRate}_low_ms"]=3.5/$sampleRate*1000
 $results["dac_${sampleRate}_saving_ms"]=16.5/$sampleRate*1000
 foreach($step in @(140,1536,2048,3072)){
  $results["attack_${sampleRate}_${step}_full_ms"]=[Math]::Ceiling(65535.0/$step)/$sampleRate*1000
  $results["attack_${sampleRate}_${step}_90_ms"]=[Math]::Ceiling(0.9*65535/$step)/$sampleRate*1000
 }
}
$results | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output ('Conditional target keyboard budget: '+$results.target_keyboard_path_ms+' ms; not measured.')
