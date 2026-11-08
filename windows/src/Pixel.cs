// I disegni a pixel dell'isola, rifatti dal codice del Mac: il razzo di Spazio (Core/Razzo.swift),
// il glifo 3x3 (PixelGlyph), il cielo a pixel della Casa a freddo (CieloPixel) e gli equalizzatori.
// Un solo orologio a 30 fotogrammi al secondo ridisegna quello che è visibile.
using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Pulsar
{
    static class Clock
    {
        static readonly DateTime start = DateTime.Now;
        public static double Now { get { return (DateTime.Now - start).TotalSeconds; } }
        public static event Action Tick;
        static DispatcherTimer timer;
        public static void Start()
        {
            if (timer != null) return;
            // priorità bassa: le animazioni non devono togliere il turno ai controlli del mouse (in VM senza scheda grafica succedeva)
            timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(50) };
            timer.Tick += (s, e) => { var h = Tick; if (h != null) h(); };
            timer.Start();
        }
    }

    /// <summary>Base: si ridisegna a ogni battito solo se è visibile.</summary>
    abstract class Animated : FrameworkElement
    {
        protected Animated()
        {
            Loaded += (s, e) => Clock.Tick += OnTick;
            Unloaded += (s, e) => Clock.Tick -= OnTick;
            IsHitTestVisible = false;
        }
        protected virtual void OnTick() { if (IsVisible && Opacity > 0) InvalidateVisual(); }
        protected static Brush Fill(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    }

    enum RocketPhase { Idle, Thrust, Wait, CatchFile, Loaded, Launch }

    class RocketView : Animated
    {
        static readonly string[] Ship =
        {
            ".....k.....",
            "....kwk....",
            "....kwk....",
            "...kwwwk...",
            "...kwbwk...",
            "..kwwbbwk..",
            "..kwwbbwk..",
            "..kwwwwsk..",
            "..kwwwwsk..",
            ".kowwwwsok.",
            "kooswwwsook",
            "kokssssskok",
            "k.kssssk..k",
            "...koook...",
            "....k.k....",
            "..........."
        };
        static readonly Brush W = Fill(T.C("#E8E6EF")), S = Fill(T.C("#969CB8")), O = Fill(T.C("#8FC7FF")), K = Fill(T.C("#0C0E16"));
        static readonly Brush B = Fill(T.C("#B9DCFF")), F1 = Fill(T.C("#E4F0FF")), F2 = Fill(T.C("#B9DCFF")), F3 = Fill(T.C("#8FC7FF"));
        static readonly Brush WinLight = Fill(T.C("#F2F7FF"));

        public double PixelSize = 1.15;
        public double Flame = 1;
        RocketPhase phase = RocketPhase.Idle;
        double phaseStart;
        public RocketPhase Phase
        {
            get { return phase; }
            set { if (phase != value) { phase = value; phaseStart = Clock.Now; } }
        }
        public void Relaunch() { phase = RocketPhase.Launch; phaseStart = Clock.Now; }

        protected override void OnRender(DrawingContext dc)
        {
            double p = PixelSize, w = ActualWidth, h = ActualHeight;
            if (w <= 0 || h <= 0) return;
            dc.PushClip(new RectangleGeometry(new Rect(0, 0, w, h)));
            double t = Clock.Now;
            double dx = 0, dy = 0, flameLen = 0;
            Brush win = B;
            switch (phase)
            {
                case RocketPhase.Idle:
                    dy = Math.Round(Math.Sin(t * 1.6) * 0.8); flameLen = 2 + Math.Abs(Math.Sin(t * 9)) * 1.5; break;
                case RocketPhase.Thrust:
                    dx = Math.Round(Math.Sin(t * 31) * 0.4); dy = -1; flameLen = 5 + 3 * Math.Abs(Math.Sin(t * 40)); break;
                case RocketPhase.Wait:
                    dy = Math.Round(Math.Sin(t * 1.1) * 0.6); flameLen = 0;
                    win = Math.Sin(t * 4) >= 0 ? WinLight : T.A3B; break;
                case RocketPhase.CatchFile:
                    dy = 1 + Math.Round(Math.Sin(t * 6) * 0.5); flameLen = 1.5 + Math.Abs(Math.Sin(t * 12));
                    win = Math.Sin(t * 5) >= 0 ? Fill(Color.FromRgb(214, 235, 255)) : Fill(Color.FromRgb(143, 199, 255)); break;
                case RocketPhase.Loaded:
                    dy = Math.Round(Math.Sin(t * 1.6) * 0.6); flameLen = 2 + Math.Abs(Math.Sin(t * 9)); win = WinLight; break;
                case RocketPhase.Launch:
                    {
                        double u = Math.Min(1, (t - phaseStart) / 2.4), hh = h / p + 18;
                        if (u < 0.55) { dy = -Math.Pow(u / 0.55, 2) * hh; flameLen = 6 + 3 * Math.Abs(Math.Sin(t * 40)); }
                        else
                        {
                            double x = (u - 0.55) / 0.45, e = 1 - Math.Pow(1 - x, 3);
                            dy = (1 - e) * hh; flameLen = 2 + 2 * (1 - x);
                        }
                        break;
                    }
            }
            double ox = Math.Round((w / p - 11) / 2 + dx);
            double oy = Math.Round((h / p - 16 - (Flame < 1 ? -2 : 0)) / 2 - 2 + dy);
            for (int r = 0; r < 16; r++)
                for (int c = 0; c < 11; c++)
                {
                    char ch = Ship[r][c];
                    Brush b = ch == 'w' ? W : ch == 's' ? S : ch == 'b' ? win : ch == 'o' ? O : ch == 'k' ? K : null;
                    if (b != null) Cell(dc, b, ox + c, oy + r, p);
                }
            int L = (int)Math.Round(flameLen * Flame);
            for (int i = 0; i < L; i++)
            {
                double f = (double)i / Math.Max(1, L);
                Brush b = f < 0.35 ? F1 : f < 0.70 ? F2 : F3;
                Cell(dc, b, ox + 5, oy + 15 + i, p);
                if (i < 0.6 * L) { Cell(dc, b, ox + 4, oy + 15 + i, p); Cell(dc, b, ox + 6, oy + 15 + i, p); }
            }
            dc.Pop();
        }

        static void Cell(DrawingContext dc, Brush b, double cx, double cy, double p)
        {
            double x = Math.Round(cx * p), y = Math.Round(cy * p);
            dc.DrawRectangle(b, null, new Rect(x, y, Math.Round((cx + 1) * p) - x, Math.Round((cy + 1) * p) - y));
        }
    }

    /// <summary>Griglia 3x3 che scatta ogni 0,16 s (PixelGlyph).</summary>
    class GlyphView : Animated
    {
        public Color[] Palette = { T.A2, T.A1, T.A3 };
        protected override void OnRender(DrawingContext dc)
        {
            double side = Math.Min(ActualWidth, ActualHeight);
            if (side <= 0) return;
            double k = side / 14.0, cell = 3.6 * k, gap = 1.5 * k, rad = 0.8 * k;
            double total = 3 * cell + 2 * gap, x0 = (ActualWidth - total) / 2, y0 = (ActualHeight - total) / 2;
            int t = (int)(Clock.Now / 0.16);
            for (int r = 0; r < 3; r++)
                for (int c = 0; c < 3; c++)
                {
                    int h = (r * 7 + c * 13 + t * 5 + (r * c + t) % 4) % 11;
                    var col = Palette[h % Palette.Length];
                    if (h < 4) col.A = (byte)(0.18 * 255);
                    dc.DrawRoundedRectangle(Fill(col), null, new Rect(x0 + c * (cell + gap), y0 + r * (cell + gap), cell, cell), rad, rad);
                }
        }
    }

    /// <summary>Razzo e glifo che si alternano ogni 7 s con una dissolvenza di 0,8 s (RazzoEGlifo).</summary>
    class RocketAndGlyph : System.Windows.Controls.Grid
    {
        readonly RocketView rocket = new RocketView { PixelSize = 1.15, Flame = 0.6 };
        readonly GlyphView glyph = new GlyphView { Width = 14, Height = 14 };
        public RocketAndGlyph()
        {
            Width = 18; Height = 25; ClipToBounds = true;
            Children.Add(rocket); Children.Add(glyph);
            Clock.Tick += () =>
            {
                double t = Clock.Now, inTurn = t % 7;
                bool rocketTurn = ((int)(t / 7)) % 2 == 0;
                double fade = Math.Min(1, inTurn / 0.8);
                fade = fade < 0.5 ? 2 * fade * fade : 1 - Math.Pow(-2 * fade + 2, 2) / 2;
                rocket.Opacity = rocketTurn ? fade : 1 - fade;
                glyph.Opacity = rocketTurn ? 1 - fade : fade;
            };
        }
    }

    /// <summary>Tre barre dell'equalizzatore nella compatta (MediaEqualizer).</summary>
    class EqBars : Animated
    {
        public bool Playing;
        static readonly Brush Bar = Fill(T.A2);
        protected override void OnRender(DrawingContext dc)
        {
            double t = Clock.Now, h = ActualHeight;
            for (int i = 0; i < 3; i++)
            {
                double bh = Playing ? 4 + 9 * Math.Abs(Math.Sin(t * (3.1 + 1.3 * i) + i)) : 4;
                bh = Math.Min(h, bh);
                dc.DrawRoundedRectangle(Bar, null, new Rect(i * 5, h - bh, 2.5, bh), 1.2, 1.2);
            }
        }
    }

    /// <summary>Equalizzatore a pixel 5x5 della tessera della musica (PixelEQ).</summary>
    class PixelEq : Animated
    {
        public bool Playing;
        public double CellSize = 2.4;
        static readonly Color Off = T.A("#EDEFF6", 0.10);
        protected override void OnRender(DrawingContext dc)
        {
            double t = Clock.Now, cell = CellSize, gap = 1.5, rad = cell * 0.25;
            Color[] rows = { T.A3, T.A3, T.A2, T.A2, T.A1 };
            for (int x = 0; x < 5; x++)
            {
                double wave = 2 + 1.6 * Math.Sin(t * (5.3 + 1.7 * x) + x) + 0.9 * Math.Sin(11 * t + x * x);
                int level = Playing ? Math.Max(1, Math.Min(5, 1 + (int)Math.Round(wave))) : 1;
                for (int r = 0; r < 5; r++)
                {
                    bool on = r < level;
                    var col = on ? rows[r] : Off;
                    dc.DrawRoundedRectangle(Fill(col), null, new Rect(x * (cell + gap), (4 - r) * (cell + gap), cell, cell), rad, rad);
                }
            }
        }
    }

    /// <summary>Il cielo a pixel della Casa a freddo (CieloPixel): celle da 4, 8 fotogrammi al secondo.</summary>
    class SkyView : FrameworkElement
    {
        static readonly int[] Perm = MakePerm();
        static readonly int[] Bayer = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
        static readonly Color[] Pal =
        {
            Color.FromRgb(21, 23, 30), Color.FromRgb(26, 29, 37), Color.FromRgb(32, 36, 46), Color.FromRgb(40, 45, 58),
            Color.FromRgb(53, 60, 76), Color.FromRgb(84, 112, 146), Color.FromRgb(138, 186, 232)
        };
        static readonly Color Star = Color.FromRgb(196, 206, 222);
        WriteableBitmap bmp; int cols, rows; double last = -1;

        public SkyView()
        {
            // un pixel per cella, ingrandito senza sfumare; l'elemento prende la misura del contenitore
            RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.NearestNeighbor);
            IsHitTestVisible = false;
            Loaded += (s, e) => Clock.Tick += Draw;
            Unloaded += (s, e) => Clock.Tick -= Draw;
            SizeChanged += (s, e) => { bmp = null; Draw(); };
        }

        protected override void OnRender(DrawingContext dc)
        {
            if (bmp != null) dc.DrawImage(bmp, new Rect(0, 0, ActualWidth, ActualHeight));
        }

        static int[] MakePerm()
        {
            var p = new int[256];
            for (int i = 0; i < 256; i++) p[i] = i;
            for (int i = 255; i >= 1; i--)
            {
                int j = (int)(((ulong)i * 2654435761UL) % (ulong)(i + 1));
                int tmp = p[i]; p[i] = p[j]; p[j] = tmp;
            }
            return p;
        }

        static double Hash(int x, int y) { return Perm[(Perm[x & 255] + y) & 255] / 255.0; }
        static double Smooth(double t) { return t * t * (3 - 2 * t); }
        static double Value(double x, double y)
        {
            int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y);
            double fx = Smooth(x - xi), fy = Smooth(y - yi);
            double a = Hash(xi, yi), b = Hash(xi + 1, yi), c = Hash(xi, yi + 1), d = Hash(xi + 1, yi + 1);
            return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
        }
        static double Fbm(double x, double y)
        {
            double s = 0, amp = 0.5, f = 1;
            for (int o = 0; o < 4; o++) { s += amp * Value(x * f, y * f); amp *= 0.5; f *= 2.03; }
            return s;
        }

        void Draw()
        {
            if (!IsVisible || ActualWidth <= 0) return;
            double now = Clock.Now;
            if (bmp != null && now - last < 0.125) return;
            last = now;
            if (bmp == null)
            {
                cols = Math.Max(1, (int)Math.Ceiling(ActualWidth / 4)); rows = Math.Max(1, (int)Math.Ceiling(ActualHeight / 4));
                bmp = new WriteableBitmap(cols, rows, 96, 96, PixelFormats.Bgr32, null);
                InvalidateVisual();
            }
            double t = (DateTime.Now.TimeOfDay.TotalSeconds % 10000) * 0.012;
            double k = 150.0 / cols * 0.6 * 1.6;
            var px = new int[cols * rows];
            for (int y = 0; y < rows; y++)
                for (int x = 0; x < cols; x++)
                {
                    double n = Fbm(x * k / 32 + t, y * k / 27 + t * 0.4);
                    double h = n * 0.62 + ((double)y / rows) * 0.55 - 0.08 + (Bayer[(y & 3) * 4 + (x & 3)] - 7.5) / 16 * 0.05;
                    int tone = h < 0.30 ? 0 : h < 0.37 ? 1 : h < 0.40 ? 2 : h < 0.58 ? 3 : h < 0.63 ? 4 : h < 0.79 ? 5 : 6;
                    var c = Pal[tone];
                    if (h < 0.5 && Fbm(x * k / 3 + 40, y * k / 3 - t * 2) > 0.8) c = Star;
                    px[y * cols + x] = (c.R << 16) | (c.G << 8) | c.B;
                }
            bmp.WritePixels(new Int32Rect(0, 0, cols, rows), px, cols * 4, 0);
        }
    }
}
