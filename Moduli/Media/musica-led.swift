// Il livello della musica (12/10/2026, notte) e i colori della copertina, per la luce sul bordo della tessera (widget-braun.swift).
// Ascolto: un tap di Core Audio sui processi di Spotify (o Musica), NON silenziato (l'app suona normalmente), solo per
// misurare quanto forte suona istante per istante. Gira solo mentre la tessera si vede e la musica suona. Niente viene
// registrato o salvato: si legge il livello e si butta. Permesso: lo stesso del mixer della ghiera (Audio delle app).
import SwiftUI
import AppKit
import CoreAudio
import AudioToolbox
import Accelerate

final class MusicMeter: ObservableObject {
    static let shared = MusicMeter()
    @Published private(set) var level: Double = 0        // 0-1, morbido
    @Published private(set) var beat: Double = 0         // 1 al colpo, poi scende
    @Published private(set) var beatAt: Date = .distantPast

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var viewers = 0
    private var raw: Float = 0                            // scritto dal thread audio
    private let lock = NSLock()
    private var timer: Timer?
    private var avg: Double = 0                           // media lenta, per riconoscere i colpi
    private var lastBeat = Date.distantPast

    func watch(_ on: Bool, bundle: String) {
        viewers = max(0, viewers + (on ? 1 : -1))
        if viewers > 0 && tapID == kAudioObjectUnknown { start(bundle) }
        if viewers == 0 { stop() }
    }

    private func addr(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// I processi audio dell'app (Spotify suona da un processo di aiuto: si prendono tutti quelli col suo bundle).
    private func processes(_ bundle: String) -> [AudioObjectID] {
        var a = addr(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var b = addr(kAudioProcessPropertyBundleID)
            var ref: Unmanaged<CFString>?
            var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &b, 0, nil, &sz, &ref) == noErr, let s = ref?.takeRetainedValue() as String? else { return false }
            return s.hasPrefix(bundle)
        }
    }

    private func outputUID() -> String? {
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        var dev = AudioObjectID(0); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr else { return nil }
        var u = addr(kAudioDevicePropertyDeviceUID)
        var ref: Unmanaged<CFString>?; var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &u, 0, nil, &sz, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    private func start(_ bundle: String) {
        let procs = processes(bundle)
        guard !procs.isEmpty, let out = outputUID() else { return }
        let desc = CATapDescription(stereoMixdownOfProcesses: procs)
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted                 // Spotify continua a suonare da solo: noi ascoltiamo e basta
        desc.isPrivate = true
        desc.name = "Pulsar LED"
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { tapID = AudioObjectID(kAudioObjectUnknown); return }
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pulsar LED",
            kAudioAggregateDeviceUIDKey: "pulsar.led.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: out,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: out]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { stop(); return }
        let q = DispatchQueue(label: "pulsar.led.io", qos: .userInitiated)
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, q) { [weak self] _, inInput, _, outOutput, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            var peak: Float = 0
            for b in ins {
                guard let d = b.mData else { continue }
                var rms: Float = 0
                vDSP_rmsqv(d.assumingMemoryBound(to: Float.self), 1, &rms, vDSP_Length(Int(b.mDataByteSize) / 4))
                peak = max(peak, rms)
            }
            // in uscita niente: il suono vero lo fa Spotify
            for b in UnsafeMutableAudioBufferListPointer(outOutput) { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
            guard let self else { return }
            self.lock.lock(); self.raw = max(self.raw * 0.6, peak); self.lock.unlock()
        }
        guard err == noErr, procID != nil, AudioDeviceStart(aggID, procID) == noErr else { stop(); return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        lock.lock(); let r = Double(raw); raw *= 0.5; lock.unlock()
        let v = min(1, pow(r * 4.2, 0.8))                 // scala percepita: la musica a volume normale riempie metà bordo
        level = level * 0.55 + v * 0.45
        avg = avg * 0.94 + v * 0.06
        // un colpo: sale di colpo sopra la media e non c'è stato un altro colpo da poco
        if v > avg * 1.35 + 0.06, Date().timeIntervalSince(lastBeat) > 0.22 { lastBeat = Date(); beatAt = lastBeat; beat = 1 }
        else { beat *= 0.86 }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        level = 0; beat = 0
    }
}

/// I colori vivi della copertina (12/10 notte, l'autore: "se il led usasse i colori della copertina alternando il bianco").
/// La copertina rimpicciolita a 24x24; si scartano i pixel grigi o troppo scuri, si raggruppano per tinta e si tengono
/// le tre tinte più presenti, schiarite quanto basta per brillare sul buio.
enum CoverPalette {
    private static var cache: [ObjectIdentifier: [Color]] = [:]
    static func colors(_ img: NSImage?) -> [Color] {
        guard let img else { return [] }
        if let c = cache[ObjectIdentifier(img)] { return c }
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var buckets: [Int: (h: Double, s: Double, b: Double, n: Double)] = [:]
        for x in 0..<side { for y in 0..<side {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            var h: CGFloat = 0, sa: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
            c.getHue(&h, saturation: &sa, brightness: &br, alpha: &al)
            guard sa > 0.28, br > 0.25 else { continue }          // niente grigi né neri
            let k = Int(h * 12) % 12                                // dodici spicchi di tinta
            let w = Double(sa * br)                                 // i pixel più vivi pesano di più
            let o = buckets[k] ?? (0, 0, 0, 0)
            buckets[k] = (o.h + Double(h) * w, o.s + Double(sa) * w, o.b + Double(br) * w, o.n + w)
        }}
        let top = buckets.values.sorted { $0.n > $1.n }.prefix(3)
        let out = top.map { v -> Color in
            let h = v.h / v.n, sa = min(0.85, v.s / v.n), br = max(0.85, v.b / v.n)   // schiariti: devono brillare
            return Color(hue: h, saturation: sa, brightness: br)
        }
        cache[ObjectIdentifier(img)] = out
        return out
    }
}
