<#
    推送重试与链路诊断（Windows / PowerShell 7 或 5.1）。

    为什么需要它：本机到 github.com 的 HTTPS 会间歇性被重置（报错形如
    "Recv failure: Connection was reset" 或 "Failed to connect ... port 443"），
    而 DNS、TCP、凭据、仓库权限本身都是好的。这类失败重试几次通常就过去了，
    手工重试容易漏掉成功的那次，于是做成脚本。

    脚本只做两件事：只读链路诊断，和按退避重试 git push。
    它不修改仓库内容、不写全局 git 配置、不碰任何文件。

    用法（在本机任意目录）：
        pwsh -NoProfile -File tools/git_push_retry.ps1 -Repo D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-integration
        pwsh -NoProfile -File tools/git_push_retry.ps1 -Repo <仓库> -Branch codex/s4-s6-integration -MaxAttempts 12

    退出码：0 = 某次尝试推送成功；1 = 全部尝试失败（脚本会打印诊断结论）。
#>
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Remote = 'origin',
    [string]$Branch = '',
    [int]$MaxAttempts = 8,
    [int]$BaseDelaySeconds = 8,
    [int]$MaxDelaySeconds = 60
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string[]]$GitArgs)
    # -c safe.directory：本机在不同账号（沙箱/用户）下跑 git 时会出现 dubious ownership，
    # 这里只在单次调用上放行，不改全局配置。
    $all = @('-c', "safe.directory=$script:RepoPath") + $GitArgs
    $out = & git @all 2>&1
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = @($out) }
}

function Show-LinkDiagnosis {
    param([string]$HostName = 'github.com')
    $tcp = Test-NetConnection -ComputerName $HostName -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    $curl = (& curl.exe -sS -o NUL --max-time 20 -w "http=%{http_code} tls=%{time_appconnect}s" "https://$HostName/" 2>&1) -join ' '
    $refs = (& curl.exe -sS -o NUL --max-time 20 -w "git_endpoint=%{http_code}" "https://$HostName/$script:Slug.git/info/refs?service=git-upload-pack" 2>&1) -join ' '
    "  链路: tcp443={0}  {1}  {2}" -f $tcp, $curl, $refs
    if (-not $tcp) { "  结论: TCP 都连不上，先查网络/代理/VPN，而不是重试。" }
    elseif ("$curl" -notmatch 'http=2\d\d') { "  结论: TCP 通但 HTTPS 被重置或超时，属于链路抖动，重试或换通道。" }
}

if (-not (Test-Path -LiteralPath $Repo)) { throw "仓库路径不存在: $Repo" }
$script:RepoPath = (Resolve-Path -LiteralPath $Repo).Path

$remoteUrl = (Invoke-Git @('remote', 'get-url', $Remote)).Output | Select-Object -First 1
if ($remoteUrl -notmatch 'github\.com[/:]([^/]+/[^/.]+)') { throw "无法从远端 URL 解析仓库 slug: $remoteUrl" }
$script:Slug = $Matches[1]

if (-not $Branch) {
    $Branch = ((Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')).Output | Select-Object -First 1).Trim()
    if ($Branch -eq 'HEAD') { throw "当前处于 detached HEAD，请用 -Branch 指定分支。" }
}

$head = ((Invoke-Git @('rev-parse', '--short', 'HEAD')).Output | Select-Object -First 1).Trim()
"仓库  : $script:RepoPath"
"远端  : $Remote -> $remoteUrl"
"分支  : $Branch (HEAD $head)"
""

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    "第 $attempt/$MaxAttempts 次尝试 $(Get-Date -Format 'HH:mm:ss')"
    $res = Invoke-Git @('push', $Remote, $Branch)
    $text = ($res.Output -join "`n")
    if ($res.Exit -eq 0) {
        $text -split "`n" | ForEach-Object { "  $_" }
        $verify = Invoke-Git @('ls-remote', '--heads', $Remote, $Branch)
        "远端校验: " + (($verify.Output | Select-Object -First 1) -replace "`t", '  ')
        "结论: 推送成功。"
        exit 0
    }

    $reason =
        if ($text -match 'Connection was reset') { '连接被重置 (Connection was reset)' }
        elseif ($text -match 'Failed to connect') { '建连超时 (Failed to connect)' }
        elseif ($text -match 'Could not resolve') { 'DNS 解析失败' }
        elseif ($text -match 'Authentication failed|403') { '认证失败：需要重新登录，不是链路问题' }
        elseif ($text -match 'Permission denied') { '权限不足：仓库或分支没有写权限' }
        elseif ($text -match 'non-fast-forward|fetch first') { '远端有新提交：需要先 pull/rebase' }
        else { ($text -split "`n" | Select-Object -First 1) }
    "  失败: $reason"

    if ($reason -match '认证失败|权限不足|non-fast-forward') {
        "结论: 这是凭据/权限/分叉问题，重试无用，请按上面的提示处理。"
        exit 1
    }

    if ($attempt -lt $MaxAttempts) {
        if ($attempt -eq 1 -or $attempt % 3 -eq 0) { Show-LinkDiagnosis }
        $delay = [Math]::Min($BaseDelaySeconds * $attempt, $MaxDelaySeconds)
        "  等待 $delay 秒后重试..."
        Start-Sleep -Seconds $delay
    }
}

"全部 $MaxAttempts 次尝试都失败。"
Show-LinkDiagnosis
"建议按顺序试：1) 破网/代理；2) git config --global http.version HTTP/1.1 后重试；"
"3) 换 SSH over 443（ssh.github.com:443，需要先在 GitHub 上登记本机公钥）。"
exit 1