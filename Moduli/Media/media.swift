// Media: Spotify nell'isola (brano, copertina, barra, tasti e testi sincronizzati).
// Spec: docs/2026-10-11-isola-design.md, sezione 3. Lettura su una coda sua, mai sul filo principale.
// Il parsing e i testi LRC stanno in isola-logica.swift (provati da prove/main.swift).
import SwiftUI
import AppKit

enum MediaCommand {
    case playPause, next, previous
    case seek(Double)
}

final class MediaSource: ObservableObject, IslandSource {
    let id = "media"
    let priority = 30
    let usesHome = true
    var onChange: (() -> Void)?

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// L'ultimo brano ascoltato (12/10 sera): la tessera lo mostra con copertina e disco anche quando non suona niente.
    @Published private(set) var last: Track? = MediaSource.loadLast()
    @Published private(set) var lyrics: LyricsState = .none {
        didSet { if lyrics != oldValue { onChange?() } }   // la riga dei testi cambia l'altezza dell'isola
    }
    @Published private(set) var needsPermission = false
    /// Quando è stata letta la posizione: serve a far scorrere la barra fra una lettura e l'altra.
    private(set) var readAt = Date()

    /// Compatta solo mentre suona; in pausa resta visibile nell'isola aperta.
    var isActive: Bool { track?.playing == true }

    static var lyricsEnabled: Bool {
        get { Impostazioni.object(.isolaLyrics) as? Bool ?? true }
        set { Impostazioni.set(newValue, .isolaLyrics) }
    }

    private let queue = DispatchQueue(label: "pulsar.media", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pollScript: NSAppleScript?
    private var lastKey = ""
    private var artworkURL: URL?

    // MARK: lettura

    func start() {
        guard timer == nil else { return }
        if track == nil, let u = last?.artworkURL { loadArtwork(u) }      // da fermo: la copertina dell'ultimo brano
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Leggera.on ? 2.0 : 1.0, leeway: .milliseconds(200))   // 13/10: leggera
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Reel (isola-demo.swift): un brano inventato con copertina e testo finti; Spotify non viene letto.
    private var demo = false

    private static let spotifyID = "com.spotify.client"
    private static let musicID = "com.apple.Music"
    private static func pollSource(_ app: String, durationMs: String) -> String {
        """
        tell application "\(app)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & \(durationMs) & linefeed & player position & linefeed & (player state as string) & linefeed & \(app == "Spotify" ? "(artwork url of t)" : "\"missing value\"")
        end tell
        """
    }
    private var musicScript: NSAppleScript?

    /// Sulla coda `pulsar.media`. Legge Spotify e Apple Music solo se sono aperti (AppleScript li aprirebbe) e
    /// preferisce quello che suona; a pari, Spotify.
    private func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var found: [Track] = []
        var denied = false
        if running.contains(Self.spotifyID) {
            if pollScript == nil { pollScript = NSAppleScript(source: Self.pollSource("Spotify", durationMs: "(duration of t)")) }
            var err: NSDictionary?
            let out = pollScript?.executeAndReturnError(&err)
            if let err { denied = (err[NSAppleScript.errorNumber] as? Int) == -1743 }      // -1743: Automazione non concessa
            else if let t = MediaParse.track(out?.stringValue ?? "", app: "Spotify") { found.append(t) }
        }
        if running.contains(Self.musicID) {
            if musicScript == nil { musicScript = NSAppleScript(source: Self.pollSource("Music", durationMs: "((duration of t) * 1000)")) }
            var err: NSDictionary?
            let out = musicScript?.executeAndReturnError(&err)
            if err == nil, let t = MediaParse.track(out?.stringValue ?? "", app: "Music") { found.append(t) }
        }
        let pick = found.first { $0.playing } ?? found.first
        publish(track: pick, denied: denied && pick == nil)
    }

