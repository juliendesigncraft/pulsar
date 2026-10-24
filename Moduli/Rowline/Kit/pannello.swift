// Rowline — il PANNELLO (14/10/2026). Stile Pulsar: lo stesso blu grafite dell'aspetto Notte (Dark Matte) e i toni chiari
// di White Matte, letti da ~/Library/Application Support/Pulsar/tema.json. Titolo e interfaccia in SF (stile Apple, 14/10),
// azzurro come unico accento, righe-dato per le scorciatoie, icone invece di parole dove si può.
// Si apre dall'icona nella barra dei menu, con ⌃⌥⌘F, o riaprendo Rowline dal Launchpad o da Spotlight.
// Schede: Fila (mappa e comandi), Postazioni, Scorciatoie, Regole, Come funziona. Testi in italiano o inglese (T).

import AppKit
import SwiftUI

// MARK: - Tema (segue Pulsar)

final class Tinta: ObservableObject {
    static let shared = Tinta()
    @Published var chiaro = false
    private var file: URL { Archivio.cartellaPulsar.appendingPathComponent("tema.json") }   // 19/10: la cartella dati di Pulsar

    init() {
        leggi()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name(Archivio.id + ".tema"), object: nil, queue: .main) { [weak self] _ in self?.leggi() }
    }
    /// Ripresa del reel: il tema si sceglie da RowlineDemo (comando "tema:chiaro"), il Mac dell'autore non cambia.
    var forzato: Bool? { didSet { if let f = forzato { chiaro = f } else { leggi() } } }

    func leggi() {
        if let f = forzato { chiaro = f; return }
        guard let d = try? Data(contentsOf: file), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        chiaro = (j["chiaro"] as? Bool) ?? false
    }

    private func c(_ h: UInt32) -> Color { Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255) }
    var alto: Color { chiaro ? c(0xF6F7F9) : c(0x2B2E3C) }
    var basso: Color { chiaro ? c(0xEEF0F3) : c(0x22252F) }
    var testo: Color { chiaro ? c(0x1E2028) : .white }
    var t2: Color { testo.opacity(0.56) }
    var t3: Color { testo.opacity(chiaro ? 0.42 : 0.34) }
    var linea: Color { testo.opacity(chiaro ? 0.10 : 0.08) }
    var velo: Color { Color.black.opacity(chiaro ? 0.05 : 0.16) }
    var sel: Color { Color.black.opacity(chiaro ? 0.10 : 0.28) }
    var azzurro: Color { chiaro ? c(0x3B82D0) : c(0x8FC7FF) }
    var schema: ColorScheme { chiaro ? .light : .dark }
}

// MARK: - La finestra

final class PannelloFinestra: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Pannello: NSObject, NSWindowDelegate {
    static let shared = Pannello()
    private var finestra: PannelloFinestra?
    private var controllore: NSHostingController<AnyView>?
    weak var bottone: NSStatusBarButton?
    let stato = StatoPannello()

    func alterna() { (finestra?.isVisible ?? false) ? chiudi() : apri() }

    func apri() {
        if finestra == nil {
            let p = PannelloFinestra(contentRect: NSRect(x: 0, y: 0, width: 392, height: 520),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false               // l'ombra di sistema disegna anche un filo scuro intorno (14/10, "togli il bordo nero"): la fa la vista
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.delegate = self
            let hc = NSHostingController(rootView: AnyView(VistaPannello().environmentObject(Motore.shared).environmentObject(Tasti.shared)
                                        .environmentObject(Tinta.shared).environmentObject(stato)))
            hc.sizingOptions = []            // la misura la decide posiziona(), anche quando cambia scheda
            controllore = hc
            p.contentView = hc.view
            finestra = p
        }
        guard let p = finestra else { return }
        Tinta.shared.leggi()
        Motore.shared.aggiornaMappa()
        p.layoutIfNeeded()
        posiziona(p)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.22; p.animator().alphaValue = 1 }
    }

