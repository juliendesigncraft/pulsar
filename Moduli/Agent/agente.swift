// Pulsar Agente (v1.9): segue Claude Code dal vivo. Dalla 1.9 in stile macOS nativo
// (SF Pro, SF Symbols, controlli di sistema) con gli aspetti Dark Matte (nel codice Notte, il predefinito),
// White Matte e Sfondo (Liquid Glass). Tutti nella grammatica di Kinso (06/10/2026): colonna di icone sul bordo,
// pannello alto alla sua sinistra, bottoni tondi in alto, campo arrotondato in basso.
// Pillola nel notch (cosa sta facendo adesso), linguetta sul bordo destro dello schermo che apre
// il pannello (domanda, passi, approvazione, riassunto in parole semplici).
// I dati li scrive agente/hook.py nella cartella dati (Cartelle.dati), agente/state.json;
// qui si legge e basta. Le risposte ai permessi tornano all'hook come reply-<id>.json.

import AppKit
import SwiftUI

// MARK: - Dati

struct AgentStep: Decodable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let state: String
    let note: String?
    let detail: String?     // "219 lines", "+3 −1": la riga piccola sopra la pillola
}

extension AgentSession {
    /// Se più sessioni hanno lo stesso progetto, si distinguono con le prime parole della richiesta.
    /// 17/10: il nome della chat come nella barra laterale di Claude (Pulsar, Fila...), se no la cartella.
    var name: String { (title ?? "").isEmpty ? project : title! }

    func label(among all: [AgentSession]) -> String {
        if let t = title, !t.isEmpty { return t.count > 22 ? String(t.prefix(21)) + "…" : t }
        guard all.filter({ $0.project == project }).count > 1, !prompt.isEmpty else { return project }
        let words = prompt.replacingOccurrences(of: "Scheduled: ", with: "").split(separator: " ").prefix(3).joined(separator: " ")
        return words.count > 22 ? String(words.prefix(21)) + "…" : words
    }
}

struct AgentPending: Decodable {
    let id: String
    let tool: String
    let what: String
    var always: Bool? = nil     // 17/10: Claude Code propone una regola ("non chiedere più"): c'è il tasto Sempre
}

/// 17/10, da coucou: una domanda di Claude (AskUserQuestion) con le sue scelte, da rispondere nel notch.
struct AgentQuestion: Decodable, Equatable {
    struct Option: Decodable, Equatable { let label: String; let description: String }
    struct Item: Decodable, Equatable { let question: String; let header: String; let multi: Bool; let options: [Option] }
    let id: String
    let items: [Item]
}

/// Righe aggiunte e tolte in un file durante la richiesta (cumulative), per il +N −M e il diff al tocco.
struct AgentChange: Decodable { let name: String; let add: Int; let rem: Int }

struct AgentSession: Decodable, Identifiable {
    let id: String
    let project: String
    let agent: String
    let prompt: String
    let started: Double
    let updated: Double
    let status: String
    let steps: [AgentStep]
    let pending: AgentPending?
    let summary: String
    let finished: Double
    let tests_at: Double
    let tests_ok: Bool?
    let stale: [String]
    let files: [String]
    var question: AgentQuestion? = nil
    var title: String? = nil
    var changes: [String: AgentChange]? = nil     // percorso intero -> +N −M

    /// I file cambiati con i loro conteggi, dal più toccato.
    var changeList: [(path: String, change: AgentChange)] {
        (changes ?? [:]).map { ($0.key, $0.value) }.sorted { $0.change.add + $0.change.rem > $1.change.add + $1.change.rem }
    }
}

private struct AgentState: Decodable { let sessions: [String: AgentSession] }

final class AgentStore: ObservableObject {
    static let dir = Cartelle.dati.appendingPathComponent("agente")
    private let stateURL = dir.appendingPathComponent("state.json")
    private let aliveURL = dir.appendingPathComponent("pulsar.alive")

    @Published var sessions: [AgentSession] = []
    @Published var selectedID: String?
    @Published var mode: AgentMode = AgentMode.saved
    @Published var section: AgentSection = .work     // Notte: quale icona della colonna è accesa
    @Published var panelShown = false
    private var lastStamp: Date?
    private var timer: Timer?

    /// La sessione da mostrare: quella scelta, altrimenti la più recente al lavoro, altrimenti l'ultima chiusa.
    var current: AgentSession? {
        if let id = selectedID, let s = sessions.first(where: { $0.id == id }) { return s }
        // con più sessioni insieme: prima quella che aspetta un ok, poi la partita per ultima (stabile, non salta)
        return active.first { $0.pending != nil } ?? active.max { $0.started < $1.started } ?? sessions.first
    }
    var active: [AgentSession] { sessions.filter { $0.status == "working" || $0.status == "waiting" } }

    /// 17/10: l'hook parla con Pulsar sul socket (agente/pulsar.sock). Il timer resta come rete di sicurezza.
    private let line = AgentSocket(path: dir.appendingPathComponent("pulsar.sock").path)

