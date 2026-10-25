#!/usr/bin/env python3
"""Pulsar Agente: hook di Claude Code.

Claude Code lo chiama a ogni evento (domanda, strumento, permesso, fine) e gli passa un JSON su stdin.
Lo script tiene lo stato di ogni sessione in state.json, che Pulsar legge per disegnare
la pillola nel notch e il pannello laterale. Solo libreria standard, niente rete.

Dal 17/10/2026 parla con Pulsar su un socket Unix (pulsar.sock), come coucou: dopo ogni evento
gli dice "ricarica" (niente più attese di 0,35 s) e per permessi e domande resta in linea finché
l'autore risponde dal notch. Se il socket non risponde Pulsar è spento: si esce subito e Claude Code
chiede nel terminale come sempre. Claude Code non resta mai bloccato.

`hook.py --ask` è l'hook dedicato alle domande di Claude (AskUserQuestion, PreToolUse): le scelte
compaiono nel notch e la risposta torna a Claude come se l'avesse data nel terminale.
"""
import fcntl
import json
import os
import re
import socket
import sys
import time
import uuid

# La cartella dell'hook è quella in cui vive: <dati>/agente (Pulsar lo ricopia lì a ogni avvio),
# così ogni build (l'autore, vendita) parla con la sua Pulsar e non con un'altra.
DATA = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(DATA, "state.json")
LOCK = os.path.join(DATA, ".lock")
SOCK = os.path.join(DATA, "pulsar.sock")
CONTEXT = os.path.join(DATA, "contesto.json")   # file trascinati sul notch per la prossima richiesta
DIFFS = os.path.join(DATA, "diffs")             # una modifica intera per file, per il diff al tocco
INBOX = os.path.join(DATA, "messaggi")          # 17/10: messaggi scritti dal pannello, un file per messaggio in messaggi/<sessione>/
WAIT = 25          # secondi di attesa per la risposta a un permesso
WAIT_ASK = 90      # secondi di attesa per la risposta a una domanda (hook con timeout 120)
KEEP = 6 * 3600    # le sessioni ferme da più di 6 ore escono dallo stato
MAX_STEPS = 40
MAX_DIFF_LINES = 4000

TEST_RE = re.compile(
    r"\b(pytest|jest|vitest|mocha|rspec|unittest|xcodebuild test|swift test|go test|cargo test|"
    r"(npm|pnpm|yarn|bun)( run)? test|make test)\b"
)


def now():
    return time.time()


def short(text, n=60):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"


def base(path):
    return os.path.basename(str(path or "").rstrip("/")) or str(path or "")


def describe(tool, inp):
    """Strumento + input -> (TIPO, etichetta in parole semplici)."""
    inp = inp or {}
    if tool == "Read":
        return "READ", base(inp.get("file_path"))
    if tool in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
        return "EDIT", base(inp.get("file_path") or inp.get("notebook_path"))
    if tool == "Bash":
        return "RUN", short(inp.get("description") or inp.get("command"), 56)
    if tool in ("Grep", "Glob"):
        return "FIND", short(inp.get("pattern"), 40)
    if tool in ("WebFetch", "WebSearch"):
        return "WEB", short(inp.get("query") or inp.get("url"), 48)
    if tool in ("Task", "Agent"):
        return "AGENT", short(inp.get("description") or "Helper", 48)
    if tool == "TodoWrite":
        return "PLAN", "Updating the plan"
    if tool == "AskUserQuestion":
        return "ASK", "Asking you"
    if tool.startswith("mcp__"):
        parts = tool.split("__")
        return "TOOL", short(parts[-1].replace("_", " "), 48)
    return "TOOL", short(tool, 48)


def what(tool, inp):
    """Cosa chiede di fare, per la card di approvazione."""
    inp = inp or {}
    if tool == "Bash":
        return short(inp.get("command"), 160)
    if inp.get("file_path"):
        return f"{tool} {base(inp['file_path'])}"
    if inp.get("url"):
        return f"{tool} {short(inp['url'], 120)}"
    return tool


