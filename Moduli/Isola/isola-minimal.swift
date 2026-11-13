// Pulsar — il notch Minimal (13/11/2026). l'autore: "puoi creare una UI alternativa che si può switchare a piacimento,
// più minimal? Il mio reel più piaciuto aveva un notch minimal". Il modello è il notch del reel del 12/10 (215.647 views,
// Reel/_pubblica/linkedin-notch): sopra solo icone piccole e grigie, una fila sola di quattro tessere (musica, meteo,
// prossimo evento, timer), sotto la riga della canzone. Niente schede, cielo o bagliori. Claude e le comparse come sempre.
// Si sceglie in Impostazioni → Aspetto o nella scheda Rapidi del pannello della barra. Di serie: Completo.
import SwiftUI
import AppKit

final class NotchMinimal: ObservableObject {
    static let shared = NotchMinimal()
    /// L'isola la imposta: un cambio ridisegna subito la forma (stesso richiamo del trascinamento e delle schede).
    weak var model: IslandModel?
    @Published var acceso: Bool = Impostazioni.bool(.isolaMinimal) {
        didSet {
            Impostazioni.set(acceso, .isolaMinimal)
            if acceso { model?.tab = .casa }
            model?.dropChanged?()
        }
    }

    /// Le quattro tessere del reel e quante celle occupa ognuna (84 pt la cella, 8 di spazio).
    static let tessere: [(id: String, celle: Int)] = [("music", 2), ("weather", 2), ("calendar", 2), ("timer", 1)]
    static var celleTotali: Int { tessere.reduce(0) { $0 + $1.celle } }
    static var larghezza: CGFloat { CGFloat(celleTotali) * TileMetrics.cell + CGFloat(celleTotali - 1) * TileMetrics.gap + 40 }
    static let altezzaTesto: CGFloat = 38

    /// Sotto le tessere la riga della canzone, solo se ne suona una con il testo.
    static func conTesto(_ model: IslandModel) -> Bool {
        guard let m = model.home as? MediaSource, m.track?.playing == true else { return false }
        if case .none = m.lyrics { return false }
        return true
    }
    static func altezza(_ model: IslandModel) -> CGFloat { TileMetrics.rowH + (conTesto(model) ? altezzaTesto : 0) }
}

/// La fascia ai lati del notch, come nel reel: a sinistra impostazioni, griglia, volume, luce e tema; a destra AirDrop,
/// File e Note. Icone piccole e grigie, nessuna scheda.
struct MinimalHead: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let half = max(0, (model.width - model.notchWidth) / 2 - 30)
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                icona("gearshape", T("Impostazioni di Sistema", "System Settings")) { IslandActions.settings() }
                icona("square.grid.3x3", T("Griglia app", "App grid")) { model.openGrid?() }
                if let d = model.dial {
                    if d.enabled, let it = d.soundItem { icona("speaker.wave.2", T("Volume", "Volume")) { EdgeDock.shared.reveal(it, hideAfter: 4) } }
                    if d.lightEnabled, let it = d.lightItem { icona("sun.max", T("Luminosità", "Brightness")) { EdgeDock.shared.reveal(it, hideAfter: 4) } }
                }
                icona("circle.lefthalf.filled", T("Tema", "Theme")) { model.toggleTheme?() }
                Spacer(minLength: 0)
            }
            .frame(width: half)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                icona("dot.radiowaves.up.forward", "AirDrop") { IslandActions.airDrop() }
                icona("folder", T("File", "Files")) { IslandActions.files() }
                icona("note.text", T("Note", "Notes")) { IslandActions.notes() }
            }
            .frame(width: half)
        }
        .padding(.horizontal, 22)
        .frame(height: model.notchHeight)
    }

    private func icona(_ simbolo: String, _ aiuto: String, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Image(systemName: simbolo).font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Volta.t2).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(aiuto)
    }
}

/// La Casa minimal: una fila di quattro tessere e, se suona una canzone, il suo testo sotto.
struct MinimalHome: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: TileMetrics.gap) {
                ForEach(NotchMinimal.tessere, id: \.id) { t in
                    if let w = model.widgets.first(where: { $0.id == t.id }) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous).fill(Volta.card)
                            w.body(cells: t.celle).padding(10)
                        }
                        .frame(width: CGFloat(t.celle) * TileMetrics.cell + CGFloat(t.celle - 1) * TileMetrics.gap, height: TileMetrics.rowH, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous))
                    }
                }
            }
            if NotchMinimal.conTesto(model), let m = model.home as? MediaSource {
                LyricsLine(src: m).foregroundStyle(Volta.t1).frame(height: NotchMinimal.altezzaTesto - 6)
            }
        }
    }
}