    func start() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: aliveURL)    // il vecchio battito: ora conta il socket
        installHook()
        line.onPing = { [weak self] in self?.tick() }
        // fase 5, 2b: le scelte delle domande stanno solo nell'Isola (Complete). Senza Isola che gira, subito al terminale.
        line.showsQuestions = {
            Registro.domandaNelNotch(isolaInEsecuzione: RegistroModuli.shared.inEsecuzione("isola"),
                                     isolaBloccata: RegistroModuli.shared.bloccato("isola"))
        }
        line.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        line.stop()            // senza socket l'hook non aspetta il notch
    }

    /// Dimostrazione (11/10): una sessione finta al posto di quelle vere, finché dura la ripresa.
    var demo: [AgentSession]? {
        didSet {
            if let demo { sessions = demo; selectedID = nil }
            else { lastStamp = nil; tick() }        // si torna alle sessioni vere
        }
    }

    private func tick() {
        checkContext()
        if demo != nil { return }
        let stamp = (try? stateURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard stamp != lastStamp else { return }
        lastStamp = stamp
        guard let data = try? Data(contentsOf: stateURL),
              let st = try? JSONDecoder().decode(AgentState.self, from: data) else { return }
        var list = Array(st.sessions.values)
        // per le registrazioni dei reel: mostra una sola sessione (defaults agentOnlySession), le altre restano private
        if let only = Impostazioni.string(.agentOnlySession) { list = list.filter { $0.id == only } }
        sessions = list.sorted { $0.updated > $1.updated }
    }

    /// Manda all'hook la risposta che sta aspettando sul socket.
    func answer(_ allow: Bool) { reply(allow ? "allow" : "deny") }
    /// Consenti e salva la regola che Claude Code propone ("non chiedere più per questo").
    func answerAlways() { reply("always") }

    private func reply(_ behavior: String) {
        guard let p = current?.pending ?? active.first(where: { $0.pending != nil })?.pending else { return }
        line.answer(p.id, ["behavior": behavior])
    }
    var hasPending: Bool { sessions.contains { $0.pending != nil } }

    // 17/10: messaggi dal pannello alla chat. Un file per messaggio in messaggi/<sessione>/; l'hook li consegna
    // a Claude dopo il prossimo strumento (o alla fine, facendolo ripartire) e li cancella.
    private func inbox(_ id: String) -> URL {
        let safe = String(id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
        return Self.dir.appendingPathComponent("messaggi").appendingPathComponent(safe)
    }
    func send(_ text: String, to id: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let d = inbox(id)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let name = String(format: "%.3f.txt", Date().timeIntervalSince1970)
        try? t.write(to: d.appendingPathComponent(name), atomically: true, encoding: .utf8)
        objectWillChange.send()
    }
    /// Messaggi scritti e non ancora letti da Claude.
    func queued(_ id: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: inbox(id).path)) ?? []).filter { $0.hasSuffix(".txt") }.count
    }

    /// La domanda di Claude in attesa (quella della sessione mostrata, se no la prima).
    var question: AgentQuestion? { current?.question ?? sessions.first { $0.question != nil }?.question }

    /// answers: testo della domanda -> scelta (stringa) o scelte (lista) nelle domande a più risposte.
    func answerQuestion(_ q: AgentQuestion, answers: [String: Any]) { line.answer(q.id, ["answers": answers]) }
    /// Lascia la domanda al terminale (o all'app di Claude).
    func questionToTerminal(_ q: AgentQuestion) { line.answer(q.id, ["behavior": "terminal"]) }

    /// File trascinati sul notch: la prossima richiesta a Claude li riceve come contesto (hook UserPromptSubmit).
    func addContext(_ urls: [URL]) {
        let url = Self.dir.appendingPathComponent("contesto.json")
        var paths: [String] = []
        if let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let old = o["paths"] as? [String], Date().timeIntervalSince1970 - ((o["t"] as? Double) ?? 0) < 1800 { paths = old }
        for u in urls where !paths.contains(u.path) { paths.append(u.path) }
        let body = try? JSONSerialization.data(withJSONObject: ["paths": Array(paths.suffix(12)), "t": Date().timeIntervalSince1970])
        try? body?.write(to: url, options: .atomic)
        contextCount = paths.count
        contextNames = paths.map { ($0 as NSString).lastPathComponent }
    }
    /// I nomi dei file in attesa di partire con il prossimo messaggio.
    var contextNames: [String] = {
        let url = AgentStore.dir.appendingPathComponent("contesto.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return ((o["paths"] as? [String]) ?? []).map { ($0 as NSString).lastPathComponent }
    }()
    /// L'hook ha preso i file (contesto.json sparito): l'isola lo dice col razzo che parte.
    var onContextTaken: (([String]) -> Void)?
    private func checkContext() {
        guard contextCount > 0 else { return }
        if !FileManager.default.fileExists(atPath: Self.dir.appendingPathComponent("contesto.json").path) {
            let names = contextNames
            contextCount = 0; contextNames = []
            onContextTaken?(names)
        }
    }
    @Published var contextCount: Int = {
        let url = AgentStore.dir.appendingPathComponent("contesto.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return 0 }
        return (o["paths"] as? [String])?.count ?? 0
    }()

    /// Una sessione viva o toccata negli ultimi 20 minuti: i file trascinati sul notch vanno a Claude, non al Vassoio.
    var acceptsContext: Bool {
        sessions.contains { $0.status == "working" || $0.status == "waiting" || Date().timeIntervalSince1970 - $0.updated < 1200 }
    }

    /// Le righe della modifica di un file nella sessione (scritte dall'hook in diffs/<sessione>.json).
    func diffLines(session: AgentSession, path: String) -> [String] {
        let safe = session.id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let url = Self.dir.appendingPathComponent("diffs/\(safe).json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: [String]] else { return [] }
        return o[path] ?? []
    }

    /// Sessione precedente o successiva, in ordine di partenza (stabile: non salta quando una si aggiorna).
    func stepSession(_ dir: Int) {
        let list = sessions.sorted { $0.started < $1.started }
        guard list.count > 1 else { return }
        let i = list.firstIndex { $0.id == current?.id } ?? 0
        selectedID = list[(i + dir + list.count) % list.count].id
    }

    /// Tiene aggiornata la copia dell'hook in Application Support (quella che chiama Claude Code).
    /// La stessa copia la fa Collega Claude Code prima di scrivere gli hook (CollegaClaude.installaHook).
    private func installHook() {
        try? CollegaClaude.installaHook(da: Bundle.main.url(forResource: "hook", withExtension: "py"), cartellaDati: Cartelle.dati)
    }

    static var hooksConnected: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let d = try? CollegaClaude.leggi(url) else { return false }   // sola lettura: qui non si scrive mai
        return CollegaClaude.collegato(d, cartellaDati: Cartelle.dati, home: FileManager.default.homeDirectoryForCurrentUser)
    }
}

/// Le sezioni della colonna di Notte, come le icone di Kinso.
enum AgentSection: String, CaseIterable {
    case work, files, approve, sessions, window   // 17/10: window = un'altra app dal vivo (agente-finestra.swift)
    case muta                                     // 19/10: le scelte di Muta (muta-viste.swift), anche senza Claude
    var symbol: String { ["work": "waveform", "files": "doc.text", "approve": "bell", "sessions": "square.stack", "window": "pip", "muta": "tray.and.arrow.down"][rawValue]! }
    var title: String { ["work": "Work", "files": "Files", "approve": "Approve", "sessions": "Sessions", "window": "Window", "muta": "Stow"][rawValue]! }
}

/// Il fondo di una superficie secondo l'aspetto. Sfondo = Liquid Glass di macOS 26.
struct AgentSurface<S: Shape>: ViewModifier {
    let mode: AgentMode
    let shape: S
    var veil: Color = .clear
    func body(content: Content) -> some View {
        switch mode {
        case .sfondo:   // 11/10: Liquid Glass col velo del colore dello sfondo dietro
            content.glassEffect(.regular.tint(veil), in: shape)
        case .notte, .bianco:
            content.background(shape.fill(Night.bottom))
        }
    }
}

extension View {
    func agentSurface<S: Shape>(_ mode: AgentMode, _ shape: S, veil: Color = .clear) -> some View { modifier(AgentSurface(mode: mode, shape: shape, veil: veil)) }
}

// MARK: - Tipi di passo: icona, colore, parole

struct StepKind {
    let symbol: String
    let tint: Color
    let doing: String      // pillola, al presente
    let done: String       // riga piccola, al passato

    static func of(_ k: String) -> StepKind {
        switch k {
        case "READ":  return StepKind(symbol: "doc.text.fill", tint: .blue, doing: "Reading", done: "Read")
        case "EDIT":  return StepKind(symbol: "pencil", tint: .orange, doing: "Editing", done: "Edited")
        case "RUN":   return StepKind(symbol: "terminal.fill", tint: Night.green, doing: "", done: "")
        case "FIND":  return StepKind(symbol: "magnifyingglass", tint: .purple, doing: "Looking for", done: "Searched")
        case "WEB":   return StepKind(symbol: "globe", tint: .teal, doing: "Searching the web", done: "Searched the web")
        case "AGENT": return StepKind(symbol: "person.2.fill", tint: .indigo, doing: "Helper:", done: "Helper:")
        case "PLAN":  return StepKind(symbol: "checklist", tint: .pink, doing: "Updating the plan", done: "Updated the plan")
        case "MSG":   return StepKind(symbol: "text.bubble.fill", tint: Night.green, doing: "", done: "You wrote:")
        default:      return StepKind(symbol: "wrench.and.screwdriver.fill", tint: .gray, doing: "", done: "")
        }
    }

    static func phrase(_ verb: String, _ st: AgentStep) -> String {
        if verb.isEmpty { return st.label }
        if st.kind == "WEB" || st.kind == "PLAN" { return verb }
        return "\(verb) \(st.label)"
    }
}

/// Le due righe della pillola, come nel riferimento: cosa ha appena fatto (piccola) e cosa fa adesso.
struct PillText {
    let small: String
    let detail: String
    let main: String
    let palette: [Color]

    static func of(_ s: AgentSession) -> PillText {
        let last = s.steps.last { $0.state != "now" }
        let small = last.map { StepKind.phrase(StepKind.of($0.kind).done, $0) } ?? s.prompt
        let detail = last?.detail ?? ""
        if s.pending != nil {
            return PillText(small: s.pending!.what, detail: "", main: "Needs your OK", palette: [.yellow, .orange])
        }
        if let q = s.question, let first = q.items.first {   // 17/10: domanda di Claude
            return PillText(small: first.question, detail: "", main: "Claude asks you", palette: [.yellow, .orange])
        }
        if s.status == "done" {
            return PillText(small: s.files.isEmpty ? "Nothing changed" : "\(s.files.count) file\(s.files.count == 1 ? "" : "s") changed",
                            detail: "", main: "Done in \(AgentLook.duration(s))", palette: [Night.green, Night.green.opacity(0.6)])
        }
        if let now = s.steps.last(where: { $0.state == "now" }) {
            let k = StepKind.of(now.kind)
            return PillText(small: small, detail: detail, main: StepKind.phrase(k.doing, now), palette: [k.tint, k.tint.opacity(0.6), .white.opacity(0.8)])
        }
        return PillText(small: small, detail: detail, main: "Thinking", palette: [.orange, .pink, Color(red: 1, green: 0.8, blue: 0.6)])
    }
}

enum AgentLook {
    static func clock(_ s: AgentSession) -> String {
        if s.pending != nil || s.question != nil { return "OK?" }
        if s.status == "done" { return "✓" }
        let sec = max(0, Int(Date().timeIntervalSince1970 - s.started))
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
    static func duration(_ s: AgentSession) -> String {
        // solo a lavoro finito vale "finished": una sessione ripartita dopo uno Stop conta fino ad adesso
        let end = s.status == "done" && s.finished > 0 ? s.finished : Date().timeIntervalSince1970
        let sec = max(0, Int(end - s.started))
        return sec < 60 ? "\(sec) s" : "\(sec / 60) m \(sec % 60) s"
    }
}

enum PillStyle: String, CaseIterable {
    case compatta, soloServe, sempre
    var title: String { ["compatta": T("Compatta", "Compact"), "soloServe": T("Solo quando serve", "Only when needed"), "sempre": T("Sempre aperta", "Always open")][rawValue]! }
    static var saved: PillStyle {
        get { PillStyle(rawValue: Impostazioni.string(.agentPill) ?? "") ?? .compatta }
        set { Impostazioni.set(newValue.rawValue, .agentPill) }
    }
}

struct NotchPill: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var edge: EdgeLook        // 11/10 sera: la capsula sta su un bordo e si sposta come la colonna
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let tap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if let s = store.current {
                let p = PillText.of(s)
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        PixelGlyph(palette: p.palette)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(p.small).lineLimit(1).truncationMode(.middle)
                                if !p.detail.isEmpty { Text(p.detail).foregroundStyle(Color.primary.opacity(0.75)) }
                            }
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
                            Text(p.main).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color.primary)
                                .lineLimit(1).truncationMode(.tail)
                                .contentTransition(.opacity)
                        }
                        Spacer(minLength: 6)
                        if s.pending != nil {
                            HStack(spacing: 4) { KeyCap("⌃⌥Y"); Text("Allow").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6)) }
                        }
                    }
                    .padding(.leading, edge.side == .left ? 16 : 18).padding(.trailing, edge.side == .left ? 18 : 16)
                    .padding(.vertical, AgentModule.edgeR)
                    .frame(maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.25), value: p.main)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // la pillola segue l'aspetto: linguetta orizzontale attaccata al bordo, stessa forma della colonna
            Color.clear.modifier(ThemeSurface(mode: store.mode, shape: DockShape(r: AgentModule.edgeR, look: edge)))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .environment(\.colorScheme, Theme.scheme)
    }
}

