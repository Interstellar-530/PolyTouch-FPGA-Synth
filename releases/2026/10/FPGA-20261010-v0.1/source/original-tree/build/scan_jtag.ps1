param(
    [string]$Programmer = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Programmer) { $Programmer = $env:GOWIN_PROGRAMMER }
if (-not $Programmer) {
    $candidates = @()
    foreach ($drive in @('C:\', 'D:\', 'E:\')) {
        $gowinDirs = Get-ChildItem -LiteralPath $drive -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and ($_.Name -match 'Gowin') }
        foreach ($dir in $gowinDirs) {
            $candidates += Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'programmer_cli.exe' -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer }
        }
    }
    $match = $candidates | Select-Object -First 1
    if ($match) { $Programmer = $match.FullName }
}

if (-not $Programmer -or -not (Test-Path -LiteralPath $Programmer -PathType Leaf)) {
    throw "programmer_cli.exe not found. Pass -Programmer or set GOWIN_PROGRAMMER."
}

Write-Output "Gowin programmer: $Programmer"
& $Programmer --scan-cables
exit $LASTEXITCODE