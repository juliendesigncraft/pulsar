// Pulsar — TEMI (11/10/2026 sera): Dark Matte e White Matte per tutto lo schermo.
// l'autore: "se scelgo White Matte, tutto lo schermo, anche le cartelle e le regolazioni di sinistra e il nuovo prodotto
// dynamic island cambino colore", e poi Spazio e Google. Si sceglie dal menu di Pulsar (sezione TEMA) o con ⌃⌥L.
// Una scelta cambia insieme:
//   1. tutto Pulsar (ghiere, luce, colonna, pannello, capsula): aspetto Notte (Dark Matte) o Bianco (White Matte);
//   2. l'aspetto di macOS (scuro o chiaro), come fa l'interruttore Dark Mode, se "Cambia anche macOS" è acceso (fase 5);
//   3. lo sfondo: ~/Pictures/matte-dark-spazio-v2.png o matte-white-spazio.png (temi/genera.py);
//   4. le icone delle cartelle della scrivania (le cartelle dell'autore), da temi/cartelle/;
//   5. chi ascolta: tema.json nella cartella dati (Cartelle.dati) + la notifica distribuita local.author.pulsar.tema
//      (Spazio la legge da /pulsar-tema; la dynamic island dell'altra chat deve fare lo stesso).
// 18/10: 3 e 4, il puntatore e lo stile delle icone sono solo della build dell'autore (Personale/temi-autore.swift);
// la vendita cambia Pulsar, l'aspetto di macOS e scrive il file e la notifica (con l'identificatore dell'app).
// Chrome non si può cambiare da fuori: i due temi sono in Apps/chrome-tema-matte e Apps/chrome-tema-white-matte.

import AppKit
import SwiftUI

enum PulsarTema: String, CaseIterable {
    case darkMatte = "dark-matte", whiteMatte = "white-matte"
    var title: String { self == .darkMatte ? "Dark Matte" : "White Matte" }
    var look: AgentMode { self == .darkMatte ? .notte : .bianco }
    var chiaro: Bool { self == .whiteMatte }

    static var attuale: PulsarTema {
        PulsarTema(rawValue: Impostazioni.string(.pulsarTema) ?? "") ?? (AgentMode.saved == .bianco ? .whiteMatte : .darkMatte)
    }
}

enum Temi {
    static let file = Cartelle.dati.appendingPathComponent("tema.json")

    /// Applica un tema a tutto. `setLook` cambia l'aspetto dell'Agente (che tiene anche il suo stato).
    static func scegli(_ t: PulsarTema, setLook: (AgentMode) -> Void) {
        Impostazioni.set(t.rawValue, .pulsarTema)
        setLook(t.look)
        scrivi(t)
        // macOS chiaro o scuro: lo stesso comando dell'interruttore Dark Mode (permesso Automazione già chiesto lì).
        // Fase 5: solo se l'interruttore "Cambia anche macOS" della pagina Aspetto è acceso (di serie sì).
        guard temaCambiaMacOS(Impostazioni.object(.temiCambiaMacOS)) else { return }
        runAppleScript(#"tell application "System Events" to tell appearance preferences to set dark mode to \#(t.chiaro ? "false" : "true")"#)
    }

    /// Il file e la notifica per chi segue Pulsar (Spazio, la dynamic island).
    static func scrivi(_ t: PulsarTema) {
        let d: [String: Any] = ["tema": t.rawValue, "chiaro": t.chiaro, "quando": Date().timeIntervalSince1970]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted]) { try? data.write(to: file) }
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("\(App.id).tema"),
                                                                     object: t.rawValue, userInfo: nil, deliverImmediately: true)
    }

}

// MARK: - Registro dei moduli (fase 2)

/// I Temi non hanno un servizio da avviare: il registro serve al menu per sapere se mostrare la scelta
/// (con Pulsar Complete) o "Sblocca con Pulsar Complete…". Bloccati, il tema già scelto resta com'è.
final class ModuloTemi: ModuloPulsar {
    var id: String { "temi" }
    var nome: String { T("Temi", "Themes") }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [.automazione] }
    var acceso: Bool { true }
    func avvia() {}
    func ferma() {}
}

// MARK: - Icone delle app dopo un cambio di stile (13/10/2026)

