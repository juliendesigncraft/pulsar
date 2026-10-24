// Anima (12/10/2026): le funzioni di Hitodama (otism_dev, hitodama.in) portate nell'Isola del notch.
// l'autore: "possiamo integrare quelle funzioni al mio notch?", poi "tutto quello che vedi, gli sfondi non mi servono".
// Tre gesti, tutti tenendo premuti due tasti (si attivano dopo un attimo, così ⌃⌥Y/N/L e le scorciatoie restano libere):
//   ⌃⌥  Dettatura pulita: parli come viene, lasci i tasti e nel campo dove sei arriva la frase sistemata.
//   ⌃⌘  Comando: "apri Spotify", "cerca su YouTube...", "ogni mattina alle 9 apri Spotify e Spazio",
//       "aggiungi alla lista: chiamare il commercialista". Domande semplici: risponde nell'isola.
//   ⌃⇧  Cerchia e chiedi: compare un velo, cerchi qualcosa sullo schermo e intanto fai la domanda a voce.
// Voce: riconoscimento di macOS (Speech), sul Mac quando si può. Pulizia e comandi: Ollama locale (qwen3:8b, gratis);
// cerchia e chiedi: Claude Code (vede l'immagine). Cose da fare e abitudini: anima-cose.swift.
// Niente di salvato fuori da anima/ nella cartella dati (Cartelle.dati); l'audio non si registra mai su disco.
import SwiftUI
import AppKit
import Speech
import AVFoundation

/// Registro breve in anima/anima.log nella cartella dati (Cartelle.dati): per capire dove si ferma un gesto.
func animaLog(_ s: String) {
    let f = AnimaBrain.casa.appendingPathComponent("anima.log")
    if let a = try? FileManager.default.attributesOfItem(atPath: f.path), (a[.size] as? Int ?? 0) > 200_000 { try? FileManager.default.removeItem(at: f) }
    let line = "\(Date()) \(s)\n"
    if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: f, atomically: true, encoding: .utf8) }
}

// MARK: - Fase dell'Anima (quello che l'isola mostra)

enum AnimaMode: String { case dettatura, comando, cerchia }

enum AnimaPhase: Equatable {
    case idle
    case ascolto(AnimaMode, String)          // sente: modalità e testo parziale
    case pensa(AnimaMode, String)            // ha capito, lavora
    case risposta(String, String)            // titolo, testo
}

final class Anima: ObservableObject {
    static let shared = Anima()
    @Published private(set) var phase: AnimaPhase = .idle
    @Published var level: Double = 0           // volume del microfono, per i puntini
    var onChange: (() -> Void)?

    var enabled: Bool {
        get { Impostazioni.animaAccesa }
        set { Impostazioni.set(newValue, .animaEnabled); RegistroModuli.shared.riapplica() }
    }

    private let keys = AnimaKeys()
    private let ear = AnimaEar()
    private let veil = CircleVeil()
    private var hideWork: DispatchWorkItem?
    private var mode: AnimaMode?

    /// All'avvio, sempre (anche con la Voce spenta o bloccata): crash.txt, collegamenti dei tasti e le cose da fare.
    /// Accendere i tasti lo fa il registro con `avvia()`.
    func boot() {
        // 12/10: se Pulsar si ferma di colpo, la pila delle chiamate finisce in anima/crash.txt
        signal(SIGABRT) { _ in
            let s = Thread.callStackSymbols.joined(separator: "\n")
            try? s.write(to: AnimaBrain.casa.appendingPathComponent("crash.txt"), atomically: true, encoding: .utf8)
            exit(134)
        }
        NSSetUncaughtExceptionHandler { e in
            let s = "\(e.name) \(e.reason ?? "")\n" + e.callStackSymbols.joined(separator: "\n")
            try? s.write(to: AnimaBrain.casa.appendingPathComponent("crash.txt"), atomically: true, encoding: .utf8)
        }
        keys.onBegin = { [weak self] m in self?.begin(m) }
        keys.onEnd = { [weak self] m in self?.end(m) }
        keys.onCancel = { [weak self] in self?.cancel() }
        ear.onText = { [weak self] t in
            guard let self, case .ascolto(let m, _) = self.phase else { return }
            self.set(.ascolto(m, t))
        }
        ear.onLevel = { [weak self] l in self?.level = l }
        AnimaCose.shared.start()
    }

