// Pagina Aspetto: la sezione TEMA del menu. Dark Matte e White Matte con lo stesso metodo della voce TEMA
// (FinestraImpostazioni.scegliTema, collegato da AppDelegate a scegliTema, come setTema), l'aspetto Sfondo come
// "Altri aspetti di Pulsar" (AgentModule.mode, come setAgentLook) e l'accento dello Sfondo (WallpaperTint.useWallAccent,
// come setWallAccent). Nessun "Acceso": è una scelta, non un servizio che gira.
// "Rimetti ghiere e colonna al loro posto" sta nella pagina Ghiere (e in Claude Code quando le Ghiere sono bloccate).
import SwiftUI

struct PaginaAspetto: View {
    @ObservedObject private var look = GhieraLook.shared
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto
    @Environment(\.fotoBloccato) private var fotoBloccato

    var body: some View {
        // nelle foto l'aspetto scelto è quello della foto, non quello salvato
        let modo: AgentMode = foto ? (m.chiaro ? .bianco : .notte) : look.mode
        SeLicenzaCambia {
            if moduloBloccato("temi", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.aspetto.titolo,
                               riga: Self.rigaBloccata,
                               prodotto: RegistroModuli.shared.prodotto(di: "temi") ?? .complete)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.aspetto.titolo) {
                    GruppoImpostazioni(T("Tema  ⌃⌥L", "Theme  ⌃⌥L")) {
                        // come nel menu: uno dei due è scelto solo se l'aspetto di Pulsar è un Matte
                        RigaScelta(T("Tema", "Theme"), opzioni: PulsarTema.allCases.map { (id: $0.rawValue, titolo: $0.title) },
                                   valore: { foto ? (m.chiaro ? PulsarTema.whiteMatte : PulsarTema.darkMatte).rawValue : Self.temaScelto() }) { raw in
                            if let t = PulsarTema(rawValue: raw) { FinestraImpostazioni.shared.scegliTema(t) }
                        }
                        // fase 5: il cliente sceglie se il tema cambia anche macOS (di serie sì, come prima)
                        RigaInterruttore(T("Cambia anche macOS", "Also switch macOS"),
                                         sotto: T("Scuro o chiaro insieme al tema", "Dark or light along with the theme"),
                                         valore: { temaCambiaMacOS(Impostazioni.object(.temiCambiaMacOS)) }) { Impostazioni.set($0, .temiCambiaMacOS) }
                    }
                    GruppoImpostazioni(T("Altri aspetti di Pulsar", "Other Pulsar looks")) {
                        ForEach(AgentMode.allCases.filter { $0 != .notte && $0 != .bianco }, id: \.self) { a in
                            if modo == a {
                                RigaValore(a.title, valore: T("In uso", "In use"))
                            } else {
                                RigaTasto(a.title, tasto: T("Usa", "Use")) { FinestraImpostazioni.shared.agent?.mode = a }
                            }
                        }
                        if modo == .sfondo {
                            RigaScelta(T("Accento", "Accent"), opzioni: [(id: "sistema", titolo: T("Di sistema", "System")), (id: "sfondo", titolo: T("Dallo sfondo", "From wallpaper"))],
                                       valore: { Impostazioni.string(.wallAccent) == "sfondo" ? "sfondo" : "sistema" }) { id in
                                WallpaperTint.shared.useWallAccent = id == "sfondo"
                            }
                        }
                    }
                } }
            }
        }
    }

    /// La riga della pagina bloccata: dice ciò che il tema fa davvero in questa build. Sfondo e cartelle
    /// cambiano solo nella build personale (Personale/temi-autore.swift); la vendita cambia Pulsar e, se si vuole, macOS.
    private static var rigaBloccata: String {
        T("Dark Matte e White Matte per Pulsar e, se vuoi, anche per macOS.",
          "Dark Matte and White Matte for Pulsar and, if you want, macOS too.")
    }

    /// Il tema da segnare, come la spunta del menu: quello salvato se Pulsar è in Dark o White Matte, nessuno in Sfondo.
    private static func temaScelto() -> String {
        let modo = GhieraLook.shared.mode
        return modo == .notte || modo == .bianco ? PulsarTema.attuale.rawValue : ""
    }
}