    /// Cambiando lingua il pannello si ricostruisce (i testi si leggono quando si disegna).
    func ricostruisci() {
        let aperto = finestra?.isVisible ?? false
        finestra?.orderOut(nil); finestra = nil; controllore = nil
        if aperto { apri() }
    }

    /// Cambio di scheda: la finestra prende la misura nuova restando appesa sotto l'icona.
    func ridimensiona() { if let p = finestra, p.isVisible { posiziona(p) } }

    private func posiziona(_ p: NSPanel) {
        // misurare dopo l'impaginazione: prima di questo la finestra nasceva 0 x 0 e non si vedeva (14/10 sera)
        var size = controllore?.sizeThatFits(in: NSSize(width: 448, height: 2000)) ?? .zero
        if size.width < 50 || size.height < 50 { size = NSSize(width: 448, height: 616) }
        if Motore.shared.soloPid != nil, let sc = NSScreen.main {
            // ripresa del reel: sotto l'icona della barra finta di RowlineDemo (centro a 250 pt dal bordo destro)
            p.setFrame(NSRect(x: sc.frame.maxX - 250 - size.width / 2, y: sc.visibleFrame.maxY + 20 - size.height, width: size.width, height: size.height), display: true)
        } else if let b = bottone, let w = b.window {
            let r = w.convertToScreen(b.convert(b.bounds, to: nil))
            let sc = w.screen ?? NSScreen.main!
            let x = min(max(sc.visibleFrame.minX + 8, r.midX - size.width / 2), sc.visibleFrame.maxX - size.width - 8)
            p.setFrame(NSRect(x: x, y: r.minY + 20 - size.height, width: size.width, height: size.height), display: true)
        } else if let sc = NSScreen.main {
            p.setFrame(NSRect(x: sc.visibleFrame.maxX - size.width - 12, y: sc.visibleFrame.maxY - size.height - 8, width: size.width, height: size.height), display: true)
        }
    }

    func chiudi() {
        stato.fermaRegistrazione()
        guard let p = finestra else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    func windowDidResignKey(_ notification: Notification) {
        if stato.registra == nil && Motore.shared.soloPid == nil { chiudi() }
    }
}

/// Lo stato del pannello: la scheda aperta e la scorciatoia che si sta registrando.
final class StatoPannello: ObservableObject {
    enum Scheda: String, CaseIterable { case fila, postazioni, tasti, regole, guida
        var simbolo: String { ["fila": "rectangle.split.3x1", "postazioni": "square.stack", "tasti": "command", "regole": "slider.horizontal.3", "guida": "questionmark"][rawValue]! }
        var titolo: String { ["fila": T("Fila", "Row"), "postazioni": T("Postazioni", "Workspaces"), "tasti": T("Scorciatoie", "Shortcuts"), "regole": T("Regole", "Settings"), "guida": T("Come funziona", "How it works")][rawValue]! }
    }
    @Published var scheda: Scheda = Archivio.d.bool(forKey: "guidaVista") ? .fila : .guida {
        didSet { DispatchQueue.main.async { Pannello.shared.ridimensiona() } }
    }
    init() { Archivio.d.set(true, forKey: "guidaVista") }
    @Published var registra: Azione?
    private var monitor: Any?

    func registra(_ a: Azione) {
        fermaRegistrazione()
        registra = a
        Tasti.shared.sospendi()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let a = self.registra else { return e }
            if e.keyCode == 53 { self.fermaRegistrazione(); return nil }                 // Esc: lascia com'era
            let c = Combo.da(e)
            // serve almeno uno fra ⌘, ⌥ e ⌃, se no la scorciatoia ruberebbe una lettera a tutte le app
            guard c.mod & UInt32(0x0100 | 0x0800 | 0x1000) != 0 else { NSSound.beep(); return nil }
            Tasti.shared.cambia(a, c)
            self.fermaRegistrazione()
            return nil
        }
    }

    func fermaRegistrazione() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if registra != nil { registra = nil; Tasti.shared.registra() }
    }
}

