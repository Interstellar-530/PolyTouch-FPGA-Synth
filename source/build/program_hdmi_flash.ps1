# Explicit persistent Flash update for the HDMI production profile.
# Operation 37 is the board's previously verified GAO-Bridge erase/program/verify.
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDir,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [string]$Programmer = 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'profile_helpers.ps1')
New-Item -ItemType Directory -Force $EvidenceDir,$WorkDir | Out-Null
$EvidenceDir=(Resolve-Path -LiteralPath $EvidenceDir).Path
$WorkDir=(Resolve-Path -LiteralPath $WorkDir).Path
$receiptPath=Join-Path $PSScriptRoot 'receipts/hdmi.json'
$receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$profile=Get-BuildProfile 'hdmi'
function Assert-Receipt {
    if($receipt.Profile -ne 'hdmi' -or $receipt.Top -ne $profile.Top){throw 'Wrong profile receipt'}
    if(-not (Test-BuildInputsUnchanged -Expected $receipt.Inputs -Current @(Get-BuildInputs $profile))){throw 'Sources differ from built HDMI image'}
    if((Get-FileHash -LiteralPath $receipt.Bitstream -Algorithm SHA256).Hash.ToLower() -ne $receipt.BitstreamSha256){throw 'Bitstream checksum mismatch'}
}
Assert-Receipt
$header=Get-Content -LiteralPath $receipt.Bitstream -TotalCount 20 | Out-String
$codeMatch=[regex]::Match($header,'//UserCode:\s*(0x[0-9A-Fa-f]+)')
if(-not $codeMatch.Success){throw 'Missing bitstream user code'}
$expectedCode=$codeMatch.Groups[1].Value
$timingPath=Join-Path (Split-Path $receipt.Bitstream) 'instrument_tr_content.html'
$timing=[Net.WebUtility]::HtmlDecode([regex]::Replace((Get-Content -LiteralPath $timingPath -Raw),'<[^>]+>',' '))
foreach($kind in @('Setup','Hold')){
    $m=[regex]::Match($timing,('Numbers of '+$kind+' Violated Endpoints\s+(\d+)'))
    if(-not $m.Success -or [int]$m.Groups[1].Value -ne 0){throw "$kind timing has violated endpoints or cannot be verified; refusing Flash write"}
}
$sim=Join-Path $PSScriptRoot '../sim/run_simulation.ps1'
& $sim -Suite Quick -TimeoutSeconds 240 -BuildDir (Join-Path $WorkDir 'quick') -MetricsDir (Join-Path $EvidenceDir 'quick') -AudioCaptureDir (Join-Path $WorkDir 'audio')
if($LASTEXITCODE -ne 0){throw 'Quick simulation failed; refusing Flash write'}
# Quick includes current production, arrangement, UI and video timing checks.
Assert-Receipt
Copy-Item -LiteralPath $receiptPath -Destination (Join-Path $EvidenceDir 'hdmi-build-receipt.json')
$before=(& $Programmer --device GW2A-18C --operation_index 0 2>&1 | Out-String)
$before | Set-Content (Join-Path $EvidenceDir 'device-before.log')
if($LASTEXITCODE -ne 0 -or $before -notmatch 'Finished' -or $before -notmatch '0x0000081B'){throw 'Board read failed or wrong device'}
$program=(& $Programmer --device GW2A-18C --operation_index 37 --fsFile $receipt.Bitstream 2>&1 | Out-String)
$programExit=$LASTEXITCODE
$program | Set-Content (Join-Path $EvidenceDir 'program-flash.log')
if($programExit -ne 0 -or $program -notmatch 'Program and Verify flash successfully' -or $program -notmatch 'Finished'){throw 'Flash verification failed'}
$reload=(& $Programmer --device GW2A-18C --operation_index 1 2>&1 | Out-String)
$reload | Set-Content (Join-Path $EvidenceDir 'reload-from-flash.log')
if($LASTEXITCODE -ne 0 -or $reload -notmatch 'Finished'){throw 'Reload from Flash failed'}
# Bound startup wait, then independent ID/user-code read; do not pass an FS image.
Start-Sleep -Seconds 5
$after=(& $Programmer --device GW2A-18C --operation_index 0 2>&1 | Out-String)
$after | Set-Content (Join-Path $EvidenceDir 'device-after.log')
if($LASTEXITCODE -ne 0 -or $after -notmatch 'Finished'){throw 'Read after Flash reload failed'}
if($after -notmatch ('(?im)User\s*Code[^\r\n]*'+[regex]::Escape($expectedCode)+'\b')){throw 'User code after Flash reload differs from target image'}
[ordered]@{Profile='hdmi';Operation=37;Verified=$true;Reloaded=$true;Bitstream=$receipt.Bitstream;
    Sha256=$receipt.BitstreamSha256;UserCode=$expectedCode;CompletedUtc=[DateTime]::UtcNow.ToString('o');
    ColdPowerCycleTested=$false} | ConvertTo-Json | Set-Content (Join-Path $EvidenceDir 'program-result.json')
Write-Output 'PASS: HDMI Flash erased/programmed/verified, reloaded and independently read.'
$after