    private func publish(track new: Track?, denied: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.demo else { return }      // una lettura partita prima del reel non cancella il brano finto
            let before = (self.track?.playing, self.track?.title, self.needsPermission)
            if self.needsPermission != denied { self.needsPermission = denied }
            if self.track != new { self.track = new }
            self.readAt = Date()
            let key = new.map { "\($0.title)|\($0.artist)|\(Int($0.duration))" } ?? ""
            if let n = new { self.saveLast(n) }
            if key != self.lastKey {
                self.lastKey = key
                self.loadArtwork(new?.artworkURL ?? self.last?.artworkURL)     // fermo: resta la copertina dell'ultimo
                self.loadLyrics(new)
            }
            if before.0 != new?.playing || before.1 != new?.title || before.2 != denied { self.onChange?() }
        }
    }

    // MARK: comandi

    func command(_ c: MediaCommand) {
        let app = track?.app == "Music" ? "Music" : "Spotify"      // i comandi vanno all'app che sta suonando
        let src: String
        switch c {
        case .playPause: src = "tell application \"\(app)\" to playpause"
        case .next:      src = "tell application \"\(app)\" to next track"
        case .previous:  src = "tell application \"\(app)\" to previous track"
        case .seek(let s): src = "tell application \"\(app)\" to set player position to \(max(0, s))"
        }
        queue.async {
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
        }
    }

    // MARK: ultimo brano (solo titolo, artista, album e indirizzo della copertina, in UserDefaults)

    private static func loadLast() -> Track? {
        guard let d = Impostazioni.dictionary(.isolaUltimoBrano) as? [String: String], let t = d["title"] else { return nil }
        return Track(app: d["app"] ?? "Spotify", title: t, artist: d["artist"] ?? "", album: d["album"] ?? "", duration: 0, position: 0,
                     playing: false, artworkURL: d["art"].flatMap(URL.init(string:)))
    }
    private func saveLast(_ t: Track) {
        guard !demo, last?.title != t.title || last?.artist != t.artist else { return }
        var p = t; p.playing = false; p.position = 0
        last = p
        Impostazioni.set(["app": t.app, "title": t.title, "artist": t.artist, "album": t.album, "art": t.artworkURL?.absoluteString ?? ""], .isolaUltimoBrano)
    }
    /// Fa ripartire l'ultimo brano: apre l'app se serve (AppleScript la avvia) e suona.
    func resumeLast() {
        let app = last?.app == "Music" ? "Music" : "Spotify"
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"\(app)\" to play")?.executeAndReturnError(&err)
        }
    }

    // MARK: copertina

    private func loadArtwork(_ url: URL?) {
        artworkURL = url
        guard let url else { artwork = nil; return }
        if let hit = Self.artCache[url] { artwork = hit; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                Self.artCache[url] = img
                if self?.artworkURL == url { self?.artwork = img }
            }
        }.resume()
    }
    private static var artCache: [URL: NSImage] = [:]

    // MARK: testi (LRCLIB)

    private static var cacheDir: URL = {
        let d = Cartelle.dati.appendingPathComponent("testi", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Chiave stabile per il file in cache (djb2: `hashValue` cambia a ogni avvio).
    private static func fileKey(_ t: Track) -> String {
        var h: UInt64 = 5381
        for u in "\(t.title)|\(t.artist)|\(Int(t.duration))".utf8 { h = (h &* 33) &+ UInt64(u) }
        return String(h, radix: 16)
    }

    private func loadLyrics(_ t: Track?) {
        guard let t, Self.lyricsEnabled else { lyrics = .none; return }
        lyrics = .loading
        let file = Self.cacheDir.appendingPathComponent(Self.fileKey(t) + ".json")
        if let d = try? Data(contentsOf: file) { lyrics = Self.decodeLyrics(d); return }
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: t.title), URLQueryItem(name: "artist_name", value: t.artist),
                        URLQueryItem(name: "album_name", value: t.album), URLQueryItem(name: "duration", value: String(Int(t.duration.rounded())))]
        guard let url = c.url else { lyrics = .none; return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Pulsar (\(App.id))", forHTTPHeaderField: "User-Agent")
        let key = lastKey
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let state: LyricsState = ok && data != nil ? Self.decodeLyrics(data!) : .none
            if ok, let data { try? data.write(to: file) }
            DispatchQueue.main.async { if self?.lastKey == key { self?.lyrics = state } }
        }.resume()
    }

    private static func decodeLyrics(_ d: Data) -> LyricsState {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return .none }
        if let s = o["syncedLyrics"] as? String {
            let lines = LRC.parse(s)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let p = o["plainLyrics"] as? String, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(p) }
        return .none
    }

    // MARK: viste

    func compactLeading() -> AnyView { AnyView(MediaCompactArt(src: self)) }
    func compactTrailing() -> AnyView { AnyView(MediaEqualizer(playing: track?.playing == true)) }
    func expandedView() -> AnyView { AnyView(MediaExpanded(src: self)) }

    /// Posizione di adesso: l'ultima letta più il tempo passato, se suona.
    func position(at date: Date) -> Double {
        guard let t = track else { return 0 }
        let p = t.position + (t.playing ? date.timeIntervalSince(readAt) : 0)
        return min(max(p, 0), t.duration)
    }
}