// MARK: - Icone delle app (con memoria)

enum Icone {
    private static var cache: [String: NSImage] = [:]
    static func di(_ bundle: String) -> NSImage {
        if let i = cache[bundle] { return i }
        let i = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        cache[bundle] = i
        return i
    }
    static func nome(_ b: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: b).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? b
    }
}

// MARK: - Le viste

struct VistaPannello: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var s: StatoPannello

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            testa
            if !m.fidato { permesso.padding(.top, 16) }
            Group {
                switch s.scheda {
                case .fila: VistaFila()
                case .postazioni: VistaPostazioni()
                case .tasti: VistaTasti()
                case .regole: VistaRegole()
                case .guida: VistaGuida()
                }
            }
            .padding(.top, 18)
            piede.padding(.top, 18)
        }
        .padding(20)
        .frame(width: 392)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [t.alto, t.basso], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(t.chiaro ? 0.065 : 0.09), radius: t.chiaro ? 11 : 8, y: 1.5)   // 19/10: l'ombra minima di Pulsar (Ombra)
        )
        .padding(28)                          // spazio per l'ombra morbida
        .foregroundStyle(t.testo)
        .environment(\.colorScheme, t.schema)
        .animation(.easeOut(duration: 0.25), value: s.scheda)
    }

    private var testa: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rowline").font(.system(size: 20, weight: .regular))   // come i titoli delle Impostazioni di Pulsar
                    Text(m.acceso ? (m.quante == 1 ? T("1 finestra in fila", "1 window in the row") : T("\(m.quante) finestre in fila", "\(m.quante) windows in the row"))
                                  : T("Spenta, le finestre sono libere", "Off, windows are free"))
                        .font(.system(size: 12)).foregroundStyle(t.t2)
                }
                Spacer()
                Interruttore(acceso: m.acceso) { m.acceso.toggle() }
                    .help(T("Accendi o spegni Rowline (⌃⌥⌘P)", "Turn Rowline on or off (⌃⌥⌘P)"))
            }
            HStack(spacing: 2) {
                ForEach(StatoPannello.Scheda.allCases, id: \.self) { k in
                    Bottone(simbolo: k.simbolo, acceso: s.scheda == k, aiuto: k.titolo) { s.scheda = k }
                }
            }
            .padding(3)
            .background(Capsule().fill(t.velo))
        }
    }

    private var permesso: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised").font(.system(size: 15)).foregroundStyle(t.azzurro)
            VStack(alignment: .leading, spacing: 2) {
                Text(T("Serve un permesso", "One permission needed")).font(.system(size: 13))
                Text(T("Accessibilità, per spostare le finestre", "Accessibility, to arrange windows")).font(.system(size: 11)).foregroundStyle(t.t2)
            }
            Spacer()
            Button(T("Apri", "Open")) {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(Pillola(principale: true))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.velo))
    }

    private var piede: some View {
        HStack {
            Button { m.adotta() } label: { Label(T("Riordina", "Tidy up"), systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(Pillola()).help(T("Rimette in fila le finestre visibili, da sinistra a destra", "Puts the visible windows back in a row, left to right"))
            Spacer()
            // 19/10: dentro Pulsar "Esci" avrebbe chiuso tutta Pulsar. Al suo posto la pagina di Rowline nelle Impostazioni.
            Button { Pannello.shared.chiudi(); Archivio.apriImpostazioni?() } label: { Label(T("Impostazioni", "Settings"), systemImage: "gearshape") }
                .buttonStyle(Pillola())
        }
    }
}

/// La mappa: ogni schermo è una fila di tessere larghe come le finestre vere; il riquadro chiaro è quello che vedi.
struct VistaFila: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if m.mappa.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.3x1").font(.system(size: 22, weight: .light)).foregroundStyle(t.t3)
                    Text(m.acceso ? T("Nessuna finestra in fila", "No windows in the row") : T("Rowline è spenta", "Rowline is off"))
                        .font(.system(size: 13)).foregroundStyle(t.t2)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.velo))
            }
            ForEach(m.mappa) { st in RigaStriscia(st: st) }
            comandi
        }
    }

    private var comandi: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach([Azione.precedente, .successiva, .spostaSx, .spostaDx, .centra, .galleggia, .griglia]) { a in Comando(a: a) }
            }
            HStack(spacing: 6) {
                ForEach([Azione.stringi, .meta, .dueTerzi, .intera, .allarga, .impila]) { a in
                    Comando(a: a, testo: a == .meta ? "½" : a == .dueTerzi ? "⅔" : a == .intera ? "1" : nil)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// La mappa (14/10 sera, l'autore: "le schede sovrapposte così mhhh"): niente riquadro sopra le tessere. Come la barra in basso:
/// tessere staccate da uno spazio, piene quelle che si vedono sullo schermo, spente quelle fuori vista.
struct RigaStriscia: View {
    let st: StrisciaVista
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    private let alt: CGFloat = 92

    var body: some View {
        let k = alt / max(st.alta, 1)       // da punti dello schermo a punti della mappa
        let totale = (st.colonne.last.map { $0.x + $0.w } ?? 0) * k
        VStack(alignment: .leading, spacing: 8) {
            if !st.nome.isEmpty { Text(st.nome).font(.system(size: 11)).foregroundStyle(t.t3) }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        ForEach(st.colonne) { c in
                            let dentro = c.x + c.w > st.scorrimento + 8 && c.x < st.scorrimento + st.vista - 8
                            VStack(spacing: 4) {
                                ForEach(Array(c.finestre.enumerated()), id: \.element.id) { j, f in
                                    Tessera(f: f, fuoco: c.fuoco && j == c.attiva)
                                }
                            }
                            .frame(width: max(c.w * k - 6, 18), height: alt)
                            .opacity(dentro ? 1 : 0.4)
                            .offset(x: c.x * k + 3)
                            .id(c.id)
                        }
                    }
                    .frame(width: max(totale, st.vista * k) + 6, height: alt, alignment: .topLeading)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.scorrimento)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.colonne.map(\.w))
                }
                .onAppear { if let f = st.colonne.first(where: \.fuoco) { proxy.scrollTo(f.id, anchor: .center) } }
            }
        }
    }
}

