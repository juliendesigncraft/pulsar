// Fase 5, compito 3b: gli aggiornamenti automatici con Sparkle (Vendor/Sparkle/LEGGIMI.md), solo nella build di vendita.
// La build personale non collega Sparkle e non lo importa: tutto il file sta dentro #if !PERSONALE.
// Indirizzo dell'appcast (SUFeedURL) e chiave pubblica EdDSA (SUPublicEDKey) stanno nell'Info.plist, scritti da build-vendita.sh.
// In rete Sparkle legge soltanto l'appcast e, se c'è una versione nuova e la si accetta, scarica il suo zip.
// L'interruttore "Cerca aggiornamenti da solo" (pagina Generale, chiave aggiornamentiAutomatici) decide il controllo
// automatico; "Check for Updates…" nel menu cerca subito anche a interruttore spento.
//
// Riapertura (05/11): Pulsar vive nel notch e di solito nessuno lo chiude. Sparkle, con l'aggiornamento automatico,
// scarica la versione nuova e la installa "alla chiusura": se la chiusura non arriva mai, l'app resta quella vecchia;
// se arriva da sola, non si riapre. Quando Sparkle dice "versione pronta" aspettiamo che il Mac sia fermo (momentoBuono),
// poi chiudiamo Pulsar (parte l'installazione) e uno script lo riapre dal suo percorso (chiudiERiapri), così
// l'aggiornamento finisce con Pulsar di nuovo acceso. Provato il 05/11 end to end in locale (3.0 -> 3.4).
import AppKit
import Sparkle

final class Aggiornamenti: NSObject, SPUUpdaterDelegate {
    static let shared = Aggiornamenti()
    private var controller: SPUStandardUpdaterController?
    /// L'aggiornatore è partito: senza indirizzo o chiave validi resta spento e la voce "Check for Updates…" non compare.
    private(set) var attivo = false

    private var attesa: Timer?

    /// All'avvio della vendita. Non mostra mai un avviso se la configurazione manca: lo scrive solo nel registro.
    func avvia() {
        guard controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller = c
        // la nostra chiave vince su quella che Sparkle tiene da sé (SUEnableAutomaticChecks nelle preferenze dell'app)
        c.updater.automaticallyChecksForUpdates = Impostazioni.aggiornamentiAutomatici
        do {
            try c.updater.start()
            attivo = true
        } catch {
            NSLog("Pulsar: aggiornamenti spenti, configurazione di Sparkle non valida: \(error.localizedDescription)")
        }
    }

    /// "Check for Updates…": cerca subito e mostra il risultato (anche "sei aggiornato").
    func cercaOra() {
        guard attivo, let c = controller else { return }
        c.checkForUpdates(nil)
    }

    /// L'interruttore della pagina Generale.
    var automatici: Bool {
        get { Impostazioni.aggiornamentiAutomatici }
        set {
            Impostazioni.set(newValue, .aggiornamentiAutomatici)
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    // MARK: riapertura dopo l'aggiornamento

    /// Sparkle ha scaricato una versione nuova e la installerebbe alla chiusura. Rispondiamo "ci pensiamo noi":
    /// prendiamo il blocco e lo lanciamo al momento giusto. Se Pulsar viene chiuso prima, Sparkle installa comunque.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        NSLog("Pulsar: versione \(item.displayVersionString) pronta, la installo e riapro appena il Mac è fermo")
        attesa?.invalidate()
        attesa = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] t in
            guard let self, Self.momentoBuono() else { return }
            t.invalidate()
            self.attesa = nil
            self.chiudiERiapri()
        }
        return true
    }

    /// Non usiamo il "riapri" di Sparkle (immediateInstallationBlock): provato il 05/11, su un Mac con più copie di Pulsar
    /// registrate (stesso identificativo) il sistema riapre una copia a caso, non quella appena aggiornata.
    /// Facciamo così: un piccolo script esterno aspetta che Pulsar sia chiuso e che l'installatore di Sparkle abbia cambiato
    /// la versione dell'app, poi la riapre dal suo percorso esatto. Se l'installazione non riesce entro un minuto,
    /// riapre comunque quella che c'era, così Pulsar non resta mai spento.
    private func chiudiERiapri() {
        let percorso = Bundle.main.bundlePath
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
        for i in $(seq 1 120); do
          n=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$2/Contents/Info.plist" 2>/dev/null)
          [ -n "$n" ] && [ "$n" != "$3" ] && break
          sleep 0.5
        done
        sleep 2
        /usr/bin/open -n "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "pulsar-riapri", String(ProcessInfo.processInfo.processIdentifier), percorso, build]
        do { try p.run() } catch {
            NSLog("Pulsar: non riesco a preparare la riapertura (\(error.localizedDescription)), chiudo senza")
        }
        // la chiusura fa partire l'installazione di Sparkle, che era già pronta e in attesa proprio di questo
        NSApp.terminate(nil)
    }

    /// Scelta dell'autore (05/11): riavviare solo dopo 5 minuti senza tasti né mouse e mai con una richiesta aperta (più vecchia di 30 minuti = fantasma, ignorata).
    static func momentoBuono() -> Bool {
        let fermoDa = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return fermoDa >= 300 && !richiestaAperta()
    }

    /// Una sessione di Pulsar Agente aspetta un OK o una risposta (agente/state.json: "pending" o "question").
    /// Se il file non si legge, per prudenza conta come richiesta aperta: meglio aggiornare più tardi che nel momento sbagliato.
    private static func richiestaAperta() -> Bool {
        let url = Cartelle.dati.appendingPathComponent("agente/state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return false }   // Agente mai usato
        guard let dati = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let sessioni = json["sessions"] as? [String: Any] else { return true }
        // 05/11, l'autore: una richiesta più vecchia di 30 minuti è un fantasma (l'hook aspetta 25 secondi, poi la riga
        // resta nel file fino a 6 ore) e non blocca l'aggiornamento. Senza l'ora "t" conta come aperta.
        let ora = Date().timeIntervalSince1970
        func viva(_ x: Any?) -> Bool {
            guard let d = x as? [String: Any] else { return false }          // null o assente: nessuna richiesta
            guard let t = (d["t"] as? NSNumber)?.doubleValue else { return true }
            return ora - t < 30 * 60
        }
        return sessioni.values.contains { s in
            guard let s = s as? [String: Any] else { return false }
            return viva(s["pending"]) || viva(s["question"])
        }
    }
}
