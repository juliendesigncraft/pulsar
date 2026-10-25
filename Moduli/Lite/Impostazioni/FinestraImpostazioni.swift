// La finestra Impostazioni di Pulsar (fase 3): barra a sinistra con un'icona per pagina, la pagina a destra.
// Una sola istanza, si apre davanti anche senza icona nel Dock, ricorda la pagina (Chiave.impostazioniPagina).
// Niente NavigationSplitView né List(selection:): disegnano il riquadro di selezione e il materiale di sistema, e
// ImageRenderer non li fotografa. La barra è una colonna di tasti nostri: la pagina scelta ha icona azzurra e testo pieno.
import SwiftUI
import AppKit

enum PaginaImpostazioni: String, CaseIterable {
    case generale, barra, suoni, agent, mixer, isola, lanciatori, voce, rowline, muta, aspetto, permessi, scorciatoie, licenza, info

    var titolo: String {
        switch self {
        case .generale: return T("Generale", "General")
        case .barra: return T("Barra dei menu", "Menu bar")
        case .suoni: return T("Suoni", "Sounds")
        case .agent: return "Claude Code"
        case .mixer: return T("Ghiere", "Dials")
        case .isola: return T("Isola", "Island")
        case .lanciatori: return T("Lanciatori", "Launchers")
        case .voce: return T("Voce", "Voice")
        case .rowline: return "Rowline"
        case .muta: return "Stow"
        case .aspetto: return T("Aspetto", "Appearance")
        case .permessi: return T("Permessi", "Permissions")
        case .scorciatoie: return T("Scorciatoie", "Shortcuts")
        case .licenza: return T("Licenza", "License")
        case .info: return T("Info", "About")
        }
    }

    var simbolo: String {
        switch self {
        case .generale: return "gearshape.fill"
        case .barra: return "menubar.rectangle"
        case .suoni: return "keyboard.fill"
        case .agent: return "sparkle"
        case .mixer: return "dial.medium.fill"
        case .isola: return "capsule.fill"
        case .lanciatori: return "circle.grid.2x2.fill"
        case .voce: return "waveform"
        case .rowline: return "rectangle.split.3x1.fill"
        case .muta: return "tray.and.arrow.down.fill"
        case .aspetto: return "circle.lefthalf.filled"
        case .permessi: return "hand.raised.fill"
        case .scorciatoie: return "command"
        case .licenza: return "key.fill"
        case .info: return "info.circle.fill"
        }
    }

    /// Le pagine non ancora costruite (tolte dalla barra e dalle foto). Dal compito 5 ci sono tutte.
    static let inArrivo: Set<PaginaImpostazioni> = []

    /// Le pagine della barra laterale: la Licenza solo nella vendita (la build personale ha tutto sbloccato).
    static var visibili: [PaginaImpostazioni] {
        allCases.filter { p in
            if inArrivo.contains(p) { return false }
            return true
        }
    }
}

/// La pagina aperta, salvata a ogni cambio.
final class StatoImpostazioni: ObservableObject {
    @Published var pagina: PaginaImpostazioni {
        didSet { Impostazioni.set(pagina.rawValue, .impostazioniPagina) }
    }
    init() {
        let salvata = PaginaImpostazioni(rawValue: Impostazioni.string(.impostazioniPagina) ?? "")
        pagina = salvata.flatMap { PaginaImpostazioni.visibili.contains($0) ? $0 : nil } ?? .generale
    }
}

final class FinestraImpostazioni: NSObject, NSWindowDelegate {
    static let shared = FinestraImpostazioni()

    /// Il cambio d'aspetto della pagina Generale: lo collega AppDelegate allo stesso metodo del menu TEMA.
    var scegliAspetto: (AgentMode) -> Void = { _ in }
    /// La pagina Barra dei menu alterna la Barra pulita con lo stesso metodo del menu: lo collega AppDelegate.
    var alternaBarraPulita: () -> Void = {}
    /// La pagina Aspetto sceglie Dark Matte o White Matte con lo stesso metodo della voce TEMA: lo collega AppDelegate.
    var scegliTema: (PulsarTema) -> Void = { _ in }
    /// I moduli vivi delle pagine Claude Code, Ghiere, Isola, Voce, Muta e Aspetto (compito 5): li mette AppDelegate
    /// all'avvio, così ogni controllo chiama la stessa proprietà o lo stesso metodo della voce di menu. Nil nelle foto da
    /// terminale, dove l'app non è partita: le pagine leggono allora le stesse chiavi salvate e i tasti non fanno niente.
    weak var agent: AgentModule?
    weak var isola: IslandModule?
    weak var griglia: GridModule?
    weak var ghiere: DialModule?
    weak var anima: Anima?
    weak var muta: MutaModule?

