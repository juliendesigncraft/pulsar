// Pulsar — il pannello a schede della barra dei menu (12/11/2026, ondata 1 di VORSSAINT.md).
// l'autore: "il menù a comparsa ridurlo affinché risulti così" (reel dell'app del notch a schede). Al posto del menu
// lungo, un pannello con la punta sotto l'icona: largo 300 pt, in alto le schede a icone, sotto righe a card.
// Le voci NON sono riscritte: il pannello legge il menu completo che Pulsar costruiva già (buildFullMenu) e ogni riga
// manda la stessa azione della voce di menu, con la voce come mittente. Così nessuna funzione si perde e le voci nuove
// del menu compaiono da sole nella scheda giusta. Il vecchio menu resta in fondo: "Menu completo".
// I colori vengono da Volta (Core/Tema.swift): Carbone, Dark Matte o White Matte, come il resto di Pulsar.
import AppKit
import SwiftUI

// MARK: - Dati

/// Una riga: una voce del menu completo, oppure un tasto rapido (QuickTile).
struct VocePannello: Identifiable {
    let id = UUID()
    let titolo: String
    let simbolo: String?            // SF Symbol, per i tasti rapidi
    let immagine: NSImage?          // l'immagine della voce di menu (icone delle app, cartelle)
    let acceso: Bool?               // nil = azione, non interruttore
    let nascosta: Bool              // le app in background spente: si vedono solo con "Mostra spente"
    let figli: [VocePannello]       // le voci con sottomenu (Altre cartelle…)
    let esegui: () -> Void
}

struct GruppoPannello: Identifiable {
    let id = UUID()
    let titolo: String?
    let voci: [VocePannello]
}

struct SchedaPannello: Identifiable {
    let id: String
    let titolo: String
    let simbolo: String
    let gruppi: [GruppoPannello]
    /// 13/11: le schede con una vista loro (Sistema, Rete, Manutenzione) e la loro altezza massima.
    var vista: AnyView? = nil
    var altezza: CGFloat = 400
}

struct DatiPannello {
    var schede: [SchedaPannello]
    var piede: [VocePannello]       // Impostazioni, Licenza, Esci… (le voci fuori sezione)
}

// MARK: - Dal menu alle schede

enum LettorePannello {
    /// Trasforma una voce di menu in riga. `chiudi` chiude il pannello prima delle azioni che aprono finestre.
    static func voce(_ item: NSMenuItem, chiudi: @escaping () -> Void, ricarica: @escaping () -> Void) -> VocePannello? {
        if item.isSeparatorItem || item.view != nil { return nil }       // le righe disegnate a mano (Mostra tutte) le rifà il pannello
        let figli = item.submenu?.items.compactMap { voce($0, chiudi: chiudi, ricarica: ricarica) } ?? []
        let interruttore = item.state == .on || (item.state == .off && item.action != nil && figli.isEmpty && Self.sembraInterruttore(item))
        return VocePannello(
            titolo: item.title,
            simbolo: nil,
            immagine: item.image,
            acceso: interruttore ? item.state == .on : nil,
            nascosta: item.isHidden,
            figli: figli,
            esegui: {
                guard let a = item.action else { return }
                if interruttore {
                    NSApp.sendAction(a, to: item.target, from: item)
                    // lo stato nuovo si legge rifacendo il menu, un attimo dopo (alcune azioni lanciano comandi)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: ricarica)
                } else {
                    chiudi()
                    DispatchQueue.main.async { NSApp.sendAction(a, to: item.target, from: item) }
                }
            })
    }

    /// Le voci di menu con la spunta possibile (toggle in main.swift) hanno sempre uno stato; quelle d'azione hanno
    /// l'immagine e lo stato .off. Si distinguono dal fatto che il menu le crea con `toggle(...)`: segnate qui.
    static func sembraInterruttore(_ item: NSMenuItem) -> Bool { item.identifier?.rawValue == "pulsar.interruttore" }