struct Tessera: View {
    let f: TesseraVista
    let fuoco: Bool
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @State private var sopra = false

    var body: some View {
        Button { m.scegli(f.id) } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                // 19/10: niente contorni (regola del notch), la finestra attiva è solo un fondo azzurro
                .fill(fuoco ? t.azzurro.opacity(t.chiaro ? 0.32 : 0.30) : (sopra ? t.sel : t.velo))
                .overlay(Image(nsImage: Icone.di(f.bundle)).resizable().interpolation(.high).frame(width: 22, height: 22))
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help(f.app)
    }
}

struct Comando: View {
    let a: Azione
    var testo: String? = nil
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var k: Tasti
    @State private var sopra = false

    var body: some View {
        Button { a.esegui() } label: {
            Group {
                if let testo { Text(testo).font(.system(size: 15, weight: .light)) }
                else { Image(systemName: a.simbolo).font(.system(size: 13, weight: .regular)) }
            }
            .frame(maxWidth: .infinity).frame(height: 36)     // 19/10: i tasti si dividono la larghezza, la prima fila usciva dal pannello
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sopra ? t.sel : t.velo))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help("\(a.titolo)  \(k.combo[a]?.testo ?? "")")
    }
}

/// Le postazioni: una fila salvata (app, ordine, larghezze) che si rimette con un clic o con ⌃⌥⌘4, 5, 6.
struct VistaPostazioni: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var k: Tasti
    @State private var nome = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if m.postazioni.isEmpty {
                Text(T("Metti le finestre come ti piacciono, dai un nome e salva. Poi un clic le rimette così, aprendo le app che mancano.",
                       "Arrange your windows the way you like, name it and save. One click brings it back, opening any missing apps."))
                    .font(.system(size: 12)).foregroundStyle(t.t2).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }
            ForEach(Array(m.postazioni.enumerated()), id: \.element.id) { i, p in riga(p, i) }
            HStack(spacing: 8) {
                TextField(T("Nome, per esempio Studio", "Name, for example Study"), text: $nome)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(t.velo))
                    .onSubmit(salva)
                Button(T("Salva la fila", "Save the row"), action: salva).buttonStyle(Pillola(principale: true)).disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 14)
        }
    }

    private func salva() {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        m.salvaPostazione(n); nome = ""
    }

    private func riga(_ p: Postazione, _ i: Int) -> some View {
        let a: Azione? = i == 0 ? .postazione1 : i == 1 ? .postazione2 : i == 2 ? .postazione3 : nil
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.nome).font(.system(size: 14))
                    HStack(spacing: 4) {
                        ForEach(Array(p.posti.enumerated()), id: \.offset) { _, x in
                            Image(nsImage: Icone.di(x.bundle)).resizable().frame(width: 16, height: 16).help(x.app)
                        }
                    }
                }
                Spacer()
                if let a, let c = k.combo[a], c.mod != 0 { Text(c.testo).font(.system(size: 12)).foregroundStyle(t.t3) }
                Bottone(simbolo: "play.fill", acceso: false, aiuto: T("Rimetti questa fila", "Bring this row back")) { m.applica(p) }
                Bottone(simbolo: "xmark", acceso: false, aiuto: T("Elimina", "Delete")) { m.postazioni.removeAll { $0.id == p.id } }
            }
            .frame(height: 56)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}

