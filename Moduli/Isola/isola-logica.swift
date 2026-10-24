// Isola: logica pura (niente AppKit, niente SwiftUI), così si prova con uno script swiftc.
// Spec: docs/2026-10-11-isola-design.md. Prove: prove/main.swift.
import Foundation

enum IslandState: String {
    case rest, compact, expanded, alert
    case peek        // una comparsa piccola e breve (notifica, Non disturbare, batteria...)
}

struct SourceOffer: Equatable {
    let id: String
    let priority: Int
    let active: Bool
}

enum IslandLogic {
    /// La fonte da mostrare: la fissata se è ancora attiva, altrimenti quella attiva con la priorità più alta
    /// (a parità, la prima dell'elenco).
    static func pick(_ offers: [SourceOffer], pinned: String?) -> String? {
        let active = offers.filter { $0.active }
        if let pinned, active.contains(where: { $0.id == pinned }) { return pinned }
        var best: SourceOffer?
        for o in active where best == nil || o.priority > best!.priority { best = o }
        return best?.id
    }

    /// Notch compatto (fase 4): Claude va ai due lati solo se è attivo e la fonte scelta è lui o non conta più di lui
    /// (a parità resta Claude). Così la riunione (80) si vede anche mentre Claude lavora (60) o ha finito (70),
    /// e Claude che aspetta un ok (90) resta come prima.
    static func claudeAiLati(agente: SourceOffer, scelta: SourceOffer?) -> Bool {
        guard agente.active else { return false }
        guard let s = scelta else { return true }
        return s.id == agente.id || agente.priority >= s.priority
    }

    /// Lo stato dell'isola: l'avviso vince su tutto, poi aperta (mouse sopra o clic) se c'è contenuto,
    /// poi la comparsa breve, poi compatta se c'è contenuto, altrimenti a riposo.
    static func state(hover: Bool, pinnedOpen: Bool, alert: Bool, hasContent: Bool, peek: Bool = false) -> IslandState {
        if alert { return .alert }
        if hover || pinnedOpen, hasContent { return .expanded }
        if peek { return .peek }
        guard hasContent else { return .rest }
        return .compact
    }
}

// MARK: - Testi sincronizzati (LRC)

struct LRCLine: Equatable {
    let time: Double
    let text: String
}

enum LRC {
    /// Righe `[mm:ss.xx] testo`, ordinate per tempo. Le righe senza tempo valido o senza testo si ignorano.
    static func parse(_ s: String) -> [LRCLine] {
        var out: [LRCLine] = []
        for raw in s.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let stamp = line[line.index(after: line.startIndex)..<close]
            let parts = stamp.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { continue }
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            out.append(LRCLine(time: m * 60 + sec, text: text))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// La riga che si sta cantando a `t` secondi: l'ultima con `time <= t`; `nil` prima della prima.
    static func index(at t: Double, in lines: [LRCLine]) -> Int? {
        var found: Int?
        for (i, l) in lines.enumerated() where l.time <= t { found = i }
        return found
    }
}

// MARK: - Media

struct Track: Equatable {
    var app: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    var artworkURL: URL?
}

enum LyricsState: Equatable {
    case loading
    case synced([LRCLine])
    case plain(String)
    case none
}

enum MediaParse {
    /// Output dello script AppleScript di Spotify: sette righe (nome, artista, album, durata in ms, posizione in s,
    /// stato, url copertina). Vuoto, `missing value` o incompleto: nessun brano.
    static func spotify(_ raw: String) -> Track? { track(raw, app: "Spotify") }

    /// Lo stesso formato per Spotify e Apple Music (che restituisce la durata in secondi: lo script la moltiplica per 1000).
    static func track(_ raw: String, app: String) -> Track? {
        let f = raw.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard f.count >= 7, !f[0].isEmpty, f[0] != "missing value",
              let ms = Double(f[3].replacingOccurrences(of: ",", with: ".")),
              let pos = Double(f[4].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let art = f[6] == "missing value" || f[6].isEmpty ? nil : URL(string: f[6])
        return Track(app: app, title: f[0], artist: f[1], album: f[2], duration: ms / 1000, position: pos,
                     playing: f[5] == "playing", artworkURL: art)
    }
}

// MARK: - Tessere dei widget

struct Tile: Codable, Equatable {
    var id: String
    var cells: Int          // da 1 a 4
}

struct TileLayout: Codable, Equatable {
    static let minCells = 1
    static let maxCells = 4
    var tiles: [Tile]