    /// Il menu completo (con le intestazioni in maiuscolo) diviso in sezioni: (intestazione o nil, voci).
    static func sezioni(_ menu: NSMenu) -> [(String?, [NSMenuItem])] {
        var out: [(String?, [NSMenuItem])] = []
        var titolo: String? = nil
        var voci: [NSMenuItem] = []
        func chiudiSezione() { if titolo != nil || !voci.isEmpty { out.append((titolo, voci)) }; titolo = nil; voci = [] }
        for item in menu.items {
            if item.isSeparatorItem { chiudiSezione(); continue }
            // il conteggio tra parentesi ("APP IN BACKGROUND (2 attive / 3)") ha lettere minuscole: si guarda solo il nome
            let t = item.title.components(separatedBy: "(").first ?? item.title
            let intestazione = !item.isEnabled && item.action == nil && item.submenu == nil && item.view == nil
                && t == t.uppercased() && t.rangeOfCharacter(from: .letters) != nil
            if intestazione { chiudiSezione(); titolo = item.title; continue }
            voci.append(item)
        }
        chiudiSezione()
        return out
    }
}

// MARK: - Stato

final class StatoPannello: ObservableObject {
    @Published var dati = DatiPannello(schede: [], piede: [])
    @Published var scheda = "rapidi"
    @Published var mostraSpente = false
    @Published var vetro = false
}

// MARK: - Il pannello

final class PannelloBarra: NSObject, NSPopoverDelegate {
    static let shared = PannelloBarra()
    let stato = StatoPannello()
    private let popover = NSPopover()
    /// L'ancora invisibile per quando la barra dei menu è nascosta (app a tutto schermo).
    private lazy var ancora: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = .statusBar; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSView()
        return p
    }()
    /// AppDelegate dà i dati freschi a ogni apertura (stessi stati del menu).
    var fornisci: (() -> DatiPannello)?
    var aperto: Bool { popover.isShown }

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: VistaPannello(stato: stato))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    func mostra(da bottone: NSStatusBarButton) {
        ultimoBottone = bottone
        ricarica()
        popover.appearance = NSAppearance(named: Theme.light ? .aqua : .darkAqua)
        // Con un'app a tutto schermo la barra dei menu è nascosta e l'icona sta fuori dallo schermo (misurato il 12/11:
        // il pannello finiva in alto a sinistra). Allora ci si attacca a un'ancora invisibile nello stesso punto, sotto la barra.
        if let f = bottone.window?.frame, let sc = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: f.midX, y: $0.frame.midY)) }),
           f.minY >= sc.frame.maxY - 1 {     // l'icona sta sopra il bordo dello schermo: barra nascosta
            ancora.setFrame(NSRect(x: f.minX, y: sc.frame.maxY - 34, width: f.width, height: 2), display: false)
            ancora.orderFrontRegardless()
            popover.show(relativeTo: ancora.contentView!.bounds, of: ancora.contentView!, preferredEdge: .minY)
        } else {
            popover.show(relativeTo: bottone.bounds, of: bottone, preferredEdge: .minY)
        }
        colora()
        popover.contentViewController?.view.window?.makeKey()
    }

    func chiudi() { popover.performClose(nil) }

    private weak var ultimoBottone: NSStatusBarButton?
    /// Riapre il pannello su una scheda (dopo una finestra di scelta, come Disinstalla).
    func riapriSu(_ scheda: String) {
        stato.scheda = scheda
        if let b = ultimoBottone, !popover.isShown { mostra(da: b) }
    }

    func ricarica() { if let f = fornisci { stato.dati = f() } }

    /// La cornice del popover (punta compresa) prende il fondo del tema: senza, macOS mette il suo vetro.
    private func colora() {
        guard let cornice = popover.contentViewController?.view.superview else { return }
        cornice.wantsLayer = true
        // 12/11, l'autore: "gli effetti vetro sui menu, se sono attivati". Acceso: il fondo del tema al 72% sopra il vetro di macOS.
        let vetro = Impostazioni.bool(.vetroPannelli)
        cornice.layer?.backgroundColor = NSColor(Volta.Scala(chiaro: Theme.light).body).withAlphaComponent(vetro ? 0.72 : 1).cgColor
        stato.vetro = vetro
    }

    func popoverDidClose(_ notification: Notification) { stato.mostraSpente = false; ancora.orderOut(nil) }
}