    private func set(_ p: AnimaPhase) {
        DispatchQueue.main.async { [self] in
            phase = p
            onChange?()
        }
    }

    // MARK: gesti

    private func begin(_ m: AnimaMode) {
        hideWork?.cancel()
        mode = m
        animaLog("inizio \(m.rawValue)")
        AnimaEar.permessi { [weak self] ok in
            animaLog("permessi \(ok)")
            guard let self, self.mode == m else { return }
            guard ok else {
                self.show(T("Serve il permesso", "Permission needed"),
                          T("Impostazioni di Sistema → Privacy: Microfono e Riconoscimento vocale per Pulsar.",
                            "System Settings → Privacy: Microphone and Speech Recognition for Pulsar."), for: 8)
                return
            }
            if m == .cerchia { self.veil.show() }
            self.set(.ascolto(m, ""))
            self.ear.start()
        }
    }

    private func end(_ m: AnimaMode) {
        guard mode == m else { return }
        mode = nil
        let area = m == .cerchia ? veil.finish() : nil
        ear.stop { [weak self] detto in self?.fine(m, detto.trimmingCharacters(in: .whitespacesAndNewlines), area) }
    }

    private func fine(_ m: AnimaMode, _ testo: String, _ area: NSRect?) {
        animaLog("fine \(m.rawValue): «\(testo)»")
        switch m {
        case .dettatura:
            guard !testo.isEmpty else { niente(); return }
            set(.pensa(m, testo))
            AnimaBrain.pulisci(testo) { [weak self] pulito in
                AnimaPaste.incolla(pulito)
                self?.set(.idle)
                PeekCenter.shared.post(PeekItem(key: "anima", kind: "info", symbol: "text.cursor", title: T("Scritto", "Typed"),
                                                detail: pulito, priority: 40, duration: 2.2))
            }
        case .comando:
            guard !testo.isEmpty else { niente(); return }
            set(.pensa(m, testo))
            AnimaBrain.comando(testo) { [weak self] r in
                let fatto = AnimaCose.shared.esegui(r.azioni)
                let msg = fatto.isEmpty ? r.risposta : fatto      // se ha agito, dice cosa ha fatto davvero
                // la voce: "Fatto" se ha agito, la risposta letta se c'è la chiave, altrimenti "non ho capito"
                if !fatto.isEmpty { AnimaVoce.frase("fatto") }
                else if r.risposta.isEmpty { AnimaVoce.frase("ripeti") }
                else { _ = AnimaVoce.leggi(r.risposta) }
                self?.show(testo, msg.isEmpty ? T("Non ho capito cosa fare.", "I didn't get what to do.") : msg,
                           for: r.risposta.count > 80 ? 14 : 6)
            }
        case .cerchia:
            guard let area else { set(.idle); return }
            set(.pensa(m, testo.isEmpty ? T("Cosa c'è qui?", "What's this?") : testo))
            AnimaVoce.frase("guardo")
            CircleVeil.cattura(area) { [weak self] file in
                guard let file else {
                    self?.show(T("Non riesco a vedere lo schermo", "Can't see the screen"),
                               T("Impostazioni di Sistema → Privacy → Registrazione schermo: accendi Pulsar.",
                                 "System Settings → Privacy → Screen Recording: turn on Pulsar."), for: 8)
                    return
                }
                AnimaBrain.chiedi(immagine: file, domanda: testo) { risposta in
                    _ = AnimaVoce.leggi(risposta)
                    self?.show(testo.isEmpty ? T("Cosa c'è qui?", "What's this?") : testo, risposta, for: 25)
                }
            }
        }
    }

