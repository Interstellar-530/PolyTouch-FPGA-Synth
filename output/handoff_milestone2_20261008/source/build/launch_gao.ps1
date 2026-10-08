param(
    [string]$GaoFile = '',
    [string]$FsFile = '',
    [string]$Family = 'GW2A',
    [string]$Device = 'GW2A-18C',
    [string]$Analyzer = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if (-not $GaoFile) {
    $GaoFile = Join-Path $projectRoot 'rtl\gao_top.rao'
}
if (-not (Test-Path -LiteralPath $GaoFile -PathType Leaf)) {
    throw "GAO configuration not found: $GaoFile"
}
$gao = (Resolve-Path -LiteralPath $GaoFile).Path

if ($FsFile) {
    if (-not (Test-Path -LiteralPath $FsFile -PathType Leaf)) {
        throw "Bitstream not found: $FsFile"
    }
    $FsFile = (Resolve-Path -LiteralPath $FsFile).Path
}

if (-not $Analyzer) { $Analyzer = $env:GOWIN_GAO_ANALYZER }
if (-not $Analyzer) {
    $candidates = @()
    foreach ($drive in @('C:\', 'D:\', 'E:\')) {
        $gowinDirs = Get-ChildItem -LiteralPath $drive -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and ($_.Name -match 'Gowin') }
        foreach ($dir in $gowinDirs) {
            $candidates += Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'gao_analyzer.exe' -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer }
        }
    }
    $match = $candidates | Select-Object -First 1
    if ($match) { $Analyzer = $match.FullName }
}

if (-not $Analyzer -or -not (Test-Path -LiteralPath $Analyzer -PathType Leaf)) {
    throw "gao_analyzer.exe not found. Pass -Analyzer or set GOWIN_GAO_ANALYZER."
}

$analyzerArgs = @('-gao', "`"$gao`"", '-family', $Family, '-device', $Device)
if ($FsFile) {
    $analyzerArgs += @('-fs', "`"$FsFile`"")
}

Write-Output "GAO analyzer : $Analyzer"
Write-Output "GAO config   : $gao"
Write-Output "Family/device: $Family / $Device"
if ($FsFile) { Write-Output "Bitstream    : $FsFile" }

$process = Start-Process -FilePath $Analyzer -ArgumentList $analyzerArgs `
    -WorkingDirectory (Split-Path -Parent $Analyzer) -PassThru
Write-Output "GAO process  : $($process.Id)"
