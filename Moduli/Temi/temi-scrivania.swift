// Temi per chi compra (25/10/2026): Dark Matte e White Matte cambiano anche lo sfondo e le cartelle scelte, come nella
// build dell'autore, ma senza niente di suo. Regola del 24/10: nei video e nella vendita si mostra solo ciò che chi compra
// riceve, e il reel 49 mostra lo sfondo che cambia.
//   - Interruttore "Cambia anche sfondo e cartelle" nella pagina Aspetto, spento di serie. Accenderlo chiede prima:
//     solo dopo il sì si salvano lo sfondo di ogni schermo e le icone delle cartelle (temi-originali.json).
//   - Sfondi: i due Matte in Moduli/Temi/risorse (temi/genera.py vendita), copiati in Cartelle.dati/Temi così
//     non si rompono se l'app viene spostata o aggiornata. Icone: una cartella Matte senza simbolo per ogni tema.
//   - Le cartelle sono solo quelle in lista (Aggiungi…, o tutte quelle sulla Scrivania): nessun'altra si tocca.
//   - Spento rimette tutto com'era; togliere una cartella dalla lista la rimette subito.
// Limite di macOS: lo sfondo cambia solo nello Spazio aperto (negli altri resta, salvo "Mostra su tutti gli Spazi").
// Nella build dell'autore resta Personale/temi-autore.swift: questo si compila ma Temi.scegli non lo chiama.
import AppKit

enum TemiScrivania {
    static let cartellaTemi = Cartelle.dati.appendingPathComponent("Temi")
    static let fileOriginali = cartellaTemi.appendingPathComponent("temi-originali.json")
    static let cartellaIcone = cartellaTemi.appendingPathComponent("icone-originali")

    static var acceso: Bool { LogicaScrivania.acceso(Impostazioni.object(.temiScrivania)) }
    static var cartelle: [String] { Impostazioni.stringArray(.temiCartelle) ?? [] }

    // MARK: - Interruttore

    /// Chiede, salva com'è adesso e applica il tema in uso. Falso se la persona ha detto no.
    @discardableResult
    static func accendi() -> Bool {
        let a = NSAlert()
        a.messageText = T("Cambiare anche sfondo e cartelle?", "Change the wallpaper and folders too?")
        a.informativeText = T("Pulsar salva lo sfondo e le icone delle cartelle di adesso e li rimette quando spegni. Le cartelle sono solo quelle che aggiungi alla lista.",
                              "Pulsar saves your current wallpaper and folder icons and puts them back when you turn this off. Only the folders you add to the list change.")
        a.addButton(withTitle: T("Accendi", "Turn On"))
        a.addButton(withTitle: T("Annulla", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        return accendiDopoIlSi()
    }

    /// Salva com'è adesso e applica il tema in uso, senza chiedere (la usa anche prove/temi-vivo).
    @discardableResult
    static func accendiDopoIlSi() -> Bool {
        // se un giro di prima non ha finito (Pulsar chiusa a metà) si tiene quello: è lo sfondo vero di prima
        var o = OriginaliScrivania.leggi(fileOriginali) ?? OriginaliScrivania()
        if o.sfondi.isEmpty { o.sfondi = sfondiAttuali() }
        for c in cartelle where o.cartelle[c] == nil { o.cartelle[c] = IconeCartella.salva(c, in: cartellaIcone) }
        do { try o.scrivi(fileOriginali) } catch { NSLog("Temi: non salvo gli originali: %@", "\(error)"); return false }
        Impostazioni.set(true, .temiScrivania)
        applica(PulsarTema.attuale)
        return true
    }

    /// Rimette sfondo e icone salvati e cancella le copie.
    static func spegni() {
        Impostazioni.set(false, .temiScrivania)
        guard let o = OriginaliScrivania.leggi(fileOriginali) else { return }
        rimettiSfondi(o.sfondi)
        for (c, nome) in o.cartelle { IconeCartella.rimetti(c, nome: nome, da: cartellaIcone) }
        try? FileManager.default.removeItem(at: fileOriginali)
        try? FileManager.default.removeItem(at: cartellaIcone)
    }

    // MARK: - Tema

    /// Sfondo e cartelle del tema `t`, se l'interruttore è acceso. Sul filo principale (setIcon da un altro fallisce).
    static func applica(_ t: PulsarTema) {
        guard acceso else { return }
        if let u = sfondo(t) {
            for s in NSScreen.screens { try? NSWorkspace.shared.setDesktopImageURL(u, for: s, options: [:]) }
        }
        icone(t, su: cartelle)
    }

    private static func icone(_ t: PulsarTema, su lista: [String]) {
        guard let img = risorsa("cartella-\(t.chiaro ? "white" : "dark").png").flatMap(NSImage.init(contentsOf:)) else {
            NSLog("Temi: manca l'icona della cartella nel pacchetto"); return
        }
        for c in lista { IconeCartella.metti(img, su: c) }
    }

    private static func risorsa(_ nome: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("temi-vendita/\(nome)")
    }

    /// Lo sfondo del tema copiato in Cartelle.dati/Temi (una volta, o di nuovo se il pacchetto ne ha uno diverso).
    private static func sfondo(_ t: PulsarTema) -> URL? {
        let nome = "sfondo-\(t.chiaro ? "white" : "dark").jpg"
        guard let src = risorsa(nome) else { return nil }
        let dst = cartellaTemi.appendingPathComponent(nome)
        let fm = FileManager.default
        func misura(_ u: URL) -> Int? { (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int) ?? nil }
        if misura(dst) != misura(src) {
            try? fm.createDirectory(at: cartellaTemi, withIntermediateDirectories: true)
            try? fm.removeItem(at: dst)
            do { try fm.copyItem(at: src, to: dst) } catch { NSLog("Temi: non copio lo sfondo: %@", "\(error)"); return nil }
        }
        return dst
    }

    // MARK: - Sfondi salvati

    private static func numero(_ s: NSScreen) -> String {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? s.localizedName
    }

    private static func sfondiAttuali() -> [String: SfondoSalvato] {
        var r: [String: SfondoSalvato] = [:]
        for s in NSScreen.screens {
            let url = NSWorkspace.shared.desktopImageURL(for: s)
            guard LogicaScrivania.daSalvare(url?.path, nostri: cartellaTemi.path), let p = url?.path else { continue }
            let o = NSWorkspace.shared.desktopImageOptions(for: s) ?? [:]
            var w = SfondoSalvato(percorso: p)
            w.scala = (o[.imageScaling] as? NSNumber)?.intValue
            w.ritaglio = (o[.allowClipping] as? NSNumber)?.boolValue
            if let c = (o[.fillColor] as? NSColor)?.usingColorSpace(.sRGB) {
                w.riempimento = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(Double.init)
            }
            r[numero(s)] = w
        }
        return r
    }

    private static func rimettiSfondi(_ sfondi: [String: SfondoSalvato]) {
        for s in NSScreen.screens {
            guard let w = LogicaScrivania.perSchermo(numero(s), in: sfondi), FileManager.default.fileExists(atPath: w.percorso) else { continue }
            var o: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if let v = w.scala { o[.imageScaling] = NSNumber(value: v) }
            if let v = w.ritaglio { o[.allowClipping] = NSNumber(value: v) }
            if let c = w.riempimento, c.count == 4 {
                o[.fillColor] = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
            }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: w.percorso), for: s, options: o)
        }
    }