def patch_lines(tool, inp, resp):
    """Le righe della modifica (+ aggiunte, - tolte, riga senza segno = contesto), dal risultato di Claude Code."""
    out = []
    if isinstance(resp, dict):
        for h in resp.get("structuredPatch") or []:
            start = h.get("newStart") or h.get("oldStart") or 0
            out.append(f"@@ {start}")
            out.extend(str(l) for l in h.get("lines", []))
        if not out and tool == "Write":
            content = resp.get("content") or (inp or {}).get("content") or ""
            out = ["@@ 1"] + ["+" + l for l in str(content).split("\n")]
    return out


def counts(lines):
    add = sum(1 for l in lines if l.startswith("+"))
    rem = sum(1 for l in lines if l.startswith("-"))
    return add, rem


def detail(tool, resp, lines):
    """Dettaglio breve dal risultato: righe lette, righe cambiate."""
    try:
        if tool == "Read" and isinstance(resp, dict):
            f = resp.get("file") or {}
            n = f.get("totalLines") or f.get("numLines")
            return f"{n} lines" if n else ""
        if tool in ("Edit", "MultiEdit", "Write"):
            add, rem = counts(lines)
            if add or rem:
                return f"+{add} −{rem}"
    except Exception:
        pass
    return ""


def diff_path(sid):
    return os.path.join(DIFFS, re.sub(r"[^A-Za-z0-9_-]", "_", sid) + ".json")


def save_diff(sid, path, lines):
    """Accoda la modifica al file dei diff della sessione: {percorso: [righe...]}."""
    if not lines:
        return
    os.makedirs(DIFFS, exist_ok=True)
    p = diff_path(sid)
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        d = {}
    cur = d.get(path, [])
    cur.extend(lines)
    d[path] = cur[-MAX_DIFF_LINES:]
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, ensure_ascii=False)
    os.replace(tmp, p)


def drop_diff(sid):
    try:
        os.remove(diff_path(sid))
    except OSError:
        pass


def clean_prompt(text):
    """Le attività programmate arrivano come <scheduled-task name="x" ...>: diventano "Scheduled: x"."""
    t = str(text or "")
    m = re.search(r'<scheduled-task[^>]*name="([^"]+)"', t)
    if m:
        return "Scheduled: " + m.group(1)
    t = re.sub(r"<[^>]+>", " ", t)               # altri tag di sistema
    return short(t, 220)


def plain(md):
    """Ultimo messaggio di Claude -> due paragrafi puliti, senza markdown."""
    t = str(md or "")
    t = re.sub(r"```.*?```", "", t, flags=re.S)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    t = re.sub(r"[*_`#>]+", "", t)
    t = re.sub(r"^\s*[-•]\s*", "", t, flags=re.M)
    paras = [" ".join(p.split()) for p in t.split("\n\n") if p.strip()]
    out = " ".join(paras[:2])
    return out if len(out) <= 420 else out[:419].rsplit(" ", 1)[0] + "…"


def parse_questions(inp):
    """Le domande di AskUserQuestion, controllate: 1-4 domande, 2-4 scelte ciascuna. None se fuori forma."""
    qs = (inp or {}).get("questions")
    if not isinstance(qs, list) or not 1 <= len(qs) <= 4:
        return None
    out = []
    for q in qs:
        if not isinstance(q, dict) or not q.get("question"):
            return None
        opts = q.get("options")
        if not isinstance(opts, list) or not 2 <= len(opts) <= 4:
            return None
        clean = []
        for o in opts:
            if not isinstance(o, dict) or not o.get("label"):
                return None
            clean.append({"label": str(o["label"]), "description": str(o.get("description") or "")})
        out.append({"question": str(q["question"]), "header": str(q.get("header") or "")[:12],
                    "multi": bool(q.get("multiSelect")), "options": clean})
    return out


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {"sessions": {}}