// MARK: - Viste

private struct MediaCompactArt: View {
    @ObservedObject var src: MediaSource
    var body: some View {
        Group {
            if let a = src.artwork {
                Image(nsImage: a).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.8))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Tre barrette che ballano mentre suona. Ferma, nessun timer.
struct MediaEqualizer: View {
    let playing: Bool
    var body: some View {
        if playing {
            TimelineView(.animation(minimumInterval: 0.12)) { ctx in   // 13/10: animazione tenuta anche in Pulsar leggera (l'autore)
                bars(ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(nil)
        }
    }
    private func bars(_ t: Double?) -> some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                let h: CGFloat = t.map { 4 + 9 * abs(sin($0 * (3.1 + Double(i) * 1.3) + Double(i))) } ?? 4
                RoundedRectangle(cornerRadius: 1.2).fill(Theme.accent).frame(width: 2.5, height: h)
            }
        }
        .frame(height: 14)
    }
}

private struct MediaExpanded: View {
    @ObservedObject var src: MediaSource
    @ObservedObject var look = GhieraLook.shared    // cambia aspetto: la vista si ridisegna

    var body: some View {
        if src.needsPermission {
            permission
        } else if let t = src.track {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 14) {
                    art.frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        Text(t.artist).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1)
                        Spacer(minLength: 4)
                        ProgressBar(src: src)
                        controls(t).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 84)
                LyricsLine(src: src)
            }
        } else {
            idle
        }
    }

    private var art: some View {
        Group {
            if let a = src.artwork { Image(nsImage: a).resizable().scaledToFill() }
            else { Color.primary.opacity(0.08).overlay(Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(Color.primary.opacity(0.4))) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func controls(_ t: Track) -> some View {
        HStack(spacing: 18) {
            button("backward.fill", 12) { src.command(.previous) }
            button(t.playing ? "pause.fill" : "play.fill", 15) { src.command(.playPause) }
            button("forward.fill", 12) { src.command(.next) }
        }
    }

    private func button(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium)).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var idle: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(Color.primary.opacity(0.45))
            Text(T("Nessuna musica in riproduzione", "Nothing playing")).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.6))
            Button { Self.open("Spotify") } label: {
                Label("Spotify", systemImage: "play.fill").font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).frame(height: 28)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var permission: some View {
        VStack(spacing: 10) {
            Text(T("Pulsar non può controllare Spotify", "Pulsar can't control Spotify")).font(.system(size: 13, weight: .medium)).foregroundStyle(Night.amber)
            Text(T("Consenti l'Automazione per Pulsar → Spotify.", "Allow Automation for Pulsar → Spotify.")).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            } label: {
                Text(T("Apri Impostazioni", "Open Settings")).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).frame(height: 28)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private static func open(_ name: String) {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name == "Spotify" ? "com.spotify.client" : "com.apple.Music") {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Barra della posizione: si trascina per saltare. Si ridisegna ogni quarto di secondo, solo se l'isola è aperta.
struct ProgressBar: View {
    @ObservedObject var src: MediaSource
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let dur = max(src.track?.duration ?? 1, 1)
            let pos = src.position(at: ctx.date)
            VStack(spacing: 3) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.14))
                        Capsule().fill(Theme.accent).frame(width: g.size.width * pos / dur)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        src.command(.seek(Double(min(max(v.location.x / g.size.width, 0), 1)) * dur))
                    })
                }
                .frame(height: 12)
                HStack {
                    Text(Self.clock(pos)); Spacer(); Text(Self.clock(dur))
                }
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.5))
            }
        }
    }
    static func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// La riga che si canta adesso e la prossima. Senza testi la riga sparisce.
struct LyricsLine: View {
    @ObservedObject var src: MediaSource
    var body: some View {
        switch src.lyrics {
        case .synced(let lines):
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let i = LRC.index(at: src.position(at: ctx.date), in: lines)
                VStack(spacing: 2) {
                    Text(i.map { lines[$0].text } ?? "…").font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text((i ?? -1) + 1 < lines.count ? lines[(i ?? -1) + 1].text : " ")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4)).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: i)
            }
        case .plain(let p):
            Text(p.split(separator: "\n").first.map(String.init) ?? "").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
                .lineLimit(1).frame(maxWidth: .infinity)
        case .loading, .none:
            Color.clear.frame(height: 1)
        }
    }
}
