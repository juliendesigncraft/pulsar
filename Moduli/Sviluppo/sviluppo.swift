// La barra di sviluppo (07/11/2026, dal reel di ZincWolf MenuBar, l'autore: "nella barra in alto").
// Tre voci accanto a Pulsar, a destra del separatore della Barra pulita (restano sempre in vista):
//  - il branch Git del progetto su cui lavora Claude Code (cwd dell'ultima sessione in agente/state.json), o di uno scelto;
//  - i server di sviluppo accesi, per porta (lsof), con apri, copia, cartella e ferma;
//  - quanto resta del limite di Claude, esatto: il token di Claude Code dal Portachiavi (macOS chiede il permesso la
//    prima volta) e la stessa risposta di /usage. Pulsar non rinnova mai il token e non lo scrive da nessuna parte.
// Spenta di serie, si accende dal menu, dal benvenuto o dalla pagina Sviluppo. La logica pura sta in sviluppo-logica.swift.
import AppKit
import Security

final class ModuloBarraSviluppo: NSObject, ModuloPulsar {
    static let shared = ModuloBarraSviluppo()
    var id: String { "barradev" }
    var nome: String { T("Barra di sviluppo", "Developer bar") }
    var prodotto: Prodotto { .agent }
    var permessi: [Permesso] { [] }
    var acceso: Bool {
        get { Impostazioni.bool(.barraDevAcceso) }
        set { Impostazioni.set(newValue, .barraDevAcceso); RegistroModuli.shared.riapplica() }
    }

    /// Quali delle tre voci mostrare (tutte di serie).
    enum Voce: String, CaseIterable { case branch, server, limite }
    static func mostra(_ v: Voce) -> Bool { (Impostazioni.dictionary(.barraDevVoci) as? [String: Bool])?[v.rawValue] ?? true }
    static func imposta(_ v: Voce, _ on: Bool) {
        var d = (Impostazioni.dictionary(.barraDevVoci) as? [String: Bool]) ?? [:]
        d[v.rawValue] = on
        Impostazioni.set(d, .barraDevVoci)
        if shared.avviato { shared.ferma(); shared.avvia() }
    }

    private var voci: [Voce: NSStatusItem] = [:]
    private var timer: Timer?
    private(set) var avviato = false
    private let coda = DispatchQueue(label: "pulsar.barradev", qos: .utility)

    private(set) var progetto: String?            // la cartella del repo che si guarda
    private(set) var git: StatoGit?
    private(set) var progettiRecenti: [String] = []
    private(set) var server: [ServerAcceso] = []
    private(set) var limite: LimiteClaude?
    private(set) var limiteErrore: String?
    private(set) var limiteLetto: Date?
    private var giri = 0

    func avvia() {
        guard !avviato else { return }
        avviato = true
        // a destra di Pulsar (420): numero più basso = più a destra. Un ⌘-trascina le sposta e macOS ricorda dove.
        let seme: [(Voce, Double)] = [(.branch, 330), (.server, 320), (.limite, 310)]
        for (v, p) in seme where Self.mostra(v) {
            let nome = "pulsar.dev.\(v.rawValue)"
            if BarraOrdine.leggi(nome) == nil { BarraOrdine.scrivi(nome, p) }    // chiave di sistema "NSStatusItem Preferred Position <nome>"
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            it.autosaveName = nome
            let m = NSMenu(); m.delegate = self; m.autoenablesItems = false
            it.menu = m
            voci[v] = it
        }
        disegna()
        aggiorna(tutto: true)
        timer = Timer.scheduledTimer(withTimeInterval: Leggera.on ? 20 : 8, repeats: true) { [weak self] _ in self?.aggiorna(tutto: false) }
    }

    func ferma() {
        timer?.invalidate(); timer = nil
        for it in voci.values { NSStatusBar.system.removeStatusItem(it) }
        voci = [:]
        avviato = false
    }

    // MARK: letture

