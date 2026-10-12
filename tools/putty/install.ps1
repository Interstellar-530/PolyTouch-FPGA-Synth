param()
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot '..\vendor\putty-0.85'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$expected = @{
    'putty.exe' = 'd01fdb5aae8f112526040a39b0bfb9e27d813003178645e65f8d1cfdb2a26c87'
    'plink.exe' = '969f36879d5716aa1a9811f43a6a6510e8f08372dbeb9695b810b9c776f39c75'
}
foreach ($name in @('putty.exe','plink.exe')) {
    $file = Join-Path $destination $name
    Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/0.85/w64/$name" -OutFile $file
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $expected[$name]) { throw "Official SHA256 mismatch: $name" }
    Write-Output "$name SHA256=$hash VERIFIED"
}
Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/0.85/sha256sums' -OutFile (Join-Path $destination 'official-sha256sums.txt')
Invoke-WebRequest -Uri 'https://www.chiark.greenend.org.uk/~sgtatham/putty/licence.html' -OutFile (Join-Path $destination 'LICENCE.html')
& (Join-Path $destination 'plink.exe') -V
if ($LASTEXITCODE -ne 0) { throw 'Plink version check failed' }
