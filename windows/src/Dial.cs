// La ghiera di Pulsar per Windows, rifatta da Moduli/Mixer/ghiera.swift del Mac.
// Sta sul bordo sinistro, sotto il notch, fuori dallo schermo: esce quando il mouse tocca il bordo a quell'altezza
// e rientra mezzo secondo dopo che il mouse si allontana. 40 tacche, triangolino in cima, puntini 5x5, numero e modo
// al centro. Rotella o trascinamento sulla corona per il valore; tocco al centro = muto o avvia/ferma il timer.
// Modi: Volume e Timer. Il mixer per app del Mac (Mix) qui non c'è ancora.
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace Pulsar
{
    enum DialMode { Volume, Timer }

    class DialWindow : Window
    {
        const double R = 16, Ring = 148, PadX = 16;
        static readonly double PanelW = PadX + Ring + PadX;
        static readonly double PanelH = R * 2 + 4 + Ring + 12 + 26 + R * 2 + 4;
        static readonly Color BarTop = T.C("#2A2D3A"), Bar = T.C("#252833");

        DialMode mode = DialMode.Volume;
        int timerMinutes = 25;
        DateTime? timerEnd;
        bool shown;
        DateTime leftAt = DateTime.MaxValue;
        DispatcherTimer watch;
        RingFace face;
        Border[] modeButtons = new Border[2];

        public DialWindow()
        {
            Title = "Pulsar dial";
            WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
            Topmost = true; ShowInTaskbar = false; ResizeMode = ResizeMode.NoResize;
            Width = PanelW + 24; Height = PanelH;          // 24 in più a destra per l'ombra
            Top = 32 + 56;                                  // sotto il notch
            Left = -Width;
            FontFamily = T.UI;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            try { timerMinutes = Math.Max(1, Math.Min(60, int.Parse(Settings.Get("dial.timer", "25")))); } catch { }

            var root = new Grid { Width = PanelW, Height = PanelH, HorizontalAlignment = HorizontalAlignment.Left };
            var bg = new System.Windows.Shapes.Path
            {
                Data = EdgeShape(PanelW, PanelH, R),
                Fill = new LinearGradientBrush(BarTop, Bar, 90)
            };   // niente DropShadowEffect: pesante senza scheda grafica
            root.Children.Add(bg);

            var col = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            face = new RingFace { Width = Ring, Height = Ring };
            face.Center += OnCenter;
            face.Set += OnSet;
            col.Children.Add(face);
            var modes = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 0) };
            string[] glyphs = { T.GVol, "" };   // Volume, Timer (cronometro)
            string[] tips = { "Volume", "Timer" };
            for (int i = 0; i < 2; i++)
            {
                int k = i;
                var t = new TextBlock { Text = glyphs[i], FontFamily = T.Icons, FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                var b = new Border { Width = 30, Height = 26, CornerRadius = new CornerRadius(13), Child = t, Cursor = Cursors.Hand, ToolTip = tips[i], Margin = new Thickness(i == 0 ? 0 : 6, 0, 0, 0), Background = Brushes.Transparent };
                b.MouseLeftButtonUp += (s, e) => { mode = (DialMode)k; Settings.Set("dial.mode", mode.ToString()); Refresh(); e.Handled = true; };
                modeButtons[i] = b;
                modes.Children.Add(b);
            }
            col.Children.Add(modes);
            root.Children.Add(col);
            Content = root;

            MouseWheel += (s, e) => { Nudge(e.Delta / 120.0); e.Handled = true; };
            if (Settings.Get("dial.mode", "Volume") == "Timer") mode = DialMode.Timer;

            watch = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(80) };
            watch.Tick += (s, e) => Watch();
            watch.Start();
            var tick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            tick.Tick += (s, e) => { if (shown || timerEnd != null) Refresh(); };
            tick.Start();
            Refresh();
        }

        /// <summary>La forma attaccata al bordo sinistro: raccordi concavi in alto e in basso (TabShape del Mac, specchiata).</summary>
        static Geometry EdgeShape(double w, double h, double r)
        {
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(new Point(0, 0), true, true);
                c.QuadraticBezierTo(new Point(0, r), new Point(r, r), true, true);           // raccordo concavo in alto
                c.LineTo(new Point(w - r, r), true, true);
                c.QuadraticBezierTo(new Point(w, r), new Point(w, 2 * r), true, true);
                c.LineTo(new Point(w, h - 2 * r), true, true);
                c.QuadraticBezierTo(new Point(w, h - r), new Point(w - r, h - r), true, true);
                c.LineTo(new Point(r, h - r), true, true);
                c.QuadraticBezierTo(new Point(0, h - r), new Point(0, h), true, true);       // raccordo concavo in basso
            }
            g.Freeze();
            return g;
        }

        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
        struct POINT { public int X, Y; }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            var h = new WindowInteropHelper(this).Handle;
            // fuori da Alt+Tab e non ruba il fuoco alla finestra in uso
            SetWindowLong(h, -20, GetWindowLong(h, -20) | 0x80 | 0x08000000);
        }

        /// <summary>Il mouse sul bordo sinistro all'altezza della ghiera la fa uscire; mezzo secondo fuori la rimette via.</summary>
        void Watch()
        {
            POINT p;
            if (!GetCursorPos(out p)) return;
            var src = PresentationSource.FromVisual(this);
            double sx = 1, sy = 1;
            if (src != null && src.CompositionTarget != null) { sx = src.CompositionTarget.TransformToDevice.M11; sy = src.CompositionTarget.TransformToDevice.M22; }
            double x = p.X / sx, y = p.Y / sy;
            bool inBand = y >= Top + R && y <= Top + PanelH - R;
            if (!shown)
            {
                if (x <= 1 && inBand) Reveal();
                return;
            }
            bool over = x <= PanelW + 6 && y >= Top - 6 && y <= Top + PanelH + 6;
            if (over || face.Dragging) { leftAt = DateTime.MaxValue; return; }
            if (leftAt == DateTime.MaxValue) leftAt = DateTime.Now;
            if ((DateTime.Now - leftAt).TotalSeconds > 0.5 && !holdOpen) HideDial();
        }

        bool holdOpen;
        public void Reveal(double hideAfter = 0)
        {
            Refresh();
            if (!shown)
            {
                shown = true;
                Show();
                BeginAnimation(LeftProperty, new DoubleAnimation(-Width, 0, TimeSpan.FromMilliseconds(380)) { EasingFunction = new CubicEase() });
            }
            leftAt = DateTime.MaxValue;
            if (hideAfter > 0)
            {
                holdOpen = true;
                var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(hideAfter) };
                t.Tick += (s, e) => { t.Stop(); holdOpen = false; leftAt = DateTime.Now; };
                t.Start();
            }
        }

        void HideDial()
        {
            if (!shown) return;
            shown = false;
            leftAt = DateTime.MaxValue;
            BeginAnimation(LeftProperty, new DoubleAnimation(-Width, TimeSpan.FromMilliseconds(300)) { EasingFunction = new CubicEase() });
        }

        // ---------------- valori ----------------

        double Level()
        {
            if (mode == DialMode.Volume) { var v = Audio.Get(); return v < 0 ? 0 : (Audio.Muted() ? 0 : v); }
            if (timerEnd != null) return Math.Max(0, (timerEnd.Value - DateTime.Now).TotalSeconds) / (timerMinutes * 60.0);
            return timerMinutes / 60.0;
        }

        void Nudge(double ticks)
        {
            if (mode == DialMode.Volume)
            {
                var v = Audio.Get(); if (v < 0) return;
                Audio.Set((float)Math.Max(0, Math.Min(1, v + ticks / 40)));
            }
            else if (timerEnd == null)
            {
                timerMinutes = Math.Max(1, Math.Min(60, timerMinutes + (int)Math.Round(ticks)));
                Settings.Set("dial.timer", timerMinutes.ToString());
            }
            Refresh();
        }

        void OnSet(double f)
        {
            f = Math.Max(0, Math.Min(1, f));
            if (mode == DialMode.Volume) { if (Audio.Get() >= 0) Audio.Set((float)f); }
            else if (timerEnd == null) { timerMinutes = Math.Max(1, (int)Math.Round(f * 60)); Settings.Set("dial.timer", timerMinutes.ToString()); }
            Refresh();
        }

        void OnCenter()
        {
            if (mode == DialMode.Volume) { if (Audio.Get() >= 0) Audio.ToggleMute(); }
            else timerEnd = timerEnd == null ? (DateTime?)DateTime.Now.AddMinutes(timerMinutes) : null;
            Refresh();
        }

        void Refresh()
        {
            for (int i = 0; i < 2; i++)
            {
                bool on = (int)mode == i;
                modeButtons[i].Background = on ? T.B("#000000", 0.28) : Brushes.Transparent;
                ((TextBlock)modeButtons[i].Child).Foreground = on ? Brushes.White : T.B("#FFFFFF", 0.56);
            }
            if (mode == DialMode.Volume)
            {
                var v = Audio.Get();
                bool muted = v >= 0 && Audio.Muted();
                face.Kind = v < 0 || muted ? DotKind.Mute : DotKind.Volume;
                face.Value = v < 0 ? "--" : muted ? "0" : Math.Round(v * 100).ToString();
                face.Label = v < 0 ? "NO OUTPUT" : "VOLUME";
                face.Rising = true;
            }
            else
            {
                if (timerEnd != null && DateTime.Now >= timerEnd.Value) TimerDone();
                face.Kind = timerEnd == null ? DotKind.Timer : DotKind.TimerRunning;
                if (timerEnd == null) face.Value = timerMinutes + ":00";
                else { int s = (int)Math.Max(0, Math.Round((timerEnd.Value - DateTime.Now).TotalSeconds)); face.Value = (s / 60) + ":" + (s % 60).ToString("00"); }
                face.Label = "TIMER";
                face.Rising = false;
            }
            face.Level = Level();
            face.InvalidateVisual();
        }

        void TimerDone()
        {
            timerEnd = null;
            System.Media.SystemSounds.Asterisk.Play();
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
            t.Tick += (s, e) => { t.Stop(); System.Media.SystemSounds.Asterisk.Play(); };
            t.Start();
            mode = DialMode.Timer;
            Reveal(4);
        }
    }

    enum DotKind { Volume, Mute, Timer, TimerRunning }

    /// <summary>Il disegno della ghiera (RingFace del Mac): 148, 40 tacche, triangolino, puntini, numero, modo.</summary>
    class RingFace : Animated
    {
        public double Level;
        public string Value = "", Label = "";
        public DotKind Kind = DotKind.Volume;
        public bool Rising = true;
        public bool Dragging;
        public event Action Center;
        public event Action<double> Set;

        static readonly Color Mint = T.C("#DBE0F0"), Azzurro = T.C("#8FC7FF"), Tail = T.C("#808FD1");
        static readonly Brush TickOff = T.B("#FFFFFF", 0.12);
        static readonly Pen Edge = new Pen(T.B("#FFFFFF", 0.07), 1);

        public RingFace()
        {
            IsHitTestVisible = true;
            Cursor = Cursors.Hand;
            MouseLeftButtonDown += (s, e) =>
            {
                var p = e.GetPosition(this);
                if (Dist(p) > 42) { Dragging = true; CaptureMouse(); FromAngle(p); }
                e.Handled = true;
            };
            MouseMove += (s, e) => { if (Dragging) FromAngle(e.GetPosition(this)); };
            MouseLeftButtonUp += (s, e) =>
            {
                var p = e.GetPosition(this);
                if (Dragging) { Dragging = false; ReleaseMouseCapture(); }
                else if (Dist(p) <= 42) { var h = Center; if (h != null) h(); }
                e.Handled = true;
            };
        }

        double Dist(Point p) { double c = ActualWidth / 2; return Math.Sqrt((p.X - c) * (p.X - c) + (p.Y - c) * (p.Y - c)); }

        void FromAngle(Point p)
        {
            double c = ActualWidth / 2, dx = p.X - c, dy = p.Y - c;
            if (Math.Sqrt(dx * dx + dy * dy) <= 42) return;
            double a = Math.Atan2(dx, -dy) / (2 * Math.PI);
            if (a < 0) a += 1;
            var h = Set; if (h != null) h(a);
        }

        static Color Mix(Color a, Color b, double t)
        {
            t = Math.Max(0, Math.Min(1, t));
            return Color.FromArgb(255, (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));
        }

        protected override void OnRender(DrawingContext dc)
        {
            double size = ActualWidth, c = size / 2;
            if (size <= 0) return;
            var faceFill = new LinearGradientBrush(T.C("#2A2D3A"), T.C("#252833"), 90);
            dc.DrawEllipse(faceFill, Edge, new Point(c, c), c - 0.5, c - 0.5);

            int ticks = 40, lit = (int)Math.Round(Math.Max(0, Math.Min(1, Level)) * ticks);
            for (int i = 0; i < ticks; i++)
            {
                double h = i % 5 == 0 ? 12 : 9;
                Brush b;
                if (i < lit)
                {
                    var col = Rising ? Mix(Mint, Azzurro, (double)i / (ticks - 1)) : Mint;
                    col.A = (byte)((0.55 + 0.45 * i / ticks) * 255);
                    b = Fill(col);
                }
                else b = TickOff;
                dc.PushTransform(new RotateTransform((double)i / ticks * 360, c, c));
                double cy = 15;   // centro della tacca a 15 dal bordo
                dc.DrawRoundedRectangle(b, null, new Rect(c - 1.5, cy - h / 2, 3, h), 1.5, 1.5);
                dc.Pop();
            }
            // triangolino in cima, a 4 dal bordo
            var tri = new StreamGeometry();
            using (var g = tri.Open())
            {
                g.BeginFigure(new Point(c - 3.5, 1), true, true);
                g.LineTo(new Point(c + 3.5, 1), true, true);
                g.LineTo(new Point(c, 7), true, true);
            }
            tri.Freeze();
            dc.DrawGeometry(Fill(Mint), null, tri);

            // centro: puntini 22, numero 24, modo in mono 9
            double dotsTop = c - 34;
            DrawDots(dc, new Rect(c - 11, dotsTop, 22, 22));
            var num = Text(Value, 24, Brushes.White, T.UI, 0);
            dc.DrawText(num, new Point(c - num.Width / 2, dotsTop + 22 + 2));
            var lab = Text(Label, 9, T.B("#FFFFFF", 0.34), T.Mono, 1.4);
            dc.DrawText(lab, new Point(c - lab.Width / 2, dotsTop + 22 + 2 + num.Height + 1));
        }

        FormattedText Text(string s, double size, Brush b, FontFamily f, double tracking)
        {
            // il Mac ha spaziatura 1,4 nel mono 9; gli spazi fini su Windows allargavano troppo, quindi niente spaziatura
            return new FormattedText(s ?? "", System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(f, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal), size, b, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        }

        static readonly int[,] RingCells = { { 2, 0 }, { 3, 0 }, { 4, 0 }, { 4, 1 }, { 4, 2 }, { 4, 3 }, { 4, 4 }, { 3, 4 }, { 2, 4 }, { 1, 4 }, { 0, 4 }, { 0, 3 }, { 0, 2 }, { 0, 1 }, { 0, 0 }, { 1, 0 } };

        void DrawDots(DrawingContext dc, Rect r)
        {
            double t = Clock.Now, cell = r.Width / 5, px = cell * 0.78, lv = Math.Max(0, Math.Min(1, Level));
            var hi = Kind == DotKind.Volume ? Mix(Colors.White, Azzurro, lv) : Colors.White;
            for (int y = 0; y < 5; y++)
                for (int x = 0; x < 5; x++)
                {
                    double a, w;
                    Value5(x, y, t, lv, out a, out w);
                    var rect = new Rect(r.X + x * cell + (cell - px) / 2, r.Y + y * cell + (cell - px) / 2, px, px);
                    var bc = Tail; bc.A = (byte)(Math.Max(0, Math.Min(1, a)) * 255);
                    dc.DrawRoundedRectangle(Fill(bc), null, rect, px * 0.28, px * 0.28);
                    if (w > 0.01) { var hc = hi; hc.A = (byte)(Math.Max(0, Math.Min(1, w)) * 255); dc.DrawRoundedRectangle(Fill(hc), null, rect, px * 0.28, px * 0.28); }
                }
        }

        static double Ease(double v) { var c = Math.Min(1, Math.Max(0, v)); return c * c * (3 - 2 * c); }

        /// <summary>Le formule di DotGlyph.value del Mac per volume, muto e timer.</summary>
        void Value5(int x, int y, double t, double lv, out double a, out double w)
        {
            const double off = 0.08;
            if (Kind == DotKind.Volume)
            {
                double amp = 0.55 + 0.45 * Math.Min(1, lv * 2.5);
                double h = lv > 0.005 ? lv * 4.6 + 0.4 + amp * Math.Sin(t * 1.9 + x * 1.25) : 0;
                double row = 4 - y, fill = Ease(h - row);
                bool top = fill > 0.05 && h - row < 1.15;
                double scan = 2 + 2.2 * Math.Sin(t * 1.3), luce = Math.Exp(-(x - scan) * (x - scan) / 0.7);
                a = off + 0.62 * fill; w = top ? (0.35 + 0.55 * luce) * fill : 0.25 * luce * fill;
                return;
            }
            if (Kind == DotKind.Mute)
            {
                bool onX = x == y || x == 4 - y;
                a = onX ? 0.28 + 0.14 * (0.5 + 0.5 * Math.Sin(t * 1.6)) : off; w = 0;
                return;
            }
            int idx = -1;
            for (int i = 0; i < 16; i++) if (RingCells[i, 0] == x && RingCells[i, 1] == y) { idx = i; break; }
            if (Math.Max(Math.Abs(x - 2), Math.Abs(y - 2)) != 2 || idx < 0)
            {
                int d = Math.Max(Math.Abs(x - 2), Math.Abs(y - 2));
                a = d == 0 ? 0.2 + 0.2 * (0.5 + 0.5 * Math.Sin(t * 2.4)) : off; w = 0;
                return;
            }
            bool litCell = idx < lv * 16 + 0.2, run = Kind == DotKind.TimerRunning;
            double head = (t * (run ? 2.2 : 1.0)) % 16, dist = idx - head;
            dist -= 16 * Math.Round(dist / 16);
            w = (run ? 0.7 : 0.35) * Math.Exp(-dist * dist / 0.5);
            double coda = 0.45 * Math.Exp(-Math.Max(0, -dist) / 2.4) * (dist <= 0 ? 1 : Math.Exp(-dist * dist / 0.3));
            a = Math.Max(litCell ? 0.55 : off, run ? coda : coda * 0.5);
        }
    }

    /// <summary>Impostazioni semplici in %APPDATA%\Pulsar\settings.txt (chiave=valore).</summary>
    static class Settings
    {
        static string FilePath { get { return System.IO.Path.Combine(Limits.Folder, "settings.txt"); } }
        public static string Get(string key, string def)
        {
            try
            {
                if (!System.IO.File.Exists(FilePath)) return def;
                foreach (var l in System.IO.File.ReadAllLines(FilePath))
                {
                    int i = l.IndexOf('=');
                    if (i > 0 && l.Substring(0, i) == key) return l.Substring(i + 1);
                }
            }
            catch { }
            return def;
        }
        public static void Set(string key, string value)
        {
            try
            {
                System.IO.Directory.CreateDirectory(Limits.Folder);
                var lines = System.IO.File.Exists(FilePath) ? new System.Collections.Generic.List<string>(System.IO.File.ReadAllLines(FilePath)) : new System.Collections.Generic.List<string>();
                lines.RemoveAll(l => l.StartsWith(key + "="));
                lines.Add(key + "=" + value);
                System.IO.File.WriteAllLines(FilePath, lines);
            }
            catch { }
        }
    }
}
