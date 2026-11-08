// Il menu a destra di Pulsar per Windows, rifatto da Moduli/Agent/agente.swift del Mac (NightRail e NightPanel).
// Una colonna di icone attaccata al bordo destro: esce quando il mouse tocca il bordo a quell'altezza o quando
// Claude Code chiede un permesso. Un clic apre il pannello accanto: Work (i passi), Files (cosa ha cambiato),
// Approve (permessi e domande), Sessions. Le icone Window e Stow del Mac qui non ci sono.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Pulsar
{
    class SideDock
    {
        const double RailW = 48, R = 14, Btn = 32, Gap = 6, PanelW = 344;
        static readonly double RailH = 2 * R + 20 + 4 * Btn + 3 * Gap;
        const double RailTop = 150;

        static readonly SolidColorBrush Rail = T.B("#1D1F29"), BarSel = T.B("#1C1F28"), Veil = T.B("#000000", 0.16), CardFill = T.B("#FFFFFF", 0.055);
        static readonly SolidColorBrush BorderB = T.B("#FFFFFF", 0.06), White62 = T.B("#FFFFFF", 0.62), White96 = T.B("#FFFFFF", 0.96), Round = T.B("#FFFFFF", 0.07), Btn8 = T.B("#FFFFFF", 0.08);
        static readonly SolidColorBrush InkB = T.B("#13141E");
        static readonly string[] Glyphs = { "", "", "", "" };   // Work, Files, Approve, Sessions
        static readonly string[] Titles = { "Work", "Files", "Approve", "Sessions" };

        readonly AgentLine line = new AgentLine();
        Window rail, panel;
        Border[] buttons = new Border[4];
        Ellipse[] dots = new Ellipse[4];
        StackPanel body; TextBlock title, sub;
        DispatcherTimer watch, poll;
        bool railShown, panelOpen;
        DateTime leftAt = DateTime.MaxValue;
        int tab;
        string chosen = "", lastSig = "", lastAlert = "";
        Dictionary<string, object> state;
        List<Dictionary<string, object>> sessions = new List<Dictionary<string, object>>();
        int questionIndex;
        Dictionary<string, object> picked = new Dictionary<string, object>();

        double ScreenW { get { return SystemParameters.PrimaryScreenWidth; } }

        public void Start()
        {
            BuildRail();
            BuildPanel();
            line.Changed += () => rail.Dispatcher.BeginInvoke(new Action(Reload));
            line.Start();
            watch = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(80) };
            watch.Tick += (s, e) => Watch();
            watch.Start();
            poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            poll.Tick += (s, e) => Reload();
            poll.Start();
            Reload();
        }

        /// <summary>Dal menu dell'icona: fa uscire colonna e pannello.</summary>
        public void Show() { Reveal(); OpenPanel(tab); }

        static Window MakeWindow(string name, double w, double h)
        {
            var win = new Window
            {
                Title = name, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
                Topmost = true, ShowInTaskbar = false, ResizeMode = ResizeMode.NoResize, Width = w, Height = h, FontFamily = T.UI
            };
            TextOptions.SetTextFormattingMode(win, TextFormattingMode.Display);
            win.SourceInitialized += (s, e) =>
            {
                var h2 = new WindowInteropHelper(win).Handle;
                SetWindowLong(h2, -20, GetWindowLong(h2, -20) | 0x80 | 0x08000000);   // fuori da Alt+Tab, non ruba il fuoco
            };
            return win;
        }

        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
        struct POINT { public int X, Y; }

        // ---------------- colonna ----------------

        void BuildRail()
        {
            rail = MakeWindow("Pulsar side", RailW, RailH);
            rail.Top = RailTop; rail.Left = ScreenW;
            var root = new Grid();
            root.Children.Add(new Path { Data = RailShape(RailW, RailH, R), Fill = Rail });
            var col = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            for (int i = 0; i < 4; i++)
            {
                int k = i;
                var g = new TextBlock { Text = Glyphs[i], FontFamily = T.Icons, FontSize = 13.5, Foreground = White62, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                var b = new Border { Width = Btn, Height = Btn, CornerRadius = new CornerRadius(9), Background = Brushes.Transparent, Child = g, Cursor = Cursors.Hand, ToolTip = Titles[i], Margin = new Thickness(0, i == 0 ? 0 : Gap, 0, 0) };
                b.MouseLeftButtonUp += (s, e) => { if (panelOpen && tab == k) ClosePanel(); else OpenPanel(k); e.Handled = true; };
                var holder = new Grid();
                holder.Children.Add(b);
                var d = new Ellipse { Width = 6, Height = 6, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, i == 0 ? 3 : Gap + 3, 3, 0), Visibility = Visibility.Collapsed, IsHitTestVisible = false };
                holder.Children.Add(d);
                buttons[i] = b; dots[i] = d;
                col.Children.Add(holder);
            }
            root.Children.Add(col);
            rail.Content = root;
            rail.Show();
        }

        /// <summary>Attaccata al bordo destro, raccordi concavi sopra e sotto (TabShape del Mac).</summary>
        static Geometry RailShape(double w, double h, double r)
        {
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(new Point(w, 0), true, true);
                c.QuadraticBezierTo(new Point(w, r), new Point(w - r, r), true, true);
                c.LineTo(new Point(r, r), true, true);
                c.QuadraticBezierTo(new Point(0, r), new Point(0, 2 * r), true, true);
                c.LineTo(new Point(0, h - 2 * r), true, true);
                c.QuadraticBezierTo(new Point(0, h - r), new Point(r, h - r), true, true);
                c.LineTo(new Point(w - r, h - r), true, true);
                c.QuadraticBezierTo(new Point(w, h - r), new Point(w, h), true, true);
            }
            g.Freeze();
            return g;
        }

        void Reveal()
        {
            leftAt = DateTime.MaxValue;
            if (railShown) return;
            railShown = true;
            rail.BeginAnimation(Window.LeftProperty, new DoubleAnimation(ScreenW, ScreenW - RailW, TimeSpan.FromMilliseconds(320)) { EasingFunction = new CubicEase() });
        }

        void HideRail()
        {
            if (!railShown) return;
            railShown = false;
            rail.BeginAnimation(Window.LeftProperty, new DoubleAnimation(ScreenW, TimeSpan.FromMilliseconds(260)) { EasingFunction = new CubicEase() });
        }

        void Watch()
        {
            POINT p;
            if (!GetCursorPos(out p)) return;
            var src = PresentationSource.FromVisual(rail);
            if (src == null || src.CompositionTarget == null) return;
            var pt = src.CompositionTarget.TransformFromDevice.Transform(new Point(p.X, p.Y));
            bool band = pt.Y >= RailTop + R && pt.Y <= RailTop + RailH - R;
            if (!railShown) { if (pt.X >= ScreenW - 2 && band) Reveal(); return; }
            bool over = pt.X >= ScreenW - RailW - 6 && pt.Y >= RailTop - 6 && pt.Y <= RailTop + RailH + 6;
            if (over || panelOpen || HasPending()) { leftAt = DateTime.MaxValue; return; }
            if (leftAt == DateTime.MaxValue) leftAt = DateTime.Now;
            if ((DateTime.Now - leftAt).TotalSeconds > 0.5) HideRail();
        }

        // ---------------- pannello ----------------

        void BuildPanel()
        {
            panel = MakeWindow("Pulsar panel", PanelW, 300);
            panel.SizeToContent = SizeToContent.Height;
            panel.Top = 96; panel.Left = ScreenW - RailW - 10 - PanelW;
            panel.MaxHeight = SystemParameters.WorkArea.Height - 120;
            var card = new Border { Width = PanelW, CornerRadius = new CornerRadius(28), BorderBrush = T.B("#FFFFFF", 0.08), BorderThickness = new Thickness(1), Background = new LinearGradientBrush(T.C("#2B2E3C"), T.C("#22252F"), 90), Padding = new Thickness(16, 16, 16, 16) };
            var dock = new DockPanel();
            var head = new Grid { Margin = new Thickness(0, 0, 0, 12) };
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var glyph = new GlyphView { Width = 18, Height = 18, Margin = new Thickness(2, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
            head.Children.Add(glyph);
            var tx = new StackPanel();
            title = Txt("", 15, T.T1, FontWeights.SemiBold);
            sub = Txt("", 12, T.T2, FontWeights.Normal); sub.TextTrimming = TextTrimming.CharacterEllipsis;
            tx.Children.Add(title); tx.Children.Add(sub);
            Grid.SetColumn(tx, 1); head.Children.Add(tx);
            var x = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(14), Background = Round, Cursor = Cursors.Hand, VerticalAlignment = VerticalAlignment.Center };
            x.Child = new TextBlock { Text = T.GClose, FontFamily = T.Icons, FontSize = 9.5, Foreground = T.T1, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            x.MouseLeftButtonUp += (s, e) => { ClosePanel(); e.Handled = true; };
            Grid.SetColumn(x, 2); head.Children.Add(x);
            DockPanel.SetDock(head, Dock.Top);
            dock.Children.Add(head);
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, MaxHeight = 460 };
            body = new StackPanel();
            sv.Content = body;
            dock.Children.Add(sv);
            card.Child = dock;
            panel.Content = card;
        }

        void OpenPanel(int t)
        {
            tab = t;
            lastSig = "";
            panelOpen = true;
            Reveal();
            Render();
            if (!panel.IsVisible) panel.Show();
            UpdateRail();
        }

        void ClosePanel()
        {
            panelOpen = false;
            panel.Hide();
            UpdateRail();
        }

        // ---------------- dati ----------------

        Dictionary<string, object> Current()
        {
            var c = sessions.FirstOrDefault(s => Agent.S(s, "id") == chosen);
            return c ?? sessions.FirstOrDefault();
        }

        bool HasPending() { return sessions.Any(s => Agent.D(s, "pending") != null || Agent.D(s, "question") != null); }

        void Reload()
        {
            try { state = Agent.Load(); } catch { return; }
            var all = Agent.D(state, "sessions");
            sessions = all.Values.OfType<Dictionary<string, object>>()
                .OrderByDescending(s => Agent.D(s, "pending") != null || Agent.D(s, "question") != null)
                .ThenByDescending(s => Agent.N(s, "updated")).ToList();

            // Claude chiede qualcosa: la colonna esce e il pannello si apre su Approve, una volta per richiesta
            var waiting = sessions.FirstOrDefault(s => Agent.D(s, "pending") != null || Agent.D(s, "question") != null);
            if (waiting != null)
            {
                var req = Agent.D(waiting, "pending") ?? Agent.D(waiting, "question");
                var id = Agent.S(req, "id");
                if (id != lastAlert && line.IsWaiting(id))
                {
                    lastAlert = id; chosen = Agent.S(waiting, "id"); questionIndex = 0; picked = new Dictionary<string, object>();
                    System.Media.SystemSounds.Asterisk.Play();
                    OpenPanel(2);
                }
            }
            UpdateRail();
            if (panelOpen) Render();
        }

        void UpdateRail()
        {
            var s = Current();
            string st = Agent.S(s, "status");
            bool ask = HasPending();
            for (int i = 0; i < 4; i++)
            {
                bool on = panelOpen && tab == i;
                buttons[i].Background = on ? (Brush)BarSel : Brushes.Transparent;
                ((TextBlock)buttons[i].Child).Foreground = on ? White96 : White62;
                dots[i].Visibility = Visibility.Collapsed;
            }
            if (st == "working") { dots[0].Fill = T.A2B; dots[0].Visibility = Visibility.Visible; }
            if (ask) { dots[2].Fill = T.Red; dots[2].Visibility = Visibility.Visible; }
        }

        void Render()
        {
            var s = Current();
            var sig = tab + "|" + (s == null ? "" : Agent.Json().Serialize(s)) + "|" + sessions.Count + "|" + questionIndex + "|" + Agent.Json().Serialize(picked);
            if (sig == lastSig) return;
            lastSig = sig;
            title.Text = s == null ? Titles[tab] : Agent.S(s, "project");
            sub.Text = s == null ? "Claude Code" : StatusLine(s);
            body.Children.Clear();
            if (s == null && tab != 3) { body.Children.Add(Empty("No Claude Code session yet. Connect it from the Dev tab, then send a message.")); return; }
            if (tab == 0) RenderWork(s);
            else if (tab == 1) RenderFiles(s);
            else if (tab == 2) RenderApprove(s);
            else RenderSessions();
        }

        static string StatusLine(Dictionary<string, object> s)
        {
            var st = Agent.S(s, "status");
            if (st != "working" && st != "waiting") return StatusWord(st);
            int sec = (int)Math.Max(0, Agent.Now() - Agent.N(s, "started"));
            return (st == "waiting" ? "Waiting for you, " : "Working for ") + (sec >= 60 ? (sec / 60) + " m " + (sec % 60) + " s" : sec + " s");
        }

        static string StatusWord(string st)
        {
            return st == "working" ? "Working" : st == "waiting" ? "Waiting for you" : st == "done" ? "Finished" : "Idle";
        }

        // ---- Work ----

        void RenderWork(Dictionary<string, object> s)
        {
            var asked = Agent.S(s, "prompt");
            if (asked.Length > 0)
            {
                var c = new StackPanel();
                c.Children.Add(Txt("You asked", 11.5, T.T2, FontWeights.Normal));
                var p = Txt(asked, 13, T.T1, FontWeights.Normal); p.TextWrapping = TextWrapping.Wrap; p.Margin = new Thickness(0, 3, 0, 0);
                c.Children.Add(p);
                body.Children.Add(Card(c));
            }
            var summary = Agent.S(s, "summary");
            if (summary.Length > 0)
            {
                var c = new StackPanel();
                c.Children.Add(Txt("In plain words", 11.5, T.T2, FontWeights.Normal));
                var p = Txt(summary, 13, T.T1, FontWeights.Normal); p.TextWrapping = TextWrapping.Wrap; p.Margin = new Thickness(0, 3, 0, 0);
                c.Children.Add(p);
                body.Children.Add(Card(c));
            }
            var steps = (Agent.L(s, "steps") ?? new List<object>()).OfType<Dictionary<string, object>>().ToList();
            if (steps.Count == 0 && asked.Length == 0) body.Children.Add(Empty("Nothing running."));
            // in ordine, gli ultimi passi; un permesso in attesa sta subito sotto, come nel pannello del Mac
            foreach (var st in steps.Skip(Math.Max(0, steps.Count - 8))) body.Children.Add(StepRow(st, Agent.S(s, "project")));
            var pend = Agent.D(s, "pending");
            if (pend != null) body.Children.Add(PermissionCard(pend));
        }

        static Brush KindColor(string k)
        {
            if (k == "EDIT") return T.Amber;
            if (k == "READ" || k == "FIND") return T.A2B;
            if (k == "RUN") return T.B("#A9B4E8");
            return T.B("#808FD1");
        }

        static string KindWord(string k)
        {
            return k.Length == 0 ? "" : k.Substring(0, 1) + k.Substring(1).ToLowerInvariant();
        }

        UIElement StepRow(Dictionary<string, object> st, string project)
        {
            var kind = Agent.S(st, "kind");
            var row = new Border { Background = Veil, CornerRadius = new CornerRadius(10), Padding = new Thickness(9, 8, 12, 8), Margin = new Thickness(0, 0, 0, 6) };
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
            g.Children.Add(new Rectangle { Width = 3, RadiusX = 1.5, RadiusY = 1.5, Fill = KindColor(kind), HorizontalAlignment = HorizontalAlignment.Left });
            var tx = new StackPanel();
            var t = Txt(Agent.S(st, "label"), 13, T.T1, FontWeights.Medium); t.TextTrimming = TextTrimming.CharacterEllipsis;
            var detail = Agent.S(st, "note").Length > 0 ? Agent.S(st, "note") : Agent.S(st, "detail");
            var d = Txt(detail.Length > 0 ? detail : project, 11.5, T.T2, FontWeights.Normal); d.TextTrimming = TextTrimming.CharacterEllipsis;
            tx.Children.Add(t); tx.Children.Add(d);
            Grid.SetColumn(tx, 1); g.Children.Add(tx);
            var v = Txt(KindWord(kind), 12, T.T2, FontWeights.Normal); v.VerticalAlignment = VerticalAlignment.Center; v.Margin = new Thickness(8, 0, 4, 0);
            Grid.SetColumn(v, 2); g.Children.Add(v);
            var state1 = Agent.S(st, "state");
            UIElement mark;
            if (state1 == "now") mark = new Ellipse { Width = 7, Height = 7, Fill = T.A2B, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
            else mark = new TextBlock { Text = state1 == "failed" ? T.GClose : T.GDone, FontFamily = T.Icons, FontSize = 10, FontWeight = FontWeights.Bold, Foreground = state1 == "failed" ? T.Red : T.T3, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(mark, 3); g.Children.Add(mark);
            row.Child = g;
            return row;
        }

        // ---- Files ----

        void RenderFiles(Dictionary<string, object> s)
        {
            var ch = Agent.D(s, "changes");
            if (ch == null || ch.Count == 0) { body.Children.Add(Empty("No files changed in this request.")); return; }
            foreach (var kv in ch)
            {
                var c = kv.Value as Dictionary<string, object>;
                if (c == null) continue;
                var path = kv.Key; var sid = Agent.S(s, "id");
                var row = new Border { Background = Veil, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 9, 12, 9), Margin = new Thickness(0, 0, 0, 6), Cursor = Cursors.Hand, ToolTip = path };
                var g = new Grid();
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var n = Txt(Agent.S(c, "name"), 13, T.T1, FontWeights.Medium); n.TextTrimming = TextTrimming.CharacterEllipsis;
                g.Children.Add(n);
                var nums = new StackPanel { Orientation = Orientation.Horizontal };
                var plus = Txt("+" + (int)Agent.N(c, "add"), 12, T.A2B, FontWeights.Normal);
                var minus = Txt("−" + (int)Agent.N(c, "rem"), 12, T.T3, FontWeights.Normal); minus.Margin = new Thickness(7, 0, 0, 0);
                nums.Children.Add(plus); nums.Children.Add(minus);
                Grid.SetColumn(nums, 1); g.Children.Add(nums);
                row.Child = g;
                row.MouseLeftButtonUp += (x, e) => { ShowDiff(sid, path, Agent.S(c, "name")); e.Handled = true; };
                body.Children.Add(row);
            }
        }

        static void ShowDiff(string sid, string path, string name)
        {
            List<string> lines;
            if (!Agent.ReadDiff(sid).TryGetValue(path, out lines)) return;
            var w = new Window { Title = name, Width = 680, Height = 520, Background = T.Body, FontFamily = T.Mono };
            var sp = new StackPanel { Margin = new Thickness(14) };
            foreach (var l in lines)
            {
                var add = l.StartsWith("+"); var rem = l.StartsWith("-"); var hunk = l.StartsWith("@@");
                var t = new TextBlock { Text = l, FontSize = 12, Foreground = add ? T.A2B : rem ? T.Red : hunk ? T.T3 : T.T2, TextWrapping = TextWrapping.Wrap };
                sp.Children.Add(t);
            }
            w.Content = new ScrollViewer { Content = sp };
            w.Show();
        }

        // ---- Approve ----

        void RenderApprove(Dictionary<string, object> s)
        {
            var who = sessions.FirstOrDefault(x => Agent.D(x, "pending") != null || Agent.D(x, "question") != null) ?? s;
            var p = Agent.D(who, "pending");
            var q = Agent.D(who, "question");
            if (p != null) { body.Children.Add(PermissionCard(p)); return; }
            if (q != null) { body.Children.Add(QuestionCard(q)); return; }
            body.Children.Add(Empty("Nothing to approve."));
        }

        UIElement PermissionCard(Dictionary<string, object> p)
        {
            var id = Agent.S(p, "id");
            var c = new StackPanel();
            var top = new StackPanel { Orientation = Orientation.Horizontal };
            top.Children.Add(new Ellipse { Width = 6, Height = 6, Fill = T.Amber, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 7, 0) });
            top.Children.Add(Txt("Claude wants to run", 13.5, T.T1, FontWeights.SemiBold));
            c.Children.Add(top);
            var cmd = new TextBlock { Text = Agent.S(p, "what"), FontFamily = T.Mono, FontSize = 12, Foreground = T.B("#FFFFFF", 0.9), TextWrapping = TextWrapping.Wrap };
            c.Children.Add(new Border { Background = T.B("#000000", 0.32), CornerRadius = new CornerRadius(10), Padding = new Thickness(10), Margin = new Thickness(0, 9, 0, 10), Child = cmd });
            bool always = Agent.Bo(p, "always");
            var row = new UniformGrid { Rows = 1, Columns = always ? 3 : 2 };
            row.Children.Add(Capsule("Deny", false, () => Reply(id, "deny"), 0));
            if (always) row.Children.Add(Capsule("Always", false, () => Reply(id, "always"), 8));
            row.Children.Add(Capsule("Allow", true, () => Reply(id, "allow"), 8));
            c.Children.Add(row);
            return Card(c);
        }

        void Reply(string id, string behavior)
        {
            var d = new Dictionary<string, object>(); d["behavior"] = behavior;
            line.Answer(id, d);
            lastSig = "";
        }

        UIElement QuestionCard(Dictionary<string, object> q)
        {
            var id = Agent.S(q, "id");
            var items = (Agent.L(q, "items") ?? new List<object>()).OfType<Dictionary<string, object>>().ToList();
            if (items.Count == 0) return Empty("");
            if (questionIndex >= items.Count) questionIndex = 0;
            var it = items[questionIndex];
            var text = Agent.S(it, "question");
            bool multi = Agent.Bo(it, "multi");
            var c = new StackPanel();
            if (items.Count > 1) c.Children.Add(Txt((questionIndex + 1) + "/" + items.Count, 11.5, T.T2, FontWeights.Normal));
            var t = Txt(text, 15, T.T1, FontWeights.Medium); t.TextWrapping = TextWrapping.Wrap; t.Margin = new Thickness(0, 2, 0, 10);
            c.Children.Add(t);
            var wrap = new WrapPanel();
            foreach (var oo in (Agent.L(it, "options") ?? new List<object>()).OfType<Dictionary<string, object>>())
            {
                var label = Agent.S(oo, "label");
                bool on = multi && picked.ContainsKey(text) && ((List<object>)picked[text]).Contains(label);
                var b = Capsule(label, on, () =>
                {
                    if (!multi) { picked[text] = label; Advance(id, items); return; }
                    if (!picked.ContainsKey(text)) picked[text] = new List<object>();
                    var l = (List<object>)picked[text];
                    if (l.Contains(label)) l.Remove(label); else l.Add(label);
                    lastSig = ""; Render();
                }, 0);
                b.Margin = new Thickness(0, 0, 7, 7); b.Padding = new Thickness(14, 0, 14, 0);
                wrap.Children.Add(b);
            }
            c.Children.Add(wrap);
            var low = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 3, 0, 0) };
            var term = Capsule("In the terminal", false, () => line.Answer(id, new Dictionary<string, object>()), 0);
            term.Padding = new Thickness(14, 0, 14, 0);
            low.Children.Add(term);
            if (multi)
            {
                var send = Capsule(questionIndex == items.Count - 1 ? "Send" : "Next", true, () => Advance(id, items), 7);
                send.Padding = new Thickness(14, 0, 14, 0);
                low.Children.Add(send);
            }
            c.Children.Add(low);
            return Card(c);
        }

        void Advance(string id, List<Dictionary<string, object>> items)
        {
            if (questionIndex < items.Count - 1) { questionIndex++; lastSig = ""; Render(); return; }
            var d = new Dictionary<string, object>(); d["answers"] = picked;
            line.Answer(id, d);
            picked = new Dictionary<string, object>(); questionIndex = 0; lastSig = "";
        }

        // ---- Sessions ----

        void RenderSessions()
        {
            if (sessions.Count == 0) { body.Children.Add(Empty("No Claude Code session yet.")); return; }
            var cur = Current();
            foreach (var s in sessions)
            {
                var id = Agent.S(s, "id");
                bool on = cur != null && Agent.S(cur, "id") == id;
                var row = new Border { Background = on ? BarSel : Veil, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 9, 12, 9), Margin = new Thickness(0, 0, 0, 6), Cursor = Cursors.Hand };
                var c = new StackPanel();
                c.Children.Add(Txt(Agent.S(s, "project"), 13, T.T1, FontWeights.Medium));
                var p = Txt(StatusWord(Agent.S(s, "status")) + ". " + Agent.S(s, "prompt"), 11.5, T.T2, FontWeights.Normal); p.TextTrimming = TextTrimming.CharacterEllipsis;
                c.Children.Add(p);
                row.Child = c;
                row.MouseLeftButtonUp += (x, e) => { chosen = id; tab = 0; lastSig = ""; Render(); UpdateRail(); e.Handled = true; };
                body.Children.Add(row);
            }
        }

        // ---- pezzi ----

        static TextBlock Txt(string s, double size, Brush fg, FontWeight w)
        {
            return new TextBlock { Text = s, FontSize = size, Foreground = fg, FontWeight = w, FontFamily = T.UI };
        }

        static UIElement Empty(string s)
        {
            var t = Txt(s, 13, T.T2, FontWeights.Normal); t.TextWrapping = TextWrapping.Wrap; t.Margin = new Thickness(2, 2, 2, 6);
            return t;
        }

        static Border Card(UIElement c)
        {
            return new Border { Background = CardFill, BorderBrush = T.B("#FFFFFF", 0.05), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16), Padding = new Thickness(14), Margin = new Thickness(0, 0, 0, 8), Child = c };
        }

        static Border Capsule(string label, bool primary, Action click, double left)
        {
            var t = Txt(label, 13, primary ? InkB : T.T1, FontWeights.Medium);
            t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center;
            var b = new Border { Height = 32, CornerRadius = new CornerRadius(16), Background = primary ? Brushes.White : (Brush)Btn8, Child = t, Cursor = Cursors.Hand, Margin = new Thickness(left, 0, 0, 0) };
            b.MouseLeftButtonUp += (s, e) => { click(); e.Handled = true; };
            return b;
        }
    }
}