    /// Clic sulla stella (12/10 notte, l'autore: "l'icona per parlare non registra, dice solo Ciao l'autore"):
    /// il primo clic ascolta un comando, il secondo lo chiude. Se sta già ascoltando coi tasti, non interferisce.
    var ascoltaDaClic = false
    private var silenzioDal: Date?
    private var clicTimer: Timer?
    func clicStella() {
        if ascoltaDaClic { fermaClic(); return }
        guard mode == nil else { return }
        ascoltaDaClic = true
        silenzioDal = nil
        begin(.comando)
        let inizio = Date()
        // si chiude da solo: 1,5 s di silenzio dopo aver detto qualcosa, o 15 s in tutto
        clicTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.ascoltaDaClic else { return }
            if Date().timeIntervalSince(inizio) > 15 { self.fermaClic(); return }
            guard case .ascolto(_, let testo) = self.phase, !testo.isEmpty else { return }
            if self.level < 0.06 { if self.silenzioDal == nil { self.silenzioDal = Date() } } else { self.silenzioDal = nil }
            if let s = self.silenzioDal, Date().timeIntervalSince(s) > 1.5 { self.fermaClic() }
        }
    }
    private func fermaClic() {
        clicTimer?.invalidate(); clicTimer = nil
        ascoltaDaClic = false
        end(.comando)
    }

    /// Prove senza microfono: pulsar://anima?modo=comando|dettatura|cerchia&testo=... (cerchia guarda il centro dello schermo).
    func prova(_ m: AnimaMode, _ testo: String) {
        var area: NSRect?
        if m == .cerchia, let f = NSScreen.main?.frame { area = NSRect(x: f.midX - 300, y: f.midY - 200, width: 600, height: 400) }
        set(.ascolto(m, testo))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.fine(m, testo, area) }
    }

    /// Il gesto è finito senza parole: lo dice, invece di non fare niente in silenzio.
    private func niente() {
        set(.idle)
        PeekCenter.shared.post(PeekItem(key: "anima", kind: "info", symbol: "mic.slash", title: T("Non ho sentito niente", "I didn't hear anything"),
                                        detail: "", priority: 40, duration: 2))
    }

    private func cancel() {
        mode = nil
        ear.stop { _ in }
        _ = veil.finish()
        set(.idle)
    }

    /// Mostra una risposta nell'isola e la ritira da sola.
    func show(_ titolo: String, _ testo: String, for secondi: Double) {
        set(.risposta(titolo, testo))
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.set(.idle) }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + secondi, execute: w)
    }
    func chiudi() { hideWork?.cancel(); set(.idle) }
}

// MARK: - I tasti: due modificatori tenuti premuti da soli

final class AnimaKeys {
    var onBegin: ((AnimaMode) -> Void)?
    var onEnd: ((AnimaMode) -> Void)?
    var onCancel: (() -> Void)?
    private var monitors: [Any] = []
    private var pending: DispatchWorkItem?
    private var active: AnimaMode?
    static let hold = 0.35            // quanto tenerli prima che parta: sotto, è una scorciatoia normale

    func start() {
        guard monitors.isEmpty else { return }
        let flags: (NSEvent) -> Void = { [weak self] e in self?.flags(e.modifierFlags) }
        let key: (NSEvent) -> Void = { [weak self] _ in self?.keyPressed() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: key) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0); return $0 }) { monitors.append(m) }
    }
    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        pending?.cancel(); pending = nil
        if active != nil { active = nil; onCancel?() }
    }

    static func mode(for f: NSEvent.ModifierFlags) -> AnimaMode? {
        let m = f.intersection([.control, .option, .command, .shift])
        if m == [.control, .option] { return .dettatura }
        if m == [.control, .command] { return .comando }
        if m == [.control, .shift] { return .cerchia }
        return nil
    }

    private func flags(_ f: NSEvent.ModifierFlags) {
        let m = Self.mode(for: f)
        if m != nil || active != nil { animaLog("tasti \(f.rawValue) -> \(m?.rawValue ?? "-")") }
        if let a = active {
            if m != a { active = nil; onEnd?(a) }      // lasciati i tasti: fine del gesto
            return
        }
        if pending != nil { animaLog("annullato da modificatori \(f.rawValue)") }
        pending?.cancel(); pending = nil
        guard let m else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.active = m
            self.onBegin?(m)
        }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold, execute: w)
    }

    /// Un tasto vero premuto mentre si aspetta: era una scorciatoia (⌃⌥Y, ⌃⌘Q...), non un gesto.
    private func keyPressed() {
        if pending != nil { animaLog("annullato da un tasto") }
        pending?.cancel(); pending = nil
    }
}