struct KeyCap: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
    }
}

// MARK: - Linguetta laterale (raccordi concavi come il riferimento)

struct TabShape: Shape {
    var r: CGFloat = 20
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        p.move(to: CGPoint(x: x1, y: y0))
        p.addArc(center: CGPoint(x: x1 - r, y: y0), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: x0 + r, y: y0 + r))
        p.addArc(center: CGPoint(x: x0 + r, y: y0 + 2 * r), radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: x0, y: y1 - 2 * r))
        p.addArc(center: CGPoint(x: x0 + r, y: y1 - 2 * r), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: x1 - r, y: y1 - r))
        p.addArc(center: CGPoint(x: x1 - r, y: y1), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct SideTab: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var edge: EdgeLook       // 11/10: bordo, goccia e fusione (bordi.swift)
    let toggle: () -> Void
    let open: (AgentSection) -> Void

    var body: some View {
        SwiftUI.Group {
            NightRail(store: store, edge: edge, open: open)   // 11/10: stesse misure in tutti gli aspetti
        }
        .scaleEffect(edge.squash, anchor: edge.anchor)
    }

}


// MARK: - Pannello, in stile Impostazioni di Sistema

struct AgentPanel: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var edge: EdgeLook
    @ObservedObject var wall = WallpaperTint.shared
    let close: () -> Void
    let setMode: (AgentMode) -> Void

    var body: some View {
        // 11/10: un solo pannello (quello di Notte) per tutti gli aspetti: stesse misure, cambiano materiale e colori.
        // Il vecchio pannello "stile Impostazioni" della v1.9 aveva font e righe più grandi.
        NightPanel(store: store, close: close, setMode: setMode)
    }

    private var system: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let s = store.current { content(s) } else { empty }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .agentSurface(store.mode, RoundedRectangle(cornerRadius: 26, style: .continuous),
                      veil: store.mode == .sfondo ? Color(nsColor: wall.info(edge).veil) : .clear)
        .tint(store.mode == .sfondo ? Color(nsColor: wall.accent(edge)) : nil)
        .environment(\.colorScheme, store.mode == .sfondo ? wall.info(edge).scheme : store.mode.scheme)
        .id(store.mode == .sfondo ? wall.version : -1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconSquare(symbol: "sparkle", tint: .orange, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Code").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help("Close (⌃⌥P)")
        }
        .padding(16)
    }

    private var subtitle: String {
        guard let s = store.current else { return "Not running" }
        switch s.status {
        case "waiting": return "\(s.name), Needs your OK"
        case "done": return "\(s.name), Done"
        default: return "\(s.name), Working"
        }
    }

    private var footer: some View {
        HStack {
            if let s = store.current {
                Text(s.status == "done" ? "Finished in \(AgentLook.duration(s))" : "Running for \(AgentLook.duration(s))")
            }
            Spacer()
            Text("⌃⌥P")
        }
        .font(.system(size: 11)).foregroundStyle(.tertiary)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text("All quiet").font(.system(size: 13, weight: .semibold))
            Text("Start Claude Code in a terminal and it shows up here.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    @ViewBuilder private func content(_ s: AgentSession) -> some View {
        if store.sessions.count > 1 {
            Picker("", selection: Binding(get: { store.current?.id ?? "" }, set: { store.selectedID = $0 })) {
                ForEach(store.sessions) { Text($0.label(among: store.sessions)).tag($0.id) }
            }
            // 06/10: menu a tendina, non segmenti: con tante sessioni i segmenti allargavano il pannello oltre lo schermo
            .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
        }
        if !s.prompt.isEmpty {
            Group(title: "You asked") {
                Text(s.prompt).font(.system(size: 13)).lineSpacing(2).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }
        if let p = s.pending { approval(p) }
        if s.status == "done" && !s.summary.isEmpty {
            Group(title: "In plain words") {
                Text(s.summary).font(.system(size: 13)).lineSpacing(3).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }
        if s.status == "done" { facts(s) } else { steps(s) }
        if !s.stale.isEmpty {
            Label {
                Text("\(s.stale.joined(separator: ", ")) changed after the tests ran. Not tested since.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .padding(.horizontal, 4)
        }
    }

    private func approval(_ p: AgentPending) -> some View {
        Group(title: "Permission") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconSquare(symbol: "terminal.fill", tint: .yellow, size: 26)
                    Text("\(store.current?.agent ?? "Claude") wants to run").font(.system(size: 13, weight: .medium))
                }
                Text(p.what).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
                HStack(spacing: 8) {
                    Button { store.answer(false) } label: {
                        HStack(spacing: 6) { Text("Deny"); Text("⌃⌥N").font(.system(size: 10.5)).foregroundStyle(.secondary) }
                    }
                    .buttonStyle(CapsuleButton(prominent: false))
                    if p.always == true {
                        Button { store.answerAlways() } label: {
                            HStack(spacing: 6) { Text("Always"); Text("⌃⌥A").font(.system(size: 10.5)).foregroundStyle(.secondary) }
                        }
                        .buttonStyle(CapsuleButton(prominent: false))
                    }
                    Button { store.answer(true) } label: {
                        HStack(spacing: 6) { Text("Allow"); Text("⌃⌥Y").font(.system(size: 10.5)).opacity(0.75) }
                    }
                    .buttonStyle(CapsuleButton(prominent: true))
                }
            }
            .padding(12)
        }
    }

    private func steps(_ s: AgentSession) -> some View {
        Group(title: "Steps") {
            VStack(spacing: 0) {
                let list = Array(s.steps.suffix(9))
                ForEach(Array(list.enumerated()), id: \.element.id) { i, st in
                    let k = StepKind.of(st.kind)
                    StepRow(symbol: k.symbol, tint: k.tint,
                            title: st.label,
                            detail: [st.detail ?? "", (st.note ?? "").isEmpty ? "" : "fixed on \(st.note!)"].filter { !$0.isEmpty }.joined(separator: "   "),
                            trailing: st.state, last: i == list.count - 1)
                }
            }
        }
    }

    private func facts(_ s: AgentSession) -> some View {
        Group(title: "Summary") {
            VStack(spacing: 0) {
                StepRow(symbol: "clock.fill", tint: .gray, title: "Time", detail: "", value: AgentLook.duration(s), trailing: "", last: false)
                StepRow(symbol: "list.bullet", tint: .blue, title: "Steps", detail: "", value: "\(s.steps.count)", trailing: "", last: false)
                StepRow(symbol: "doc.on.doc.fill", tint: .orange, title: "Files changed", detail: s.files.joined(separator: ", "),
                        value: "\(s.files.count)", trailing: "", last: s.tests_ok == nil)
                if let ok = s.tests_ok {
                    StepRow(symbol: "checkmark.seal.fill", tint: ok ? Night.green : Night.red, title: "Tests", detail: "",
                            value: ok ? "Passed" : "Failed", trailing: "", last: true)
                }
            }
        }
    }
}

/// Riquadro raggruppato come in Impostazioni di Sistema, con titolo piccolo sopra.
private struct Group<C: View>: View {
    let title: String
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
            content
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quinary))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
        }
    }
}

/// Pulsanti a capsula come in macOS 26. Allow resta blu anche se la finestra non è attiva
/// (il pannello non ruba mai il fuoco al terminale, quindi i bottoni di sistema sarebbero sempre spenti).
private struct CapsuleButton: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .medium : .regular))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct IconSquare: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(tint.gradient))
    }
}

private struct StepRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var value: String = ""
    let trailing: String
    let last: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconSquare(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if !value.isEmpty { Text(value).font(.system(size: 13)).foregroundStyle(.secondary) }
            switch trailing {
            case "now": ProgressView().controlSize(.small)
            case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(Night.green)
            case "failed": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            default: EmptyView()
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .overlay(alignment: .bottom) {
            if !last { Divider().padding(.leading, 44) }
        }
    }
}

