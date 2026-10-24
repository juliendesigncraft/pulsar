// YouTube nel browser (Chrome e Safari): titolo, miniatura, play e pausa nell'isola.
// Spec: docs/2026-10-11-isola-design.md, sezione 3. Il parsing sta in isola-logica.swift (BrowserParse).
// Titolo e indirizzo delle schede arrivano da AppleScript; play, pausa e posizione richiedono che l'utente attivi
// "Consenti JavaScript da eventi Apple" nel browser (Chrome: Visualizza > Sviluppatore, Safari: menu Sviluppo).
// Senza, resta il titolo con il tasto per tornare alla scheda. Tutto su una coda sua, mai sul filo principale.
import SwiftUI
import AppKit

private enum Browser: CaseIterable {
    case chrome, safari
    var bundle: String { self == .chrome ? "com.google.Chrome" : "com.apple.Safari" }
    var app: String { self == .chrome ? "Google Chrome" : "Safari" }
    /// Cerca la prima scheda con un video di YouTube: titolo, indirizzo, indice finestra, indice scheda.
    var findScript: String {
        let name = self == .chrome ? "title of t" : "name of t"
        return """
        tell application "\(app)"
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    set u to URL of t
                    if u contains "youtube.com/watch" or u contains "youtube.com/shorts/" then return (\(name)) & linefeed & u & linefeed & wi & linefeed & ti
                end repeat
            end repeat
            return ""
        end tell
        """
    }
    func js(_ code: String, window: Int, tab: Int) -> String {
        let c = code.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return self == .chrome
            ? "tell application \"Google Chrome\" to execute tab \(tab) of window \(window) javascript \"\(c)\""
            : "tell application \"Safari\" to do JavaScript \"\(c)\" in tab \(tab) of window \(window)"
    }
    func focus(window: Int, tab: Int) -> String {
        self == .chrome
            ? "tell application \"Google Chrome\"\nset active tab index of window \(window) to \(tab)\nset index of window \(window) to 1\nactivate\nend tell"
            : "tell application \"Safari\"\nset current tab of window \(window) to tab \(tab) of window \(window)\nset index of window \(window) to 1\nactivate\nend tell"
    }
}

final class BrowserMediaSource: ObservableObject, IslandSource {
    let id = "youtube"
    let priority = 25
    let usesHome = true
    var onChange: (() -> Void)?

    @Published private(set) var video: YouTubeVideo?
    @Published private(set) var player: PlayerState?
    @Published private(set) var needsJS = false
    @Published private(set) var thumb: NSImage?
    private(set) var readAt = Date()
    private(set) var browserBundle: String?

    /// Compatta solo mentre il video suona (e lo si sa solo con JavaScript consentito).
    var isActive: Bool { player?.playing == true }

    static var enabled: Bool {
        get { Impostazioni.object(.isolaYouTube) as? Bool ?? true }
        set { Impostazioni.set(newValue, .isolaYouTube) }
    }

