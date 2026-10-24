// Pagina Rowline: le voci del sottomenu Rowline sotto ISOLA. Stessi metodi del menu: ModuloRowline.shared.acceso
// (toggleRowline, il registro avvia o ferma Rowline), apriPannello (openRowline) e riordina (tidyRowline).
import SwiftUI

struct PaginaRowline: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var acceso: Bool { ModuloRowline.shared.acceso }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("rowline", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.rowline.titolo,
                               riga: T("Le finestre in fila orizzontale, da far scorrere come una striscia.",
                                       "Your windows in one horizontal row that scrolls like a strip."),
                               prodotto: RegistroModuli.shared.prodotto(di: "rowline") ?? .complete)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.rowline.titolo) {
                    GruppoAcceso(valore: { Self.acceso }) { ModuloRowline.shared.acceso = $0 }
                    GruppoImpostazioni {
                        RigaTasto(T("Rowline  ⌃⌥⌘F", "Rowline  ⌃⌥⌘F"), tasto: T("Apri Rowline", "Open Rowline")) { ModuloRowline.shared.apriPannello() }
                        RigaTasto(T("Finestre", "Windows"), tasto: T("Riordina le finestre", "Tidy up windows")) { ModuloRowline.shared.riordina() }
                    }
                    .attenuata(!Self.acceso)
                } }
            }
        }
    }
}