/// Il vetro sotto il blu: sfoca quello che c'è dietro la finestra. La maschera tonda tiene la sfocatura dentro gli angoli.
private struct NightBlur: NSViewRepresentable {
    let radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active                  // il pannello non diventa mai finestra attiva: senza questo il vetro si spegne
        v.appearance = NSAppearance(named: .darkAqua)
        v.maskImage = Self.mask(radius)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
    static func mask(_ r: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }
}

/// Il fondo del pannello: in Notte il vetro blu notte di sempre, negli altri aspetti il loro materiale.
private struct PanelSurface<S: Shape>: ViewModifier {
    let mode: AgentMode
    let shape: S
    func body(content: Content) -> some View {
        if mode == .notte {
            content
                .background(LinearGradient(colors: [Night.top.opacity(0.985), Night.bottom.opacity(0.99)], startPoint: .top, endPoint: .bottom))   // opaco: niente vetro lucido
                .background(NightBlur(radius: 28))
        } else {
            content.modifier(ThemeSurface(mode: mode, shape: shape))
        }
    }
}

// MARK: Colonna

/// Il fondo della colonna: Dark e White Matte sulla scheda grafica (DockLayerFill, bordi.swift), gli aspetti in vetro come prima.
struct RailSurface: ViewModifier {
    let mode: AgentMode
    let edge: EdgeLook
    let veil: Color
    // 21/10: osserva anche la forma (attaccata o libera), se no il fondo restava quello "attaccato" con le punte
    @ObservedObject private var form: EdgeForm
    init(mode: AgentMode, edge: EdgeLook, veil: Color) { self.mode = mode; self.edge = edge; self.veil = veil; form = edge.form }
    func body(content: Content) -> some View {
        switch mode {
        case .notte, .bianco:
            content.background(DockLayerFill(r: NightRail.r, look: edge, top: NSColor(edge.joinTop > 0.5 ? Night.bar : Night.barTop), bottom: NSColor(Night.bar)))
        default:
            content.modifier(ThemeSurface(mode: mode, shape: DockShape(r: NightRail.r, look: edge), veil: veil))
        }
    }
}

struct NightRail: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var edge: EdgeLook
    @ObservedObject var wall = WallpaperTint.shared
    let open: (AgentSection) -> Void
    private var glass: Bool { store.mode == .sfondo }   // 11/10: aspetto Sfondo, accento dallo sfondo
    private var light: Bool { Theme.light }
    static let r: CGFloat = 14          // raccordi concavi verso il bordo, come la linguetta del 05/10
    // 21/10: libera è un rettangolo arrotondato staccato (angoli 22, Bordi.rightPath), tasti da 42 a 10 l'uno dall'altro
    static let tastoLibero: CGFloat = 42, distanzaLibera: CGFloat = 10, bordoLibero: CGFloat = 14

    var body: some View {
        // 21/10: lasciata libera lontano dai bordi (come la ghiera del reel di will.geez) diventa una fila orizzontale
        let fila = edge.libero ? AnyLayout(HStackLayout(spacing: NightRail.distanzaLibera)) : AnyLayout(VStackLayout(spacing: 6))
        fila {
            ForEach(AgentSection.allCases, id: \.self) { sec in
                RailButton(symbol: sec.symbol, active: store.panelShown && store.section == sec,
                           badge: badge(sec), help: sec.title,
                           fg: .primary,
                           selFill: glass ? Color(nsColor: wall.accent(edge)).opacity(0.24) : store.mode == .notte ? Night.barSel : Night.sel,
                           ring: store.mode == .notte ? Night.bar : .clear, grande: edge.libero) { open(sec) }
            }
        }
        .padding(.vertical, edge.libero ? NightRail.bordoLibero : NightRail.r * 2 + 4)
        .padding(.horizontal, edge.libero ? NightRail.bordoLibero : 0)
        .padding(edge.side == .left ? .trailing : .leading, edge.libero ? 0 : 7).padding(edge.side == .left ? .leading : .trailing, edge.libero ? 0 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(EdgeFormed(form: edge.form) { RailSurface(mode: store.mode, edge: edge, veil: Color(nsColor: wall.info(edge).veil)) })
        .environment(\.colorScheme, Theme.scheme)
    }

    /// Il puntino rosso di Kinso sta sulla campanella: qui vuol dire che Claude aspetta un ok.
    private func badge(_ s: AgentSection) -> Color? {
        switch s {
        case .approve: return store.hasPending ? Night.red : nil
        case .work: return store.current?.status == "working" ? (glass ? Color(nsColor: wall.accent(edge)) : Night.green) : nil
        default: return nil
        }
    }
}

private struct RailButton: View {
    let symbol: String
    let active: Bool
    let badge: Color?
    let help: String
    var fg: Color = .white
    var selFill: Color = Night.barSel
    var ring: Color = Night.bar
    var grande = false                  // 21/10: colonna libera, l'autore: "troppo piccola", icone più grandi
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let lato: CGFloat = grande ? NightRail.tastoLibero : 32, raggio: CGFloat = grande ? 12 : 9
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: grande ? 17 : 13.5, weight: .medium))
                .foregroundStyle(fg.opacity(active ? 0.96 : hover ? 0.9 : 0.62))
                .frame(width: lato, height: lato)
                .background(RoundedRectangle(cornerRadius: raggio, style: .continuous)
                    .fill(active ? selFill : fg.opacity(hover ? 0.06 : 0)))
                .overlay(RoundedRectangle(cornerRadius: raggio, style: .continuous)
                    .strokeBorder(fg.opacity(active ? 0.08 : 0), lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Circle().fill(badge).frame(width: 6, height: 6)
                            .overlay(Circle().stroke(active ? selFill : ring, lineWidth: 1.5))
                            .offset(x: -5, y: 5)
                    }
                }
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.18), value: active)
                .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: Pannello

/// Voce di menu che esegue una chiusura (per il menu "…" del pannello).
private final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func go() { run() }
}

struct NightPanel: View {
    @ObservedObject var store: AgentStore
    let close: () -> Void
    let setMode: (AgentMode) -> Void
    @State private var draft = ""
    /// Nelle foto (FotoImpostazioni, foto di vendita) niente ScrollView né campo di testo: ImageRenderer non li disegna.
    @Environment(\.fotoImpostazioni) private var foto
    private let shape = RoundedRectangle(cornerRadius: 28, style: .circular)

