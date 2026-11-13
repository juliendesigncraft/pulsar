// Promesse: dove si leggono i messaggi. WhatsApp dal suo database sul Mac (sola lettura), Mail dall'app Mail
// via osascript (gli account sono quelli del Mac, in Pulsar nessuna password). I testi restano in memoria.
import Foundation
import SQLite3

enum FonteWhatsApp {
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")
    }
    static var esiste: Bool { FileManager.default.fileExists(atPath: file.path) }

    /// I messaggi dopo `dopoPK` (o degli ultimi `giorni` giorni), solo chat singole (dal 09/11 niente gruppi), niente stati né canali.
    /// Torna anche l'ultimo Z_PK letto, così il giro dopo riparte da lì.
    static func leggi(dopoPK: Int, giorni: Int = 4) -> (messaggi: [PMessaggio], ultimoPK: Int, errore: String?) {
        var db: OpaquePointer?
        let uri = "file:\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let e = db.map { String(cString: sqlite3_errmsg($0)) } ?? "apertura"
            sqlite3_close(db)
            return ([], dopoPK, e)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        let da = Date().addingTimeInterval(-Double(giorni) * 86400).timeIntervalSinceReferenceDate
        let sql = """
        SELECT m.Z_PK, m.ZISFROMME, IFNULL(m.ZTEXT,''), m.ZMESSAGEDATE, m.ZMESSAGETYPE, s.Z_PK, IFNULL(s.ZPARTNERNAME,''),
               s.ZSESSIONTYPE, IFNULL(gm.ZCONTACTNAME,'')
        FROM ZWAMESSAGE m JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
        LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER
        WHERE m.Z_PK > ? AND m.ZMESSAGEDATE > ? AND s.ZSESSIONTYPE = 0 AND IFNULL(s.ZREMOVED,0) = 0
        ORDER BY m.Z_PK LIMIT 4000
        """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return ([], dopoPK, String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, Int64(dopoPK))
        sqlite3_bind_double(st, 2, da)
        var out: [PMessaggio] = []
        var ultimo = dopoPK
        func testo(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
        while sqlite3_step(st) == SQLITE_ROW {
            let pk = Int(sqlite3_column_int64(st, 0))
            ultimo = max(ultimo, pk)
            let tipo = Int(sqlite3_column_int(st, 4))
            let gruppo = sqlite3_column_int(st, 7) == 1
            var chat = testo(6)
            let membro = testo(8)
            if gruppo, !membro.isEmpty { chat = "\(membro) · \(chat)" }
            out.append(PMessaggio(id: "wa-\(pk)", fonte: "WhatsApp", chatID: "wa-\(sqlite3_column_int64(st, 5))", chat: chat,
                                  daMe: sqlite3_column_int(st, 1) == 1, testo: testo(2),
                                  data: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 3)),
                                  allegato: [1, 2, 8].contains(tipo)))
        }
        return (out, ultimo, nil)
    }
}

extension FonteWhatsApp {
    /// I tuoi messaggi nelle chat indicate dopo una data: una promessa si chiude anche con una risposta già vista in un giro precedente.
    static func mieiDopo(chat: [Int64], da: Date) -> [PMessaggio] {
        guard !chat.isEmpty else { return [] }
        var db: OpaquePointer?
        let uri = "file:\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        let elenco = chat.map(String.init).joined(separator: ",")   // numeri presi dal database, non testo libero
        let sql = "SELECT Z_PK, ZCHATSESSION, IFNULL(ZTEXT,''), ZMESSAGEDATE, ZMESSAGETYPE FROM ZWAMESSAGE WHERE ZISFROMME = 1 AND ZCHATSESSION IN (\(elenco)) AND ZMESSAGEDATE > ? LIMIT 2000"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, da.timeIntervalSinceReferenceDate)
        var out: [PMessaggio] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let testo = sqlite3_column_text(st, 2).map { String(cString: $0) } ?? ""
            out.append(PMessaggio(id: "wa-\(sqlite3_column_int64(st, 0))", fonte: "WhatsApp", chatID: "wa-\(sqlite3_column_int64(st, 1))", chat: "",
                                  daMe: true, testo: testo, data: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 3)),
                                  allegato: [1, 2, 8].contains(Int(sqlite3_column_int(st, 4)))))
        }
        return out
    }
}

