// Pagina Info: nome, versione e crediti (come nel README e in sounds/FONTI.md).
import SwiftUI
import AppKit

struct PaginaInfo: View {
    /// L'icona da mostrare: nell'app è quella del pacchetto; le foto da terminale (senza pacchetto) la mettono da assets/.
    static var icona: NSImage?
    @Environment(\.matte) private var m

    var body: some View {
        let versione = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0"
        PaginaCornice(titolo: PaginaImpostazioni.info.titolo) {
            HStack(spacing: 14) {
                Image(nsImage: Self.icona ?? NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pulsar").font(.system(size: 17)).foregroundStyle(m.t1)
                    Text(T("Versione \(versione)", "Version \(versione)")).font(.system(size: MisureImpostazioni.piccolo + 1)).foregroundStyle(m.t2)
                }
            }
            .padding(.leading, 4)
            GruppoImpostazioni(T("Crediti", "Credits")) {
                RigaValore(T("Suoni meccanici", "Mechanical sounds"), valore: "ClickClack, César Ferreira, MIT")
                RigaValore(T("Macchina da scrivere", "Typewriter"), valore: "BigSoundBank, Joseph Sardin, CC0")
                RigaValore(T("Linea con Claude", "Line with Claude"), valore: "coucou, Louis Raillé, MIT")
            }
        }
    }
}
