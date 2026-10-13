using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.IO.Ports;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace PolyTouchPc
{
    public sealed class KeyboardWindow : Form
    {
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int how);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        private readonly KeyboardState notes = new KeyboardState();
        private readonly Dictionary<Keys, int> layout = new Dictionary<Keys, int>();
        private readonly Dictionary<Keys, Label> tiles = new Dictionary<Keys, Label>();
        private SerialTransport transport;
        private readonly ComboBox ports = new ComboBox();
        private readonly Label status = new Label();
        private readonly Button manualButton;
        private readonly TextBox history = new TextBox();
        private readonly string logPath;
        private bool manual = true;
        public KeyboardWindow(string defaultPort, string logFile)
        {
            logPath = logFile;
            Text = "PolyTouch 电脑演奏";
            ClientSize = new Size(880, 440);
            MinimumSize = new Size(896, 479);
            Font = new Font("Microsoft YaHei UI", 10);
            BackColor = Color.FromArgb(245, 247, 250);
            KeyPreview = true; ImeMode = ImeMode.Disable;
            ports.DropDownStyle = ComboBoxStyle.DropDownList;
            ports.SetBounds(20, 18, 120, 30);
            foreach (string name in SerialPort.GetPortNames()) ports.Items.Add(name);
            if (!ports.Items.Contains(defaultPort)) ports.Items.Add(defaultPort);
            ports.SelectedItem = defaultPort;
            Controls.Add(ports);
            ButtonAt("连接", 150, delegate { ConnectPort(); });
            manualButton = ButtonAt("手动", 260, delegate { Mode(false); });
            ButtonAt("演示", 370, delegate { Mode(true); });
            ButtonAt("全松键", 480, delegate { AllOff(); });
            ButtonAt("静音", 590, delegate { Send("M0"); });
            ButtonAt("有声", 700, delegate { Send("M1"); });
            status.SetBounds(20, 60, 840, 28); status.Text = "正在连接…"; Controls.Add(status);
            Label guide = new Label(); guide.SetBounds(20, 98, 840, 50);
            guide.Text = "按住下列电脑键发音，松开释音；可同时按多个键（当前最多四声部）。\n空格：全松键。切到其他窗口时自动松键。演示时按音符键自动转手动。";
            Controls.Add(guide);
            string letters = "AWS EDFTGYHUJK".Replace(" ", "");
            int[] offsets = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
            string[] names = { "C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4", "C5" };
            for (int i = 0; i < letters.Length; i++)
            {
                Keys key = (Keys)Enum.Parse(typeof(Keys), letters[i].ToString());
                layout.Add(key, offsets[i]);
                Label tile = new Label(); tile.SetBounds(20 + i * 64, 162, 60, 92);
                bool sharp = names[i].Contains("#");
                tile.Text = letters[i] + "\n" + names[i]; tile.TextAlign = ContentAlignment.MiddleCenter;
                tile.BackColor = sharp ? Color.FromArgb(54, 65, 82) : Color.White;
                tile.ForeColor = sharp ? Color.White : Color.FromArgb(28, 42, 59);
                tile.BorderStyle = BorderStyle.FixedSingle;
                tile.Click += delegate { ActiveControl = manualButton; manualButton.Focus(); };
                tiles.Add(key, tile); Controls.Add(tile);
            }
            history.SetBounds(20, 274, 840, 144); history.Multiline = true;
            history.ReadOnly = true; history.ScrollBars = ScrollBars.Vertical;
            history.TabStop = false; Controls.Add(history);
            Shown += delegate
            {
                ConnectPort();
                // Hidden PowerShell startup must hide its console, not this UI.
                BeginInvoke(new Action(delegate
                {
                    ShowWindow(Handle, 5); SetForegroundWindow(Handle);
                    ActiveControl = manualButton; manualButton.Focus();
                }));
            };
            Deactivate += delegate
            {
                if (manual) { Record("失去焦点 -> 全松键"); AllOff(); }
            };
            Activated += delegate
            {
                foreach (Keys key in layout.Keys)
                    if ((GetAsyncKeyState((int)key) & 0x8000) == 0)
                    {
                        string release = notes.Release((int)key);
                        if (release != null) Send(release);
                        ResetTile(key);
                    }
            };
            FormClosing += delegate { if (transport != null) transport.Dispose(); };
        }
        private Button ButtonAt(string text, int x, EventHandler action)
        {
            Button button = new Button(); button.Text = text; button.SetBounds(x, 18, 100, 32);
            button.Click += action; Controls.Add(button); return button;
        }
        private void Record(string text)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { try { BeginInvoke(new Action<string>(Record), text); } catch (InvalidOperationException) { } return; }
            string line = DateTime.Now.ToString("HH:mm:ss.fff") + " " + text;
            if (history.Lines.Length > 150) history.Clear();
            history.AppendText(line + Environment.NewLine);
            if (!String.IsNullOrEmpty(logPath)) File.AppendAllText(logPath, line + Environment.NewLine);
            if (text.StartsWith("ERROR:")) status.Text = text;
        }
        private void ConnectPort()
        {
            if (transport != null) transport.Dispose();
            notes.Clear(); ResetTiles();
            transport = new SerialTransport(); transport.Message += Record;
            try
            {
                transport.Connect(ports.SelectedItem.ToString()); manual = true;
                status.Text = "已连接 · 手动模式 · 按住琴键发音（若无应答请看下方记录）";
                ActiveControl = manualButton; manualButton.Focus();
            }
            catch (Exception e) { status.Text = "连接失败：" + e.Message + "；请先关闭 PuTTY。"; Record(status.Text); }
        }
        private void Send(string command)
        {
            try { if (transport == null) throw new InvalidOperationException("请先连接串口。"); transport.Send(command); }
            catch (Exception e) { status.Text = e.Message; notes.Clear(); ResetTiles(); if (transport != null) transport.Panic(null); }
        }
        private void Mode(bool demo)
        {
            if (transport == null || !transport.Connected) { status.Text = "请先连接串口。"; return; }
            notes.Clear(); ResetTiles(); manual = !demo;
            transport.Panic(demo ? "D1" : "D0");
            status.Text = demo ? "演示模式 · 按任意琴键可转回手动" : "手动模式 · 按住琴键发音";
            ActiveControl = manualButton; manualButton.Focus();
        }
        private void ResetTiles()
        {
            foreach (KeyValuePair<Keys, Label> pair in tiles)
                pair.Value.BackColor = pair.Value.Text.Contains("#") ? Color.FromArgb(54, 65, 82) : Color.White;
        }
        private void AllOff()
        {
            notes.Clear(); ResetTiles();
            if (transport != null && transport.Connected) transport.Panic(null);
            manual = true;
        }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (ActiveControl == ports || e.Control || e.Alt) { base.OnKeyDown(e); return; }
            if (e.KeyCode == Keys.Space) { AllOff(); e.Handled = true; e.SuppressKeyPress = true; return; }
            int offset;
            if (layout.TryGetValue(e.KeyCode, out offset))
            {
                if (transport != null && transport.Connected)
                {
                    if (!manual && !notes.IsBlocked((int)e.KeyCode)) Mode(false);
                    string command = notes.Press((int)e.KeyCode, offset);
                    if (command != null) { Send(command); tiles[e.KeyCode].BackColor = Color.FromArgb(42, 153, 130); }
                }
                e.Handled = true; e.SuppressKeyPress = true;
            }
            base.OnKeyDown(e);
        }
        protected override void OnKeyUp(KeyEventArgs e)
        {
            string command = notes.Release((int)e.KeyCode);
            if (command != null) { Send(command); ResetTile(e.KeyCode); e.Handled = true; }
            base.OnKeyUp(e);
        }
        private void ResetTile(Keys key)
        {
            Label tile; if (tiles.TryGetValue(key, out tile))
                tile.BackColor = tile.Text.Contains("#") ? Color.FromArgb(54, 65, 82) : Color.White;
        }
        public static void Open(string port, string log)
        {
            Application.EnableVisualStyles();
            Application.Run(new KeyboardWindow(port, log));
        }
    }
}
