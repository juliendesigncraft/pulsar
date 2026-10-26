// I Lanciatori (24/10/2026, nella Lite dal 24/10 sera): cartelle di siti da aprire con un clic, nella tessera dell'Isola,
// nel pannello sul bordo destro (EdgeDock) e nel riquadro sul desktop. Disegno approvato: agente/anteprima-lanciatori.html
// (tessera e griglia) e agente/anteprima-lanciatori-impostazioni.html (pagina delle Impostazioni).
// Da dove arriva la lista lo decide la fonte (FonteLanciatori): nella vendita è il file lanciatori.json nella cartella dati,
// cambiato dalla pagina Lanciatori delle Impostazioni (FonteLocale, sotto); nella build dell'autore è un'altra
// (Personale/lanciatori-personale.swift), che può anche aprire app e dare icone sue.
// Favicon chieste solo al sito stesso, cache in <cartella dati>/favicon/. Clic = Google Chrome, se manca il browser di sistema.
import SwiftUI
import AppKit
import Combine

struct LanciatoriWidget: IslandWidget {
    let id = "lanciatori"
    var title: String { T("Lanciatori", "Launchers") }
    let symbol = "circle.grid.2x2"
    func body(cells: Int) -> AnyView { AnyView(LanciatoriTile(dock: .shared, cells: cells)) }
}

/// Da dove arriva la lista dei Lanciatori.
protocol FonteLanciatori: AnyObject {
    /// Vero: la pagina delle Impostazioni cambia la lista e la fonte la salva. Falso: la pagina la mostra soltanto.
    var modificabile: Bool { get }
    /// La riga della pagina quando la lista non si cambia da lì (da dove arriva).
    var nota: String? { get }
    /// La riga della tessera e della griglia quando non c'è nessun sito.
    var vuota: String { get }
    /// Ogni quanti secondi rileggere; nil = mai (la lista cambia solo dalla pagina).
    var ogni: TimeInterval? { get }
    /// Dà la lista, anche più di una volta (prima la copia salvata, poi quella fresca).
    func leggi(_ fatto: @escaping ([Lanciatori.Cartella]) -> Void)
    func salva(_ cartelle: [Lanciatori.Cartella])
    /// Una voce che la fonte apre da sé (un'app); falso = è un sito, lo apre Lanciatori.
    func apri(_ v: Lanciatori.Voce) -> Bool
    /// L'icona di una voce che non è un sito; nil = si chiede al sito.
    func icona(_ v: Lanciatori.Voce) async -> Data?
    /// 25/10: le cartelle del riquadro sul desktop quando non devono ripetere quelle dello stash (le app del Mac). Vuoto = le stesse.
    var cartelleScrivania: [Lanciatori.Cartella] { get }
}

extension FonteLanciatori {
    var cartelleScrivania: [Lanciatori.Cartella] { [] }
}

/// La fonte della vendita: lanciatori.json nella cartella dati, gli esempi al primo avvio.
final class FonteLocale: FonteLanciatori {
    let file = Cartelle.dati.appendingPathComponent("lanciatori.json")
    var modificabile: Bool { true }
    var nota: String? { nil }
    var vuota: String { T("Aggiungi i tuoi siti nelle Impostazioni", "Add your sites in Settings") }
    var ogni: TimeInterval? { nil }

    func leggi(_ fatto: @escaping ([Lanciatori.Cartella]) -> Void) {
        if let c = ListaLanciatori.leggi(file) {
            if !FileManager.default.fileExists(atPath: file.path) { ListaLanciatori.scrivi(c, in: file) }   // gli esempi, una volta
            fatto(c)
        } else {
            // file rotto: si mette da parte, mai sovrascritto, e si riparte vuoti
            let via = file.deletingPathExtension().appendingPathExtension("rotto.json")
            try? FileManager.default.removeItem(at: via)
            try? FileManager.default.moveItem(at: file, to: via)
            ListaLanciatori.scrivi([], in: file)
            fatto([])
        }
    }
    func salva(_ cartelle: [Lanciatori.Cartella]) { ListaLanciatori.scrivi(cartelle, in: file) }
    func apri(_ v: Lanciatori.Voce) -> Bool { false }
    func icona(_ v: Lanciatori.Voce) async -> Data? { nil }
}

/// Il modulo nel registro: Lite, nessun permesso. Spento, niente pannello né riquadro e nessuna rilettura.
final class ModuloLanciatori: ModuloPulsar {
    static let shared = ModuloLanciatori()
    var id: String { "lanciatori" }
    var nome: String { T("Lanciatori", "Launchers") }
    var prodotto: Prodotto { .lite }
    var permessi: [Permesso] { [] }
    var acceso: Bool {
        get { Impostazioni.object(.lanciatoriAcceso) as? Bool ?? true }
        set { Impostazioni.set(newValue, .lanciatoriAcceso); RegistroModuli.shared.riapplica() }
    }
    func avvia() {
        Lanciatori.shared.avvia()
        LanciatoriStash.shared.avvia()
        LanciatoriDesktop.shared.avvia()
    }
    func ferma() {
        LanciatoriStash.shared.ferma()
        LanciatoriDesktop.shared.ferma()
        Lanciatori.shared.ferma()
    }
    /// Pannello e riquadro partono solo col modulo in esecuzione.
    static var inEsecuzione: Bool { RegistroModuli.shared.inEsecuzione("lanciatori") }
}

final class Lanciatori: ObservableObject {
    static let shared = Lanciatori()
    typealias Voce = VoceLanciatore
    typealias Cartella = CartellaLanciatori

    static var fonteDiSerie: FonteLanciatori { FonteLocale() }

    let fonte: FonteLanciatori
    @Published private(set) var cartelle: [Cartella] = []
    @Published var icone: [String: NSImage] = [:]          // per host, o "app-<id>" per le voci-app
    /// Le cartelle del riquadro sul desktop, se la fonte ne dà di sue (FonteLanciatori.cartelleScrivania).
    @Published private(set) var scrivania: [Cartella] = []

    private let dirIcone = Cartelle.dati.appendingPathComponent("favicon", isDirectory: true)
    private var inCorso = Set<String>()
    private var timer: Timer?

    init(fonte: FonteLanciatori = Lanciatori.fonteDiSerie) {
        self.fonte = fonte
        try? FileManager.default.createDirectory(at: dirIcone, withIntermediateDirectories: true)
        aggiorna()
    }

