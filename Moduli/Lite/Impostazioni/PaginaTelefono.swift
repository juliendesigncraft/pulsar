// Il gruppo "iPhone" della pagina Claude Code (01/11/2026): l'interruttore del ponte con l'app Pulsar Pocket, il codice
// di accoppiamento e i telefoni accoppiati. Il ponte (telefono-ponte.swift) è spento di serie: questo è l'unico posto che lo accende.
import SwiftUI
import AppKit

struct GruppoTelefono: View {
    @State private var giro = 0
    @Environment(\.matte) private var m

    private var store: AgentStore? { FinestraImpostazioni.shared.agent?.store }

    var body: some View {
        let _ = giro
        let acceso = Impostazioni.bool(.agentTelefono)
        GruppoImpostazioni(T("iPhone", "iPhone")) {
            RigaInterruttore(T("Vedi Claude Code dall'iPhone", "See Claude Code from your iPhone"),
                             sotto: T("Spento di serie. Acceso, Pulsar ascolta sulla rete di casa (porta \(PonteTelefono.portaPredefinita)), tutto cifrato, e solo gli iPhone che accoppi con un codice vedono le sessioni e rispondono ai permessi. Niente passa da internet. L'app è Pulsar Pocket.",
                                      "Off by default. When on, Pulsar listens on your home network (port \(PonteTelefono.portaPredefinita)), everything encrypted, and only iPhones you pair with a code can see sessions and answer permissions. Nothing goes through the internet. The app is Pulsar Pocket."),
                             valore: { Impostazioni.bool(.agentTelefono) }) { store?.telefono($0) }
            if acceso, let ponte = store?.ponte {
                RigaBase(titolo: T("Accoppia un iPhone", "Pair an iPhone"),
                         sotto: T("Apri Pulsar Pocket sul telefono, scegli questo Mac e scrivi il codice. Vale 2 minuti, una volta sola.",
                                  "Open Pulsar Pocket on the phone, pick this Mac and type the code. It lasts 2 minutes, once.")) {
                    if let c = ponte.codiceAttivo {
                        Text(c.valore.prefix(3) + " " + c.valore.suffix(3))
                            .font(.system(size: 20, weight: .light, design: .monospaced)).foregroundStyle(m.a2).monospacedDigit()
                    } else {
                        TastoImpostazioni(T("Mostra il codice", "Show code"), principale: true) { ponte.nuovoCodice() }
                    }
                }
                ForEach(ponte.dispositivi) { d in
                    RigaBase(titolo: d.nome, sotto: T("Ultimo uso \(Self.quando(d.ultimo))", "Last used \(Self.quando(d.ultimo))"), simbolo: "iphone") {
                        TastoImpostazioni(T("Scollega", "Unpair")) { ponte.scollega(d.id) }
                    }
                }
                RigaValore(T("Stato", "Status"), sotto: T("Il telefono confronta questa impronta all'accoppiamento.", "The phone remembers this fingerprint when it pairs."),
                           valore: Self.stato(ponte))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .telefonoCambiato)) { _ in giro += 1 }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in if acceso { giro += 1 } }
    }

    private static func stato(_ p: PonteTelefono) -> String {
        let imp = p.impronta.isEmpty ? "" : "  " + stride(from: 0, to: 12, by: 4).map { String(p.impronta.dropFirst($0).prefix(4)) }.joined(separator: " ")
        return "\(p.stato == "in ascolto" ? T("in ascolto", "listening") : p.stato), \(p.connessi) \(T("connessi", "connected"))\(imp)"
    }

    private static func quando(_ t: Double) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: Date(timeIntervalSince1970: t), relativeTo: Date())
    }
}
