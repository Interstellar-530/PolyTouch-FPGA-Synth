# Minimal serial console for the PolyTouch FPGA Synth.
#
# Opens a COM port, shows everything the board sends back, and lets you type
# or click commands. Built on System.IO.Ports + WinForms so it needs no
# installation. Logs every line to tools/serial_console/serial_log.txt.
#
# Quick buttons match the v0.4 firmware protocol in
# output/handoff_milestone2_20261008/source/rtl/audio/uart_pitch.v:
#   F440 -> set pitch to 440 Hz,  M0 -> digital mute,  M1 -> unmute

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:port  = $null
$script:logPath = Join-Path $PSScriptRoot 'serial_log.txt'

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'PolyTouch 串口控制台'
$form.Size            = New-Object System.Drawing.Size(760, 560)
$form.StartPosition   = 'CenterScreen'
$form.Font            = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = '串口'
$lblPort.Location = New-Object System.Drawing.Point(12, 15)
$lblPort.Size = New-Object System.Drawing.Size(36, 20)
$form.Controls.Add($lblPort)

$cmbPort = New-Object System.Windows.Forms.ComboBox
$cmbPort.Location = New-Object System.Drawing.Point(52, 12)
$cmbPort.Size = New-Object System.Drawing.Size(110, 24)
$cmbPort.DropDownStyle = 'DropDown'
$form.Controls.Add($cmbPort)

$lblBaud = New-Object System.Windows.Forms.Label
$lblBaud.Text = '波特率'
$lblBaud.Location = New-Object System.Drawing.Point(174, 15)
$lblBaud.Size = New-Object System.Drawing.Size(50, 20)
$form.Controls.Add($lblBaud)

$cmbBaud = New-Object System.Windows.Forms.ComboBox
$cmbBaud.Location = New-Object System.Drawing.Point(228, 12)
$cmbBaud.Size = New-Object System.Drawing.Size(90, 24)
[void]$cmbBaud.Items.AddRange(@('115200', '9600', '57600', '230400'))
$cmbBaud.Text = '115200'
$form.Controls.Add($cmbBaud)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = '刷新端口'
$btnRefresh.Location = New-Object System.Drawing.Point(330, 11)
$btnRefresh.Size = New-Object System.Drawing.Size(84, 26)
$form.Controls.Add($btnRefresh)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = '打开'
$btnConnect.Location = New-Object System.Drawing.Point(420, 11)
$btnConnect.Size = New-Object System.Drawing.Size(84, 26)
$form.Controls.Add($btnConnect)

$lblState = New-Object System.Windows.Forms.Label
$lblState.Text = '未连接'
$lblState.Location = New-Object System.Drawing.Point(516, 15)
$lblState.Size = New-Object System.Drawing.Size(220, 20)
$lblState.ForeColor = [System.Drawing.Color]::DarkRed
$form.Controls.Add($lblState)

$txtRecv = New-Object System.Windows.Forms.TextBox
$txtRecv.Location = New-Object System.Drawing.Point(12, 46)
$txtRecv.Size = New-Object System.Drawing.Size(724, 380)
$txtRecv.Multiline = $true
$txtRecv.ScrollBars = 'Vertical'
$txtRecv.ReadOnly = $true
$txtRecv.BackColor = [System.Drawing.Color]::White
$txtRecv.Font = New-Object System.Drawing.Font('Consolas', 10)
$form.Controls.Add($txtRecv)

$txtSend = New-Object System.Windows.Forms.TextBox
$txtSend.Location = New-Object System.Drawing.Point(12, 438)
$txtSend.Size = New-Object System.Drawing.Size(560, 26)
$txtSend.Font = New-Object System.Drawing.Font('Consolas', 10)
$form.Controls.Add($txtSend)

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = '发送'
$btnSend.Location = New-Object System.Drawing.Point(580, 437)
$btnSend.Size = New-Object System.Drawing.Size(72, 28)
$form.Controls.Add($btnSend)

$chkNewline = New-Object System.Windows.Forms.CheckBox
$chkNewline.Text = '自动加 CR LF'
$chkNewline.Checked = $true
$chkNewline.Location = New-Object System.Drawing.Point(662, 440)
$chkNewline.Size = New-Object System.Drawing.Size(100, 24)
$form.Controls.Add($chkNewline)