    /// Col modulo acceso: la rilettura periodica, se la fonte la vuole.
    func avvia() {
        aggiorna()
        guard timer == nil, let s = fonte.ogni else { return }
        timer = Timer.scheduledTimer(withTimeInterval: s, repeats: true) { [weak self] _ in self?.aggiorna() }
    }
    func ferma() { timer?.invalidate(); timer = nil }

    func aggiorna() {
        let s = fonte.cartelleScrivania                    // riletta a ogni giro: un'app installata dopo compare da sola
        if s != scrivania { scrivania = s; for v in s.flatMap(\.voci) { icona(per: v) } }
        fonte.leggi { [weak self] nuove in
            DispatchQueue.main.async { if let self, nuove != self.cartelle { self.usa(nuove) } }
        }
    }

    /// La pagina delle Impostazioni (e pulsar://lanciatori?aggiungi=) cambia la lista: si mostra e si salva.
    func cambia(_ nuove: [Cartella]) {
        guard fonte.modificabile, nuove != cartelle else { return }
        usa(nuove)
        fonte.salva(nuove)
    }

    private func usa(_ c: [Cartella]) {
        cartelle = c
        for v in c.flatMap(\.voci) { icona(per: v) }
    }

    static func host(_ u: String) -> String { URL(string: u)?.host ?? u }
    /// La chiave dell'icona: il sito, o l'app.
    static func chiave(_ v: Voce) -> String {
        if let a = v.app { return "app-" + a }
        if v.u.hasPrefix("file://") { return "file-" + String(v.u.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }.suffix(60)) }
        if let i = v.icona { return "img-" + String(i.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }.suffix(60)) }
        return host(v.u)
    }

    /// 25/10: le voci di una cartella divise per categoria, nell'ordine in cui arrivano. Senza categorie, un gruppo solo.
    static func gruppi(_ voci: [Voce]) -> [(cat: String?, voci: [Voce])] {
        var out: [(cat: String?, voci: [Voce])] = []
        for v in voci {
            if let i = out.firstIndex(where: { $0.cat == v.cat }) { out[i].voci.append(v) } else { out.append((v.cat, [v])) }
        }
        return out
    }

    func apri(_ v: Voce) {
        if fonte.apri(v) { return }
        // 25/10: un'app del Mac (file:///Applications/Figma.app): la apre il Finder, come dal Dock
        if v.u.hasPrefix("file://"), let u = URL(string: v.u) {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration()); return
        }
        // 25/10: i link che non sono siti (steam://rungameid/...) li apre la loro app, non Chrome
        if !v.u.hasPrefix("http"), let u = URL(string: v.u) { NSWorkspace.shared.open(u); return }
        chrome(v.u)
    }

    func chrome(_ link: String) {
        esegui(["-a", "Google Chrome", link]) { if let u = URL(string: link) { NSWorkspace.shared.open(u) } }
    }

    func esegui(_ args: [String], seFallisce: (() -> Void)? = nil) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = args
        p.terminationHandler = { pr in if pr.terminationStatus != 0, let f = seFallisce { DispatchQueue.main.async(execute: f) } }
        try? p.run()
    }

    // MARK: favicon

    private func icona(per v: Voce) {
        let h = Lanciatori.chiave(v)
        guard icone[h] == nil, !inCorso.contains(h) else { return }
        if v.u.hasPrefix("file://"), let u = URL(string: v.u) { icone[h] = NSWorkspace.shared.icon(forFile: u.path); return }   // l'icona vera dell'app
        let file = dirIcone.appendingPathComponent(h + ".icon"), vuoto = dirIcone.appendingPathComponent(h + ".none")
        if let d = try? Data(contentsOf: file), let im = NSImage(data: d) { icone[h] = im; return }
        // un sito senza icona si richiede dopo una settimana, non a ogni apertura
        if let a = try? FileManager.default.attributesOfItem(atPath: vuoto.path)[.modificationDate] as? Date,
           Date().timeIntervalSince(a) < 7 * 86400 { return }
        inCorso.insert(h)
        let fonte = self.fonte
        Task.detached {
            let d: Data?
            if v.app != nil { d = await fonte.icona(v) }
            else if let i = v.icona, let u = URL(string: i) { d = try? await URLSession.shared.data(for: Lanciatori.richiesta(u)).0 }
            else { d = await Lanciatori.scarica(host: h) }
            await MainActor.run { Lanciatori.shared.arrivata(h, d, file: file, vuoto: vuoto) }
        }
    }

    private func arrivata(_ h: String, _ d: Data?, file: URL, vuoto: URL) {
        inCorso.remove(h)
        if let d, let im = NSImage(data: d) {
            try? d.write(to: file, options: .atomic); try? FileManager.default.removeItem(at: vuoto)
            icone[h] = im
        } else if !h.hasPrefix("app-") && !h.hasPrefix("img-") {      // un'app o una copertina senza icona si riprova al prossimo giro
            try? Data().write(to: vuoto)
        }
    }

    /// Dalla pagina del sito: apple-touch-icon, poi <link rel=icon>, poi /favicon.ico.
    private static func scarica(host h: String) async -> Data? {
        guard let base = URL(string: "https://\(h)/") else { return nil }
        var candidati: [URL] = []
        if let (d, _) = try? await URLSession.shared.data(for: richiesta(base)), let html = String(data: d.prefix(200_000), encoding: .utf8)
            ?? String(data: d.prefix(200_000), encoding: .isoLatin1) {
            candidati = linkIcone(html, base: base)
        }
        candidati.append(base.appendingPathComponent("favicon.ico"))
        for c in candidati {
            if let (d, r) = try? await URLSession.shared.data(for: richiesta(c)), (r as? HTTPURLResponse)?.statusCode == 200,
               d.count > 64, NSImage(data: d) != nil { return d }
        }
        return nil
    }

    private static func richiesta(_ u: URL) -> URLRequest {
        var r = URLRequest(url: u); r.timeoutInterval = 8
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Pura: gli href dei <link> d'icona, quelli grandi (apple-touch-icon) per primi.
    static func linkIcone(_ html: String, base: URL) -> [URL] {
        guard let re = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else { return [] }
        func attr(_ tag: String, _ nome: String) -> String? {
            guard let r = try? NSRegularExpression(pattern: "\\b\(nome)\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive),
                  let m = r.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let g = Range(m.range(at: 1), in: tag) else { return nil }
            return String(tag[g])
        }
        var grandi: [URL] = [], piccole: [URL] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let g = Range(m.range, in: html) else { continue }
            let tag = String(html[g])
            guard let rel = attr(tag, "rel")?.lowercased(), rel.contains("icon"),
                  let href = attr(tag, "href"), let u = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
            else { continue }
            if rel.contains("apple-touch") { grandi.append(u) } else if !rel.contains("mask") { piccole.append(u) }
        }
        return grandi + piccole
    }
}