/// Le scorciatoie come righe-dato: azione a sinistra, tasti a destra. Un clic sulla riga e si registrano i tasti nuovi.
struct VistaTasti: View {
    @EnvironmentObject var k: Tasti
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var s: StatoPannello

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Azione.allCases) { a in riga(a) }
                }
            }
            .frame(height: 330)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            HStack {
                Text(T("Un clic su una riga, poi i tasti nuovi. Esc annulla.", "Click a row, then press the new keys. Esc cancels.")).font(.system(size: 11)).foregroundStyle(t.t3)
                Spacer()
                Button(T("Di serie", "Defaults")) { k.ripristina() }.buttonStyle(Pillola())
            }
            .padding(.top, 10)
            Text(T("Tieni premuti ⌃⌥⌘ per un secondo: compare il foglio con tutte le scorciatoie.", "Hold ⌃⌥⌘ for a second to see every shortcut."))
                .font(.system(size: 11)).foregroundStyle(t.t3).padding(.top, 8)
        }
    }

    private func riga(_ a: Azione) -> some View {
        let reg = s.registra == a
        return Button { reg ? s.fermaRegistrazione() : s.registra(a) } label: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: a.simbolo).font(.system(size: 12)).foregroundStyle(t.t3).frame(width: 22)
                    Text(a.titolo).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(reg ? T("Premi i tasti", "Press the keys") : (k.combo[a].map { $0.mod == 0 ? T("Nessuna", "None") : $0.testo } ?? ""))
                        .font(.system(size: 12)).foregroundStyle(reg ? t.azzurro : t.t2)
                }
                .frame(height: 40)
                Rectangle().fill(t.linea).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct VistaRegole: View {
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @ObservedObject private var barra = Barra.shared
    @ObservedObject private var gesto = Gesto.shared
    @ObservedObject private var ant = Anteprime.shared
    @State private var tasti = TastiVisti.shared.acceso
    @State private var lingua = linguaInglese ? "en" : "it"
    @State private var griglia = Reticolo.misura

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                riga("hand.draw", T("Scorri col trackpad", "Trackpad swipe"), Picker("", selection: $gesto.modo) {
                    ForEach(ModoGesto.allCases, id: \.self) { Text($0.titolo).tag($0) }
                }.pickerStyle(.menu).frame(width: 150))
                if gesto.modo.dita > 0 && ModoGesto.usateDalSistema(gesto.modo.dita) {
                    Text(T("macOS usa già \(gesto.modo.dita) dita per cambiare Scrivania: scegli l'altro numero, o cambialo in Impostazioni → Trackpad → Altri gesti.",
                           "macOS already uses \(gesto.modo.dita) fingers to switch desktops: pick the other number, or change it in Settings → Trackpad → More Gestures."))
                        .font(.system(size: 11)).foregroundStyle(t.t2).padding(.vertical, 8)
                }
                riga("arrow.left.arrow.right", T("Inverti il verso", "Reverse direction"), Toggle("", isOn: $gesto.inverti))
                riga("wind", T("Animazioni", "Animations"), Toggle("", isOn: $m.animazioni))
                riga("slider.horizontal.below.rectangle", T("Barra in basso", "Bottom slider"), Picker("", selection: $barra.modo) {
                    ForEach(ModoBarra.allCases, id: \.self) { Text($0.titolo).tag($0) }
                }.pickerStyle(.menu).frame(width: 150))
                riga("photo", T("Anteprime nella barra", "Previews in the slider"), Toggle("", isOn: $ant.accese))
                if ant.accese && !ant.permesso {
                    Text(T("Servono le anteprime: Impostazioni → Privacy → Registrazione schermo → Rowline.", "Needs Settings → Privacy → Screen Recording → Rowline."))
                        .font(.system(size: 11)).foregroundStyle(t.t2).padding(.vertical, 8)
                }
                riga("square.grid.3x3", T("Griglia (⌃⌥⌘G)", "Grid (⌃⌥⌘G)"), Picker("", selection: $griglia) {
                    ForEach(Reticolo.misure, id: \.self) { Text($0.replacingOccurrences(of: "x", with: " × ")).tag($0) }
                }.pickerStyle(.menu).frame(width: 150).onChange(of: griglia) { _, v in Archivio.d.set(v, forKey: "griglia") })
                riga("square.split.2x1", T("Margine fra le finestre", "Gap between windows"), cursore($m.margine, 0...24, 2))
                riga("rectangle.lefthalf.inset.filled.arrow.left", T("Finestre vicine che sbucano", "Neighbours peeking in"), cursore($m.sbirciata, 0...64, 8))
                riga("keyboard", T("Mostra i tasti premuti", "Show keys on screen"), Toggle("", isOn: $tasti).onChange(of: tasti) { _, v in TastiVisti.shared.acceso = v })
                riga("globe", T("Lingua", "Language"), Picker("", selection: $lingua) {
                    Text("Italiano").tag("it"); Text("English").tag("en")
                }.pickerStyle(.menu).frame(width: 150).onChange(of: lingua) { _, v in
                    Archivio.d.set(v, forKey: "lingua")
                    DispatchQueue.main.async { Pannello.shared.ricostruisci(); Barra.shared.aggiorna() }
                })

                Text(T("Larghezza per app", "Width per app")).font(.system(size: 15, weight: .semibold)).padding(.top, 22)
                Text(T("Tasto destro su una linea della barra per sceglierla", "Right-click a line in the slider to set one")).font(.system(size: 11)).foregroundStyle(t.t3).padding(.top, 2)
                Griglia(voci: m.regoleApp.keys.sorted(), etichetta: { b in
                    let v = m.regoleApp[b] ?? 0.5
                    return abs(v - 1.0 / 3) < 0.01 ? "⅓" : abs(v - 0.5) < 0.01 ? "½" : abs(v - 2.0 / 3) < 0.01 ? "⅔" : T("intera", "full")
                }, togli: { m.regoleApp[$0] = nil }).padding(.top, 12)

                Text(T("Libere", "Always free")).font(.system(size: 15, weight: .semibold)).padding(.top, 22)
                Text(T("Queste app non entrano mai in fila", "These apps never join the row")).font(.system(size: 11)).foregroundStyle(t.t3).padding(.top, 2)
                Griglia(voci: m.escluse, etichetta: { _ in nil }, togli: { b in m.escluse.removeAll { $0 == b } }).padding(.top, 12)
                if let a = m.appInFuoco, !m.escluse.contains(a.bundle) {
                    Button { m.liberaApp(a.bundle) } label: { Label(T("Lascia libera \(a.nome)", "Leave \(a.nome) free"), systemImage: "plus") }
                        .buttonStyle(Pillola()).padding(.top, 12)
                }
            }
        }
        .frame(maxHeight: 440)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private func cursore(_ v: Binding<Double>, _ r: ClosedRange<Double>, _ passo: Double) -> some View {
        HStack(spacing: 8) {
            Slider(value: v, in: r, step: passo).frame(width: 110).tint(t.azzurro)
            Text("\(Int(v.wrappedValue))").font(.system(size: 12)).foregroundStyle(t.t2).frame(width: 20, alignment: .trailing)
        }
    }

    private func riga<V: View>(_ simbolo: String, _ testo: String, _ v: V) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: simbolo).font(.system(size: 12)).foregroundStyle(t.t3).frame(width: 22)
                Text(testo).font(.system(size: 13)).lineLimit(1)
                Spacer()
                v.toggleStyle(.switch).labelsHidden().tint(t.azzurro).controlSize(.small)
            }
            .frame(height: 44)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}