$quick = @(
    @{ Text = 'F440 (A4)';  Cmd = 'F440' },
    @{ Text = 'F262 (C4)';  Cmd = 'F262' },
    @{ Text = 'F523 (C5)';  Cmd = 'F523' },
    @{ Text = 'M0 静音';    Cmd = 'M0'   },
    @{ Text = 'M1 解除';    Cmd = 'M1'   },
    @{ Text = 'F2000';      Cmd = 'F2000' }
)
$x = 12
foreach ($q in $quick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $q.Text
    $b.Tag = $q.Cmd
    $b.Location = New-Object System.Drawing.Point($x, 476)
    $b.Size = New-Object System.Drawing.Size(96, 30)
    $form.Controls.Add($b)
    $b.Add_Click({
        param($sender, $e)
        $txtSend.Text = $sender.Tag
        $btnSend.PerformClick()
    })
    $x += 100
}

function Write-Log([string]$text) {
    Add-Content -LiteralPath $script:logPath -Value $text -Encoding utf8
}

function Append-Recv([string]$text) {
    if ($text.Length -eq 0) { return }
    $txtRecv.AppendText($text)
    $txtRecv.SelectionStart = $txtRecv.TextLength
    $txtRecv.ScrollToCaret()
    Write-Log ("[{0}] RX  {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), ($text -replace "`r`n", ' | '))
}

function Refresh-Ports {
    $cmbPort.Items.Clear()
    foreach ($p in [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object) {
        [void]$cmbPort.Items.Add($p)
    }
    # Do not probe by opening every port here: the Bluetooth virtual ports on
    # this machine take seconds to time out and would freeze the window.
    # Prefer a USB serial device and skip the Bluetooth virtual ports, which
    # are never the board.
    $usb = @()
    $bt  = @()
    foreach ($p in $cmbPort.Items) {
        $name = ''
        try {
            $dev = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match "\($p\)" } | Select-Object -First 1
            if ($dev) { $name = $dev.Name }
        } catch { }
        if ($name -match '蓝牙|Bluetooth') { $bt += $p } else { $usb += $p }
    }
    if ($usb.Count -gt 0) { $cmbPort.Text = $usb[$usb.Count - 1] }
    elseif ($bt.Count -gt 0) { $cmbPort.Text = $bt[0] }
    Append-Recv ("检测到端口: " + (($cmbPort.Items | ForEach-Object { $_.ToString() }) -join ', ') + "`r`n")
    Append-Recv ("其中 USB 串口: " + ($usb -join ', ') + " ；蓝牙虚拟串口: " + ($bt -join ', ') + "`r`n")
}

$btnRefresh.Add_Click({ Refresh-Ports })

$btnConnect.Add_Click({
    if ($script:port -and $script:port.IsOpen) {
        $script:port.Close()
        $script:port.Dispose()
        $script:port = $null
        $btnConnect.Text = '打开'
        $lblState.Text = '未连接'
        $lblState.ForeColor = [System.Drawing.Color]::DarkRed
        Append-Recv "`r`n[已关闭端口]`r`n"
        return
    }
    try {
        $script:port = New-Object System.IO.Ports.SerialPort($cmbPort.Text, [int]$cmbBaud.Text, 'None', 8, 'One')
        $script:port.ReadTimeout = 200
        $script:port.NewLine = "`n"
        $script:port.Open()
        $btnConnect.Text = '关闭'
        $lblState.Text = "已连接 $($cmbPort.Text) @ $($cmbBaud.Text)"
        $lblState.ForeColor = [System.Drawing.Color]::DarkGreen
        Append-Recv "`r`n[已打开 $($cmbPort.Text) @ $($cmbBaud.Text)]`r`n"
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("打开失败: $($_.Exception.Message)", '串口控制台')
    }
})

$send = {
    if (-not ($script:port -and $script:port.IsOpen)) {
        [void][System.Windows.Forms.MessageBox]::Show('请先打开串口', '串口控制台')
        return
    }
    $payload = $txtSend.Text
    if ($chkNewline.Checked) { $payload += "`r`n" }
    try {
        $script:port.Write($payload)
        Append-Recv ("[TX] " + $txtSend.Text + "`r`n")
        Write-Log ("[{0}] TX  {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $txtSend.Text)
    } catch {
        Append-Recv "[发送失败] $($_.Exception.Message)`r`n"
    }
}
$btnSend.Add_Click($send)
$txtSend.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { & $send; $_.SuppressKeyPress = $true } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60
$timer.Add_Tick({
    if ($script:port -and $script:port.IsOpen) {
        try {
            if ($script:port.BytesToRead -gt 0) { Append-Recv ($script:port.ReadExisting()) }
        } catch { }
    }
})
$timer.Start()

$form.Add_FormClosing({
    if ($script:port -and $script:port.IsOpen) { $script:port.Close() }
    $timer.Stop()
})

Refresh-Ports
Append-Recv "PolyTouch 串口控制台已就绪。日志: $script:logPath`r`n命令: F<频率Hz> 设音高, M0 静音, M1 解除。`r`n"
[void]$form.ShowDialog()
