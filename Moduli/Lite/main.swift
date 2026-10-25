// Pulsar — interruttori di sistema nella menu bar (clone funzionale di One Switch, 100% API pubbliche)
// v1.1: icona custom + T("Barra pulita", "Clean menu bar") (nasconde le icone oltre il separatore, stile Hidden Bar).
// v1.4: sezione SCRIVANIA — 5 voci in cima, tutte le altre nel sottomenu "Altre n…".
// v1.5: SUONI TASTIERA — Alpaca o macchina da scrivere Hermes a ogni tasto e clic.
// v1.6: volumi separati tastiera/mouse con cursore, Pulsar sempre scura, 12 pacchetti meccanici.
// v1.7: Dark Mode riparata: spunta letta dal tema di sistema, permesso Automazione chiesto e segnalato.
// v1.8: AGENTE — Claude Code dal vivo: pillola nel notch, linguetta laterale e pannello (agente.swift).
// v1.9: Agente in stile macOS nativo, Agente con gli aspetti Dark Matte, White Matte e Sfondo (Scuro, Vetro e Vetro scuro sono usciti il 18/10/2026).
// 06/10/2026: GHIERA sul bordo sinistro: volume, mixer per app (tap audio) e timer (ghiera.swift).
// 06/10/2026: aspetto Notte (predefinito), colonna e pannello nella grammatica di Kinso (agente.swift).
// Compilazione: ./build.sh — nessuna dipendenza esterna, AppKit (+ SwiftUI per il pannello Agente).

import AppKit
import SwiftUI
import AVFoundation
import AudioToolbox
import ApplicationServices
import Intents

// MARK: - Shell helpers

// MARK: - Icone disegnate in codice (template: si adattano a barra chiara/scura)

enum Icons {
    /// Toggle a capsula minimale — l'icona principale di Pulsar.
    static func toggle() -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 13), flipped: false) { _ in
            let capsule = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 20.5, height: 11.5), xRadius: 5.75, yRadius: 5.75)
            capsule.lineWidth = 1.5
            NSColor.black.setStroke()
            capsule.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.5, y: 3, width: 7, height: 7)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - Suoni tastiera (v1.5)
// Un suono a ogni tasto e clic, da tutto il sistema. Pacchetti in Resources/sounds (fonti e licenze in sounds/FONTI.md).
// Serve il permesso Accessibilità: senza, macOS non consegna i tasti premuti nelle altre app.

final class KeySounds {
    /// Pacchetti disponibili: cartella in sounds/ → nome nel menu. I meccanici hanno tutti la stessa
    /// struttura (press/GENERIC_R0…R4, SPACE, ENTER, BACKSPACE + release/); la macchina da scrivere è a parte.
    static let mechanical: [(id: String, name: String)] = [
        ("alpaca", "Alpaca"), ("blackink", "Gateron Black Ink"), ("redink", "Gateron Red Ink"),
        ("mxblack", "Cherry MX Black"), ("mxbrown", "Cherry MX Brown"), ("holypanda", "Holy Panda"),
        ("cream", "NK Cream"), ("turquoise", "Turquoise Tealios"), ("topre", "Topre"),
        ("bluealps", "Blue Alps"), ("boxnavy", "Kailh Box Navy"), ("buckling", "IBM Buckling Spring"),
    ]
    static let typewriter = "typewriter"

    var enabled = Impostazioni.bool(.soundsEnabled) {
        didSet { Impostazioni.set(enabled, .soundsEnabled); enabled ? start() : stop() }
    }
    var pack = Impostazioni.string(.soundPack) ?? "alpaca" {
        didSet { Impostazioni.set(pack, .soundPack); column = 0 }
    }
    // due volumi separati: tastiera e mouse si livellano ognuno per conto suo
    var keyVolume: Float = (Impostazioni.object(.soundKeyVolume) as? NSNumber)?.floatValue ?? 1.0 {
        didSet { Impostazioni.set(keyVolume, .soundKeyVolume) }
    }
    var mouseVolume: Float = (Impostazioni.object(.soundMouseVolume) as? NSNumber)?.floatValue ?? 0.5 {
        didSet { Impostazioni.set(mouseVolume, .soundMouseVolume) }
    }
    var mouse = Impostazioni.object(.soundMouse) as? Bool ?? true {
        didSet { Impostazioni.set(mouse, .soundMouse) }
    }

    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var monitors: [Any] = []
    private var column = 0                 // battute sulla riga corrente (campanello della macchina da scrivere)
    private let bellColumn = 62
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    /// Per la goccia dei bordi (11/10/2026): stesso motore, stesso interruttore, volume del mouse.
    static weak var shared: KeySounds?

    /// La goccia quando un elemento si stacca da un bordo. Suona solo se i suoni di Pulsar sono accesi.
    func drop(gain: Float = 1) {
        guard enabled else { return }
        play("goccia/drop_\(Int.random(in: 0...2))", gain: gain * Float.random(in: 0.9...1.0), mouse: true)
    }

