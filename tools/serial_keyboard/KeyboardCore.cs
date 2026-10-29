using System;
using System.Collections.Generic;
using System.IO.Ports;
using System.Text.RegularExpressions;
using System.Threading;

namespace PolyTouchPc
{
    public static class KeyboardLayout
    {
        public static readonly int[] LowerKeys =
            { 'Z', 'S', 'X', 'D', 'C', 'V', 'G', 'B', 'H', 'N', 'J', 'M' };
        public static readonly int[] UpperKeys =
            { 'Q', '2', 'W', '3', 'E', 'R', '5', 'T', '6', 'Y', '7', 'U' };
        public static readonly int[] TimbrePresets = { 250, 251, 252, 253, 254 };
        public const int DefaultBaseNote = 60;
        public const int MinBaseNote = 36;
        public const int MaxBaseNote = 84;

        public static bool TryOffset(int key, out int offset)
        {
            for (int i = 0; i < LowerKeys.Length; i++)
            {
                if (key == LowerKeys[i]) { offset = i - 12; return true; }
            }
            for (int i = 0; i < UpperKeys.Length; i++)
            {
                if (key == UpperKeys[i]) { offset = i; return true; }
            }
            switch (key)
            {
                case 'A': offset = 0; return true;  // legacy C4
                case 'F': offset = 5; return true;  // legacy F4
                case 'K': offset = 12; return true; // legacy C5
                default: offset = 0; return false;
            }
        }

        public static int ShiftBase(int baseNote, int semitones)
        {
            int shifted = baseNote + semitones;
            return Math.Max(MinBaseNote, Math.Min(MaxBaseNote, shifted));
        }

        public static string[] PolyphonyTestNotes(int baseNote)
        {
            int[] offsets = { 0, 4, 7, 12 };
            string[] commands = new string[offsets.Length];
            for (int i = 0; i < offsets.Length; i++)
                commands[i] = "N" + Math.Max(1, Math.Min(127, baseNote + offsets[i]));
            return commands;
        }

        public static int TimbreForFunctionKey(int key)
        {
            int index = key - 112; // WinForms Keys.F1
            return (index >= 0 && index < TimbrePresets.Length) ? TimbrePresets[index] : -1;
        }
    }

    public sealed class KeyboardState
    {
        private readonly Dictionary<int, int> held = new Dictionary<int, int>();
        private readonly HashSet<int> blocked = new HashSet<int>();
        public int BaseNote = 60;
        public int HeldCount { get { return held.Count; } }
        public string Press(int key, int offset)
        {
            if (held.ContainsKey(key) || blocked.Contains(key)) return null;
            int note = BaseNote + offset;
            if (note < 1 || note > 127) return null;
            held[key] = note;
            return "N" + note;
        }
        public string Release(int key)
        {
            blocked.Remove(key);
            int note;
            if (!held.TryGetValue(key, out note)) return null;
            held.Remove(key);
            return "O" + note;
        }
        public bool IsBlocked(int key) { return blocked.Contains(key); }
        public void Clear()
        {
            foreach (int key in held.Keys) blocked.Add(key);
            held.Clear();
        }
    }

    public sealed class CommandQueue
    {
        private readonly Queue<string> queue = new Queue<string>();
        private readonly object gate = new object();
        private string pendingTimbre;
        public void Add(string command)
        {
            lock (gate)
            {
                if (command.StartsWith("T")) { pendingTimbre = command; return; }
                if (queue.Count >= 128) throw new InvalidOperationException("串口发送积压，请停止演奏并重新连接。");
                queue.Enqueue(command);
            }
        }
        public void Panic(string next)
        {
            lock (gate)
            {
                pendingTimbre = null;
                queue.Clear(); // discard stale Note Ons before all-notes-off
                queue.Enqueue("X");
                if (next != null) queue.Enqueue(next);
            }
        }
        public bool Take(out string command)
        {
            lock (gate)
            {
                if (queue.Count == 0) { command = pendingTimbre; pendingTimbre = null; return command != null; }
                command = queue.Dequeue(); return true;
            }
        }
    }