def save(state):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, ensure_ascii=False)
    os.replace(tmp, STATE)


def session(state, ev):
    sid = ev.get("session_id") or "unknown"
    s = state["sessions"].get(sid)
    if s is None:
        cwd = ev.get("cwd") or ""
        s = {"id": sid, "cwd": cwd, "project": base(cwd), "agent": "Claude",
             "prompt": "", "started": now(), "status": "idle", "steps": [],
             "pending": None, "question": None, "summary": "", "finished": 0, "tests_at": 0,
             "tests_ok": None, "stale": [], "files": [], "changes": {}, "fails": {}}
        state["sessions"][sid] = s
    s.setdefault("changes", {})
    s.setdefault("question", None)
    s["updated"] = now()
    return s


def step_for(s, tid):
    for st in reversed(s["steps"]):
        if st.get("id") == tid:
            return st
    return None


TITLE_RE = re.compile(r'"customTitle":"((?:[^"\\]|\\.)*)"')


def chat_title(path):
    """17/10: il titolo della chat (quello nella barra laterale dell'app di Claude), dall'ultima riga
    custom-title del registro della sessione. Legge solo la coda del file; "" se non c'è."""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            for back in (262144, size):
                f.seek(max(0, size - back))
                hits = TITLE_RE.findall(f.read().decode("utf-8", "ignore"))
                if hits:
                    return short(json.loads('"' + hits[-1] + '"'), 48)
                if back >= size:
                    break
    except Exception:
        pass
    return ""


def handle(ev, state):
    name = ev.get("hook_event_name")
    s = session(state, ev)
    tool = ev.get("tool_name") or ""
    inp = ev.get("tool_input") or {}
    tid = ev.get("tool_use_id") or str(uuid.uuid4())

    if name == "UserPromptSubmit" or not s.get("title"):
        t = chat_title(ev.get("transcript_path") or "")
        if t:
            s["title"] = t

    if name == "UserPromptSubmit":
        raw = str(ev.get("prompt") or "")
        # 17/10: le notifiche dei lavori in background e i messaggi fra sessioni non sono domande dell'autore
        # 25/10: anche quelli che arrivano dall'app Claude senza tag ("Linked sessions now...", "The session \"x\" ... finished")
        if raw.lstrip().startswith(("<task-notification", "<cross-session-message", "[Subagent hand-back]",
                                    "Linked sessions now", "The session \"", "Another Claude session")):
            prompt = s.get("prompt") or "Background task finished"
        else:
            prompt = clean_prompt(raw)
        s.update(prompt=prompt, started=now(), status="working",
                 steps=[], summary="", finished=0, pending=None, question=None, stale=[], files=[],
                 changes={}, fails={}, tests_ok=None, tests_at=0)
        drop_diff(s["id"])

    elif name == "PreToolUse":
        kind, label = describe(tool, inp)
        for st in s["steps"]:
            if st["state"] == "now" and kind != "AGENT":
                st["state"] = "done"
        s["steps"].append({"id": tid, "kind": kind, "label": label, "state": "now",
                           "t": now(), "note": "", "cmd": inp.get("command", "") if tool == "Bash" else ""})
        s["steps"] = s["steps"][-MAX_STEPS:]
        if s["status"] != "waiting":
            s["status"] = "working"

    elif name in ("PostToolUse", "PostToolUseFailure"):
        st = step_for(s, tid)
        failed = name == "PostToolUseFailure"
        resp = ev.get("tool_response")
        lines = patch_lines(tool, inp, resp) if tool in ("Edit", "MultiEdit", "Write") and not failed else []
        if st:
            st["state"] = "failed" if failed else "done"
            st["detail"] = detail(tool, resp, lines)
        if tool in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
            full = str(inp.get("file_path") or inp.get("notebook_path") or "")
            f = base(full)
            if f and f not in s["files"]:
                s["files"].append(f)
            if s["tests_at"] and f and f not in s["stale"]:
                s["stale"].append(f)
            if full and lines:
                add, rem = counts(lines)
                c = s["changes"].get(full) or {"name": f, "add": 0, "rem": 0}
                c["add"] += add
                c["rem"] += rem
                s["changes"][full] = c
                save_diff(s["id"], full, lines)
        if tool == "Bash":
            cmd = inp.get("command", "")
            key = short(cmd, 80)
            if failed:
                s["fails"][key] = s["fails"].get(key, 0) + 1
            elif s["fails"].get(key) and st:
                st["note"] = f"try {s['fails'][key] + 1}"
            if TEST_RE.search(cmd):
                s["tests_at"] = now()
                s["tests_ok"] = not failed
                s["stale"] = []
        if s["status"] == "waiting" and not s.get("pending") and not s.get("question"):
            s["status"] = "working"

    elif name == "PermissionRequest":
        pid = uuid.uuid4().hex[:12]
        always = bool(ev.get("permission_suggestions"))
        s["pending"] = {"id": pid, "tool": tool, "what": what(tool, inp), "t": now(), "always": always}
        s["status"] = "waiting"
        return pid

    elif name == "Stop":
        for st in s["steps"]:
            if st["state"] == "now":
                st["state"] = "done"
        s["status"] = "done"
        s["finished"] = now()
        s["pending"] = None
        s["question"] = None
        s["summary"] = plain(ev.get("last_assistant_message"))

    elif name == "SessionEnd":
        state["sessions"].pop(s["id"], None)
        drop_diff(s["id"])

    # pulizia delle sessioni vecchie
    cut = now() - KEEP
    for k in [k for k, v in state["sessions"].items() if v.get("updated", 0) <= cut]:
        state["sessions"].pop(k, None)
        drop_diff(k)
    return None


