// Agent: Claude Code dal vivo nel notch, come Pulsar per Mac (agente/hook.py + agente-linea.swift).
// Claude Code lancia "Pulsar.exe --hook" a ogni evento con un JSON su stdin. L'hook tiene lo stato delle
// sessioni in %APPDATA%\Pulsar\agente\state.json e parla con Pulsar su una named pipe: "ping" dopo ogni
// evento, "wait" per permessi e domande (resta in linea finché si risponde dal notch). Se Pulsar è spento
// l'hook esce subito e Claude Code chiede nel terminale come sempre: non resta mai bloccato.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace Pulsar
{
    static class Agent
    {
        public static string Folder { get { return Path.Combine(Limits.Folder, "agente"); } }
        static string StatePath { get { return Path.Combine(Folder, "state.json"); } }
        static string Diffs { get { return Path.Combine(Folder, "diffs"); } }
        static string ContextPath { get { return Path.Combine(Folder, "contesto.json"); } }
        public static string PipeName { get { return "PulsarAgent-" + Environment.UserName; } }

        const int Wait = 25, WaitAsk = 90, MaxSteps = 40, MaxDiffLines = 4000;
        const double Keep = 6 * 3600;
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
        static readonly Regex TestRe = new Regex(@"\b(pytest|jest|vitest|mocha|rspec|unittest|go test|cargo test|dotnet test|(npm|pnpm|yarn|bun)( run)? test|make test)\b");

        public static JavaScriptSerializer Json() { return new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 200 }; }
        public static double Now() { return (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds; }

        // ---------------- dizionari, come in Python ----------------

        public static object Norm(object o)
        {
            var d = o as Dictionary<string, object>;
            if (d != null) { foreach (var k in d.Keys.ToList()) d[k] = Norm(d[k]); return d; }
            var a = o as object[];
            if (a != null) return a.Select(Norm).ToList();
            var l = o as System.Collections.ArrayList;
            if (l != null) return l.Cast<object>().Select(Norm).ToList();
            return o;
        }
        public static string S(Dictionary<string, object> d, string k)
        {
            object v; return d != null && d.TryGetValue(k, out v) && v != null ? Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : "";
        }
        public static double N(Dictionary<string, object> d, string k)
        {
            object v; if (d == null || !d.TryGetValue(k, out v) || v == null) return 0;
            try { return Convert.ToDouble(v, System.Globalization.CultureInfo.InvariantCulture); } catch { return 0; }
        }
        public static bool Bo(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) && v is bool && (bool)v; }
        public static Dictionary<string, object> D(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) ? v as Dictionary<string, object> : null; }
        public static List<object> L(Dictionary<string, object> d, string k)
        {
            object v; if (d == null || !d.TryGetValue(k, out v)) return null;
            return v as List<object>;
        }
        static Dictionary<string, object> Obj(params object[] kv)
        {
            var d = new Dictionary<string, object>();
            for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
            return d;
        }

        static string Short(string t, int n)
        {
            t = string.Join(" ", (t ?? "").Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries));
            return t.Length <= n ? t : t.Substring(0, n - 1) + "…";
        }
        static string Base(string p)
        {
            p = (p ?? "").TrimEnd('/', '\\');
            int i = Math.Max(p.LastIndexOf('/'), p.LastIndexOf('\\'));
            return i >= 0 ? p.Substring(i + 1) : p;
        }

        // ---------------- cosa sta facendo, in parole semplici ----------------

        public static string[] Describe(string tool, Dictionary<string, object> inp)
        {
            if (tool == "Read") return new[] { "READ", Base(S(inp, "file_path")) };
            if (tool == "Edit" || tool == "MultiEdit" || tool == "Write" || tool == "NotebookEdit")
                return new[] { "EDIT", Base(S(inp, "file_path").Length > 0 ? S(inp, "file_path") : S(inp, "notebook_path")) };
            if (tool == "Bash" || tool == "PowerShell") return new[] { "RUN", Short(S(inp, "description").Length > 0 ? S(inp, "description") : S(inp, "command"), 56) };
            if (tool == "Grep" || tool == "Glob") return new[] { "FIND", Short(S(inp, "pattern"), 40) };
            if (tool == "WebFetch" || tool == "WebSearch") return new[] { "WEB", Short(S(inp, "query").Length > 0 ? S(inp, "query") : S(inp, "url"), 48) };
            if (tool == "Task" || tool == "Agent") return new[] { "AGENT", Short(S(inp, "description").Length > 0 ? S(inp, "description") : "Helper", 48) };
            if (tool == "TodoWrite") return new[] { "PLAN", "Updating the plan" };
            if (tool == "AskUserQuestion") return new[] { "ASK", "Asking you" };
            if (tool.StartsWith("mcp__")) { var parts = tool.Split(new[] { "__" }, StringSplitOptions.None); return new[] { "TOOL", Short(parts[parts.Length - 1].Replace("_", " "), 48) }; }
            return new[] { "TOOL", Short(tool, 48) };
        }

        static string What(string tool, Dictionary<string, object> inp)
        {
            if (tool == "Bash" || tool == "PowerShell") return Short(S(inp, "command"), 160);
            if (S(inp, "file_path").Length > 0) return tool + " " + Base(S(inp, "file_path"));
            if (S(inp, "url").Length > 0) return tool + " " + Short(S(inp, "url"), 120);
            return tool;
        }

        static List<string> PatchLines(string tool, Dictionary<string, object> inp, object resp)
        {
            var outp = new List<string>();
            var r = resp as Dictionary<string, object>;
            if (r == null) return outp;
            var hunks = L(r, "structuredPatch");
            if (hunks != null)
                foreach (var ho in hunks)
                {
                    var h = ho as Dictionary<string, object>;
                    if (h == null) continue;
                    double start = N(h, "newStart"); if (start == 0) start = N(h, "oldStart");
                    outp.Add("@@ " + (int)start);
                    var lines = L(h, "lines");
                    if (lines != null) foreach (var l in lines) outp.Add(Convert.ToString(l));
                }
            if (outp.Count == 0 && tool == "Write")
            {
                var content = S(r, "content"); if (content.Length == 0) content = S(inp, "content");
                outp.Add("@@ 1");
                foreach (var l in content.Split('\n')) outp.Add("+" + l.TrimEnd('\r'));
            }
            return outp;
        }

        static string Plain(string md)
        {
            var t = md ?? "";
            t = Regex.Replace(t, "```.*?```", "", RegexOptions.Singleline);
            t = Regex.Replace(t, @"\[([^\]]+)\]\([^)]+\)", "$1");
            t = Regex.Replace(t, @"[*_`#>]+", "");
            t = Regex.Replace(t, @"^\s*[-•]\s*", "", RegexOptions.Multiline);
            var paras = Regex.Split(t.Replace("\r", ""), @"\n\s*\n").Select(p => string.Join(" ", p.Split(new[] { ' ', '\n', '\t' }, StringSplitOptions.RemoveEmptyEntries))).Where(p => p.Length > 0).Take(2);
            var o = string.Join(" ", paras);
            if (o.Length <= 420) return o;
            o = o.Substring(0, 419); int sp = o.LastIndexOf(' ');
            return (sp > 0 ? o.Substring(0, sp) : o) + "…";
        }

        static string CleanPrompt(string raw)
        {
            var m = Regex.Match(raw ?? "", "<scheduled-task[^>]*name=\"([^\"]+)\"");
            if (m.Success) return "Scheduled: " + m.Groups[1].Value;
            return Short(Regex.Replace(raw ?? "", "<[^>]+>", " "), 220);
        }

        static List<object> ParseQuestions(Dictionary<string, object> inp)
        {
            var qs = L(inp, "questions");
            if (qs == null || qs.Count < 1 || qs.Count > 4) return null;
            var outp = new List<object>();
            foreach (var qo in qs)
            {
                var q = qo as Dictionary<string, object>;
                if (q == null || S(q, "question").Length == 0) return null;
                var opts = L(q, "options");
                if (opts == null || opts.Count < 2 || opts.Count > 4) return null;
                var clean = new List<object>();
                foreach (var oo in opts)
                {
                    var o = oo as Dictionary<string, object>;
                    if (o == null || S(o, "label").Length == 0) return null;
                    clean.Add(Obj("label", S(o, "label"), "description", S(o, "description")));
                }
                var header = S(q, "header");
                outp.Add(Obj("question", S(q, "question"), "header", header.Length > 12 ? header.Substring(0, 12) : header, "multi", Bo(q, "multiSelect"), "options", clean));
            }
            return outp;
        }

        // ---------------- stato su disco, con un lucchetto fra processi ----------------

        public static Dictionary<string, object> Load()
        {
            try
            {
                var d = Norm(Json().DeserializeObject(File.ReadAllText(StatePath, Utf8))) as Dictionary<string, object>;
                if (d != null && D(d, "sessions") != null) return d;
            }
            catch { }
            return Obj("sessions", new Dictionary<string, object>());
        }

        static void Save(Dictionary<string, object> st)
        {
            Directory.CreateDirectory(Folder);
            var tmp = StatePath + ".tmp";
            File.WriteAllText(tmp, Json().Serialize(st), Utf8);
            if (File.Exists(StatePath)) File.Replace(tmp, StatePath, null); else File.Move(tmp, StatePath);
        }

        public static T Locked<T>(Func<Dictionary<string, object>, T> fn)
        {
            using (var m = new Mutex(false, "Local\\PulsarAgentState"))
            {
                bool got = false;
                try { got = m.WaitOne(3000); } catch (AbandonedMutexException) { got = true; }
                try
                {
                    var st = Load();
                    var r = fn(st);
                    Save(st);
                    return r;
                }
                finally { if (got) m.ReleaseMutex(); }
            }
        }

        static Dictionary<string, object> Session(Dictionary<string, object> st, Dictionary<string, object> ev)
        {
            var sid = S(ev, "session_id"); if (sid.Length == 0) sid = "unknown";
            var all = D(st, "sessions");
            var s = D(all, sid);
            if (s == null)
            {
                var cwd = S(ev, "cwd");
                s = Obj("id", sid, "cwd", cwd, "project", Base(cwd), "agent", "Claude", "prompt", "", "started", Now(), "status", "idle",
                        "steps", new List<object>(), "pending", null, "question", null, "summary", "", "finished", 0.0, "tests_at", 0.0,
                        "tests_ok", null, "stale", new List<object>(), "files", new List<object>(), "changes", new Dictionary<string, object>(),
                        "fails", new Dictionary<string, object>());
                all[sid] = s;
            }
            if (D(s, "changes") == null) s["changes"] = new Dictionary<string, object>();
            if (D(s, "fails") == null) s["fails"] = new Dictionary<string, object>();
            if (L(s, "steps") == null) s["steps"] = new List<object>();
            if (L(s, "files") == null) s["files"] = new List<object>();
            if (L(s, "stale") == null) s["stale"] = new List<object>();
            s["updated"] = Now();
            return s;
        }

        static Dictionary<string, object> StepFor(Dictionary<string, object> s, string tid)
        {
            var steps = L(s, "steps");
            for (int i = steps.Count - 1; i >= 0; i--) { var st = steps[i] as Dictionary<string, object>; if (st != null && S(st, "id") == tid) return st; }
            return null;
        }

        static string DiffPath(string sid) { return Path.Combine(Diffs, Regex.Replace(sid, "[^A-Za-z0-9_-]", "_") + ".json"); }

        static void SaveDiff(string sid, string path, List<string> lines)
        {
            if (lines.Count == 0) return;
            Directory.CreateDirectory(Diffs);
            var p = DiffPath(sid);
            Dictionary<string, object> d = null;
            try { d = Norm(Json().DeserializeObject(File.ReadAllText(p, Utf8))) as Dictionary<string, object>; } catch { }
            if (d == null) d = new Dictionary<string, object>();
            var cur = L(d, path) ?? new List<object>();
            cur.AddRange(lines.Cast<object>());
            if (cur.Count > MaxDiffLines) cur = cur.Skip(cur.Count - MaxDiffLines).ToList();
            d[path] = cur;
            File.WriteAllText(p, Json().Serialize(d), Utf8);
        }

        public static Dictionary<string, List<string>> ReadDiff(string sid)
        {
            var outp = new Dictionary<string, List<string>>();
            try
            {
                var d = Norm(Json().DeserializeObject(File.ReadAllText(DiffPath(sid), Utf8))) as Dictionary<string, object>;
                if (d != null) foreach (var kv in d) { var l = kv.Value as List<object>; if (l != null) outp[kv.Key] = l.Select(x => Convert.ToString(x)).ToList(); }
            }
            catch { }
            return outp;
        }

        static void DropDiff(string sid) { try { File.Delete(DiffPath(sid)); } catch { } }

        // ---------------- un evento di Claude Code ----------------

        static string Handle(Dictionary<string, object> ev, Dictionary<string, object> st)
        {
            var name = S(ev, "hook_event_name");
            var s = Session(st, ev);
            var tool = S(ev, "tool_name");
            var inp = D(ev, "tool_input") ?? new Dictionary<string, object>();
            var tid = S(ev, "tool_use_id"); if (tid.Length == 0) tid = Guid.NewGuid().ToString("N");
            var steps = L(s, "steps");

            if (name == "UserPromptSubmit")
            {
                var raw = S(ev, "prompt").TrimStart();
                string prompt;
                if (raw.StartsWith("<task-notification") || raw.StartsWith("<cross-session-message") || raw.StartsWith("[Subagent hand-back]")
                    || raw.StartsWith("Linked sessions now") || raw.StartsWith("The session \"") || raw.StartsWith("Another Claude session"))
                    prompt = S(s, "prompt").Length > 0 ? S(s, "prompt") : "Background task finished";
                else prompt = CleanPrompt(raw);
                s["prompt"] = prompt; s["started"] = Now(); s["status"] = "working";
                s["steps"] = new List<object>(); s["summary"] = ""; s["finished"] = 0.0; s["pending"] = null; s["question"] = null;
                s["stale"] = new List<object>(); s["files"] = new List<object>(); s["changes"] = new Dictionary<string, object>();
                s["fails"] = new Dictionary<string, object>(); s["tests_ok"] = null; s["tests_at"] = 0.0;
                DropDiff(S(s, "id"));
            }
            else if (name == "PreToolUse")
            {
                var kl = Describe(tool, inp);
                foreach (Dictionary<string, object> x in steps) if (S(x, "state") == "now" && kl[0] != "AGENT") x["state"] = "done";
                steps.Add(Obj("id", tid, "kind", kl[0], "label", kl[1], "state", "now", "t", Now(), "note", "", "cmd", tool == "Bash" ? S(inp, "command") : ""));
                if (steps.Count > MaxSteps) s["steps"] = steps.Skip(steps.Count - MaxSteps).ToList();
                if (S(s, "status") != "waiting") s["status"] = "working";
            }
            else if (name == "PostToolUse" || name == "PostToolUseFailure")
            {
                var stp = StepFor(s, tid);
                bool failed = name == "PostToolUseFailure";
                object resp; ev.TryGetValue("tool_response", out resp);
                bool editing = tool == "Edit" || tool == "MultiEdit" || tool == "Write";
                var lines = editing && !failed ? PatchLines(tool, inp, resp) : new List<string>();
                int add = lines.Count(l => l.StartsWith("+")), rem = lines.Count(l => l.StartsWith("-"));
                if (stp != null)
                {
                    stp["state"] = failed ? "failed" : "done";
                    if (editing && (add > 0 || rem > 0)) stp["detail"] = "+" + add + " −" + rem;
                    var rd = resp as Dictionary<string, object>;
                    if (tool == "Read" && D(rd, "file") != null)
                    {
                        var total = N(D(rd, "file"), "totalLines"); if (total == 0) total = N(D(rd, "file"), "numLines");
                        if (total > 0) stp["detail"] = (int)total + " lines";
                    }
                }
                if (editing || tool == "NotebookEdit")
                {
                    var full = S(inp, "file_path"); if (full.Length == 0) full = S(inp, "notebook_path");
                    var f = Base(full);
                    var files = L(s, "files");
                    if (f.Length > 0 && !files.Contains(f)) files.Add(f);
                    if (full.Length > 0 && lines.Count > 0)
                    {
                        var ch = D(s, "changes");
                        var c = D(ch, full) ?? Obj("name", f, "add", 0.0, "rem", 0.0);
                        c["add"] = N(c, "add") + add; c["rem"] = N(c, "rem") + rem;
                        ch[full] = c;
                        SaveDiff(S(s, "id"), full, lines);
                    }
                }
                if (tool == "Bash")
                {
                    var cmd = S(inp, "command");
                    var key = Short(cmd, 80);
                    var fails = D(s, "fails");
                    if (failed) fails[key] = N(fails, key) + 1;
                    else if (N(fails, key) > 0 && stp != null) stp["note"] = "try " + (N(fails, key) + 1);
                    if (TestRe.IsMatch(cmd)) { s["tests_at"] = Now(); s["tests_ok"] = !failed; s["stale"] = new List<object>(); }
                }
                if (S(s, "status") == "waiting" && D(s, "pending") == null && D(s, "question") == null) s["status"] = "working";
            }
            else if (name == "PermissionRequest")
            {
                var pid = Guid.NewGuid().ToString("N").Substring(0, 12);
                object sugg; bool always = ev.TryGetValue("permission_suggestions", out sugg) && sugg is List<object> && ((List<object>)sugg).Count > 0;
                s["pending"] = Obj("id", pid, "tool", tool, "what", What(tool, inp), "t", Now(), "always", always);
                s["status"] = "waiting";
                return pid;
            }
            else if (name == "Stop")
            {
                foreach (Dictionary<string, object> x in L(s, "steps")) if (S(x, "state") == "now") x["state"] = "done";
                s["status"] = "done"; s["finished"] = Now(); s["pending"] = null; s["question"] = null;
                s["summary"] = Plain(S(ev, "last_assistant_message"));
            }
            else if (name == "SessionEnd")
            {
                D(st, "sessions").Remove(S(s, "id"));
                DropDiff(S(s, "id"));
            }
            var all = D(st, "sessions");
            double cut = Now() - Keep;
            foreach (var k in all.Keys.ToList()) { var x = all[k] as Dictionary<string, object>; if (x == null || N(x, "updated") <= cut) { all.Remove(k); DropDiff(k); } }
            return null;
        }

        // ---------------- la linea con Pulsar (named pipe) ----------------

        /// <summary>Manda una riga a Pulsar. alive=false se Pulsar è spento. wait>0: aspetta la risposta.</summary>
        public static Dictionary<string, object> Talk(Dictionary<string, object> msg, int waitSec, out bool alive)
        {
            alive = false;
            var c = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut);
            try { c.Connect(800); }
            catch { c.Dispose(); return null; }
            alive = true;
            try
            {
                var w = new StreamWriter(c, Utf8) { AutoFlush = true };
                w.WriteLine(Json().Serialize(msg));
                if (waitSec <= 0) { c.Dispose(); return null; }
                var r = new StreamReader(c, Utf8);
                var task = Task.Factory.StartNew(() => r.ReadLine());
                if (!task.Wait(waitSec * 1000)) return null;   // il processo dell'hook esce comunque subito dopo
                var line = task.Result;
                c.Dispose();
                return string.IsNullOrEmpty(line) ? null : Norm(Json().DeserializeObject(line)) as Dictionary<string, object>;
            }
            catch { return null; }
        }

        static void Ping() { bool a; Talk(Obj("op", "ping"), 0, out a); }

        static void Print(Dictionary<string, object> o)
        {
            var w = new StreamWriter(Console.OpenStandardOutput(), Utf8);
            w.Write(Json().Serialize(o));
            w.Flush();
        }

        // ---------------- l'hook: Pulsar.exe --hook [--ask] ----------------

        public static int Hook(string[] args)
        {
            if (Environment.GetEnvironmentVariable("PULSAR_ANIMA") == "1") return 0;
            try
            {
                Directory.CreateDirectory(Folder);
                string raw;
                using (var rd = new StreamReader(Console.OpenStandardInput(), Utf8)) raw = rd.ReadToEnd();
                var ev = Norm(Json().DeserializeObject(raw)) as Dictionary<string, object>;
                if (ev == null) return 0;
                if (args.Contains("--ask")) { Ask(ev); return 0; }
                RunEvent(ev);
            }
            catch (Exception e) { App.Log("hook: " + e.Message); }
            return 0;   // un hook rotto non deve mai fermare Claude
        }

        /// <summary>Un evento intero, come lo fa l'hook. Usato anche dalla prova.</summary>
        public static void RunEvent(Dictionary<string, object> ev)
        {
            var pid = Locked(st => Handle(ev, st));
            var name = S(ev, "hook_event_name");
            if (name == "UserPromptSubmit")
            {
                var extra = TakeContext();
                Ping();
                if (extra != null) Print(Obj("hookSpecificOutput", Obj("hookEventName", "UserPromptSubmit", "additionalContext", extra)));
                return;
            }
            if (pid == null) { Ping(); return; }

            bool alive;
            var data = Talk(Obj("op", "wait", "id", pid), Wait, out alive);
            var sid = S(ev, "session_id"); if (sid.Length == 0) sid = "unknown";
            Locked(st =>
            {
                var s = D(D(st, "sessions"), sid);
                var p = D(s, "pending");
                if (s != null && p != null && S(p, "id") == pid) { s["pending"] = null; s["status"] = D(s, "question") != null ? "waiting" : "working"; }
                return 0;
            });
            Ping();
            if (data == null) return;
            var b = S(data, "behavior");
            Dictionary<string, object> decision;
            if (b == "always")
            {
                decision = Obj("behavior", "allow");
                object sugg;
                if (ev.TryGetValue("permission_suggestions", out sugg) && sugg != null) decision["updatedPermissions"] = sugg;
            }
            else if (b == "allow") decision = Obj("behavior", "allow");
            else if (b == "deny") decision = Obj("behavior", "deny", "message", "Denied from Pulsar.");
            else return;
            Print(Obj("hookSpecificOutput", Obj("hookEventName", "PermissionRequest", "decision", decision)));
        }

        static void Ask(Dictionary<string, object> ev)
        {
            if (S(ev, "tool_name") != "AskUserQuestion") return;
            var items = ParseQuestions(D(ev, "tool_input"));
            if (items == null) return;
            var sid = S(ev, "session_id"); if (sid.Length == 0) sid = "unknown";
            var qid = Guid.NewGuid().ToString("N").Substring(0, 12);
            Locked(st => { var s = Session(st, ev); s["question"] = Obj("id", qid, "items", items, "t", Now()); s["status"] = "waiting"; return 0; });
            bool alive;
            var data = Talk(Obj("op", "wait", "id", qid, "kind", "ask"), WaitAsk, out alive);
            Locked(st =>
            {
                var s = D(D(st, "sessions"), sid);
                var q = D(s, "question");
                if (s != null && q != null && S(q, "id") == qid)
                {
                    s["question"] = null;
                    if (S(s, "status") == "waiting" && D(s, "pending") == null) s["status"] = "working";
                }
                return 0;
            });
            Ping();
            var answers = D(data, "answers");
            if (answers != null && answers.Count > 0)
            {
                object qs = null; var ti = D(ev, "tool_input"); if (ti != null) ti.TryGetValue("questions", out qs);
                Print(Obj("hookSpecificOutput", Obj("hookEventName", "PreToolUse", "permissionDecision", "allow",
                    "updatedInput", Obj("questions", qs, "answers", answers))));
            }
        }

        /// <summary>File trascinati sul notch per Claude (al massimo 30 minuti fa): contesto della prossima richiesta.</summary>
        static string TakeContext()
        {
            try
            {
                if (!File.Exists(ContextPath)) return null;
                var d = Norm(Json().DeserializeObject(File.ReadAllText(ContextPath, Utf8))) as Dictionary<string, object>;
                File.Delete(ContextPath);
                var paths = (L(d, "paths") ?? new List<object>()).Select(x => Convert.ToString(x)).Where(x => x.Length > 0).ToList();
                if (paths.Count == 0 || Now() - N(d, "t") > 1800) return null;
                return "The user dropped these files on the Pulsar notch as context for this request. Read them if they help:\n" + string.Join("\n", paths.Select(p => "- " + p));
            }
            catch { return null; }
        }

        public static void GiveToClaude(IEnumerable<string> paths)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                File.WriteAllText(ContextPath, Json().Serialize(Obj("paths", paths.Cast<object>().ToList(), "t", Now())), Utf8);
            }
            catch { }
        }

        // ---------------- collegare gli hook a Claude Code ----------------

        static readonly string[] Events = { "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Stop", "SessionEnd" };

        public static bool HooksConnected(string settingsText) { return settingsText != null && settingsText.Contains("--hook"); }

        /// <summary>Aggiunge le voci di Pulsar ai "hooks" che ci sono già, senza toglierne nessuna.</summary>
        public static void AddHooks(Dictionary<string, object> root, string exe)
        {
            var cmd = "\"" + exe.Replace("\\", "/") + "\" --hook";
            var hooks = D(root, "hooks");
            if (hooks == null) { hooks = new Dictionary<string, object>(); root["hooks"] = hooks; }
            foreach (var e in Events)
            {
                var list = L(hooks, e);
                if (list == null) { list = new List<object>(); hooks[e] = list; }
                bool has = Json().Serialize(list).Contains("--hook");
                if (has) continue;
                int timeout = e == "PermissionRequest" ? 40 : 5;
                list.Add(Obj("hooks", new List<object> { Obj("type", "command", "command", cmd, "timeout", timeout) }));
                if (e == "PreToolUse")
                    list.Add(Obj("matcher", "AskUserQuestion", "hooks", new List<object> { Obj("type", "command", "command", cmd + " --ask", "timeout", 120) }));
            }
        }

        // ---------------- prova: una sessione intera, senza Claude Code ----------------

        /// <summary>Pulsar.exe --prova: rimette in scena una sessione con passi, un permesso, una domanda, modifiche e fine.</summary>
        public static int Rehearsal()
        {
            var sid = "prova-" + DateTime.Now.ToString("HHmmss");
            var cwd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Desktop", "Pulsar", "demo-progetto");
            Func<string, Dictionary<string, object>> ev = n => Obj("hook_event_name", n, "session_id", sid, "cwd", cwd);
            Action<int> pause = ms => Thread.Sleep(ms);

            var e = ev("UserPromptSubmit"); e["prompt"] = "Add a dark mode toggle to the settings page"; RunEvent(e); pause(1500);
            Step(ev, "Read", Obj("file_path", cwd + "\\src\\settings.tsx"), Obj("file", Obj("totalLines", 64.0)), false); pause(1400);
            Step(ev, "Grep", Obj("pattern", "useTheme"), null, false); pause(1200);
            var patch = Obj("structuredPatch", new List<object> { Obj("newStart", 12.0, "lines", new List<object> { " const [dark, setDark] = useState(false)", "+const toggle = () => setDark(d => !d)", "+<Switch checked={dark} onChange={toggle} />", "-<p>Theme</p>" }) });
            Step(ev, "Edit", Obj("file_path", cwd + "\\src\\settings.tsx"), patch, false); pause(1400);

            // permesso: aspetta la risposta dal notch (Allow, Deny o Always)
            var pr = ev("PermissionRequest"); pr["tool_name"] = "Bash"; pr["tool_input"] = Obj("command", "npm run test -- settings");
            pr["permission_suggestions"] = new List<object> { Obj("type", "addRules", "rules", new List<object> { Obj("toolName", "Bash", "ruleContent", "npm run test:*") }) };
            RunEvent(pr); pause(600);
            Step(ev, "Bash", Obj("command", "npm run test -- settings", "description", "Run the settings tests"), null, false); pause(1500);

            // domanda con scelte
            var q = ev("PreToolUse"); q["tool_name"] = "AskUserQuestion"; q["tool_use_id"] = Guid.NewGuid().ToString("N");
            q["tool_input"] = Obj("questions", new List<object> { Obj("question", "Where should the toggle go?", "header", "Placement", "multiSelect", false,
                "options", new List<object> { Obj("label", "Top of the page", "description", ""), Obj("label", "Next to Language", "description", "") }) });
            Ask(q); pause(800);

            var patch2 = Obj("structuredPatch", new List<object> { Obj("newStart", 3.0, "lines", new List<object> { "+:root.dark { --bg: #1D1F29 }", "+:root.dark { --text: #EDEFF6 }" }) });
            Step(ev, "Edit", Obj("file_path", cwd + "\\src\\theme.css"), patch2, false); pause(1300);
            var stop = ev("Stop"); stop["last_assistant_message"] = "Dark mode toggle added to Settings. It remembers the choice and the tests pass."; RunEvent(stop);
            return 0;
        }

        static void Step(Func<string, Dictionary<string, object>> ev, string tool, Dictionary<string, object> inp, Dictionary<string, object> resp, bool fail)
        {
            var id = Guid.NewGuid().ToString("N");
            var pre = ev("PreToolUse"); pre["tool_name"] = tool; pre["tool_input"] = inp; pre["tool_use_id"] = id; RunEvent(pre);
            Thread.Sleep(900);
            var post = ev(fail ? "PostToolUseFailure" : "PostToolUse"); post["tool_name"] = tool; post["tool_input"] = inp; post["tool_use_id"] = id;
            if (resp != null) post["tool_response"] = resp;
            RunEvent(post);
        }
    }

    /// <summary>Il lato di Pulsar della linea: accetta "ping" e tiene in sospeso i "wait" finché si risponde dal notch.</summary>
    class AgentLine
    {
        public event Action Changed;   // qualsiasi filo
        readonly Dictionary<string, StreamWriter> waiting = new Dictionary<string, StreamWriter>();
        readonly Dictionary<string, NamedPipeServerStream> pipes = new Dictionary<string, NamedPipeServerStream>();
        readonly object gate = new object();

        public void Start()
        {
            var th = new Thread(Loop) { IsBackground = true, Name = "PulsarAgentLine" };
            th.Start();
        }

        void Loop()
        {
            while (true)
            {
                NamedPipeServerStream s = null;
                try
                {
                    var sec = new PipeSecurity();
                    sec.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
                    s = new NamedPipeServerStream(Agent.PipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Byte, PipeOptions.None, 4096, 4096, sec);
                    s.WaitForConnection();
                    var conn = s;
                    ThreadPool.QueueUserWorkItem(_ => Serve(conn));
                }
                catch (Exception e)
                {
                    App.Log("agent line: " + e.Message);
                    if (s != null) s.Dispose();
                    Thread.Sleep(1000);
                }
            }
        }

        void Serve(NamedPipeServerStream s)
        {
            try
            {
                var r = new StreamReader(s, new UTF8Encoding(false));
                var line = r.ReadLine();
                var msg = string.IsNullOrEmpty(line) ? null : Agent.Norm(Agent.Json().DeserializeObject(line)) as Dictionary<string, object>;
                var op = Agent.S(msg, "op");
                if (op == "wait")
                {
                    var id = Agent.S(msg, "id");
                    lock (gate) { waiting[id] = new StreamWriter(s, new UTF8Encoding(false)) { AutoFlush = true }; pipes[id] = s; }
                    Fire();
                    return;   // resta aperta finché si risponde
                }
                s.Dispose();
                Fire();
            }
            catch { try { s.Dispose(); } catch { } }
        }

        void Fire() { var h = Changed; if (h != null) h(); }

        public bool IsWaiting(string id) { lock (gate) return waiting.ContainsKey(id); }

        /// <summary>Risponde a un permesso ({"behavior": "allow"|"deny"|"always"}) o a una domanda ({"answers": {...}}).</summary>
        public bool Answer(string id, Dictionary<string, object> data)
        {
            StreamWriter w; NamedPipeServerStream p;
            lock (gate)
            {
                if (!waiting.TryGetValue(id, out w)) return false;
                p = pipes[id];
                waiting.Remove(id); pipes.Remove(id);
            }
            try { w.WriteLine(Agent.Json().Serialize(data)); p.WaitForPipeDrain(); } catch { }
            try { p.Dispose(); } catch { }
            return true;
        }
    }
}