private struct LanciatoriTile: View {
    @ObservedObject var dock: Lanciatori
    let cells: Int
    @State private var scelta: String?
    @State private var sopra: String?

    private var cartella: Lanciatori.Cartella? {
        dock.cartelle.first { $0.id == scelta } ?? dock.cartelle.first
    }

    var body: some View {
        Group {
            if dock.cartelle.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "circle.grid.2x2").font(.system(size: 12)).foregroundStyle(Volta.t3)
                    Spacer(minLength: 0)
                    Text(dock.fonte.vuota)
                        .font(.system(size: 11)).foregroundStyle(Volta.t2).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if cells == 1 {
                // una cella: griglia 2x2 senza pillole
                LazyVGrid(columns: [GridItem(.fixed(26), spacing: 8), GridItem(.fixed(26), spacing: 8)], spacing: 8) {
                    ForEach((cartella?.voci ?? []).prefix(4)) { v in Cerchio(dock: dock, voce: v, lato: 26, sopra: $sopra) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // 24/10, l'autore: il nome tagliava la seconda pillola. Ora al passaggio prende il posto delle pillole.
                    ZStack(alignment: .leading) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(dock.cartelle) { c in
                                    let on = c.id == cartella?.id
                                    Text(c.titolo)
                                        .font(.system(size: 11))
                                        .foregroundStyle(on ? Volta.primT : Volta.pillT)
                                        .padding(.horizontal, 9).frame(height: 20)
                                        .background(Capsule().fill(on ? Volta.prim : Volta.pill))
                                        .contentShape(Capsule())
                                        .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { scelta = c.id } }
                                }
                            }
                        }
                        .opacity(sopra == nil ? 1 : 0)
                        .allowsHitTesting(sopra == nil)
                        Text(sopra ?? "").font(.system(size: 12)).foregroundStyle(Volta.t1)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(sopra == nil ? 0 : 1)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 20)
                    .animation(.easeOut(duration: 0.2), value: sopra)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // 25/10: nell'ordine delle categorie, come nella griglia
                            ForEach(Lanciatori.gruppi(cartella?.voci ?? []).flatMap(\.voci)) { v in Cerchio(dock: dock, voce: v, lato: 36, sopra: $sopra) }
                        }
                        .padding(.vertical, 4)   // 24/10: spazio per il cerchio che sale al passaggio, se no la ScrollView lo taglia sopra
                    }
                    .frame(height: 44)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct Cerchio: View {
    @ObservedObject var dock: Lanciatori
    let voce: Lanciatori.Voce
    let lato: CGFloat
    @Binding var sopra: String?
    /// Vero dentro una griglia che cancella il nome da sé quando il mouse ne esce.
    var esciDaSolo = false
    @State private var hover = false

    var body: some View {
        let h = Lanciatori.chiave(voce), app = voce.u.hasPrefix("file://")
        Button { dock.apri(voce) } label: {
            ZStack {
                Circle().fill(hover ? Volta.a4 : Volta.card2).opacity(app ? 0 : 1)
                if app, let im = dock.icone[h] {
                    // 25/10: un'app del Mac ha già la sua forma: l'icona intera, senza cerchio dietro
                    Image(nsImage: im).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: lato, height: lato)
                } else if voce.icona != nil, let im = dock.icone[h] {
                    // 25/10: una copertina (i giochi di Steam) riempie tutto il cerchio, come la foto di un contatto
                    Image(nsImage: im).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: lato, height: lato).clipShape(Circle())
                } else if let im = dock.icone[h] {
                    Image(nsImage: im).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: lato * 0.56, height: lato * 0.56)
                        .clipShape(RoundedRectangle(cornerRadius: lato * 0.14, style: .continuous))
                } else {
                    Text(String(voce.n.prefix(1)).uppercased())
                        .font(.system(size: lato * 0.4)).foregroundStyle(Volta.a2)
                }
            }
            .frame(width: lato, height: lato)
            .contentShape(Circle())
        }
        .buttonStyle(Stringi())
        .offset(y: hover && lato > 30 ? -2 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
        .help(voce.n)
        .onHover { dentro in
            hover = dentro
            // 25/10: il nome lo cancella la griglia quando il mouse esce da tutta la griglia, non il cerchio:
            // fra due icone c'è uno spazio e prima tornavano le pillole a ogni passaggio (nome, pillole, nome...)
            if dentro { sopra = voce.n } else if !esciDaSolo, sopra == voce.n { sopra = nil }
        }
    }
}