    static let standard = TileLayout(tiles: [Tile(id: "music", cells: 2), Tile(id: "weather", cells: 2),
                                             Tile(id: "calendar", cells: 2), Tile(id: "timer", cells: 1)])

    static func clamp(_ n: Int) -> Int { min(max(n, minCells), maxCells) }

    mutating func resize(_ id: String, to cells: Int) {
        guard let i = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[i].cells = Self.clamp(cells)
    }

    mutating func move(_ id: String, to index: Int) {
        guard let i = tiles.firstIndex(where: { $0.id == id }) else { return }
        let t = tiles.remove(at: i)
        tiles.insert(t, at: min(max(index, 0), tiles.count))
    }

    mutating func remove(_ id: String) { tiles.removeAll { $0.id == id } }

    mutating func add(_ id: String, cells: Int = 2) {
        guard !tiles.contains(where: { $0.id == id }) else { return }
        tiles.append(Tile(id: id, cells: Self.clamp(cells)))
    }

    func encode() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Dati assenti o corrotti: layout standard. Celle limitate a 1...4, id doppi tolti.
    static func decode(_ d: Data?) -> TileLayout {
        guard let d, let l = try? JSONDecoder().decode(TileLayout.self, from: d) else { return .standard }
        var seen = Set<String>()
        let clean = l.tiles.compactMap { t -> Tile? in
            guard seen.insert(t.id).inserted else { return nil }
            return Tile(id: t.id, cells: clamp(t.cells))
        }
        return TileLayout(tiles: clean)
    }

    /// Larghezza totale della riga: ogni tessera `cells * cell + (cells - 1) * gap`, più lo spazio fra tessere.
    func width(cell: CGFloat, gap: CGFloat) -> CGFloat {
        guard !tiles.isEmpty else { return 0 }
        let tilesW = tiles.reduce(CGFloat(0)) { $0 + CGFloat($1.cells) * cell + CGFloat($1.cells - 1) * gap }
        return tilesW + CGFloat(tiles.count - 1) * gap
    }
}

// MARK: - Meteo (Open-Meteo)

struct WeatherNow: Equatable {
    var temp: Double
    var code: Int
    var isDay: Bool
    var hi: Double
    var lo: Double
}

enum WeatherParse {
    /// Risposta di `api.open-meteo.com/v1/forecast` con `current` e `daily`. Incompleta o corrotta: nil.
    static func forecast(_ d: Data) -> WeatherNow? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let cur = o["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double, let code = cur["weather_code"] as? Int,
              let day = o["daily"] as? [String: Any],
              let hi = (day["temperature_2m_max"] as? [Double])?.first, let lo = (day["temperature_2m_min"] as? [Double])?.first else { return nil }
        let isDay = (cur["is_day"] as? Int ?? 1) == 1
        return WeatherNow(temp: t, code: code, isDay: isDay, hi: hi, lo: lo)
    }

    /// Risposta di `geocoding-api.open-meteo.com/v1/search`: la prima città trovata.
    static func place(_ d: Data) -> (name: String, lat: Double, lon: Double)? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (o["results"] as? [[String: Any]])?.first,
              let name = r["name"] as? String, let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return nil }
        return (name, lat, lon)
    }

    /// SF Symbol del codice WMO di Open-Meteo.
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - YouTube nel browser

struct YouTubeVideo: Equatable {
    var title: String
    var id: String
}

struct PlayerState: Equatable {
    var playing: Bool
    var position: Double
    var duration: Double      // 0 per le dirette (durata infinita o NaN)
}

enum BrowserParse {
    /// Una scheda di Chrome o Safari: è un video solo se l'indirizzo è youtube.com/watch?v=ID o /shorts/ID.
    /// Il titolo perde il suffisso " - YouTube".
    static func video(title: String, url: String) -> YouTubeVideo? {
        guard let u = URLComponents(string: url), let host = u.host, host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        var id: String?
        if u.path == "/watch" { id = u.queryItems?.first { $0.name == "v" }?.value }
        else if u.path.hasPrefix("/shorts/") { id = String(u.path.dropFirst("/shorts/".count)) }
        guard let id, !id.isEmpty else { return nil }
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix(" - YouTube") { t = String(t.dropLast(" - YouTube".count)) }
        return YouTubeVideo(title: t, id: id)
    }