/// Pillole di app (icona, nome, eventuale valore, x per togliere).
struct Griglia: View {
    let voci: [String]
    let etichetta: (String) -> String?
    let togli: (String) -> Void
    @EnvironmentObject var t: Tinta

    var body: some View {
        if voci.isEmpty {
            Text(T("Nessuna", "None")).font(.system(size: 12)).foregroundStyle(t.t2)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(voci, id: \.self) { b in
                    HStack(spacing: 8) {
                        Image(nsImage: Icone.di(b)).resizable().frame(width: 18, height: 18)
                        Text(Icone.nome(b)).font(.system(size: 12)).lineLimit(1)
                        if let e = etichetta(b) { Text(e).font(.system(size: 12)).foregroundStyle(t.azzurro) }
                        Spacer(minLength: 0)
                        Button { togli(b) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                            .buttonStyle(.plain).foregroundStyle(t.t3)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Capsule().fill(t.velo))
                }
            }
        }
    }
}

// MARK: - Pezzi piccoli

/// L'interruttore di Pulsar (come nelle Impostazioni): binario azzurro quando è acceso, manopola chiara.
struct Interruttore: View {
    let acceso: Bool
    let tocca: () -> Void
    @EnvironmentObject var t: Tinta
    var body: some View {
        Button(action: tocca) {
            ZStack(alignment: acceso ? .trailing : .leading) {
                Capsule().fill(acceso ? t.azzurro : t.testo.opacity(t.chiaro ? 0.13 : 0.16))
                Circle().fill(Color.white).padding(2).shadow(color: .black.opacity(t.chiaro ? 0.14 : 0.2), radius: 1, y: 0.5)
            }
            .frame(width: 34, height: 20)
            .animation(.easeOut(duration: 0.15), value: acceso)
        }
        .buttonStyle(.plain)
    }
}