enum FonteMail {
    /// Mail del Mac: la posta in arrivo e la posta inviata degli ultimi giorni, mittente, oggetto e l'inizio del testo.
    /// La prima volta macOS chiede il permesso di Automazione per Mail. Se Mail è chiusa non la apre.
    private static let script = """
    on run argv
        set giorni to (item 1 of argv) as integer
        if application "Mail" is not running then return "CHIUSA"
        set da to (current date) - giorni * days
        set out to ""
        set sep to (ASCII character 30)
        set fine to (ASCII character 31)
        tell application "Mail"
            repeat with coppia in {{"in", inbox}, {"out", sent mailbox}}
                set verso to item 1 of coppia
                try
                    set ms to (messages of (item 2 of coppia) whose date received > da)
                on error
                    set ms to {}
                end try
                set k to 0
                repeat with m in ms
                    set k to k + 1
                    if k > 60 then exit repeat
                    try
                        set c to content of m
                        if (length of c) > 700 then set c to text 1 thru 700 of c
                        set chi to sender of m
                        if verso is "out" then
                            try
                                set chi to address of item 1 of to recipients of m
                            end try
                        end if
                        set out to out & verso & sep & (id of m) & sep & chi & sep & (subject of m) & sep & my quando(date received of m) & sep & c & fine
                    end try
                end repeat
            end repeat
        end tell
        return out
    end run

    on quando(d)
        return ((year of d) as string) & "-" & ((month of d as integer) as string) & "-" & ((day of d) as string) & "-" & ((time of d) as string)
    end quando
    """

    static func leggi(giorni: Int = 4, _ fatto: @escaping ([PMessaggio], String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process(), o = Pipe(), e = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script, "\(giorni)"]
            p.standardOutput = o; p.standardError = e
            do { try p.run() } catch { fatto([], "osascript"); return }
            let d = o.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let s = String(data: d, encoding: .utf8) ?? ""
            if p.terminationStatus != 0 { fatto([], "Mail: permesso o errore \(p.terminationStatus)"); return }
            if s.hasPrefix("CHIUSA") { fatto([], "Mail chiusa"); return }
            fatto(analizza(s), nil)
        }
    }

    /// Una riga per mail: verso, id, persona, oggetto, secondi dal 2001, testo. Il filo è l'oggetto senza Re:/Fwd:
    /// più l'indirizzo, così la tua risposta finisce nella stessa "chat" della mail a cui rispondi.
    static func analizza(_ s: String) -> [PMessaggio] {
        s.components(separatedBy: "\u{1F}").compactMap { r in
            let c = r.components(separatedBy: "\u{1E}")
            guard c.count >= 6 else { return nil }
            let chi = c[2]
            let indirizzo = chi.range(of: "<[^>]+>", options: .regularExpression).map { String(chi[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "<>")) } ?? chi
            let nome = chi.components(separatedBy: "<").first?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? chi
            let oggetto = c[3].replacingOccurrences(of: "^((re|r|fwd|fw|i)\\s*:\\s*)+", with: "", options: [.regularExpression, .caseInsensitive])
            let q = c[4].split(separator: "-").compactMap { Int($0) }
            var dc = DateComponents()
            if q.count == 4 { dc.year = q[0]; dc.month = q[1]; dc.day = q[2]; dc.second = q[3] }
            let data = Calendar.current.date(from: dc) ?? Date()
            let corpo = (oggetto + ". " + c[5...].joined(separator: " ")).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return PMessaggio(id: "mail-\(c[1])", fonte: "Mail", chatID: "mail-\(indirizzo.lowercased())-\(oggetto.lowercased())",
                              chat: nome.isEmpty ? indirizzo : nome, daMe: c[0] == "out", testo: corpo,
                              data: data)
        }
    }
}
