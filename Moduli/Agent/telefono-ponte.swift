// Il ponte con l'iPhone (Pulsar Pocket), 01/11/2026.
// Un server nella rete di casa dentro Pulsar: il telefono vede cosa fa Claude Code sul Mac e risponde ai permessi.
// Solo Foundation, Network, Security e CryptoKit (niente AppKit), così lo usa anche il banco di prova `prova/ponte-prova.swift`.
//
// Regole, tutte controllate dal codice qui sotto:
//  - Spento di serie. Non ascolta finché l'autore non accende l'interruttore (Impostazioni → Claude Code → iPhone).
//  - Solo rete locale: si rifiutano le connessioni che non vengono da un indirizzo privato (10.x, 172.16-31.x, 192.168.x,
//    169.254.x, fe80::, fc00::/7, loopback). Nessun server esterno, niente passa da internet.
//  - Cifrato: TLS 1.3 con un certificato che Pulsar crea la prima volta (RSA 2048, in telefono/identita.p12, permessi 0600).
//    Il telefono ne ricorda l'impronta SHA-256 all'accoppiamento e poi accetta solo quella.
//  - Accoppiamento: codice di 6 cifre mostrato da Pulsar, vale 2 minuti, una volta sola, 5 tentativi. Poi il telefono
//    riceve un token da 256 bit; qui resta solo la sua impronta SHA-256. "Scollega" lo cancella.
//  - Il telefono può solo: leggere lo stato delle sessioni e rispondere a un permesso che l'hook sta aspettando davvero
//    (consenti, nega, sempre). Non può eseguire niente, né leggere file.
//
// Protocollo: righe JSON su TLS, una per messaggio.
//   telefono -> Mac   {"op":"pair","code":"123456","name":"iPhone di …"}   | {"op":"hello","token":"…"}
//                     {"op":"decide","id":"<permesso>","behavior":"allow|deny|always"}  | {"op":"ping"}
//                     {"op":"approve","id":"<voce>","value":true|false}   (solo se chi ospita il ponte ha dato `approva`; 01/11)
//   Mac -> telefono   {"op":"paired","token","device","mac"}  | {"op":"ready","mac","v":1}
//                     {"op":"state","sessions":[…],"theme":"notte|bianco|sfondo","t":…}  (a ogni cambiamento)  | {"op":"ack","id","ok","why"?}
//                     {"op":"hb"} ogni 15 s  | {"op":"error","why":"code|auth|…"}
import Foundation
import Network
import Security
import CryptoKit

/// Un telefono accoppiato. Il token vero sta solo sul telefono: qui c'è la sua impronta SHA-256.
struct TelefonoAccoppiato: Codable, Identifiable, Equatable {
    let id: String
    var nome: String
    let impronta: String
    let creato: Double
    var ultimo: Double
}

final class PonteTelefono: @unchecked Sendable {
    static let servizio = "_pulsarpocket._tcp"
    static let portaPredefinita: UInt16 = 47631
    /// L'hook aspetta la risposta a un permesso al massimo questi secondi (WAIT in hook.py). Dopo, il permesso passa al terminale.
    static var attesaPermesso: Double = 25      // il banco di prova la allunga (PONTE_ATTESA) per provare a mano

    /// Il pannello di Pulsar si aggiorna quando cambiano codice, telefoni o stato del server (sul filo principale).
    var onCambio: (() -> Void)?

    /// Ganci opzionali, vuoti di serie (nella vendita restano vuoti: il ponte non sa niente di Spazio).
    /// `oggi`: la vista da mandare al telefono (già filtrata da chi la dà; chiamata a ogni battito, deve essere economica).
    /// `approva`: esegue un'approvazione e dice com'è andata. Si chiama su una coda di fondo, mai sul filo principale.
    var oggi: (() -> [String: Any]?)?
    var approva: ((_ id: String, _ valore: Bool, _ fatto: @escaping (Bool, String?) -> Void) -> Void)?

    private let cartella: URL
    private let statoURL: URL
    private let porta: UInt16
    private let etichetta: String
    private let nomeMac: String
    private let risposta: (_ idPermesso: String, _ behavior: String) -> Void
    /// L'aspetto di Pulsar adesso ("notte" = Dark Matte, "bianco" = White Matte, "sfondo"): il telefono lo segue.
    private let tema: () -> String
    private let coda = DispatchQueue(label: "pulsar.ponte-telefono")

