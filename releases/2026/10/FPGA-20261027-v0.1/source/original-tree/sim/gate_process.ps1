# Run tools with bounded wall time and preserve their real exit codes (Windows PS 5.1).
function Invoke-GateProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Log, [int]$TimeoutSeconds)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    # Windows argv quoting; all arguments are data, never shell source.
    $info.Arguments = (@($Arguments | ForEach-Object {
        '"' + ([regex]::Replace(([regex]::Replace($_, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
    }) -join ' ')
    $info.WorkingDirectory = (Get-Location).Path
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
            $process.WaitForExit()
        }
        $output = $stdout.Result + $stderr.Result
        $output | Set-Content -LiteralPath $Log -Encoding UTF8
        $code = $process.ExitCode
        if ($timedOut) { $code = 124 }
        return [pscustomobject]@{ ExitCode=$code; TimedOut=$timedOut; Seconds=$timer.Elapsed.TotalSeconds; Output=$output }
    } finally { $timer.Stop(); $process.Dispose() }
}