/// Al clic il cerchio si stringe e torna: nessun colore in più.
private struct Stringi: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Fuori dal notch (24/10 sera, l'autore: "tutti e due")
// Gli stessi Lanciatori nello stash in basso a sinistra (dal 24/10 notte, al posto del pannello sul bordo destro)
// e in un riquadro fisso sul desktop, sotto le finestre. Stessa grammatica della tessera:
// pillole delle cartelle, cerchi con la favicon, il nome al passaggio al posto delle pillole. Niente contorni.

/// La griglia grande: pillole sopra, cerchi da 40 pt a quattro colonne, al massimo tre file poi scorre.
struct LanciatoriGriglia: View {
    @ObservedObject var dock: Lanciatori = .shared
    @State private var scelta: String?
    @State private var sopra: String?
    /// Le cartelle da mostrare al posto di quelle dei Lanciatori (il riquadro sul desktop con le app). nil = le solite.
    var cartelleFisse: [Lanciatori.Cartella]? = nil
    init(cartelleFisse: [Lanciatori.Cartella]? = nil) { self.cartelleFisse = cartelleFisse }
    static let lato: CGFloat = 40, gap: CGFloat = 10, colonne = 4
    static var larghezza: CGFloat { CGFloat(colonne) * lato + CGFloat(colonne - 1) * gap }

    private var elenco: [Lanciatori.Cartella] { cartelleFisse ?? dock.cartelle }
    private var cartella: Lanciatori.Cartella? { elenco.first { $0.id == scelta } ?? elenco.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(elenco) { c in
                            let on = c.id == cartella?.id
                            Text(c.titolo)
                                .font(.system(size: 11))
                                .foregroundStyle(on ? Volta.primT : Volta.pillT)
                                .padding(.horizontal, 10).frame(height: 22)
                                .background(Capsule().fill(on ? Volta.prim : Volta.pill))
                                .contentShape(Capsule())
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.25)) { scelta = c.id }
                                    DispatchQueue.main.async { dock.objectWillChange.send() }   // pannello e widget si rimisurano
                                }
                        }
                    }
                }
                .opacity(sopra == nil ? 1 : 0)
                .allowsHitTesting(sopra == nil)
                Text(sopra ?? "").font(.system(size: 12)).foregroundStyle(Volta.t1)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(sopra == nil ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .frame(height: 22)
            .animation(.easeOut(duration: 0.15), value: sopra == nil)    // solo il passaggio pillole/nome, non nome/nome

            if elenco.isEmpty {
                Text(dock.fonte.vuota)
                    .font(.system(size: 11)).foregroundStyle(Volta.t2)
                    .frame(width: Self.larghezza, height: Self.lato, alignment: .leading)
            } else {
                let voci = cartella?.voci ?? []
                let gruppi = Lanciatori.gruppi(voci)
                let titoli = gruppi.count > 1 || gruppi.first?.cat != nil
                // 25/10: con le categorie, un titoletto sopra ogni gruppo; l'altezza segue il contenuto fino a 5 file
                let righe = gruppi.reduce(0) { $0 + ($1.voci.count + Self.colonne - 1) / Self.colonne }
                let alto = CGFloat(righe) * Self.lato + CGFloat(max(0, righe - gruppi.count)) * Self.gap
                    + (titoli ? CGFloat(gruppi.count) * 26 : 0) + CGFloat(max(0, gruppi.count - 1)) * 6 + 8
                let massimo = 5 * Self.lato + 4 * Self.gap + (titoli ? 3 * 26 : 0) + 8
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(gruppi.enumerated()), id: \.offset) { _, g in
                            if titoli {
                                Text(g.cat ?? T("Altro", "Other")).font(.system(size: 11)).foregroundStyle(Volta.t3)
                                    .frame(height: 20, alignment: .bottomLeading)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.lato), spacing: Self.gap), count: Self.colonne),
                                      alignment: .leading, spacing: Self.gap) {
                                ForEach(g.voci) { v in Cerchio(dock: dock, voce: v, lato: Self.lato, sopra: $sopra, esciDaSolo: true) }
                            }
                        }
                    }
                    .padding(.vertical, 4)    // il cerchio sale di 2 pt al passaggio: niente taglio sopra
                }
                .frame(width: Self.larghezza, height: min(alto, massimo))
                .onHover { if !$0 { sopra = nil } }      // fuori dalla griglia: tornano le pillole
                .animation(.easeOut(duration: 0.25), value: cartella?.id)
            }
        }
        .frame(width: Self.larghezza)
    }
}

