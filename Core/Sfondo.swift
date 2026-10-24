// Pulsar — aspetto SFONDO (11/10/2026). l'autore: "aggiungi un tema che matchi il background e che abbia
// l'accento di sistema, o magari un accento che ci azzecchi. Sempre stile Swift Apple, con vetri e trasparenze."
// Vetro Liquid Glass di macOS 26 con un velo leggerissimo del colore dello sfondo che sta dietro l'elemento
// (la fascia del bordo sinistro o destro), testo chiaro o scuro scelto per il contrasto (WCAG 4,5:1),
// accento di sistema oppure il colore più vivo dello sfondo. Si ricalcola solo quando cambia qualcosa:
// sfondo, Spazio, schermi, accento di sistema, bordo dell'elemento. Niente timer.

import AppKit
import SwiftUI
import ImageIO

struct WallInfo {
    var edge: NSColor            // colore medio della fascia del bordo
    var veil: NSColor            // il velo sul vetro (colore e opacità)
    var darkText: Bool
    var wallAccent: NSColor      // il colore più vivo dello sfondo, già reso leggibile
    var scheme: ColorScheme { darkText ? .light : .dark }

    static let neutral = WallInfo(edge: NSColor(white: 0.2, alpha: 1), veil: NSColor(white: 0.08, alpha: 0.3),
                                  darkText: false, wallAccent: .controlAccentColor)
}

// MARK: - Colori: luminanza e contrasto WCAG

enum Wcag {
    static func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func rgb(_ c: NSColor) -> (CGFloat, CGFloat, CGFloat) {
        let s = c.usingColorSpace(.sRGB) ?? NSColor(white: 0.5, alpha: 1)
        return (s.redComponent, s.greenComponent, s.blueComponent)
    }
    static func lum(_ c: NSColor) -> CGFloat {
        let (r, g, b) = rgb(c)
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let x = lum(a), y = lum(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
        return NSColor(srgbRed: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
    static func hsb(_ c: NSColor, sat: (CGFloat) -> CGFloat, bri: CGFloat) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        return NSColor(hue: s.hueComponent, saturation: sat(s.saturationComponent), brightness: bri, alpha: 1).usingColorSpace(.sRGB)!
    }
}

/// Il calcolo puro: dall'immagine dello sfondo alle tinte. Separato per poterlo provare su un file qualunque.
enum WallMath {
    /// L'immagine a bassa risoluzione (64 px sul lato lungo), in RGBA sRGB.
    static func pixels(_ url: URL) -> (w: Int, h: Int, px: [UInt8])? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary)
        else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, px)
    }

    static func info(_ url: URL, side: EdgeSide) -> WallInfo? {
        guard let (w, h, px) = pixels(url), w > 2, h > 2 else { return nil }
        // fascia del bordo: il 18% dal lato dove sta l'elemento
        let band = max(1, Int(Double(w) * 0.18))
        let xs = side == .left ? 0..<band : (w - band)..<w
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in 0..<h { for x in xs {
            let i = (y * w + x) * 4
            r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); n += 1
        } }
        let edge = NSColor(srgbRed: r / n / 255, green: g / n / 255, blue: b / n / 255, alpha: 1)

        // testo bianco o scuro, e il velo minimo che porta il contrasto oltre 4,5:1 (con margine per la sfocatura)
        let darkText = Wcag.lum(edge) >= 0.32
        let veilColor = darkText ? Wcag.hsb(edge, sat: { min($0, 0.22) }, bri: 0.98)
                                 : Wcag.hsb(edge, sat: { min($0, 0.5) }, bri: 0.12)
        var alpha: CGFloat = darkText ? 0.14 : 0.18
        while alpha < 0.7 {
            let bg = Wcag.mix(edge, veilColor, alpha)
            let ok = darkText ? Wcag.lum(bg) >= 0.36 : Wcag.lum(bg) <= 0.13
            if ok { break }
            alpha += 0.02
        }
        let bg = Wcag.mix(edge, veilColor, alpha)

        // accento: la tinta più viva (12 spicchi di tinta pesati per saturazione e luce), resa leggibile sul fondo
        var bins = [(w: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = NSColor(srgbRed: CGFloat(px[i]) / 255, green: CGFloat(px[i + 1]) / 255, blue: CGFloat(px[i + 2]) / 255, alpha: 1)
            let s = c.saturationComponent, v = c.brightnessComponent
            guard s > 0.25, v > 0.25 else { continue }
            let k = min(11, Int(c.hueComponent * 12)), wgt = Double(s * s * v)
            bins[k].w += wgt; bins[k].r += Double(px[i]) * wgt; bins[k].g += Double(px[i + 1]) * wgt; bins[k].b += Double(px[i + 2]) * wgt
        }
        var accent = NSColor.controlAccentColor
        if let best = bins.max(by: { $0.w < $1.w }), best.w > 0.5 {
            let base = NSColor(srgbRed: best.r / best.w / 255, green: best.g / best.w / 255, blue: best.b / best.w / 255, alpha: 1)
            // tacche e cursori: almeno 3:1 sul fondo (componenti dell'interfaccia), saturazione piena ma non al neon
            var bri: CGFloat = darkText ? 0.62 : 0.92
            var c = Wcag.hsb(base, sat: { max(0.5, min($0, 0.85)) }, bri: bri)
            while Wcag.contrast(c, bg) < 3, bri > 0.2, bri < 1 {
                bri += darkText ? -0.04 : 0.02
                c = Wcag.hsb(base, sat: { max(0.5, min($0, 0.85)) }, bri: min(1, bri))
            }
            // se la sola luce non basta (viola su viola), si sbianca o si scurisce finché si legge
            var t: CGFloat = 0
            let toward: NSColor = darkText ? .black : .white
            while Wcag.contrast(c, bg) < 3, t < 0.9 { t += 0.05; c = Wcag.mix(c, toward, 0.05 / (1 - t + 0.05)) }
            accent = c
        }
        return WallInfo(edge: edge, veil: veilColor.withAlphaComponent(alpha), darkText: darkText, wallAccent: accent)
    }
}

