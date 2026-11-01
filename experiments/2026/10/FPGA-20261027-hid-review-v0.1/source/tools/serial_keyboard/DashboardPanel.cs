using System;
using System.Drawing;
using System.Windows.Forms;

namespace PolyTouchPc
{
    public sealed class DashboardPanel : Panel
    {
        private DashboardSnapshot snapshot;
        private readonly Font titleFont = new Font("Microsoft YaHei UI", 18, FontStyle.Bold);
        private readonly Font bodyFont = new Font("Microsoft YaHei UI", 10, FontStyle.Regular);
        private readonly Font smallFont = new Font("Consolas", 9, FontStyle.Regular);

        public DashboardPanel()
        {
            BackColor = Color.FromArgb(13, 20, 34);
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer, true);
            snapshot = new DashboardSnapshot();
        }

        public void SetSnapshot(DashboardSnapshot value)
        {
            if (value == null) return;
            snapshot = value;
            Invalidate();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                titleFont.Dispose(); bodyFont.Dispose(); smallFont.Dispose();
            }
            base.Dispose(disposing);
        }

        private static void DrawText(Graphics g, string text, Font font, Brush brush, float x, float y)
        {
            g.DrawString(text, font, brush, x, y);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.Clear(BackColor);
            int w = Math.Max(640, ClientSize.Width);
            int h = Math.Max(420, ClientSize.Height);
            using (Brush white = new SolidBrush(Color.FromArgb(235, 242, 252)))
            using (Brush muted = new SolidBrush(Color.FromArgb(150, 170, 195)))
            using (Brush cyan = new SolidBrush(Color.FromArgb(74, 220, 210)))
            using (Pen grid = new Pen(Color.FromArgb(42, 63, 88)))
            using (Pen trace = new Pen(Color.FromArgb(74, 220, 210), 2.0f))
            {
                DrawText(g, "PolyTouch FPGA Dashboard", titleFont, white, 28, 20);
                DrawText(g, "电脑显示 · F7 切换到外接 HDMI", bodyFont, muted, 32, 55);
                DrawText(g, snapshot.Guitar ? "吉他" : "钢琴", bodyFont, cyan, w - 180, 28);
                DrawText(g, snapshot.Muted ? "MUTED" : (snapshot.Demo ? "DEMO" : "MANUAL"), bodyFont,
                    snapshot.Muted ? Brushes.OrangeRed : cyan, w - 180, 55);

                int cardY = 90;
                Card(g, "活跃声部", snapshot.ActiveCount.ToString(), 28, cardY, 150, 64, white, cyan);
                Card(g, "主音符", snapshot.LeadNote == 0 ? "--" : NoteName(snapshot.LeadNote), 190, cardY, 150, 64, white, cyan);
                Card(g, "力度", snapshot.LeadVelocity.ToString(), 352, cardY, 150, 64, white, cyan);
                Card(g, "压力", snapshot.Pressure.ToString(), 514, cardY, 150, 64, white, cyan);
                Card(g, "音色", snapshot.ShowTimbre ? snapshot.Timbre.ToString() : "默认", 676, cardY, 150, 64, white, cyan);
                Card(g, "速度", (snapshot.Tempo + 1).ToString(), 838, cardY, 120, 64, white, cyan);

                int padTop = 178;
                int padW = Math.Max(54, (w - 56) / 12 - 6);
                for (int i = 0; i < 12; i++)
                {
                    int x = 28 + i * (padW + 6);
                    bool active = (snapshot.NoteMask & (1 << i)) != 0;
                    using (Brush fill = new SolidBrush(active ? Color.FromArgb(33, 132, 132) :
                        (IsSharp(i) ? Color.FromArgb(35, 48, 69) : Color.FromArgb(26, 37, 54))))
                    using (Pen border = new Pen(active ? Color.FromArgb(94, 240, 210) : Color.FromArgb(64, 86, 112)))
                    {
                        g.FillRectangle(fill, x, padTop, padW, 72);
                        g.DrawRectangle(border, x, padTop, padW, 72);
                    }
                    DrawText(g, NoteName(60 + i), smallFont, active ? Brushes.White : muted, x + 8, padTop + 28);
                }

                int plotY = Math.Min(h - 172, 290);
                DrawText(g, "波形", bodyFont, white, 28, plotY - 28);
                DrawText(g, "频带活动", bodyFont, white, w / 2 + 20, plotY - 28);
                int plotW = w / 2 - 58;
                int plotH = 128;
                g.DrawRectangle(grid, 28, plotY, plotW, plotH);
                for (int i = 1; i < 4; i++)
                    g.DrawLine(grid, 28, plotY + i * plotH / 4, 28 + plotW, plotY + i * plotH / 4);
                PointF previous = PointF.Empty;
                for (int i = 0; i < snapshot.Waveform.Length; i++)
                {
                    float x = 30 + i * (plotW - 4) / 31.0f;
                    float y = plotY + plotH - 4 - snapshot.Waveform[i] * (plotH - 8) / 16.0f;
                    PointF current = new PointF(x, y);
                    if (i != 0) g.DrawLine(trace, previous, current);
                    previous = current;
                }
                int barsX = w / 2 + 20;
                int barsW = w - barsX - 28;
                g.DrawRectangle(grid, barsX, plotY, barsW, plotH);
                for (int i = 0; i < 8; i++)
                {
                    int bw = Math.Max(6, barsW / 10);
                    int bx = barsX + 8 + i * (barsW - 16) / 8;
                    int bh = snapshot.Spectrum[i] * (plotH - 16) / 255;
                    using (Brush bar = new SolidBrush(Color.FromArgb(100, 164, 240)))
                        g.FillRectangle(bar, bx, plotY + plotH - 8 - bh, bw, bh);
                }
                DrawText(g, "相位图", bodyFont, white, 28, h - 145);
                int gridX = 28, gridY = h - 115, cell = 12;
                for (int y = 0; y < 8; y++)
                    for (int x = 0; x < 8; x++)
                    {
                        bool on = (snapshot.Lissajous[y] & (1 << x)) != 0;
                        using (Brush cellBrush = new SolidBrush(on ? Color.FromArgb(241, 180, 77) : Color.FromArgb(34, 50, 70)))
                            g.FillRectangle(cellBrush, gridX + x * cell, gridY + y * cell, cell - 2, cell - 2);
                    }
                DrawText(g, "Q 快照 · 115200 8N1", smallFont, muted, w - 190, h - 26);
            }
        }

        private static void Card(Graphics g, string name, string value, int x, int y, int width, int height,
            Brush white, Brush accent)
        {
            using (Brush fill = new SolidBrush(Color.FromArgb(23, 34, 53)))
            using (Pen border = new Pen(Color.FromArgb(48, 72, 100)))
            {
                g.FillRectangle(fill, x, y, width, height);
                g.DrawRectangle(border, x, y, width, height);
            }
            using (Font labelFont = new Font("Microsoft YaHei UI", 9))
            using (Font valueFont = new Font("Consolas", 16, FontStyle.Bold))
            {
                g.DrawString(name, labelFont, accent, x + 10, y + 8);
                g.DrawString(value, valueFont, white, x + 10, y + 29);
            }
        }

        private static bool IsSharp(int index)
        {
            return index == 1 || index == 3 || index == 6 || index == 8 || index == 10;
        }

        private static string NoteName(int note)
        {
            string[] names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
            if (note <= 0) return "--";
            int octave = note / 12 - 1;
            return names[note % 12] + octave;
        }
    }
}
