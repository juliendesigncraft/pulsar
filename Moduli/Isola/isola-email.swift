// L'email dal notch (24/10/2026, dal reel di coucou "Drop a file on your notch. Mochi eats it"): si trascina un file
// sul notch, lo si lascia sulla tessera Email di Stow e il notch apre un'email già pronta, col razzo al posto della mascotte.
// Parte da Mail del Mac (gli account sono i suoi, in Pulsar nessuna password) e solo col tasto Invia.
import SwiftUI
import AppKit

final class EmailBozza: ObservableObject {
    enum Stato: Equatable { case scrivi, invio, inviata(String), errore(String) }
    let file: [URL]
    @Published var a = ""
    @Published var oggetto: String
    @Published var testo = ""
    @Published var stato: Stato = .scrivi

    init(file: [URL]) {
        self.file = file
        oggetto = file.count == 1 ? file[0].lastPathComponent : T("\(file.count) file", "\(file.count) files")
    }

    var valida: Bool { a.contains("@") && a.contains(".") && !a.contains(" ") }

    /// Gli ultimi indirizzi usati, per non riscriverli (solo su questo Mac).
    static var recenti: [String] {
        get { UserDefaults.standard.stringArray(forKey: "emailRecenti") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(4)), forKey: "emailRecenti") }
    }
}

/// Nella vendita la tessera Email non c'è (24/10): niente Mail e niente permesso di Automazione per Mail nel binario.
enum MailMac {
    static func invia(_ b: EmailBozza, fatto: @escaping (String?) -> Void) { fatto(T("Non disponibile", "Not available")) }
}

/// La scheda dell'email: razzo a sinistra, campi a destra, niente contorni (solo le sfumature dell'azzurro).
struct EmailCard: View {
    static let altezza: CGFloat = 186
    @ObservedObject var bozza: EmailBozza
    var chiudi: () -> Void
    @FocusState private var campo: Int?

    var body: some View {
        VCard(glow: Volta.a1, breathe: bozza.stato == .invio, padding: 16) {
            HStack(alignment: .center, spacing: 16) {
                Razzo(phase: fase, pixel: 3.4).frame(width: 60, height: 84).clipped()
                switch bozza.stato {
                case .inviata(let dest):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Email inviata", "Email sent")).font(.system(size: 16, weight: .light)).foregroundStyle(Volta.t1)
                        Text(T("a ", "to ") + dest).font(.system(size: 12.5)).foregroundStyle(Volta.t2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    modulo
                }
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { campo = 0 } }
        .onExitCommand(perform: chiudi)
    }

    private var fase: Razzo.Phase {
        switch bozza.stato { case .invio: return .launch; case .inviata: return .idle; case .errore: return .wait; case .scrivi: return .loaded }
    }

    private var modulo: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(T("Nuova email", "New email")).font(.system(size: 13)).foregroundStyle(Volta.t1)
                Text(T("con ", "with ") + bozza.oggetto).font(.system(size: 11.5)).foregroundStyle(Volta.t3).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            riga(T("A", "To")) {
                TextField("", text: $bozza.a, prompt: Text("nome@studio.it").foregroundColor(Volta.t3))
                    .focused($campo, equals: 0).onSubmit { campo = 2 }
            }
            if bozza.a.isEmpty, !EmailBozza.recenti.isEmpty {
                HStack(spacing: 5) {
                    ForEach(EmailBozza.recenti, id: \.self) { r in
                        Text(r).font(.system(size: 10.5)).foregroundStyle(Volta.pillT).lineLimit(1)
                            .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(Volta.pill))
                            .onTapGesture { bozza.a = r; campo = 2 }
                    }
                }
            }
            riga(T("Oggetto", "Subject")) { TextField("", text: $bozza.oggetto).focused($campo, equals: 1) }
            riga(nil) {
                TextField("", text: $bozza.testo, prompt: Text(T("Due righe, se vuoi", "A line, if you like")).foregroundColor(Volta.t3))
                    .focused($campo, equals: 2).onSubmit(invia)
            }
            HStack(spacing: 6) {
                Button(action: invia) {
                    Text(bozza.stato == .invio ? T("Invio…", "Sending…") : T("Invia", "Send")).font(.system(size: 12))
                        .foregroundStyle(Volta.primT).padding(.horizontal, 14).frame(height: 24)
                        .background(Capsule().fill(Volta.prim.opacity(bozza.valida ? 1 : 0.45)))
                }
                .buttonStyle(.plain).disabled(!bozza.valida || bozza.stato == .invio)
                .keyboardShortcut(.return, modifiers: .command)
                Button(action: chiudi) {
                    Text(T("Annulla", "Cancel")).font(.system(size: 12)).foregroundStyle(Volta.t2)
                        .padding(.horizontal, 12).frame(height: 24).background(Capsule().fill(Volta.card2))
                }
                .buttonStyle(.plain)
                if case .errore(let e) = bozza.stato {
                    Text(e).font(.system(size: 10.5)).foregroundStyle(Volta.t2).lineLimit(2)
                }
            }
            .padding(.top, 2)
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        .foregroundStyle(Volta.t1)
    }

    private func riga<C: View>(_ etichetta: String?, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) {
            if let etichetta { Text(etichetta).font(.system(size: 11)).foregroundStyle(Volta.t3).frame(width: 46, alignment: .leading) }
            c()
        }
        .padding(.horizontal, 10).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Volta.card2))
    }

    private func invia() {
        guard bozza.valida, bozza.stato != .invio else { return }
        bozza.stato = .invio
        let dest = bozza.a
        MailMac.invia(bozza) { errore in
            if let errore { bozza.stato = .errore(errore); return }
            EmailBozza.recenti = [dest] + EmailBozza.recenti.filter { $0 != dest }
            bozza.stato = .inviata(dest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: chiudi)
        }
    }
}