private final class LanciatoriPanel: NSPanel {
    override func orderFrontRegardless() { super.orderFrontRegardless(); Ombra.segui(self) }
    override func orderFront(_ sender: Any?) { super.orderFront(sender); Ombra.segui(self) }
    init(livello: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = livello
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LanciatoriHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Lo stash (24/10 notte, l'autore: "uno stash uguale alla dock del mac"): al posto del pannello sul bordo destro.
/// 24/10 sera tardi, l'autore: "stesso tempo di apertura e chiusura del dock, stessa magnificazione, alla stessa altezza,
/// icone con lo sfondo scuro del dock" e "si devono adeguare alla modalità del sistema: notte, giorno, tema, glass,
/// monocolore". Quindi: striscia di vetro neutra alta 47 pt a 6 pt dal fondo (misurata sul suo Dock), tessere da 36 pt
/// (`tilesize`), ingrandimento a onda fino a `largesize` se `magnification` è acceso, e le icone nell'aspetto scelto in
/// Impostazioni di Sistema → Aspetto → Icone (AppleIconAppearanceTheme: Regular, Clear, Tinted; chiaro, scuro, automatico).
/// Esce insieme al Dock, da tutto il bordo in basso, e rientra con lui (scelta dell'autore del 24/10: "come un Dock unico").
final class LanciatoriStash {
    static let shared = LanciatoriStash()
    static let margine: CGFloat = 8          // dal bordo sinistro
    static let fondo: CGFloat = 6            // dal basso, come il Dock (misurato il 24/10)
    /// I tempi del Dock, misurati il 24/10 su una ripresa a 120 fps del Dock dell'autore allineata al registro del mouse
    /// (autohide-delay e autohide-time-modifier non scritti, quindi i valori di macOS): esce 0,27-0,37 s dopo che il mouse
    /// tocca il fondo (media 0,33), sale in 0,15 s partendo veloce e frenando, rientra in 0,15 s appena il mouse si alza,
    /// partendo piano. Se l'autore scrive le due chiavi del Dock, lo stash le segue.
    enum Tempo {
        static var ritardo: Double { (UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "autohide-delay") as? Double) ?? 0.33 }
        static var fattore: Double { (UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "autohide-time-modifier") as? Double) ?? 1 }
        static var esce: Double { 0.15 * fattore }
        static var rientra: Double { 0.15 * fattore }
        static let attesaUscita = 0.0        // il Dock rientra appena il mouse se ne va
    }

    private var win: LanciatoriPanel?
    private var monitors: [Any] = []
    private var cambi: Any?
    private var cambiTutti: Any?
    private var fuori = false
    private var nascondi: DispatchWorkItem?
    private var apri: DispatchWorkItem?

    var acceso: Bool {
        get { Impostazioni.object(.lanciatoriStash) as? Bool ?? true }
        set { Impostazioni.set(newValue, .lanciatoriStash); newValue ? avvia() : ferma() }
    }

    private var schermo: NSScreen { EdgeDock.defaultScreen }
    private var misura: NSSize { win?.contentView?.fittingSize ?? NSSize(width: 600, height: 120) }

    func avvia() {
        guard acceso, ModuloLanciatori.inEsecuzione, win == nil else { return }
        let w = LanciatoriPanel(livello: .statusBar)
        w.contentView = LanciatoriHost(rootView: StashVista())
        win = w
        w.setFrame(cornice(false), display: false)
        w.orderFrontRegardless()
        let guarda: (NSEvent) -> Void = { [weak self] _ in self?.guarda(NSEvent.mouseLocation) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: guarda) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { guarda($0); return $0 }) { monitors.append(l) }
        cambi = Lanciatori.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.rimisura() } }
        cambiTutti = StashStato.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.rimisura() } }
        Self.misuraDock()
        AspettoIcone.shared.segui()
    }

    func ferma() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        win?.orderOut(nil); win = nil; cambi = nil; cambiTutti = nil; fuori = false
    }

    /// In vista per qualche secondo (menu e pulsar://lanciatori?mostra=1).
    func mostra() { esci(); pianifica(dopo: 4) }

    /// La finestra è più alta e larga della striscia: sopra c'è l'aria per l'ingrandimento e il nome.
    private func cornice(_ visibile: Bool) -> NSRect {
        let f = schermo.frame, s = misura
        return NSRect(x: f.minX + Self.margine, y: visibile ? f.minY + Self.fondo : f.minY - s.height - 2, width: s.width, height: s.height)
    }

    /// La striscia vera, per sapere se il mouse ci è sopra (la finestra intorno è quasi tutta trasparente).
    private var striscia: NSRect {
        guard let w = win else { return .zero }
        return NSRect(x: w.frame.minX, y: w.frame.minY, width: StashVista.larghezzaBase, height: StashVista.altezza + StashVista.extra)
    }

    private func guarda(_ p: NSPoint) {
        let (sotto, fascia) = Self.zona(p, schermo: schermo.frame, larghezza: StashVista.larghezzaBase)
        if !fuori {
            if sotto {
                guard apri == nil else { return }
                let lavoro = DispatchWorkItem { [weak self] in self?.apri = nil; self?.esci() }
                apri = lavoro
                DispatchQueue.main.asyncAfter(deadline: .now() + Tempo.ritardo, execute: lavoro)
            } else { apri?.cancel(); apri = nil }
        } else if (StashStato.shared.tutti ? win?.frame ?? .zero : striscia).insetBy(dx: -4, dy: -4).contains(p) || sotto || fascia {
            nascondi?.cancel(); nascondi = nil
        } else {
            pianifica(dopo: Tempo.attesaUscita)
        }
    }

    /// 26/10, l'autore: "non serve si apra ogni volta che si sorvola il Dock normale. Se sorvolo quella parte, lo fai comparire."
    /// Prima (24/10, "come un Dock unico") usciva da tutto il bordo in basso, quindi anche usando il Dock di macOS.
    /// Ora conta solo la sua zona: dal bordo sinistro fino alla fine della striscia (che finisce prima del Dock, posti(cartelle:)).
    /// Pura: `sotto` = il mouse tocca il bordo basso nella zona (fa uscire), `fascia` = è all'altezza della striscia nella zona (la tiene fuori).
    static func zona(_ p: NSPoint, schermo f: NSRect, larghezza: CGFloat) -> (sotto: Bool, fascia: Bool) {
        let fine = f.minX + margine + larghezza + 8
        let dentro = p.x >= f.minX && p.x <= fine
        return (dentro && p.y <= f.minY + 2, dentro && p.y <= f.minY + fondo + StashVista.altezza + 2)
    }

    private func esci() {
        nascondi?.cancel(); nascondi = nil
        guard let w = win, !fuori else { return }
        fuori = true
        // il Dock può essere cambiato (un'app in più): si rimisura prima di uscire, e la fila si accorcia se serve
        let prima = Self.bordoDock
        Self.misuraDock()
        if prima != Self.bordoDock { Lanciatori.shared.objectWillChange.send() }
        StashStato.shared.pronto = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Tempo.esce + 0.12) { if self.fuori { StashStato.shared.pronto = true } }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = Tempo.esce; c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().setFrame(cornice(true), display: true)
        }
    }

    private func pianifica(dopo: Double) {
        guard nascondi == nil else { return }
        let lavoro = DispatchWorkItem { [weak self] in
            guard let self, let w = self.win else { return }
            self.nascondi = nil; self.fuori = false
            StashStato.shared.pronto = false
            NSAnimationContext.runAnimationGroup { c in
                c.duration = Tempo.rientra; c.timingFunction = CAMediaTimingFunction(name: .easeIn)
                w.animator().setFrame(self.cornice(false), display: true)
            } completionHandler: { StashStato.shared.tutti = false }     // rientrato: la griglia di tutti i titoli si richiude
        }
        nascondi = lavoro
        DispatchQueue.main.asyncAfter(deadline: .now() + dopo, execute: lavoro)
    }

    private func rimisura() {
        guard let w = win, misura != w.frame.size else { return }
        w.setFrame(cornice(fuori), display: true)
    }

    /// 25/10: dove comincia il Dock, letto dall'Accessibilità (la lista del Dock, come la Barra pulita legge le icone).
    /// l'autore: lo stash finiva sopra Finder e Safari quando il Dock si è allargato. nil = non si sa (niente Accessibilità,
    /// Dock di lato): si torna alla stima del 24/10.
    static var bordoDock: CGFloat?
    static func misuraDock() {
        let orient = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        guard orient == "bottom", AXIsProcessTrusted(),
              let d = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { bordoDock = nil; return }
        let el = AXUIElementCreateApplication(d.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.2)
        var figli: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &figli) == .success,
              let lista = (figli as? [AXUIElement])?.first else { bordoDock = nil; return }
        var p: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(lista, kAXPositionAttribute as CFString, &p)
        AXUIElementCopyAttributeValue(lista, kAXSizeAttribute as CFString, &s)
        var pt = CGPoint.zero, sz = CGSize.zero
        if let p { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
        if let s { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
        bordoDock = sz.width > 0 ? pt.x : nil
    }

    /// Quante tessere stanno prima del Dock. 25/10, l'autore: "si sovrappone ancora al Dock, riduci di due".
    /// Col Dock fermo restavano 16 pt, ma con l'ingrandimento la fila si allarga verso destra e il Dock verso sinistra:
    /// si tiene libero anche quello (due volte l'extra dell'ingrandimento) più due tessere d'aria.
    static func posti(cartelle: Int) -> Int {
        let f = EdgeDock.defaultScreen.frame
        let aria = 16 + 2 * StashVista.extra + 2 * StashVista.lato
        let largo = (bordoDock.map { $0 - f.minX - aria } ?? f.width / 2 - 264 - 2 * StashVista.lato) - margine
        let fisso = 2 * StashVista.bordo + CGFloat(cartelle) * StashVista.lato + StashVista.separatore
        return max(4, Int((largo - fisso) / StashVista.lato))
    }
}

/// L'aspetto delle icone scelto in macOS (Impostazioni di Sistema → Aspetto → Icone) e il chiaro o scuro del sistema.
final class AspettoIcone: ObservableObject {
    static let shared = AspettoIcone()
    enum Stile: String { case colori, vetro, tinta }
    @Published private(set) var stile: Stile = .colori
    @Published private(set) var scuro = true
    @Published private(set) var tinta: NSColor = .controlAccentColor
    private var timer: Timer?
    private var avviato = false

