// Rowline nel registro dei moduli (19/10/2026): le finestre in fila, dentro Pulsar Complete.
// Il codice di Rowline sta in Moduli/Rowline/Kit, compilato a parte come RowlineKit (vedi sorgenti.sh, rowline_kit).
// Qui solo l'aggancio: interruttore (Chiave.rowlineAcceso), licenza (Complete), permesso (Accessibilità).
import AppKit
import RowlineKit

final class ModuloRowline: ModuloPulsar {
    static let shared = ModuloRowline()
    private var partito = false
    private var annullato = false     // spento durante l'attesa della vecchia app: l'attesa non deve più farlo partire

    var id: String { "rowline" }
    var nome: String { "Rowline" }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [.accessibilita] }
    var acceso: Bool {
        get { Impostazioni.object(.rowlineAcceso) as? Bool ?? true }
        set { Impostazioni.set(newValue, .rowlineAcceso); RegistroModuli.shared.riapplica() }
    }

    func avvia() {
        annullato = false
        parti()
    }

    private func parti() {
        if partito { RowlineKit.riprendi() } else {
            RowlineKit.quandoImpostazioni { FinestraImpostazioni.shared.apri(.rowline) }
            RowlineKit.avvia(cartellaPulsar: Cartelle.dati); partito = true
        }
    }


    func ferma() { annullato = true; RowlineKit.ferma() }

    func apriPannello() { RowlineKit.apriPannello() }
    func riordina() { RowlineKit.riordina() }
    var inFila: Bool {
        get { RowlineKit.inFila }
        set { RowlineKit.inFila = newValue }
    }
}