# MARK: socket con Pulsar

def talk(msg, wait=0):
    """Manda una riga a Pulsar. wait > 0: resta in linea per la risposta.
    Torna False se Pulsar è spento, None se non risponde in tempo, il dizionario se risponde."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.0)
        s.connect(SOCK)
    except OSError:
        return False
    try:
        s.sendall((json.dumps(msg) + "\n").encode())
        if not wait:
            return None
        s.settimeout(wait)
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0].strip()
        return json.loads(line) if line else None
    except Exception:
        return None
    finally:
        try:
            s.close()
        except OSError:
            pass


def locked(fn):
    with open(LOCK, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            state = load()
            out = fn(state)
            save(state)
            return out
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)


def take_messages(sid):
    """I messaggi che l'autore ha scritto dal pannello per questa sessione, in ordine; li toglie dalla coda."""
    d = os.path.join(INBOX, re.sub(r"[^A-Za-z0-9_-]", "_", sid))
    out = []
    try:
        names = sorted(n for n in os.listdir(d) if n.endswith(".txt"))
    except OSError:
        return out
    for n in names:
        p = os.path.join(d, n)
        try:
            with open(p, encoding="utf-8") as f:
                t = f.read().strip()
            os.remove(p)
        except OSError:
            continue
        if t:
            out.append(t)
    return out


def deliver(ev):
    """17/10: consegna a Claude i messaggi del pannello. Dopo uno strumento come nota da leggere subito,
    alla fine come istruzione che lo fa ripartire. Torna True se ha scritto qualcosa per Claude Code."""
    name = ev.get("hook_event_name")
    if name not in ("PostToolUse", "PostToolUseFailure", "Stop"):
        return False
    sid = ev.get("session_id") or "unknown"
    msgs = take_messages(sid)
    if not msgs:
        return False
    text = "\n".join(msgs)
    note = ("l'autore just sent you this message from Pulsar (his notch panel) while you were working. "
            "Read it now and follow it; it takes priority over your current plan:\n" + text)

    def mark(state):
        s = session(state, ev)
        for m in msgs:
            s["steps"].append({"id": uuid.uuid4().hex[:8], "kind": "MSG", "label": short(m, 56), "state": "done",
                               "t": now(), "note": "", "cmd": ""})
        s["steps"] = s["steps"][-MAX_STEPS:]
        if name == "Stop":
            s.update(status="working", finished=0, summary="")
    locked(mark)
    if name == "Stop":
        print(json.dumps({"decision": "block", "reason": note}))
    else:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": name, "additionalContext": note}}))
    return True


