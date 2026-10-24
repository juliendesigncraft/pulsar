// Licenza dal vivo (fase 2, compito 5): Portachiavi, chiamata a Gumroad e la finestra "Licenza…".
// La logica pura sta in Core/Licenza.swift; qui solo ciò che tocca il mondo: UserDefaults, Portachiavi, rete, NSAlert.
// Le chiavi vivono SOLO nel Portachiavi (servizio "<App.id>.licenza", un elemento per prodotto, account = rawValue):
// mai in UserDefaults, mai in un log o in un messaggio.
// Nella build dell'autore (PERSONALE) tutto è sbloccato e non si va mai in rete.
import AppKit
import Security

/// Dove stanno le chiavi, una per prodotto. Nell'app è il Portachiavi; nelle prove a mano una versione in memoria.
protocol CassaforteChiavi: AnyObject {
    func leggi(_ p: Prodotto) -> String?
    func salva(_ chiave: String, per p: Prodotto)
    func togli(_ p: Prodotto)
}

final class LicenzaViva {
    static let shared = LicenzaViva()

    /// Chiamata (sul thread principale) quando cambia cosa è sbloccato.
    var onChange: (() -> Void)?

    private static let timeout: TimeInterval = 10
    private let cassaforte: CassaforteChiavi
    /// Sul thread principale: cresce a ogni `inserisci`. Un controllo d'avvio partito prima viene scartato,
    /// così un risultato tardivo non sovrascrive la chiave appena inserita.
    private var generazione = 0

    init(cassaforte: CassaforteChiavi = Portachiavi(servizio: "\(App.id).licenza")) {
        self.cassaforte = cassaforte
    }

    // MARK: Stato in UserDefaults

    /// Lo stato salvato. Prodotti illeggibili = insieme vuoto (non una prova nuova).
    /// `provaDal` illeggibile (valore presente ma non una data) = prova già finita: uno stato rovinato non regala giorni.
    /// `provaDal` mancante del tutto: si usa "adesso" (lo scrive `avvio`).
    private var stato: StatoLicenza {
        let grezzi = Impostazioni.stringArray(.licenzaProdotti) ?? []
        let prodotti = Set(grezzi.compactMap(Prodotto.init(rawValue:)))
        let controllo = Impostazioni.object(.licenzaControllo) as? Date
        let provaDal: Date
        if let v = Impostazioni.object(.licenzaProvaDal) { provaDal = (v as? Date) ?? .distantPast } else { provaDal = Date() }
        return StatoLicenza(prodotti: prodotti, ultimoControllo: controllo, provaDal: provaDal)
    }

    /// Salva prodotti e data del controllo. `provaDal` non si riscrive mai qui: lo scrive solo `avvio`, e solo se manca.
    private func salva(_ s: StatoLicenza) {
        Impostazioni.set(s.prodotti.map(\.rawValue).sorted(), .licenzaProdotti)
        if let u = s.ultimoControllo { Impostazioni.set(u, .licenzaControllo) }
    }

    var sbloccati: Set<Prodotto> {
        #if DA_SORGENTE
        return Set(Prodotto.allCases)   // compilata dal codice: tutto sbloccato
        #else
        return Licenza.sbloccati(stato, ora: Date(), personale: false)
        #endif
    }

    var giorniProvaRimasti: Int { Licenza.giorniProvaRimasti(stato, ora: Date()) }

    /// La riga sotto "Licenza…" nel menu: "Prova: N giorni" finché dura, poi i prodotti comprati (o Lite).
    var riassunto: String {
        #if DA_SORGENTE
        return T("Compilata dal codice: tutto sbloccato", "Built from source: everything unlocked")
        #endif
        let g = giorniProvaRimasti
        if g > 0 {
            let prova = g == 1 ? T("Prova di Complete: 1 giorno", "Complete trial: 1 day") : T("Prova di Complete: \(g) giorni", "Complete trial: \(g) days")
            // durante la prova si vede anche cosa è stato comprato
            let comprati = stato.prodotti.subtracting([.lite])
            return comprati.isEmpty ? prova : Licenza.nomiComprati(comprati) + ". " + prova
        }
        return Licenza.nomiComprati(stato.prodotti)
    }

    // MARK: Avvio

    /// Al primo avvio segna l'inizio della prova; poi, se è passato abbastanza tempo, ricontrolla in background ogni
    /// prodotto salvato con la sua chiave, solo sul suo ID Gumroad. Senza rete o se Gumroad non risponde non cambia niente.
    func avvio() {
        #if DA_SORGENTE
        return
        #endif
        avviaOrologio()
        if Impostazioni.object(.licenzaProvaDal) == nil { Impostazioni.set(Date(), .licenzaProvaDal) }
        controllaSeServe()
    }