// MARK: - Lo stato condiviso

final class WallpaperTint: ObservableObject {
    static let shared = WallpaperTint()
    @Published private(set) var version = 0
    private var cache: [String: WallInfo] = [:]
    private var lastURLs: [String] = []

    /// Accento: quello di sistema (predefinito) o il colore più vivo dello sfondo.
    var useWallAccent: Bool {
        get { Impostazioni.string(.wallAccent) == "sfondo" }
        set { Impostazioni.set(newValue ? "sfondo" : "sistema", .wallAccent); version += 1 }
    }

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(changed), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accentChanged), name: NSColor.systemColorsDidChangeNotification, object: nil)
        // l'avviso di sfondo cambiato non è pubblico: questo nome lo mandano le versioni di macOS che lo hanno
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed),
                                                            name: NSNotification.Name("com.apple.desktop"), object: "BackgroundChanged")
    }

    @objc private func changed() { DispatchQueue.main.async { self.refreshIfChanged(force: true) } }
    @objc private func accentChanged() { DispatchQueue.main.async { self.version += 1 } }

    /// Rilegge solo se lo sfondo di qualche schermo è cambiato davvero (chiamata anche quando un elemento esce).
    func refreshIfChanged(force: Bool = false) {
        let urls = NSScreen.screens.map { s -> String in
            guard let u = NSWorkspace.shared.desktopImageURL(for: s) else { return "" }
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(u.path)|\(d)"
        }
        guard force || urls != lastURLs else { return }
        lastURLs = urls
        cache = [:]
        version += 1
        if Theme.mode == .sfondo { Theme.refreshAppearance() }
    }

    func info(screen: NSScreen, side: EdgeSide) -> WallInfo {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return .neutral }
        let key = "\(url.path)|\(side.rawValue)"
        if let c = cache[key] { return c }
        let i = WallMath.info(url, side: side) ?? .neutral
        cache[key] = i
        return i
    }

    func info(_ look: EdgeLook) -> WallInfo { info(screen: look.screen, side: look.side) }

    func accent(_ look: EdgeLook) -> NSColor { useWallAccent ? info(look).wallAccent : .controlAccentColor }
    /// Per i colori senza un elemento preciso (tacche, cursori): lo schermo principale.
    var accent: NSColor {
        useWallAccent ? info(screen: EdgeDock.defaultScreen, side: .left).wallAccent : .controlAccentColor
    }
}

extension EdgeLook {
    /// Lo schermo dove sta l'elemento (lo tiene aggiornato EdgeDock).
    var screen: NSScreen {
        NSScreen.screens.first { EdgeDock.displayID($0) == screenID } ?? EdgeDock.defaultScreen
    }
}

/// La superficie di ogni elemento secondo l'aspetto, sulla sua forma. `solid`: il colore pieno di Notte
/// (per la pillola nel notch è il nero, che continua il notch vero).
struct ThemeSurface<S: Shape>: ViewModifier {
    let mode: AgentMode
    let shape: S
    var solid: AnyShapeStyle = AnyShapeStyle(Night.barFill)
    var veil: Color = Theme.veil
    func body(content: Content) -> some View {
        switch mode {
        case .notte, .bianco: content.background(shape.fill(solid))
        case .sfondo: content.glassEffect(.regular.tint(veil), in: shape)
        }
    }
}