// MARK: - L'orecchio: riconoscimento vocale di macOS

final class AnimaEar {
    var onText: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    private let q = DispatchQueue(label: "pulsar.anima.ear")   // mai l'audio sul filo principale (lezione dell'11/10)
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var text = ""
    private let lock = NSLock()
    var picco = 0.0          // il volume più alto sentito nel gesto (per il registro)

    /// Fase 5: nella vendita la lingua del Mac, nella build dell'autore l'italiano (Impostazioni.linguaVoce).
    static var lingua: String { Impostazioni.linguaVoce }

    static func permessi(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { s in
            guard s == .authorized else { DispatchQueue.main.async { done(false) }; return }
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
        }
    }

    func start() {
        lock.lock(); text = ""; lock.unlock()
        picco = 0
        q.async { [self] in
            // una lingua del Mac che il riconoscimento non conosce: si ripiega sull'inglese americano
            guard let rec = SFSpeechRecognizer(locale: Locale(identifier: Self.lingua)) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), rec.isAvailable else { animaLog("riconoscitore non disponibile"); return }
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            // 12/10: obbligare il riconoscimento sul Mac dava testo vuoto (modello italiano locale assente):
            // macOS sceglie da sé, sul Mac se può, altrimenti col servizio di Apple
            req.requiresOnDeviceRecognition = Impostazioni.bool(.animaSoloMac)
            req.addsPunctuation = true
            let eng = AVAudioEngine()
            let input = eng.inputNode
            let fmt = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                req.append(buf)
                guard let ch = buf.floatChannelData?[0] else { return }
                var sum: Float = 0
                let n = Int(buf.frameLength)
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                let l = min(1, max(0, Double(rms) * 12))
                if l > (self?.picco ?? 1) { self?.picco = l }
                DispatchQueue.main.async { self?.onLevel?(l) }
            }
            do { eng.prepare(); try eng.start() } catch { animaLog("microfono: \(error)"); return }
            animaLog("ascolto partito, on-device \(req.requiresOnDeviceRecognition), formato \(fmt), ingresso \(AVCaptureDevice.default(for: .audio)?.localizedName ?? "?")")
            engine = eng; request = req
            task = rec.recognitionTask(with: req) { [weak self] r, err in
                if let err { animaLog("riconoscimento: \(err.localizedDescription)") }
                guard let self, let r else { return }
                let s = r.bestTranscription.formattedString
                self.lock.lock(); self.text = s; self.lock.unlock()
                DispatchQueue.main.async { self.onText?(s) }
            }
        }
    }

    /// Ferma e passa quanto sentito, dopo un attimo per l'ultima parola. Tutto fuori dal filo principale.
    func stop(_ done: @escaping (String) -> Void) {
        q.async { [self] in
            request?.endAudio()
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            q.asyncAfter(deadline: .now() + 0.35) { [self] in
                task?.finish(); task = nil; request = nil; engine = nil
                lock.lock(); let t = text; lock.unlock()
                animaLog("picco voce \(String(format: "%.3f", picco))")
                DispatchQueue.main.async { self.onLevel?(0); done(t) }
            }
        }
    }
}

// MARK: - Incollare nel campo dove si è

enum AnimaPaste {
    /// Mette il testo negli appunti, preme ⌘V e rimette gli appunti di prima.
    static func incolla(_ s: String) {
        let pb = NSPasteboard.general
        let prima = pb.pasteboardItems?.map { item -> NSPasteboardItem in
            let copia = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copia.setData(d, forType: t) } }
            return copia
        } ?? []
        pb.clearContents()
        pb.setString(s, forType: .string)
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)   // V
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !prima.isEmpty else { return }
            pb.clearContents()
            pb.writeObjects(prima)
        }
    }
}

// MARK: - Il cervello: Ollama per il veloce, Claude per guardare

struct AnimaRisposta {
    var risposta = ""
    var azioni: [[String: Any]] = []
}

