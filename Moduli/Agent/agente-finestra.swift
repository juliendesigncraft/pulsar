// Finestra (17/10/2026): una finestra di un'altra app, dal vivo, dentro il pannello laterale dell'Agente.
// l'autore: "il video YouTube che stavo guardando, o una app che riduco, si può continuare a vedere lì dentro,
// con la possibilità di muoversi e zoomare all'interno del riquadro".
// Limite di macOS: una finestra ridotta nel Dock non viene più disegnata, quindi non si può riprendere.
// Basta lasciarla aperta dietro le altre: coperta si riprende benissimo.
// Usa ScreenCaptureKit (permesso Registrazione schermo, lo stesso della miniatura dell'isola) e si ferma
// appena la sezione non si vede.
import SwiftUI
import AppKit
import ScreenCaptureKit
import CoreImage

struct LiveWindowInfo: Identifiable, Equatable {
    let id: UInt32
    let app: String
    let bundle: String
    let title: String
    let size: CGSize
}

final class LiveWindow: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = LiveWindow()

    @Published private(set) var list: [LiveWindowInfo] = []
    @Published private(set) var image: CGImage?
    @Published private(set) var current: LiveWindowInfo?
    @Published private(set) var denied = false
    @Published private(set) var lost = false        // la finestra è stata ridotta o chiusa

    private var stream: SCStream?
    private var generation = 0
    private let ctx = CIContext()
    private let queue = DispatchQueue(label: "pulsar.finestra", qos: .userInitiated)
    private var lastFrame = Date()
    private var watchdog: Timer?

    /// Le finestre vere sullo schermo: livello normale, abbastanza grandi, col titolo, non di Pulsar.
    func refresh(retry: Int = 2) {
        Task {
            do {
                let c = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let wins = c.windows.filter {
                    $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 120 && !($0.title ?? "").isEmpty
                        && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                }
                let out = wins.map { LiveWindowInfo(id: $0.windowID, app: $0.owningApplication?.applicationName ?? "",
                                                    bundle: $0.owningApplication?.bundleIdentifier ?? "",
                                                    title: $0.title ?? "", size: $0.frame.size) }
                await MainActor.run { self.list = out; self.denied = false }
                // appena avviata Pulsar, ScreenCaptureKit a volte risponde con un elenco vuoto: si riprova
                if out.isEmpty && retry > 0 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self.refresh(retry: retry - 1)
                }
            } catch {
                await MainActor.run { self.denied = true }
            }
        }
    }

    func watch(_ info: LiveWindowInfo) {
        stop()
        generation += 1
        let mine = generation
        Impostazioni.set("\(info.bundle)|\(info.title)", .agenteFinestra)
        Task { [weak self] in
            do {
                let c = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let self, self.generation == mine, let win = c.windows.first(where: { $0.windowID == info.id }) else {
                    await MainActor.run { self?.lost = true }
                    return
                }
                let cfg = SCStreamConfiguration()
                // abbastanza pixel per zoomare fino a 4x senza sgranare troppo, ma non di più
                let w = min(2200, max(800, Int(win.frame.width * 2)))
                cfg.width = w
                cfg.height = max(100, Int(CGFloat(w) * win.frame.height / win.frame.width))
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)   // un video resta fluido
                cfg.showsCursor = false
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.queueDepth = 4
                let s = SCStream(filter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                try await s.startCapture()
                await MainActor.run {
                    if self.generation == mine {
                        self.stream = s; self.current = info; self.lost = false; self.denied = false
                        self.lastFrame = Date()
                        self.startWatchdog()
                    } else { Task { try? await s.stopCapture() } }
                }
            } catch {
                await MainActor.run { self?.denied = true }
            }
        }
    }

    /// Riprende l'ultima finestra guardata, se c'è ancora.
    func resume() {
        guard stream == nil else { return }
        let key = Impostazioni.string(.agenteFinestra) ?? ""
        guard !key.isEmpty else { refresh(); return }
        Task {
            let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let hit = c?.windows.first { "\($0.owningApplication?.bundleIdentifier ?? "")|\($0.title ?? "")" == key }
            await MainActor.run {
                if let w = hit {
                    self.watch(LiveWindowInfo(id: w.windowID, app: w.owningApplication?.applicationName ?? "",
                                              bundle: w.owningApplication?.bundleIdentifier ?? "", title: w.title ?? "", size: w.frame.size))
                } else { self.refresh() }
            }
        }
    }

    func stop() {
        generation += 1
        watchdog?.invalidate(); watchdog = nil
        if let s = stream { Task { try? await s.stopCapture() } }
        stream = nil
    }

    /// Torna all'elenco.
    func close() {
        stop()
        current = nil
        image = nil
        lost = false
        Impostazioni.remove(.agenteFinestra)
        refresh()
    }

    /// Porta la finestra in primo piano nella sua app.
    func raise() {
        guard let c = current else { return }
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == c.bundle }?.activate()
    }

    // Se la finestra viene ridotta nel Dock i fotogrammi smettono di arrivare: lo si dice invece di restare su un'immagine ferma.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, let c = self.current else { return }
            guard Date().timeIntervalSince(self.lastFrame) > 3 else { if self.lost { self.lost = false }; return }
            Task {
                let on = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let visible = on?.windows.contains { $0.windowID == c.id } ?? true
                await MainActor.run { self.lost = !visible }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        DispatchQueue.main.async { [weak self] in self?.image = cg; self?.lastFrame = Date() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.stream = nil; self?.lost = true }
    }
}

