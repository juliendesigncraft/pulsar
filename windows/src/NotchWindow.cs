// L'isola di Pulsar per Windows, rifatta sul Mac (Moduli/Isola, spec in SPEC-ISOLA.md).
// Compatta: nera, ai lati del "notch" (190 x 32 in alto al centro): pastiglia delle app a sinistra,
// razzo e glifo 3x3 a destra. Aperta: forma con spalle concave, fondo Volta, testa con le schede
// (Casa, Vassoio, Terminale, Dev) e a destra stato, giorno e ora. Comparsa: una riga sotto il notch.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Pulsar
{
    class NotchWindow : Window
    {
        // misure del Mac (punti = DIP): notch, ali della compatta, spalle
        const double NW = 190, NH = 32, Wing = 46, S = IslandShape.Shoulder;
        static readonly double CompactW = NW + 2 * Wing + 20;
        static readonly Size[] TabSize =
        {
            new Size(620, NH + 8 + 128 + 10),   // Casa (580 a freddo)
            new Size(600, NH + 8 + 128 + 10),   // Vassoio
            new Size(700, NH + 8 + 300 + 10),   // Terminale
            new Size(640, NH + 8 + 236 + 10)    // Dev
        };
        const double WinW = 860, WinH = 420;
        static readonly CultureInfo En = new CultureInfo("en-US");

        enum Mode { Compact, Peek, Open }
        Mode mode = Mode.Compact;
        int tab;
        bool pinned, dragInside, draggingOut;

        Grid island;
        IslandShape shape;
        Grid compactView, peekView, openView;
        Grid[] bodies = new Grid[4];
        Border[] tabButtons = new Border[4];
        DispatcherTimer openTimer, closeTimer, peekTimer, fastTimer, slowTimer, appTimer, hoverTimer;
        bool wasInZone;

        // compatta
        Border pastille; TextBlock pastilleGlyph; RocketAndGlyph rocketGlyph; EqBars eqBars; TextBlock musicNote;
        List<string> recentApps = new List<string>(); int appIndex;
        // comparsa
        TextBlock peekGlyph, peekTitle, peekDetail;
        // testa
        TextBlock headStatus, headDay, headTime;
        // Casa
        Grid musicCard, welcomeCard; TextBlock npTitle, npArtist, playGlyph; PixelEq pixelEq; Border pausedPill; TextBlock pausedTitle;
        NowPlaying np = new NowPlaying();
        // vassoio
        WrapPanel trayPanel; TextBlock trayEmpty, trayTitle; RocketView trayRocket;
        List<string> trayFiles = new List<string>();
        // terminale
        Shell shell;
        TextBox termInput; TextBlock termOut, termPath; ScrollViewer termScroll; Border termBranch;
        LinkedList<string> termLines = new LinkedList<string>();
        // dev
        TextBlock devRepo, devBranch, devLimitNote; StackPanel devServers; Border devConnect; Grid limit5, limit7;
        Limit limit = new Limit();

        public NotchWindow()
        {
            Title = "Pulsar";
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            Topmost = true;
            ShowInTaskbar = false;
            ResizeMode = ResizeMode.NoResize;
            FitWindow(false);
            Top = 0;
            FontFamily = T.UI;
            AllowDrop = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            Clock.Start();

            island = new Grid { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Width = CompactW, Height = NH, AllowDrop = true };
            // niente DropShadowEffect: in un PC senza scheda grafica (la VM) costava secondi; l'ombra la disegna la forma
            shape = new IslandShape { HeadHeight = NH };
            island.Children.Add(shape);

            compactView = BuildCompact();
            peekView = BuildPeek(); peekView.Opacity = 0; peekView.Visibility = Visibility.Collapsed;
            openView = BuildOpen(); openView.Opacity = 0; openView.Visibility = Visibility.Collapsed;
            island.Children.Add(compactView); island.Children.Add(peekView); island.Children.Add(openView);

            var root = new Grid();
            root.Children.Add(island);
            Content = root;

            shell = new Shell(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
            shell.Line += l => Dispatcher.BeginInvoke(new Action(() => AddTermLine(l)));
            shell.CwdChanged += () => Dispatcher.BeginInvoke(new Action(UpdateCwd));

            // mouse: si apre dopo 0,25 s sopra, si chiude 0,05 s dopo che esce (come sul Mac)
            openTimer = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(250) };
            openTimer.Tick += (s, e) => { openTimer.Stop(); if (CursorInZone()) OpenIsland(); };
            closeTimer = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(50) };
            closeTimer.Tick += (s, e) => { closeTimer.Stop(); TryClose(); };
            // come sul Mac (isola.swift, wakeZone): si guarda dov'è il cursore, non gli eventi del mouse,
            // così funziona anche mentre si trascina un file (Windows non manda eventi durante il trascinamento)
            hoverTimer = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(50) };
            hoverTimer.Tick += (s, e) => WatchCursor();
            hoverTimer.Start();
            island.MouseLeftButtonUp += (s, e) => { if (mode == Mode.Open) pinned = !pinned; else { OpenIsland(); pinned = true; } };
            island.MouseWheel += (s, e) => WheelVolume(e.Delta);
            Deactivated += (s, e) => { if (mode == Mode.Open && !CursorInZone()) { pinned = false; CloseIsland(); } };
            KeyDown += (s, e) => { if (e.Key == Key.Escape) { pinned = false; CloseIsland(); } };

            // file trascinati: l'isola si apre sul Vassoio e resta aperta finché il file è sopra
            PreviewDragEnter += (s, e) => HandleDrag(e);
            PreviewDragOver += (s, e) => HandleDrag(e);
            PreviewDragLeave += (s, e) =>
            {
                var p = e.GetPosition(island);
                if (p.X < 0 || p.Y < 0 || p.X > island.ActualWidth || p.Y > island.ActualHeight) { dragInside = false; closeTimer.Stop(); closeTimer.Start(); }
            };
            PreviewDrop += (s, e) =>
            {
                dragInside = false;
                var f = e.Data.GetData(DataFormats.FileDrop) as string[];
                App.Log("drop: " + (f == null ? "no files" : f.Length + " file(s)"));
                if (f != null && f.Length > 0) { AddToTray(f); ShowTab(1); SetDropLook(false); }
                else Peek(T.GTray, "Nothing to keep", "only files", 2500);
                e.Handled = true;
            };

            peekTimer = new DispatcherTimer();
            peekTimer.Tick += (s, e) => { peekTimer.Stop(); if (mode == Mode.Peek) GoCompact(); };
            fastTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            fastTimer.Tick += (s, e) => PollFast();
            fastTimer.Start();
            slowTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            slowTimer.Tick += (s, e) => PollSlow();
            slowTimer.Start();
            appTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            appTimer.Tick += (s, e) => TrackApps();
            appTimer.Start();

            LoadTray();
            ShowTab(0);
            PollFast(); PollSlow();
        }

        // ================== Win32: fuori da Alt+Tab, tasti globali, schermo intero ==================

        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
        struct RECT { public int L, T, R, B; }
        IntPtr hwnd;

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            hwnd = new WindowInteropHelper(this).Handle;
            SetWindowLong(hwnd, -20, GetWindowLong(hwnd, -20) | 0x80 /*WS_EX_TOOLWINDOW*/);
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);
            if (!RegisterHotKey(hwnd, 1, 0x2 | 0x1 | 0x4000, 0x54)) App.Log("Ctrl+Alt+T is taken by another app");   // Ctrl+Alt+T
            RegisterHotKey(hwnd, 2, 0x2 | 0x4000, 0xC0);                                                            // Ctrl+` (tastiere US)
        }

        IntPtr WndProc(IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled)
        {
            if (msg == 0x0312 /*WM_HOTKEY*/)
            {
                if (mode == Mode.Open && tab == 2) { pinned = false; CloseIsland(); } else OpenTab(2, true);
                handled = true;
            }
            return IntPtr.Zero;
        }

        public void Shutdown()
        {
            try { UnregisterHotKey(hwnd, 1); UnregisterHotKey(hwnd, 2); } catch { }
            shell.Kill();
            SaveTray();
        }

        bool ForegroundIsFullscreen()
        {
            var fg = GetForegroundWindow();
            if (fg == IntPtr.Zero || fg == hwnd) return false;
            var cls = new System.Text.StringBuilder(64);
            GetClassName(fg, cls, 64);
            var c = cls.ToString();
            if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd") return false;
            RECT r;
            if (!GetWindowRect(fg, out r)) return false;
            return r.L <= 0 && r.T <= 0 && r.R >= GetSystemMetrics(0) && r.B >= GetSystemMetrics(1);
        }

        // ================== stati e misure ==================

        public void OpenTab(int t, bool focus)
        {
            Visibility = Visibility.Visible;
            island.Visibility = Visibility.Visible;
            ShowTab(t);
            pinned = focus;
            OpenIsland();
            if (focus)
            {
                Activate();
                SetForegroundWindow(hwnd);
                if (t == 2) Dispatcher.BeginInvoke(new Action(() => { termInput.Focus(); Keyboard.Focus(termInput); }), DispatcherPriority.Input);
            }
        }

        Size OpenSize()
        {
            var s = TabSize[tab];
            if (tab == 0 && !np.Playing) s.Width = 580;
            return s;
        }

        void OpenIsland()
        {
            FitWindow(true);
            bool was = mode == Mode.Open;
            mode = Mode.Open;
            peekTimer.Stop();
            var s = OpenSize();
            SizeTo(s.Width, s.Height, 550);
            Animate(shape, IslandShape.BottomProperty, 28, 550, new CubicEase());
            Animate(shape, IslandShape.BodyOpacityProperty, 1, 260, null);
            Show(compactView, false, 120); Show(peekView, false, 100);
            if (!was)
            {
                openView.Visibility = Visibility.Visible;
                openView.RenderTransformOrigin = new Point(0.5, 0);
                openView.RenderTransform = new ScaleTransform(0.97, 0.97);
                var a = new DoubleAnimation(0.97, 1, TimeSpan.FromMilliseconds(450)) { EasingFunction = new CubicEase() };
                openView.RenderTransform.BeginAnimation(ScaleTransform.ScaleXProperty, a);
                openView.RenderTransform.BeginAnimation(ScaleTransform.ScaleYProperty, a);
                Fade(openView, 1, 90, 260);
            }
            UpdateHead();
            PollFast(); PollSlow();
        }

        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
        struct POINT { public int X, Y; }

        /// <summary>Il cursore è nella zona dell'isola? Chiusa: n.w + 60 attorno al centro, fino a 6 sotto il notch.
        /// Aperta (o in comparsa): tutta la forma allargata di 6 per lato.</summary>
        bool CursorInZone()
        {
            POINT p;
            if (!GetCursorPos(out p)) return false;
            var src = PresentationSource.FromVisual(this);
            if (src == null || src.CompositionTarget == null) return false;
            var pt = src.CompositionTarget.TransformFromDevice.Transform(new Point(p.X, p.Y));
            double cx = Left + Width / 2, x = pt.X - cx, y = pt.Y - Top;
            if (mode == Mode.Open) return Math.Abs(x) <= island.ActualWidth / 2 + 6 && y <= island.ActualHeight + 6 && y >= -2;
            return Math.Abs(x) <= (NW + 60) / 2 && y <= NH + 6 && y >= -2;
        }

        void WatchCursor()
        {
            if (island.Visibility != Visibility.Visible) return;
            bool inside = CursorInZone();
            if (inside == wasInZone) return;
            wasInZone = inside;
            if (inside) { closeTimer.Stop(); if (mode != Mode.Open) openTimer.Start(); }
            else { openTimer.Stop(); closeTimer.Start(); }
        }

        void TryClose()
        {
            if (mode != Mode.Open) return;
            if (pinned || dragInside || draggingOut || CursorInZone()) return;
            if (tab == 2 && termInput.IsKeyboardFocused) return;
            CloseIsland();
        }

        void CloseIsland()
        {
            if (mode != Mode.Open) return;
            SetDropLook(false);
            GoCompact();
        }

        void GoCompact()
        {
            mode = Mode.Compact;
            SizeTo(CompactW, NH, 550);
            Animate(shape, IslandShape.BottomProperty, 10, 400, new CubicEase());
            Animate(shape, IslandShape.BodyOpacityProperty, 0, 180, null);
            Show(openView, false, 120); Show(peekView, false, 120);
            Show(compactView, true, 200);
            // a chiusura finita la finestra torna piccola quanto il notch: meno da ridisegnare
            var shrink = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(650) };
            shrink.Tick += (s, e) => { shrink.Stop(); if (mode == Mode.Compact) FitWindow(false); };
            shrink.Start();
        }

        /// <summary>Comparsa: una riga sotto il notch per qualche secondo (volume, file nel Vassoio).</summary>
        void Peek(string glyph, string title, string detail, int ms)
        {
            if (mode == Mode.Open) return;
            peekGlyph.Text = glyph; peekTitle.Text = title; peekDetail.Text = detail;
            peekDetail.Visibility = string.IsNullOrEmpty(detail) ? Visibility.Collapsed : Visibility.Visible;
            peekView.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var row = (FrameworkElement)peekView.Children[0];
            row.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            double w = Math.Max(NW + 20, Math.Min(440, row.DesiredSize.Width + 2 * 16 + 2 * S));
            mode = Mode.Peek;
            FitWindow(true);
            SizeTo(w, NH + 28, mode == Mode.Peek ? 350 : 550);
            Animate(shape, IslandShape.BottomProperty, 14, 350, new CubicEase());
            Show(compactView, false, 100);
            Show(peekView, true, 200);
            peekTimer.Stop(); peekTimer.Interval = TimeSpan.FromMilliseconds(ms); peekTimer.Start();
        }

        void SizeTo(double w, double h, int ms)
        {
            Animate(island, WidthProperty, w, ms, new CubicEase());
            Animate(island, HeightProperty, h, ms, new CubicEase());
        }

        bool big;
        /// <summary>Chiusa la finestra è poco più grande del notch; aperta (o in comparsa) prende tutto lo spazio.</summary>
        void FitWindow(bool large)
        {
            if (big == large && Width > 0 && !double.IsNaN(Width)) return;
            big = large;
            // larghezza sempre uguale (cambiarla sposta l'isola di lato prima che arrivi la nuova posizione):
            // cambia solo l'altezza, 58 da chiusa e 420 da aperta
            Width = WinW;
            Left = Math.Round((SystemParameters.PrimaryScreenWidth - WinW) / 2);
            Height = large ? WinH : NH + 26;
        }

        static void Animate(DependencyObject el, DependencyProperty p, double to, int ms, IEasingFunction ease)
        {
            var a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(ms)) { EasingFunction = ease };
            var ui = el as IAnimatable;
            if (ui != null) ui.BeginAnimation(p, a, HandoffBehavior.SnapshotAndReplace);
        }

        static void Fade(UIElement el, double to, int delay, int ms)
        {
            var a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(ms)) { BeginTime = TimeSpan.FromMilliseconds(delay) };
            el.BeginAnimation(OpacityProperty, a);
        }

        static void Show(UIElement el, bool on, int ms)
        {
            if (on) { el.Visibility = Visibility.Visible; el.IsHitTestVisible = true; Fade(el, 1, 0, ms); }
            else
            {
                el.IsHitTestVisible = false;
                var a = new DoubleAnimation(0, TimeSpan.FromMilliseconds(ms));
                a.Completed += (s, e) => { if (el.Opacity < 0.01 && !el.IsHitTestVisible) el.Visibility = Visibility.Collapsed; };
                el.BeginAnimation(OpacityProperty, a);
            }
        }

        void ShowTab(int t)
        {
            tab = t;
            for (int i = 0; i < 4; i++)
            {
                bodies[i].Visibility = i == t ? Visibility.Visible : Visibility.Collapsed;
                var on = i == t;
                tabButtons[i].Background = on ? T.Pill : Brushes.Transparent;
                ((TextBlock)tabButtons[i].Child).Foreground = on ? T.T1 : T.T3;
            }
            if (mode == Mode.Open) { var s = OpenSize(); SizeTo(s.Width, s.Height, 550); }
            if (t == 3) PollSlow();
            UpdateHead();
        }

        // ================== compatta ==================

        Grid BuildCompact()
        {
            var g = new Grid { Margin = new Thickness(S, 0, S, 0), Height = NH, VerticalAlignment = VerticalAlignment.Top };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(NW - 2 * S) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            // sinistra: pastiglia dell'app (rettangolo chiaro col simbolo "scavato" in nero) o nota della musica
            var left = new Grid { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            pastille = new Border { Width = 15, Height = 12.5, CornerRadius = new CornerRadius(3.2), Background = T.B("#EDEFF6", 0.85) };
            pastilleGlyph = new TextBlock { FontFamily = T.Icons, FontSize = 7.5, Foreground = T.Ink, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Text = T.GApp };
            pastille.Child = pastilleGlyph;
            pastille.RenderTransformOrigin = new Point(0.5, 0.5);
            pastille.RenderTransform = new ScaleTransform(1, 1);
            left.Children.Add(pastille);
            musicNote = new TextBlock { FontFamily = T.Icons, FontSize = 11, Foreground = T.B("#EDEFF6", 0.8), Text = T.GMusic, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
            left.Children.Add(musicNote);
            g.Children.Add(left);

            // destra: razzo e glifo che si alternano, o le tre barre della musica
            var right = new Grid { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            rocketGlyph = new RocketAndGlyph();
            eqBars = new EqBars { Width = 13, Height = 14, Visibility = Visibility.Collapsed };
            right.Children.Add(rocketGlyph); right.Children.Add(eqBars);
            Grid.SetColumn(right, 2);
            g.Children.Add(right);
            return g;
        }

        /// <summary>Le app usate di recente, come la pastiglia del Mac: una alla volta, 2 s ciascuna, al massimo 5.</summary>
        void TrackApps()
        {
            try
            {
                var fg = GetForegroundWindow();
                if (fg != IntPtr.Zero && fg != hwnd)
                {
                    uint pid; GetWindowThreadProcessId(fg, out pid);
                    var name = Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant();
                    if (name != "pulsar" && name != "shellexperiencehost" && name != "searchhost" && name != "startmenuexperiencehost")
                    {
                        recentApps.Remove(name); recentApps.Insert(0, name);
                        if (recentApps.Count > 5) recentApps.RemoveAt(5);
                    }
                }
            }
            catch { }
            if (DateTime.Now.Second % 2 != 0 || recentApps.Count == 0) return;
            appIndex = (appIndex + 1) % recentApps.Count;
            var glyph = AppGlyph(recentApps[appIndex]);
            if (pastilleGlyph.Text == glyph) return;
            // dissolvenza + scala 0,85, 0,3 s
            var st = (ScaleTransform)pastille.RenderTransform;
            var down = new DoubleAnimation(1, 0.85, TimeSpan.FromMilliseconds(150)) { AutoReverse = true };
            st.BeginAnimation(ScaleTransform.ScaleXProperty, down); st.BeginAnimation(ScaleTransform.ScaleYProperty, down);
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(150)) { AutoReverse = true };
            pastilleGlyph.BeginAnimation(OpacityProperty, fade);
            var swap = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
            swap.Tick += (s, e) => { swap.Stop(); pastilleGlyph.Text = glyph; };
            swap.Start();
        }

        static string AppGlyph(string n)
        {
            if (n.Contains("claude")) return T.GThink;
            if (n == "chrome" || n == "msedge" || n == "firefox" || n == "brave" || n == "opera" || n == "arc") return T.GGlobe;
            if (n == "explorer") return T.GFolder;
            if (n == "windowsterminal" || n == "cmd" || n == "powershell" || n == "pwsh" || n == "conhost") return T.GTerm;
            if (n.Contains("spotify") || n.Contains("music") || n == "wmplayer") return T.GMusic;
            if (n.Contains("outlook") || n.Contains("mail") || n == "thunderbird") return T.GMail;
            if (n == "code" || n == "devenv" || n.Contains("rider") || n.Contains("idea")) return T.GCode;
            if (n.Contains("figma") || n.Contains("framer") || n.Contains("photoshop") || n.Contains("illustrator")) return T.GEdit;
            if (n.Contains("whatsapp") || n.Contains("telegram") || n.Contains("teams") || n.Contains("slack") || n.Contains("discord")) return T.GChat;
            if (n.Contains("photos") || n.Contains("paint")) return T.GPhoto;
            if (n == "notepad" || n == "winword" || n.Contains("onenote") || n.Contains("notion")) return T.GNote;
            if (n.Contains("vlc") || n.Contains("video") || n.Contains("movies")) return T.GVideo;
            if (n == "systemsettings") return T.GSettings;
            if (n.Contains("store")) return T.GBag;
            return T.GApp;
        }

        // ================== comparsa ==================

        Grid BuildPeek()
        {
            var g = new Grid { Margin = new Thickness(S, NH, S, 0), Height = 26, VerticalAlignment = VerticalAlignment.Top };
            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            peekGlyph = new TextBlock { FontFamily = T.Icons, FontSize = 12, Foreground = T.A2B, Width = 14, VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Center };
            peekTitle = Txt("", 11.5, T.T1, FontWeights.Medium); peekTitle.Margin = new Thickness(8, 0, 0, 0); peekTitle.VerticalAlignment = VerticalAlignment.Center;
            peekDetail = Txt("", 11, T.B("#EDEFF6", 0.55), FontWeights.Normal); peekDetail.Margin = new Thickness(8, 0, 0, 0); peekDetail.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(peekGlyph); row.Children.Add(peekTitle); row.Children.Add(peekDetail);
            g.Children.Add(row);
            return g;
        }

        void WheelVolume(int delta)
        {
            var v = Audio.Get();
            if (v < 0) { Peek(T.GMute, "Volume", "no output", 1300); return; }
            v = Math.Max(0, Math.Min(1, v + (delta > 0 ? 0.02f : -0.02f)));
            Audio.Set(v);
            Peek(Audio.Muted() || v <= 0 ? T.GMute : T.GVol, "Volume", Math.Round(v * 100) + "%", 1300);
        }

        // ================== aperta: testa e schede ==================

        Grid BuildOpen()
        {
            var g = new Grid { Margin = new Thickness(S, 0, S, 0) };
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(NH) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(8) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            // testa: le schede a sinistra del notch e lo stato a destra, ancorate al centro
            // (sul Mac stanno ai bordi; qui restano ferme mentre l'isola cambia misura)
            var head = new Grid();
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(NW + 16) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var tabs = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
            string[] glyphs = { T.GHome, T.GTray, T.GTerm, T.GCode };
            string[] tips = { "Home", "Tray", "Terminal  (Ctrl+Alt+T)", "Dev" };
            for (int i = 0; i < 4; i++)
            {
                int k = i;
                var b = Circle(glyphs[i], 10.5, 24, () => ShowTab(k), tips[i]);
                b.Margin = new Thickness(i == 0 ? 0 : 2, 0, 0, 0);
                tabButtons[i] = b;
                tabs.Children.Add(b);
            }
            head.Children.Add(tabs);
            var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
            headStatus = Txt("", 11.5, T.T3, FontWeights.Medium);
            headDay = Txt("", 11.5, T.T3, FontWeights.Medium); headDay.Margin = new Thickness(6, 0, 0, 0);
            headTime = Txt("", 11.5, T.T1, FontWeights.Medium); headTime.Margin = new Thickness(6, 0, 0, 0);
            foreach (var t in new[] { headStatus, headDay, headTime }) Typography.SetNumeralAlignment(t, FontNumeralAlignment.Tabular);
            right.Children.Add(headStatus); right.Children.Add(headDay); right.Children.Add(headTime);
            Grid.SetColumn(right, 2);
            head.Children.Add(right);
            g.Children.Add(head);

            bodies[0] = BuildCasa(); bodies[1] = BuildTray(); bodies[2] = BuildTerminal(); bodies[3] = BuildDev();
            foreach (var b in bodies) { b.Margin = new Thickness(20, 0, 20, 10); Grid.SetRow(b, 2); g.Children.Add(b); }
            return g;
        }

        void UpdateHead()
        {
            if (headTime == null) return;
            headDay.Text = DateTime.Now.ToString("ddd d", En);
            headTime.Text = DateTime.Now.ToString("HH:mm");
            if (tab == 0) headStatus.Text = np.Playing ? "Playing" : Greeting();
            else if (tab == 1) headStatus.Text = trayFiles.Count == 1 ? "1 file" : trayFiles.Count + " files";
            else if (tab == 2) headStatus.Text = Git.Branch(shell.Cwd) ?? "Terminal";
            else headStatus.Text = limit.Known ? "Claude " + Math.Round(limit.FiveHour) + "%" : "Dev";
        }

        static string Greeting()
        {
            int h = DateTime.Now.Hour;
            return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
        }

        // ---- Casa: la musica che suona, o il cielo a pixel col razzo in volo ----

        Grid BuildCasa()
        {
            var g = new Grid();
            musicCard = BuildMusicCard();
            welcomeCard = BuildWelcome();
            g.Children.Add(musicCard); g.Children.Add(welcomeCard);
            return g;
        }

        Grid BuildMusicCard()
        {
            var card = VCard(T.A2);
            var inner = (Grid)((Border)card.Children[1]).Child;
            inner.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            inner.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            inner.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var art = new Border { Width = 56, Height = 56, CornerRadius = new CornerRadius(14), VerticalAlignment = VerticalAlignment.Center };
            var grad = new LinearGradientBrush(T.A2, T.A4, new Point(0, 0), new Point(1, 1)); grad.Freeze();
            art.Background = grad;
            art.Child = new TextBlock { FontFamily = T.Icons, FontSize = 18, Text = T.GMusic, Foreground = T.B("#13203A", 0.7), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            inner.Children.Add(art);

            var col = new StackPanel { Margin = new Thickness(14, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
            var top = new StackPanel { Orientation = Orientation.Horizontal };
            pixelEq = new PixelEq { Width = 5 * 2.4 + 4 * 1.5, Height = 5 * 2.4 + 4 * 1.5, VerticalAlignment = VerticalAlignment.Center };
            var now = Txt("Now playing", 12, T.T2, FontWeights.Normal); now.Margin = new Thickness(7, 0, 0, 0); now.VerticalAlignment = VerticalAlignment.Center;
            top.Children.Add(pixelEq); top.Children.Add(now);
            npTitle = Txt("", 16, T.T1, FontWeights.Medium); npTitle.Margin = new Thickness(0, 4, 0, 0); npTitle.TextTrimming = TextTrimming.CharacterEllipsis;
            npArtist = Txt("", 12.5, T.T2, FontWeights.Normal); npArtist.TextTrimming = TextTrimming.CharacterEllipsis;
            col.Children.Add(top); col.Children.Add(npTitle); col.Children.Add(npArtist);
            Grid.SetColumn(col, 1); inner.Children.Add(col);

            var ctr = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var prev = Circle(T.GPrev, 11, 32, () => { Media.Previous(); SoonPoll(); }, "Previous");
            var play = Circle(T.GPause, 13, 38, () => { Media.PlayPause(); np.Playing = !np.Playing; UpdateMusic(); SoonPoll(); }, "Play / pause");
            play.Background = T.Pill; playGlyph = (TextBlock)play.Child; playGlyph.Foreground = T.T1;
            var next = Circle(T.GNext, 11, 32, () => { Media.Next(); SoonPoll(); }, "Next");
            prev.Margin = new Thickness(0, 0, 4, 0); next.Margin = new Thickness(4, 0, 0, 0);
            foreach (var b in new[] { prev, play, next }) { ((TextBlock)b.Child).Foreground = T.T1; ctr.Children.Add(b); }
            Grid.SetColumn(ctr, 2); inner.Children.Add(ctr);
            return card;
        }

        Grid BuildWelcome()
        {
            var g = new Grid { ClipToBounds = true };
            var clip = new Border { CornerRadius = new CornerRadius(20), Background = T.Card };
            g.Children.Add(clip);
            var sky = new SkyView();
            var holder = new Grid();
            holder.Children.Add(sky);
            var canvas = new Canvas();
            var flyer = new RocketView { PixelSize = 2.6, Width = 36, Height = 60 };
            canvas.Children.Add(flyer);
            holder.Children.Add(canvas);
            // il cielo resta dentro gli angoli da 20
            holder.Loaded += (s, e) => UpdateClip(holder);
            holder.SizeChanged += (s, e) => UpdateClip(holder);
            Clock.Tick += () =>
            {
                if (!holder.IsVisible) return;
                double t = Clock.Now, w = holder.ActualWidth, h = holder.ActualHeight;
                double x = w * (0.5 + 0.035 * Math.Sin(0.21 * t) + 0.01 * Math.Sin(0.53 * t + 1.3));
                double y = h * (0.46 + 0.05 * Math.Sin(0.33 * t + 0.7) + 0.01 * Math.Sin(0.9 * t));
                double vy = 0.0165 * Math.Cos(0.33 * t + 0.7) + 0.009 * Math.Cos(0.9 * t);
                flyer.Phase = vy < 0 ? RocketPhase.Thrust : RocketPhase.Idle;
                Canvas.SetLeft(flyer, Math.Round(x - 18)); Canvas.SetTop(flyer, Math.Round(y - 30));
            };
            g.Children.Add(holder);

            // canzone in pausa: un tasto piccolo in basso a destra
            pausedPill = new Border { Height = 26, CornerRadius = new CornerRadius(13), Background = T.B("#1D1F29", 0.7), Padding = new Thickness(5, 0, 10, 0), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 10, 10), Cursor = Cursors.Hand, Visibility = Visibility.Collapsed };
            var pr = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var mini = new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(5), Background = new LinearGradientBrush(T.A2, T.A4, 45) };
            pausedTitle = Txt("", 11, T.T1, FontWeights.Normal); pausedTitle.MaxWidth = 130; pausedTitle.TextTrimming = TextTrimming.CharacterEllipsis; pausedTitle.Margin = new Thickness(7, 0, 7, 0); pausedTitle.VerticalAlignment = VerticalAlignment.Center;
            var pg = new TextBlock { FontFamily = T.Icons, FontSize = 9, Text = T.GPlay, Foreground = T.T1, VerticalAlignment = VerticalAlignment.Center };
            pr.Children.Add(mini); pr.Children.Add(pausedTitle); pr.Children.Add(pg);
            pausedPill.Child = pr;
            pausedPill.MouseLeftButtonUp += (s, e) => { Media.PlayPause(); SoonPoll(); e.Handled = true; };
            g.Children.Add(pausedPill);
            return g;
        }

        static void UpdateClip(FrameworkElement el)
        {
            el.Clip = new RectangleGeometry(new Rect(0, 0, el.ActualWidth, el.ActualHeight), 20, 20);
        }

        void UpdateMusic()
        {
            bool playing = np.Any && np.Playing;
            musicCard.Visibility = playing ? Visibility.Visible : Visibility.Collapsed;
            welcomeCard.Visibility = playing ? Visibility.Collapsed : Visibility.Visible;
            npTitle.Text = np.Title;
            npArtist.Text = np.Artist.Length > 0 ? np.Artist : np.App;
            playGlyph.Text = np.Playing ? T.GPause : T.GPlay;
            pixelEq.Playing = playing;
            pausedPill.Visibility = np.Any && !np.Playing && np.Title != "Paused" ? Visibility.Visible : Visibility.Collapsed;
            pausedTitle.Text = np.Title;
            // compatta: con la musica nota a sinistra e barre a destra
            musicNote.Visibility = playing ? Visibility.Visible : Visibility.Collapsed;
            pastille.Visibility = playing ? Visibility.Collapsed : Visibility.Visible;
            eqBars.Playing = playing;
            eqBars.Visibility = playing ? Visibility.Visible : Visibility.Collapsed;
            rocketGlyph.Visibility = playing ? Visibility.Collapsed : Visibility.Visible;
            if (mode == Mode.Open && tab == 0) { var s = OpenSize(); SizeTo(s.Width, s.Height, 550); }
            UpdateHead();
        }

        void SoonPoll()
        {
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(450) };
            t.Tick += (s, e) => { t.Stop(); PollFast(); };
            t.Start();
        }

        // ---- Vassoio: file appoggiati al notch ----

        Grid BuildTray()
        {
            var card = VCard(T.A1);
            var inner = (Grid)((Border)card.Children[1]).Child;
            inner.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            inner.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            trayRocket = new RocketView { PixelSize = 3.6, Width = 64, Height = 88, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(-6, -10, 12, -10) };
            inner.Children.Add(trayRocket);
            var col = new DockPanel { LastChildFill = true };
            trayTitle = Txt("Tray", 16, T.T1, FontWeights.Medium);
            DockPanel.SetDock(trayTitle, Dock.Top);
            col.Children.Add(trayTitle);
            var holder = new Grid { Margin = new Thickness(0, 8, 0, 0) };
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            trayPanel = new WrapPanel();
            sv.Content = trayPanel;
            holder.Children.Add(sv);
            trayEmpty = Txt("Drop files on the notch. They wait here, then drag them out.", 12.5, T.T2, FontWeights.Normal);
            trayEmpty.TextWrapping = TextWrapping.Wrap;
            holder.Children.Add(trayEmpty);
            col.Children.Add(holder);
            Grid.SetColumn(col, 1);
            inner.Children.Add(col);
            return card;
        }

        void HandleDrag(DragEventArgs e)
        {
            bool files = e.Data.GetDataPresent(DataFormats.FileDrop);
            e.Effects = files ? DragDropEffects.Copy : DragDropEffects.None;
            e.Handled = true;
            if (!files || draggingOut) return;
            closeTimer.Stop();
            if (!dragInside) { dragInside = true; ShowTab(1); SetDropLook(true); if (mode != Mode.Open) OpenIsland(); }
        }

        void SetDropLook(bool on)
        {
            if (trayRocket == null) return;
            trayRocket.Phase = on ? RocketPhase.CatchFile : RocketPhase.Idle;
            trayTitle.Text = on ? "Drop here, it stays in the tray" : "Tray";
        }

        void AddToTray(string[] files)
        {
            int before = trayFiles.Count;
            foreach (var f in files) if (!trayFiles.Contains(f)) trayFiles.Add(f);
            SaveTray();
            RenderTray();
            trayRocket.Phase = RocketPhase.Loaded;
            var n = trayFiles.Count - before;
            if (mode != Mode.Open) Peek(T.GTray, n == 1 ? "1 file in the tray" : n + " files in the tray", "", 3000);
            UpdateHead();
        }

        void RenderTray()
        {
            trayPanel.Children.Clear();
            trayFiles = trayFiles.Where(f => File.Exists(f) || Directory.Exists(f)).ToList();
            trayEmpty.Visibility = trayFiles.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            foreach (var f in trayFiles)
            {
                var path = f;
                var chip = new Border { Height = 26, Background = T.Card2, CornerRadius = new CornerRadius(13), Padding = new Thickness(11, 0, 5, 0), Margin = new Thickness(0, 0, 7, 7), Cursor = Cursors.Hand, ToolTip = path };
                var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
                var ext = Directory.Exists(path) ? "folder" : System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
                var name = Txt(System.IO.Path.GetFileName(path.TrimEnd('\\')), 12, T.T1, FontWeights.Normal);
                name.MaxWidth = 170; name.TextTrimming = TextTrimming.CharacterEllipsis; name.VerticalAlignment = VerticalAlignment.Center;
                var tag = Txt(ext.Length > 0 ? ext : "file", 11.5, T.A2B, FontWeights.Normal);
                tag.VerticalAlignment = VerticalAlignment.Center; tag.Margin = new Thickness(7, 0, 0, 0);
                var x = Circle(T.GClose, 8, 18, () => { trayFiles.Remove(path); SaveTray(); RenderTray(); UpdateHead(); }, "Remove from tray");
                x.Margin = new Thickness(6, 0, 0, 0);
                row.Children.Add(name); row.Children.Add(tag); row.Children.Add(x);
                chip.Child = row;
                chip.MouseEnter += (s, e) => chip.Background = T.Pill;
                chip.MouseLeave += (s, e) => chip.Background = T.Card2;
                Point start = new Point();
                chip.MouseLeftButtonDown += (s, e) => { start = e.GetPosition(this); if (e.ClickCount == 2) OpenPath(path); e.Handled = true; };
                chip.MouseMove += (s, e) =>
                {
                    if (e.LeftButton != MouseButtonState.Pressed) return;
                    var p = e.GetPosition(this);
                    if (Math.Abs(p.X - start.X) + Math.Abs(p.Y - start.Y) < 6) return;
                    draggingOut = true;
                    try { DragDrop.DoDragDrop(chip, new DataObject(DataFormats.FileDrop, new[] { path }), DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link); }
                    finally { draggingOut = false; closeTimer.Start(); }
                };
                trayPanel.Children.Add(chip);
            }
        }

        static void OpenPath(string path)
        {
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
        }

        string TrayFile { get { return System.IO.Path.Combine(Limits.Folder, "tray.txt"); } }
        void LoadTray()
        {
            try { if (File.Exists(TrayFile)) trayFiles = File.ReadAllLines(TrayFile).Where(l => l.Trim().Length > 0).ToList(); } catch { }
            RenderTray();
        }
        void SaveTray()
        {
            try { Directory.CreateDirectory(Limits.Folder); File.WriteAllLines(TrayFile, trayFiles); } catch { }
        }

        // ---- Terminale che scende dal notch ----

        Grid BuildTerminal()
        {
            var g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var top = new Grid { Margin = new Thickness(2, 0, 0, 8) };
            var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var dot = new Ellipse { Width = 6, Height = 6, Fill = T.A2B, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 7, 0) };
            termPath = Txt("", 12.5, T.T2, FontWeights.Normal);
            termPath.VerticalAlignment = VerticalAlignment.Center; termPath.MaxWidth = 380; termPath.TextTrimming = TextTrimming.CharacterEllipsis;
            termBranch = PillLabel("");
            termBranch.Margin = new Thickness(10, 0, 0, 0);
            left.Children.Add(dot); left.Children.Add(termPath); left.Children.Add(termBranch);
            top.Children.Add(left);
            var acts = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            var stop = PillButton("Stop", () => { shell.Restart(); AddTermLine("(stopped)"); }, false);
            var full = PillButton("Windows Terminal", () => shell.OpenFull(), false);
            stop.Margin = new Thickness(0, 0, 7, 0);
            acts.Children.Add(stop); acts.Children.Add(full);
            top.Children.Add(acts);
            g.Children.Add(top);

            var box = new Border { Background = T.Card, CornerRadius = new CornerRadius(20), Padding = new Thickness(18, 12, 18, 12) };
            termScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            termOut = new TextBlock { FontFamily = T.Mono, FontSize = 12, Foreground = T.T2, TextWrapping = TextWrapping.Wrap, LineHeight = 17 };
            termScroll.Content = termOut;
            box.Child = termScroll;
            Grid.SetRow(box, 1);
            g.Children.Add(box);

            var inRow = new Border { Background = T.Card2, CornerRadius = new CornerRadius(15), Height = 30, Margin = new Thickness(0, 8, 0, 0), Padding = new Thickness(14, 0, 14, 0) };
            var ig = new Grid();
            ig.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            ig.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var caret = Txt("›", 15, T.A2B, FontWeights.Normal);
            caret.VerticalAlignment = VerticalAlignment.Center; caret.Margin = new Thickness(0, -2, 10, 0);
            ig.Children.Add(caret);
            termInput = new TextBox
            {
                Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = T.T1,
                CaretBrush = T.A2B, FontFamily = T.Mono, FontSize = 12.5, VerticalAlignment = VerticalAlignment.Center,
                SelectionBrush = T.A4B
            };
            var history = new List<string>(); int hi = 0;
            termInput.PreviewKeyDown += (s, e) =>
            {
                if (e.Key == Key.Enter)
                {
                    var cmd = termInput.Text;
                    termInput.Text = "";
                    if (cmd.Trim() == "cls" || cmd.Trim() == "clear") { termLines.Clear(); termOut.Text = ""; e.Handled = true; return; }
                    AddTermLine("› " + cmd);
                    if (cmd.Trim().Length > 0) { history.Add(cmd); hi = history.Count; }
                    shell.Run(cmd);
                    e.Handled = true;
                }
                else if (e.Key == Key.Up && history.Count > 0) { hi = Math.Max(0, hi - 1); termInput.Text = history[hi]; termInput.CaretIndex = termInput.Text.Length; e.Handled = true; }
                else if (e.Key == Key.Down && history.Count > 0) { hi = Math.Min(history.Count, hi + 1); termInput.Text = hi < history.Count ? history[hi] : ""; termInput.CaretIndex = termInput.Text.Length; e.Handled = true; }
                else if (e.Key == Key.Escape) { pinned = false; CloseIsland(); e.Handled = true; }
            };
            Grid.SetColumn(termInput, 1);
            ig.Children.Add(termInput);
            inRow.Child = ig;
            Grid.SetRow(inRow, 2);
            g.Children.Add(inRow);

            g.Loaded += (s, e) => UpdateCwd();
            return g;
        }

        void AddTermLine(string l)
        {
            termLines.AddLast(l);
            while (termLines.Count > 400) termLines.RemoveFirst();
            termOut.Text = string.Join("\n", termLines);
            termScroll.ScrollToEnd();
        }

        void UpdateCwd()
        {
            termPath.Text = shell.Cwd;
            var b = Git.Branch(shell.Cwd);
            ((TextBlock)termBranch.Child).Text = b ?? "";
            termBranch.Visibility = b == null ? Visibility.Collapsed : Visibility.Visible;
            if (devRepo != null) UpdateGit();
            UpdateHead();
        }

        // ---- Dev: ramo Git, server per porta, limite di Claude Code ----

        Grid BuildDev()
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.15, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var left = new Border { Background = T.Card, CornerRadius = new CornerRadius(20), Padding = new Thickness(20, 18, 16, 14) };
            var lp = new DockPanel { LastChildFill = true };
            var git = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
            DockPanel.SetDock(git, Dock.Top);
            git.Children.Add(Txt("Git branch", 12, T.T3, FontWeights.Normal));
            devBranch = Txt("No repository", 16, T.T1, FontWeights.Medium);
            devBranch.Margin = new Thickness(0, 3, 0, 0); devBranch.TextTrimming = TextTrimming.CharacterEllipsis;
            devRepo = Txt("Open a project folder in the terminal (cd)", 12.5, T.T2, FontWeights.Normal);
            devRepo.TextTrimming = TextTrimming.CharacterEllipsis;
            git.Children.Add(devBranch); git.Children.Add(devRepo);
            lp.Children.Add(git);
            var srvLabel = Txt("Dev servers", 12, T.T3, FontWeights.Normal);
            srvLabel.Margin = new Thickness(0, 0, 0, 4);
            DockPanel.SetDock(srvLabel, Dock.Top);
            lp.Children.Add(srvLabel);
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
            devServers = new StackPanel();
            sv.Content = devServers;
            lp.Children.Add(sv);
            left.Child = lp;
            g.Children.Add(left);

            var right = new Border { Background = T.Card, CornerRadius = new CornerRadius(20), Padding = new Thickness(20, 18, 20, 14) };
            var rp = new StackPanel();
            rp.Children.Add(Txt("Claude Code limit", 12, T.T3, FontWeights.Normal));
            limit5 = LimitRow("5-hour window");
            limit7 = LimitRow("This week");
            limit5.Margin = new Thickness(0, 10, 0, 0); limit7.Margin = new Thickness(0, 14, 0, 0);
            rp.Children.Add(limit5); rp.Children.Add(limit7);
            devLimitNote = Txt("", 11, T.T3, FontWeights.Normal);
            devLimitNote.TextWrapping = TextWrapping.Wrap; devLimitNote.Margin = new Thickness(0, 12, 0, 0);
            rp.Children.Add(devLimitNote);
            devConnect = PillButton("Connect Claude Code", () =>
            {
                var ok = MessageBox.Show("Pulsar will add a status line to Claude Code (~/.claude/settings.json), after making a copy of the file.\n\nContinue?", "Pulsar", MessageBoxButton.OKCancel);
                if (ok != MessageBoxResult.OK) return;
                var err = Limits.Connect(App.Exe);
                if (err != null) MessageBox.Show(err, "Pulsar");
                PollSlow();
            }, true);
            devConnect.HorizontalAlignment = HorizontalAlignment.Left; devConnect.Margin = new Thickness(0, 10, 0, 0);
            rp.Children.Add(devConnect);
            right.Child = rp;
            Grid.SetColumn(right, 2);
            g.Children.Add(right);
            return g;
        }

        Grid LimitRow(string label)
        {
            var g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var top = new Grid();
            top.Children.Add(Txt(label, 12.5, T.T2, FontWeights.Normal));
            var pct = Txt("unknown", 16, T.T1, FontWeights.Medium);
            pct.HorizontalAlignment = HorizontalAlignment.Right; pct.Margin = new Thickness(0, -4, 0, 0);
            Typography.SetNumeralAlignment(pct, FontNumeralAlignment.Tabular);
            top.Children.Add(pct);
            g.Children.Add(top);
            var trk = new Grid { Height = 4, Margin = new Thickness(0, 7, 0, 5) };
            trk.Children.Add(new Border { CornerRadius = new CornerRadius(2), Background = T.Card2 });
            var fill = new Border { CornerRadius = new CornerRadius(2), Background = T.A2B, HorizontalAlignment = HorizontalAlignment.Left, Width = 0 };
            trk.Children.Add(fill);
            Grid.SetRow(trk, 1);
            g.Children.Add(trk);
            var reset = Txt("", 11, T.T3, FontWeights.Normal);
            Grid.SetRow(reset, 2);
            g.Children.Add(reset);
            g.Tag = new object[] { pct, fill, trk, reset };
            return g;
        }

        void SetLimitRow(Grid row, double pct, long reset)
        {
            var parts = (object[])row.Tag;
            var t = (TextBlock)parts[0]; var fill = (Border)parts[1]; var trk = (Grid)parts[2]; var r = (TextBlock)parts[3];
            if (pct < 0) { t.Text = "unknown"; fill.Width = 0; r.Text = ""; return; }
            t.Text = Math.Round(pct) + "% used";
            fill.Width = Math.Max(0, trk.ActualWidth * Math.Min(1, pct / 100));
            fill.Background = pct >= 85 ? T.Red : T.A2B;
            r.Text = Limits.ResetIn(reset);
        }

        void UpdateGit()
        {
            var b = Git.Branch(shell.Cwd);
            devBranch.Text = b ?? "No repository";
            var repo = Git.RepoName(shell.Cwd);
            devRepo.Text = repo != null ? repo + ".  " + shell.Cwd : "Open a project folder in the terminal (cd)";
        }

        void RenderServers(List<Listener> list)
        {
            devServers.Children.Clear();
            if (list.Count == 0)
            {
                var t = Txt("Nothing listening. Start a dev server and it shows up here.", 12.5, T.T2, FontWeights.Normal);
                t.TextWrapping = TextWrapping.Wrap;
                devServers.Children.Add(t);
                return;
            }
            foreach (var l in list)
            {
                var item = l;
                var row = new Grid { Height = 30 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(62) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var port = Txt(":" + item.Port, 13, T.T1, FontWeights.Normal);
                port.FontFamily = T.Mono; port.VerticalAlignment = VerticalAlignment.Center;
                row.Children.Add(port);
                var name = Txt(item.Name, 12.5, T.T2, FontWeights.Normal);
                name.VerticalAlignment = VerticalAlignment.Center; name.TextTrimming = TextTrimming.CharacterEllipsis;
                Grid.SetColumn(name, 1); row.Children.Add(name);
                var acts = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
                var open = Circle(T.GGlobe, 11, 26, () => Ports.Open(item.Port), "Open localhost:" + item.Port);
                var kill = Circle(T.GStop, 10, 26, () =>
                {
                    if (MessageBox.Show("Stop " + item.Name + " on port " + item.Port + "?", "Pulsar", MessageBoxButton.OKCancel) == MessageBoxResult.OK)
                    { Ports.Stop(item.Pid); PollSlow(); }
                }, "Stop this server");
                kill.Margin = new Thickness(2, 0, 0, 0);
                acts.Children.Add(open); acts.Children.Add(kill);
                Grid.SetColumn(acts, 2); row.Children.Add(acts);
                devServers.Children.Add(row);
            }
        }

        // ================== aggiornamenti ==================

        bool polling;
        void PollFast()
        {
            if (ForegroundIsFullscreen()) { if (mode != Mode.Open) island.Visibility = Visibility.Hidden; }
            else island.Visibility = Visibility.Visible;
            UpdateHead();
            if (polling) return;
            polling = true;
            Task.Factory.StartNew(() => Media.Read()).ContinueWith(t =>
            {
                NowPlaying n = t.IsFaulted ? null : t.Result;
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    polling = false;
                    if (n == null) return;
                    np = n;
                    UpdateMusic();
                }));
            });
        }

        void PollSlow()
        {
            limit = Limits.Load();
            bool connected = Limits.Connected();
            SetLimitRow(limit5, limit.FiveHour, limit.FiveReset);
            SetLimitRow(limit7, limit.SevenDay, limit.SevenReset);
            devConnect.Visibility = connected ? Visibility.Collapsed : Visibility.Visible;
            if (limit.Known) devLimitNote.Text = "Updated " + Ago(limit.Read) + (limit.Model.Length > 0 ? ". " + limit.Model : "");
            else if (!connected) devLimitNote.Text = "Connect once and Claude Code tells Pulsar how much of your plan limit is used.";
            else devLimitNote.Text = "Connected. The limit shows up after your next message in Claude Code (Pro and Max plans).";
            UpdateGit();
            UpdateHead();
            if (mode == Mode.Open && tab == 3)
            {
                Task.Factory.StartNew(() => Ports.Read()).ContinueWith(t =>
                {
                    if (t.IsFaulted) return;
                    var list = t.Result;
                    Dispatcher.BeginInvoke(new Action(() => RenderServers(list)));
                });
            }
        }

        static string Ago(DateTime t)
        {
            var d = DateTime.Now - t;
            if (d.TotalMinutes < 1) return "just now";
            if (d.TotalHours < 1) return (int)d.TotalMinutes + " min ago";
            if (d.TotalDays < 1) return (int)d.TotalHours + " h ago";
            return t.ToString("d MMM", En);
        }

        // ================== pezzi (VCard, VPill, icone tonde) ==================

        static TextBlock Txt(string s, double size, Brush fg, FontWeight w)
        {
            return new TextBlock { Text = s, FontSize = size, Foreground = fg, FontWeight = w, FontFamily = T.UI };
        }

        /// <summary>Tessera del Mac: raggio 20, fondo card, margini 20/18, luce dal basso nel colore dello stato.</summary>
        static Grid VCard(Color glow)
        {
            var g = new Grid();
            var bg = new Border { CornerRadius = new CornerRadius(20), Background = T.Card, ClipToBounds = true };
            var light = new RadialGradientBrush { Center = new Point(0.5, 1.25), GradientOrigin = new Point(0.5, 1.25), RadiusX = 0.75, RadiusY = 1.1 };
            var c0 = glow; c0.A = (byte)(0.30 * 255);
            var c1 = glow; c1.A = 0;
            light.GradientStops.Add(new GradientStop(c0, 0)); light.GradientStops.Add(new GradientStop(c1, 1));
            light.Freeze();
            var glowLayer = new Border { CornerRadius = new CornerRadius(20), Background = light, Opacity = 0.85, IsHitTestVisible = false };
            var content = new Border { Padding = new Thickness(20, 18, 20, 18), Child = new Grid() };
            // Children[0] fondo, Children[1] contenuto (chi costruisce lo prende da qui), Children[2] luce;
            // l'ordine di disegno lo decide ZIndex: fondo, luce, contenuto
            g.Children.Add(bg); g.Children.Add(content); g.Children.Add(glowLayer);
            Panel.SetZIndex(bg, 0); Panel.SetZIndex(glowLayer, 1); Panel.SetZIndex(content, 2);
            return g;
        }

        /// <summary>Icona in un cerchio (testa del Mac: 24, simbolo 10,5; acceso su pill).</summary>
        static Border Circle(string glyph, double size, double d, Action click, string tip)
        {
            var t = new TextBlock { Text = glyph, FontFamily = T.Icons, FontSize = size, Foreground = T.T3, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            var b = new Border { Child = t, Width = d, Height = d, Background = Brushes.Transparent, CornerRadius = new CornerRadius(d / 2), Cursor = Cursors.Hand, ToolTip = tip };
            Brush before = null;
            b.MouseEnter += (s, e) => { before = b.Background; if (before == Brushes.Transparent) b.Background = T.B("#EDEFF6", 0.07); };
            b.MouseLeave += (s, e) => { if (before == Brushes.Transparent) b.Background = Brushes.Transparent; };
            b.MouseLeftButtonUp += (s, e) => { click(); e.Handled = true; };
            return b;
        }

        /// <summary>Pillola del Mac (VPill): capsula alta 30, testo 12,5; principale = azzurro chiaro.</summary>
        static Border PillButton(string label, Action click, bool primary)
        {
            var t = Txt(label, 12.5, primary ? T.PrimT : T.PillT, primary ? FontWeights.Medium : FontWeights.Normal);
            t.VerticalAlignment = VerticalAlignment.Center;
            var bg = primary ? T.Prim : T.Pill;
            var b = new Border { Child = t, Height = 30, Background = bg, CornerRadius = new CornerRadius(15), Padding = new Thickness(14, 0, 14, 0), Cursor = Cursors.Hand };
            b.RenderTransform = new TranslateTransform();
            b.MouseEnter += (s, e) => b.RenderTransform.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-1, TimeSpan.FromMilliseconds(200)));
            b.MouseLeave += (s, e) => b.RenderTransform.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(200)));
            b.MouseLeftButtonUp += (s, e) => { click(); e.Handled = true; };
            return b;
        }

        static Border PillLabel(string s)
        {
            var t = Txt(s, 11.5, T.PillT, FontWeights.Normal);
            return new Border { Background = T.Pill, CornerRadius = new CornerRadius(11), Height = 22, Padding = new Thickness(10, 0, 10, 0), Child = t, VerticalAlignment = VerticalAlignment.Center };
        }
    }
}
