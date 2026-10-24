// Pagina Generale: l'aspetto rapido (Dark Matte, White Matte, Sfondo) e la lingua.
// L'aspetto usa lo stesso metodo del menu TEMA (FinestraImpostazioni.scegliAspetto, collegato da AppDelegate).
// Nella vendita anche "Mostra di nuovo il benvenuto" (compito 7) e "Cerca aggiornamenti da solo" (fase 5, 3b).
import SwiftUI

struct PaginaGenerale: View {
    private static let vendita = true
    @ObservedObject private var look = GhieraLook.shared
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto

    private static let aggiornamentiPerFoto: Bool? = nil
    private static func aggiornamentiAutomatici(foto: Bool) -> Bool {
        if let f = aggiornamentiPerFoto { return f }
        if foto { return true }   // nelle foto come lo trova il cliente: acceso
        return Impostazioni.aggiornamentiAutomatici
    }
    /// Nelle foto un tocco non scrive niente: la preferenza vera resta com'era.
    private static func impostaAggiornamenti(_ acceso: Bool, foto: Bool) {
        guard !foto, aggiornamentiPerFoto == nil else { return }
        Aggiornamenti.shared.automatici = acceso
    }

    var body: some View {
        // nelle foto l'aspetto scelto è quello della foto, non quello salvato
        let modo: AgentMode = foto ? (m.chiaro ? .bianco : .notte) : look.mode
        SeLicenzaCambia {
            PaginaCornice(titolo: PaginaImpostazioni.generale.titolo) {
                GruppoImpostazioni(T("Aspetto", "Look")) {
                    if RegistroModuli.shared.bloccato("temi") {
                        RigaTasto(T("Dark Matte e White Matte", "Dark Matte and White Matte"),
                                  tasto: T("Sblocca con \(Licenza.nome(.complete))…", "Unlock with \(Licenza.nome(.complete))…"),
                                  principale: true) { LicenzaViva.shared.chiedi() }
                    } else {
                        RigaScelta(T("Tema", "Theme"),
                                   opzioni: AgentMode.allCases.map { (id: $0.rawValue, titolo: $0.title) },
                                   valore: { foto ? modo.rawValue : GhieraLook.shared.mode.rawValue }) { raw in
                            if let a = AgentMode(rawValue: raw) { FinestraImpostazioni.shared.scegliAspetto(a) }
                        }
                    }
                }
                GruppoImpostazioni {
                    RigaValore(T("Lingua", "Language"),
                               valore: pulsarItalian ? "Italiano, come il Mac" : "English, like your Mac")
                }
                // fase 5, 3b: Sparkle cerca le versioni nuove da solo (acceso di serie); solo nella vendita, nelle foto sempre
                if Self.vendita || foto {
                    GruppoImpostazioni(T("Aggiornamenti", "Updates")) {
                        RigaInterruttore(T("Cerca aggiornamenti da solo", "Check for updates automatically"),
                                         sotto: T("Una volta al giorno legge l'elenco delle versioni nuove. Non manda niente su di te.",
                                                  "Once a day Pulsar reads the list of new versions. It sends nothing about you."),
                                         valore: { Self.aggiornamentiAutomatici(foto: foto) }) { Self.impostaAggiornamenti($0, foto: foto) }
                    }
                }
                // compito 7: solo nella vendita (nella personale il benvenuto si apre con pulsar://benvenuto); nelle foto sempre
                if Self.vendita || foto {
                    GruppoImpostazioni {
                        RigaTasto(T("Benvenuto", "Welcome"), tasto: T("Mostra di nuovo", "Show again")) {
                            FinestraBenvenuto.shared.apri()
                        }
                    }
                }
            }
        }
    }
}