    private var sezione: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.section == .window { LiveWindowSection() }
            else if store.section == .muta { MutaSection() }
            else if let s = store.current { sectionView(s) } else { quiet }
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
            SwiftUI.Group {
                if foto { sezione.frame(maxHeight: .infinity, alignment: .top) }
                else { ScrollView(showsIndicators: false) { sezione } }
            }
            .mask(VStack(spacing: 0) {       // il contenuto sfuma prima del campo in basso
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 18)
            })
            if store.section != .window && store.section != .muta { composer.padding(.horizontal, 12).padding(.bottom, 12) }
        }
        .modifier(PanelSurface(mode: store.mode, shape: shape))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.06)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .environment(\.colorScheme, Theme.scheme)
    }

    // MARK: in alto: indietro, spunta e altro, avanti; a destra orologio e chiudi

    private var toolbar: some View {
        let many = store.sessions.count > 1
        let pending = store.current?.pending != nil || store.hasPending
        return HStack(spacing: 6) {
            RoundIcon(symbol: "chevron.left", enabled: many, help: "Previous session") { store.stepSession(-1) }
            HStack(spacing: 0) {
                RoundIcon(symbol: "checkmark", enabled: pending, help: "Allow (⌃⌥Y)", bare: true) { store.answer(true) }
                RoundIcon(symbol: "ellipsis", help: "More", bare: true) { moreMenu() }
            }
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            RoundIcon(symbol: "chevron.right", enabled: many, help: "Next session") { store.stepSession(1) }
            Spacer()
            RoundIcon(symbol: "clock", active: store.section == .sessions, help: "Sessions") {
                store.section = store.section == .sessions ? .work : .sessions
            }
            RoundIcon(symbol: "xmark", help: "Close (⌃⌥P)", action: close)
        }
    }

    private func moreMenu() {
        let m = NSMenu()
        m.appearance = NSAppearance(named: Theme.light ? .aqua : .darkAqua)
        func add(_ title: String, on: Bool = false, _ f: @escaping () -> Void) {
            let a = MenuAction(f)
            let i = NSMenuItem(title: title, action: #selector(MenuAction.go), keyEquivalent: "")
            i.target = a; i.representedObject = a; i.state = on ? .on : .off
            m.addItem(i)
        }
        if store.hasPending {
            add("Allow  ⌃⌥Y") { store.answer(true) }
            add("Deny  ⌃⌥N") { store.answer(false) }
            m.addItem(.separator())
        }
        for sec in AgentSection.allCases { add(sec.title, on: store.section == sec) { store.section = sec } }
        // 11/10 sera: il tema si sceglie dal menu di Pulsar (sezione TEMA), non più da qui
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: titolo della sezione

    private func titleBlock(_ title: String, _ sub: String, glyph: [Color]? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let glyph { PixelGlyph(palette: glyph).padding(.top, 3) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1)
                Text(sub).font(.system(size: 12)).foregroundStyle(Night.t2).lineLimit(1)
            }
        }
        .padding(.leading, 2).padding(.bottom, 6)
    }

    private func status(_ s: AgentSession) -> String {
        switch s.status {
        case "waiting": return "Needs your OK"
        case "done": return "Done in \(AgentLook.duration(s))"
        default: return "Working for \(AgentLook.duration(s))"
        }
    }

    @ViewBuilder private func sectionView(_ s: AgentSession) -> some View {
        switch store.section {
        case .work: work(s)
        case .files: files(s)
        case .approve: approve(s)
        case .sessions: sessionsList
        case .window: LiveWindowSection()
        case .muta: MutaSection()
        }
    }

    // MARK: Lavoro

    @ViewBuilder private func work(_ s: AgentSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            titleBlock(s.name, status(s), glyph: PillText.of(s).palette)
        }
        if store.sessions.count > 1 { sessionPills }
        if !s.prompt.isEmpty {
            NightCard {
                Text("You asked").font(.system(size: 11.5)).foregroundStyle(Night.t2)
                Text(s.prompt).font(.system(size: 13.5)).foregroundStyle(Color.primary.opacity(0.92)).lineSpacing(2.5)
                    .textSelection(.enabled)
            }
        }
        if let p = s.pending { approvalCard(p) }
        if s.status == "done" && !s.summary.isEmpty {
            NightCard {
                Text("In plain words").font(.system(size: 11.5)).foregroundStyle(Night.t2)
                Text(s.summary).font(.system(size: 13.5)).foregroundStyle(Color.primary.opacity(0.9)).lineSpacing(3.5)
                    .textSelection(.enabled)
            }
        }
        if s.status == "done" {
            EventRow(bar: .gray, title: "Time", value: AgentLook.duration(s))
            EventRow(bar: .blue, title: "Steps", value: "\(s.steps.count)")
            EventRow(bar: .orange, title: "Files changed", sub: s.files.joined(separator: ", "), value: "\(s.files.count)")
            if let ok = s.tests_ok {
                EventRow(bar: ok ? Night.green : Night.red, title: "Tests", value: ok ? "Passed" : "Failed")
            }
        } else {
            // il più recente in cima: nel pannello stretto il passo in corso resta sempre in vista
            ForEach(Array(s.steps.suffix(9).reversed())) { st in
                let k = StepKind.of(st.kind)
                EventRow(bar: st.state == "failed" ? Night.red : k.tint, title: st.label,
                         sub: [Self.word(st.kind), st.detail ?? "", (st.note ?? "").isEmpty ? "" : "fixed on \(st.note!)"]
                            .filter { !$0.isEmpty }.joined(separator: "   "),
                         state: st.state)
            }
        }
        staleNote(s)
    }

    private static func word(_ kind: String) -> String {
        ["READ": "Read", "EDIT": "Edit", "RUN": "Command", "FIND": "Search", "WEB": "Web",
         "AGENT": "Helper", "PLAN": "Plan", "MSG": "From you"][kind] ?? kind.capitalized
    }

    @ViewBuilder private func staleNote(_ s: AgentSession) -> some View {
        if !s.stale.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Night.amber).frame(width: 6, height: 6).padding(.top, 5)
                Text("\(s.stale.joined(separator: ", ")) changed after the tests ran. Not tested since.")
                    .font(.system(size: 12)).foregroundStyle(Night.t2)
            }
            .padding(.horizontal, 4).padding(.top, 4)
        }
    }

    private var sessionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(byStart.reversed()) { x in      // la più recente a sinistra, sempre in vista
                    let on = x.id == store.current?.id
                    Button { store.selectedID = x.id } label: {
                        HStack(spacing: 6) {
                            Circle().fill(dot(x)).frame(width: 5, height: 5)
                            Text(x.label(among: store.sessions)).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.primary.opacity(on ? 0.96 : 0.72))
                        .padding(.horizontal, 11).frame(height: 26)
                        .background(Capsule().fill(on ? Night.sel : Color.primary.opacity(0.07)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0.07 : 0), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 2)
    }

    /// Ordine di partenza: le pillole non si scambiano di posto quando una sessione si aggiorna.
    private var byStart: [AgentSession] { store.sessions.sorted { $0.started < $1.started } }

    private func dot(_ x: AgentSession) -> Color {
        x.pending != nil ? Night.amber : x.status == "done" ? Color.primary.opacity(0.4) : Night.green
    }

    // MARK: Approva

    private func approvalCard(_ p: AgentPending) -> some View {
        NightCard {
            HStack(spacing: 8) {
                Circle().fill(Night.amber).frame(width: 6, height: 6)
                Text("\(store.current?.agent ?? "Claude") wants to run").font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            Text(p.what).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.primary.opacity(0.9))
                .textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.light ? Color.white.opacity(0.7) : Color.black.opacity(0.32)))   // White Matte: riquadro chiaro, non grigio
            HStack(spacing: 8) {
                Button { store.answer(false) } label: { keyLabel("Deny", "⌃⌥N") }
                    .buttonStyle(NightPill(prominent: false))
                if p.always == true {
                    Button { store.answerAlways() } label: { keyLabel("Always", "⌃⌥A") }
                        .buttonStyle(NightPill(prominent: false))
                }
                Button { store.answer(true) } label: { keyLabel("Allow", "⌃⌥Y") }
                    .buttonStyle(NightPill(prominent: true))
            }
            .padding(.top, 2)
        }
    }

    private func keyLabel(_ t: String, _ k: String) -> some View {
        HStack(spacing: 6) { Text(t); Text(k).font(.system(size: 10.5)).opacity(0.55) }
    }

    @ViewBuilder private func approve(_ s: AgentSession) -> some View {
        let p = s.pending ?? store.active.first { $0.pending != nil }?.pending
        titleBlock("Approve", p == nil ? "Nothing waiting" : "\(s.agent) is waiting for you")
        if let p { approvalCard(p) } else {
            NightCard {
                Text("When Claude asks for permission it shows up here first. ⌃⌥Y allows it and ⌃⌥N denies it from any app.")
                    .font(.system(size: 13)).foregroundStyle(Night.t2).lineSpacing(2.5)
            }
        }
    }

    // MARK: File

    @ViewBuilder private func files(_ s: AgentSession) -> some View {
        let edits = s.steps.filter { $0.kind == "EDIT" }
        let changed = s.files.isEmpty ? Self.unique(edits.map(\.label)) : s.files
        let read = Self.unique(s.steps.filter { $0.kind == "READ" }.map(\.label)).filter { !changed.contains($0) }
        titleBlock("Files", "\(changed.count) changed, \(read.count) read")
        if changed.isEmpty && read.isEmpty {
            NightCard { Text("No files touched yet.").font(.system(size: 13)).foregroundStyle(Night.t2) }
        }
        ForEach(changed, id: \.self) { f in
            let stale = s.stale.contains { f.hasSuffix($0) || $0.hasSuffix(f) }
            // 17/10: +N −M di tutta la richiesta; un clic apre il diff intero (agente-linea.swift)
            let full = s.changeList.first { ($0.path as NSString).lastPathComponent == f }
            let counts = full.map { "+\($0.change.add) \u{2212}\($0.change.rem)" } ?? edits.last { $0.label == f }?.detail ?? ""
            Button {
                if let full { DiffWindow.open(store: store, session: s, path: full.path) }
            } label: {
                EventRow(bar: stale ? Night.amber : .orange, title: (f as NSString).lastPathComponent,
                         sub: [f.contains("/") ? f : "", counts].filter { !$0.isEmpty }.joined(separator: "   "),
                         value: stale ? "Not tested" : full != nil ? "See diff" : "Changed")
            }
            .buttonStyle(.plain)
            .disabled(full == nil)
        }
        ForEach(read, id: \.self) { f in
            EventRow(bar: .blue, title: (f as NSString).lastPathComponent, sub: f.contains("/") ? f : "", value: "Read")
        }
    }

    private static func unique(_ a: [String]) -> [String] {
        var seen = Set<String>(); return a.filter { seen.insert($0).inserted }
    }

    // MARK: Sessioni

    @ViewBuilder private var sessionsList: some View {
        titleBlock("Sessions", "\(store.active.count) running, \(store.sessions.count) in all")
        Button { store.selectedID = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10.5, weight: .semibold))
                Text("Follow the newest").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.primary.opacity(store.selectedID == nil ? 0.96 : 0.72))
            .padding(.horizontal, 11).frame(height: 26)
            .background(Capsule().fill(store.selectedID == nil ? Night.sel : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
        ForEach(byStart.reversed()) { x in
            Button {
                store.selectedID = x.id
                store.section = .work
            } label: {
                EventRow(bar: dot(x), title: x.name, sub: x.prompt,
                         value: x.pending != nil ? "Waiting" : x.status == "done" ? "Done" : "Working",
                         highlight: x.id == store.current?.id && store.selectedID != nil)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Vuoto

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleBlock("All quiet", "Nothing running")
            NightCard {
                Text("Start Claude Code in a terminal and it shows up here: what you asked, every step, and the permissions to approve.")
                    .font(.system(size: 13)).foregroundStyle(Night.t2).lineSpacing(2.5)
            }
        }
    }

    // MARK: in basso: il campo arrotondato con le icone piccole

    private var composer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let s = store.current
            VStack(alignment: .leading, spacing: 12) {
                let live = s.map { $0.status == "working" || $0.status == "waiting" } ?? false
                ZStack(alignment: .leading) {
                    if draft.isEmpty {
                        Text(live ? T("Scrivi a Claude mentre lavora", "Message Claude while it works") : placeholder(s))
                            .font(.system(size: 13)).foregroundStyle(Night.t3).lineLimit(1)
                    }
                    if !foto {
                        TextField("", text: $draft, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                            .disabled(!live)
                            .onSubmit { sendDraft() }
                    }
                }
                if let s, store.queued(s.id) > 0 {
                    Text(T("Arriva al prossimo passo di Claude", "Arrives at Claude's next step"))
                        .font(.system(size: 11)).foregroundStyle(Night.green)
                }
                HStack(spacing: 12) {
                    if let s {
                        meta("timer", AgentLook.duration(s))
                        meta("list.bullet", "\(s.steps.count)")
                        meta("doc", "\(s.files.isEmpty ? Self.unique(s.steps.filter { $0.kind == "EDIT" }.map(\.label)).count : s.files.count)")
                    }
                    Spacer()
                    Text("⌃⌥P").font(.system(size: 11)).foregroundStyle(Night.t3)
                    if store.hasPending {
                        Button { store.answer(true) } label: {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Night.ink)
                                .frame(width: 24, height: 24).background(Circle().fill(Night.prominent))
                        }
                        .buttonStyle(.plain).help("Allow (⌃⌥Y)")
                    } else {
                        let ready = live && !draft.trimmingCharacters(in: .whitespaces).isEmpty
                        Button { sendDraft() } label: {
                            Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ready ? Night.ink : Night.t3)
                                .frame(width: 24, height: 24).background(Circle().fill(ready ? Night.green : Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain).disabled(!ready).help(T("Manda alla chat", "Send to this chat"))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 11)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.light ? Color.white.opacity(0.75) : Color.black.opacity(0.3)))   // White Matte: campo chiaro
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

    private func sendDraft() {
        guard let s = store.current, s.status == "working" || s.status == "waiting" else { return }
        store.send(draft, to: s.id)
        draft = ""
    }

    private func placeholder(_ s: AgentSession?) -> String {
        guard let s else { return "Waiting for Claude Code" }
        if store.hasPending { return "Waiting for your OK" }
        return PillText.of(s).main
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
            Text(text).font(.system(size: 11.5).monospacedDigit())
        }
        .foregroundStyle(Night.t3)
    }
}

/// Bottone tondo della fila in alto, come Kinso. `bare` = dentro la capsula condivisa (senza cerchio suo).
private struct RoundIcon: View {
    let symbol: String
    var enabled = true
    var active = false
    let help: String
    var bare = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(active ? 0.96 : !enabled ? 0.25 : hover ? 0.95 : 0.7))
                .frame(width: 28, height: 28)
                .background(Circle().fill(active ? Night.sel : Color.primary.opacity(bare ? (hover && enabled ? 0.08 : 0) : (hover && enabled ? 0.13 : 0.07))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Riquadro un po' più chiaro del fondo (la mail aperta di Kinso).
private struct NightCard<C: View>: View {
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Night.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.05), lineWidth: 1))
    }
}

