// Pulsar — il notch Minimal (13/11/2026). l'autore: "puoi creare una UI alternativa che si può switchare a piacimento,
// più minimal? Il mio reel più piaciuto aveva un notch minimal", poi: "come minimal intendevo il look, tutte le funzioni
// mettile" e "metti una homepage e la schermata di avvio animata".
// Quindi Minimal è un ASPETTO, le funzioni restano tutte (stesse schede, stessa testa, stesso pannello di Claude):
//   - la Casa ha lo sfondo del saluto all'avvio (nero del tema, stelle che si accendono e respirano) al posto del cielo a pixel;
//   - le card sono piatte: niente bagliore in basso, niente colori della copertina che si muovono;
//   - il pannello di Claude a destra usa righe di testo al posto delle card (agente.swift, workMinimal).
// Si sceglie in Impostazioni → Aspetto o nella scheda Rapidi del pannello della barra. Di serie: Completo.
import SwiftUI
import AppKit

final class NotchMinimal: ObservableObject {
    static let shared = NotchMinimal()
    /// L'isola la imposta: un cambio ridisegna subito (stesso richiamo del trascinamento e delle schede).
    weak var model: IslandModel?
    @Published var acceso: Bool = Impostazioni.bool(.isolaMinimal) {
        didSet {
            Impostazioni.set(acceso, .isolaMinimal)
            model?.dropChanged?()
        }
    }
}

/// Lo sfondo dei riquadri della Casa: il cielo a pixel in Completo, le stelle del saluto all'avvio in Minimal.
struct SfondoCasa: View {
    @ObservedObject private var minimal = NotchMinimal.shared
    @State private var nato = Date().addingTimeInterval(-2)       // le stelle già accese quando si apre
    var body: some View {
        if minimal.acceso {
            ZStack { Volta.body; Cielo(nato: nato, colore: Theme.light ? Volta.t1.opacity(0.55) : .white) }
        } else {
            CieloPixel()
        }
    }
}