def take_context():
    """File trascinati sul notch (al massimo 30 minuti fa): diventano contesto della richiesta, poi si cancellano."""
    try:
        with open(CONTEXT) as f:
            d = json.load(f)
        os.remove(CONTEXT)
    except Exception:
        return None
    paths = [p for p in d.get("paths", []) if isinstance(p, str)]
    if not paths or now() - float(d.get("t", 0)) > 1800:
        return None
    listed = "\n".join(f"- {p}" for p in paths)
    return ("l'autore ha trascinato questi file sul notch di Pulsar come contesto per questa richiesta. "
            "Leggili se servono a rispondere:\n" + listed)


def ask(ev):
    """AskUserQuestion: le scelte nel notch, la risposta torna a Claude. Senza risposta decide il terminale."""
    if (ev.get("tool_name") or "") != "AskUserQuestion":
        return
    items = parse_questions(ev.get("tool_input"))
    if not items:
        return
    sid = ev.get("session_id") or "unknown"
    qid = uuid.uuid4().hex[:12]

    def put(state):
        s = session(state, ev)
        s["question"] = {"id": qid, "items": items, "t": now()}
        s["status"] = "waiting"
    locked(put)

    # "kind": "ask" (fase 5): se le scelte non si possono mostrare (Isola spenta o bloccata) Pulsar risponde subito
    # "nel terminale" e qui si esce senza attesa
    data = talk({"op": "wait", "id": qid, "kind": "ask"}, wait=WAIT_ASK)

    def clear(state):
        s = state["sessions"].get(sid)
        if s and s.get("question") and s["question"].get("id") == qid:
            s["question"] = None
            if s.get("status") == "waiting" and not s.get("pending"):
                s["status"] = "working"
    locked(clear)
    talk({"op": "ping"})

    if isinstance(data, dict) and isinstance(data.get("answers"), dict) and data["answers"]:
        questions = (ev.get("tool_input") or {}).get("questions", [])
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                                 "updatedInput": {"questions": questions, "answers": data["answers"]}}}))


def main():
    # 12/10: le domande dell'Anima (anima.swift, "cerchia e chiedi") girano su Claude Code ma non sono lavoro da mostrare
    if os.environ.get("PULSAR_ANIMA") == "1":
        return
    os.makedirs(DATA, exist_ok=True)
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return
    if "--ask" in sys.argv[1:]:
        ask(ev)
        return
    pid = locked(lambda st: handle(ev, st))

    if ev.get("hook_event_name") == "UserPromptSubmit":
        extra = take_context()
        talk({"op": "ping"})
        if extra:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": extra}}))
        return
    if not pid:
        deliver(ev)
        talk({"op": "ping"})
        return

    data = talk({"op": "wait", "id": pid}, wait=WAIT)
    sid = ev.get("session_id") or "unknown"

    def clear(state):
        s = state["sessions"].get(sid)
        if s and s.get("pending") and s["pending"].get("id") == pid:
            s["pending"] = None
            s["status"] = "waiting" if s.get("question") else "working"
    locked(clear)
    talk({"op": "ping"})

    if not isinstance(data, dict):
        return
    b = data.get("behavior")
    if b == "always":
        decision = {"behavior": "allow"}
        sugg = ev.get("permission_suggestions")
        if sugg:
            decision["updatedPermissions"] = sugg   # Claude Code salva la regola, come "Sì, non chiedere più"
    elif b in ("allow", "deny"):
        decision = {"behavior": b}
        if b == "deny":
            decision["message"] = "Denied from Pulsar."
    else:
        return
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # un hook rotto non deve mai fermare Claude
