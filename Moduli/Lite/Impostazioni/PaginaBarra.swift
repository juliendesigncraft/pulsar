// Pagina Barra dei menu: la Barra pulita e quante cartelle della Scrivania mostrare nel menu.
// Gli elenchi (App in background, Scrivania) restano nel menu: sono da usare, non impostazioni.
// La Barra pulita alterna con lo stesso metodo del menu (AppDelegate.toggleBar, via FinestraImpostazioni.alternaBarraPulita);
// il valore si legge dalla stessa chiave (Chiave.barCollapsed). La guardia (barra-guardia.swift) segue da sola.
import SwiftUI

/// Quante cartelle della Scrivania il menu mostra prima di "Altre n…". Un solo punto per il menu e per la pagina.
enum ScrivaniaConteggio {
    static let scelte = [4, 5, 6, 8]
    static var valore: Int {
        get {
            let n = Impostazioni.integer(.visibleDesktopCount)
            return n == 0 ? 5 : n
        }
        set { Impostazioni.set(newValue, .visibleDesktopCount) }
    }
}

struct PaginaBarra: View {
    var body: some View {
        PaginaCornice(titolo: PaginaImpostazioni.barra.titolo) {
            GruppoImpostazioni(T("Barra", "Bar")) {
                RigaInterruttore(T("Barra pulita", "Clean menu bar"),
                                 sotto: T("⌘-trascina un'icona a sinistra della capsula per nasconderla",
                                          "⌘-drag an icon left of the capsule to hide it"),
                                 valore: { Impostazioni.bool(.barCollapsed) }) { acceso in
                    if acceso != Impostazioni.bool(.barCollapsed) { FinestraImpostazioni.shared.alternaBarraPulita() }
                }
            }
            GruppoImpostazioni(T("Scrivania", "Desktop")) {
                RigaScelta(T("Quante mostrarne", "How many to show"),
                           opzioni: ScrivaniaConteggio.scelte.map { (id: "\($0)", titolo: "\($0)") },
                           valore: { "\(ScrivaniaConteggio.valore)" }) { raw in
                    if let n = Int(raw) { ScrivaniaConteggio.valore = n }
                }
            }
        }
    }
}
