// Il Terminale del notch (07/11/2026, dal reel di ZincWolf Island, l'autore: "SwiftTerm dentro Pulsar").
// ⌃⌥Invio fa scendere dal notch un terminale vero (la tua shell, colori, Claude Code dentro); di nuovo ⌃⌥Invio,
// o un clic fuori, lo fa risalire. La shell resta viva fra un'apertura e l'altra: si ritrova quello che c'era.
// Il terminale è SwiftTerm 1.20 (Vendor/SwiftTerm, MIT). Spento di serie, si accende dal menu, dal benvenuto o dalla
// pagina Sviluppo. Nessun permesso: la scorciatoia è Carbon come quella della Griglia.
import AppKit
import Carbon.HIToolbox
import SwiftTerm

final class ModuloTerminale: NSObject, ModuloPulsar {
    static let shared = ModuloTerminale()
    var id: String { "terminale" }
    var nome: String { T("Terminale", "Terminal") }
    var prodotto: Prodotto { .agent }
    var permessi: [Permesso] { [] }
    var acceso: Bool {
        get { Impostazioni.bool(.terminaleAcceso) }
        set { Impostazioni.set(newValue, .terminaleAcceso); RegistroModuli.shared.riapplica() }
    }
    private(set) var inEsecuzione = false

    private var pannello: PannelloTerminale?
    private var vista: LocalProcessTerminalView?
    private var tasto: EventHotKeyRef?
    private var gestore: EventHandlerRef?
    private var prima: NSRunningApplication?
    private var aperto = false
    private var osservatore: NSObjectProtocol?

    func avvia() {
        inEsecuzione = true
        registraTasto()
    }

    func ferma() {
        inEsecuzione = false
        if let t = tasto { UnregisterEventHotKey(t); tasto = nil }
        chiudi(riattiva: false)
        if let o = osservatore { NotificationCenter.default.removeObserver(o); osservatore = nil }
        vista?.terminate(); vista = nil
        pannello?.orderOut(nil); pannello = nil
    }

    func toggle() { aperto ? chiudi(riattiva: true) : apri() }

    /// Apre il terminale; con `cartella` ci scrive `cd` (dalla barra di sviluppo).
    func apri(cartella: String? = nil) {
        guard inEsecuzione else { return }
        // shell nuova: parte già nella cartella. Un `cd` scritto mentre la shell si carica usciva mescolato al primo prompt.
        let nuova = pannello == nil
        let p = pannello ?? creaPannello(cartella: cartella)
        if !aperto {
            prima = NSWorkspace.shared.frontmostApplication
            aperto = true
            let (su, giu) = cornici()
            p.setFrame(su, display: false)
            p.alphaValue = 0
            NSApp.activate(ignoringOtherApps: true)
            p.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.22
                c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                p.animator().setFrame(giu, display: true)
                p.animator().alphaValue = 1
            }
        }
        if let v = vista { p.makeFirstResponder(v) }
        if let c = cartella, !nuova {
            let q = "'" + c.replacingOccurrences(of: "'", with: "'\\''") + "'"
            vista?.send(txt: "cd \(q)\r")
        }
    }

    func chiudi(riattiva: Bool) {
        guard aperto, let p = pannello else { return }
        aperto = false
        let (su, _) = cornici()
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.16
            p.animator().setFrame(su, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
        if riattiva, let a = prima, a.bundleIdentifier != Bundle.main.bundleIdentifier { a.activate() }
    }

    // MARK: finestra

    /// Il riquadro aperto (sotto il notch, centrato, largo 60% fino a 900 pt) e quello di partenza: stessa misura, 60 pt più su.
    /// 07/11: prima partiva schiacciato nel notch (200 pt) e si allargava. A ogni larghezza di passaggio la shell riceveva
    /// un cambio di colonne e ridisegnava il prompt: restava una scala di righe tagliate. La misura ora non cambia mai.
    private func cornici() -> (NSRect, NSRect) {
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = s.frame
        let w = min(900, (f.width * 0.6).rounded()), h: CGFloat = min(460, (f.height * 0.5).rounded())
        let x = f.midX - w / 2
        let aperto = NSRect(x: x, y: f.maxY - h, width: w, height: h)
        return (aperto.offsetBy(dx: 0, dy: 60), aperto)
    }

    private func creaPannello(cartella: String? = nil) -> PannelloTerminale {
        let p = PannelloTerminale()
        let fondo = NSView()
        fondo.wantsLayer = true
        fondo.layer?.backgroundColor = NSColor.black.cgColor
        fondo.layer?.cornerRadius = 20
        fondo.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // solo gli angoli in basso: in alto si attacca al notch
        p.contentView = fondo

        let v = LocalProcessTerminalView(frame: .zero)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        v.nativeBackgroundColor = .black
        v.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        v.caretColor = NSColor(red: 0x8F / 255, green: 0xC7 / 255, blue: 0xFF / 255, alpha: 1)   // l'azzurro di Dark Matte
        // ⌥ resta ⌥: sulla tastiera italiana serve per @ # [ ] { } ~. Con optionAsMetaKey (di serie in SwiftTerm) sparirebbero.
        v.optionAsMetaKey = false
        v.processDelegate = self
        fondo.addSubview(v)
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let sopra = max(s.safeAreaInsets.top, 24) + 6
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: fondo.topAnchor, constant: sopra),
            v.leadingAnchor.constraint(equalTo: fondo.leadingAnchor, constant: 14),
            v.trailingAnchor.constraint(equalTo: fondo.trailingAnchor, constant: -10),
            v.bottomAnchor.constraint(equalTo: fondo.bottomAnchor, constant: -12),
        ])
        avviaShell(v, cartella: cartella)
        vista = v
        pannello = p
        osservatore = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            self?.chiudi(riattiva: false)    // un clic fuori: risale, e l'app cliccata resta davanti
        }
        return p
    }

    /// La shell dell'utente come shell di login (legge .zprofile: PATH di Homebrew, nvm, claude), nella cartella Inizio.
    private func avviaShell(_ v: LocalProcessTerminalView, cartella: String?) {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Pulsar"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }      // Pulsar parte da launchd senza LANG: senza UTF-8 gli accenti si rompono
        let nome = "-" + (shell as NSString).lastPathComponent      // il trattino davanti = shell di login
        v.startProcess(executable: shell, args: [], environment: env.map { "\($0.key)=\($0.value)" }, execName: nome,
                       currentDirectory: cartella ?? FileManager.default.homeDirectoryForCurrentUser.path)
    }

    // MARK: scorciatoia ⌃⌥Invio (Carbon, nessun permesso)

    private func registraTasto() {
        if gestore == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, ud in
                var hk = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                guard hk.signature == OSType(0x50554C54) else { return OSStatus(eventNotHandledErr) }   // "PULT"
                guard let ud else { return noErr }
                let me = Unmanaged<ModuloTerminale>.fromOpaque(ud).takeUnretainedValue()
                DispatchQueue.main.async { me.toggle() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &gestore)
        }
        let id = EventHotKeyID(signature: OSType(0x50554C54), id: 1)
        RegisterEventHotKey(UInt32(kVK_Return), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &tasto)
    }
}

extension ModuloTerminale: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    /// `exit` nella shell: il terminale risale e alla prossima apertura riparte una shell nuova.
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.chiudi(riattiva: true)
            if let o = self.osservatore { NotificationCenter.default.removeObserver(o) }
            self.vista = nil
            let p = self.pannello; self.pannello = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { p?.orderOut(nil) }
        }
    }
}

final class PannelloTerminale: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)   // sopra la barra, sotto la Griglia (+4)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { true }
}
