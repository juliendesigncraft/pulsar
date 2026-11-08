// Il terminale che scende dal notch: un cmd.exe sempre acceso dietro, così "cd" resta.
// Dopo ogni comando chiede la cartella corrente con un segnale, per il ramo Git.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace Pulsar
{
    class Shell
    {
        const string Mark = "__PULSAR_CWD__";
        Process p;
        public string Cwd;
        public event Action<string> Line;      // riga di uscita (thread qualsiasi)
        public event Action CwdChanged;
        bool skipBlank = true;

        public Shell(string start)
        {
            Cwd = Directory.Exists(start) ? start : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        public bool Running { get { return p != null && !p.HasExited; } }

        void Start()
        {
            var si = new ProcessStartInfo("cmd.exe", "/Q /K chcp 65001 >nul")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = Cwd,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            p = new Process { StartInfo = si, EnableRaisingEvents = true };
            p.OutputDataReceived += (s, e) => Got(e.Data);
            p.ErrorDataReceived += (s, e) => Got(e.Data);
            p.Start();
            p.StandardInput.AutoFlush = true;
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            // /Q non basta quando l'ingresso arriva da una pipe: il prompt compare lo stesso.
            p.StandardInput.WriteLine("@echo off");
            p.StandardInput.WriteLine("prompt $S");
        }

        void Got(string data)
        {
            if (data == null) return;
            int m = data.IndexOf(Mark);
            if (m >= 0)
            {
                var c = data.Substring(m + Mark.Length).Trim();
                if (c.Length > 0 && c != Cwd) { Cwd = c; var h = CwdChanged; if (h != null) h(); }
                return;
            }
            if (data.Trim().Length == 0 && skipBlank) return;
            var l = Line; if (l != null) l(data);
        }

        public void Run(string command)
        {
            if (!Running) Start();
            try
            {
                p.StandardInput.WriteLine(command);
                p.StandardInput.WriteLine("echo " + Mark + "%CD%");
            }
            catch { }
        }

        /// <summary>Ferma tutto quello che gira nel terminale (come chiudere la finestra) e riparte pulito.</summary>
        public void Restart()
        {
            Kill();
            Start();
        }

        public void Kill()
        {
            try
            {
                if (Running)
                {
                    var k = Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + p.Id) { CreateNoWindow = true, UseShellExecute = false });
                    if (k != null) k.WaitForExit(2000);
                }
            }
            catch { }
            p = null;
        }

        /// <summary>Apre Windows Terminal (o cmd) nella stessa cartella, per i programmi a schermo intero.</summary>
        public void OpenFull()
        {
            try { Process.Start(new ProcessStartInfo("wt.exe", "-d \"" + Cwd + "\"") { UseShellExecute = true }); }
            catch
            {
                try { Process.Start(new ProcessStartInfo("cmd.exe") { WorkingDirectory = Cwd, UseShellExecute = true }); } catch { }
            }
        }
    }
}