/// Riga scura con la barretta colorata a sinistra (gli eventi del calendario di Kinso).
private struct EventRow: View {
    let bar: Color
    let title: String
    var sub: String = ""
    var value: String = ""
    var state: String = ""
    var highlight = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(bar.opacity(state == "done" ? 0.75 : 1))
                .frame(width: 3).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary)
                    .lineLimit(1).truncationMode(.middle)
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 11.5)).foregroundStyle(Night.t2).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            if !value.isEmpty { Text(value).font(.system(size: 12).monospacedDigit()).foregroundStyle(Night.t2) }
            switch state {
            case "now": BreathDot()
            case "done": Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Night.t3)
            case "failed": Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Night.red)
            default: EmptyView()
            }
        }
        .padding(.vertical, 9).padding(.leading, 8).padding(.trailing, 12)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(highlight ? Color.primary.opacity(0.09) : Night.veil))
        .contentShape(Rectangle())
    }
}

/// Il passo in corso: un puntino menta che respira (la rotella mini spariva sul blu).
private struct BreathDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Leggera.on)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let k = 0.5 + 0.5 * sin(t * 2 * .pi / 1.8)
            ZStack {
                Circle().fill(Night.green.opacity(0.25 * (1 - k))).frame(width: 7 + 8 * k, height: 7 + 8 * k)
                Circle().fill(Night.green).frame(width: 7, height: 7)
            }
            .frame(width: 16, height: 16)
        }
    }
}

