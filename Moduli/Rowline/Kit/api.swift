// Rowline dentro Pulsar (19/10/2026). l'autore: Rowline entra in Pulsar Complete, non si vende da sola.
// Questi file sono quelli dell'app Rowline (Apps/rowline), compilati come libreria a parte (modulo RowlineKit):
// così i loro nomi (Motore, Pannello, Barra, T...) non si scontrano con quelli di Pulsar. Pulsar vede solo
// quello che c'è qui sotto, segnato `public`. Niente icona nella barra dei menu: Rowline si apre dal menu di Pulsar,
// con ⌃⌥⌘F o dalla tessera dell'Isola.
import AppKit

/// Dove Rowline salva le sue scelte e dove legge il tema di Pulsar. Le chiavi di Rowline ("acceso", "griglia", "tasti"...)
/// si scontrerebbero con quelle di Pulsar, quindi stanno in un archivio loro: <id di Pulsar>.rowline.
enum Archivio {
    static let id = Bundle.main.bundleIdentifier ?? "pulsar"
    static let d: UserDefaults = UserDefaults(suiteName: id + ".rowline") ?? .standard
    static let notificaComando = Notification.Name(id + ".rowline.comando")
    static let notificaFila = Notification.Name(id + ".rowline.fila")
    static let sempreLibere: Set<String> = [id]
    /// Il tasto Impostazioni del pannello: Pulsar ci mette l'apertura della pagina di Rowline.
    static var apriImpostazioni: (() -> Void)?
    /// La cartella dati di Pulsar (tema.json): la imposta Pulsar prima di avviare.
    static var cartellaPulsar = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulsar")

    /// Prima volta dentro Pulsar: si portano le scelte dell'app Rowline (identificativo rimasto local.author.fila).
    static func portaDaRowline() {
    }
}

public enum RowlineKit {
    private static var avviato = false
    private static var segnale: DispatchSourceSignal?

    /// Accende Rowline: la fila, le scorciatoie, il gesto, la barra in basso, il foglio. Ripeterla non fa danni.
    public static func avvia(cartellaPulsar: URL) {
        Archivio.cartellaPulsar = cartellaPulsar
        Tinta.shared.leggi()
        guard !avviato else { Motore.shared.acceso = true; return }
        avviato = true
        Archivio.portaDaRowline()
        Motore.shared.avvia()
        Tasti.shared.registra()
        Gesto.shared.avvia()
        Barra.shared.avvia()
        Foglio.shared.avvia()
        // chiusa da fuori (pkill, build.sh, logout): prima di uscire rimette in vista le finestre parcheggiate
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Motore.shared.libera()
        }
        signal(SIGTERM, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        s.setEventHandler { Motore.shared.libera(); exit(0) }
        s.resume()
        segnale = s
    }

    /// Spegne Rowline senza toccare le scelte salvate: le finestre tornano tutte in vista, le scorciatoie tacciono.
    public static func ferma() {
        guard avviato else { return }
        Motore.shared.libera()
        Tasti.shared.sospendi()
        Gesto.shared.ferma()
        Pannello.shared.chiudi()
        Motore.shared.sospesa = true
        Motore.shared.adotta()              // svuota la mappa: la barra in basso e la tessera dell'Isola si spengono
    }

    /// Riaccende dopo `ferma()`.
    public static func riprendi() {
        guard avviato else { return }
        Motore.shared.sospesa = false
        Tasti.shared.registra()
        Gesto.shared.avvia()
        if Motore.shared.acceso { Motore.shared.adotta() }
    }

    public static func apriPannello() { Pannello.shared.apri() }
    /// Cosa fa il tasto Impostazioni del pannello (lo decide Pulsar).
    public static func quandoImpostazioni(_ f: @escaping () -> Void) { Archivio.apriImpostazioni = f }
    public static func riordina() { Motore.shared.adotta() }
    /// La fila sta lavorando (l'interruttore di Rowline, quello del suo pannello).
    public static var inFila: Bool {
        get { Motore.shared.acceso }
        set { Motore.shared.acceso = newValue }
    }
    public static var haPermesso: Bool { AXIsProcessTrusted() }
}
