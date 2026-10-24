// Isola sempre accesa, simboli delle app e tasti rapidi del menu (le icone a puntini DotIcon/DotGlyphs, 12/10/2026,
// sono state tolte il 18/10/2026: nessuno le usava più).
import SwiftUI

// MARK: - L'isola sempre accesa (12/10/2026 sera)
// l'autore, vedendo il notch vuoto a fine lavoro: "ma ora non ci sono più". Quando nessuna fonte ha qualcosa da dire,
// l'isola resta compatta: a sinistra le app aperte a pastiglia, a destra la griglia di Claude ferma-lenta.
// Priorità più bassa di tutte: musica, Claude e Anima la scavalcano. Si spegne dal menu ISOLA ("LED sempre acceso").

final class AmbientSource: IslandSource {
    let id = "ambiente"
    let priority = 1
    var onChange: (() -> Void)?
    var usesHome: Bool { true }
    static var enabled: Bool {
        get { Impostazioni.object(.isolaAmbiente) as? Bool ?? true }
        set { Impostazioni.set(newValue, .isolaAmbiente) }
    }
    var isActive: Bool { Self.enabled }
    // a riposo: a sinistra le app aperte a pastiglia, a destra la griglia
    func compactLeading() -> AnyView { AnyView(PastiglieInSequenza()) }      // le app aperte, a pastiglia
    // 23/10, l'autore: "a destra a riposo alterna il razzo solo con l'animazione del menu laterale di Pulsar e basta"
    func compactTrailing() -> AnyView { AnyView(RazzoEGlifo()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

/// A riposo, a destra del notch: il razzo di Spazio e il glifo 3x3 del menu laterale (PixelGlyph), uno alla volta,
/// sette secondi ciascuno, con una dissolvenza lenta. Nient'altro (né griglia 5x5 né app).
private struct RazzoEGlifo: View {
    private static let turno = 7.0
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let razzo = Int(ctx.date.timeIntervalSinceReferenceDate / Self.turno) % 2 == 0
            ZStack {
                if razzo {
                    Razzo(phase: .idle, pixel: 1.15, flame: 0.6).frame(width: 18, height: 25).clipped().transition(.opacity)
                } else {
                    PixelGlyph(palette: [Volta.a2, Volta.a1, Volta.a3]).transition(.opacity)
                }
            }
            .frame(width: 18, height: 25)
            .animation(.easeInOut(duration: 0.8), value: razzo)
        }
    }
}

// MARK: - Un simbolo di sistema per ogni app (12/10/2026, tarda sera)
/// Un simbolo di sistema per ogni app (niente puntini).
enum AppSymbol {
    static func of(name: String, bundle: String) -> String {
        let n = name.lowercased().replacingOccurrences(of: "\u{200e}", with: ""), b = bundle.lowercased()
        func has(_ k: String...) -> Bool { k.contains { n.contains($0) || b.contains($0) } }
        if has("claude") { return "sparkle" }
        if has("chrome", "safari", "firefox", "arc") { return "globe" }
        if has("whatsapp", "messag", "telegram") { return "bubble.left.fill" }
        if has("finder") { return "face.smiling" }
        if has("terminal", "iterm", "warp") { return "terminal.fill" }
        if has("figma", "framer", "paper", "sketch") { return "pencil.and.outline" }
        if has("spotify", "music", "musica") { return "music.note" }
        if has("memo", "voicememos") { return "waveform" }
        if has("utm", "parallels") { return "cube.fill" }
        if has("mail") { return "envelope.fill" }
        if has("notes", "note") { return "note.text" }
        if has("calendar", "calendario") { return "calendar" }
        if has("preview", "anteprima", "photos", "foto") { return "photo" }
        if has("textedit", "pages", "word") { return "doc.text.fill" }
        if has("quicktime", "vlc", "tv") { return "play.rectangle.fill" }
        if has("app store") { return "bag.fill" }
        if has("settings", "impostazioni") { return "gearshape.fill" }
        return "app.fill"
    }
}

// MARK: - Tasti rapidi del menu di Pulsar (13/10/2026)
// l'autore: "l'app Pulsar è davvero lunga, è possibile renderla più carina?". In cima al menu una griglia 4x2 come il
// Centro di Controllo: tasto tondo, acceso = pieno nell'azzurro di Spazio, nome piccolo sotto. Un clic cambia e chiude.

struct QuickTile: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let on: Bool
    let act: () -> Void
}

struct QuickGrid: View {
    let tiles: [QuickTile]
    var small: [QuickTile] = []
    /// 19/10 sera, l'autore: "aggiungici delle icone per tutti gli extra di Pulsar, magari un giorno non voglio più il menu
    /// a destra attivo". Un tasto per pezzo (Claude, Ghiere, Isola, Voce, Rowline, Muta): azzurro = acceso, un clic lo cambia.
    var moduli: [QuickTile] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            griglia
            if !moduli.isEmpty {
                Text(T("Pezzi di Pulsar", "Pulsar pieces")).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.5)).padding(.leading, 14).padding(.top, 2)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 6), count: 4), spacing: 10) {
                    ForEach(moduli) { t in QuickTileView(tile: t) }
                }
                .frame(width: 272)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
            }
        }
    }

    private var griglia: some View {
        HStack(alignment: .top, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 6), count: 4), spacing: 10) {
                ForEach(tiles) { t in QuickTileView(tile: t) }
            }
            .frame(width: 272)
            if !small.isEmpty {
                // le azioni piccole, a destra: riga con icona e nome, come voci di menu ma raccolte
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(small) { t in SmallActionRow(tile: t) }
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SmallActionRow: View {
    let tile: QuickTile
    @State private var over = false
    var body: some View {
        Button(action: tile.act) {
            HStack(spacing: 9) {
                Image(systemName: tile.symbol).font(.system(size: 11.5, weight: .medium)).frame(width: 16)
                    .foregroundStyle(Color.primary.opacity(0.7))
                Text(tile.title).font(.system(size: 12.5)).foregroundStyle(Color.primary.opacity(0.85)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(over ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
    }
}

private struct QuickTileView: View {
    let tile: QuickTile
    @State private var over = false
    var body: some View {
        Button(action: tile.act) {
            VStack(spacing: 5) {
                ZStack {
                    // l'azzurro chiaro di Spazio (#8FC7FF) in tutti e due i temi (l'autore: "più chiaro, come in Spazio")
                    Circle().fill(tile.on ? Color(red: 0x8F / 255, green: 0xC7 / 255, blue: 1) : Color.primary.opacity(over ? 0.14 : 0.08))
                    Image(systemName: tile.symbol).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tile.on ? Color.black.opacity(0.78) : Color.primary.opacity(0.8))
                }
                .frame(width: 40, height: 40)
                Text(tile.title).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .animation(.easeOut(duration: 0.12), value: over)
    }
}