    // One line returned by the FPGA Q command. The payload is ASCII hex so
    // it remains compatible with the existing 115200 8N1 link.
    public sealed class DashboardSnapshot
    {
        public ulong Status;
        public readonly byte[] Waveform = new byte[32];
        public readonly byte[] Spectrum = new byte[8];
        public readonly byte[] Lissajous = new byte[8];
        // Match ui_status_export.v exactly; the UART transmits this 64-bit word unchanged.
        public int ActiveCount { get { return (int)(((Status >> 12) & 15UL) | (((Status >> 60) & 3UL) << 4)); } }
        public int Capacity { get { return ((Status >> 62) & 1UL) != 0 ? 32 : 8; } }
        public int LeadNote { get { return (int)((Status >> 16) & 127UL); } }
        public int LeadVelocity { get { return (int)((Status >> 23) & 255UL); } }
        public int Pressure { get { return (int)((Status >> 31) & 255UL) << 4; } }
        public bool Demo { get { return ((Status >> 39) & 1UL) != 0; } }
        public int Instrument { get { return (int)((Status >> 40) & (Capacity == 32 ? 1UL : 3UL)); } }
        public bool Sustain { get { return Capacity == 32 && ((Status >> 41) & 1UL) != 0; } }
        public bool Piano { get { return ((Status >> 42) & 1UL) != 0; } }
        public bool Guitar { get { return ((Status >> 43) & 1UL) != 0; } }
        public bool Muted { get { return ((Status >> 44) & 1UL) != 0; } }
        public int PianoTone { get { return (int)((Status >> 45) & 7UL); } }
        public int Timbre { get { return (int)((Status >> 48) & 255UL); } }
        public int Tempo { get { return (int)((Status >> 56) & 3UL); } }
        public bool ShowTimbre { get { return ((Status >> 58) & 1UL) != 0; } }
        public bool ChordB { get { return Capacity != 32 && ((Status >> 59) & 1UL) != 0; } }
        public int Song { get { return Capacity == 32 && ((Status >> 59) & 1UL) != 0 ? 2 : 1; } }
        public bool Paused { get { return ((Status >> 63) & 1UL) != 0; } }
        public int NoteMask { get { return (int)(Status & 4095UL); } }

        private static byte HexByte(string text, int offset)
        {
            return Convert.ToByte(text.Substring(offset, 2), 16);
        }

        private static byte HexNibble(char value)
        {
            if (value >= '0' && value <= '9') return (byte)(value - '0');
            if (value >= 'A' && value <= 'F') return (byte)(value - 'A' + 10);
            if (value >= 'a' && value <= 'f') return (byte)(value - 'a' + 10);
            throw new FormatException();
        }

        public static bool TryParse(string line, out DashboardSnapshot result)
        {
            result = null;
            if (String.IsNullOrEmpty(line) || !line.StartsWith("@S") || line.Length != 114)
                return false;
            try
            {
                DashboardSnapshot value = new DashboardSnapshot();
                value.Status = Convert.ToUInt64(line.Substring(2, 16), 16);
                // The FPGA keeps 64 four-bit waveform columns in 256 bits;
                // keep every second column for the 32-pixel PC trace.
                for (int i = 0; i < 32; i++)
                    value.Waveform[i] = HexNibble(line[18 + 63 - i * 2]);
                for (int i = 0; i < 8; i++)
                    value.Spectrum[i] = HexByte(line, 82 + (7 - i) * 2);
                for (int i = 0; i < 8; i++)
                    value.Lissajous[i] = HexByte(line, 98 + (7 - i) * 2);
                result = value;
                return true;
            }
            catch (FormatException) { return false; }
            catch (OverflowException) { return false; }
        }
    }

    public sealed class SerialTransport : IDisposable
    {
        private readonly CommandQueue commands = new CommandQueue();
        private readonly AutoResetEvent wake = new AutoResetEvent(false);
        private SerialPort port;
        private Thread worker;
        private volatile bool stopAfterDrain;
        private volatile bool connected;
        private volatile bool snapshotOutstanding;
        public event Action<string> Message;
        public event Action<DashboardSnapshot> Snapshot;
        public bool Connected { get { return connected; } }
        private void Report(string text) { Action<string> callback = Message; if (callback != null) callback(text); }
        public void Connect(string name)
        {
            if (worker != null) throw new InvalidOperationException("连接已经建立。");
            port = new SerialPort(name, 115200, Parity.None, 8, StopBits.One);
            port.Handshake = Handshake.None;
            port.NewLine = "\n";
            port.ReadTimeout = 1200;
            port.WriteTimeout = 1200;
            try { port.Open(); port.DiscardInBuffer(); }
            catch { port.Dispose(); port = null; throw; }
            connected = true;
            stopAfterDrain = false;
            snapshotOutstanding = false;
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Start();
            Send("D0"); Send("M1");
        }
        public void Send(string command)
        {
            if (!Regex.IsMatch(command, "^(N[0-9]{1,3}|O[0-9]{1,3}|X|D[01]|M[01]|T[0-9]{1,3}|I[01]|V[0-9]{1,3}|R[01])$"))
                throw new ArgumentException("不支持的命令。");
            if (command.StartsWith("V") && Int32.Parse(command.Substring(1)) > 100) throw new ArgumentException("音量必须为 0 到 100。");
            if (command.StartsWith("T") && Int32.Parse(command.Substring(1)) > 255)
                throw new ArgumentException("音色权重必须为 0 到 255。");
            if (command.StartsWith("R") && Int32.Parse(command.Substring(1)) > 1)
                throw new ArgumentException("显示路由必须为 0（电脑）或 1（HDMI）。");
            if (!connected || stopAfterDrain) throw new InvalidOperationException("串口尚未连接。");
            commands.Add(command); wake.Set();
        }