    /// Il risultato del piccolo JavaScript: `paused|currentTime|duration`. Vuoto o corrotto: nil.
    static func player(_ raw: String) -> PlayerState? {
        let f = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 3, f[0] == "true" || f[0] == "false", let pos = Double(f[1]) else { return nil }
        guard let dur = Double(f[2]) ?? (f[2] == "NaN" || f[2] == "Infinity" ? 0 : nil) else { return nil }
        return PlayerState(playing: f[0] == "false", position: pos, duration: dur.isFinite ? dur : 0)
    }
}

// MARK: - Miniatura: quale finestra

enum WindowPick {
    /// La finestra dopo `current` nell'elenco; se `current` non c'è più (o è nil) la prima; elenco vuoto: nil.
    static func next(after current: UInt32?, in ids: [UInt32]) -> UInt32? {
        guard !ids.isEmpty else { return nil }
        guard let current, let i = ids.firstIndex(of: current) else { return ids[0] }
        return ids[(i + 1) % ids.count]
    }
}

// MARK: - Comparse (peek): coda

struct PeekItem: Equatable {
    var key: String          // stessa chiave = stessa comparsa, si aggiorna invece di ripetersi
    var kind: String         // "notification", "focus", "battery", "health", "apps", "info"
    var symbol: String
    var title: String
    var detail: String
    var priority: Int
    var duration: Double
}

/// Una comparsa alla volta, ognuna per la sua durata. Una più importante non scavalca quella in corso: aspetta.
struct PeekQueue {
    private(set) var queue: [PeekItem] = []
    private(set) var current: PeekItem?
    private var shownAt: Date?
    static let maxQueued = 6

    mutating func push(_ item: PeekItem, now: Date) {
        if current?.key == item.key { current = item; shownAt = now; return }
        queue.removeAll { $0.key == item.key }
        queue.append(item)
        if queue.count > Self.maxQueued {
            if let low = queue.indices.min(by: { queue[$0].priority < queue[$1].priority }) { queue.remove(at: low) }
        }
    }

    /// Fa scadere quella in corso e, se serve, mette in scena la prossima. Restituisce quella da mostrare adesso.
    @discardableResult
    mutating func advance(now: Date) -> PeekItem? {
        if let c = current, let s = shownAt, now.timeIntervalSince(s) >= c.duration { current = nil }
        if current == nil, !queue.isEmpty {
            var best = 0
            for i in queue.indices where queue[i].priority > queue[best].priority { best = i }
            current = queue.remove(at: best)
            shownAt = now
        }
        return current
    }
}

// MARK: - Batteria

struct BatterySnapshot: Equatable {
    var percent: Int
    var pluggedIn: Bool
}

enum BatteryRules {
    /// Gli eventi fra due letture: "plugged", "unplugged", "low20", "low10", "full". La prima lettura non ne fa.
    static func events(from p: BatterySnapshot?, to n: BatterySnapshot) -> [String] {
        guard let p else { return [] }
        var e: [String] = []
        if !p.pluggedIn && n.pluggedIn { e.append("plugged") }
        if p.pluggedIn && !n.pluggedIn { e.append("unplugged") }
        if !n.pluggedIn && p.percent > 20 && n.percent <= 20 { e.append("low20") }
        if !n.pluggedIn && p.percent > 10 && n.percent <= 10 { e.append("low10") }
        if n.pluggedIn && p.percent < 100 && n.percent == 100 { e.append("full") }
        return e
    }

    /// Salute della batteria: capacità massima attuale su capacità di progetto, al massimo 100.
    static func healthPercent(rawMax: Double, design: Double) -> Int? {
        guard rawMax > 0, design > 0 else { return nil }
        return min(100, Int((rawMax / design * 100).rounded()))
    }
}

// MARK: - Focus dal file di sistema

enum FocusParse {
    /// `~/Library/DoNotDisturb/DB/Assertions.json`: un Focus è acceso se c'è almeno un record. Corrotto: nil.
    static func active(_ d: Data) -> Bool? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let data = o["data"] as? [[String: Any]] else { return nil }
        return data.contains { !(($0["storeAssertionRecords"] as? [Any]) ?? []).isEmpty }
    }
}