// MARK: - Viste

struct VistaPannello: View {
    @ObservedObject var stato: StatoPannello
    @ObservedObject private var look = GhieraLook.shared
    /// Le foto (pulsar://foto-pannello) passano il tema da fotografare; dal vivo vale quello in uso.
    var forza: Volta.Scala? = nil
    private var s: Volta.Scala { forza ?? Volta.Scala(chiaro: Theme.light) }
    private var chiaro: Bool { s.chiaro }

    var body: some View {
        let schede = stato.dati.schede
        let attiva = schede.first { $0.id == stato.scheda } ?? schede.first
        VStack(spacing: 0) {
            // il segno di Pulsar in alto, piccolo
            Image(nsImage: Icons.toggle()).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 22, height: 22).foregroundStyle(s.t1)
                .padding(.top, 14).padding(.bottom, 12)
            barraSchede(schede, attiva: attiva?.id)
            if let a = attiva {
                HStack {
                    Text(a.titolo.uppercased()).font(.system(size: 10, weight: .medium)).tracking(1.1).foregroundStyle(s.t3)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                let righe = VStack(alignment: .leading, spacing: 6) {
                    if let v = a.vista { v } else { ForEach(a.gruppi) { g in gruppo(g) } }
                }
                .padding(.horizontal, 12).padding(.bottom, 4)
                if forza != nil {
                    righe        // le foto: ImageRenderer non disegna dentro una ScrollView
                } else if a.vista != nil {
                    ScrollView(.vertical, showsIndicators: false) { righe }.frame(height: a.altezza)
                } else {
                    ScrollView(.vertical, showsIndicators: false) { righe }
                        .frame(height: min(400, altezza(a)))
                }
            }
            piede
        }
        .frame(width: 300)
        .background(stato.vetro && forza == nil ? Color.clear : s.body)
        .environment(\.colorScheme, chiaro ? .light : .dark)
        .environment(\.matte, s)          // 13/11: le schede con una vista loro prendono la stessa scala
    }

    /// L'altezza delle righe di una scheda (36 pt + 6 di spazio, i titoli dei gruppi 23 pt), così il pannello è alto quanto serve.
    private func altezza(_ a: SchedaPannello) -> CGFloat {
        var h: CGFloat = 4
        for g in a.gruppi {
            if g.titolo != nil { h += 23 }
            let n = g.voci.filter { !$0.nascosta || stato.mostraSpente }.count
            h += CGFloat(n) * 42
            if g.voci.contains(where: \.nascosta) { h += 32 }
        }
        return h
    }

