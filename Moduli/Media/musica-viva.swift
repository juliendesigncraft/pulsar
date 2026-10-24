// Musica viva (17/10/2026). l'autore: "una bella animazione per Spotify quando riproduce, sia di colore che movimento,
// e sul launchpad (come in LaunchMe) una schermata a schermo intero con l'immagine dell'album; e la possibilità di
// aggiungere widget, immagini e note". Qui: i colori presi dalla copertina, il bagliore che si muove, l'equalizzatore
// a pixel (stessa grammatica del razzo), la pagina "In riproduzione" della griglia e le note.
import SwiftUI
import AppKit

// MARK: - Colori della copertina

/// Tre colori dalla copertina: il più presente, il più saturo, uno chiaro. Senza copertina, l'azzurro di Spazio.
enum ArtPalette {
    private static var cache: [ObjectIdentifier: [Color]] = [:]

    static func colors(_ img: NSImage?) -> [Color] {
        guard let img else { return [Volta.a2, Volta.a3, Volta.a4] }
        let id = ObjectIdentifier(img)
        if let c = cache[id] { return c }
        let c = compute(img) ?? [Volta.a2, Volta.a3, Volta.a4]
        if cache.count > 20 { cache.removeAll() }
        cache[id] = c
        return c
    }

    private static func compute(_ img: NSImage) -> [Color]? {
        let n = 12
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var px: [(r: Double, g: Double, b: Double, s: Double, l: Double)] = []
        for i in 0..<(n * n) {
            let r = Double(p[i * 4]) / 255, g = Double(p[i * 4 + 1]) / 255, b = Double(p[i * 4 + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            px.append((r, g, b, mx == 0 ? 0 : (mx - mn) / mx, (mx + mn) / 2))
        }
        func color(_ x: (r: Double, g: Double, b: Double, s: Double, l: Double)) -> Color { Color(red: x.r, green: x.g, blue: x.b) }
        let avg = px.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.r, $0.1 + $1.g, $0.2 + $1.b) }
        let k = Double(px.count)
        let mean = Color(red: avg.0 / k, green: avg.1 / k, blue: avg.2 / k)
        let vivid = px.filter { $0.l > 0.18 && $0.l < 0.85 }.max { $0.s < $1.s }.map(color) ?? mean
        let bright = px.max { $0.l < $1.l }.map(color) ?? mean
        return [vivid, mean, bright]
    }
}

// MARK: - Bagliore che si muove

/// Tre luci coi colori della copertina che girano piano una attorno all'altra (fermo se la musica è in pausa).
struct MusicGlow: View {
    let colors: [Color]
    var playing: Bool
    var strength: Double = 0.55
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height, r = max(w, h)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let a = t * (0.22 + Double(i) * 0.07) + Double(i) * 2.1
                        RadialGradient(colors: [colors[i % colors.count].opacity(strength), .clear], center: .center, startRadius: 0, endRadius: r * 0.55)
                            .frame(width: r * 1.1, height: r * 1.1)
                            .position(x: w * (0.5 + 0.38 * cos(a)), y: h * (0.5 + 0.42 * sin(a * 1.3)))
                    }
                }
                .blur(radius: 18)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Equalizzatore a pixel

/// Cinque colonne di pixel che salgono e scendono, coi colori della copertina (la grammatica del razzo e della griglia 5x5).
struct PixelEQ: View {
    let colors: [Color]
    var playing: Bool
    var cell: CGFloat = 3
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let rows = 5
                for x in 0..<5 {
                    let dx = Double(x)
                    let speed: Double = 5.3 + dx * 1.7
                    let a1: Double = 1.6 * sin(t * speed + dx)
                    let a2: Double = 0.9 * sin(t * 11.0 + dx * dx)
                    let wave: Double = 2.0 + a1 + a2
                    let lv: Int = playing ? 1 + Int(wave.rounded()) : 1
                    let level = min(rows, max(1, lv))
                    for y in 0..<rows {
                        let on = y >= rows - level
                        let c = on ? colors[(rows - 1 - y) % colors.count] : Color.primary.opacity(0.10)
                        g.fill(Path(roundedRect: CGRect(x: CGFloat(x) * (cell + 1.5), y: CGFloat(y) * (cell + 1.5), width: cell, height: cell), cornerRadius: cell * 0.25),
                               with: .color(c))
                    }
                }
            }
        }
        .frame(width: 5 * cell + 4 * 1.5, height: 5 * cell + 4 * 1.5)
    }
}