struct Bottone: View {
    let simbolo: String
    let acceso: Bool
    let aiuto: String
    let azione: () -> Void
    @EnvironmentObject var t: Tinta
    @State private var sopra = false

    var body: some View {
        Button(action: azione) {
            Image(systemName: simbolo).font(.system(size: 12))
                .foregroundStyle(acceso ? t.azzurro : t.t2)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(acceso || sopra ? t.sel : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help(aiuto)
    }
}

struct Pillola: ButtonStyle {
    var principale = false
    func makeBody(configuration: Configuration) -> some View {
        PillolaCorpo(configuration: configuration, principale: principale)
    }
    private struct PillolaCorpo: View {
        let configuration: ButtonStyleConfiguration
        let principale: Bool
        @EnvironmentObject var t: Tinta
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .padding(.horizontal, 14).frame(height: 30)
                .foregroundStyle(principale ? (t.chiaro ? Color.white : Color(red: 0.075, green: 0.08, blue: 0.118)) : t.testo)
                .background(Capsule().fill(principale ? AnyShapeStyle(t.chiaro ? Color(white: 0.1) : .white) : AnyShapeStyle(t.velo)))
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// Come funziona, in cinque tappe con un disegno ciascuna. Si apre da sola la prima volta.
struct VistaGuida: View {
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var k: Tasti
    @ObservedObject private var gesto = Gesto.shared

    var body: some View {
        let c: (Azione) -> String = { k.combo[$0]?.testo ?? "" }
        let dita = gesto.modo == .tre ? T("tre dita sul trackpad", "three fingers on the trackpad")
            : gesto.modo == .quattro ? T("quattro dita sul trackpad", "four fingers on the trackpad")
            : gesto.modo == .opzione ? T("⌥ e due dita sul trackpad", "⌥ and two fingers on the trackpad") : T("la barra in basso", "the bottom slider")
        VStack(alignment: .leading, spacing: 0) {
            tappa(disegno: [0.5, 0.5, 0.5], fuoco: 1, T("Le finestre stanno in fila", "Your windows sit in a row"),
                  T("Ogni finestra aperta prende un posto, una accanto all'altra. Quelle nuove arrivano a destra.", "Every window gets its own spot, side by side. New ones land on the right."))
            tappa(disegno: [0.5, 0.5, 0.5], fuoco: 2, T("Scorri la fila", "Slide along"),
                  T("\(c(.precedente)) e \(c(.successiva)), oppure \(dita). Le linee in basso mostrano dove sei.", "\(c(.precedente)) and \(c(.successiva)), or \(dita). The lines at the bottom show where you are."))
            tappa(disegno: [1.0 / 3, 2.0 / 3, 0.5], fuoco: 1, T("Cambia larghezza", "Change the width"),
                  T("\(c(.meta)) metà, \(c(.dueTerzi)) due terzi, \(c(.intera)) intera, \(c(.allarga)) e \(c(.stringi)) a piccoli passi.", "\(c(.meta)) half, \(c(.dueTerzi)) two thirds, \(c(.intera)) full, \(c(.allarga)) and \(c(.stringi)) in small steps."))
            tappa(disegno: [0.5, 0.5], fuoco: 0, pila: true, T("Impila", "Stack"),
                  T("\(c(.impila)) mette la finestra sopra quella a sinistra, \(c(.stacca)) la stacca.", "\(c(.impila)) stacks the window onto the one on the left, \(c(.stacca)) pops it out."))
            tappa(disegno: [0.5, 0.5, 0.5], fuoco: -1, T("Non ricordi un tasto?", "Forgot a shortcut?"),
                  T("Tieni premuti ⌃⌥⌘ per un secondo e compare il foglio con tutte le scorciatoie.", "Hold ⌃⌥⌘ for a second and every shortcut appears."))
        }
    }

    private func tappa(disegno: [CGFloat], fuoco: Int, pila: Bool = false, _ titolo: String, _ testo: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                HStack(spacing: 3) {
                    ForEach(Array(disegno.enumerated()), id: \.offset) { i, w in
                        VStack(spacing: 3) {
                            ForEach(0..<(pila && i == 0 ? 2 : 1), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(i == fuoco ? t.azzurro : t.testo.opacity(0.16))
                            }
                        }
                        .frame(width: w * 30)
                    }
                }
                .frame(width: 62, height: 34, alignment: .leading)
                .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(titolo).font(.system(size: 14))
                    Text(testo).font(.system(size: 12)).foregroundStyle(t.t2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            Rectangle().fill(t.linea).frame(height: 1)
        }
    }
}