    private var listener: NWListener?
    private var clienti: [ObjectIdentifier: Cliente] = [:]
    private var timer: DispatchSourceTimer?
    private var ultimoBattito = Date.distantPast
    private var codice: (valore: String, scade: Date, tentativi: Int)?
    private var _dispositivi: [TelefonoAccoppiato] = []
    private var _stato: String = "spento"
    private var _impronta: String = ""

    private final class Cliente {
        let conn: NWConnection
        var buffer = Data()
        var dispositivo: String?                 // id del telefono, dopo hello/pair riusciti
        var ultimoInviato = Data()
        var avviato = Date()
        init(_ c: NWConnection) { conn = c }
    }

    /// - cartella: dove stanno i telefoni accoppiati (agente/telefono).
    /// - etichetta: il nome del certificato ("Pulsar Pocket"; il banco di prova ne usa un'altra).
    init(cartella: URL, statoURL: URL, porta: UInt16 = PonteTelefono.portaPredefinita, etichetta: String = "Pulsar Pocket",
         nomeMac: String = Host.current().localizedName ?? "Mac",
         tema: @escaping () -> String = { "notte" },
         risposta: @escaping (_ idPermesso: String, _ behavior: String) -> Void) {
        self.cartella = cartella
        self.statoURL = statoURL
        self.porta = porta
        self.etichetta = etichetta
        self.nomeMac = nomeMac
        self.risposta = risposta
        self.tema = tema
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        _dispositivi = Self.leggiDispositivi(cartella)
    }

    // MARK: Stato visibile al pannello

    var dispositivi: [TelefonoAccoppiato] { coda.sync { _dispositivi } }
    /// "spento", "in ascolto", "errore: …"
    var stato: String { coda.sync { _stato } }
    /// Impronta del certificato, per le Impostazioni (le prime 8 cifre bastano a riconoscerla).
    var impronta: String { coda.sync { _impronta } }
    var portaAscolto: UInt16 { porta }
    /// Il codice da mostrare e quando scade; nil se non ce n'è uno valido.
    var codiceAttivo: (valore: String, scade: Date)? {
        coda.sync { if let c = codice, c.scade > Date() { return (c.valore, c.scade) } else { return nil } }
    }
    var connessi: Int { coda.sync { clienti.values.filter { $0.dispositivo != nil }.count } }

    private func cambiato() { DispatchQueue.main.async { [weak self] in self?.onCambio?() } }

    // MARK: Accendere e spegnere

    func avvia() {
        coda.async { [self] in
            guard listener == nil else { return }
            guard let id = identita() else { _stato = "errore: certificato"; cambiato(); return }
            do {
                let tls = NWProtocolTLS.Options()
                let sec = tls.securityProtocolOptions
                guard let si = sec_identity_create(id) else { _stato = "errore: identità"; cambiato(); return }
                sec_protocol_options_set_local_identity(sec, si)
                sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
                let tcp = NWProtocolTCP.Options()
                tcp.enableKeepalive = true
                tcp.keepaliveIdle = 30
                tcp.noDelay = true
                let params = NWParameters(tls: tls, tcp: tcp)
                params.includePeerToPeer = false
                guard let p = NWEndpoint.Port(rawValue: porta) else { return }
                let l = try NWListener(using: params, on: p)
                l.service = NWListener.Service(name: nomeMac, type: Self.servizio)
                l.newConnectionHandler = { [weak self] c in self?.nuova(c) }
                l.stateUpdateHandler = { [weak self] s in
                    guard let self else { return }
                    switch s {
                    case .ready: self._stato = "in ascolto"
                    case .failed(let e): self._stato = "errore: \(e)"; self.listener?.cancel(); self.listener = nil
                    case .cancelled: self._stato = "spento"
                    default: break
                    }
                    self.cambiato()
                }
                listener = l
                l.start(queue: coda)
                _impronta = Self.impronta(di: id)
                avviaTimer()
            } catch {
                _stato = "errore: \(error.localizedDescription)"
                cambiato()
            }
        }
    }

    func ferma() {
        coda.async { [self] in
            timer?.cancel(); timer = nil
            listener?.cancel(); listener = nil
            for c in clienti.values { c.conn.cancel() }
            clienti = [:]
            codice = nil
            _stato = "spento"
            cambiato()
        }
    }

