// La linea con Claude Code (17/10/2026), idee prese da coucou di Louis Raillé (codice MIT; nome, Mochi e suoni no):
// il socket Unix con l'hook, la card delle domande di Claude con le scelte, il diff intero di un file.
// Confronto e scelte in docs/2026-10-17-coucou-confronto.md.
import AppKit
import SwiftUI

// (il socket con l'hook sta in agente-socket.swift)


// MARK: - Domande di Claude nel notch

/// Le scelte di AskUserQuestion nello stile del pannello nuovo (17/10): razzo a sinistra, domanda, scelte in pillole
/// che vanno a capo; la descrizione di una scelta compare passandoci sopra. Nelle domande a più risposte si accendono
/// e si invia. "Nel terminale" lascia rispondere lì.
struct AgentQuestionCard: View {
    let question: AgentQuestion
    let project: String
    let send: ([String: Any]) -> Void
    let toTerminal: () -> Void
    @State private var index = 0
    @State private var picked: [Int: [String]] = [:]

    var body: some View {
        let item = question.items[min(index, question.items.count - 1)]
        VCard(glow: Volta.a2) {
            HStack(alignment: .center, spacing: 18) {
                Razzo(phase: .wait, pixel: 3.6).frame(width: 64, height: 88)
                VStack(alignment: .leading, spacing: 9) {
                    VWho(project: project, what: (item.header.isEmpty ? T("Claude ti fa una domanda", "Claude asks you") : item.header)
                         + (question.items.count > 1 ? "  \(index + 1)/\(question.items.count)" : ""))
                    Text(item.question).font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    Flow(spacing: 7) {
                        ForEach(item.options, id: \.label) { o in
                            let on = (picked[index] ?? []).contains(o.label)
                            VPill(title: o.label, kind: on ? .on : .normal, help: o.description.isEmpty ? nil : o.description) { choose(o, item) }
                        }
                        if index > 0 { VPill(title: T("Indietro", "Back"), kind: .ghost) { index -= 1 } }
                        if item.multi {
                            VPill(title: index == question.items.count - 1 ? T("Invia", "Send") : T("Avanti", "Next"), kind: .primary) { next() }
                                .disabled((picked[index] ?? []).isEmpty).opacity((picked[index] ?? []).isEmpty ? 0.45 : 1)
                        }
                        VPill(title: T("Nel terminale", "In the terminal"), kind: .ghost, action: toTerminal)
                    }
                }
            }
        }
        .id(question.id)
    }

    private func choose(_ o: AgentQuestion.Option, _ item: AgentQuestion.Item) {
        if item.multi {
            var cur = picked[index] ?? []
            if cur.contains(o.label) { cur.removeAll { $0 == o.label } } else { cur.append(o.label) }
            picked[index] = cur
        } else {
            picked[index] = [o.label]
            next()
        }
    }

    private func next() {
        if index < question.items.count - 1 { index += 1; return }
        var answers: [String: Any] = [:]
        for (i, it) in question.items.enumerated() {
            guard let p = picked[i], !p.isEmpty else { continue }
            answers[it.question] = it.multi ? p : p[0]
        }
        send(answers)
    }

    /// Altezza della tessera: la domanda più lunga va a capo a circa 470 pt, le pillole su una o due righe.
    static func height(_ q: AgentQuestion) -> CGFloat {
        func lines(_ s: String, _ w: CGFloat) -> CGFloat { max(1, (CGFloat(s.count) * w / 470).rounded(.up)) }
        let tallest = q.items.map { it -> CGFloat in
            let pills = it.options.map { CGFloat($0.label.count) * 7 + 36 }.reduce(0, +) + 120
            return 36 + 26 + lines(it.question, 8.2) * 21 + (pills > 470 ? 74 : 38)
        }.max() ?? 140
        return min(max(tallest, 132), 260)
    }
}

/// Le pillole in fila che vanno a capo quando non c'è più posto.
struct Flow: Layout {
    var spacing: CGFloat = 7
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 480
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX && x + s.width > b.maxX { y += row + spacing; x = b.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

// MARK: - Diff intero

/// La finestra col diff di un file: righe aggiunte in verde, tolte in rosso, contesto in grigio.
enum DiffWindow {
    private static var win: NSPanel?

    static func open(store: AgentStore, session: AgentSession, path: String) {
        let lines = store.diffLines(session: session, path: path)
        let c = session.changes?[path]
        let view = DiffView(name: (path as NSString).lastPathComponent, path: path, add: c?.add ?? 0, rem: c?.rem ?? 0, lines: lines)
            .environment(\.colorScheme, Theme.light ? .light : .dark)
        let p = win ?? {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.hidesOnDeactivate = false
            return w
        }()
        p.contentView = NSHostingView(rootView: view)
        p.title = (path as NSString).lastPathComponent
        if win == nil { p.center() }
        win = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }
}

private struct DiffView: View {
    let name: String
    let path: String
    let add: Int
    let rem: Int
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text("+\(add)").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Night.green)
                Text("\u{2212}\(rem)").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Color.red)
                Spacer()
                Button(T("Apri il file", "Open file")) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
            }
            .padding(.horizontal, 18).padding(.top, 34).padding(.bottom, 4)
            Text(path).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45)).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 18).padding(.bottom, 12)
            if lines.isEmpty {
                Text(T("Nessuna riga salvata per questo file.", "No lines saved for this file."))
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.55)).padding(18)
                Spacer()
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in row(l) }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.primary.opacity(0.04))
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    @ViewBuilder private func row(_ l: String) -> some View {
        if l.hasPrefix("@@") {
            Text(T("riga ", "line ") + l.dropFirst(3)).font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.4))
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 3)
        } else {
            let mark = l.first.map(String.init) ?? " "
            let tint: Color = mark == "+" ? Night.green : mark == "-" ? .red : .clear
            HStack(spacing: 0) {
                Text(mark == " " ? " " : mark).frame(width: 18).foregroundStyle(tint == .clear ? Color.primary.opacity(0.3) : tint)
                Text(String(l.dropFirst())).foregroundStyle(Color.primary.opacity(tint == .clear ? 0.6 : 0.92))
            }
            .font(.system(size: 11.5, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.13))
            .textSelection(.enabled)
        }
    }
}