// MARK: - In riproduzione, a schermo intero (griglia app)

/// La pagina della griglia con la canzone: la copertina enorme e sfocata come fondo, i suoi colori che si muovono,
/// al centro la copertina nitida che respira, titolo, artista, avanzamento e comandi. Spotify non dà il video
/// "Canvas" a chi lo legge da AppleScript: si usa la copertina.
struct NowPlayingPage: View {
    @ObservedObject var media: MediaSource
    var close: () -> Void
    @State private var breathe = false

    var body: some View {
        let t = media.track ?? media.last
        let playing = media.track?.playing == true
        let cols = ArtPalette.colors(media.artwork)
        ZStack {
            Color.black
            if let a = media.artwork {
                Image(nsImage: a).resizable().scaledToFill().blur(radius: 80).opacity(0.75).clipped()
            }
            MusicGlow(colors: cols, playing: playing, strength: 0.6)
            Color.black.opacity(0.28)
            VStack(spacing: 28) {
                Group {
                    if let a = media.artwork { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
                    else { LinearGradient(colors: [Volta.a2, Volta.a4], startPoint: .topLeading, endPoint: .bottomTrailing) }
                }
                .frame(width: 380, height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
                .scaleEffect(playing ? (breathe ? 1.015 : 0.99) : 0.96)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        PixelEQ(colors: cols.map { $0.opacity(0.95) }, playing: playing, cell: 4)
                        Text(t?.title ?? T("Niente in riproduzione", "Nothing playing")).font(.system(size: 28, weight: .regular)).tracking(-0.4)
                    }
                    Text([t?.artist, t?.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "     "))
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)
                if let tr = media.track, tr.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let pos = media.position(at: ctx.date)
                        VStack(spacing: 6) {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.18))
                                    Capsule().fill(.white.opacity(0.9)).frame(width: g.size.width * min(1, pos / tr.duration))
                                }
                            }
                            .frame(width: 380, height: 5)
                            HStack {
                                Text(ProgressBar.clock(pos)); Spacer(); Text(ProgressBar.clock(tr.duration))
                            }
                            .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).frame(width: 380)
                        }
                    }
                    .frame(height: 30)
                }
                HStack(spacing: 34) {
                    control("backward.fill", 20) { media.command(.previous) }
                    control(playing ? "pause.fill" : "play.fill", 30) { media.command(.playPause) }
                    control("forward.fill", 20) { media.command(.next) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38).background(Circle().fill(.white.opacity(0.2)))
            }
            .buttonStyle(.plain).padding(.top, 60).padding(.trailing, 48)
        }
        .onAppear { breathe = true }
        .ignoresSafeArea()
    }

    private func control(_ s: String, _ size: CGFloat, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: size)).foregroundStyle(.white.opacity(0.92)).frame(width: 56, height: 56).contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Note nella griglia

struct GridNote: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var text: String = ""
}

/// Una nota come tessera: si scrive dentro, si toglie con la crocetta al passaggio.
struct NoteTile: View {
    @Binding var note: GridNote
    let height: CGFloat
    let remove: () -> Void
    @State private var over = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TileMetrics.radius * 1.3, style: .continuous).fill(Volta.card)
            if note.text.isEmpty {
                Text(T("Scrivi una nota…", "Write a note…")).font(.system(size: 13)).foregroundStyle(Volta.t3).padding(.horizontal, 14).padding(.top, 12)
            }
            TextEditor(text: $note.text)
                .font(.system(size: 13)).foregroundStyle(Volta.t1)
                .scrollContentBackground(.hidden).background(.clear)
                .padding(.horizontal, 9).padding(.vertical, 6)
        }
        .frame(width: height * 1.6, height: height)
        .overlay(alignment: .topTrailing) {
            if over {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Volta.t2, Volta.card2)
                }
                .buttonStyle(.plain).padding(6)
            }
        }
        .onHover { over = $0 }
    }
}