enum AnimaBrain {
    static let ollama = URL(string: "http://127.0.0.1:11434/api/generate")!
    static var modello: String { Impostazioni.string(.animaModello) ?? "qwen3:8b" }
    static let casa: URL = {
        let u = Cartelle.dati.appendingPathComponent("anima")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    private static func genera(_ prompt: String, json: Bool, _ done: @escaping (String?) -> Void) {
        var req = URLRequest(url: ollama, timeoutInterval: 40)
        req.httpMethod = "POST"
        var body: [String: Any] = ["model": modello, "prompt": prompt, "stream": false, "think": false,
                                   "options": ["temperature": 0.2]]
        if json { body["format"] = "json" }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { d, _, _ in
            let r = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["response"] as? String
            DispatchQueue.main.async { done(r.map(pulisciRisposta)) }
        }.resume()
    }

    /// qwen3 a volte lascia il ragionamento fra <think>: via.
    private static func pulisciRisposta(_ s: String) -> String {
        var s = s
        if let r = s.range(of: "</think>") { s = String(s[r.upperBound...]) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dettatura: toglie esitazioni e false partenze, tiene la correzione finale, non aggiunge niente.
    static func pulisci(_ testo: String, _ done: @escaping (String) -> Void) {
        let p = """
        Riscrivi questa dettatura come testo pulito, nella stessa lingua. Togli esitazioni (ehm, uh, cioè), ripetizioni e \
        false partenze; se chi parla si corregge ("alle nove, no, alle dieci") tieni solo la versione corretta. \
        Punteggiatura e maiuscole giuste. Non aggiungere, non riassumere, non rispondere: restituisci solo il testo.

        Dettatura: \(testo)
        """
        genera(p, json: false) { r in
            let ok = (r ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\"“” \n"))
            done(ok.isEmpty ? testo : ok)
        }
    }

    /// Gli esempi di app poco note nel prompt dei comandi: nella build dell'autore anche le sue.
    private static var appPocoNote: String {
        return "Pulsar, Figma..."
    }

    /// Comando: il modello sceglie fra azioni fisse (niente comandi liberi della shell).
    static func comando(_ testo: String, _ done: @escaping (AnimaRisposta) -> Void) {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let p = """
        Sei l'assistente vocale nel notch di un Mac. Adesso è \(f.string(from: Date())) (\(iso.string(from: Date()))).
        Trasforma la richiesta in JSON: {"risposta": "frase breve per l'utente", "azioni": [...]}.
        Azioni possibili (solo queste):
        {"tipo":"apri_app","nome":"Spotify"}
        {"tipo":"apri_url","url":"https://..."}
        {"tipo":"cerca","dove":"youtube|google|amazon|spotify|maps","testo":"..."}
        {"tipo":"todo","testo":"..."}
        {"tipo":"promemoria","testo":"...","quando":"AAAA-MM-GGTHH:MM"}
        {"tipo":"programma","quando":"AAAA-MM-GGTHH:MM","azioni":[...]}   (una volta)
        {"tipo":"routine","ora":"HH:MM","giorni":"tutti|feriali|weekend","azioni":[...]}   (ogni giorno)
        {"tipo":"timer","minuti":10}
        Se nomina più app o più cose, un'azione per ciascuna (anche app poco note: \(appPocoNote)).
        Se è una domanda e non serve agire, azioni vuote e la risposta in "risposta" (breve, massimo 3 frasi).
        Rispondi nella lingua della richiesta. Solo JSON.

        Richiesta: \(testo)
        """
        genera(p, json: true) { r in
            guard let r, let d = r.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                done(AnimaRisposta(risposta: r == nil ? T("Ollama è spento o manca il modello \(modello): aprilo per i comandi a voce.", "Ollama is off or the \(modello) model is missing: open it for voice commands.") : "", azioni: []))
                return
            }
            done(AnimaRisposta(risposta: o["risposta"] as? String ?? "", azioni: o["azioni"] as? [[String: Any]] ?? []))
        }
    }

    /// Cerchia e chiedi: Claude Code guarda il ritaglio. Gira in una cartella sua, senza i CLAUDE.md del lavoro,
    /// solo con lo strumento Read, e l'hook di Pulsar lo ignora (PULSAR_ANIMA=1).
    static func chiedi(immagine: URL, domanda: String, _ done: @escaping (String) -> Void) {
        let q = domanda.isEmpty ? T("Cos'è questo? Spiegalo in breve.", "What is this? Explain briefly.") : domanda
        let prompt = """
        Guarda l'immagine \(immagine.path) (il ritaglio della zona di schermo che l'utente ha cerchiato; il cerchio non è disegnato nell'immagine) e rispondi alla domanda. \
        Risposta breve e concreta, testo semplice senza markdown, nella lingua della domanda.

        Domanda: \(q)
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let bin = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
                       "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
                .first { FileManager.default.isExecutableFile(atPath: $0) }
            guard let bin else {
                DispatchQueue.main.async { done(T("Claude Code non è installato.", "Claude Code isn't installed.")) }
                return
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-p", prompt, "--model", "sonnet", "--allowedTools", "Read", "--output-format", "text"]
            p.currentDirectoryURL = casa
            var env = ProcessInfo.processInfo.environment
            env["PULSAR_ANIMA"] = "1"
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            do { try p.run() } catch {
                DispatchQueue.main.async { done(T("Claude non parte.", "Claude won't start.")) }
                return
            }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: killer)
            let d = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            try? FileManager.default.removeItem(at: immagine)       // il ritaglio non resta sul disco
            let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async { done(s.isEmpty ? T("Nessuna risposta.", "No answer.") : s) }
        }
    }
}

// MARK: - Il velo per cerchiare

/// Una finestra trasparente su tutto lo schermo: col mouse si disegna il cerchio, che resta finché si tengono i tasti.
final class CircleVeil {
    private var win: NSWindow?
    private var view: VeilView?

    func show() {
        guard win == nil, let s = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let w = NSPanel(contentRect: s.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let v = VeilView(frame: NSRect(origin: .zero, size: s.frame.size))
        w.contentView = v
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; w.animator().alphaValue = 1 }
        win = w; view = v
    }

    /// Chiude il velo e restituisce l'area cerchiata in coordinate dello schermo (origine in basso a sinistra).
    func finish() -> NSRect? {
        guard let w = win, let v = view else { return nil }
        let r = v.bounds(in: w)
        w.orderOut(nil)
        win = nil; view = nil
        return r
    }

    /// Fotografa l'area con screencapture (permesso Registrazione schermo), in un file temporaneo.
    static func cattura(_ r: NSRect, _ done: @escaping (URL?) -> Void) {
        guard let top = NSScreen.screens.first?.frame.maxY else { done(nil); return }
        let x = Int(r.minX), y = Int(top - r.maxY), w = Int(r.width), h = Int(r.height)
        let file = AnimaBrain.casa.appendingPathComponent("cerchio-\(Int(Date().timeIntervalSince1970)).png")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12) {   // il velo è sparito
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-R", "\(x),\(y),\(w),\(h)", file.path]
            try? p.run(); p.waitUntilExit()
            let ok = FileManager.default.fileExists(atPath: file.path)
            DispatchQueue.main.async { done(ok ? file : nil) }
        }
    }
}

private final class VeilView: NSView {
    private var punti: [NSPoint] = []
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) { punti = [convert(e.locationInWindow, from: nil)]; needsDisplay = true }
    override func mouseDragged(with e: NSEvent) { punti.append(convert(e.locationInWindow, from: nil)); needsDisplay = true }
    // con ⌃ tenuto macOS può consegnare il clic come clic destro: stesso disegno
    override func rightMouseDown(with e: NSEvent) { mouseDown(with: e) }
    override func rightMouseDragged(with e: NSEvent) { mouseDragged(with: e) }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    func bounds(in w: NSWindow) -> NSRect? {
        guard punti.count > 3 else { return nil }
        let xs = punti.map(\.x), ys = punti.map(\.y)
        let r = NSRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).insetBy(dx: -8, dy: -8)
        guard r.width > 12, r.height > 12 else { return nil }
        return w.convertToScreen(r)
    }

    override func draw(_ dirty: NSRect) {
        let chiaro = Theme.light
        // un velo appena percettibile: si capisce che si sta cerchiando, senza coprire
        (chiaro ? NSColor(white: 1, alpha: 0.10) : NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.18)).setFill()
        bounds.fill()
        guard punti.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: punti[0])
        for p in punti.dropFirst() { path.line(to: p) }
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (chiaro ? NSColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 0.9) : NSColor(white: 0.97, alpha: 0.92)).setStroke()
        path.stroke()
    }
}

// MARK: - Nell'isola

/// La fonte dell'isola: compatta mentre ascolta (puntini che seguono la voce e testo che scorre), aperta per le risposte.
final class AnimaSource: IslandSource {
    let id = "anima"
    var onChange: (() -> Void)?
    let anima: Anima
    init(anima: Anima) {
        self.anima = anima
        anima.onChange = { [weak self] in self?.onChange?() }
    }
    var isActive: Bool { anima.phase != .idle }
    var priority: Int { 95 }
    /// Si apre da sola per le risposte e per il testo di un comando; la dettatura resta compatta (non copre).
    var alert: Bool {
        switch anima.phase {
        case .risposta: return true
        case .pensa(let m, _), .ascolto(let m, _): return m != .dettatura
        case .idle: return false
        }
    }
    var usesHome: Bool { false }
    /// Quanto è alta l'isola aperta: le risposte lunghe hanno bisogno di spazio.
    var height: CGFloat {
        if case .risposta(_, let t) = anima.phase { return min(260, 96 + CGFloat(t.count / 70) * 17) }
        return 112
    }
    func compactLeading() -> AnyView { AnyView(AnimaGlyph(anima: anima).frame(width: 18, height: 18)) }
    func compactTrailing() -> AnyView { AnyView(AnimaCompactText(anima: anima)) }
    func expandedView() -> AnyView { AnyView(AnimaExpanded(anima: anima)) }
}

/// I puntini 5x5: colonne che seguono la voce mentre ascolta, la cometa dell'isola mentre pensa.
private struct AnimaGlyph: View {
    @ObservedObject var anima: Anima
    var body: some View {
        switch anima.phase {
        case .ascolto: DotGlyph(kind: .volume, level: 0.15 + anima.level * 0.85)
        case .pensa: NotchPulse(phase: .working)
        case .risposta: NotchPulse(phase: .done)
        case .idle: Color.clear
        }
    }
}

private struct AnimaCompactText: View {
    @ObservedObject var anima: Anima
    var body: some View {
        let s: String = {
            switch anima.phase {
            case .ascolto(let m, _): return m == .dettatura ? T("Detta", "Dictate") : m == .cerchia ? T("Cerchia", "Circle") : T("Dimmi", "Speak")
            case .pensa(let m, _): return m == .dettatura ? T("Scrivo", "Typing") : "…"
            default: return ""
            }
        }()
        Text(s).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.primary.opacity(0.75))
    }
}

private struct AnimaExpanded: View {
    @ObservedObject var anima: Anima
    var body: some View {
        let (titolo, testo, piccolo): (String, String, String) = {
            switch anima.phase {
            case .ascolto(let m, let t):
                let h = m == .cerchia ? T("Cerchia qualcosa e chiedi", "Circle something and ask") : T("Ti ascolto", "Listening")
                return (h, t.isEmpty ? "…" : t, m == .cerchia ? "⌃⇧" : "⌃⌘")
            case .pensa(let m, let t): return (m == .cerchia ? T("Guardo", "Looking") : T("Ci penso", "Thinking"), t, "")
            case .risposta(let a, let b): return (a, b, "")
            case .idle: return ("", "", "")
            }
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AnimaGlyph(anima: anima).frame(width: 18, height: 18)
                Text(titolo).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if !piccolo.isEmpty { Text(piccolo).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4)) }
                if case .risposta = anima.phase {
                    Button { anima.chiudi() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                Text(testo).font(.system(size: 12.5)).foregroundStyle(Color.primary.opacity(0.78))
                    .lineSpacing(2).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Registro dei moduli (fase 2): la Voce vale solo con Pulsar Complete

extension Anima: ModuloPulsar {
    var id: String { "anima" }
    var nome: String { T("Voce", "Voice") }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [.microfono, .riconoscimentoVocale, .registrazioneSchermo, .accessibilita] }
    var acceso: Bool { enabled }
    func avvia() {
        keys.start()
    }
    func ferma() { keys.stop() }                    // la scelta salvata non si tocca
}