    func segui() {
        guard !avviato else { return }
        avviato = true
        leggi()
        for n in ["AppleInterfaceThemeChangedNotification", "AppleColorPreferencesChangedNotification", "AppleIconAppearanceThemeChangedNotification"] {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(n), object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.leggi() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.leggi() }   // se una notifica manca
    }

    func leggi() {
        // il dominio globale si legge da standard (suiteName: globalDomain non è permesso e dà valori vuoti)
        let g: UserDefaults? = UserDefaults.standard
        let tema = g?.string(forKey: "AppleIconAppearanceTheme") ?? "RegularAutomatic"
        let sistemaScuro = g?.string(forKey: "AppleInterfaceStyle") == "Dark"
        let st: Stile = tema.hasPrefix("Clear") ? .vetro : tema.hasPrefix("Tinted") ? .tinta : .colori
        let sc = tema.hasSuffix("Dark") ? true : tema.hasSuffix("Light") ? false : sistemaScuro
        var t = NSColor.controlAccentColor
        if let c = g?.string(forKey: "AppleIconAppearanceCustomTintColor")?.split(separator: " ").compactMap({ Double($0) }), c.count >= 3 {
            t = NSColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
        }
        if st != stile { stile = st }
        if sc != scuro { scuro = sc }
        if t != tinta { tinta = t }
    }
}

private struct StashVista: View {
    @ObservedObject var dock: Lanciatori = .shared
    @ObservedObject var aspetto = AspettoIcone.shared
    @ObservedObject var stato = StashStato.shared
    @State private var scelta: String?
    @State private var mouseX: CGFloat?

    static let lato: CGFloat = 36            // tilesize del Dock dell'autore
    static let altezza: CGFloat = 47         // la striscia del Dock, misurata
    static let bordo: CGFloat = 6
    static let separatore: CGFloat = 13
    static var grande: CGFloat {             // largesize, solo se l'ingrandimento è acceso
        let d = UserDefaults(suiteName: "com.apple.dock")
        guard (d?.object(forKey: "magnification") as? Bool) == true else { return lato }
        return CGFloat((d?.object(forKey: "largesize") as? Double) ?? 64)
    }
    static var extra: CGFloat { grande - lato }
    static var larghezzaBase: CGFloat = 400  // aggiornata a ogni disegno: la usa lo stash per sapere dove sta il mouse

    private enum Elem: Identifiable {
        case cartella(Lanciatori.Cartella), voce(Lanciatori.Voce), separa, altri
        var id: String {
            switch self { case .cartella(let c): return "c:" + c.id; case .voce(let v): return v.id; case .separa: return "|"; case .altri: return ">" }
        }
        var nome: String {
            switch self {
            case .cartella(let c): return c.titolo
            case .voce(let v): return v.n
            case .separa: return ""
            case .altri: return T("Tutti", "All")
            }
        }
    }

    private var cartella: Lanciatori.Cartella? { dock.cartelle.first { $0.id == scelta } ?? dock.cartelle.first }

    private struct Disposizione { let elems: [Elem]; let basi: [CGFloat]; let larghe: [CGFloat]; let base: CGFloat; let totale: CGFloat; let vicino: Int? }

    /// Gli elementi in fila e l'onda dell'ingrandimento: centri calcolati sulle misure di base, come fa il Dock.
    private func disponi() -> Disposizione {
        let voci = cartella?.voci ?? []
        let posti = LanciatoriStash.posti(cartelle: dock.cartelle.count)
        // 25/10: niente pagine. Quelle che stanno prima del Dock, poi "Tutti" apre sopra la fila la griglia con ogni titolo
        let molte = voci.count > posti
        let elems: [Elem] = dock.cartelle.map { .cartella($0) } + [.separa]
            + voci.prefix(molte ? posti - 1 : posti).map { .voce($0) } + (molte ? [.altri] : [])
        let basi: [CGFloat] = elems.map { e in if case .separa = e { return Self.separatore }; return Self.lato }
        var centri: [CGFloat] = []
        var x = Self.bordo
        for b in basi { centri.append(x + b / 2); x += b }
        let base = x + Self.bordo
        var larghe: [CGFloat] = []
        for i in elems.indices {
            var sc: CGFloat = 1
            if let m = mouseX, basi[i] == Self.lato, Self.extra > 0 {
                let d = abs(m - centri[i]) / (Self.lato * 2.5)          // l'onda prende circa due icone per lato
                if d < 1 { sc = 1 + (Self.extra / Self.lato) * CGFloat((cos(Double(d) * .pi) + 1) / 2) }
            }
            larghe.append(basi[i] * sc)
        }
        var vicino: Int?
        if let m = mouseX {
            var acc = Self.bordo
            for i in elems.indices {
                if m >= acc && m < acc + larghe[i] { vicino = basi[i] == Self.lato ? i : nil; break }
                acc += larghe[i]
            }
        }
        Self.larghezzaBase = base
        return Disposizione(elems: elems, basi: basi, larghe: larghe, base: base, totale: larghe.reduce(Self.bordo * 2, +), vicino: vicino)
    }

