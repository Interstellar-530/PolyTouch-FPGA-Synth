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

    public sealed class SerialTransport : IDisposable
    {
        private readonly CommandQueue commands = new CommandQueue();
        private readonly AutoResetEvent wake = new AutoResetEvent(false);
        private SerialPort port;
        private Thread worker;
        private volatile bool stopAfterDrain;
        private volatile bool connected;
        public event Action<string> Message;
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
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Start();
            Send("D0"); Send("M1");
        }
        public void Send(string command)
        {
            if (!Regex.IsMatch(command, "^(N[0-9]{1,3}|O[0-9]{1,3}|X|D[01]|M[01]|T[0-9]{1,3}|I[01])$"))
                throw new ArgumentException("不支持的命令。");
            if (command.StartsWith("T") && Int32.Parse(command.Substring(1)) > 255)
                throw new ArgumentException("音色权重必须为 0 到 255。");
            if (!connected || stopAfterDrain) throw new InvalidOperationException("串口尚未连接。");
            commands.Add(command); wake.Set();
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
                    if (reply != "OK")
                        throw new InvalidOperationException(command + " 收到 " + reply + "；请确认固件支持该命令，音色 T 命令需要本次版本。");
                    Report(command + " -> OK");
                }
            }
            catch (Exception error) { Report("ERROR: " + error.Message); }
            finally
            {
                connected = false;
                if (port != null) { port.Close(); port.Dispose(); }
                Report("串口已关闭");
            }
        }
        public void Dispose()
        {
            if (worker == null) return;
            if (connected) { commands.Panic(null); stopAfterDrain = true; wake.Set(); }
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
            Console.WriteLine("PASS keyboard: press/release, chord, panic, range, octave and piano hardness keys");
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
            Check(failure == null && acknowledgements == 9, "disconnect did not acknowledge final panic");
            Console.WriteLine("PASS serial transport: mode, chord, Note Off and closing panic acknowledged");
        }
    }
}
