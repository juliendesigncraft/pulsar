// La stella dell'Anima (12/10/2026): al posto dei pulsanti a sinistra del notch, un'icona personale sempre in moto
// (la stella a quattro punte dell'immagine dell'autore) che ogni tanto diventa la scritta "Ciao l'autore" e poi torna stella.
// I pulsanti che c'erano (impostazioni, griglia, volume, luce, tema, AirDrop) ora stanno nella tessera Controlli.
// Qui anche la voce. Build dell'autore: frasi fisse fatte con ElevenLabs (voce Aurora) in voce/*.mp3; risposte intere
// a voce solo se l'autore mette la sua chiave nel Portachiavi (servizio "Pulsar ElevenLabs"), mai scritta nel codice.
// Vendita (18/10): le frasi fisse le dice la sintesi vocale di macOS nella lingua di Pulsar; le risposte non si leggono.
import SwiftUI
import AppKit
import AVFoundation

// MARK: - La voce

enum AnimaVoce {
    static var enabled: Bool {
        get { Impostazioni.object(.animaParla) as? Bool ?? true }
        set { Impostazioni.set(newValue, .animaParla) }
    }
    private static let sintesi = AVSpeechSynthesizer()

    /// Una frase fissa: "ciao", "fatto", "guardo", "ripeti", detta dalla voce di macOS nella lingua di Pulsar.
    static func frase(_ nome: String) {
        let testo: String
        switch nome {
        case "ciao": testo = Saluto.ciao(Persona.nome, inglese: !pulsarItalian)
        case "fatto": testo = T("Fatto", "Done")
        case "guardo": testo = T("Un attimo, ci guardo", "One moment, let me look")
        case "ripeti": testo = T("Scusa, non ho capito", "Sorry, I didn't get that")
        default: return
        }
        guard enabled else { return }
        let u = AVSpeechUtterance(string: testo)
        u.voice = AVSpeechSynthesisVoice(language: pulsarItalian ? "it-IT" : "en-US")
        DispatchQueue.main.async {
            if sintesi.isSpeaking { sintesi.stopSpeaking(at: .immediate) }
            sintesi.speak(u)
        }
    }

    /// Nella vendita le risposte intere non si leggono: resta il testo nell'isola.
    static func leggi(_ testo: String) -> Bool { false }
}

// MARK: - La stella

/// Stella a quattro punte coi lati incurvati, come quella dell'immagine dell'autore.
struct StellaShape: Shape {
    var pinch: CGFloat = 0.18          // quanto stringono i fianchi (più basso = punte più sottili)
    var animatableData: CGFloat { get { pinch } set { pinch = newValue } }
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        let tips = [CGPoint(x: c.x, y: c.y - R), CGPoint(x: c.x + R, y: c.y), CGPoint(x: c.x, y: c.y + R), CGPoint(x: c.x - R, y: c.y)]
        var p = Path()
        p.move(to: tips[0])
        for i in 0..<4 {
            let a = tips[i], b = tips[(i + 1) % 4]
            let ctrl = CGPoint(x: c.x + (a.x + b.x - 2 * c.x) * pinch, y: c.y + (a.y + b.y - 2 * c.y) * pinch)
            p.addQuadCurve(to: b, control: ctrl)
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Icone a pastiglia (12/10 notte)
// l'autore: "a sinistra hai un paio di icone, creane altre dello stesso stile, una per ogni app aperta". Lo stile è quello
// di terminal.fill: una pastiglia chiara arrotondata con il simbolo scavato dentro, scuro. Tutte della stessa misura.

struct Pastiglia: View {
    let symbol: String
    var tint: Color? = nil
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.2, style: .continuous)
                .fill(tint ?? Color.primary.opacity(0.85))
            Image(systemName: symbol).font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Theme.light ? Color.white : Color.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: 15, height: 12.5)
    }
}

/// Il simbolo del passo di Claude come pastiglia (legge, modifica, esegue...): esegue usa terminal.fill, che è già così.
enum StepPastiglia {
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "READ": return "doc.text"
        case "EDIT": return "pencil"
        case "RUN": return "chevron.right"
        case "FIND": return "magnifyingglass"
        case "WEB": return "globe"
        case "AGENT": return "person.2"
        case "PLAN": return "checklist"
        case "WAIT": return "hand.raised"
        case "DONE": return "checkmark"
        case "THINK": return "sparkle"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// Simbolo da scavare nella pastiglia per ogni app (le stesse scelte di AppSymbol, versioni senza riempimento).
enum AppPastiglia {
    static func of(name: String, bundle: String) -> String {
        let s = AppSymbol.of(name: name, bundle: bundle)
        return s.replacingOccurrences(of: ".fill", with: "")
    }
}

/// La sinistra del notch: il passo di Claude per 5 s, poi le app aperte una alla volta (2 s), poi di nuovo il passo.
/// Se Claude aspetta un ok resta la mano ferma. Senza Claude: solo le app.
struct PastiglieInSequenza: View {
    var kind: String? = nil              // nil = niente Claude (isola a riposo)
    var waiting = false
    @ObservedObject var recents = RecentApps.shared
    var body: some View {
        let apps = Array(recents.entries.filter(\.running).prefix(5))
        let head = kind == nil ? 0.0 : 5.0
        let cycle = head + Double(max(apps.count, 1)) * 2.0
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let i = Int((t - head) / 2.0)
            ZStack {
                if waiting {
                    Pastiglia(symbol: "hand.raised", tint: Night.amber)
                } else if let k = kind, (t < head || apps.isEmpty) {
                    Pastiglia(symbol: StepPastiglia.symbol(k), tint: k == "DONE" ? Night.green : nil).id("step" + k)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else if !apps.isEmpty {
                    let e = apps[min(max(i, 0), apps.count - 1)]
                    Pastiglia(symbol: AppPastiglia.of(name: e.name, bundle: e.bundle)).id(e.bundle)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .help(e.name)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: waiting ? -2 : (t < head ? -1 : i))
        }
        .frame(width: 16, height: 14)
    }
}
