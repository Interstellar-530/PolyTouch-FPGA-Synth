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
        private readonly Label octaveLabel = new Label();
        private readonly Label timbreLabel = new Label();
        private readonly Button instrumentButton;
        private readonly TrackBar timbre = new TrackBar();
        private readonly Timer polyphonyTimer = new Timer();
        private readonly string logPath;
        private int baseNote = KeyboardLayout.DefaultBaseNote;
        private bool timbreDirty;
        private bool manual = true;
        private bool guitarMode;
        public KeyboardWindow(string defaultPort, string logFile)
        {
            logPath = logFile;
            Text = "PolyTouch 电脑演奏";
            ClientSize = new Size(1200, 660);
            MinimumSize = new Size(1216, 699);
            Font = new Font("Microsoft YaHei UI", 10);
            BackColor = Color.FromArgb(245, 247, 250);
            KeyPreview = true; ImeMode = ImeMode.Disable;
            ports.DropDownStyle = ComboBoxStyle.DropDownList;
            ports.SetBounds(20, 18, 120, 30);
            foreach (string name in SerialPort.GetPortNames()) ports.Items.Add(name);
            if (!ports.Items.Contains(defaultPort)) ports.Items.Add(defaultPort);
            ports.SelectedItem = defaultPort;
            Controls.Add(ports);
            ButtonAt("连接", 120, delegate { ConnectPort(); });
            manualButton = ButtonAt("手动", 220, delegate { Mode(false); });
            ButtonAt("演示", 320, delegate { Mode(true); });
            ButtonAt("全松键", 420, delegate { AllOff(); });
            ButtonAt("静音", 520, delegate { Send("M0"); });
            ButtonAt("有声", 620, delegate { Send("M1"); });
            ButtonAt("四音测试", 720, delegate { PolyphonyTest(); });
            instrumentButton = ButtonAt("音色：钢琴", 820, delegate { ToggleInstrument(); });
            instrumentButton.Width = 140;
            status.SetBounds(20, 60, 1160, 28); status.Text = "正在连接…"; Controls.Add(status);
            Label guide = new Label(); guide.SetBounds(20, 96, 1160, 52);
            guide.Text = "两排钢琴键：低排 C3–B3，高排 C4–B4；A/F/K 保留为 C4/F4/C5 快捷别名。\r\nPageUp/PageDown 移调；F1–F5 切换钢琴硬度，F5 为最强击弦；F6 或“音色”按钮切换钢琴/吉他；空格全松键。";
            Controls.Add(guide);

            for (int i = 0; i < KeyboardLayout.LowerKeys.Length; i++)
            {
                AddNoteTile((Keys)KeyboardLayout.LowerKeys[i], i - 12, i, 160);
            }
            for (int i = 0; i < KeyboardLayout.UpperKeys.Length; i++)
            {
                AddNoteTile((Keys)KeyboardLayout.UpperKeys[i], i, i, 258);
            }
            layout.Add(Keys.A, 0);
            layout.Add(Keys.F, 5);
            layout.Add(Keys.K, 12);

            octaveLabel.SetBounds(20, 350, 1160, 24);
            Controls.Add(octaveLabel);
            timbreLabel.SetBounds(20, 378, 1160, 24);
            Controls.Add(timbreLabel);
            timbre.SetBounds(20, 404, 620, 40);
            timbre.Minimum = 0; timbre.Maximum = 4; timbre.TickFrequency = 1; timbre.Value = 4;
            timbre.TabStop = false; Controls.Add(timbre);
            // Limit host traffic, keep only the latest slider target, and leave
            // ordinary note events ahead of pending timbre in the transport.
            System.Windows.Forms.Timer timbreTimer = new System.Windows.Forms.Timer();
            timbreTimer.Interval = 40;
            timbre.ValueChanged += delegate {
                UpdateTimbreLabel();
                timbreDirty = true;
            };
            timbreTimer.Tick += delegate {
                if (timbreDirty && transport != null && transport.Connected) {
                    timbreDirty = false; Send("T" + (250 + timbre.Value));
                }
            };
            timbreTimer.Start();
            FormClosed += delegate { timbreTimer.Stop(); timbreTimer.Dispose(); };
            for (int pi = 0; pi < KeyboardLayout.TimbrePresets.Length; pi++) {
                int presetIndex = pi;
                Button preset = new Button(); preset.SetBounds(660 + pi * 80, 404, 72, 32);
                preset.Text = "F" + (pi + 1); preset.TabStop = false;
                preset.Click += delegate { SetTimbre(presetIndex); };
                Controls.Add(preset);
            }
            UpdateOctaveLabel();
            UpdateTimbreLabel();
            UpdateTiles();
            polyphonyTimer.Interval = 2600;
            polyphonyTimer.Tick += delegate
            {
                polyphonyTimer.Stop();
                AllOff();
                status.Text = "四音测试结束 · 已全松键";
            };
            history.SetBounds(20, 458, 1160, 182); history.Multiline = true;
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
            FormClosing += delegate
            {
                polyphonyTimer.Stop(); polyphonyTimer.Dispose();
                if (transport != null) transport.Dispose();
            };
        }
        private void AddNoteTile(Keys key, int offset, int column, int y)
        {
            layout.Add(key, offset);
            Label tile = new Label();
            tile.SetBounds(20 + column * 93, y, 88, 84);
            tile.TextAlign = ContentAlignment.MiddleCenter;
            tile.BorderStyle = BorderStyle.FixedSingle;
            tile.Click += delegate { ActiveControl = manualButton; manualButton.Focus(); };
            tiles.Add(key, tile);
            Controls.Add(tile);
        }
        private static string NoteName(int midi)
        {
            string[] names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
            int octave = (midi / 12) - 1;
            return names[((midi % 12) + 12) % 12] + octave;
        }
        private void UpdateTiles()
        {
            foreach (KeyValuePair<Keys, int> pair in layout)
            {
                Label tile;
                if (!tiles.TryGetValue(pair.Key, out tile)) continue;
                int note = baseNote + pair.Value;
                string letter = ((char)(int)pair.Key).ToString();
                bool sharp = NoteName(note).Contains("#");
                tile.Text = letter + "\r\n" + NoteName(note);
                tile.BackColor = sharp ? Color.FromArgb(54, 65, 82) : Color.White;
                tile.ForeColor = sharp ? Color.White : Color.FromArgb(28, 42, 59);
            }
        }
        private Button ButtonAt(string text, int x, EventHandler action)
        {
            Button button = new Button(); button.Text = text; button.SetBounds(x, 18, 100, 32);
            button.Click += action; Controls.Add(button); return button;
        }
        private void UpdateOctaveLabel()
        {
            octaveLabel.Text = "当前音域 " + NoteName(baseNote - 12) + " – " + NoteName(baseNote + 11) +
                " · PageUp 升八度 / PageDown 降八度 · A/F/K 为 C4/F4/C5 别名";
        }
        private void UpdateTimbreLabel()
        {
            string[] names = { "柔和琴体", "温暖", "标准", "明亮", "强击弦" };
            timbreLabel.Text = "钢琴硬度 " + (timbre.Value + 1) + " · " + names[timbre.Value] +
                " · F1–F5 直接选择；包络会随衰减自动回归琴体";
        }
        private void SetTimbre(int value)
        {
            timbre.Value = value;
            timbreDirty = true;
            UpdateTimbreLabel();
            ActiveControl = manualButton; manualButton.Focus();
        }
        private void ToggleInstrument()
        {
            if (transport == null || !transport.Connected) { status.Text = "请先连接串口。"; return; }
            guitarMode = !guitarMode;
            if (guitarMode) Send("I1");
            else { Send("I0"); Send("T" + (250 + timbre.Value)); }
            instrumentButton.Text = "音色：" + (guitarMode ? "吉他" : "钢琴");
            status.Text = guitarMode ? "吉他音色 · 8 声部持续音" : "钢琴音色";
            ActiveControl = manualButton; manualButton.Focus();
        }
        private void ShiftOctave(int semitones)
        {
            int shifted = KeyboardLayout.ShiftBase(baseNote, semitones);
            if (shifted == baseNote) return;
            baseNote = shifted;
            notes.BaseNote = baseNote;
            UpdateOctaveLabel();
            UpdateTiles();
            status.Text = "已移调到 " + NoteName(baseNote - 12) + " – " + NoteName(baseNote + 11);
        }
        private void PolyphonyTest()
        {
            if (transport == null || !transport.Connected) { status.Text = "请先连接串口。"; return; }
            polyphonyTimer.Stop();
            notes.Clear(); UpdateTiles(); manual = true;
            transport.Panic("D0");
            Send("M1");
            foreach (string command in KeyboardLayout.PolyphonyTestNotes(baseNote))
                Send(command);
            status.Text = "四音测试中 · " + String.Join(" ", KeyboardLayout.PolyphonyTestNotes(baseNote)) +
                " · 2.6 秒后自动全松键";
            ActiveControl = manualButton; manualButton.Focus();
            polyphonyTimer.Start();
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
            UpdateTiles();
        }
        private void AllOff()
        {
            polyphonyTimer.Stop();
            notes.Clear(); ResetTiles();
            if (transport != null && transport.Connected) transport.Panic(null);
            manual = true;
        }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (ActiveControl == ports || e.Control || e.Alt) { base.OnKeyDown(e); return; }
            if (e.KeyCode == Keys.F6) {
                ToggleInstrument();
                e.Handled = true; e.SuppressKeyPress = true; return;
            }
            int timbreTarget = KeyboardLayout.TimbreForFunctionKey((int)e.KeyCode);
            if (timbreTarget >= 0) {
                SetTimbre(timbreTarget - 250);
                e.Handled = true; e.SuppressKeyPress = true; return;
            }
            if (e.KeyCode == Keys.PageUp) {
                ShiftOctave(12); e.Handled = true; e.SuppressKeyPress = true; return;
            }
            if (e.KeyCode == Keys.PageDown) {
                ShiftOctave(-12); e.Handled = true; e.SuppressKeyPress = true; return;
            }
            if (e.KeyCode == Keys.Space) { AllOff(); e.Handled = true; e.SuppressKeyPress = true; return; }
            int offset;
            if (layout.TryGetValue(e.KeyCode, out offset))
            {
                if (transport != null && transport.Connected)
                {
                    if (!manual && !notes.IsBlocked((int)e.KeyCode)) Mode(false);
                    string command = notes.Press((int)e.KeyCode, offset);
                    Label tile;
                    if (command != null)
                    {
                        Send(command);
                        if (tiles.TryGetValue(e.KeyCode, out tile))
                            tile.BackColor = Color.FromArgb(42, 153, 130);
                    }
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
        protected override void OnHelpRequested(HelpEventArgs hevent)
        {
            hevent.Handled = true;
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