    private var finestra: NSWindow?
    private lazy var stato = StatoImpostazioni()

    /// Vero se `oggetto` è la finestra delle Impostazioni (per filtrare le notifiche delle finestre).
    func eLaFinestra(_ oggetto: Any?) -> Bool { finestra != nil && (oggetto as? NSWindow) === finestra }

    func apri(_ p: PaginaImpostazioni? = nil) {
        if let p, PaginaImpostazioni.visibili.contains(p) { stato.pagina = p }
        let w = finestra ?? crea()
        finestra = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func crea() -> NSWindow {
        let w = FinestraConChiudi(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Pulsar"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = false   // i cursori trascinano il valore, non la finestra
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 640, height: 520)
        w.contentMaxSize = NSSize(width: 1400, height: 520)     // solo in larghezza
        w.delegate = self
        w.contentView = NSHostingView(rootView: RadiceImpostazioni(stato: stato))
        w.center()
        return w
    }
}

/// Pulsar non ha il menu dell'app (vive nella barra dei menu): ⌘W lo gestisce la finestra stessa. La usa anche il benvenuto.
/// 24/10: per lo stesso motivo nei campi di testo (pagina Lanciatori) ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z e ⇧⌘Z non arrivavano
/// (l'autore: "non mi lasciava fare copia incolla"): li manda la finestra al campo attivo, come farebbe il menu Modifica.
final class FinestraConChiudi: NSWindow {
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mod = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let tasto = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if mod == .command, tasto == "w" { performClose(nil); return true }
        let azione: Selector? = switch (mod, tasto) {
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
        if let azione, NSApp.sendAction(azione, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: e)
    }
}

/// La radice della finestra viva: segue l'aspetto di Pulsar (GhieraLook) e passa la scala dei colori alle pagine.
private struct RadiceImpostazioni: View {
    @ObservedObject var stato: StatoImpostazioni
    @ObservedObject private var look = GhieraLook.shared

    var body: some View {
        _ = look.mode   // ridisegna al cambio d'aspetto
        return VistaImpostazioni(pagina: $stato.pagina, scala: Volta.Scala(chiaro: Theme.light))
    }
}

/// Barra e pagina. La stessa vista per la finestra e per le foto (FotoImpostazioni), così le foto sono la finestra.
struct VistaImpostazioni: View {
    @Binding var pagina: PaginaImpostazioni
    let scala: Volta.Scala
    var foto = false

    var body: some View {
        HStack(spacing: 0) {
            BarraImpostazioni(pagina: $pagina)
                .frame(width: 200)
                .background(scala.lato)
            contenuto
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scala.pagina)
        }
        .environment(\.matte, scala)
        .environment(\.fotoImpostazioni, foto)
        .environment(\.colorScheme, scala.chiaro ? .light : .dark)
        .font(.system(size: MisureImpostazioni.testo))
    }

    @ViewBuilder private var contenuto: some View {
        switch pagina {
        case .generale: PaginaGenerale()
        case .barra: PaginaBarra()
        case .suoni: PaginaSuoni()
        case .permessi: PaginaPermessi()
        case .scorciatoie: PaginaScorciatoie()
        case .licenza: PaginaLicenza()
        case .info: PaginaInfo()
        case .agent: PaginaAgent()
        case .mixer: PaginaMixer()
        case .isola: PaginaIsola()
        case .voce: PaginaVoce()
        case .rowline: PaginaRowline()
        case .muta: PaginaMuta()
        case .lanciatori: PaginaLanciatori()
        case .aspetto: PaginaAspetto()
        }
    }
}

/// La colonna delle pagine: icona piena e nome. Scelta = icona azzurra e testo pieno, senza riquadro dietro.
private struct BarraImpostazioni: View {
    @Binding var pagina: PaginaImpostazioni
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto

    var body: some View {
        // nelle foto la pagina fotografata compare anche se nella build non è in barra (la Licenza nella personale)
        let voci = PaginaImpostazioni.visibili.contains(pagina) || !foto ? PaginaImpostazioni.visibili
            : PaginaImpostazioni.allCases.filter { PaginaImpostazioni.visibili.contains($0) || $0 == pagina }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(voci, id: \.self) { p in
                let scelta = p == pagina
                Button { pagina = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.simbolo)
                            .font(.system(size: 14))
                            .foregroundStyle(scelta ? m.a2 : m.t3)
                            .frame(width: 20)
                        Text(p.titolo)
                            .font(.system(size: MisureImpostazioni.testo))
                            .foregroundStyle(scelta ? m.t1 : m.t2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 52)          // sotto i tre bottoni della finestra
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