// MARK: - WhatsApp: una riga della lista chat (letta con l'Accessibilità)

struct ChatPreview: Equatable {
    var name: String
    var text: String
    var time: String
    var unread: Int
}

enum WhatsAppParse {
    private static let invisible: Set<Character> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202C}"]
    private static func clean(_ s: String) -> String { String(s.filter { !invisible.contains($0) }) }
    private static func clock(_ s: String) -> String? {
        guard let r = s.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    /// Descrizione: "Nome" o "Nome, N messaggi non letti". Valore: "messaggio, testo, 23:56, Ricevuto" (il testo può
    /// contenere virgole; prima dell'ora). L'etichetta "messaggio" si toglie, "Il tuo messaggio" diventa "Tu:",
    /// gli altri tipi (Foto, Audio) restano.
    static func row(description: String, value: String, youPrefix: String = "Tu: ") -> ChatPreview? {
        let d = clean(description).components(separatedBy: ", ")
        guard let name = d.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let unread = d.dropFirst().compactMap { part in part.split(separator: " ").first.flatMap { Int($0) } }.first ?? 0
        var parts = clean(value).components(separatedBy: ", ")
        if parts == [""] { parts = [] }
        let timeIdx = parts.firstIndex { clock($0) != nil }
        var textParts = Array(parts[..<(timeIdx ?? parts.count)])
        var mine = false
        if textParts.count > 1 {
            let label = textParts[0].lowercased()
            if ["messaggio", "message"].contains(label) { textParts.removeFirst() }
            else if ["il tuo messaggio", "your message"].contains(label) { textParts.removeFirst(); mine = true }
        }
        let body = textParts.joined(separator: ", ")
        let time = timeIdx.flatMap { clock(parts[$0]) } ?? ""
        return ChatPreview(name: name, text: mine ? youPrefix + body : body, time: time, unread: unread)
    }
}

// MARK: - Griglia ⌘4: pagine e ricerca

enum GridPaging {
    static func pages(count: Int, perPage: Int) -> Int { max(1, (count + perPage - 1) / perPage) }
    static func clamp(page: Int, count: Int, perPage: Int) -> Int { min(max(page, 0), pages(count: count, perPage: perPage) - 1) }
    static func range(page: Int, count: Int, perPage: Int) -> Range<Int> {
        let a = min(max(page, 0) * perPage, count)
        return a..<min(a + perPage, count)
    }
}

enum AppSearch {
    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// Indici delle app che corrispondono, nell'ordine: prima chi comincia con la ricerca, poi chi ha una parola
    /// che comincia così, poi chi la contiene. A parità resta l'ordine di partenza. Ricerca vuota: tutte.
    static func filter(_ names: [String], _ query: String) -> [Int] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return Array(names.indices) }
        var a: [Int] = [], b: [Int] = [], c: [Int] = []
        for (i, n) in names.enumerated() {
            let f = fold(n)
            if f.hasPrefix(q) { a.append(i) }
            else if f.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { b.append(i) }
            else if f.contains(q) { c.append(i) }
        }
        return a + b + c
    }
}

// MARK: - Griglia ⌘4: categorie automatiche

enum AppCategory {
    static let order = ["productivity", "creative", "developer", "media", "social", "utilities", "games", "other"]

    /// Il gruppo di un'app dalla sua `LSApplicationCategoryType`. Senza categoria o sconosciuta: "other".
    static func group(_ type: String?) -> String {
        guard let t = type?.replacingOccurrences(of: "public.app-category.", with: "") else { return "other" }
        if t.hasSuffix("games") { return "games" }
        switch t {
        case "productivity", "business", "finance": return "productivity"
        case "graphics-design", "photography", "video": return "creative"
        case "developer-tools": return "developer"
        case "music", "entertainment": return "media"
        case "social-networking": return "social"
        case "utilities": return "utilities"
        default: return "other"
        }
    }
}