    private let queue = DispatchQueue(label: "pulsar.browser", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var at: (browser: Browser, window: Int, tab: Int)?
    private var lastID = ""

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: Leggera.on ? 4.0 : 2.0, leeway: .milliseconds(400))   // 13/10: leggera
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
    }

    func stop() { timer?.cancel(); timer = nil }

    // MARK: lettura (coda pulsar.browser)

    private func poll() {
        guard Self.enabled else { publish(nil, nil, false, nil); return }
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        for b in Browser.allCases where running.contains(b.bundle) {
            var err: NSDictionary?
            let out = NSAppleScript(source: b.findScript)?.executeAndReturnError(&err).stringValue ?? ""
            if err != nil { continue }                                   // Automazione non concessa per questo browser
            let f = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, let v = BrowserParse.video(title: f[0], url: f[1]), let wi = Int(f[2]), let ti = Int(f[3]) else { continue }
            at = (b, wi, ti)
            var jsErr: NSDictionary?
            let code = "(function(){var v=document.querySelector('video');return v?(v.paused+'|'+v.currentTime+'|'+v.duration):''})()"
            let raw = NSAppleScript(source: b.js(code, window: wi, tab: ti))?.executeAndReturnError(&jsErr).stringValue ?? ""
            publish(v, BrowserParse.player(raw), jsErr != nil, b.bundle)
            return
        }
        at = nil
        publish(nil, nil, false, nil)
    }

    private func publish(_ v: YouTubeVideo?, _ p: PlayerState?, _ js: Bool, _ bundle: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let before = (self.video, self.player?.playing, self.needsJS)
            if self.video != v { self.video = v }
            if self.player != p { self.player = p }
            if self.needsJS != js { self.needsJS = js }
            self.browserBundle = bundle
            self.readAt = Date()
            let id = v?.id ?? ""
            if id != self.lastID { self.lastID = id; self.loadThumb(id) }
            if before.0 != v || before.1 != p?.playing || before.2 != js { self.onChange?() }
        }
    }

    private func loadThumb(_ id: String) {
        guard !id.isEmpty, let url = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") else { thumb = nil; return }
        if let hit = Self.cache[id] { thumb = hit; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { Self.cache[id] = img; if self?.lastID == id { self?.thumb = img } }
        }.resume()
    }
    private static var cache: [String: NSImage] = [:]

    // MARK: comandi

    func playPause() { run("var v=document.querySelector('video');v&&(v.paused?v.play():v.pause())") }
    func seek(_ s: Double) { run("var v=document.querySelector('video');if(v){v.currentTime=\(max(0, s))}") }

    private func run(_ code: String) {
        guard let a = at else { return }
        queue.async { var e: NSDictionary?; NSAppleScript(source: a.browser.js(code, window: a.window, tab: a.tab))?.executeAndReturnError(&e) }
    }

    /// Porta il browser in primo piano sulla scheda del video (l'unica azione senza JavaScript).
    func focusTab() {
        guard let a = at else { return }
        queue.async { var e: NSDictionary?; NSAppleScript(source: a.browser.focus(window: a.window, tab: a.tab))?.executeAndReturnError(&e) }
    }

    func position(at date: Date) -> Double {
        guard let p = player else { return 0 }
        let v = p.position + (p.playing ? date.timeIntervalSince(readAt) : 0)
        return p.duration > 0 ? min(max(v, 0), p.duration) : max(v, 0)
    }

    // MARK: viste compatte

    func compactLeading() -> AnyView { AnyView(YouTubeCompactArt(src: self)) }
    func compactTrailing() -> AnyView { AnyView(MediaEqualizer(playing: true)) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

private struct YouTubeCompactArt: View {
    @ObservedObject var src: BrowserMediaSource
    var body: some View {
        Group {
            if let t = src.thumb { Image(nsImage: t).resizable().scaledToFill() }
            else { Image(systemName: "play.rectangle.fill").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.8)) }
        }
        .frame(width: 26, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Tessera YouTube

struct YouTubeWidget: IslandWidget {
    let browser: BrowserMediaSource
    let thumbnail = WindowThumbnail()      // il piccolo video dal vivo (solo con Miniatura finestre accesa)
    let id = "youtube"
    var title: String { "YouTube" }
    let symbol = "play.rectangle"
    func body(cells: Int) -> AnyView { AnyView(YouTubeTile(src: browser, thumbnail: thumbnail, cells: cells)) }
}

private struct YouTubeTile: View {
    @ObservedObject var src: BrowserMediaSource
    @ObservedObject var thumbnail: WindowThumbnail
    let cells: Int
    @AppStorage(Chiave.isolaThumb.rawValue) private var thumbOn = false

    private var live: Bool { thumbOn && cells >= 3 }

    var body: some View {
        Group {
            if let v = src.video {
                if cells == 1 {
                    VStack(spacing: 6) {
                        picture(64, 36)
                        control
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 10) {
                        picture(cells >= 3 ? 112 : 64, cells >= 3 ? 63 : 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(v.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                            Spacer(minLength: 0)
                            if src.needsJS {
                                Text(cells >= 3 ? T("Attiva \"JavaScript da eventi Apple\" nel browser", "Turn on \"Allow JavaScript from Apple Events\"") : T("Controlli spenti", "Controls off"))
                                    .font(.system(size: 9)).foregroundStyle(Night.amber).lineLimit(2)
                            } else if cells >= 3, let p = src.player, p.duration > 0 {
                                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                                    Capsule().fill(Color.primary.opacity(0.14)).frame(height: 3)
                                        .overlay(alignment: .leading) {
                                            GeometryReader { g in Capsule().fill(Theme.accent).frame(width: g.size.width * src.position(at: ctx.date) / p.duration) }
                                        }
                                }
                                .frame(height: 3)
                            }
                            control
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "play.rectangle").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                    if cells > 1 { Text(T("Nessun video aperto", "No video open")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { updateLive() }
        .onDisappear { thumbnail.stop() }
        .onChange(of: live) { _ in updateLive() }
        .onChange(of: src.video) { _ in updateLive() }
    }

    @ViewBuilder private func picture(_ w: CGFloat, _ h: CGFloat) -> some View {
        Group {
            if live, let img = thumbnail.image { Image(decorative: img, scale: 1).resizable().scaledToFit() }
            else if let t = src.thumb { Image(nsImage: t).resizable().scaledToFill() }
            else { Color.primary.opacity(0.1) }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder private var control: some View {
        HStack(spacing: 12) {
            if !src.needsJS {
                Button { src.playPause() } label: {
                    Image(systemName: src.player?.playing == true ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { src.focusTab() } label: {
                Image(systemName: "arrow.up.right.square").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// La miniatura dal vivo: la finestra del browser con il video, solo se serve e se è acceso.
    private func updateLive() {
        guard live, let v = src.video, let bundle = src.browserBundle else { thumbnail.stop(); return }
        thumbnail.start { wins in
            wins.first { $0.owningApplication?.bundleIdentifier == bundle && ($0.title ?? "").contains(String(v.title.prefix(20))) }
        }
    }
}