    init() {
        defer { KeySounds.shared = self }
        for _ in 0..<12 {
            let v = AVAudioPlayerNode()
            engine.attach(v)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            voices.append(v)
        }
        engine.mainMixerNode.outputVolume = 1
        // Più forte di tutto il resto (05/10/2026, l'autore: "il video lo sento di più di tastiera e mouse"):
        // i colpi hanno picchi alti ma pochissima sostanza (~-28 dB medi). Un limitatore di Apple davanti
        // all'uscita li alza di +12 dB e tiene i picchi sotto lo 0: più volume, niente distorsione.
        engine.attach(limiter)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)
        setLimiter()
        loadBuffers()
        if enabled { start() }
        // Cuffie Bluetooth, AirPods, casse: quando l'uscita cambia macOS ferma il motore audio.
        // Prima non lo riaccendeva nessuno e i suoni sparivano. Ora si riaggancia alla nuova uscita.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartWork?.cancel()
            let w = DispatchWorkItem { self?.audioQ.async { self?.restartEngine() } }   // mai sul filo principale
            self?.restartWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)   // gli avvisi arrivano a raffica
        }
    }

    private var restartWork: DispatchWorkItem?

    static let boostDB: Float = 6                        // il limitatore ora è solo una rete: il corpo lo dà saturate()
    static let drive: Float = 2                          // saturazione leggera; 3-4 = più forte e più compresso

    /// Saturazione morbida (tanh): porta il picco a 0,9 e dà sostanza al colpo. Con drive 2 il volume
    /// medio sale di ~11 dB rispetto al file, senza toccare l'attacco. Il limitatore da solo non bastava:
    /// i colpi sono quasi tutto picco, e alzare il picco non li fa sentire più forti.
    static func saturate(_ b: AVAudioPCMBuffer) {
        guard let ch = b.floatChannelData else { return }
        let n = Int(b.frameLength); var peak: Float = 0
        for c in 0..<Int(b.format.channelCount) { for i in 0..<n { peak = max(peak, abs(ch[c][i])) } }
        guard peak > 0.001 else { return }
        let k = drive, norm = 0.9 / tanh(k)
        for c in 0..<Int(b.format.channelCount) { for i in 0..<n { ch[c][i] = tanh(k * ch[c][i] / peak) * norm } }
    }
    static let mouseTrim: Float = 0.62                   // il mouse un gradino sotto la tastiera
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))

    private func setLimiter() {
        let au = limiter.audioUnit
        AudioUnitSetParameter(au, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, KeySounds.boostDB, 0)
        AudioUnitSetParameter(au, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(au, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.03, 0)
    }

    /// Riaggancia il mixer all'uscita attuale (il Bluetooth può avere un altro formato) e riparte.
    private func restartEngine() {
        engine.stop()
        let hw = engine.outputNode.outputFormat(forBus: 0)
        if hw.sampleRate > 0 {
            engine.disconnectNodeOutput(limiter)
            engine.connect(limiter, to: engine.outputNode, format: hw)
        }
        setLimiter()
        guard enabled else { return }
        engine.prepare()
        if (try? engine.start()) != nil { voices.forEach { $0.play() } }
    }

    var hasPermission: Bool { AXIsProcessTrusted() }

    // Fase 3: le stesse azioni della voce di menu e della pagina Suoni delle Impostazioni (un solo codice).
    /// Sceglie il pacchetto di suoni e suona un colpo di prova, così si sente subito com'è.
    func scegliPacchetto(_ id: String) {
        pack = id
        preview(mouse: false)
    }
    /// Imposta il volume di tastiera o mouse. Il colpo di prova lo suona chi chiama al rilascio del cursore (`preview`).
    func impostaVolume(mouse: Bool, _ v: Float) {
        if mouse { mouseVolume = v } else { keyVolume = v }
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func loadBuffers() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("sounds"),
              let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker where url.pathExtension == "wav" {
            guard let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil,
                  file.processingFormat.sampleRate == 48_000, file.processingFormat.channelCount == 1 else { continue }
            // chiave relativa: "alpaca/press/SPACE", "typewriter/key_03"
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if !rel.hasPrefix("goccia/") { KeySounds.saturate(buf) }   // più corpo, stesso scatto (05/10/2026); la goccia resta morbida
            buffers[(rel as NSString).deletingPathExtension] = buf
        }
    }

    private var permissionTimer: Timer?
    private var hadPermission = false

    private func start() {
        hadPermission = hasPermission
        // la finestra di sistema solo la prima volta; dopo si chiede dal menu (T("Concedi Accessibilità…", "Grant Accessibility…"))
        if !hadPermission && !Impostazioni.bool(.askedAccessibility) {
            Impostazioni.set(true, .askedAccessibility)
            requestPermission()
        }
        // Un monitor creato prima del permesso non riceve i tasti: appena il permesso arriva, lo ricreo.
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.enabled else { return }
            let now = self.hasPermission
            if now && !self.hadPermission { self.reinstallMonitors() }
            self.hadPermission = now
        }
        audioQ.async { [weak self] in            // anche l'avvio del motore: mai sul filo principale
            guard let self, !self.engine.isRunning else { return }
            try? self.engine.start()
            self.voices.forEach { $0.play() }
        }
        installMonitors()
    }

    private func reinstallMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        installMonitors()
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) { monitors.append(g) }
        // anche dentro Pulsar stessa (il menu), dove il monitor globale non arriva
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) { monitors.append(l) }
    }

    private func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        audioQ.async { [weak self] in self?.engine.pause() }
    }

    /// Un colpo di prova quando si sposta un cursore del volume.
    func preview(mouse isMouse: Bool) {
        if isMouse { play("mouse/down_0", gain: 0.9, mouse: true) }
        else if pack != KeySounds.typewriter { play("\(pack)/press/GENERIC_R0") }
        else { play("typewriter/key_05") }
    }

    // 06/10/2026: Pulsar si è bloccato tutto (ghiere, colonna, menu). Il filo principale aspettava per sempre dentro
    // AVAudioPlayerNode.play(), che a ogni ripartenza attende un giro del motore audio: se CoreAudio si incanta,
    // l'attesa non finisce. Ora l'audio vive su un filo suo, le voci restano sempre accese (il colpo nuovo sostituisce
    // il vecchio con .interrupts, niente stop/play) e se l'audio resta indietro i colpi in coda si scartano.
    private let audioQ = DispatchQueue(label: "pulsar.suoni", qos: .userInteractive)
    private let queuedLock = NSLock()
    private var queued = 0

    private func play(_ name: String, gain: Float = 1, mouse isMouse: Bool = false) {
        guard let buf = buffers[name] else { return }
        queuedLock.lock(); let busy = queued >= 4; if !busy { queued += 1 }; queuedLock.unlock()
        guard !busy else { return }              // l'audio è fermo: meglio un colpo in meno che un'app bloccata
        let v = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        let vol = min(1, gain * (isMouse ? mouseVolume * KeySounds.mouseTrim : keyVolume))
        audioQ.async { [weak self] in
            defer { self?.queuedLock.lock(); self?.queued -= 1; self?.queuedLock.unlock() }
            guard let self else { return }
            if !self.engine.isRunning { self.restartEngine(); guard self.engine.isRunning else { return } }   // rete di sicurezza
            v.volume = vol
            v.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !v.isPlaying { v.play() }
        }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .keyDown:
            if e.isARepeat { return }
            keyDown(e.keyCode)
        case .keyUp:
            if pack != KeySounds.typewriter { play("\(pack)/release/" + alpacaName(e.keyCode, release: true), gain: 0.55) }
        case .leftMouseDown, .rightMouseDown:
            // il mouse ha un clic suo, uguale per tutti i pacchetti: non si confonde con i tasti
            if mouse { play("mouse/down_\(Int.random(in: 0...2))", gain: Float.random(in: 0.85...1.0), mouse: true) }
        case .leftMouseUp:
            if mouse { play("mouse/up_\(Int.random(in: 0...2))", gain: 0.6, mouse: true) }
        default: break
        }
    }

    private func alpacaName(_ code: UInt16, release: Bool) -> String {
        switch code {
        case 49: return "SPACE"
        case 36, 76: return "ENTER"
        case 51, 117: return "BACKSPACE"
        default: return release ? "GENERIC" : "GENERIC_R\(Int.random(in: 0...4))"
        }
    }

    private func keyDown(_ code: UInt16) {
        let gain = Float.random(in: 0.8...1.0)   // nessun colpo uguale all'altro
        if pack != KeySounds.typewriter {
            play("\(pack)/press/" + alpacaName(code, release: false), gain: gain)
            return
        }
        switch code {
        case 36, 76:                               // invio: ritorno carrello, riga nuova
            play("typewriter/enter", gain: 0.95)
            column = 0
        case 49:
            play("typewriter/space", gain: gain)
            advance()
        case 51, 117:
            play("typewriter/key_single", gain: gain * 0.7)
            column = max(0, column - 1)
        default:
            play("typewriter/key_\(String(format: "%02d", Int.random(in: 0...11)))", gain: gain)
            advance()
        }
    }

    private func advance() {
        column += 1
        if column == bellColumn {                  // come sulla Hermes: il campanello avvisa che la riga sta finendo
            play("typewriter/bell_\(Bool.random() ? 4 : 5)", gain: 0.6)
        }
    }
}

