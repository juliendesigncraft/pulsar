// Il razzo di Spazio in Pulsar (17/10/2026). l'autore: "al posto di una faccia devi usare lo stesso razzo di Spazio".
// Stessa navicella 11x16 del viaggio fra i mondi (Vault/os.html, NAVE e PAL), con la palette Matte di Spazio
// (arancio e oblò diventano azzurri, fiamma azzurra). Niente occhi: il carattere sta in come si muove.
import SwiftUI

struct Razzo: View {
    enum Phase: Equatable {
        case idle        // sospeso, la fiamma respira piano
        case thrust      // Claude lavora: fiamma lunga, una vibrazione
        case wait        // aspetta un tuo ok: motore spento, l'oblò lampeggia ambra
        case catchFile   // un file sta arrivando: il razzo scende un filo e l'oblò si accende
        case loaded      // file a bordo: l'oblò resta acceso, fiamma corta
        case launch      // decollo: sale e sparisce in alto, poi torna dal basso
    }
    var phase: Phase = .idle
    var pixel: CGFloat = 3              // lato di un pixel della navicella
    var flame: Double = 1               // lunghezza della fiamma (0,6 nella compatta: il razzo non tocca i bordi)
    @State private var born = Date()    // il decollo parte quando il razzo compare, una volta sola

    // . vuoto, w scafo, s ombra, b oblò, o arancio, k contorno (identica a Spazio)
    private static let nave: [[Character]] = [
        ".....k.....", "....kwk....", "....kwk....", "...kwwwk...", "...kwbwk...", "..kwwbbwk..",
        "..kwwbbwk..", "..kwwwwsk..", "..kwwwwsk..", ".kowwwwsok.", "kooswwwsook", "kokssssskok",
        "k.kssssk..k", "...koook...", "....k.k....", "..........."].map(Array.init)
    // palette Matte di Spazio (SpazioAspetto 'matte'): o e b azzurri
    private static let pal: [Character: Color] = [
        "w": Color(red: 232/255, green: 230/255, blue: 239/255), "s": Color(red: 150/255, green: 156/255, blue: 184/255),
        "b": Color(red: 185/255, green: 220/255, blue: 255/255), "o": Color(red: 143/255, green: 199/255, blue: 255/255),
        "k": Color(red: 12/255, green: 14/255, blue: 22/255)]
    private static let flame = [Color(red: 228/255, green: 240/255, blue: 255/255), Color(red: 185/255, green: 220/255, blue: 255/255),
                                Color(red: 143/255, green: 199/255, blue: 255/255)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let p = pixel
                // dove sta la navicella (in pixel della navicella) secondo la fase
                var dx = 0.0, dy = 0.0
                var flameLen = 0.0
                var porthole: Color? = nil
                switch phase {
                case .idle:
                    dy = (sin(t * 1.6) * 0.8).rounded()
                    flameLen = 2 + abs(sin(t * 9)) * 1.5
                case .thrust:
                    dx = (sin(t * 31) * 0.4).rounded(); dy = -1
                    flameLen = 5 + 3 * abs(sin(t * 40))
                case .wait:
                    dy = (sin(t * 1.1) * 0.6).rounded()
                    porthole = sin(t * 4) > 0 ? Color(red: 0.95, green: 0.97, blue: 1) : Volta.a3   // 17/10: solo azzurro, niente ambra
                case .catchFile:
                    dy = 1 + (sin(t * 6) * 0.5).rounded()
                    flameLen = 1.5 + abs(sin(t * 12))
                    porthole = sin(t * 5) > 0 ? Color(red: 0.84, green: 0.92, blue: 1) : Color(red: 0.56, green: 0.78, blue: 1)
                case .loaded:
                    dy = (sin(t * 1.6) * 0.6).rounded()
                    flameLen = 2 + abs(sin(t * 9))
                    porthole = Color(red: 0.95, green: 0.97, blue: 1)
                case .launch:
                    // una volta: sale e sparisce, poi rientra dal basso e resta sospeso
                    let u = min(1, ctx.date.timeIntervalSince(born) / 2.4)
                    let h = Double(size.height / p) + 18
                    dy = u < 0.55 ? -pow(u / 0.55, 2) * h : (1 - Self.ease((u - 0.55) / 0.45)) * h
                    flameLen = u < 0.55 ? 6 + 3 * abs(sin(t * 40)) : 2 + 2 * (1 - (u - 0.55) / 0.45)
                }
                let w = 11.0, hN = 16.0
                let ox = (Double(size.width) / Double(p) - w) / 2 + dx
                let oy = (Double(size.height) / Double(p) - hN - (flame < 1 ? -2 : 0)) / 2 - 2 + dy
                func cell(_ c: Double, _ r: Double, _ col: Color) {
                    g.fill(Path(CGRect(x: (ox + c).rounded() * Double(p), y: (oy + r).rounded() * Double(p), width: Double(p), height: Double(p))), with: .color(col))
                }
                for (r, row) in Self.nave.enumerated() {
                    for (c, ch) in row.enumerated() {
                        guard var col = Self.pal[ch] else { continue }
                        if ch == "b", let porthole { col = porthole }
                        cell(Double(c), Double(r), col)
                    }
                }
                // fiamma: tre colonne al centro, più corta ai lati (come in Spazio)
                let L = Int((flameLen * flame).rounded())
                for i in 0..<max(0, L) {
                    for wcol in -1...1 {
                        if abs(wcol) == 1 && Double(i) > Double(L) * 0.6 { continue }
                        let col = Double(i) < Double(L) * 0.35 ? Self.flame[0] : Double(i) < Double(L) * 0.7 ? Self.flame[1] : Self.flame[2]
                        cell(5 + Double(wcol), 15 + Double(i), col)
                    }
                }
            }
        }
    }

    static func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - pow(1 - c, 3) }
}