/// Allow bianco col testo scuro, Deny scuro: i due bottoni a capsula di Notte.
private struct NightPill: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Night.onProminent : Color.primary.opacity(0.9))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Capsule().fill(prominent ? Night.prominent : Color.primary.opacity(0.08)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

final class AgentModule {
    let store = AgentStore()
    /// La colonna come elemento del bordo (11/10): si trascina, cambia bordo, si fonde con le ghiere (bordi.swift).
    let tabItem = EdgeDock.Item(id: "agente", side: .right)
    /// La capsula di Claude (11/10 sera, l'autore: "DEVE stare SEMPRE a destra", e si sposta su, giù, sinistra e destra).
    let pillItem = EdgeDock.Item(id: "avviso", side: .right)
    private var pillWanted = false
    private var pillWin: FloatPanel?
    private var tabWin: FloatPanel?
    private var panelWin: FloatPanel?
    private var cancellable: Any?
    private var monitors: [Any] = []
    private(set) var panelOpen = false
    private var pillShown = false

    // Colonna stretta (44 + 6 dal bordo) e pannello stretto e alto, come Kinso
    // 11/10: stesse misure in tutti gli aspetti (prima Scuro e Vetro avevano linguetta, pannello e righe diversi)
    private var panelW: CGFloat { 344 }
    private var tabW: CGFloat { 44 }
    private var tabH: CGFloat {
        let n = CGFloat(AgentSection.allCases.count)
        return n * 32 + (n - 1) * 6 + 2 * (NightRail.r * 2 + 4)
    }
    private func panelHeight(_ vf: NSRect) -> CGFloat { min(vf.height - 24, 640) }
    /// La fila orizzontale della colonna libera: le icone da 32 con 6 fra l'una e l'altra, 12 ai lati.
    private var railLength: CGFloat {
        let n = CGFloat(AgentSection.allCases.count)
        return n * NightRail.tastoLibero + (n - 1) * NightRail.distanzaLibera + 2 * NightRail.bordoLibero
    }
    private var railHeight: CGFloat { NightRail.tastoLibero + 2 * NightRail.bordoLibero }
    /// La colonna ha la cima allineata al pannello.
    private func tabY(_ vf: NSRect) -> CGFloat {
        vf.midY + panelHeight(vf) / 2 - tabH + NightRail.r
    }

    var enabled: Bool {
        get { Impostazioni.object(.agentEnabled) as? Bool ?? true }
        set { Impostazioni.set(newValue, .agentEnabled); RegistroModuli.shared.riapplica() }   // avvia o ferma il registro, secondo scelta e licenza
    }
    var tabEnabled: Bool {
        get { Impostazioni.object(.agentTab) as? Bool ?? true }
        set { Impostazioni.set(newValue, .agentTab); layout(animated: false) }
    }
    /// Linguetta a scomparsa, come il Dock: esce quando il mouse tocca il bordo destro.
    var tabAutoHide: Bool {
        get { Impostazioni.object(.agentTabAuto) as? Bool ?? true }
        set { Impostazioni.set(newValue, .agentTabAuto); EdgeDock.shared.conceal(tabItem); layout(animated: true) }
    }
    static let edgeR: CGFloat = 12          // raccordi concavi della linguetta degli avvisi

    /// Come appare la pillola: sempre o solo quando serve.
    var pillStyle: PillStyle {
        get { PillStyle.saved }
        set { PillStyle.saved = newValue; layout(animated: true) }
    }
    private var pillHover = false
    private var flashUntil: Double = 0
    private var seenFailed: [String: Int] = [:]
    private var seenStatus: [String: String] = [:]
    private var seenPending: [String: String] = [:]
    private var seenQuestion: [String: String] = [:]
    /// Un suono quando Claude finisce o chiede un permesso (06/10): si sente anche senza guardare il notch.
    var agentSounds: Bool {
        get { Impostazioni.object(.agentSounds) as? Bool ?? true }
        set { Impostazioni.set(newValue, .agentSounds) }
    }
    private func chime(_ name: String, _ volume: Float) {
        guard agentSounds, let snd = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        snd.volume = volume; snd.play()
    }
    private var seenStart: [String: Double] = [:]
    private var hideWork: DispatchWorkItem?
    private var pillHoverWork: DispatchWorkItem?

    var mode: AgentMode {
        get { store.mode }
        set {
            guard !RegistroModuli.shared.bloccato("temi") else { return }   // senza Complete il tema scelto resta com'è
            Theme.apply(newValue); store.mode = newValue; panelWin?.hasShadow = false
        }
    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private var notchSize: CGSize {
        let s = screen
        guard s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else {
            return CGSize(width: 190, height: NSStatusBar.system.thickness)
        }
        return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
    }


    private func start() {
        guard pillWin == nil else { return }
        store.start()
        let lvl = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        let pill = FloatPanel(level: lvl)
        pill.contentView = FirstClickHost(rootView: NotchPill(store: store, edge: pillItem.look, notchHeight: notchSize.height, notchWidth: notchSize.width,
                                                              tap: { [weak self] in self?.togglePanel() }))
        pillWin = pill
        setupPillItem(pill)

        let tab = FloatPanel(level: .statusBar)
        tab.contentView = FirstClickHost(rootView: SideTab(store: store, edge: tabItem.look, toggle: { [weak self] in self?.togglePanel() },
                                                           open: { [weak self] in self?.openSection($0) }))
        tabWin = tab
        setupTabItem(tab)

        let panel = FloatPanel(level: .statusBar, keyable: true)
        panel.hasShadow = false   // niente ombra di finestra, faceva un bordo nero
        Ombra.attacca(panel) { [weak self] r in Ombra.tonda(self?.store.mode.rail == true ? 28 : 26)(r) }   // 12/10: l'ombra minima del tema
        panel.contentView = FirstClickHost(rootView: AgentPanel(store: store, edge: tabItem.look, close: { [weak self] in self?.setPanel(false) },
                                                                setMode: { [weak self] m in
                                                                    // senza Complete la scelta dell'aspetto apre la licenza invece di non fare niente
                                                                    if RegistroModuli.shared.bloccato("temi") { LicenzaViva.shared.chiedi() } else { self?.mode = m }
                                                                }))
        panelWin = panel

        cancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.layout(animated: true) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        addHotkeys()
        layout(animated: false)
        panel.orderFrontRegardless()
        tab.orderFrontRegardless()     // la colonna sta sopra il pannello (in Notte restano insieme)
    }

    /// La capsula è un elemento dei bordi come la colonna: parte in alto a destra, si trascina dove si vuole.
    private func setupPillItem(_ win: NSWindow) {
        let it = pillItem
        it.radius = { AgentModule.edgeR }
        it.size = { NSSize(width: 330, height: 48 + 2 * AgentModule.edgeR) }
        it.defaultTop = { vf in vf.maxY - 6 }
        it.reach = 30
        it.forced = { [weak self] in self?.pillWanted ?? false }   // esce e rientra secondo il lavoro di Claude, non col mouse
        it.apply = { [weak self] in self?.layout(animated: $0) }
        it.colors = { (.black, .black) }
        EdgeDock.shared.register(it, window: win)
    }

    /// Cosa sa il regista dei bordi della colonna: misure, quando deve stare fuori, colori della goccia.
    private func setupTabItem(_ win: NSWindow) {
        let it = tabItem
        Theme.agentLook = it.look
        it.radius = { NightRail.r }
        it.size = { [weak self, weak it] in
            guard let self else { return NSSize(width: 44, height: 210) }
            if it?.floating != nil { return NSSize(width: self.railLength, height: self.railHeight) }   // 21/10: libera, in orizzontale
            return NSSize(width: self.tabW, height: self.tabH)
        }
        it.defaultTop = { [weak self] vf in (self?.tabY(vf) ?? vf.midY) + (self?.tabH ?? 0) }
        it.reach = 110                     // la colonna è stretta: la fascia che la fa uscire è più alta di lei
        it.forced = { [weak self] in
            guard let self else { return false }
            if !self.tabEnabled { return false }
            if self.panelOpen { return true }                    // la colonna resta accanto al pannello
            if !self.tabAutoHide || self.store.hasPending { return true }
            return nil
        }
        it.apply = { [weak self] in self?.layout(animated: $0) }
        it.willDrag = { [weak self] in if self?.panelOpen == true { self?.setPanel(false) } }
        it.colors = { [weak self] in
            guard let self else { return (.black, .black) }
            if self.store.mode == .sfondo { let v = WallpaperTint.shared.info(self.tabItem.look).veil; return (v, v) }
            return self.store.mode == .notte ? (NSColor(Night.barTop), NSColor(Night.bar)) : GhieraColors.goo
        }
        EdgeDock.shared.register(it, window: win)
    }

    private func stop() {
        EdgeDock.shared.unregister(tabItem)
        EdgeDock.shared.unregister(pillItem)
        store.stop()
        [pillWin, tabWin, panelWin].forEach { $0?.orderOut(nil) }
        pillWin = nil; tabWin = nil; panelWin = nil
        cancellable = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func screensChanged() { layout(animated: false) }

    /// 11/10 sera, l'autore: "Claude rimane in primo piano anche se apro un'altra app". Cambiando app il pannello si
    /// chiude e la capsula rientra nel bordo; resta fuori solo se Claude aspetta un permesso.
    @objc private func appActivated(_ n: Notification) {
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if panelOpen { setPanel(false) }
        pillHover = false; pillHoverWork?.cancel(); pillHoverWork = nil
        flashUntil = 0
        layout(animated: true)
    }

    /// ⌃⌥Y consenti, ⌃⌥N nega, ⌃⌥P apre e chiude il pannello, ⌃⌥L cambia aspetto. Il monitor globale usa
    /// lo stesso permesso Accessibilità dei suoni tastiera.
    private func addHotkeys() {
        let handler: (NSEvent) -> Bool = { [weak self] e in
            guard let self, e.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.control, .option]) else { return false }
            switch e.keyCode {
            case 16 where self.store.hasPending: self.store.answer(true); return true    // Y
            case 45 where self.store.hasPending: self.store.answer(false); return true   // N
            case 0 where self.store.hasPending: self.store.answerAlways(); return true    // A: Sempre (17/10)
            case 35: DispatchQueue.main.async { self.togglePanel() }; return true          // P
            case 37: DispatchQueue.main.async { self.cycleMode() }; return true            // L: aspetto successivo
            default: return false
            }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = handler($0) }) { monitors.append(g) }
        // il mouse sul bordo destro fa uscire la linguetta (i movimenti del mouse non chiedono permessi)
        let move: (NSEvent) -> Void = { [weak self] _ in self?.mouseMoved() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: move) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { move($0); return $0 }) { monitors.append(l) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { handler($0) ? nil : $0 }) { monitors.append(l) }
        // 10/10, l'autore: il pannello si chiude anche con un clic sinistro ovunque fuori dal box, non solo con la croce.
        // Il clic su pillola e linguetta resta loro (aprono e chiudono già da sé). I clic del mouse non chiedono permessi.
        let fuori: (NSEvent) -> Void = { [weak self] _ in DispatchQueue.main.async { self?.chiudiSeFuori() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: fuori) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { fuori($0); return $0 }) { monitors.append(l) }
    }

    private func chiudiSeFuori() {
        // 11/10 sera: un clic fuori riduce anche la capsula aperta (torna compatta o rientra nel bordo)
        if pillHover, let f = pillWin?.frame, !f.contains(NSEvent.mouseLocation) {
            pillHover = false; pillHoverWork?.cancel(); pillHoverWork = nil; flashUntil = 0; layout(animated: true)
        }
        guard panelOpen, let panelWin else { return }
        let p = NSEvent.mouseLocation
        let dentro = [panelWin, tabWin, pillWin].compactMap { $0 }.contains { $0.isVisible && $0.frame.contains(p) }
        if !dentro { setPanel(false) }
    }

    func togglePanel() {
        if !panelOpen { store.section = store.hasPending ? .approve : .work }
        setPanel(!panelOpen)
    }

    /// Notte: un'icona della colonna apre la sua sezione; la stessa icona di nuovo chiude.
    func openSection(_ sec: AgentSection) {
        if panelOpen && store.section == sec { setPanel(false); return }
        store.section = sec
        setPanel(true)
    }

    /// Come il Dock: il mouse che tocca il bordo destro all'altezza della linguetta la fa uscire;
    /// quando si allontana, dopo mezzo secondo rientra.
    private func mouseMoved() {
        // L'avviso sta nascosto oltre il bordo: toccando il bordo a quell'altezza esce,
        // come la colonna (06/10, "visibile se ci passi sopra")
        if !pillShown, !pillHover, let s = store.current, s.status == "working" || s.status == "waiting" {
            let p = NSEvent.mouseLocation, sf = EdgeDock.shared.screen(of: pillItem).frame
            let pf = EdgeDock.shared.shownFrame(for: pillItem)
            let atEdge = pillItem.side == .right ? p.x >= sf.maxX - 4 : p.x <= sf.minX + 3
            if atEdge && p.y <= pf.maxY + 15 && p.y >= pf.minY - 15 {
                pillHover = true; pillHoverWork?.cancel(); pillHoverWork = nil; layout(animated: true)
                return
            }
        }
        // il mouse sopra la pillola la apre; fuori, mezzo secondo e torna compatta
        if pillShown, let f = pillWin?.frame {
            let inside = f.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
            if inside && !pillHover { pillHover = true; pillHoverWork?.cancel(); layout(animated: true) }
            else if !inside && pillHover && pillHoverWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.pillHover = false; self?.pillHoverWork = nil; self?.layout(animated: true) }
                pillHoverWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
            } else if inside { pillHoverWork?.cancel(); pillHoverWork = nil }
        }
        // la colonna che esce dal bordo e rientra ora la segue EdgeDock (bordi.swift), dovunque sia
    }

    /// ⌃⌥L: passa fra Dark Matte e White Matte (con sfondo, cartelle, macOS e Spazio: Temi.scegli).
    func cycleMode() {
        guard !RegistroModuli.shared.bloccato("temi") else { LicenzaViva.shared.chiedi(); return }   // senza Complete ⌃⌥L apre la licenza
        Temi.scegli(mode == .bianco ? .darkMatte : .whiteMatte) { [weak self] in self?.mode = $0 }
    }

    func setPanel(_ open: Bool) {
        panelOpen = open
        if store.panelShown != open { store.panelShown = open }
        if !open { EdgeDock.shared.conceal(tabItem) }
        layout(animated: true)
    }

    /// Mette al loro posto pillola, linguetta e pannello. Si muove solo il frame delle finestre.
    private func layout(animated: Bool) {
        guard let pillWin, let tabWin, let panelWin else { return }

        // pillola: viva se c'è lavoro, se aspetta un permesso o per 6 s dopo la fine
        let s = store.current
        let nowT = Date().timeIntervalSince1970
        let live: Bool = {
            guard let s else { return false }
            if s.status == "working" || s.status == "waiting" { return true }
            return s.status == "done" && nowT - s.finished < 6
        }()
        if live, s?.status == "done" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) { [weak self] in self?.layout(animated: true) }
        }
        // lampi: si apre da sola per qualche secondo quando parte una richiesta o fallisce un passo
        for x in store.sessions {          // suoni: fine del lavoro e richiesta di permesso, una volta per evento
            if let prev = seenStatus[x.id], prev != "done", x.status == "done" { chime("Glass", 0.45) }
            if let pid = x.pending?.id, seenPending[x.id] != pid, seenStatus[x.id] != nil { chime("Tink", 0.6) }
            seenStatus[x.id] = x.status
            seenPending[x.id] = x.pending?.id ?? ""
            if let qid = x.question?.id, seenQuestion[x.id] != qid, seenStatus[x.id] != nil { chime("Tink", 0.6) }   // 17/10: domanda di Claude
            seenQuestion[x.id] = x.question?.id ?? ""
        }
        for x in store.sessions {          // contati per sessione: passare da una all'altra non è un evento
            let failed = x.steps.filter { $0.state == "failed" }.count
            if failed > (seenFailed[x.id] ?? failed) { flashUntil = max(flashUntil, nowT + 3) }
            seenFailed[x.id] = failed
            if let prev = seenStart[x.id], prev != x.started, x.status == "working" { flashUntil = max(flashUntil, nowT + 3) }
            if seenStart[x.id] == nil && x.status == "working" && nowT - x.started < 3 { flashUntil = max(flashUntil, nowT + 3) }
            seenStart[x.id] = x.started
        }
        if s != nil {
            if flashUntil > nowT {
                DispatchQueue.main.asyncAfter(deadline: .now() + (flashUntil - nowT) + 0.1) { [weak self] in self?.layout(animated: true) }
            }
        }
        let needed = (s?.pending != nil) || (s?.question != nil) || (s?.status == "done") || flashUntil > nowT || pillHover
        // 11/10 sera: la capsula sta sempre sul bordo (di partenza a destra, sotto la barra dei menu), mai nel notch
        let open: Bool, show: Bool
        switch pillStyle == .sempre ? PillStyle.sempre : .soloServe {
        case .sempre:    show = live; open = live
        case .compatta:  show = live; open = live && needed
        case .soloServe: show = live && needed; open = show
        }
        let pillFrame: NSRect
        // sul suo bordo, dove l'hai messa (EdgeDock); di partenza in alto a destra sotto la barra dei menu
        pillWanted = show
        pillFrame = EdgeDock.shared.shownFrame(for: pillItem)
        if show && !pillShown {
            let dx = pillItem.side == .right ? pillFrame.width : -pillFrame.width   // entra dal suo bordo
            pillWin.setFrame(pillFrame.offsetBy(dx: dx, dy: 0), display: false)
            pillWin.orderFrontRegardless()
        }
        pillShown = show

        // pannello sospeso accanto alla colonna, sul suo bordo e sul suo schermo (11/10: la colonna si sposta).
        // La colonna resta e il pannello compare verso l'interno, con una dissolvenza e 28 pt di corsa.
        let dock = EdgeDock.shared
        let tsf = dock.screen(of: tabItem).frame, tvf = dock.screen(of: tabItem).visibleFrame
        let right = tabItem.side == .right
        let gap: CGFloat = 12
        let panelH = panelHeight(tvf)
        let column = dock.shownFrame(for: tabItem)
        let openX: CGFloat = tabEnabled
            ? (right ? tsf.maxX - tabW - 10 - panelW : tsf.minX + tabW + 10)
            : (right ? tsf.maxX - panelW - gap : tsf.minX + gap)
        let closedX = openX + (right ? 28 : -28)
        var panelX = panelOpen ? openX : closedX
        // La cima del pannello coincide con la cima visibile della colonna (se la colonna c'è); altrimenti è centrato su di lei
        var panelY = tabEnabled ? column.maxY - NightRail.r - panelH : column.midY - panelH / 2
        // 21/10: colonna libera (fila orizzontale): il pannello si apre sotto, centrato su di lei; se sotto non c'è posto, sopra
        if tabItem.floating != nil && tabEnabled {
            let sotto = column.minY - gap - panelH >= tvf.minY + 12
            panelX = min(max(column.midX - panelW / 2, tvf.minX + 12), tvf.maxX - 12 - panelW)
            let aperto = sotto ? column.minY - gap - panelH : column.maxY + gap
            panelY = panelOpen ? aperto : aperto + (sotto ? 28 : -28)
        }
        panelY = min(max(panelY, tvf.minY + 12), tvf.maxY - 12 - panelH)
        let panelFrame = NSRect(x: panelX, y: panelY, width: panelW, height: panelH)
        let panelAlpha: CGFloat = !panelOpen ? 0 : 1
        panelWin.ignoresMouseEvents = !panelOpen
        let tabFrame = dock.frame(for: tabItem)
        let dragging = tabItem.dragging           // mentre la trascini la colonna la muove EdgeDock
        let pillMoving = pillItem.dragging || pillItem.settling   // idem per la capsula

        let apply = {
            if !pillMoving { pillWin.animator().setFrame(pillFrame, display: true) }
            if !dragging { panelWin.animator().setFrame(panelFrame, display: true) }
            panelWin.animator().alphaValue = panelAlpha; Ombra.trasparenza(panelWin, panelAlpha, animata: true)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.55
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                apply()
            } completionHandler: { [weak self] in
                if self?.pillShown == false { pillWin.orderOut(nil) }
            }
        } else {
            if !pillMoving { pillWin.setFrame(pillFrame, display: true) }
            if !dragging { panelWin.setFrame(panelFrame, display: true) }
            panelWin.alphaValue = panelAlpha; Ombra.trasparenza(panelWin, panelAlpha, animata: false)
            if !show { pillWin.orderOut(nil) }
        }
        // la colonna con lo stesso tempo delle ghiere: se sono fuse escono e rientrano insieme
        if !dragging {
            dock.sizeChanged(tabItem)
            dock.move(tabWin, to: tabFrame, animated: animated)
        }
    }
}

// MARK: - Registro dei moduli (fase 2): l'Agente vale con Pulsar Agent (o Complete)

extension AgentModule: ModuloPulsar {
    var id: String { "agente" }
    var nome: String { T("Claude Code dal vivo", "Claude Code live") }
    var prodotto: Prodotto { .agent }
    var permessi: [Permesso] { [.accessibilita] }
    var acceso: Bool { enabled }
    func avvia() { start() }                        // start() esce subito se è già partito
    func ferma() { if pillWin != nil { stop() } }   // la scelta salvata non si tocca
}