    // MARK: Accoppiamento

    /// Un codice nuovo di 6 cifre (sostituisce quello di prima). Vale 2 minuti, una volta, 5 tentativi.
    @discardableResult
    func nuovoCodice() -> String {
        let v = String(format: "%06d", Int.random(in: 0...999_999))
        coda.sync { codice = (v, Date().addingTimeInterval(120), 0) }
        cambiato()
        return v
    }

    func annullaCodice() { coda.sync { codice = nil }; cambiato() }

    func scollega(_ id: String) {
        coda.async { [self] in
            _dispositivi.removeAll { $0.id == id }
            salvaDispositivi()
            for (k, c) in clienti where c.dispositivo == id { c.conn.cancel(); clienti[k] = nil }
            cambiato()
        }
    }

    // MARK: Connessioni

    private func nuova(_ conn: NWConnection) {
        guard Self.indirizzoPrivato(conn.endpoint) else { conn.cancel(); return }   // solo rete locale
        let c = Cliente(conn)
        let key = ObjectIdentifier(c)
        clienti[key] = c
        conn.stateUpdateHandler = { [weak self] s in
            switch s {
            case .failed, .cancelled: self?.coda.async { self?.clienti[key] = nil; self?.cambiato() }
            default: break
            }
        }
        conn.start(queue: coda)
        leggi(c)
        // chi non si presenta (hello o pair) entro 10 secondi cade
        coda.asyncAfter(deadline: .now() + 10) { [weak self] in
            if c.dispositivo == nil, self?.clienti[key] != nil { c.conn.cancel(); self?.clienti[key] = nil }
        }
    }

