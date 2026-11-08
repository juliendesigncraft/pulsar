// Strumenti da sviluppatore, da ZincWolf (reel salvato il 06/11/2026):
// i server in ascolto per porta, il ramo Git della cartella del terminale, il limite di Claude Code.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;

namespace Pulsar
{
    class Listener
    {
        public int Port;
        public int Pid;
        public string Name;
    }

    static class Ports
    {
        [DllImport("iphlpapi.dll", SetLastError = true)]
        static extern uint GetExtendedTcpTable(IntPtr pTcpTable, ref int pdwSize, bool bOrder, int ulAf, int tableClass, uint reserved);

        const int AF_INET = 2, AF_INET6 = 23, TCP_TABLE_OWNER_PID_LISTENER = 3;

        // Processi di sistema: ascoltano sempre, non sono server tuoi.
        static readonly HashSet<string> Sistema = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            "System", "Idle", "svchost", "lsass", "wininit", "services", "spoolsv", "smss", "csrss",
            "winlogon", "jhi_service", "OneDrive", "Pulsar", "msedgewebview2", "SearchHost", "WUDFHost" };

        public static List<Listener> Read()
        {
            var byPort = new Dictionary<int, Listener>();
            Fill(AF_INET, 24, byPort);   // MIB_TCPROW_OWNER_PID: 6 DWORD
            Fill(AF_INET6, 56, byPort);  // MIB_TCP6ROW_OWNER_PID: 16+4+4+16+4+4+4+4
            return byPort.Values.Where(l => !Sistema.Contains(l.Name) && l.Port >= 1024 && l.Port < 49152)
                                .OrderBy(l => l.Port).ToList();
        }

        static void Fill(int af, int rowSize, Dictionary<int, Listener> into)
        {
            int size = 0;
            GetExtendedTcpTable(IntPtr.Zero, ref size, true, af, TCP_TABLE_OWNER_PID_LISTENER, 0);
            if (size <= 0) return;
            IntPtr buf = Marshal.AllocHGlobal(size);
            try
            {
                if (GetExtendedTcpTable(buf, ref size, true, af, TCP_TABLE_OWNER_PID_LISTENER, 0) != 0) return;
                int n = Marshal.ReadInt32(buf);
                for (int i = 0; i < n; i++)
                {
                    IntPtr row = new IntPtr(buf.ToInt64() + 4 + (long)i * rowSize);
                    int portOff = af == AF_INET ? 8 : 20;     // dwLocalPort
                    int pidOff = af == AF_INET ? 20 : 52;     // dwOwningPid
                    int raw = Marshal.ReadInt32(row, portOff);
                    int port = ((raw & 0xFF) << 8) | ((raw >> 8) & 0xFF);  // ordine di rete
                    int pid = Marshal.ReadInt32(row, pidOff);
                    if (into.ContainsKey(port)) continue;
                    into[port] = new Listener { Port = port, Pid = pid, Name = ProcName(pid) };
                }
            }
            finally { Marshal.FreeHGlobal(buf); }
        }

        static string ProcName(int pid)
        {
            if (pid == 0) return "Idle";
            if (pid == 4) return "System";
            try { return Process.GetProcessById(pid).ProcessName; } catch { return "pid " + pid; }
        }

        public static void Open(int port)
        {
            try { Process.Start("http://localhost:" + port + "/"); } catch { }
        }

