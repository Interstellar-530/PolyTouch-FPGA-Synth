param(
    [ValidatePattern('^COM[0-9]+$')][string]$Port = 'COM13',
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(M[01]|D[01]|X|[NO][0-9]{1,3})$')][string]$Command,
    [ValidateRange(100,30000)][int]$TimeoutMs = 5000
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\vendor\putty-0.85\plink.exe')).Path
$process = [System.Diagnostics.Process]::new()
$process.StartInfo.FileName = $exe
$process.StartInfo.Arguments = "-serial $Port -sercfg 115200,8,n,1,N -batch"
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.CreateNoWindow = $true
$process.StartInfo.RedirectStandardInput = $true
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$started = $false
try {
    if (-not $process.Start()) { throw 'Cannot start Plink' }
    $started = $true
    $errors = $process.StandardError.ReadToEndAsync()
    $reply = $process.StandardOutput.ReadLineAsync()
    Start-Sleep -Milliseconds 200
    if ($process.HasExited) { throw "Plink exited: $($errors.Result)" }
    $process.StandardInput.Write($Command + "`r")
    $process.StandardInput.Flush()
    if (-not $reply.Wait($TimeoutMs)) { throw "UART response timeout for $Command on $Port" }
    $response = $reply.Result
    if ($response -ne 'OK') { throw "Unexpected UART response: $response" }
    Write-Output "Plink 0.85 $Port 115200 8N1: $Command -> $response"
} finally {
    if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