    var body: some View {
        let d = disponi()
        let elems = d.elems, larghe = d.larghe, totale = d.totale, base = d.base, vicino = d.vicino
        VStack(alignment: .leading, spacing: 10) {
        if stato.tutti, let c = cartella {
            StashTutti(dock: dock, aspetto: aspetto, cartella: c, larghezza: max(base, 340))
                .transition(.opacity.combined(with: .offset(y: 12)))
        }
        ZStack(alignment: .bottomLeading) {
            Fondo(aspetto: aspetto).frame(width: totale, height: Self.altezza)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(elems.enumerated()), id: \.element.id) { i, e in
                    elemento(e, lato: larghe[i], sopra: vicino == i)
                }
            }
            .padding(.horizontal, Self.bordo)
            .padding(.bottom, (Self.altezza - Self.lato) / 2)
        }
        .frame(width: base + Self.extra * 2.4, height: Self.altezza + Self.extra + 34, alignment: .bottomLeading)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { fase in
            switch fase {
            case .active(let q): mouseX = stato.pronto ? q.x : nil
            case .ended: mouseX = nil
            }
        }
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: mouseX)
        }
        .environment(\.colorScheme, aspetto.scuro ? .dark : .light)
        .fixedSize()
    }

    @ViewBuilder private func elemento(_ e: Elem, lato: CGFloat, sopra: Bool) -> some View {
        switch e {
        case .separa:
            Rectangle().fill(Color.primary.opacity(0.22)).frame(width: 1, height: Self.lato - 6)
                .frame(width: Self.separatore, height: Self.lato)
        case .cartella(let c):
            let on = c.id == cartella?.id
            Button {
                withAnimation(.easeOut(duration: 0.25)) { scelta = c.id }
                DispatchQueue.main.async { dock.objectWillChange.send() }
            } label: {
                IconaStash(aspetto: aspetto, lato: lato) { Image(systemName: Self.simbolo(c.id)).font(.system(size: lato * 0.4)) }
            }
            .buttonStyle(Stringi())
            .overlay(alignment: .bottom) {   // la cartella aperta ha il puntino sotto, come le app aperte nel Dock
                Circle().fill(Color.primary.opacity(0.7)).frame(width: 4, height: 4).offset(y: 3.5).opacity(on ? 1 : 0)
            }
            .overlay(alignment: .top) { Nome(testo: e.nome, visibile: sopra) }
        case .voce(let v):
            Button { dock.apri(v) } label: { IconaSito(dock: dock, aspetto: aspetto, voce: v, lato: lato) }
                .buttonStyle(Stringi())
                .overlay(alignment: .top) { Nome(testo: e.nome, visibile: sopra) }
        case .altri:
            Button { withAnimation(.easeOut(duration: 0.25)) { stato.tutti.toggle() } } label: {
                IconaStash(aspetto: aspetto, lato: lato) {
                    Image(systemName: stato.tutti ? "chevron.down" : "square.grid.2x2").font(.system(size: lato * 0.34))
                }
            }
            .buttonStyle(Stringi())
            .overlay(alignment: .top) { Nome(testo: e.nome, visibile: sopra) }
        }
    }

    static func simbolo(_ id: String) -> String {
        // le cartelle dell'autore e quelle di esempio della vendita; una cartella nuova ha la cartella
        ["giochi": "gamecontroller", "play": "gamecontroller", "imparare": "book.closed", "learn": "book.closed",
         "strumenti": "wrench.and.screwdriver", "tools": "wrench.and.screwdriver", "ai": "sparkles"][id] ?? "folder"
    }
}

/// Se la griglia con tutti i titoli è aperta sopra lo stash: la vista la disegna, lo stash allarga la zona del mouse.
final class StashStato: ObservableObject {
    static let shared = StashStato()
    @Published var tutti = false
    /// 25/10, l'autore: "si apre in modo glitchato, forse perché il mouse è già su un'app e parte subito l'ingrandimento".
    /// Falso mentre lo stash sale: l'onda dell'ingrandimento parte solo a stash fermo e al primo movimento del mouse.
    @Published var pronto = false
}

/// 25/10, l'autore: "premendo la freccia non si vedono gli altri titoli, deve mostrarli tutti". Come una pila del Dock
/// aperta a griglia: tutte le voci della cartella, divise per categoria, sopra la fila; scorre solo oltre il 60% dello schermo.
private struct StashTutti: View {
    @ObservedObject var dock: Lanciatori
    @ObservedObject var aspetto: AspettoIcone
    let cartella: Lanciatori.Cartella
    let larghezza: CGFloat
    @State private var sopra: String?
    static let lato: CGFloat = 44, gap: CGFloat = 10, margine: CGFloat = 16

    var body: some View {
        let colonne = max(4, Int((larghezza - 2 * Self.margine + Self.gap) / (Self.lato + Self.gap)))
        let gruppi = Lanciatori.gruppi(cartella.voci)
        let titoli = gruppi.count > 1 || gruppi.first?.cat != nil
        let righe = gruppi.reduce(0) { $0 + ($1.voci.count + colonne - 1) / colonne }
        let alto = CGFloat(righe) * Self.lato + CGFloat(max(0, righe - gruppi.count)) * Self.gap
            + (titoli ? CGFloat(gruppi.count) * 24 : 0) + CGFloat(max(0, gruppi.count - 1)) * 8 + 8
        VStack(alignment: .leading, spacing: 10) {
            Text(sopra ?? cartella.titolo).font(.system(size: 13)).foregroundStyle(Color.primary)
                .lineLimit(1).truncationMode(.tail)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(gruppi.enumerated()), id: \.offset) { _, g in
                        if titoli {
                            Text(g.cat ?? T("Altro", "Other")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                                .frame(height: 16, alignment: .bottomLeading)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.lato), spacing: Self.gap), count: colonne),
                                  alignment: .leading, spacing: Self.gap) {
                            ForEach(g.voci) { v in
                                Button { dock.apri(v) } label: { IconaSito(dock: dock, aspetto: aspetto, voce: v, lato: Self.lato) }
                                    .buttonStyle(Stringi())
                                    .help(v.n)
                                    .onHover { d in if d { sopra = v.n } else if sopra == v.n { sopra = nil } }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: min(alto, EdgeDock.defaultScreen.visibleFrame.height * 0.6))
        }
        .padding(Self.margine)
        .frame(width: larghezza, alignment: .leading)
        .background(Fondo(aspetto: aspetto))
    }
}

/// La striscia: vetro neutro come il Dock (niente velo blu), scuro di notte e chiaro di giorno.
private struct Fondo: View {
    @ObservedObject var aspetto: AspettoIcone
    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 18, style: .continuous)
        forma.fill(Color.clear)
            .glassEffect(.regular.tint(aspetto.scuro ? Color(white: 0.07).opacity(0.55) : Color(white: 0.98).opacity(0.35)), in: forma)
    }
}

/// Il nome sopra l'icona, come nel Dock ma senza fondino: un alone lo stacca da quello che c'è dietro.
private struct Nome: View {
    let testo: String
    let visibile: Bool
    @Environment(\.colorScheme) private var cs
    var body: some View {
        let alone = cs == .dark ? Color.black : Color.white
        Text(testo).font(.system(size: 12)).foregroundStyle(Color.primary).lineLimit(1).fixedSize()
            .shadow(color: alone.opacity(0.9), radius: 3).shadow(color: alone.opacity(0.6), radius: 8)
            .offset(y: -26)
            .opacity(visibile ? 1 : 0)
            .allowsHitTesting(false)
    }
}

/// La tessera nell'aspetto delle icone di sistema: colori (fondo pieno chiaro o scuro), vetro (Clear), monocolore (Tinted).
private struct IconaStash<C: View>: View {
    @ObservedObject var aspetto: AspettoIcone
    let lato: CGFloat
    @ViewBuilder let segno: () -> C