/// macOS legge lo stile delle icone (AppleIconAppearanceTheme) una volta sola per processo: dopo un cambio di tema
/// NSWorkspace.icon(forFile:) dentro Pulsar continua a dare lo stile vecchio (provato: nemmeno notifiche e attese
/// servono), mentre un processo nuovo lo legge giusto. Così, dal primo cambio in poi, le icone le disegna Pulsar
/// stesso lanciato di nascosto (`Pulsar --icone <cartella> <percorsi…>`, vedi rendiIcone) e qui si tengono in memoria.
/// Prima di ogni cambio si usa NSWorkspace come sempre. Chi mostra icone osserva `IconeApp.shared`.
final class IconeApp: ObservableObject {
    static let shared = IconeApp()
    @Published private(set) var versione = 0
    private var attivo = false                    // vero dal primo cambio di stile in questo processo
    private var fresche: [String: NSImage] = [:]
    private var viste = Set<String>()             // ogni percorso chiesto: al cambio si ridisegnano tutte insieme
    private var coda = Set<String>()
    private var inVolo = Set<String>()            // già chieste al processo che sta disegnando
    private var inCorso = false
    private var giro = 0                          // sale a ogni cambio: le icone di un giro vecchio si scartano
    private var attesa: DispatchWorkItem?
    private var osservatore: NSObjectProtocol?

    private init() {
        // anche quando lo stile lo cambia Impostazioni di Sistema
        osservatore = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleIconAppearanceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.stileCambiato()
        }
    }

    func icona(_ path: String) -> NSImage {
        viste.insert(path)
        guard attivo else { return NSWorkspace.shared.icon(forFile: path) }
        if let i = fresche[path] { return i }
        chiedi([path])
        return NSWorkspace.shared.icon(forFile: path)     // per un attimo, finché arriva quella giusta
    }

    func icona(bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { icona($0.path) }
    }

    /// Lo stile delle icone è cambiato: si buttano quelle in memoria e si ridisegnano tutte quelle già viste.
    func stileCambiato() {
        attesa?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.attivo = true
            self.giro += 1
            self.fresche = [:]
            self.coda.formUnion(self.viste)
            self.versione += 1
            self.esegui()
        }
        attesa = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)    // una notifica e la chiamata diretta: un giro solo
    }

    private func chiedi(_ paths: [String]) {
        let nuovi = paths.filter { !coda.contains($0) && !inVolo.contains($0) }
        guard !nuovi.isEmpty else { return }
        coda.formUnion(nuovi)
        DispatchQueue.main.async { [weak self] in self?.esegui() }
    }

    private func esegui() {
        guard !inCorso, !coda.isEmpty, let exe = Bundle.main.executablePath else { return }
        inCorso = true
        let paths = Array(coda); coda = []; inVolo = Set(paths)
        let g = giro
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pulsar-icone-" + UUID().uuidString)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = ["--icone", dir.path] + paths
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            var lette: [String: NSImage] = [:]
            if (try? p.run()) != nil {
                p.waitUntilExit()
                for (i, path) in paths.enumerated() {
                    if let img = NSImage(contentsOf: dir.appendingPathComponent("\(i).png")) {
                        img.size = NSSize(width: 128, height: 128); lette[path] = img
                    }
                }
            }
            try? FileManager.default.removeItem(at: dir)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inCorso = false; self.inVolo = []
                // se intanto lo stile è cambiato di nuovo, queste sono vecchie: rifà il giro con la coda nuova
                if g == self.giro {
                    // un'icona che il processo non ha saputo disegnare resta quella di NSWorkspace: niente giri a vuoto
                    for path in paths { self.fresche[path] = lette[path] ?? NSWorkspace.shared.icon(forFile: path) }
                } else { self.coda.formUnion(paths) }
                self.versione += 1
                self.esegui()
            }
        }
    }
}

extension IconeApp {
    func prova() {
        func luce(_ img: NSImage) -> Double {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return -1 }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64)); NSGraphicsContext.restoreGraphicsState()
            var s = 0.0, n = 0.0
            for x in 0..<64 { for y in 0..<64 { if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 { s += c.brightnessComponent; n += 1 } } }
            return n > 0 ? s / n : -1
        }
        var txt = "stile=\(Impostazioni.string(.appleIconAppearanceTheme) ?? "-") versione=\(versione)\n"
        for e in RecentApps.shared.entries.prefix(5) {
            guard let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundle) else { continue }
            txt += String(format: "%@ pulsar=%.2f nsworkspace=%.2f\n", e.name, luce(icona(u.path)), luce(NSWorkspace.shared.icon(forFile: u.path)))
        }
        let dir = Cartelle.dati
        try? txt.write(to: dir.appendingPathComponent("icone.txt"), atomically: true, encoding: .utf8)
    }
}

/// Il lato "processo nuovo": disegna l'icona di ogni percorso in <cartella>/<n>.png (256 px) ed esce.
func rendiIcone(_ args: [String]) -> Never {
    guard let dir = args.first else { exit(1) }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (i, path) in args.dropFirst().enumerated() {
        let img = NSWorkspace.shared.icon(forFile: path)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(i).png"))
    }
    exit(0)
}