    // MARK: - Lista delle cartelle

    /// Aggiunge cartelle alla lista; con l'interruttore acceso le salva prima e le cambia subito.
    static func aggiungi(_ percorsi: [String]) {
        let prima = cartelle
        let lista = LogicaScrivania.aggiungi(percorsi, a: prima)
        Impostazioni.set(lista, .temiCartelle)
        guard acceso else { return }
        let nuove = lista.filter { !prima.contains($0) }
        var o = OriginaliScrivania.leggi(fileOriginali) ?? OriginaliScrivania()
        for c in nuove where o.cartelle[c] == nil { o.cartelle[c] = IconeCartella.salva(c, in: cartellaIcone) }
        try? o.scrivi(fileOriginali)
        icone(PulsarTema.attuale, su: nuove)
    }

    /// Toglie una cartella dalla lista e, se Pulsar l'aveva cambiata, la rimette com'era.
    static func togli(_ cartella: String) {
        Impostazioni.set(cartelle.filter { $0 != cartella }, .temiCartelle)
        guard var o = OriginaliScrivania.leggi(fileOriginali), let nome = o.cartelle[cartella] else { return }
        IconeCartella.rimetti(cartella, nome: nome, da: cartellaIcone)
        o.cartelle[cartella] = nil
        try? o.scrivi(fileOriginali)
    }

    /// La finestra di macOS per scegliere una o più cartelle.
    static func scegliCartelle() {
        let pan = NSOpenPanel()
        pan.canChooseDirectories = true
        pan.canChooseFiles = false
        pan.allowsMultipleSelection = true
        pan.prompt = T("Aggiungi", "Add")
        pan.message = T("Le cartelle che cambiano col tema", "Folders that change with the theme")
        NSApp.activate(ignoringOtherApps: true)
        guard pan.runModal() == .OK else { return }
        aggiungi(pan.urls.map(\.path))
    }

    /// Le cartelle che stanno sulla Scrivania adesso (la prima volta macOS può chiedere il permesso per la Scrivania).
    static func cartelleSullaScrivania() -> [String] {
        let desk = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let chiavi: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: desk, includingPropertiesForKeys: chiavi)) ?? []
        let voci = urls.map { u -> (nome: String, cartella: Bool, pacchetto: Bool) in
            let v = try? u.resourceValues(forKeys: Set(chiavi))
            return (u.lastPathComponent, v?.isDirectory ?? false, v?.isPackage ?? false)
        }
        return LogicaScrivania.cartelleScrivania(voci).map { desk.appendingPathComponent($0).path }
    }
}
