// Pagina Scorciatoie: sola lettura, dall'elenco unico Core/Scorciatoie.swift.
import SwiftUI

struct PaginaScorciatoie: View {
    @Environment(\.matte) private var m

    var body: some View {
        let griglia: String = {
            switch GridModule.hotKey {
            case .cmd4: return "⌘4"
            case .ctrlOptSpace: return T("⌃⌥Spazio", "⌃⌥Space")
            case .off: return T("Spenta", "Off")
            }
        }()
        let righe = Scorciatoie.elenco(italiano: pulsarItalian, griglia: griglia)
        let moduli = righe.reduce(into: [String]()) { if !$0.contains($1.modulo) { $0.append($1.modulo) } }
        PaginaCornice(titolo: PaginaImpostazioni.scorciatoie.titolo) {
            ForEach(moduli, id: \.self) { mod in
                GruppoImpostazioni(mod) {
                    ForEach(righe.filter { $0.modulo == mod }, id: \.tasti) { r in
                        RigaBase(titolo: r.cosa) {
                            Text(r.tasti)
                                .font(.system(size: MisureImpostazioni.testo))
                                .foregroundStyle(m.t1)
                                .padding(.horizontal, 8).frame(minWidth: 34, minHeight: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(m.t1.opacity(m.chiaro ? 0.06 : 0.08)))
                        }
                    }
                }
            }
        }
    }
}
