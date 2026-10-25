// Fase 4 (20/10/2026): la prossima riunione nel notch. Da 5 minuti prima dell'inizio fino a 10 minuti dopo
// (mai dopo la fine) l'isola compatta mostra la telecamera e quanto manca; aperta, il titolo, l'orario e il tasto Entra.
// La logica pura sta in Core/Riunione.swift, gli eventi li legge CalendarModel (widget.swift) in sola lettura.
import SwiftUI
import AppKit
import Combine

final class RiunioneSource: IslandSource {
    let id = "riunione"
    let priority = 80                       // sopra Claude che lavora (60) e che ha finito (70), sotto Claude che aspetta (90)
    var onChange: (() -> Void)?
    /// L'isola lo imposta: chiude il pannello aperto (anche fissato) dopo Entra o Apri nel Calendario.
    var chiudi: (() -> Void)?
    private let calendario: CalendarModel
    private var timer: Timer?
    private var ascolto: AnyCancellable?
    private var eraAttiva = false

    init(calendario: CalendarModel = .shared) { self.calendario = calendario }

    private var riunione: CalendarModel.Next? { calendario.prossimaRiunione }

    /// L'interruttore "Prossima riunione nel notch" (pagina Isola). Acceso di serie.
    static var enabled: Bool {
        get { Impostazioni.object(.riunioneNelNotch) as? Bool ?? true }
        set { Impostazioni.set(newValue, .riunioneNelNotch) }
    }

    /// Dopo un cambio dell'interruttore: la fonte entra o esce subito dall'isola.
    func rivaluta() {
        if Self.enabled { calendario.aggiornaSeConsentito() }
        ricontrolla(cambiata: true)
    }

    var isActive: Bool {
        guard Self.enabled else { return false }
        guard let r = riunione else { return false }
        return Riunione.visibile(inizio: r.start, fine: r.end, ora: Date())
    }

    /// Timer da 20 s sul filo principale e ascolto del calendario. Il permesso non lo chiede mai (lo chiede la tessera Calendario).
    func start() {
        guard timer == nil else { return }
        ascolto = calendario.$prossimaRiunione.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            // il valore pubblicato arriva prima di essere scritto: si ricontrolla al giro dopo
            DispatchQueue.main.async { self?.ricontrolla(cambiata: true) }
        }
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            guard Self.enabled else { self?.ricontrolla(cambiata: false); return }   // interruttore spento: EventKit non si interroga
            self?.calendario.aggiornaSeConsentito()
            self?.ricontrolla(cambiata: false)
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if Self.enabled { calendario.aggiornaSeConsentito() }
        ricontrolla(cambiata: true)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        ascolto = nil
        eraAttiva = false
    }

    private func ricontrolla(cambiata: Bool) {
        let ora = isActive
        if ora != eraAttiva || (cambiata && ora) {
            eraAttiva = ora
            onChange?()
        }
    }

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: riunione?.link != nil ? "video.fill" : "calendar")
            .font(.system(size: 12, weight: .regular)).foregroundStyle(Volta.a2))
    }

    func compactTrailing() -> AnyView {
        guard let r = riunione else { return AnyView(EmptyView()) }
        return AnyView(TimelineView(.periodic(from: .now, by: 15)) { ctx in
            Text(Riunione.quantoManca(inizio: r.start, ora: ctx.date, inglese: !pulsarItalian))
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Volta.a2)
                .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: 42)
        })
    }

    /// 25/10, l'autore: "ridimensionare". La scheda è alta 112: il pannello finisce lì, niente vuoto sotto.
    var panelSize: CGSize? { CGSize(width: 600, height: 112) }

    func expandedView() -> AnyView {
        guard let r = riunione else { return AnyView(EmptyView()) }
        return AnyView(RiunioneVista(riunione: r, chiudi: { [weak self] in self?.chiudi?() }))
    }
}

/// La vista aperta: una tessera senza contorni, a sinistra la telecamera, al centro titolo e orario, a destra il tasto.
/// `ora` fissa solo per le foto (dati finti); nell'isola vera il tempo scorre.
struct RiunioneVista: View {
    let riunione: CalendarModel.Next
    var ora: Date? = nil
    var chiudi: () -> Void = {}

    private static let ore: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        if let ora { contenuto(ora) } else { TimelineView(.periodic(from: .now, by: 15)) { contenuto($0.date) } }
    }

    private func contenuto(_ adesso: Date) -> some View {
        VCard(glow: Volta.a2, padding: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Volta.a2.opacity(Theme.light ? 0.18 : 0.20))
                    Image(systemName: riunione.link != nil ? "video.fill" : "calendar")
                        .font(.system(size: 18, weight: .regular)).foregroundStyle(Volta.a1)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    VWho(project: T("Riunione", "Meeting"), what: Riunione.quantoManca(inizio: riunione.start, ora: adesso, inglese: !pulsarItalian))
                    Text(riunione.title.isEmpty ? T("Senza titolo", "Untitled") : riunione.title)
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1)
                        .lineLimit(1).truncationMode(.tail)
                    Text(orario).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Volta.t2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let link = riunione.link {
                    VPill(title: T("Entra", "Join"), kind: .primary) { NSWorkspace.shared.open(link); chiudi() }
                } else {
                    VPill(title: T("Apri nel Calendario", "Open in Calendar"), kind: .primary) { Self.apriCalendario(); chiudi() }
                }
            }
        }
        .frame(height: 112)
    }

    private var orario: String {
        let a = Self.ore.string(from: riunione.start), b = Self.ore.string(from: riunione.end)
        return T("dalle \(a) alle \(b)", "\(a) to \(b)")
    }

    /// Apre l'app Calendario (sola lettura: nessun evento toccato).
    static func apriCalendario() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
