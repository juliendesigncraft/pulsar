// Claude Code nel notch: l'Agente (agente.swift) come fonte dell'isola.
// Compatta: a destra del notch un'animazione fatta apposta (anello di 16 pixel con una cometa e un cuore che pulsa,
// nei toni Dark Matte); un permesso in attesa o la fine del lavoro aprono l'isola da sole.
// La capsula sul bordo destro dell'Agente non cambia.
import SwiftUI
import AppKit
import Combine

final class AgentIslandSource: ObservableObject, IslandSource {
    let id = "agent"
    var onChange: (() -> Void)?
    let store: AgentStore
    private var watch: AnyCancellable?

    init(store: AgentStore) {
        self.store = store
        watch = store.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.onChange?() } }
    }

    private var session: AgentSession? { store.current }
    var pending: Bool { session?.pending != nil || store.question != nil }   // 17/10: anche una domanda di Claude apre l'isola
    /// Per sei secondi dopo la fine del lavoro l'isola lo dice da sola.
    var recentlyDone: Bool {
        guard let s = session, s.status == "done" else { return false }
        return Date().timeIntervalSince1970 - s.finished < 6
    }
    var alert: Bool { pending || recentlyDone }
    var priority: Int { pending ? 90 : recentlyDone ? 70 : 60 }
    var isActive: Bool {
        guard let s = session else { return false }
        return s.status == "working" || s.status == "waiting" || recentlyDone
    }
    /// Avviso (permesso, fine lavoro): vista tutta sua. Altrimenti si vede la casa con le tessere.
    var usesHome: Bool { !alert }
    var pulseState: NotchPulse.Phase { pending ? .waiting : recentlyDone ? .done : .working }
    /// Altezza della vista aperta: la domanda ne chiede di più, la fine lavoro coi file un po' di più.
    /// Altezza della tessera (17/10, pannello nuovo): la domanda ne chiede di più se ha le descrizioni lunghe.
    var height: CGFloat {
        if let q = store.question { return AgentQuestionCard.height(q) }
        if recentlyDone, let s = session, !s.changeList.isEmpty { return 160 }
        return 132
    }

    func compactLeading() -> AnyView {
        // 17/10 sera: a sinistra tornano le pastiglie del passo (l'autore), il razzo va a destra
        AnyView(AgentStepIcon(store: store))
    }
    func compactTrailing() -> AnyView {
        // 12/10 sera: il loop con le app è stato provato e tolto (l'autore: "la precedente era la migliore")
        // 12/10 notte: ripristinata com'era nel reel finale (32, v7): NotchPulse, senza aggiunte
        AnyView(SessionRockets(store: store))
    }
    func expandedView() -> AnyView {
        AnyView(AgentAlertView(store: store))
    }
}

/// A sinistra del notch: cosa sta facendo Claude adesso (legge, modifica, esegue, cerca), al posto del tempo
/// (l'autore, 12/10: "quel timer cos'è?"). Il tempo resta nell'avviso e nel pannello.
private struct AgentStepIcon: View {
    @ObservedObject var store: AgentStore
    var body: some View {
        // 12/10 notte: pastiglie nello stile di terminal.fill, il passo di Claude e poi le app aperte (anima-stella.swift)
        let s = store.current
        let kind: String = {
            guard let s else { return "THINK" }
            if s.status == "done" { return "DONE" }
            if let now = s.steps.last(where: { $0.state == "now" }) { return now.kind }
            return "THINK"
        }()
        HStack(spacing: 6) {
            // 17/10: file trascinati che aspettano il prossimo messaggio: graffetta e numero, finché Claude non li prende
            if store.contextCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "paperclip").font(.system(size: 10, weight: .semibold))
                    Text("\(store.contextCount)").font(.system(size: 10.5, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .help(T("In attesa del tuo prossimo messaggio", "Waiting for your next message"))
            }
            PastiglieInSequenza(kind: kind, waiting: s?.pending != nil || s?.question != nil)
        }
    }
}

// MARK: - L'animazione del notch

/// Griglia 5x5 nei toni Dark Matte. Un moto continuo, senza scatti (l'autore, 12/10: "partono repentinamente senza
/// ganci", "troppo bianco"): la cometa gira, rallenta, si ferma e torna indietro; poi sfuma in un'onda che si allarga
/// dal centro, si ferma e rientra; poi torna la cometa. Velocità integrate nel tempo, passaggi con curve morbide.
/// Solo la testa della cometa è chiara, il resto è blu-grafite. Ambra (più lenta) se aspetta un ok, menta a fine lavoro.
struct NotchPulse: View {
    enum Phase { case working, waiting, done }
    let phase: Phase
    @State private var motion = PulseMotion()
    @ObservedObject private var look = GhieraLook.shared     // in White Matte: base grafite chiaro, testa grafite scuro