    private func leggi(_ c: Cliente) {
        c.conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, fine, errore in
            guard let self else { return }
            if let d = data, !d.isEmpty {
                c.buffer.append(d)
                if c.buffer.count > 32768 { c.conn.cancel(); return }             // righe enormi: no
                while let i = c.buffer.firstIndex(of: 10) {
                    let riga = c.buffer[c.buffer.startIndex..<i]
                    c.buffer = Data(c.buffer[(i + 1)...])
                    if let m = try? JSONSerialization.jsonObject(with: riga) as? [String: Any] { self.messaggio(m, da: c) }
                }
            }
            if errore != nil || fine { c.conn.cancel(); return }
            self.leggi(c)
        }
    }

    private func invia(_ obj: [String: Any], a c: Cliente) {
        guard var d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        d.append(10)
        c.conn.send(content: d, completion: .contentProcessed { _ in })
    }

    /// Manda l'ultima riga e poi chiude (un `cancel()` subito dopo `send` butterebbe via la riga non ancora partita).
    private func rifiuta(_ why: String, _ c: Cliente) {
        guard var d = try? JSONSerialization.data(withJSONObject: ["op": "error", "why": why]) else { c.conn.cancel(); return }
        d.append(10)
        c.conn.send(content: d, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.conn.cancel() })
    }

    private func messaggio(_ m: [String: Any], da c: Cliente) {
        switch m["op"] as? String {
        case "pair": accoppia(m, c)
        case "hello": presenta(m, c)
        case "ping": invia(["op": "hb"], a: c)
        case "decide": decidi(m, c)
        case "approve": approvazione(m, c)
        default: invia(["op": "error", "why": "op"], a: c)
        }
    }

    private func accoppia(_ m: [String: Any], _ c: Cliente) {
        guard c.dispositivo == nil, let dato = m["code"] as? String else { invia(["op": "error", "why": "code"], a: c); return }
        guard var k = codice, k.scade > Date(), k.tentativi < 5 else {
            codice = nil; cambiato()
            rifiuta("code", c); return
        }
        guard Self.uguali(dato, k.valore) else {
            k.tentativi += 1
            codice = k.tentativi >= 5 ? nil : k
            cambiato()
            rifiuta("code", c); return
        }
        codice = nil                                                               // una volta sola
        var raw = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, raw.count, &raw) == errSecSuccess else { c.conn.cancel(); return }
        let token = Data(raw).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let nome = String(((m["name"] as? String) ?? "iPhone").prefix(40))
        let d = TelefonoAccoppiato(id: UUID().uuidString, nome: nome, impronta: Self.sha(token),
                                   creato: Date().timeIntervalSince1970, ultimo: Date().timeIntervalSince1970)
        _dispositivi.append(d)
        salvaDispositivi()
        c.dispositivo = d.id
        invia(["op": "paired", "token": token, "device": d.id, "mac": nomeMac], a: c)
        cambiato()
        pubblica(forza: true)
    }

    private func presenta(_ m: [String: Any], _ c: Cliente) {
        guard let t = m["token"] as? String, let i = _dispositivi.firstIndex(where: { Self.uguali($0.impronta, Self.sha(t)) }) else {
            rifiuta("auth", c); return
        }
        _dispositivi[i].ultimo = Date().timeIntervalSince1970
        salvaDispositivi()
        c.dispositivo = _dispositivi[i].id
        invia(["op": "ready", "mac": nomeMac, "v": 1], a: c)
        cambiato()
        pubblica(forza: true)
    }

    private func decidi(_ m: [String: Any], _ c: Cliente) {
        guard c.dispositivo != nil else { invia(["op": "error", "why": "auth"], a: c); return }
        guard let id = m["id"] as? String, let b = m["behavior"] as? String, ["allow", "deny", "always"].contains(b) else {
            invia(["op": "ack", "ok": false, "why": "form"], a: c); return
        }
        // si risponde solo a un permesso che l'hook sta aspettando davvero adesso
        let esiste = Self.vista(da: try? Data(contentsOf: statoURL), adesso: Date().timeIntervalSince1970)
            .contains { (($0["pending"] as? [String: Any])?["id"] as? String) == id }
        guard esiste else { invia(["op": "ack", "id": id, "ok": false, "why": "gone"], a: c); return }
        DispatchQueue.main.async { [risposta] in risposta(id, b) }
        invia(["op": "ack", "id": id, "ok": true], a: c)
    }

    private func approvazione(_ m: [String: Any], _ c: Cliente) {
        guard c.dispositivo != nil else { invia(["op": "error", "why": "auth"], a: c); return }
        guard let id = m["id"] as? String, id.count <= 120, let v = m["value"] as? Bool else {
            invia(["op": "ack", "id": "approve", "ok": false, "why": "form"], a: c); return
        }
        let chiave = "approve:" + id
        guard let approva else { invia(["op": "ack", "id": chiave, "ok": false, "why": "off"], a: c); return }
        approva(id, v) { [weak self] ok, perche in
            self?.coda.async {
                var r: [String: Any] = ["op": "ack", "id": chiave, "ok": ok]
                if let perche { r["why"] = perche }
                self?.invia(r, a: c)
                self?.pubblica(forza: false)
            }
        }
    }

    // MARK: Stato verso i telefoni

    private func avviaTimer() {
        let t = DispatchSource.makeTimerSource(queue: coda)
        t.schedule(deadline: .now() + 0.4, repeating: 0.4)
        t.setEventHandler { [weak self] in self?.battito() }
        t.resume()
        timer = t
    }

    private func battito() {
        pubblica(forza: false)
        if Date().timeIntervalSince(ultimoBattito) > 15 {
            ultimoBattito = Date()
            for c in clienti.values where c.dispositivo != nil { invia(["op": "hb"], a: c) }
        }
    }

    /// Chiamato da Pulsar quando l'hook dice che qualcosa è cambiato (così il telefono non aspetta il timer).
    func notifica() { coda.async { [weak self] in self?.pubblica(forza: false) } }

    private func pubblica(forza: Bool) {
        let adesso = Date().timeIntervalSince1970
        let sessioni = Self.vista(da: try? Data(contentsOf: statoURL), adesso: adesso)
        let aspetto = tema()
        guard clienti.values.contains(where: { $0.dispositivo != nil }) else { return }
        let oggiVista = oggi?()
        for c in clienti.values where c.dispositivo != nil {
            // "t" non entra nel confronto: il telefono riceve solo se è cambiato qualcosa (sessioni, aspetto o Oggi)
            var corpo: [String: Any] = ["s": sessioni, "theme": aspetto]
            if let oggiVista { corpo["today"] = oggiVista }
            guard let confronto = try? JSONSerialization.data(withJSONObject: corpo, options: [.sortedKeys]) else { continue }
            if !forza && confronto == c.ultimoInviato { continue }
            c.ultimoInviato = confronto
            var msg: [String: Any] = ["op": "state", "sessions": sessioni, "theme": aspetto, "t": adesso]
            if let oggiVista { msg["today"] = oggiVista }
            invia(msg, a: c)
        }
    }

    /// Dallo state.json dell'hook a ciò che vede il telefono. Pura (testabile). Solo ciò che serve: niente percorsi interi,
    /// niente righe dei diff, richieste e passi accorciati. Un permesso più vecchio di 28 s non c'è più (l'hook ha smesso di aspettare).
    static func vista(da dati: Data?, adesso: Double) -> [[String: Any]] {
        guard let dati, let radice = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let sess = radice["sessions"] as? [String: Any] else { return [] }
        func corto(_ v: Any?, _ n: Int) -> String { String(String(describing: v ?? "").prefix(n)) }
        var out: [[String: Any]] = []
        for (_, v) in sess {
            guard let s = v as? [String: Any], let id = s["id"] as? String else { continue }
            let stato = (s["status"] as? String) ?? "idle"
            let aggiornata = (s["updated"] as? Double) ?? 0
            var pend: [String: Any]?
            if let p = s["pending"] as? [String: Any], let pid = p["id"] as? String, let t = p["t"] as? Double, adesso - t < attesaPermesso + 3 {
                pend = ["id": pid, "tool": corto(p["tool"], 40), "what": corto(p["what"], 400), "t": t,
                        "always": (p["always"] as? Bool) ?? false, "wait": attesaPermesso]
            }
            let passi = (s["steps"] as? [[String: Any]]) ?? []
            let ultimi: [[String: Any]] = passi.suffix(6).map {
                ["kind": corto($0["kind"], 8), "label": corto($0["label"], 80), "state": corto($0["state"], 8), "detail": corto($0["detail"], 24)]
            }
            let ora = passi.last { ($0["state"] as? String) == "now" } ?? passi.last
            let cambi = (s["changes"] as? [String: [String: Any]]) ?? [:]
            let domanda = s["question"] is [String: Any]          // null nel JSON arriva come NSNull: != nil non basta
            let viva = pend != nil || domanda || stato == "waiting" || (stato == "working" && adesso - aggiornata < 900)
            var o: [String: Any] = [
                "id": id, "project": corto(s["project"], 40), "title": corto(s["title"], 60), "prompt": corto(s["prompt"], 200),
                "status": stato, "started": (s["started"] as? Double) ?? 0, "updated": aggiornata,
                "finished": (s["finished"] as? Double) ?? 0, "summary": corto(s["summary"], 420), "viva": viva,
                "steps": ultimi, "files": (s["files"] as? [Any])?.count ?? 0,
                "add": cambi.values.reduce(0) { $0 + (($1["add"] as? Int) ?? 0) },
                "rem": cambi.values.reduce(0) { $0 + (($1["rem"] as? Int) ?? 0) },
                "question": domanda,
            ]
            if let ora { o["now"] = ["kind": corto(ora["kind"], 8), "label": corto(ora["label"], 80)] }
            if let pend { o["pending"] = pend }
            if let c = s["context"] as? [String: Any], let u = c["used"] as? Int, let w = c["window"] as? Int { o["context"] = ["used": u, "window": w] }
            out.append(o)
        }
        // prima chi aspetta un ok, poi le vive, poi le altre; dentro ogni gruppo la più recente
        return out.sorted {
            func peso(_ s: [String: Any]) -> Int { s["pending"] != nil ? 0 : ((s["viva"] as? Bool) == true ? 1 : 2) }
            let (a, b) = (peso($0), peso($1))
            return a != b ? a < b : ($0["updated"] as? Double ?? 0) > ($1["updated"] as? Double ?? 0)
        }
    }

    // MARK: Identità (certificato) e file

    /// L'identità sta in due file della cartella del ponte (0600): il certificato con la chiave (p12) e la sua frase.
    /// Si importa solo in memoria (`kSecImportToMemoryOnly`): niente voci nel portachiavi, quindi nessuna finestra
    /// "Pulsar vuole usare il portachiavi" a metà di una connessione (provato: con la chiave nel portachiavi la firma TLS si bloccava).
    private func identita() -> SecIdentity? {
        let p12 = cartella.appendingPathComponent("identita.p12"), fraseURL = cartella.appendingPathComponent("identita.frase")
        if FileManager.default.fileExists(atPath: p12.path) == false || FileManager.default.fileExists(atPath: fraseURL.path) == false {
            guard creaIdentita(p12: p12, fraseURL: fraseURL) else { return nil }
        }
        guard let dati = try? Data(contentsOf: p12), let frase = try? String(contentsOf: fraseURL, encoding: .utf8) else { return nil }
        var voci: CFArray?
        let opz: [String: Any] = [kSecImportExportPassphrase as String: frase, kSecImportToMemoryOnly as String: true]
        guard SecPKCS12Import(dati as CFData, opz as CFDictionary, &voci) == errSecSuccess,
              let primo = (voci as? [[String: Any]])?.first, let id = primo[kSecImportItemIdentity as String] else { return nil }
        return (id as! SecIdentity)
    }

    /// Prima volta: openssl (quello di sistema) fa chiave e certificato in una cartella temporanea e li impacchetta in un p12;
    /// la cartella sparisce, restano solo i due file.
    private func creaIdentita(p12: URL, fraseURL: URL) -> Bool {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pulsar-pocket-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: tmp) }
        var r = [UInt8](repeating: 0, count: 18)
        guard SecRandomCopyBytes(kSecRandomDefault, r.count, &r) == errSecSuccess else { return false }
        let frase = Data(r).base64EncodedString()
        func openssl(_ args: [String]) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            p.arguments = args
            p.currentDirectoryURL = tmp
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
        // RSA 2048: il p12 con una chiave a curva ellittica fatto da LibreSSL manda in errore SecPKCS12Import (provato)
        guard openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "k.pem", "-out", "c.pem", "-days", "3650",
                       "-subj", "/CN=" + etichetta]),
              openssl(["pkcs12", "-export", "-inkey", "k.pem", "-in", "c.pem", "-name", etichetta, "-out", "i.p12", "-passout", "pass:" + frase]),
              let dati = try? Data(contentsOf: tmp.appendingPathComponent("i.p12")) else { return false }
        guard (try? dati.write(to: p12, options: .atomic)) != nil, (try? frase.write(to: fraseURL, atomically: true, encoding: .utf8)) != nil else { return false }
        chmod(p12.path, 0o600); chmod(fraseURL.path, 0o600)
        return true
    }

    static func impronta(di id: SecIdentity) -> String {
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(id, &cert) == errSecSuccess, let cert else { return "" }
        return SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
    }

    private static func leggiDispositivi(_ cartella: URL) -> [TelefonoAccoppiato] {
        guard let d = try? Data(contentsOf: cartella.appendingPathComponent("telefoni.json")),
              let l = try? JSONDecoder().decode([TelefonoAccoppiato].self, from: d) else { return [] }
        return l
    }

    private func salvaDispositivi() {
        let url = cartella.appendingPathComponent("telefoni.json")
        guard let d = try? JSONEncoder().encode(_dispositivi) else { return }
        try? d.write(to: url, options: .atomic)
        chmod(url.path, 0o600)
    }

    // MARK: Piccoli attrezzi

    static func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// Confronto a tempo costante (i token e i codici non si confrontano con ==).
    static func uguali(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Array(a.utf8), Array(b.utf8))
        guard x.count == y.count else { return false }
        var d: UInt8 = 0
        for i in 0..<x.count { d |= x[i] ^ y[i] }
        return d == 0
    }

    /// Vero se l'indirizzo è di casa: privato, link-local o loopback. Un indirizzo pubblico (porta aperta sul router) no.
    static func indirizzoPrivato(_ e: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = e else { return false }
        switch host {
        case .ipv4(let a): return privato4(Array(a.rawValue))
        case .ipv6(let a):
            let b = Array(a.rawValue)
            if b.count == 16, b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return privato4(Array(b[12...])) }  // ::ffff:a.b.c.d
            if b == [UInt8](repeating: 0, count: 15) + [1] { return true }                  // ::1
            return b.count == 16 && ((b[0] == 0xfe && (b[1] & 0xc0) == 0x80) || (b[0] & 0xfe) == 0xfc)   // fe80::/10, fc00::/7
        default: return false
        }
    }

    private static func privato4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 10 || b[0] == 127 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254)
    }
}