    var body: some View {
        let l = lato * 0.84, forma = RoundedRectangle(cornerRadius: l * 0.225, style: .continuous)   // la squircle delle icone Mac
        ZStack {
            switch aspetto.stile {
            case .vetro:
                forma.fill(Color.clear).glassEffect(.regular.tint(Color.white.opacity(aspetto.scuro ? 0.04 : 0.25)), in: forma)
            default:
                forma.fill(LinearGradient(colors: aspetto.scuro ? [Color(white: 0.23), Color(white: 0.11)] : [Color(white: 0.99), Color(white: 0.90)],
                                          startPoint: .top, endPoint: .bottom))
            }
            segno().foregroundStyle(colore)
        }
        .frame(width: l, height: l)
        .frame(width: lato, height: lato)
    }

    private var colore: Color {
        switch aspetto.stile {
        case .tinta: return Color(nsColor: aspetto.tinta).opacity(aspetto.scuro ? 0.95 : 0.85)
        case .vetro: return Color.primary.opacity(0.85)
        case .colori: return Color.primary.opacity(0.7)
        }
    }
}

/// L'icona del sito o dell'app nella tessera: a colori, o resa in grigio (vetro) o nella tinta (monocolore).
private struct IconaSito: View {
    @ObservedObject var dock: Lanciatori
    @ObservedObject var aspetto: AspettoIcone
    let voce: Lanciatori.Voce
    let lato: CGFloat
    var body: some View {
        let h = Lanciatori.chiave(voce)
        IconaStash(aspetto: aspetto, lato: lato) {
            if voce.icona != nil, let im = dock.icone[h] {
                // 25/10: la copertina riempie la squircle, a colori come le icone delle app nel Dock
                let l = lato * 0.84
                Image(nsImage: im).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: l, height: l)
                    .clipShape(RoundedRectangle(cornerRadius: l * 0.225, style: .continuous))
            } else if let im = dock.icone[h] {
                let resa = aspetto.stile == .colori ? im : Lanciatori.mono(im, chiave: h, tinta: aspetto.stile == .tinta ? aspetto.tinta : nil, scuro: aspetto.scuro)
                Image(nsImage: resa).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: lato * 0.5, height: lato * 0.5)
                    .clipShape(RoundedRectangle(cornerRadius: lato * 0.1, style: .continuous))
            } else {
                Text(String(voce.n.prefix(1)).uppercased()).font(.system(size: lato * 0.4))
            }
        }
    }
}

extension Lanciatori {
    private static var mono: [String: NSImage] = [:]
    /// Una sola tinta come le icone Tinted o Clear di macOS: luminanza dell'icona portata sulla tinta (o sul grigio).
    static func mono(_ im: NSImage, chiave: String, tinta: NSColor?, scuro: Bool) -> NSImage {
        let t = (tinta ?? (scuro ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.18, alpha: 1))).usingColorSpace(.sRGB) ?? .gray
        let k = "\(chiave)|\(t.redComponent),\(t.greenComponent),\(t.blueComponent)|\(scuro)"
        if let g = mono[k] { return g }
        guard let tiff = im.tiffRepresentation, let ci = CIImage(data: tiff),
              let f = CIFilter(name: "CIColorMonochrome") else { return im }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(CIColor(red: t.redComponent, green: t.greenComponent, blue: t.blueComponent), forKey: kCIInputColorKey)
        f.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: out.extent) else { return im }
        let g = NSImage(cgImage: cg, size: im.size)
        mono[k] = g
        return g
    }
}

/// Il riquadro sul desktop: sopra lo sfondo e sotto le finestre, si sposta trascinandolo dal fondo e ricorda dove sta.
final class LanciatoriDesktop {
    static let shared = LanciatoriDesktop()
    private var win: LanciatoriPanel?
    private var spostato: Any?
    private var cambi: Any?

    var acceso: Bool {
        get { Impostazioni.object(.lanciatoriScrivania) as? Bool ?? LanciatoriDesktop.diSerie }
        set { Impostazioni.set(newValue, .lanciatoriScrivania); newValue ? avvia() : ferma() }
    }
    /// Chi compra trova acceso solo il bordo: il riquadro sul desktop lo sceglie lui. l'autore li aveva tutti e due.
    static let diSerie = false

    func avvia() {
        guard acceso, ModuloLanciatori.inEsecuzione, win == nil else { return }
        // un gradino sopra le icone della scrivania, sotto qualsiasi finestra
        let w = LanciatoriPanel(livello: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1))
        w.isMovableByWindowBackground = true
        w.isMovable = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.contentView = LanciatoriHost(rootView: DesktopVista())
        let size = w.contentView?.fittingSize ?? NSSize(width: 230, height: 180)
        let vf = EdgeDock.defaultScreen.visibleFrame
        var origine = NSPoint(x: vf.maxX - size.width - 40, y: vf.minY + 40)
        if let p = Impostazioni.object(.lanciatoriScrivaniaPos) as? [Double], p.count == 2 {
            let q = NSPoint(x: p[0], y: p[1])
            if NSScreen.screens.contains(where: { $0.frame.contains(q) }) { origine = q }    // lo schermo c'è ancora
        }
        w.setFrame(NSRect(origin: origine, size: size), display: false)
        spostato = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak w] _ in
            guard let o = w?.frame.origin else { return }
            Impostazioni.set([Double(o.x), Double(o.y)], .lanciatoriScrivaniaPos)
        }
        win = w
        cambi = Lanciatori.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.misura() } }
        w.orderFrontRegardless()
        Ombra.segui(w)
    }

    /// Cambiano i siti o la cartella: nuova misura, l'angolo in alto a sinistra resta fermo.
    private func misura() {
        guard let w = win, let s = w.contentView?.fittingSize, s != w.frame.size else { return }
        let alto = w.frame.maxY
        w.setFrame(NSRect(x: w.frame.minX, y: alto - s.height, width: s.width, height: s.height), display: true, animate: false)
    }

    func ferma() {
        if let spostato { NotificationCenter.default.removeObserver(spostato) }
        win?.orderOut(nil); win = nil; spostato = nil; cambi = nil
    }
}

private struct DesktopVista: View {
    @ObservedObject var look = GhieraLook.shared
    @ObservedObject var dock: Lanciatori = .shared
    var body: some View {
        // 25/10: giochi e Learn stanno già nello stash in basso: se la fonte dà cartelle sue (le app), il riquadro mostra quelle
        LanciatoriGriglia(cartelleFisse: dock.scrivania.isEmpty ? nil : dock.scrivania)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Volta.body))
            .environment(\.colorScheme, look.mode.scheme)
            .id(look.mode.rawValue)
            .fixedSize()
    }
}