    var body: some View {
        TimelineView(.animation(minimumInterval: Leggera.on ? 1.0 / 15 : 1.0 / 30)) { ctx in   // 13/10: animazione tenuta anche in Pulsar leggera (l'autore)
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                motion.advance(to: t, slow: phase == .waiting)
                let cell = min(size.width, size.height) / 5.0
                let px = cell * 0.78
                for y in 0..<5 {
                    for x in 0..<5 {
                        let (a, white) = phase == .done ? PulseMotion.doneLevel(x, y, t: t) : motion.level(x, y, t: t)
                        let light = Theme.light
                        let base: Color = phase == .waiting ? Night.amber : phase == .done ? Night.green : (light ? Color(white: 0.55) : PulseMotion.tail)
                        let hi: Color = phase == .working ? (light ? Color(white: 0.1) : .white) : base
                        let r = CGRect(x: (size.width - cell * 5) / 2 + CGFloat(x) * cell + (cell - px) / 2,
                                       y: (size.height - cell * 5) / 2 + CGFloat(y) * cell + (cell - px) / 2, width: px, height: px)
                        let path = Path(roundedRect: r, cornerRadius: px * 0.28)
                        g.fill(path, with: .color(base.opacity(a)))
                        if white > 0.01 { g.fill(path, with: .color(hi.opacity(white))) }
                    }
                }
            }
        }
    }
}

// MARK: - Avviso: permesso o fine lavoro

private struct AgentAlertView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var look = GhieraLook.shared

    var body: some View {
        if let q = store.question, let qs = store.sessions.first(where: { $0.question?.id == q.id }) ?? store.current {
            // la domanda di Claude con le sue scelte (agente-linea.swift)
            AgentQuestionCard(question: q, project: qs.name,
                              send: { store.answerQuestion(q, answers: $0) },
                              toTerminal: { store.questionToTerminal(q) })
        } else if let s = store.current {
            if let p = s.pending {
                VCard(glow: Volta.a1, breathe: true) {
                    HStack(spacing: 18) {
                        Razzo(phase: .wait, pixel: 3.6).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 9) {
                            VWho(project: s.name, what: T("Claude vuole \(p.tool == "Bash" ? "lanciare un comando" : "usare \(p.tool)")",
                                                             "Claude wants to \(p.tool == "Bash" ? "run a command" : "use \(p.tool)")"))
                            Text(p.what).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Volta.t1).lineLimit(2)
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Volta.card2))
                            HStack(spacing: 7) {
                                VPill(title: T("Nega", "Deny"), key: "N") { store.answer(false) }
                                if p.always == true { VPill(title: T("Sempre", "Always"), key: "A") { store.answerAlways() } }
                                VPill(title: T("Consenti", "Allow"), key: "Y", kind: .primary) { store.answer(true) }
                            }
                        }
                    }
                }
            } else if s.status != "done" {
                VCard(glow: Volta.a2) {
                    HStack(spacing: 18) {
                        Razzo(phase: .thrust, pixel: 3.6).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 8) {
                            VWho(project: s.name, what: T("consentito", "allowed"))
                            Text(PillText.of(s).main).font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1).lineLimit(1)
                        }
                    }
                }
            } else {
                VCard(glow: Volta.a1) {
                    HStack(spacing: 18) {
                        Razzo(phase: .launch, pixel: 3.6).frame(width: 64, height: 88).clipped()
                        VStack(alignment: .leading, spacing: 9) {
                            VWho(project: s.name, what: T("Claude ha finito in \(AgentLook.duration(s))", "Claude finished in \(AgentLook.duration(s))"))
                            Text(Self.firstSentence(s.summary) ?? (s.files.isEmpty ? T("Fatto, nessun file cambiato", "Done, nothing changed") : T("Fatto", "Done")))
                                .font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1).lineLimit(1)
                            if !s.changeList.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(s.changeList.prefix(3), id: \.path) { c in ChangeRow(path: c.path, change: c.change) { DiffWindow.open(store: store, session: s, path: c.path) } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// La prima frase del riassunto di Claude: il titolo della fine lavoro (non "Fatto").
    static func firstSentence(_ t: String) -> String? {
        let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.isEmpty else { return nil }
        if let r = x.range(of: #"[.!?](\s|$)"#, options: .regularExpression) { return String(x[..<r.upperBound]).trimmingCharacters(in: .whitespaces) }
        return x
    }
}

/// Un file cambiato: nome, +N in verde, −M in rosso. Un tocco apre il diff.
struct ChangeRow: View {
    let path: String
    let change: AgentChange
    let open: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Text(change.name).font(.system(size: 12)).foregroundStyle(Volta.t1).lineLimit(1)
                Text("+\(change.add)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Volta.a2)
                Text("\u{2212}\(change.rem)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Volta.t3)
            }
            .padding(.horizontal, 11).frame(height: 26)
            .background(Capsule().fill(hover ? Volta.pill : Volta.card2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(T("Vedi il diff", "See the diff"))
    }
}