    /// La parte di rete del controllo dei 30 giorni: all'avvio e ogni ora (se l'app resta aperta a lungo).
    private func controllaSeServe() {
        guard Licenza.serveControllo(stato, ora: Date()) else { return }
        let g = generazione
        let salvati = stato.prodotti
        DispatchQueue.global(qos: .utility).async {
            let richieste = salvati.compactMap { p -> (Prodotto, String)? in self.cassaforte.leggi(p).map { (p, $0) } }
            guard !richieste.isEmpty else { return }
            Self.controlla(richieste) { esiti in
                DispatchQueue.main.async { self.applicaControllo(esiti, generazione: g) }
            }
        }
    }

    /// Ultimo insieme di prodotti comunicato a `onChange` (o visto all'avvio dell'orologio).
    private var notificati: Set<Prodotto>?
    private var orologio: Timer?

    /// Ogni ora ricalcola `sbloccati` (calcolo locale): se la prova di 7 giorni scade con l'app
    /// aperta, `onChange` parte e il registro ferma i moduli. In PERSONALE non esiste.
    private func avviaOrologio() {
        guard orologio == nil else { return }
        notificati = sbloccati
        orologio = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ora = self.sbloccati
            if ora != self.notificati { self.notificati = ora; self.onChange?() }
            self.controllaSeServe()
        }
    }

    private func applicaControllo(_ esiti: [Prodotto: EsitoControllo], generazione g: Int) {
        guard g == generazione else { return }   // nel frattempo è stata inserita una chiave: vince quella
        let prima = sbloccati
        var s = stato
        let restano = Licenza.aggiorna(s.prodotti, esiti: esiti)
        for p in s.prodotti.subtracting(restano) { cassaforte.togli(p) }
        s.prodotti = restano
        // con anche un solo "rete assente" non si segna il controllo: al prossimo avvio si riprova
        if !esiti.values.contains(.reteAssente) { s.ultimoControllo = Date() }
        salva(s)
        if sbloccati != prima { notificati = sbloccati; onChange?() }
    }

    // MARK: Inserire una chiave

    /// Prova la chiave sui tre prodotti. Per ogni prodotto valido la chiave va nel Portachiavi sotto quel prodotto,
    /// che si aggiunge a quelli già comprati. Una chiave che non vale (o la rete assente) non cambia niente.
    func inserisci(chiave: String, fatto: @escaping (Bool) -> Void) {
        prova(chiave: chiave) { esiti in fatto(esiti.values.contains { if case .valida = $0 { return true }; return false }) }
    }

    private func prova(chiave grezza: String, fatto: @escaping ([Prodotto: EsitoControllo]) -> Void) {
        generazione += 1
        let chiave = grezza.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chiave.isEmpty else { fatto([:]); return }
        let richieste = Licenza.idGumroad.keys.map { ($0, chiave) }
        Self.controlla(richieste) { esiti in
            DispatchQueue.main.async {
                let validi = Set(esiti.compactMap { p, e -> Prodotto? in if case .valida = e { return p }; return nil })
                if !validi.isEmpty {
                    self.generazione += 1
                    for p in validi { self.cassaforte.salva(chiave, per: p) }
                    let prima = self.sbloccati
                    var s = self.stato
                    s.prodotti.formUnion(validi)
                    s.ultimoControllo = Date()   // appena verificata: il primo riavvio non rifà il controllo
                    self.salva(s)
                    if self.sbloccati != prima { self.notificati = self.sbloccati; self.onChange?() }
                }
                fatto(esiti)
            }
        }
    }

    // MARK: Finestra

    /// Chiede la chiave con un NSAlert, poi dice cosa è sbloccato o che la chiave non vale.
    func chiedi() {
        let alert = NSAlert()
        alert.messageText = T("Licenza di Pulsar", "Pulsar license")
        let g = giorniProvaRimasti
        let giorni = g > 0
            ? (g == 1 ? T("Resta 1 giorno di prova di Pulsar Complete.", "1 day left in the Pulsar Complete trial.")
                      : T("Restano \(g) giorni di prova di Pulsar Complete.", "\(g) days left in the Pulsar Complete trial."))
            : T("La prova è finita. Adesso: \(riassunto).", "The trial is over. Now: \(riassunto).")
        let cosa = T("""
            Pulsar Agent: Claude Code dal vivo nel notch e nel pannello.
            Pulsar Mixer: la ghiera del suono, app per app.
            Pulsar Complete: tutto, con Isola, Griglia, Voce e Temi.
            Pulsar Lite resta sempre gratis.
            """, """
            Pulsar Agent: Claude Code live in the notch and the side panel.
            Pulsar Mixer: the sound dial, app by app.
            Pulsar Complete: everything, with Island, Grid, Voice and Themes.
            Pulsar Lite is always free.
            """)
        alert.informativeText = giorni + "\n\n" + cosa + "\n\n" + T("Incolla la chiave ricevuta da Gumroad:", "Paste the key you got from Gumroad:")
        let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        campo.placeholderString = "XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX"
        alert.accessoryView = campo
        alert.addButton(withTitle: T("Attiva", "Activate"))
        alert.addButton(withTitle: T("Annulla", "Cancel"))
        alert.window.initialFirstResponder = campo
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        prova(chiave: campo.stringValue) { [weak self] esiti in self?.mostraEsito(esiti) }
    }

    private func mostraEsito(_ dizionario: [Prodotto: EsitoControllo]) {
        let alert = NSAlert()
        let esiti = Array(dizionario.values)
        let validi = esiti.contains { if case .valida = $0 { return true }; return false }
        if validi {
            alert.messageText = T("Fatto, grazie!", "Done, thank you!")
            alert.informativeText = T("Sbloccato: \(riassuntoComprati).", "Unlocked: \(riassuntoComprati).")
        } else if esiti.contains(.reteAssente) {
            // nessun esito valido ma almeno un prodotto non ha risposto: non si può dire che la chiave non vale
            alert.messageText = T("Gumroad non risponde", "Gumroad is not answering")
            alert.informativeText = T("Controlla la connessione, o riprova più tardi. Non è cambiato niente.", "Check your connection, or try again later. Nothing has changed.")
        } else {
            alert.messageText = T("Questa chiave non vale", "This key is not valid")
            alert.informativeText = T("Controlla di averla copiata tutta, dalla mail di Gumroad. Non è cambiato niente.",
                                      "Check that you copied all of it from the Gumroad email. Nothing has changed.")
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// I prodotti comprati, senza contare la prova (dopo un'attivazione si dice cosa resta anche a prova finita).
    /// I prodotti comprati a parole (Pulsar Lite se nessuno): anche per la pagina Licenza delle Impostazioni.
    var riassuntoComprati: String { Licenza.nomiComprati(stato.prodotti) }

    // MARK: Rete

    private static var indirizzo: URL {
        #if PROVA_LICENZA
        // solo nelle prove a mano (EXTRA="-D PROVA_LICENZA" ./compila.sh ...): un server finto in locale
        if let s = ProcessInfo.processInfo.environment["PULSAR_GUMROAD_URL"], let u = URL(string: s) { return u }
        #endif
        return URL(string: "https://api.gumroad.com/v2/licenses/verify")!
    }

    /// Una richiesta per ogni coppia (prodotto, chiave), sull'ID Gumroad di quel prodotto, tutte in parallelo,
    /// 10 secondi al massimo ciascuna. `fatto` arriva su un thread qualsiasi con un esito per prodotto.
    static func controlla(_ richieste: [(Prodotto, String)], fatto: @escaping ([Prodotto: EsitoControllo]) -> Void) {
        let gruppo = DispatchGroup()
        let blocco = NSLock()
        var esiti: [Prodotto: EsitoControllo] = [:]
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let sessione = URLSession(configuration: config)
        for (prodotto, chiave) in richieste {
            guard let id = Licenza.idGumroad[prodotto] else { continue }
            var r = URLRequest(url: indirizzo, timeoutInterval: timeout)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = modulo(["product_id": id, "license_key": chiave, "increment_uses_count": "false"])
            gruppo.enter()
            sessione.dataTask(with: r) { data, risposta, errore in
                let codice = errore == nil ? (risposta as? HTTPURLResponse)?.statusCode : nil
                let esito = Licenza.esitoDi(prodotto, status: codice, data: data)
                blocco.lock(); esiti[prodotto] = esito; blocco.unlock()
                gruppo.leave()
            }.resume()
        }
        gruppo.notify(queue: .global(qos: .utility)) {
            sessione.finishTasksAndInvalidate()
            fatto(esiti)
        }
    }

    private static func modulo(_ campi: [String: String]) -> Data {
        var ok = CharacterSet.alphanumerics
        ok.insert(charactersIn: "-._~")
        let righe = campi.sorted { $0.key < $1.key }.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: ok) ?? "")"
        }
        return Data(righe.joined(separator: "&").utf8)
    }
}

// MARK: - Portachiavi

/// Le chiavi nel Portachiavi: password generiche, un elemento per prodotto (account = rawValue del prodotto).
final class Portachiavi: CassaforteChiavi {
    private let servizio: String
    init(servizio: String) { self.servizio = servizio }

    private func domanda(_ p: Prodotto) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servizio,
         kSecAttrAccount as String: p.rawValue]
    }

    func leggi(_ p: Prodotto) -> String? {
        var q = domanda(p)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func salva(_ chiave: String, per p: Prodotto) {
        let dati = Data(chiave.utf8)
        if SecItemUpdate(domanda(p) as CFDictionary, [kSecValueData as String: dati] as CFDictionary) == errSecItemNotFound {
            var q = domanda(p)
            q[kSecValueData as String] = dati
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    func togli(_ p: Prodotto) { SecItemDelete(domanda(p) as CFDictionary) }
}