// MARK: - La sezione del pannello

struct LiveWindowSection: View {
    @ObservedObject var live = LiveWindow.shared
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let c = live.current { viewer(c) } else { picker }
        }
        .onAppear { live.current == nil ? live.resume() : live.watch(live.current!) }
        .onDisappear { live.stop() }
    }

    // MARK: elenco delle finestre

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("Finestra", "Window")).font(.system(size: 15, weight: .semibold))
                    Text(T("Guarda un'altra app qui dentro", "Watch another app in here")).font(.system(size: 12)).foregroundStyle(Night.t2)
                }
                Spacer()
                Button { live.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(Night.t2)
                        .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain).help(T("Aggiorna", "Refresh"))
            }
            .padding(.leading, 2).padding(.bottom, 4)
            if live.denied {
                note(T("Consenti Registrazione schermo a Pulsar in Impostazioni di Sistema, Privacy e sicurezza.",
                       "Allow Screen Recording for Pulsar in System Settings, Privacy & Security."))
            } else if live.list.isEmpty {
                note(T("Nessuna finestra aperta. Le finestre ridotte nel Dock non si vedono: macOS smette di disegnarle.",
                       "No open windows. Windows minimized to the Dock can't be shown: macOS stops drawing them."))
            } else {
                ForEach(live.list) { w in
                    Button { zoom = 1; offset = .zero; live.watch(w) } label: { row(w) }.buttonStyle(.plain)
                }
                note(T("Lasciala aperta dietro le altre invece di ridurla nel Dock: coperta si vede, ridotta no.",
                       "Leave it open behind other windows instead of minimizing it: covered works, minimized doesn't."))
            }
        }
    }

    private func row(_ w: LiveWindowInfo) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(w.bundle)).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(w.app).font(.system(size: 11.5)).foregroundStyle(Night.t2).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Night.event))
        .contentShape(Rectangle())
    }

    private func icon(_ bundle: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage()
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5)).foregroundStyle(Night.t3).lineSpacing(2).padding(.horizontal, 2).padding(.top, 2)
    }

    // MARK: la finestra dal vivo

    private func viewer(_ c: LiveWindowInfo) -> some View {
        let z = min(6, max(1, zoom * pinch))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { live.close() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(Night.t2)
                        .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain).help(T("Altre finestre", "Other windows"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(c.app).font(.system(size: 11.5)).foregroundStyle(Night.t2).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { live.raise() } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 11, weight: .semibold)).foregroundStyle(Night.t2)
                        .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain).help(T("Apri la finestra", "Bring the window forward"))
            }
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(Theme.light ? 0.06 : 0.35))
                    if let img = live.image {
                        Image(decorative: img, scale: 1).resizable().interpolation(.high).scaledToFit()
                            .scaleEffect(z)
                            .offset(clamped(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), z, geo.size))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if live.lost {
                        Text(T("La finestra è ridotta o chiusa. Riaprila e lasciala dietro le altre.",
                               "The window is minimized or closed. Reopen it and leave it behind the others."))
                            .font(.system(size: 11.5, weight: .medium)).multilineTextAlignment(.center).foregroundStyle(.white)
                            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6))).padding(16)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { drag = $0.translation }
                    .onEnded { v in
                        offset = clamped(CGSize(width: offset.width + v.translation.width, height: offset.height + v.translation.height), z, geo.size)
                        drag = .zero
                    })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { v in zoom = min(6, max(1, zoom * v.magnification)); pinch = 1
                        offset = clamped(offset, zoom, geo.size) })
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.25)) { if zoom > 1.01 { zoom = 1; offset = .zero } else { zoom = 2 } }
                }
            }
            .aspectRatio(c.size.width / max(1, c.size.height), contentMode: .fit)
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                zoomButton("minus") { zoom = max(1, zoom / 1.4); if zoom <= 1.01 { offset = .zero } }
                Text("\(Int((z * 100).rounded()))%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Night.t2).frame(width: 44)
                zoomButton("plus") { zoom = min(6, zoom * 1.4) }
                Spacer()
                Text(T("Trascina per muoverti, pizzica per zoomare, doppio clic per tornare", "Drag to move, pinch to zoom, double-click to reset"))
                    .font(.system(size: 10.5)).foregroundStyle(Night.t3).lineLimit(2).multilineTextAlignment(.trailing)
            }
        }
    }

    private func zoomButton(_ symbol: String, _ f: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { f() } } label: {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Night.t2)
                .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    /// Non si esce dal riquadro: lo spostamento massimo è quanto l'immagine ingrandita sborda.
    private func clamped(_ o: CGSize, _ z: CGFloat, _ box: CGSize) -> CGSize {
        let mx = box.width * (z - 1) / 2, my = box.height * (z - 1) / 2
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }
}
