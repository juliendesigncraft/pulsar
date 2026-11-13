// Il socket con l'hook di Claude Code (sposto da agente-linea.swift il 01/11/2026, senza cambiarlo):
// solo Foundation, così lo usano anche il banco di prova del ponte con l'iPhone e Pulsar.
import Foundation

// MARK: - Socket con l'hook


/// Server sul socket `agente/pulsar.sock`. L'hook manda una riga JSON:
/// `{"op":"ping"}` = stato cambiato, ricarica subito; `{"op":"wait","id":…}` = resta in linea finché l'autore risponde.
/// `{"op":"wait","id":…,"kind":"ask"}` = una domanda di Claude: se `showsQuestions` dice no (l'Isola non gira),
/// risponde subito "nel terminale" e Claude Code chiede lì senza aspettare (fase 5, 2b).
/// Se Pulsar è spento il socket non risponde e l'hook esce subito: Claude Code non aspetta mai.
final class AgentSocket {
    let path: String
    var onPing: (() -> Void)?
    /// Chiamata sul filo principale per ogni domanda di Claude: vero = le scelte si vedono nel notch, quindi si aspetta.
    /// Nil = si aspetta sempre (come prima).
    var showsQuestions: (() -> Bool)?
    private var fd: Int32 = -1
    private var waiters: [String: Int32] = [:]          // id della domanda -> connessione dell'hook in attesa
    private var early: [String: Data] = [:]              // risposte arrivate prima che l'hook si mettesse in attesa
    private let lock = NSLock()

    init(path: String) { self.path = path }

    func start() {
        guard fd < 0 else { return }
        unlink(path)
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(s); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, listen(s, 16) == 0 else { close(s); return }
        chmod(path, 0o600)                                  // solo l'utente del Mac
        fd = s
        let t = Thread { [weak self] in self?.loop(s) }
        t.name = "Pulsar agente socket"
        t.start()
    }

    func stop() {
        guard fd >= 0 else { return }
        let s = fd
        fd = -1
        shutdown(s, SHUT_RDWR); close(s)
        unlink(path)
        lock.lock()
        waiters.values.forEach { close($0) }                 // chi aspettava torna al terminale
        waiters = [:]; early = [:]
        lock.unlock()
    }

    private func loop(_ s: Int32) {
        while fd == s {
            let c = accept(s, nil, nil)
            if c < 0 { if fd != s { return }; continue }
            var on: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))   // un hook chiuso non fa cadere Pulsar
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve(c) }
        }
    }

    private func serve(_ c: Int32) {
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 4096)
        var got = Data()
        while !got.contains(10) {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            got.append(contentsOf: buf[0..<n])
        }
        guard let lineEnd = got.firstIndex(of: 10) ?? (got.isEmpty ? nil : got.endIndex),
              let msg = try? JSONSerialization.jsonObject(with: got[got.startIndex..<lineEnd]) as? [String: Any],
              let op = msg["op"] as? String else { close(c); return }
        DispatchQueue.main.async { [weak self] in self?.onPing?() }
        guard op == "wait", let id = msg["id"] as? String else { close(c); return }
        lock.lock()
        if let ready = early.removeValue(forKey: id) {
            lock.unlock()
            send(ready, to: c)
            return
        }
        if let old = waiters[id] { close(old) }
        waiters[id] = c
        lock.unlock()
        // la domanda è in linea: se nessuno può vederne le scelte, torna subito al terminale
        if msg["kind"] as? String == "ask" {
            DispatchQueue.main.async { [weak self] in
                guard let self, let mostra = self.showsQuestions, !mostra() else { return }
                self.answer(id, ["behavior": "terminal"])
            }
        }
    }

    /// La risposta per l'hook che aspetta `id`. Se non è ancora in linea, la tiene per quando arriva.
    func answer(_ id: String, _ body: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: body) else { return }
        data.append(10)
        lock.lock()
        if let c = waiters.removeValue(forKey: id) {
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.send(data, to: c) }
        } else {
            early[id] = data
            if early.count > 20 { early.removeValue(forKey: early.keys.first!) }
            lock.unlock()
        }
    }

    private func send(_ data: Data, to c: Int32) {
        data.withUnsafeBytes { p in _ = write(c, p.baseAddress, data.count) }
        close(c)
    }
}
