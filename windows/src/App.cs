// Pulsar per Windows: il notch in alto al centro, come Pulsar su Mac.
// Avvio, una sola copia, icona nell'area di notifica (Esci, Claude Code, Avvio con Windows).
using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using Microsoft.Win32;

namespace Pulsar
{
    static class App
    {
        public const string Version = "0.2.0";
        public static string Exe { get { return System.Reflection.Assembly.GetExecutingAssembly().Location; } }
        static System.Windows.Forms.NotifyIcon tray;
        static NotchWindow notch;
        static DialWindow dial;
        static SideDock side;

        [STAThread]
        static int Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--statusline") return Limits.StatusLine();
            if (args.Length > 0 && args[0] == "--hook") return Agent.Hook(args);
            if (args.Length > 0 && args[0] == "--prova") return Agent.Rehearsal();
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Crash(e.ExceptionObject as Exception);
            try { return Run(); }
            catch (Exception e) { Crash(e); return 1; }
        }

        static void Crash(Exception e)
        {
            Log("crash: " + e);
            try { MessageBox.Show("Pulsar could not start.\n\n" + e, "Pulsar"); } catch { }
        }

        static int Run()
        {
            bool first;
            using (var m = new Mutex(true, "Local\\PulsarNotchWindows", out first))
            {
                if (!first) return 0;
                var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                app.DispatcherUnhandledException += (s, e) =>
                {
                    Log("error: " + e.Exception);
                    e.Handled = true;
                };
                notch = new NotchWindow();
                notch.Show();
                dial = new DialWindow();
                side = new SideDock();
                side.Start();
                dial.Show();   // fuori dallo schermo finché il mouse non tocca il bordo sinistro
                MakeTray();
                app.Run();
                tray.Visible = false;
                tray.Dispose();
            }
            return 0;
        }

        public static void Log(string s)
        {
            try
            {
                Directory.CreateDirectory(Limits.Folder);
                File.AppendAllText(Path.Combine(Limits.Folder, "pulsar.log"), DateTime.Now.ToString("s") + " " + s + Environment.NewLine);
            }
            catch { }
        }

        static void MakeTray()
        {
            tray = new System.Windows.Forms.NotifyIcon();
            try { tray.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Exe); } catch { tray.Icon = System.Drawing.SystemIcons.Application; }
            tray.Text = "Pulsar " + Version;
            tray.Visible = true;
            var menu = new System.Windows.Forms.ContextMenuStrip();

            var openItem = new System.Windows.Forms.ToolStripMenuItem("Open the notch");
            openItem.Click += (s, e) => notch.OpenTab(0, false);
            menu.Items.Add(openItem);

            var termItem = new System.Windows.Forms.ToolStripMenuItem("Terminal   Ctrl+Alt+T");
            termItem.Click += (s, e) => notch.OpenTab(2, true);
            menu.Items.Add(termItem);

            var dialItem = new System.Windows.Forms.ToolStripMenuItem("Show the dial");
            dialItem.Click += (s, e) => dial.Reveal(4);
            menu.Items.Add(dialItem);

            var sideItem = new System.Windows.Forms.ToolStripMenuItem("Show the side menu");
            sideItem.Click += (s, e) => side.Show();
            menu.Items.Add(sideItem);

            var demoItem = new System.Windows.Forms.ToolStripMenuItem("Run a demo session");
            demoItem.Click += (s, e) => { try { System.Diagnostics.Process.Start(Exe, "--prova"); } catch { } };
            menu.Items.Add(demoItem);

            menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());

            var claude = new System.Windows.Forms.ToolStripMenuItem("Connect Claude Code");
            claude.Click += (s, e) =>
            {
                if (Limits.Connected()) { MessageBox.Show("Already connected. Your next Claude Code message shows up in the side menu.", "Pulsar"); return; }
                var ok = MessageBox.Show("Pulsar will add a status line and hooks to Claude Code (~/.claude/settings.json), after making a copy of the file. Claude Code then shows its work in the side menu and tells Pulsar how much of your limit is used.\n\nContinue?", "Pulsar", MessageBoxButton.OKCancel);
                if (ok != MessageBoxResult.OK) return;
                var err = Limits.Connect(Exe);
                MessageBox.Show(err ?? "Connected. Send a message in Claude Code and it shows up in the side menu.", "Pulsar");
            };
            menu.Items.Add(claude);

            var startup = new System.Windows.Forms.ToolStripMenuItem("Start with Windows") { Checked = StartsWithWindows() };
            startup.Click += (s, e) => { SetStartWithWindows(!startup.Checked); startup.Checked = StartsWithWindows(); };
            menu.Items.Add(startup);

            menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
            var logItem = new System.Windows.Forms.ToolStripMenuItem("Open log");
            logItem.Click += (s, e) =>
            {
                // le ultime righe del registro in una finestra (Notepad non sempre parte)
                try
                {
                    var lines = File.ReadAllLines(Path.Combine(Limits.Folder, "pulsar.log"));
                    MessageBox.Show(string.Join("\n", lines.Skip(Math.Max(0, lines.Length - 30))), "Pulsar log");
                }
                catch (Exception ex) { MessageBox.Show("No log yet: " + ex.Message, "Pulsar log"); }
            };
            menu.Items.Add(logItem);
            var quit = new System.Windows.Forms.ToolStripMenuItem("Quit Pulsar");
            quit.Click += (s, e) => { notch.Shutdown(); Application.Current.Shutdown(); };
            menu.Items.Add(quit);

            tray.ContextMenuStrip = menu;
            tray.MouseClick += (s, e) => { if (e.Button == System.Windows.Forms.MouseButtons.Left) notch.OpenTab(0, false); };
        }

        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        static bool StartsWithWindows()
        {
            try { using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k != null && k.GetValue("Pulsar") != null; }
            catch { return false; }
        }

        static void SetStartWithWindows(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k == null) return;
                    if (on) k.SetValue("Pulsar", "\"" + Exe + "\"");
                    else k.DeleteValue("Pulsar", false);
                }
            }
            catch { }
        }
    }
}
