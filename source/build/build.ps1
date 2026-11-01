param(
    [string]$GwSh = '',
    [ValidateSet('debug','standard','standard27','debug8','debug8g','debug8usb','hdmi')][string]$Profile = 'debug',
    [ValidateSet('IdleOnly','Strict')][string]$HostTimeoutPolicy = 'IdleOnly'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'profile_helpers.ps1')
$configuration = Get-BuildProfile $Profile
if ($HostTimeoutPolicy -eq 'Strict' -and $Profile -notin @('standard27','debug8usb')) { throw 'Strict policy is supported only by standard27/debug8usb.' }
$receiptSuffix = '.json'
if ($HostTimeoutPolicy -eq 'Strict') { $receiptSuffix = '.strict.json' }
$receipt = Join-Path $PSScriptRoot ('receipts/' + $Profile + $receiptSuffix)
# An unsuccessful attempt must never leave a previous build as the default.
if (Test-Path -LiteralPath $receipt) { Remove-Item -LiteralPath $receipt }
$inputs = @(Get-BuildInputs $configuration)

if (-not $GwSh) { $GwSh = $env:GOWIN_GW_SH }
if (-not $GwSh) {
    $candidates = @()
    foreach ($drive in @('C:\', 'D:\', 'E:\')) {
        $gowinDirs = Get-ChildItem -LiteralPath $drive -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and ($_.Name -match 'Gowin') }
        foreach ($dir in $gowinDirs) {
            $candidates += Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'gw_sh.exe' -ErrorAction SilentlyContinue |

                Where-Object { -not $_.PSIsContainer }
        }
    }
    $match = $candidates | Select-Object -First 1
    if ($match) { $GwSh = $match.FullName }
}

if (-not $GwSh -or -not (Test-Path -LiteralPath $GwSh -PathType Leaf)) {
    throw "gw_sh.exe not found. Pass -GwSh or set GOWIN_GW_SH."
}

$tcl = Join-Path $PSScriptRoot 'build_profile.tcl'
if (-not (Test-Path -LiteralPath $tcl -PathType Leaf)) {
    throw "Build script not found: $tcl"
}

Write-Output "Project root: $ProjectRoot"
Write-Output "Gowin shell : $GwSh"
$runId = (Get-Date -Format 'yyyyMMddTHHmmssfff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runDir = Join-Path $PSScriptRoot ($configuration.Directory + '/runs/' + $runId)
$fs = Join-Path $runDir 'instrument/impl/pnr/instrument.fs'
$entry = Join-Path $runDir 'entry.tcl'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
# Use a tiny per-run entry instead of mutating the checked-in Tcl scripts.
$tclPath = $tcl.Replace('\','/')
Set-Content -LiteralPath $entry -Encoding ASCII -Value "set profile $Profile`nsource {$tclPath}"
$oldRunDir = $env:FPGA_BUILD_RUN_DIR
$oldWrapper = $env:FPGA_BUILD_WRAPPER
$wrapperFile = ''
if ($Profile -in @('standard27','debug8usb')) {
    $template = Join-Path $PSScriptRoot ('isolated/' + $configuration.Top + '.v')
    $wrapperFile = Join-Path $runDir ($configuration.Top + '.v')
    $text = [System.IO.File]::ReadAllText($template, [System.Text.Encoding]::UTF8)
    $policyValue = 1
    if ($HostTimeoutPolicy -eq 'Strict') { $policyValue = 0 }
    $pattern = 'parameter integer HOST_KBD_TIMEOUT_POLICY = 1'
    if (-not $text.Contains($pattern)) { throw 'Policy wrapper template mismatch.' }
    $text = $text.Replace($pattern, ('parameter integer HOST_KBD_TIMEOUT_POLICY = ' + $policyValue))
    [System.IO.File]::WriteAllText($wrapperFile, $text, (New-Object System.Text.UTF8Encoding($false)))
}

try {
    $env:FPGA_BUILD_RUN_DIR = $runDir
    $env:FPGA_BUILD_WRAPPER = $wrapperFile
    Write-Output "Profile     : $Profile ($($configuration.Top))"
    & $GwSh $entry
    if ($LASTEXITCODE -ne 0) { throw "Gowin build failed: exit $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $fs -PathType Leaf) -or (Get-Item -LiteralPath $fs).Length -eq 0) {
        throw "No bitstream produced by this build: $fs"
    }
    $after = @(Get-BuildInputs $configuration)
    if (-not (Test-BuildInputsUnchanged -Expected $inputs -Current $after)) {
        throw 'Build inputs changed during compilation; rebuild before programming.'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $receipt) -Force | Out-Null
    $bitstream = Get-Item -LiteralPath $fs
    # Bind the receipt to the exact tool version and bitstream content as well.
    $toolVersion = Get-GowinToolVersion (Join-Path $runDir 'instrument/impl/pnr/instrument.rpt.txt')
    if ($toolVersion) { $versionSource = 'pnr_report' } else { $versionSource = 'unavailable' }
    [ordered]@{ Profile=$Profile; Top=$configuration.Top; Bitstream=$fs;
        BitstreamLength=$bitstream.Length; BitstreamModifiedUtc=$bitstream.LastWriteTimeUtc.Ticks;
        BitstreamSha256=(Get-FileHash -LiteralPath $fs -Algorithm SHA256).Hash.ToLower();
        TimeoutPolicy=$HostTimeoutPolicy; GeneratedWrapper=$wrapperFile;
        GeneratedWrapperSha256=$(if ($wrapperFile) { (Get-FileHash -LiteralPath $wrapperFile -Algorithm SHA256).Hash.ToLower() } else { '' });
        CompletedUtc=[DateTime]::UtcNow.ToString('o');
        Tool=[ordered]@{ Name='gw_sh'; Path=$GwSh; Version=$toolVersion; VersionSource=$versionSource };
        InputsDigest=(Get-BuildInputsDigest $inputs); Inputs=$inputs } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receipt -Encoding UTF8
    Write-Output "Bitstream   : $fs"
    Write-Output "Receipt     : $receipt"
} finally { $env:FPGA_BUILD_RUN_DIR = $oldRunDir; $env:FPGA_BUILD_WRAPPER = $oldWrapper }