    private func aggiorna(tutto: Bool) {
        giri += 1
        coda.async { [weak self] in
            guard let self else { return }
            let recenti = Self.progettiDaClaude()
            let scelto = Impostazioni.string(.barraDevProgetto)
            let p = (scelto.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }) ?? recenti.first
            let g = p.flatMap { Self.esegui("/usr/bin/git", ["-C", $0, "status", "--porcelain=v1", "-b"]) }.flatMap(LetturaGit.leggi)
            var s = LetturaServer.leggi(Self.esegui("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]) ?? "")
            for i in s.indices { s[i].cartella = Self.cartella(di: s[i].pid) }
            DispatchQueue.main.async {
                self.progettiRecenti = recenti; self.progetto = p; self.git = g; self.server = s
                self.disegna()
            }
        }
        // il limite ogni 5 minuti: Anthropic lo aggiorna di continuo ma non serve chiederlo più spesso
        if Self.mostra(.limite), !negato, tutto || (limiteLetto.map { Date().timeIntervalSince($0) > 300 } ?? true) { leggiLimite() }
    }

    /// Se si è detto no al Portachiavi non si richiede da soli: solo con "Aggiorna adesso".
    private var negato = false
    private var leggendo = false

    /// `chiedendo`: solo il tasto Aggiorna adesso può far comparire la richiesta del Portachiavi. La letture a tempo non la mostrano mai:
    /// macOS lega il permesso alla singola compilazione, quindi a ogni build la richiesta tornava da sola (09/11, l'autore: "ogni tot").
    func leggiLimite(chiedendo: Bool = false) {
        guard !leggendo else { return }
        leggendo = true
        limiteLetto = Date()
        // 07/11: fuori dal filo principale. La prima volta macOS mostra la richiesta del Portachiavi e la lettura
        // aspetta la risposta: sul filo principale Pulsar restava ferma (prova del 07/11, nessun aggiornamento per 20 s).
        coda.async { [weak self] in
            let (dati, stato) = Self.credenziali(chiedendo: chiedendo)
            DispatchQueue.main.async {
                guard let self else { return }
                if stato == errSecUserCanceled || stato == errSecAuthFailed || stato == errSecInteractionNotAllowed {
                    self.negato = true; self.leggendo = false
                    self.limiteErrore = T("Serve il permesso: Aggiorna adesso", "Permission needed: Refresh now")
                    self.limite = nil; self.disegna(); return
                }
                self.negato = false
                guard let dati, let token = LetturaLimite.token(dati) else {
                    self.leggendo = false
                    self.limiteErrore = T("Apri Claude Code per collegarlo", "Open Claude Code to connect it"); self.limite = nil; self.disegna(); return
                }
                self.chiedi(token)
            }
        }
    }

    private func chiedi(_ token: String) {
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        URLSession.shared.dataTask(with: r) { [weak self] d, resp, _ in
            let codice = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let l = d.flatMap(LetturaLimite.leggi)
            DispatchQueue.main.async {
                guard let self else { return }
                self.leggendo = false
                if let l { self.limite = l; self.limiteErrore = nil }
                else { self.limiteErrore = codice == 401 ? T("Accesso scaduto: apri Claude Code", "Sign-in expired: open Claude Code")
                                                         : T("Anthropic non risponde, riprovo fra poco", "Anthropic is not answering, retrying soon") }
                self.disegna()
            }
        }.resume()
    }

    /// Il JSON delle credenziali di Claude Code dal Portachiavi di login. La prima volta macOS chiede se Pulsar può leggerlo.
    private static func credenziali(chiedendo: Bool) -> (Data?, OSStatus) {
        // Vale per tutto il processo: si rimette a posto subito dopo la lettura.
        if !chiedendo { SecKeychainSetUserInteractionAllowed(false) }
        defer { if !chiedendo { SecKeychainSetUserInteractionAllowed(true) } }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "Claude Code-credentials",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        return (st == errSecSuccess ? out as? Data : nil, st)
    }

    /// Le cartelle delle ultime sessioni di Claude Code (dall'hook dell'Agente), dalla più recente, senza doppioni.
    private static func progettiDaClaude() -> [String] {
        let url = AgentStore.dir.appendingPathComponent("state.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let ss = o["sessions"] as? [String: [String: Any]] else { return [] }
        var visti = Set<String>()
        return ss.values.sorted { ($0["updated"] as? Double ?? 0) > ($1["updated"] as? Double ?? 0) }
            .compactMap { $0["cwd"] as? String }.filter { !$0.isEmpty && visti.insert($0).inserted }
            .prefix(6).map { $0 }
    }

    /// 13/11, "alleggerisci Pulsar": la cartella di lavoro di un processo si legge dal sistema (proc_pidinfo) e si ricorda
    /// per pid, invece di lanciare un lsof a ogni server a ogni giro.
    private static var cartelle: [Int32: String] = [:]
    private static let bloccoCartelle = NSLock()
    private static func cartella(di pid: Int32) -> String {
        bloccoCartelle.lock(); defer { bloccoCartelle.unlock() }
        if let c = cartelle[pid] { return c }
        var info = proc_vnodepathinfo()
        let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        var c = ""
        if n == Int32(MemoryLayout<proc_vnodepathinfo>.size) {
            c = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
        if cartelle.count > 200 { cartelle.removeAll() }
        cartelle[pid] = c
        return c
    }

    private static func esegui(_ exe: String, _ args: [String]) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let d = o.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: d, encoding: .utf8) : nil
    }

    // MARK: la barra

    private func disegna() {
        func metti(_ v: Voce, _ simbolo: String, _ testo: String, _ aiuto: String) {
            guard let b = voci[v]?.button else { return }
            b.image = NSImage(systemSymbolName: simbolo, accessibilityDescription: aiuto)
            b.image?.isTemplate = true
            b.imagePosition = testo.isEmpty ? .imageOnly : .imageLeading
            b.attributedTitle = NSAttributedString(string: testo.isEmpty ? "" : " " + testo,
                                                   attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
            b.toolTip = aiuto
        }
        if let g = git { metti(.branch, "arrow.triangle.branch", g.branch + (g.modificati > 0 ? "*" : ""), T("Branch Git", "Git branch")) }
        else { metti(.branch, "arrow.triangle.branch", "", T("Nessun progetto Git", "No Git project")) }
        metti(.server, "server.rack", server.isEmpty ? "" : "\(server.count)", T("Server accesi", "Running servers"))
        if let r = limite?.restaNellaBarra { metti(.limite, "gauge.with.dots.needle.50percent", "\(r)%", T("Limite di Claude rimasto", "Claude limit left")) }
        else { metti(.limite, "gauge.with.dots.needle.0percent", "", limiteErrore ?? T("Limite di Claude", "Claude limit")) }
        // registro di cosa mostra la barra (solo quando cambia): con la barra dei menu nascosta è l'unico modo di controllarla
        let riga = Voce.allCases.compactMap { v in voci[v].map { "\(v.rawValue)=[\($0.button?.title.trimmingCharacters(in: .whitespaces) ?? "")]" } }.joined(separator: " ")
            + " progetto=\(progetto.map(LetturaServer.nomeCartella) ?? "-") server=\(server.map { String($0.porta) }.joined(separator: ","))"
            + (limiteErrore.map { " limite: \($0)" } ?? "")
        if riga != ultimaRiga { ultimaRiga = riga; Self.log(riga) }
    }
    private var ultimaRiga = ""
    private static func log(_ s: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Pulsar-sviluppo.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func titolo(_ s: String) -> NSMenuItem { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }
    private func voce(_ s: String, _ a: Selector?, _ dato: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: a, keyEquivalent: ""); i.target = self; i.representedObject = dato; return i
    }

    fileprivate func riempi(_ m: NSMenu, _ v: Voce) {
        m.removeAllItems()
        switch v {
        case .branch:
            if let p = progetto {
                m.addItem(titolo(LetturaServer.nomeCartella(p)))
                if let g = git {
                    m.addItem(voce(g.branch, #selector(copia(_:)), g.branch))
                    m.addItem(titolo(g.modificati == 0 ? T("Niente da salvare", "Nothing to commit")
                                                       : T("\(g.modificati) file cambiati", "\(g.modificati) changed files")))
                    if g.avanti + g.indietro > 0 {
                        m.addItem(titolo(T("\(g.avanti) da mandare, \(g.indietro) da prendere", "\(g.avanti) to push, \(g.indietro) to pull")))
                    }
                } else { m.addItem(titolo(T("Questa cartella non usa Git", "This folder does not use Git"))) }
                if ModuloTerminale.shared.inEsecuzione { m.addItem(voce(T("Apri nel Terminale del notch", "Open in the notch Terminal"), #selector(apriTerminale(_:)), p)) }
                m.addItem(voce(T("Mostra nel Finder", "Show in Finder"), #selector(mostra(_:)), p))
            } else {
                m.addItem(titolo(T("Nessuna sessione di Claude Code", "No Claude Code session")))
            }
            m.addItem(.separator())
            m.addItem(titolo(T("Progetto da seguire", "Project to follow")))
            let scelto = Impostazioni.string(.barraDevProgetto)
            let segui = voce(T("L'ultimo di Claude Code", "Claude Code's latest"), #selector(scegli(_:)), "")
            segui.state = scelto == nil ? .on : .off
            m.addItem(segui)
            for p in progettiRecenti {
                let i = voce(LetturaServer.nomeCartella(p), #selector(scegli(_:)), p); i.state = scelto == p ? .on : .off; i.toolTip = p
                m.addItem(i)
            }
            m.addItem(voce(T("Scegli una cartella…", "Choose a folder…"), #selector(scegliCartella)))
        case .server:
            if server.isEmpty { m.addItem(titolo(T("Nessun server acceso", "No servers running"))) }
            for s in server {
                let nome = s.cartella.isEmpty ? s.comando : "\(LetturaServer.nomeCartella(s.cartella))  \(s.comando)"
                let i = NSMenuItem(title: "localhost:\(s.porta)   \(nome)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                sub.addItem(voce(T("Apri nel browser", "Open in browser"), #selector(apri(_:)), s.porta))
                sub.addItem(voce(T("Copia l'indirizzo", "Copy address"), #selector(copia(_:)), "http://localhost:\(s.porta)"))
                if !s.cartella.isEmpty { sub.addItem(voce(T("Mostra la cartella", "Show folder"), #selector(mostra(_:)), s.cartella)) }
                sub.addItem(.separator())
                sub.addItem(voce(T("Ferma…", "Stop…"), #selector(fermaServer(_:)), s.pid))
                i.submenu = sub
                m.addItem(i)
            }
        case .limite:
            if let l = limite {
                let it = pulsarItalian
                func riga(_ nome: String, _ f: LimiteClaude.Finestra?) {
                    guard let f else { return }
                    let quando = f.azzera.map { ", " + T("si azzera ", "resets ") + LetturaLimite.tra($0, it: it) } ?? ""
                    m.addItem(titolo("\(nome): \(Int(f.usato.rounded()))% " + T("usato", "used") + quando))
                }
                riga(T("Sessione di 5 ore", "5-hour session"), l.cinqueOre)
                riga(T("Settimana", "Week"), l.settimana)
                riga(T("Settimana, Opus", "Week, Opus"), l.settimanaOpus)
            } else { m.addItem(titolo(limiteErrore ?? T("Lettura in corso…", "Reading…"))) }
            if let d = limiteLetto {
                let f = DateFormatter(); f.timeStyle = .short
                m.addItem(titolo(T("Letto alle ", "Read at ") + f.string(from: d)))
            }
            m.addItem(voce(T("Aggiorna adesso", "Refresh now"), #selector(rileggi)))
        }
    }

    // MARK: azioni

    @objc private func copia(_ i: NSMenuItem) {
        guard let s = i.representedObject as? String else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
    }
    @objc private func apri(_ i: NSMenuItem) {
        guard let p = i.representedObject as? Int, let u = URL(string: "http://localhost:\(p)") else { return }
        NSWorkspace.shared.open(u)
    }
    @objc private func mostra(_ i: NSMenuItem) {
        guard let p = i.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }
    @objc private func apriTerminale(_ i: NSMenuItem) {
        guard let p = i.representedObject as? String else { return }
        ModuloTerminale.shared.apri(cartella: p)
    }
    @objc private func scegli(_ i: NSMenuItem) {
        let p = i.representedObject as? String ?? ""
        Impostazioni.set(p.isEmpty ? nil : p, .barraDevProgetto)
        aggiorna(tutto: false)
    }
    @objc private func scegliCartella() {
        let pan = NSOpenPanel(); pan.canChooseDirectories = true; pan.canChooseFiles = false
        NSApp.activate(ignoringOtherApps: true)
        guard pan.runModal() == .OK, let u = pan.url else { return }
        Impostazioni.set(u.path, .barraDevProgetto)
        aggiorna(tutto: false)
    }
    @objc private func rileggi() { leggiLimite(chiedendo: true) }
    /// Ferma un server: chiede prima, poi manda SIGTERM (il programma si chiude da solo, come con ⌃C).
    @objc private func fermaServer(_ i: NSMenuItem) {
        guard let pid = i.representedObject as? Int32, let s = server.first(where: { $0.pid == pid }) else { return }
        let a = NSAlert()
        a.messageText = T("Fermare il server su localhost:\(s.porta)?", "Stop the server on localhost:\(s.porta)?")
        a.informativeText = T("Si chiude \(s.comando) (processo \(pid)), come con ⌃C nel suo terminale.",
                              "This quits \(s.comando) (process \(pid)), like ⌃C in its terminal.")
        a.addButton(withTitle: T("Ferma", "Stop")); a.addButton(withTitle: T("Annulla", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.aggiorna(tutto: false) }
    }
}

extension ModuloBarraSviluppo: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let v = voci.first(where: { $0.value.menu === menu })?.key else { return }
        if v == .limite, !negato, limiteLetto.map({ Date().timeIntervalSince($0) > 60 }) ?? true { leggiLimite() }
        riempi(menu, v)
    }
}
