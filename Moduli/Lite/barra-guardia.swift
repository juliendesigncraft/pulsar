// Guardia della Barra pulita (19/10/2026).
// l'autore: "ogni tanto mi trovo icone nuove a destra di quelle di Pulsar quando è attiva la funzione di pulizia della barra".
// macOS ordina le icone con un numero per ognuna ("NSStatusItem Preferred Position", distanza dal bordo destro).
// Due guasti misurati il 19/10:
//  1. separatore a 440 e Pulsar a 420: Full immersion (424) finiva in mezzo e restava sempre visibile.
//     Rimedio: il separatore vale sempre Pulsar + 1, nessuno ci sta più in mezzo.
//  2. un'app che parte dopo Pulsar (o con una posizione sua salvata) si mette a destra della capsula.
//     Pulsar non può spostare le icone degli altri (solo l'utente, col ⌘-trascina), ma può spostare le sue:
//     se trova l'icona di un'app non Apple a destra, ricrea le sue due icone più a destra e l'intrusa finisce nascosta.
// Chi è di chi lo dice l'Accessibilità (AXExtrasMenuBar di ogni app): su macOS 26 le finestre delle icone
// risultano tutte del Centro di Controllo. Senza Accessibilità la guardia non fa niente.
import AppKit

enum BarraOrdine {
    static let chiave = "NSStatusItem Preferred Position "

    /// Pura: il nuovo numero di Pulsar per stare a destra dell'intrusa. Numero più alto = più a sinistra.
    /// `bordo` = bordo destro dello schermo, `destraIntrusa` = bordo destro dell'icona estranea, `attuale` = numero di oggi.
    /// Sempre più piccolo di quello di oggi; ogni tentativo scende di altri 30 (la stima dalla posizione sbaglia di qualche decina).
    static func posizioneOltre(bordo: CGFloat, destraIntrusa: CGFloat, attuale: Double, tentativo: Int) -> Double {
        let stima = Double(bordo - destraIntrusa)      // il numero è circa la distanza del bordo destro dell'icona dal bordo dello schermo
        return max(10, min(attuale - 8, stima - 14 - Double(tentativo) * 30)).rounded()
    }

    static func leggi(_ nome: String) -> Double? {
        UserDefaults.standard.object(forKey: chiave + nome) as? Double
    }

    static func scrivi(_ nome: String, _ v: Double) {
        UserDefaults.standard.set(v, forKey: chiave + nome)
    }
}

/// Le icone della barra dei menu delle altre app, con chi le possiede.
struct IconaBarra { let x: CGFloat; let larghezza: CGFloat; let app: String }

enum BarraLettura {
    static func icone() -> [IconaBarra] {
        guard AXIsProcessTrusted() else { return [] }
        var out: [IconaBarra] = []
        let mio = Bundle.main.bundleIdentifier ?? ""
        for app in NSWorkspace.shared.runningApplications {
            let id = app.bundleIdentifier ?? ""
            if id == mio { continue }
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.2)       // un'app bloccata non ferma la guardia
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { continue }
            var figli: CFTypeRef?
            AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &figli)
            for k in (figli as? [AXUIElement]) ?? [] {
                var p: CFTypeRef?, s: CFTypeRef?
                AXUIElementCopyAttributeValue(k, kAXPositionAttribute as CFString, &p)
                AXUIElementCopyAttributeValue(k, kAXSizeAttribute as CFString, &s)
                var pt = CGPoint.zero, sz = CGSize.zero
                if let p { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
                if let s { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
                guard sz.width > 0, pt.x > 0 else { continue }   // quelle già nascoste stanno fuori schermo
                out.append(IconaBarra(x: pt.x, larghezza: sz.width, app: id))
            }
        }
        return out
    }
}

/// Controlla ogni pochi secondi, e quando parte un'app, che a destra di Pulsar non ci siano icone di altre app.
final class BarraGuardia {
    private var timer: Timer?
    private var ultimo = Date.distantPast
    private var tentativi = 0
    private let posizioneMia: () -> NSRect?      // la cornice dell'icona di Pulsar sullo schermo
    private let attiva: () -> Bool               // la Barra pulita è accesa?
    private let ricrea: () -> Void               // ricrea le due icone (rilegge le posizioni salvate)

    init(posizione: @escaping () -> NSRect?, attiva: @escaping () -> Bool, ricrea: @escaping () -> Void) {
        self.posizioneMia = posizione
        self.attiva = attiva
        self.ricrea = ricrea
    }

    func avvia() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.controlla() }
        timer?.tolerance = 2
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.controlla() }   // le icone nascono un attimo dopo l'app
        }
    }

    func controlla() {
        guard attiva(), Date().timeIntervalSince(ultimo) > 8, let mia = posizioneMia(),
              let schermo = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: mia.midX, y: mia.midY)) }) else { return }
        let intruse = BarraLettura.icone().filter {
            !$0.app.hasPrefix("com.apple.") && $0.x > mia.maxX - 2 && $0.x < schermo.frame.maxX
        }
        guard let ultima = intruse.max(by: { $0.x < $1.x }) else { tentativi = 0; return }
        guard tentativi < 4 else { return }              // dopo 4 tentativi si lascia stare: niente giri infiniti
        tentativi += 1
        ultimo = Date()
        let nuovo = BarraOrdine.posizioneOltre(bordo: schermo.frame.maxX, destraIntrusa: ultima.x + ultima.larghezza,
                                               attuale: BarraOrdine.leggi("pulsar.main") ?? 420, tentativo: tentativi - 1)
        BarraOrdine.scrivi("pulsar.main", nuovo)
        BarraOrdine.scrivi("pulsar.separator", nuovo + 1)
        NSLog("Pulsar barra: icona di \(ultima.app) a destra della capsula, Pulsar passa a \(nuovo)")
        ricrea()
    }
}
