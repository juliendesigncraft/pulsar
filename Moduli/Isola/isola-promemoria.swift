// I promemoria nel notch (31/10/2026, dal reel di NotchOwl: "A nudge you can't miss. Right in the notch.").
// Un'attività della lista dell'Anima con un'ora (Todo.quando) arrivata: l'isola mostra a destra del notch l'ora,
// a sinistra la campanella, e aperta il titolo con due tasti, Fatto e Tra 10 minuti. Niente finestre né suoni nuovi.
import SwiftUI
import AppKit

final class PromemoriaSource: IslandSource {
    let id = "promemoria"
    let priority = 85                       // sopra la riunione (80) e Claude che lavora, sotto Claude che aspetta un ok (90)
    var onChange: (() -> Void)?
    var chiudi: (() -> Void)?
    private var timer: Timer?
    private var eraAttiva = false
    private var giaVisti: Set<String> = []    // la comparsa piccola parte una volta sola per promemoria

    /// L'interruttore "Promemoria nel notch" (scheda Oggi, Personalizza). Acceso di serie.
    static var enabled: Bool {
        get { Impostazioni.object(.isolaPromemoria) as? Bool ?? true }
        set { Impostazioni.set(newValue, .isolaPromemoria) }
    }

    /// Il primo promemoria arrivato e non ancora fatto.
    var arrivato: AnimaCose.Todo? {
        guard Self.enabled else { return nil }
        let ora = Date()
        return AnimaCose.shared.aperte.filter { !$0.fatto && ($0.quando.map { $0 <= ora } ?? false) }
            .min { ($0.quando ?? ora) < ($1.quando ?? ora) }
    }

    var isActive: Bool { arrivato != nil }

    func start() {
        guard timer == nil else { return }
        AnimaCose.shared.start()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.ricontrolla() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        ricontrolla()
    }

    func stop() { timer?.invalidate(); timer = nil; eraAttiva = false }

    /// Dopo Fatto, Rimanda o un cambio nella lista: l'isola si aggiorna subito.
    func ricontrolla() {
        let a = arrivato
        if let a, !giaVisti.contains(a.id + "\(a.quando?.timeIntervalSince1970 ?? 0)") {
            giaVisti.insert(a.id + "\(a.quando?.timeIntervalSince1970 ?? 0)")
            PeekCenter.shared.post(PeekItem(key: "promemoria-\(a.id)", kind: "info", symbol: "bell.fill",
                                            title: a.testo, detail: T("Promemoria", "Reminder"), priority: 70, duration: 5))
        }
        let ora = a != nil
        if ora != eraAttiva || ora { eraAttiva = ora; onChange?() }
    }

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: "bell.fill").font(.system(size: 11.5)).foregroundStyle(Volta.a2))
    }

    func compactTrailing() -> AnyView {
        guard let q = arrivato?.quando else { return AnyView(EmptyView()) }
        return AnyView(Text(OraTesto.hm(q)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Volta.a2).lineLimit(1))
    }

    var panelSize: CGSize? { CGSize(width: 600, height: 112) }

    func expandedView() -> AnyView {
        guard let a = arrivato else { return AnyView(EmptyView()) }
        return AnyView(PromemoriaVista(todo: a,
            fatto: { [weak self] in AnimaCose.shared.spunta(a); self?.dopo() },
            rimanda: { [weak self] in AnimaCose.shared.promemoria(a, Date().addingTimeInterval(600)); self?.dopo() }))
    }

    private func dopo() {
        chiudi?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.ricontrolla() }
    }
}

/// La vista aperta, nella grammatica della riunione: campanella, titolo, ora, due tasti a destra.
struct PromemoriaVista: View {
    let todo: AnimaCose.Todo
    let fatto: () -> Void
    let rimanda: () -> Void
    var body: some View {
        VCard(glow: Volta.a2, breathe: true, padding: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Volta.a2.opacity(Theme.light ? 0.18 : 0.20))
                    Image(systemName: "bell.fill").font(.system(size: 17)).foregroundStyle(Volta.a1)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    VWho(project: T("Promemoria", "Reminder"), what: todo.quando.map { T("alle ", "at ") + OraTesto.hm($0) } ?? "")
                    Text(todo.testo).font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VPill(title: T("Tra 10 min", "In 10 min"), kind: .normal, action: rimanda)
                VPill(title: T("Fatto", "Done"), kind: .primary, action: fatto)
            }
        }
        .frame(height: 112)
    }
}
