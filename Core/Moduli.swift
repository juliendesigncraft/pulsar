// Registro dei moduli (fase 2, compito 6): chi è acceso, chi è sbloccato dalla licenza, chi parte e chi si ferma.
// Solo Foundation: si prova senza l'app. I moduli veri conformano a `ModuloPulsar` nei loro file.
// Regola: un modulo gira solo se l'utente lo vuole acceso E la licenza lo sblocca. Fermare per licenza non scrive
// mai la scelta dell'utente (`acceso` resta com'è): al rinnovo il modulo riparte da solo.
import Foundation

/// I permessi di macOS che un modulo può chiedere: li mostrano la pagina Permessi e il benvenuto (fase 3).
enum Permesso: String, CaseIterable { case accessibilita, automazione, registrazioneSchermo, microfono, riconoscimentoVocale, calendario }

protocol ModuloPulsar: AnyObject {
    var id: String { get }
    var nome: String { get }
    var prodotto: Prodotto { get }
    var permessi: [Permesso] { get }
    /// La scelta dell'utente (la stessa chiave salvata di sempre), non la licenza.
    var acceso: Bool { get }
    /// Avvia il servizio, senza toccare la scelta salvata. Ripeterla non fa danni.
    func avvia()
    /// Ferma il servizio, senza toccare la scelta salvata. Ripeterla non fa danni.
    func ferma()
}

enum Registro {
    /// Pura: per ogni modulo, attivo = acceso dall'utente E sbloccato dalla licenza.
    /// `inAttesa` (fase 3): i moduli che aspettano la fine del benvenuto non partono, qualunque sia la scelta.
    static func decidi(_ moduli: [(id: String, prodotto: Prodotto, acceso: Bool)], sbloccati: Set<Prodotto>, inAttesa: Set<String> = []) -> [String: Bool] {
        var r: [String: Bool] = [:]
        for m in moduli { r[m.id] = m.acceso && sbloccati.contains(m.prodotto) && !inAttesa.contains(m.id) }
        return r
    }

    /// Pura (fase 5, 2b): le scelte di una domanda di Claude (AskUserQuestion) si mostrano solo nell'Isola.
    /// Vero = la domanda resta in attesa nel notch; falso = l'hook riceve subito "nel terminale" e Claude Code chiede lì,
    /// senza i 90 s di attesa. Falso quando l'Isola non gira (spenta, bloccata dalla licenza, in attesa del benvenuto).
    static func domandaNelNotch(isolaInEsecuzione: Bool, isolaBloccata: Bool) -> Bool { isolaInEsecuzione && !isolaBloccata }

    /// Pura: unione senza doppioni, nell'ordine fisso di `Permesso.allCases`.
    static func permessi(_ liste: [[Permesso]]) -> [Permesso] {
        let tutti = Set(liste.joined())
        return Permesso.allCases.filter(tutti.contains)
    }
}

/// Va usato sul filo principale (AppKit sotto).
final class RegistroModuli {
    static let shared = RegistroModuli()

    private var moduli: [ModuloPulsar] = []          // nell'ordine di registrazione: è anche l'ordine di avvio
    private var avviati: Set<String> = []
    /// Prima della prima `applica` niente è bloccato (nessuna decisione presa).
    private var sbloccati: Set<Prodotto> = Set(Prodotto.allCases)
    /// Fase 3: i moduli che non partono finché il benvenuto è aperto (BenvenutoLogica.moduliInAttesa). Vuoto di solito.
    var inAttesa: Set<String> = []

    func registra(_ m: ModuloPulsar) {
        guard !moduli.contains(where: { $0 === m }) else { return }
        moduli.append(m)
    }

    /// Porta ogni modulo dove la licenza e la scelta dell'utente dicono. Avvia solo chi non gira già, ferma solo chi gira.
    func applica(sbloccati nuovi: Set<Prodotto>) {
        sbloccati = nuovi
        let voluti = Registro.decidi(moduli.map { (id: $0.id, prodotto: $0.prodotto, acceso: $0.acceso) }, sbloccati: nuovi, inAttesa: inAttesa)
        for m in moduli {
            let vuole = voluti[m.id] ?? false
            if vuole && !avviati.contains(m.id) {
                avviati.insert(m.id)          // prima di avviare: un avvio che richiama `riapplica` non riparte da capo
                m.avvia()
            } else if !vuole && avviati.contains(m.id) {
                avviati.remove(m.id)
                m.ferma()
            }
        }
    }

    /// Dopo che l'utente ha cambiato una scelta (interruttore del menu): stessa licenza di prima.
    func riapplica() { applica(sbloccati: sbloccati) }

    /// Il benvenuto si è chiuso: i moduli in attesa partono secondo le scelte fatte (e la licenza di adesso).
    func liberaAttesa() {
        guard !inAttesa.isEmpty else { return }
        inAttesa = []
        applica(sbloccati: sbloccati)
    }

    /// Pura: ciò che un modulo fa da solo (routine, promemoria) gira solo se il modulo non è bloccato.
    static func deveEseguire(bloccato: Bool) -> Bool { !bloccato }

    func bloccato(_ id: String) -> Bool {
        guard let m = moduli.first(where: { $0.id == id }) else { return false }
        return !sbloccati.contains(m.prodotto)
    }

    func inEsecuzione(_ id: String) -> Bool { avviati.contains(id) }

    func prodotto(di id: String) -> Prodotto? { moduli.first { $0.id == id }?.prodotto }

    /// I permessi dei moduli registrati, accesi e sbloccati, più `altri` (quelli di Lite): unione senza doppioni,
    /// nell'ordine fisso di `Permesso.allCases`. Per la pagina Permessi delle Impostazioni (fase 3).
    func permessiInUso(altri: [Permesso] = []) -> [Permesso] {
        Registro.permessi(moduli.filter { $0.acceso && sbloccati.contains($0.prodotto) }.map(\.permessi) + [altri])
    }
}