    private func barraSchede(_ schede: [SchedaPannello], attiva: String?) -> some View {
        HStack(spacing: 2) {
            ForEach(schede) { sc in
                Button { stato.scheda = sc.id; stato.mostraSpente = false } label: {
                    Image(systemName: sc.simbolo).font(.system(size: 13, weight: .regular))
                        .foregroundStyle(sc.id == attiva ? s.t1 : s.t2)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(sc.id == attiva ? s.card2 : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(sc.titolo)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.card.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(chiaro ? 0 : 0.06), lineWidth: 1))
        .padding(.horizontal, 12)
    }

    @ViewBuilder private func gruppo(_ g: GruppoPannello) -> some View {
        if let t = g.titolo {
            Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(s.t2).padding(.leading, 4).padding(.top, 6)
        }
        let visibili = g.voci.filter { !$0.nascosta || stato.mostraSpente }
        ForEach(visibili) { v in RigaPannello(voce: v, s: s) }
        let spente = g.voci.filter(\.nascosta).count
        if spente > 0 {
            Button { stato.mostraSpente.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: stato.mostraSpente ? "chevron.up" : "chevron.down").font(.system(size: 10))
                    Text(stato.mostraSpente ? T("Riduci", "Show less") : T("Mostra spente (\(spente))", "Show stopped (\(spente))"))
                        .font(.system(size: 11.5))
                    Spacer()
                }
                .foregroundStyle(s.t2).padding(.horizontal, 6).frame(height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var piede: some View {
        HStack(spacing: 4) {
            ForEach(stato.dati.piede) { v in
                Button(action: v.esegui) {
                    Text(v.titolo).font(.system(size: 11.5)).foregroundStyle(s.t2).lineLimit(1)
                        .padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 10).padding(.horizontal, 8)
    }
}

private struct RigaPannello: View {
    let voce: VocePannello
    let s: Volta.Scala
    @State private var sopra = false
    @State private var aperta = false

    var body: some View {
        VStack(spacing: 4) {
            Button {
                if voce.figli.isEmpty { voce.esegui() } else { withAnimation(.easeOut(duration: 0.18)) { aperta.toggle() } }
            } label: {
                HStack(spacing: 10) {
                    icona.frame(width: 18, height: 18)
                    Text(voce.titolo).font(.system(size: 12.5, weight: .medium)).foregroundStyle(s.t1).lineLimit(1)
                    Spacer(minLength: 6)
                    if let on = voce.acceso {
                        InterruttorePannello(on: on, s: s)
                    } else if !voce.figli.isEmpty {
                        Image(systemName: aperta ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(s.t3)
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(s.t3)
                    }
                }
                .padding(.horizontal, 10).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sopra ? s.card2 : s.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(s.chiaro ? 0 : 0.06), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { sopra = $0 }
            if aperta {
                ForEach(voce.figli) { f in RigaPannello(voce: f, s: s).padding(.leading, 14) }
            }
        }
    }

    @ViewBuilder private var icona: some View {
        if let n = voce.simbolo {
            Image(systemName: n).font(.system(size: 13)).foregroundStyle(s.t2)
        } else if let im = voce.immagine {
            if im.isTemplate {
                Image(nsImage: im).renderingMode(.template).foregroundStyle(s.t2)
            } else if let cg = im.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: 2)]) {
                // le icone di app e cartelle si disegnano in pixel: così escono anche nelle foto (ImageRenderer)
                Image(decorative: cg, scale: 2).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(nsImage: im).resizable().scaledToFit()
            }
        } else {
            Color.clear
        }
    }
}

/// Interruttore monocromo (Carbone): binario chiaro e pallino scuro acceso, binario grigio e pallino grigio spento.
private struct InterruttorePannello: View {
    let on: Bool
    let s: Volta.Scala
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? s.prim : s.t3.opacity(0.45)).frame(width: 30, height: 18)
            Circle().fill(on ? s.primT : s.t2).frame(width: 14, height: 14).padding(2)
        }
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - Foto (12/11): ogni scheda in ogni tema, PNG a scala 2, senza aprire il pannello
// pulsar://foto-pannello → Cartelle.dati/foto-pannello/<scheda>-<tema>.png. Servono a controllare il tema senza cliccare.
enum FotoPannello {
    @MainActor static func scatta(dati: DatiPannello, in cartella: URL) {
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        for tema in PulsarTema.allCases {
            let scala = Volta.Scala(chiaro: tema.chiaro, carbone: tema == .carbone)
            for sc in dati.schede {
                let st = StatoPannello(); st.dati = dati; st.scheda = sc.id
                let r = ImageRenderer(content: VistaPannello(stato: st, forza: scala))
                r.scale = 2
                guard let im = r.nsImage, let tiff = im.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: cartella.appendingPathComponent("\(sc.id)-\(tema.rawValue).png"))
            }
        }
    }
}