/// 25/10: la larghezza del menu di Pulsar, quella del video di vendita (griglia 4x62 + azioni piccole a destra).
enum MenuMisure { static let larghezza: CGFloat = 430 }

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!      // icona principale con il menu
    private var separatorItem: NSStatusItem!   // separatore: si allarga per nascondere ciò che ha a sinistra
    private var mainMenu: NSMenu!              // tenuto da parte: assegnato all'item solo per il click sinistro
    private var caffeinate: Process?
    private var sounds: KeySounds!
    private let agent = AgentModule()
    private let isola = IslandModule()
    private lazy var griglia = GridModule(island: isola.model)
    private let dial = DialModule()
    private let temi = ModuloTemi()
    private let muta = MutaModule()          // 19/10: converte nel notch e mette a posto (Pulsar Complete)

    private let expandedLength: CGFloat = 2
    private let collapsedLength: CGFloat = 10_000 // macOS nasconde da solo ciò che non entra
    private var barraGuardia: BarraGuardia?
    private var barCollapsed = Impostazioni.bool(.barCollapsed) {
        didSet { Impostazioni.set(barCollapsed, .barCollapsed) }
    }
    // Registro persistente: ogni app di background vista almeno una volta (bundleID → nome, percorso).
    private var knownApps: [String: [String: String]] =
        (Impostazioni.dictionary(.knownApps) as? [String: [String: String]]) ?? [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Senza una posizione salvata macOS mette gli item nuovi a sinistra di tutti gli altri:
        // il separatore allora non ha nulla da nascondere. Al primo avvio (o se le preferenze
        // sono state pulite) li ancoro accanto alle icone di sistema; un ⌘-trascina li sovrascrive.
        // Il valore è la distanza in pt dal bordo destro dello schermo.
        let defaults = UserDefaults.standard   // chiavi di sistema costruite col nome dell'elemento: restano fuori da Chiave
        let seeds: [(String, Double)] = [("pulsar.main", 420), ("pulsar.separator", 421)]
        for (name, position) in seeds where defaults.object(forKey: "NSStatusItem Preferred Position \(name)") == nil {
            defaults.set(position, forKey: "NSStatusItem Preferred Position \(name)")
        }
        // 19/10: il separatore vale sempre Pulsar + 1. Con 420 e 440 Full immersion (424) finiva in mezzo e restava
        // sempre visibile; un ⌘-trascina della capsula sposta Pulsar e qui il separatore la segue al prossimo avvio.
        if let m = BarraOrdine.leggi("pulsar.main") { BarraOrdine.scrivi("pulsar.separator", m + 1) }
        makeStatusItems()
        applyBarState()
        barraGuardia = BarraGuardia(posizione: { [weak self] in self?.statusItem.button?.window?.frame },
                                    attiva: { [weak self] in self?.barCollapsed ?? false },
                                    ricrea: { [weak self] in self?.rebuildStatusItems() })
        barraGuardia?.avvia()
        sounds = KeySounds()
        SuonoBordi.goccia = { KeySounds.shared?.drop(gain: $0) }
        Theme.refreshAppearance()   // 11/10: menu e avvisi seguono l'aspetto di Pulsar (chiaro in White Matte e in Sfondo chiaro)
        // fase 2: i collegamenti fra i moduli si fanno subito (sono solo assegnazioni); a far partire i moduli
        // ci pensa il registro, secondo la licenza e le scelte dell'utente. Un modulo bloccato non parte e gli altri
        // non lo presumono partito. Ordine di avvio, com'era: Agente, Voce (12/10: ⌃⌥ detta, ⌃⌘ comanda, ⌃⇧ cerchia), Isola, Griglia, Ghiere.
        isola.dialStore = dial.store
        isola.model.dial = dial
        isola.agentStore = agent.store
        isola.model.openGrid = { [weak self] in self?.griglia.open() }
        isola.model.toggleTheme = { [weak self] in self?.agent.cycleMode() }
        collegaPagineLite()
        // fase 3: la pagina Generale cambia l'aspetto con gli stessi metodi del menu TEMA (setTema e setAgentLook)
        FinestraImpostazioni.shared.scegliAspetto = { [weak self] m in
            guard let self, !self.bloccato("temi") else { LicenzaViva.shared.chiedi(); return }
            if let t = PulsarTema.allCases.first(where: { $0.look == m }) { self.scegliTema(t) }
            else { self.agent.mode = m }
        }
        Anima.shared.boot()          // sempre: gestori di crash, collegamenti e cose da fare, anche con la Voce spenta o bloccata
        let registro = RegistroModuli.shared
        [agent, Anima.shared, isola, griglia, dial, temi, muta].forEach(registro.registra)
        registro.registra(ModuloRowline.shared)   // 19/10: Rowline dentro Complete
        registro.registra(ModuloLanciatori.shared)   // 24/10: i Lanciatori nella Lite (Moduli/Lanciatori)
        LicenzaViva.shared.onChange = {
            RegistroModuli.shared.applica(sbloccati: LicenzaViva.shared.sbloccati)
            NotificationCenter.default.post(name: .licenzaCambiata, object: nil)   // le pagine dei moduli passano da bloccate a sbloccate
        }
        // fase 3: al primo avvio della vendita i moduli a pagamento aspettano che il benvenuto si chiuda (nessun permesso prima della scelta)
        let personale = false
        let apreBenvenuto = BenvenutoLogica.deveAprire(visto: Impostazioni.bool(.benvenutoVisto), personale: personale)
        registro.inAttesa = BenvenutoLogica.moduliInAttesa(apreBenvenuto: apreBenvenuto)
        registro.applica(sbloccati: LicenzaViva.shared.sbloccati)
        LicenzaViva.shared.avvio()   // fase 2: inizio della prova al primo avvio, controllo Gumroad al massimo ogni 30 giorni
        Aggiornamenti.shared.avvia()   // fase 5, 3b: Sparkle, controllo automatico secondo l'interruttore della pagina Generale
        // fase 3: il benvenuto al primo avvio, solo nella vendita (nella build personale si apre con pulsar://benvenuto).
        // Alla chiusura (Fatto o la finestra chiusa) FinestraBenvenuto libera i moduli in attesa.
        if apreBenvenuto { DispatchQueue.main.async { FinestraBenvenuto.shared.apri() } }
        // solo la build dell'autore (build.sh): la versione in vendita non ha la dimostrazione

        // Registra ogni nuova app di background nel momento in cui appare.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerRunningApps()
        }
        registerRunningApps()
    }

    func applicationWillTerminate(_ notification: Notification) {
        caffeinate?.terminate()
        agent.store.stop()   // senza battito l'hook smette di aspettare la pillola
        dial.stop()          // chiude i tap: le app tornano a suonare da sole
    }

    // Ricostruisce il menu a ogni apertura, così gli stati sono sempre freschi.
    // 13/10, l'autore: "l'app è davvero lunga, rendila più carina": in cima i tasti rapidi, sotto una riga per sezione
    // con il suo sottomenu. Il menu completo si costruisce come prima e poi si ripiega (fold), così nessuna voce si perde.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === mainMenu else { return }
        menu.removeAllItems()
        let full = NSMenu()
        buildFullMenu(full)
        let quick = quickGridItem(menu)
        menu.addItem(quick)
        menu.addItem(.separator())
        fold(full, into: menu)
        // 25/10, l'autore: "stringi un po' il menu come nel video di vendita". Erano le voci lunghe (nomi delle app in
        // background) ad allargarlo: oltre 30 caratteri si accorciano, il nome intero resta nel suggerimento.
        for i in menu.items where i.view == nil && i.title.count > 30 {
            i.toolTip = i.toolTip ?? i.title
            i.title = String(i.title.prefix(29)).trimmingCharacters(in: .whitespaces) + "…"
        }
        // la griglia prende tutta la larghezza del menu: a destra, nello spazio che restava vuoto, le azioni piccole
        if let v = quick.view { v.frame.size.width = max(MenuMisure.larghezza, menu.size.width) }
    }

    /// Una riga per ogni sezione: l'intestazione (titolo in maiuscolo, disattivato) diventa una voce con sottomenu,
    /// le voci fino al separatore successivo finiscono dentro. Quello che non ha intestazione (Esci) resta in vista.
    private func fold(_ full: NSMenu, into menu: NSMenu) {
        var current: NSMenu?
        for item in full.items {
            full.removeItem(item)
            if item.isSeparatorItem { current = nil; continue }
            let t = item.title
            let isHeader = !item.isEnabled && item.action == nil && item.submenu == nil && item.view == nil
                && t == t.uppercased() && t.rangeOfCharacter(from: .letters) != nil
            if isHeader, t.uppercased().hasPrefix("AZIONI") || t.uppercased().hasPrefix("ACTIONS") {
                current = NSMenu()          // le azioni stanno in alto a destra, accanto ai tasti rapidi: qui no
                continue
            }
            if isHeader {
                let (name, symbol) = Self.sectionName(t)
                // tre gruppi separati da una riga: le app, poi le funzioni (Scrivania, Claude Code, Isola, Tema...), poi interruttori e azioni
                let u = t.uppercased()
                if (u.hasPrefix("SCRIVANIA") || u.hasPrefix("DESKTOP") || u.hasPrefix("INTERRUTTORI") || u.hasPrefix("SWITCHES")),
                   menu.items.last.map({ !$0.isSeparatorItem }) == true { menu.addItem(.separator()) }
                let s = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                s.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
                let sub = NSMenu()
                s.submenu = sub
                menu.addItem(s)
                current = sub
                continue
            }
            if let c = current { c.addItem(item) } else if item.keyEquivalent != "q" {   // Esci è in alto a destra
                menu.addItem(item)
            }
        }
    }

    /// Dal titolo maiuscolo della sezione al nome da riga, con il conteggio tra parentesi quando c'è.
    private static func sectionName(_ header: String) -> (String, String) {
        let count = header.range(of: "(").map { String(header[$0.lowerBound...]).replacingOccurrences(of: " / ", with: " su ") } ?? ""
        let h = header.uppercased()
        func n(_ it: String, _ en: String) -> String { (T(it, en) + (count.isEmpty ? "" : "  " + count.lowercased())) }
        if h.hasPrefix("APP IN BACKGROUND") || h.hasPrefix("BACKGROUND APPS") { return (n("App in background", "Background apps"), "square.stack.3d.up") }
        if h.hasPrefix("SCRIVANIA") || h.hasPrefix("DESKTOP") { return (n("Scrivania", "Desktop"), "folder") }
        if h.hasPrefix("TEMPO") || h.hasPrefix("WORK TIME") { return (T("Tempo al lavoro", "Work time"), "hourglass") }
        if h.hasPrefix("INTERRUTTORI") || h.hasPrefix("SWITCHES") { return (T("Altri interruttori", "More switches"), "switch.2") }
        if h.hasPrefix("AZIONI") || h.hasPrefix("ACTIONS") { return (T("Azioni", "Actions"), "bolt") }
        return (header.capitalized, "circle")
    }

    /// I tasti rapidi in cima al menu, come il Centro di Controllo: un clic cambia e chiude il menu.
    private func quickGridItem(_ menu: NSMenu) -> NSMenuItem {
        let close: (@escaping () -> Void) -> () -> Void = { act in { menu.cancelTracking(); DispatchQueue.main.async(execute: act) } }
        let tiles: [QuickTile] = [
            QuickTile(symbol: "wand.and.stars", title: T("Barra pulita", "Clean bar"), on: barCollapsed, act: close { [weak self] in self?.toggleBar() }),
            QuickTile(symbol: PulsarTema.attuale.chiaro ? "sun.max.fill" : "moon.fill", title: PulsarTema.attuale.title, on: true,
                      act: close { [weak self] in self?.bloccatoOppure("temi") { self?.agent.cycleMode() } }),
            QuickTile(symbol: "moon.zzz.fill", title: T("Non disturbare", "Do Not Disturb"), on: SystemStatus.shared.focus, act: close { [weak self] in self?.toggleDND() }),
            QuickTile(symbol: "cup.and.saucer.fill", title: "Keep Awake", on: caffeinate?.isRunning == true, act: close { [weak self] in self?.toggleKeepAwake() }),
            QuickTile(symbol: "speaker.slash.fill", title: T("Muto", "Mute"), on: SystemState.muted, act: close { [weak self] in self?.toggleMute() }),
        ]
        // 19/10 sera: Isola, Voce e Claude non stanno più qui ma nella fila "Pezzi di Pulsar", con tutti gli altri pezzi.
        // Stesso elenco e stessi interruttori del benvenuto e delle pagine delle Impostazioni (VoceBenvenuto.tutte).
        let moduli: [QuickTile] = VoceBenvenuto.tutte.map { v in
            QuickTile(symbol: v.pagina.simbolo, title: v.id == "agente" ? "Claude" : v.pagina.titolo, on: v.valore(),
                      act: close { v.cambia(!v.valore()) })
        }
        // 13/10, l'autore: "altre azioni o cose piccole potresti metterle in alto a destra, c'è uno spazio vuoto"
        let small: [QuickTile] = [
            QuickTile(symbol: "gearshape", title: T("Impostazioni…", "Settings…"), on: false, act: close { FinestraImpostazioni.shared.apri() }),
            QuickTile(symbol: "lock.fill", title: T("Blocca schermo", "Lock screen"), on: false, act: close { [weak self] in self?.lockScreen() }),
            QuickTile(symbol: "sparkles.tv", title: T("Salvaschermo", "Screen saver"), on: false, act: close { [weak self] in self?.startScreenSaver() }),
            QuickTile(symbol: "trash", title: T("Svuota Cestino…", "Empty Trash…"), on: false, act: close { [weak self] in self?.emptyTrash() }),
            QuickTile(symbol: "power", title: T("Esci da Pulsar", "Quit Pulsar"), on: false, act: close { NSApp.terminate(nil) }),
        ]
        let host = NSHostingView(rootView: QuickGrid(tiles: tiles, small: small, moduli: moduli))
        host.frame = NSRect(x: 0, y: 0, width: MenuMisure.larghezza, height: max(150, host.fittingSize.height))
        let item = NSMenuItem()
        item.view = host
        return item
    }

    // MARK: Moduli a pagamento (fase 2)

    private func bloccato(_ id: String) -> Bool { RegistroModuli.shared.bloccato(id) }

    /// Se il modulo è bloccato apre la finestra della licenza, altrimenti fa l'azione.
    private func bloccatoOppure(_ id: String, _ azione: () -> Void) {
        if bloccato(id) { LicenzaViva.shared.chiedi() } else { azione() }
    }

    private func buildFullMenu(_ menu: NSMenu) {

        registerRunningApps() // ogni app che si manifesta finisce nel registro persistente
        let running = runningAccessoryApps()
        let entries = knownApps.sorted {
            ($0.value["name"] ?? "").localizedCaseInsensitiveCompare($1.value["name"] ?? "") == .orderedAscending
        }
        if pulsarDemoMenu {
            menu.addItem(header(T("APP IN BACKGROUND (2 attive / 3)", "BACKGROUND APPS (2 running / 3)")))
            for (n, on) in [("Clipboard", true), ("Battery Monitor", true), ("Window Grid", false)] {
                let i = NSMenuItem(title: n, action: nil, keyEquivalent: ""); i.state = on ? .on : .off
                let ic = NSWorkspace.shared.icon(for: .application); ic.size = NSSize(width: 16, height: 16); i.image = ic
                menu.addItem(i)
            }
        } else {
        menu.addItem(header(T("APP IN BACKGROUND (\(running.count) attive / \(entries.count))", "BACKGROUND APPS (\(running.count) running / \(entries.count))")))
        }
        // 25/10, l'autore: "non serve che mostri tutte le attività in background, aggiungi un mostra tutto e riduci".
        // Ridotto si vedono solo quelle accese; le spente si nascondono e la riga in fondo le mostra senza chiudere il menu.
        var spente: [NSMenuItem] = []
        for (bundleID, info) in (pulsarDemoMenu ? [] : entries) {
            let isOn = running[bundleID] != nil
            let item = NSMenuItem(title: info["name"] ?? bundleID, action: #selector(toggleApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bundleID
            item.state = isOn ? .on : .off
            let icon: NSImage? = running[bundleID]?.bundleURL.map { IconeApp.shared.icona($0.path) } ?? running[bundleID]?.icon
                ?? info["path"].map { IconeApp.shared.icona($0) }
            if let icon = icon.flatMap({ $0.copy() as? NSImage }) {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            if !isOn { item.isHidden = !appTutte; spente.append(item) }
            menu.addItem(item)
        }
        if !spente.isEmpty {
            let riga = NSMenuItem()
            let vista = RigaMostraTutto(frame: NSRect(x: 0, y: 0, width: MenuMisure.larghezza, height: 24))
            let testo: () -> String = { [unowned self] in
                self.appTutte ? T("Riduci", "Show less") : T("Mostra tutte (\(spente.count) spente)", "Show all (\(spente.count) off)")
            }
            vista.testo = testo()
            vista.aperta = appTutte
            vista.azione = { [weak self, weak vista] in
                guard let self else { return }
                self.appTutte.toggle()
                spente.forEach { $0.isHidden = !self.appTutte }
                vista?.testo = testo(); vista?.aperta = self.appTutte
            }
            riga.view = vista
            menu.addItem(riga)
        }

        menu.addItem(.separator())
        let desk = desktopEntries()
        let limit = min(visibleDesktopCount, desk.count)
        if pulsarDemoMenu {
            menu.addItem(header(T("SCRIVANIA (5)", "DESKTOP (5)")))
            for n in ["Projects", "Inspiration", "Invoices", "Reading", "Screenshots"] {
                let i = NSMenuItem(title: n, action: nil, keyEquivalent: "")
                let ic = NSWorkspace.shared.icon(for: .folder); ic.size = NSSize(width: 16, height: 16); i.image = ic
                menu.addItem(i)
            }
        } else {
        menu.addItem(header(T("SCRIVANIA (\(desk.count))", "DESKTOP (\(desk.count))")))
        if desk.isEmpty {
            let none = NSMenuItem(title: T("Scrivania vuota", "Desktop is empty"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for url in desk.prefix(limit) { menu.addItem(desktopItem(url)) }
            if desk.count > limit {
                let more = NSMenuItem(title: T("Altre \(desk.count - limit)…", "\(desk.count - limit) more…"), action: nil, keyEquivalent: "")
                more.image = NSImage(systemSymbolName: "ellipsis.circle",
                                     accessibilityDescription: T("Altre cartelle", "More folders"))
                let sub = NSMenu()
                for url in desk { sub.addItem(desktopItem(url)) }   // qui ci sono tutte
                more.submenu = sub
                menu.addItem(more)
            }
        }
        }

        // fase 3: Claude Code, Isola, Voce, Rowline, Tema, Ghiere e Suoni vivono nelle pagine di Impostazioni (⌘,)
        // 11/10: la ripresa del reel la fa Pulsar (coreografia + registrazione dello schermo con solo Pulsar e lo sfondo)


        menu.addItem(.separator())
        menu.addItem(header(T("INTERRUTTORI", "SWITCHES")))
        menu.addItem(toggle("Dark Mode", symbol: "moon.fill", on: SystemState.darkMode, #selector(toggleDarkMode)))
        menu.addItem(toggle(T("Nascondi icone desktop", "Hide desktop icons"), symbol: "menubar.dock.rectangle", on: SystemState.desktopIconsHidden, #selector(toggleDesktopIcons)))
        menu.addItem(toggle(T("Mostra file nascosti", "Show hidden files"), symbol: "eye.fill", on: SystemState.hiddenFilesShown, #selector(toggleHiddenFiles)))
        menu.addItem(toggle("Keep Awake", symbol: "cup.and.saucer.fill", on: caffeinate?.isRunning == true, #selector(toggleKeepAwake)))
        menu.addItem(toggle(T("Muto", "Mute"), symbol: "speaker.slash.fill", on: SystemState.muted, #selector(toggleMute)))
        menu.addItem(toggle("Stage Manager", symbol: "squares.leading.rectangle", on: SystemState.stageManager, #selector(toggleStageManager)))
        menu.addItem(toggle(T("Non disturbare", "Do Not Disturb"), symbol: "moon.zzz.fill", on: false, #selector(toggleDND)))

        menu.addItem(.separator())
        menu.addItem(header(T("AZIONI", "ACTIONS")))
        menu.addItem(action(T("Salvaschermo", "Screen saver"), symbol: "sparkles.tv", #selector(startScreenSaver)))
        menu.addItem(action(T("Blocca schermo", "Lock screen"), symbol: "lock.fill", #selector(lockScreen)))
        menu.addItem(action(T("Svuota Cestino…", "Empty Trash…"), symbol: "trash.fill", #selector(emptyTrash)))

        // fase 2: la licenza. Fuori dalle sezioni (dopo un separatore il ripiego la lascia in vista), sotto il riassunto.
        menu.addItem(.separator())
        menu.addItem(action(T("Licenza…", "License…"), symbol: "key", #selector(apriLicenza)))
        let riassunto = NSMenuItem(title: LicenzaViva.shared.riassunto, action: nil, keyEquivalent: "")
        riassunto.isEnabled = false
        menu.addItem(riassunto)
        // fase 5, 3b: cerca subito una versione nuova (Sparkle), anche con il controllo automatico spento.
        // Solo se l'aggiornatore è partito (indirizzo e chiave validi nell'Info.plist): altrimenti la voce non farebbe niente.
        if Aggiornamenti.shared.attivo {
            menu.addItem(action(T("Cerca aggiornamenti…", "Check for Updates…"), symbol: "arrow.down.circle", #selector(cercaAggiornamenti)))
        }

        menu.addItem(.separator())
        // fase 3: le impostazioni dei moduli vivono nella finestra Impostazioni (⌘,), sopra Esci
        let impostazioni = action(T("Impostazioni…", "Settings…"), symbol: "gearshape", #selector(apriImpostazioni))
        impostazioni.keyEquivalent = ","
        menu.addItem(impostazioni)
        let quit = NSMenuItem(title: T("Esci da Pulsar", "Quit Pulsar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: Scrivania

    /// Quante voci mostrare al primo livello prima di finire in "Altre…".
    var visibleDesktopCount: Int {
        get { ScrivaniaConteggio.valore }
        set { ScrivaniaConteggio.valore = newValue }
    }

    /// Il contenuto visibile della scrivania: cartelle prima, poi il resto, in ordine alfabetico.
    /// Nessun file viene toccato — è solo una lista di scorciatoie.
    private func desktopEntries() -> [URL] {
        let fm = FileManager.default
        guard let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first,
              let items = try? fm.contentsOfDirectory(
                  at: desktop,
                  includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                  options: [.skipsHiddenFiles])
        else { return [] }

        func isDir(_ u: URL) -> Bool {
            (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        }
        return items.sorted { a, b in
            let da = isDir(a), db = isDir(b)
            if da != db { return da }                       // cartelle in cima
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent)
                == .orderedAscending
        }
    }

    private func desktopItem(_ url: URL) -> NSMenuItem {
        let name = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
            ?? url.deletingPathExtension().lastPathComponent
        let item = NSMenuItem(title: name, action: #selector(openDesktopItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        // icona vera del Finder: le cartelle colorate restano riconoscibili
        if let icon = IconeApp.shared.icona(url.path).copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        return item
    }

    @objc private func openDesktopItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: App in background

    /// Le app "accessory" in esecuzione (vivono solo nella menu bar, senza Dock), per bundle id.
    /// Escluse quelle di sistema (com.apple.*) e Pulsar stessa.
    private func runningAccessoryApps() -> [String: NSRunningApplication] {
        var out: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .accessory,
                  app != NSRunningApplication.current,
                  let id = app.bundleIdentifier,
                  !id.hasPrefix("com.apple.") else { continue }
            out[id] = app
        }
        return out
    }

    /// Aggiunge al registro persistente ogni app di background vista almeno una volta.
    private func registerRunningApps() {
        var changed = false
        for (id, app) in runningAccessoryApps() {
            let entry = ["name": app.localizedName ?? id,
                         "path": app.bundleURL?.path ?? ""]
            if knownApps[id] != entry { knownApps[id] = entry; changed = true }
        }
        if changed { Impostazioni.set(knownApps, .knownApps) }
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if let app = runningAccessoryApps()[bundleID] {
            app.terminate() // spegni (chiusura gentile)
        } else if let path = knownApps[bundleID]?["path"], !path.isEmpty,
                  FileManager.default.fileExists(atPath: path) {
            // riaccendi
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        } else {
            let alert = NSAlert()
            alert.messageText = T("Impossibile riavviare l'app", "Can't reopen the app")
            alert.informativeText = T("Il percorso registrato non esiste più. L'app verrà ri-registrata alla prossima esecuzione.", "The saved location no longer exists. The app will be registered again the next time it runs.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Click sull'icona

    @objc private func mainClicked() {
        let event = NSApp.currentEvent
        let isQuickToggle = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        if isQuickToggle {
            toggleBar()
        } else {
            // Trucco standard: assegna il menu, simula il click per aprirlo, poi lo stacca in menuDidClose.
            statusItem.menu = mainMenu
            statusItem.button?.performClick(nil)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil // altrimenti il menu intercetterebbe anche i click destri futuri
    }

    /// 19/10: la guardia sposta le due icone scrivendo le posizioni e ricreandole (macOS le rilegge solo alla nascita).
    private func rebuildStatusItems() {
        let m = BarraOrdine.leggi("pulsar.main") ?? 420
        NSStatusBar.system.removeStatusItem(separatorItem)
        NSStatusBar.system.removeStatusItem(statusItem)
        BarraOrdine.scrivi("pulsar.main", m)            // togliere un'icona può cancellarne la posizione salvata
        BarraOrdine.scrivi("pulsar.separator", m + 1)
        makeStatusItems()
        applyBarState()
    }

    private func makeStatusItems() {
        // Icona principale (creata per prima: resta più a destra).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "pulsar.main"
        statusItem.button?.image = Icons.toggle()
        mainMenu = NSMenu()
        mainMenu.delegate = self
        // Niente menu fisso: click sinistro = menu, click destro / ⌥-click = toggle rapido barra pulita.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(mainClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = T("Pulsar: click destro o ⌥-click: mostra/nascondi le icone", "Pulsar: right-click or ⌥-click to show or hide icons")

        // Item tecnico per la "barra pulita": invisibile, sta subito a sinistra dell'icona.
        // Quando si allarga a 10.000pt, macOS nasconde tutto ciò che gli sta a sinistra.
        separatorItem = NSStatusBar.system.statusItem(withLength: expandedLength)
        separatorItem.autosaveName = "pulsar.separator"
    }

    // MARK: Barra pulita

    @objc private func toggleBar() {
        barCollapsed.toggle()
        applyBarState()
    }
    /// Fase 3: la pagina Barra dei menu alterna la Barra pulita con lo stesso metodo del menu e dei riquadri della griglia.
    private func collegaPagineLite() {
        let f = FinestraImpostazioni.shared
        f.alternaBarraPulita = { [weak self] in self?.toggleBar() }
        // compito 5: le pagine dei moduli usano gli stessi moduli e lo stesso metodo del menu
        f.agent = agent; f.isola = isola; f.griglia = griglia; f.ghiere = dial; f.anima = Anima.shared; f.muta = muta
        f.scegliTema = { [weak self] t in self?.scegliTema(t) }
    }

    private func applyBarState() {
        separatorItem.length = barCollapsed ? collapsedLength : expandedLength
        // 14/10 sera: il separatore resta SEMPRE visibile. Nasconderlo a barra aperta (per togliere lo slot di 18 pt)
        // faceva perdere a macOS la sua posizione: riacceso rinasceva altrove e la Barra pulita non nascondeva più niente
        // (l'autore: "perché Pulsar non mi nasconde le icone?"). Meglio lo spazietto che la funzione rotta.
        separatorItem.isVisible = true
    }

    // MARK: Costruzione voci


    /// Le app in background spente si vedono solo dopo "Mostra tutte" (finché Pulsar resta aperta).
    var appTutte = false

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func toggle(_ title: String, symbol: String, on: Bool, _ sel: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func action(_ title: String, symbol: String, _ sel: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    @objc private func apriLicenza() { LicenzaViva.shared.chiedi() }
    @objc private func cercaAggiornamenti() { Aggiornamenti.shared.cercaOra() }
    @objc private func apriImpostazioni() { FinestraImpostazioni.shared.apri() }

    // MARK: Tempo al lavoro (tempo.swift)


    // MARK: Agente

    @objc private func toggleAgent() { agent.enabled.toggle() }
    @objc private func toggleIsola() { isola.enabled.toggle() }
    /// Dark Matte o White Matte: la voce TEMA del menu e le pagine Generale e Aspetto passano tutte da qui.
    private func scegliTema(_ t: PulsarTema) {
        guard !bloccato("temi") else { LicenzaViva.shared.chiedi(); return }
        Temi.scegli(t) { [weak self] in self?.agent.mode = $0 }
    }
    // MARK: Interruttori

    @objc private func toggleDarkMode() {
        // 06/10: prima si prova il comando e basta. Il controllo preventivo (AEDeterminePermission) poteva dire "no"
        // anche con l'interruttore acceso in Impostazioni, e l'avviso compariva senza motivo. Ora l'avviso esce solo
        // se macOS rifiuta davvero il comando (-1743), dopo aver chiesto il permesso una volta.
        let script = #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        var err = runAppleScript(script)
        if err == 0 { return }
        let status = automationAllowed("com.apple.systemevents")
        NSLog("Dark Mode: AppleScript %d, permesso %d", err, Int(status))
        if status == noErr { err = runAppleScript(script); if err == 0 { return } }
        if err != -1743 && err != -1744 && status == noErr { NSLog("Dark Mode: AppleScript error %d", err); return }
        // permesso negato o mai concesso: lo diciamo e apriamo il pannello giusto
        let alert = NSAlert()
        alert.messageText = T("Pulsar ha bisogno del permesso Automazione", "Pulsar needs the Automation permission")
        alert.informativeText = T("Per cambiare la Dark Mode, consenti a Pulsar di controllare System Events in Impostazioni di Sistema, Privacy e sicurezza, Automazione.", "To switch Dark Mode, allow Pulsar to control System Events in System Settings, Privacy & Security, Automation.")
        alert.addButton(withTitle: T("Apri Impostazioni", "Open Settings"))
        alert.addButton(withTitle: T("Annulla", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleDesktopIcons() {
        let hidden = SystemState.desktopIconsHidden
        shell("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "true" : "false"])
        shell("/usr/bin/killall", ["Finder"])
    }

    @objc private func toggleHiddenFiles() {
        let shown = SystemState.hiddenFilesShown
        shell("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", shown ? "false" : "true"])
        shell("/usr/bin/killall", ["Finder"])
    }

    @objc private func toggleKeepAwake() {
        if let p = caffeinate, p.isRunning {
            p.terminate()
            caffeinate = nil
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-di"] // display + idle sleep bloccati finché Pulsar non lo spegne
            try? p.run()
            caffeinate = p
        }
    }

    @objc private func toggleMute() {
        shell("/usr/bin/osascript", ["-e", "set volume output muted (not (output muted of (get volume settings)))"])
    }

    @objc private func toggleStageManager() {
        let on = SystemState.stageManager
        shell("/usr/bin/defaults", ["write", "com.apple.WindowManager", "GloballyEnabled", "-bool", on ? "false" : "true"])
    }

    @objc private func toggleDND() {
        // Apple non espone un'API pubblica per il Focus: si passa da Comandi Rapidi.
        // Serve un comando rapido chiamato "Pulsar DND" con l'azione "Imposta full immersion".
        DispatchQueue.global().async {
            let (status, _) = shell("/usr/bin/shortcuts", ["run", "Pulsar DND"])
            if status != 0 {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = T("Comando rapido mancante", "Shortcut missing")
                    alert.informativeText = T("Crea in Comandi Rapidi un comando chiamato \"Pulsar DND\" con l'azione «Imposta full immersion» (attiva/disattiva Non disturbare), poi riprova.", "In Shortcuts, create a shortcut named \"Pulsar DND\" with the action Set Focus (toggle Do Not Disturb), then try again.")
                    alert.runModal()
                }
            }
        }
    }

    // MARK: Azioni

    @objc private func startScreenSaver() {
        shell("/usr/bin/open", ["-b", "com.apple.ScreenSaver.Engine"])
    }

    @objc private func lockScreen() {
        let cgSession = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: cgSession) {
            shell(cgSession, ["-suspend"])
        } else {
            // Spegne il display: con "Richiedi password subito" equivale al blocco.
            shell("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    @objc private func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = T("Svuotare il Cestino?", "Empty the Trash?")
        alert.informativeText = T("L'operazione non si può annullare.", "You can't undo this.")
        alert.addButton(withTitle: T("Svuota", "Empty"))
        alert.addButton(withTitle: T("Annulla", "Cancel"))
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runAppleScript(#"tell application "Finder" to empty trash"#)
    }
}

extension IslandModule {
    /// Il LED sempre acceso nel notch: la voce di menu ISOLA e la pagina Isola delle Impostazioni passano da qui.
    func impostaLED(_ acceso: Bool) { AmbientSource.enabled = acceso; force(nil) }
}

// MARK: - Avvio

// 13/10: Pulsar lanciato da sé stesso solo per disegnare icone con lo stile di macOS appena scelto (temi.swift, IconeApp)
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--icone" { rendiIcone(Array(CommandLine.arguments.dropFirst(2))) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // solo menu bar, niente Dock
app.run()


/// 25/10: la riga "Mostra tutte / Riduci" delle app in background. È una vista e non una voce normale perché il clic
/// non deve chiudere il menu: si aprono le righe nascoste e si resta lì.
final class RigaMostraTutto: NSView {
    var testo = "" { didSet { needsDisplay = true } }
    var aperta = false { didSet { needsDisplay = true } }
    var azione: (() -> Void)?
    private var sopra = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { sopra = true }
    override func mouseExited(with e: NSEvent) { sopra = false }
    override func mouseUp(with e: NSEvent) { azione?() }

    override func draw(_ r: NSRect) {
        if sopra {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let col = NSColor.secondaryLabelColor
        if let im = NSImage(systemSymbolName: aperta ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular)) {
            let t = im.tinted(col)
            t.draw(in: NSRect(x: 32 - t.size.width / 2, y: (bounds.height - t.size.height) / 2, width: t.size.width, height: t.size.height))
        }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: col]
        let str = NSAttributedString(string: testo, attributes: a)
        str.draw(at: NSPoint(x: 46, y: (bounds.height - str.size().height) / 2))
    }
}

private extension NSImage {
    func tinted(_ c: NSColor) -> NSImage {
        let im = NSImage(size: size, flipped: false) { r in
            self.draw(in: r); c.set(); r.fill(using: .sourceAtop); return true
        }
        return im
    }
}