        public bool RequestSnapshot()
        {
            if (!connected || stopAfterDrain || snapshotOutstanding) return false;
            snapshotOutstanding = true;
            try { commands.Add("Q"); wake.Set(); return true; }
            catch { snapshotOutstanding = false; throw; }
        }
        public void Panic(string next)
        {
            if (!connected || stopAfterDrain) return;
            if (next != null && next != "D0" && next != "D1") throw new ArgumentException("模式无效。");
            commands.Panic(next); wake.Set();
        }
        private void Run()
        {
            try
            {
                while (true)
                {
                    string command;
                    if (!commands.Take(out command))
                    {
                        if (stopAfterDrain) break;
                        wake.WaitOne(100); continue;
                    }
                    port.Write(command + "\r");
                    string reply = port.ReadLine().Trim();
                    if (command == "Q")
                    {
                        DashboardSnapshot snapshot;
                        if (!DashboardSnapshot.TryParse(reply, out snapshot))
                            throw new InvalidOperationException("Q 收到无效状态快照：" + reply);
                        Action<DashboardSnapshot> callback = Snapshot;
                        if (callback != null) callback(snapshot);
                        snapshotOutstanding = false;
                        continue;
                    }
                    if (reply != "OK")
                        throw new InvalidOperationException(command + " 收到 " + reply + "；请确认固件支持该命令，音色 T/R 命令需要本次版本。");
                    Report(command + " -> OK");
                }
            }
            catch (Exception error) { Report("ERROR: " + error.Message); }
            finally
            {
                snapshotOutstanding = false;
                connected = false;
                // Best effort fallback for an unexpected worker exit.  If the
                // UART is still usable, restore the board-side HDMI route
                // before closing it so a PC dashboard crash cannot leave the
                // external screen black indefinitely.  A removed cable or an
                // older bitstream may reject R1; either case is intentionally
                // ignored while tearing the transport down.
                try
                {
                    if (port != null && port.IsOpen)
                    {
                        port.Write("R1\r");
                        port.ReadLine();
                    }
                }
                catch { }
                if (port != null) { port.Close(); port.Dispose(); }
                Report("串口已关闭");
            }
        }
        public void Dispose()
        {
            if (worker == null) return;
            if (connected)
            {
                // Clear stale notes and put the HDMI route behind the panic
                // command.  The worker drains this pair before it exits.
                commands.Panic(null);
                commands.Add("R1");
                stopAfterDrain = true;
                wake.Set();
            }
            if (!worker.Join(2800))
            {
                if (port != null) port.Close();
                worker.Join(1500);
            }
            worker = null;
        }
    }

