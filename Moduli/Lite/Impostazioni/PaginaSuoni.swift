// Pagina Suoni: i suoni della tastiera e del mouse. Ogni controllo chiama lo stesso codice della voce di menu di prima:
// interruttore (KeySounds.enabled), Concedi Accessibilità (requestPermission), scelta del suono (scegliPacchetto, con colpo
// di prova), cursori (impostaVolume al trascinamento, colpo di prova al rilascio), Anche il mouse (KeySounds.mouse).
// I valori si leggono dall'istanza viva (KeySounds.shared); nelle foto, dove l'app non è partita, dalle stesse chiavi.
import SwiftUI
import AppKit

struct PaginaSuoni: View {
    @Environment(\.matte) private var m

    private static var s: KeySounds? { KeySounds.shared }
    private static var acceso: Bool { s?.enabled ?? Impostazioni.bool(.soundsEnabled) }
    private static var pacchetto: String { s?.pack ?? Impostazioni.string(.soundPack) ?? "alpaca" }
    private static var voceMouse: Bool { s?.mouse ?? (Impostazioni.object(.soundMouse) as? Bool ?? true) }
    private static var volumeTasti: Double {
        Double(s?.keyVolume ?? (Impostazioni.object(.soundKeyVolume) as? NSNumber)?.floatValue ?? 1.0)
    }
    private static var volumeMouse: Double {
        Double(s?.mouseVolume ?? (Impostazioni.object(.soundMouseVolume) as? NSNumber)?.floatValue ?? 0.5)
    }

    var body: some View {
        let suoni: [(id: String, titolo: String)] =
            KeySounds.mechanical.map { (id: $0.id, titolo: $0.name) } + [(id: KeySounds.typewriter, titolo: T("Macchina da scrivere", "Typewriter"))]
        PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.suoni.titolo) {
            GruppoImpostazioni(T("Tastiera", "Keyboard")) {
                RigaInterruttore(T("Suoni tastiera", "Keyboard sounds"), valore: { Self.acceso }) { Self.s?.enabled = $0 }
                // come nel menu: solo se i suoni sono accesi e manca il permesso
                if Self.acceso && !(Self.s?.hasPermission ?? AXIsProcessTrusted()) {
                    RigaTasto(T("Accessibilità", "Accessibility"), tasto: T("Concedi Accessibilità…", "Grant Accessibility…"), principale: true) {
                        Self.s?.requestPermission()
                    }
                }
                RigaSceltaMolte(T("Suono", "Sound"), opzioni: suoni, valore: { Self.pacchetto }) { Self.s?.scegliPacchetto($0) }
                RigaCursore(T("Tastiera", "Keyboard"), simbolo: "keyboard",
                            valore: { Self.volumeTasti },
                            cambia: { Self.s?.impostaVolume(mouse: false, Float($0)) },
                            rilascio: { Self.s?.preview(mouse: false) })
            }
            GruppoImpostazioni(T("Mouse", "Mouse")) {
                RigaInterruttore(T("Anche il mouse", "Mouse too"), valore: { Self.voceMouse }) { Self.s?.mouse = $0 }
                if Self.voceMouse {
                    RigaCursore("Mouse", simbolo: "computermouse",
                                valore: { Self.volumeMouse },
                                cambia: { Self.s?.impostaVolume(mouse: true, Float($0)) },
                                rilascio: { Self.s?.preview(mouse: true) })
                }
            }
        } }
    }
}