        public static void Stop(int pid)
        {
            try { Process.GetProcessById(pid).Kill(); } catch { }
        }
    }

    static class Git
    {
        /// <summary>Ramo della cartella (o di una cartella sopra). Legge .git/HEAD: Git non serve installato.</summary>
        public static string Branch(string dir)
        {
            try
            {
                var d = new DirectoryInfo(dir);
                while (d != null)
                {
                    var g = Path.Combine(d.FullName, ".git");
                    string head = null;
                    if (Directory.Exists(g)) head = Path.Combine(g, "HEAD");
                    else if (File.Exists(g))
                    {
                        // worktree o sottomodulo: ".git" è un file con "gitdir: <percorso>"
                        var line = File.ReadAllText(g).Trim();
                        if (line.StartsWith("gitdir:"))
                        {
                            var p = line.Substring(7).Trim();
                            if (!Path.IsPathRooted(p)) p = Path.Combine(d.FullName, p);
                            head = Path.Combine(p, "HEAD");
                        }
                    }
                    if (head != null && File.Exists(head))
                    {
                        var h = File.ReadAllText(head).Trim();
                        if (h.StartsWith("ref: refs/heads/")) return h.Substring(16);
                        return h.Length >= 7 ? h.Substring(0, 7) : h;   // HEAD staccato: commit corto
                    }
                    d = d.Parent;
                }
            }
            catch { }
            return null;
        }

        public static string RepoName(string dir)
        {
            try
            {
                var d = new DirectoryInfo(dir);
                while (d != null)
                {
                    if (Directory.Exists(Path.Combine(d.FullName, ".git")) || File.Exists(Path.Combine(d.FullName, ".git"))) return d.Name;
                    d = d.Parent;
                }
            }
            catch { }
            return null;
        }
    }

    class Limit
    {
        public double FiveHour = -1, SevenDay = -1;   // percentuale usata, -1 = non noto
        public long FiveReset, SevenReset;            // secondi Unix
        public DateTime Read;
        public string Model = "";
        public bool Known { get { return FiveHour >= 0; } }
    }

    /// <summary>
    /// Limite di Claude Code. Claude Code passa alla sua riga di stato un JSON con rate_limits
    /// (five_hour e seven_day, used_percentage e resets_at). "Pulsar.exe --statusline" lo salva
    /// e il notch lo legge. Non stima nulla: se Claude Code non lo manda, il notch dice "unknown".
    /// </summary>
    static class Limits
    {
        public static string Folder { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Pulsar"); } }
        static string FilePath { get { return Path.Combine(Folder, "claude-limit.json"); } }
        static string Settings { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "settings.json"); } }

        /// <summary>Modo riga di stato: legge il JSON da stdin, lo salva, stampa una riga corta.</summary>
        public static int StatusLine()
        {
            string json;
            try { json = Console.In.ReadToEnd(); } catch { return 0; }
            try
            {
                Directory.CreateDirectory(Folder);
                var tmp = FilePath + ".tmp";
                File.WriteAllText(tmp, json);
                if (File.Exists(FilePath)) File.Delete(FilePath);
                File.Move(tmp, FilePath);
            }
            catch { }
            var l = Parse(json);
            try
            {
                var o = Console.OpenStandardOutput();
                var w = new StreamWriter(o);
                w.Write(l.Known ? ("5h " + Math.Round(l.FiveHour) + "%" + (l.SevenDay >= 0 ? "  7d " + Math.Round(l.SevenDay) + "%" : "")) : "Pulsar");
                w.Flush();
            }
            catch { }
            return 0;
        }

        public static Limit Load()
        {
            try
            {
                if (!File.Exists(FilePath)) return new Limit();
                var l = Parse(File.ReadAllText(FilePath));
                l.Read = File.GetLastWriteTime(FilePath);
                return l;
            }
            catch { return new Limit(); }
        }

        static Limit Parse(string json)
        {
            var l = new Limit();
            try
            {
                var root = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>;
                if (root == null) return l;
                object m;
                if (root.TryGetValue("model", out m) && m is Dictionary<string, object>)
                {
                    object dn; if (((Dictionary<string, object>)m).TryGetValue("display_name", out dn) && dn != null) l.Model = dn.ToString();
                }
                object rl;
                if (!root.TryGetValue("rate_limits", out rl) || !(rl is Dictionary<string, object>)) return l;
                var r = (Dictionary<string, object>)rl;
                Window(r, "five_hour", out l.FiveHour, out l.FiveReset);
                Window(r, "seven_day", out l.SevenDay, out l.SevenReset);
            }
            catch { }
            return l;
        }

        static void Window(Dictionary<string, object> r, string key, out double pct, out long reset)
        {
            pct = -1; reset = 0;
            object w;
            if (!r.TryGetValue(key, out w) || !(w is Dictionary<string, object>)) return;
            var d = (Dictionary<string, object>)w;
            object p, t;
            if (d.TryGetValue("used_percentage", out p) && p != null) pct = Convert.ToDouble(p);
            if (d.TryGetValue("resets_at", out t) && t != null)
            {
                long v;
                if (long.TryParse(t.ToString(), out v)) reset = v;
                else { DateTime dt; if (DateTime.TryParse(t.ToString(), out dt)) reset = (long)(dt.ToUniversalTime() - new DateTime(1970, 1, 1)).TotalSeconds; }
            }
        }

        public static string ResetIn(long unix)
        {
            if (unix <= 0) return "";
            var at = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(unix);
            var left = at - DateTime.UtcNow;
            if (left.TotalSeconds <= 0) return "resets now";
            if (left.TotalHours >= 24) return "resets in " + (int)left.TotalDays + "d " + left.Hours + "h";
            if (left.TotalHours >= 1) return "resets in " + (int)left.TotalHours + "h " + left.Minutes + "m";
            return "resets in " + Math.Max(1, left.Minutes) + "m";
        }

        // ---- Collegamento a Claude Code (scelta del cliente, con copia di sicurezza) ----

        public static bool Connected()
        {
            try { return File.Exists(Settings) && File.ReadAllText(Settings).Contains("--hook"); } catch { return false; }
        }

        /// <summary>Scrive statusLine in ~/.claude/settings.json. Non tocca una riga di stato che c'è già.</summary>
        public static string Connect(string exe)
        {
            try
            {
                var ser = new JavaScriptSerializer();
                Dictionary<string, object> root = new Dictionary<string, object>();
                if (File.Exists(Settings))
                {
                    var txt = File.ReadAllText(Settings);
                    if (txt.Trim().Length > 0)
                    {
                        root = ser.DeserializeObject(txt) as Dictionary<string, object>;
                        if (root == null) return "Your Claude Code settings.json could not be read. Nothing was changed.";
                    }
                    File.Copy(Settings, Settings + ".before-pulsar-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"), true);
                }
                else Directory.CreateDirectory(Path.GetDirectoryName(Settings));
                // una riga di stato che c'è già non si tocca: quella del cliente resta sua
                if (!root.ContainsKey("statusLine"))
                {
                    var sl = new Dictionary<string, object>();
                    sl["type"] = "command";
                    sl["command"] = "\"" + exe.Replace("\\", "/") + "\" --statusline";
                    root["statusLine"] = sl;
                }
                root = Agent.Norm(root) as Dictionary<string, object>;
                Agent.AddHooks(root, exe);
                File.WriteAllText(Settings, Pretty(ser.Serialize(root)));
                return null;
            }
            catch (Exception e) { return "Could not connect: " + e.Message; }
        }

        // JavaScriptSerializer scrive tutto su una riga: rientro minimo per chi riapre il file.
        static string Pretty(string json)
        {
            var sb = new System.Text.StringBuilder();
            int ind = 0; bool str = false, esc = false;
            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (str)
                {
                    sb.Append(c);
                    if (esc) esc = false;
                    else if (c == '\\') esc = true;
                    else if (c == '"') str = false;
                    continue;
                }
                if (c == '"') { str = true; sb.Append(c); continue; }
                if (c == '{' || c == '[') { sb.Append(c).Append('\n').Append(new string(' ', (++ind) * 2)); }
                else if (c == '}' || c == ']') { sb.Append('\n').Append(new string(' ', (--ind) * 2)).Append(c); }
                else if (c == ',') { sb.Append(c).Append('\n').Append(new string(' ', ind * 2)); }
                else if (c == ':') sb.Append(": ");
                else sb.Append(c);
            }
            return sb.ToString();
        }
    }
}