    public static class KeyboardChecks
    {
        private static void Check(bool ok, string why) { if (!ok) throw new Exception(why); }
        public static void Run()
        {
            KeyboardState state = new KeyboardState();
            Check(state.Press(65, 0) == "N60", "keydown did not send Note On");
            Check(state.Press(65, 0) == null, "auto-repeat retriggered held note");
            Check(state.Press(83, 2) == "N62" && state.HeldCount == 2, "chord input failed");
            state.BaseNote = 72;
            Check(state.Release(65) == "O60", "octave change lost original Note Off");
            Check(state.Release(65) == null, "duplicate keyup generated an event");
            state.Clear();
            Check(state.HeldCount == 0 && state.Release(83) == null, "panic left held state");
            Check(state.Press(65, 0) == "N72", "repress failed");
            state.Clear();
            Check(state.Press(65, 0) == null, "panic allowed auto-repeat to restart held key");
            Check(state.Release(65) == null && state.Press(65, 0) == "N72", "release did not unblock panic key");
            CommandQueue q = new CommandQueue(); string item;
            q.Add("N60"); q.Add("N64"); q.Panic("D1");
            Check(q.Take(out item) && item == "X", "panic did not clear stale Note Ons");
            Check(q.Take(out item) && item == "D1", "mode did not follow panic");
            Check(!q.Take(out item), "stale queue entries survived panic");
            q.Add("T0"); q.Add("T64"); q.Add("N60"); q.Add("T255");
            Check(q.Take(out item) && item == "N60", "timbre delayed note event");
            Check(q.Take(out item) && item == "T255" && !q.Take(out item), "timbre coalescing failed");
            q.Add("T160"); q.Panic(null);
            Check(q.Take(out item) && item == "X" && !q.Take(out item), "panic retained stale timbre");
            CommandQueue safeClose = new CommandQueue();
            safeClose.Add("N60"); safeClose.Panic(null); safeClose.Add("R1");
            Check(safeClose.Take(out item) && item == "X", "safe close did not put panic first");
            Check(safeClose.Take(out item) && item == "R1" && !safeClose.Take(out item),
                "safe close did not leave HDMI route as the final command");

            int offset;
            Check(KeyboardLayout.TryOffset('Z', out offset) && offset == -12,
                "lower-row C3 key did not map one octave below");
            Check(KeyboardLayout.TryOffset('Q', out offset) && offset == 0,
                "upper-row C4 key did not map to base note");
            Check(KeyboardLayout.TryOffset('U', out offset) && offset == 11,
                "upper-row B4 key did not map to offset 11");
            Check(KeyboardLayout.TryOffset('A', out offset) && offset == 0,
                "legacy C4 alias disappeared");
            Check(KeyboardLayout.TryOffset('F', out offset) && offset == 5,
                "legacy F4 alias disappeared");
            Check(KeyboardLayout.TryOffset('K', out offset) && offset == 12,
                "legacy C5 alias disappeared");
            Check(KeyboardLayout.ShiftBase(60, 12) == 72, "octave up did not shift twelve semitones");
            Check(KeyboardLayout.ShiftBase(84, 12) == 84, "octave upper bound was not clamped");
            Check(KeyboardLayout.ShiftBase(36, -12) == 36, "octave lower bound was not clamped");
            string[] testNotes = KeyboardLayout.PolyphonyTestNotes(60);
            Check(String.Join(",", testNotes) == "N60,N64,N67,N72",
                "four-note polyphony test chord is wrong");
            Check(KeyboardLayout.TimbreForFunctionKey(112) == 250, "F1 did not select piano soft");
            Check(KeyboardLayout.TimbreForFunctionKey(113) == 251, "F2 did not select piano mellow");
            Check(KeyboardLayout.TimbreForFunctionKey(114) == 252, "F3 did not select piano medium");
            Check(KeyboardLayout.TimbreForFunctionKey(115) == 253, "F4 did not select piano bright");
            Check(KeyboardLayout.TimbreForFunctionKey(116) == 254, "F5 did not select piano hard");
            DashboardSnapshot snapshot;
            Check(DashboardSnapshot.TryParse("@S" + new String('0', 112), out snapshot),
                "dashboard Q snapshot parser rejected a zero frame");
            Check(snapshot.ActiveCount == 0 && snapshot.Waveform.Length == 32 &&
                  !DashboardSnapshot.TryParse("@S00", out snapshot),
                "dashboard Q snapshot length checks failed");
            ulong probeStatus = (2UL << 60) | (1UL << 62) | (1UL << 41) | (1UL << 59) |
                (64UL << 16) | (100UL << 23) | (64UL << 31) | (1UL << 42) | (252UL << 48) | 0x11UL;
            Check(DashboardSnapshot.TryParse("@S" + probeStatus.ToString("X16") + new String('0', 96), out snapshot) &&
                snapshot.ActiveCount == 32 && snapshot.Capacity == 32 && snapshot.Sustain && snapshot.Song == 2 &&
                snapshot.LeadNote == 64 && snapshot.LeadVelocity == 100 && snapshot.Pressure == 1024 &&
                snapshot.Piano && snapshot.Timbre == 252 && snapshot.NoteMask == 0x11,
                "32-voice hardware status schema mismatch");
            char[] frame = ("@S" + new String('0', 112)).ToCharArray();
            frame[18 + 63] = 'F';
            Check(DashboardSnapshot.TryParse(new String(frame), out snapshot) && snapshot.Waveform[0] == 15,
                "dashboard waveform nibble order failed");
            Console.WriteLine("PASS keyboard: press/release, chord, panic, range, octave, piano keys and dashboard parser");
        }
        public static void Smoke(string port)
        {
            int acknowledgements = 0;
            string failure = null;
            ManualResetEvent done = new ManualResetEvent(false);
            SerialTransport transport = new SerialTransport();
            transport.Message += delegate(string message)
            {
                Console.WriteLine(message);
                if (message.StartsWith("ERROR:")) { failure = message; done.Set(); }
                if (message.EndsWith(" -> OK") && Interlocked.Increment(ref acknowledgements) == 8) done.Set();
            };
            try
            {
                transport.Connect(port);
                foreach (string command in new string[] { "N60", "N64", "N67", "O60", "O64", "O67" })
                    transport.Send(command);
                Check(done.WaitOne(3500), "hardware replies timed out");
                Check(failure == null && acknowledgements == 8, "hardware rejected keyboard commands: " + failure);
            }
            finally { transport.Dispose(); }
            Check(failure == null && acknowledgements == 10,
                "disconnect did not acknowledge final panic and HDMI route");
            Console.WriteLine("PASS serial transport: mode, chord, Note Off, panic and HDMI fallback acknowledged");
        }
    }
}
