// Barra pulita quando registri (16/11/2026).
// l'autore, dopo macOS 27: la freccia « di sistema nasconde già le icone in più, la Barra pulita fissa le dava fastidio.
// Scelta sua: "Solo quando registri". La barra si pulisce da sola mentre lo schermo è registrato o condiviso e torna
// com'era quando la registrazione finisce. Il resto del tempo Pulsar non tocca la barra e la freccia « fa il suo lavoro.
//
// Come si capisce che si sta registrando (misurato il 16/11 con `screencapture -v`): durante la registrazione il
// Window Server apre due finestre "StatusIndicator" (l'indicatore in alto a destra); finita, spariscono.
// Il nome della finestra non cambia con la lingua. Non serve nessun permesso per leggerlo.
// Dedotto, non provato: la stessa finestra compare anche col solo microfono acceso (chiamate). Va bene così:
// pulire la barra durante una chiamata non disturba.
import AppKit

enum BarraRegistrazione {
    /// L'interruttore "Barra pulita quando registri" (spento se mancante).
    static var acceso: Bool {
        get { Impostazioni.bool(.barraQuandoRegistri) }
        set { Impostazioni.set(newValue, .barraQuandoRegistri) }
    }

    /// C'è l'indicatore di registrazione di macOS sullo schermo?
    static func inCorso() -> Bool {
        let l = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        return l.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Window Server" &&
            ($0[kCGWindowName as String] as? String) == "StatusIndicator"
        }
    }
}
