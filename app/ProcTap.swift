// PROCTAP (v14, 10.11.2026, task 99): one app's sound through a CoreAudio process tap (macOS 14.2+).
// Chrome renders every tab's sound in its AudioService helper ("Google Chrome Helper", bundle com.google.Chrome.helper),
// which ScreenCaptureKit does not list as an application nor give to Chrome: the SCK app capture of Chrome was silent
// (peak -100 dBFS, measured 10.11.2026). The tap takes the processes whose CoreAudio bundle id starts with the app's,
// helpers included, mixed to stereo, into a private aggregate device whose IOProc hands the frames to the ring.
// The Mac's input and output are never changed (the aggregate is private, the tap is unmuted: Chrome still sounds).
import Foundation
import CoreAudio
import AudioToolbox

final class ProcTap: AppSource {
    /// the apps that need it (their sound comes from helper processes)
    static func wanted(_ bundle: String) -> Bool { bundle.hasPrefix("com.google.Chrome") || bundle.hasPrefix("com.microsoft.edgemac") || bundle.hasPrefix("com.brave.Browser") }

    /// v18: any app whose sound CoreAudio already sees (a process object) goes through the tap; Firefox keeps ScreenCaptureKit (as before)
    static func preferred(_ bundle: String) -> Bool {
        if wanted(bundle) { return true }
        if bundle == "org.mozilla.firefox" { return false }
        return !processes(bundle).isEmpty
    }

    private let sink: (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void
    private(set) var running = false
    private(set) var rate: Double = 48000
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var interleaved = true
    private var channels = 2
    private let q = DispatchQueue(label: "proctap")
    init(sink: @escaping (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void) { self.sink = sink }

    private static func err(_ code: Int, _ m: String) -> NSError { NSError(domain: "ProcTap", code: code, userInfo: [NSLocalizedDescriptionKey: m]) }

    private static func prop<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ zero: T) -> T? {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = zero; var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    /// CoreAudio's process objects whose bundle id starts with `bundle` (the app and its helpers)
    static func processes(_ bundle: String) -> [(AudioObjectID, String, pid_t)] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        var out: [(AudioObjectID, String, pid_t)] = []
        for id in ids {
            let b = (prop(id, kAudioProcessPropertyBundleID, "" as CFString) as String?) ?? ""
            let pid = prop(id, kAudioProcessPropertyPID, pid_t(0)) ?? 0
            if b.hasPrefix(bundle) { out.append((id, b, pid)) }
        }
        return out
    }

    func start(bundle: String) async throws {
        let procs = Self.processes(bundle)
        guard !procs.isEmpty else { throw Self.err(1, "\(bundle) has no audio process (is it running?)") }
        let desc = CATapDescription(stereoMixdownOfProcesses: procs.map { $0.0 })
        desc.uuid = UUID(); desc.name = "Sound Recorder (Mantra) tap"; desc.isPrivate = true; desc.muteBehavior = .unmuted
        var t = AudioObjectID(kAudioObjectUnknown)
        var st = AudioHardwareCreateProcessTap(desc, &t)
        guard st == noErr, t != kAudioObjectUnknown else { throw Self.err(2, "the process tap was refused (\(st)): System Audio Recording not allowed?") }
        tapID = t
        // the tap's format
        var fa = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription(); var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(t, &fa, 0, nil, &sz, &asbd) == noErr {
            rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000
            interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            channels = max(1, Int(asbd.mChannelsPerFrame))
        }
        // a private aggregate device on the default output's clock, holding only the tap (the output is not changed)
        var outID = AudioObjectID(0); var osz = UInt32(MemoryLayout<AudioObjectID>.size)
        var oa = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &oa, 0, nil, &osz, &outID)
        let outUID = (Self.prop(outID, kAudioDevicePropertyDeviceUID, "" as CFString) as String?) ?? ""
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sound Recorder tap", kAudioAggregateDeviceUIDKey: "mantra.soundrecorder.tap." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID, kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]]]
        var a = AudioObjectID(kAudioObjectUnknown)
        st = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &a)
        guard st == noErr, a != kAudioObjectUnknown else { stop(); throw Self.err(3, "the aggregate device was refused (\(st))") }
        aggID = a
        let inter = interleaved, ch = channels, sink = self.sink
        var pid: AudioDeviceIOProcID?
        st = AudioDeviceCreateIOProcIDWithBlock(&pid, a, q) { _, inData, _, _, _ in
            let bufs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard bufs.count > 0, let d0 = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let n: Int
            if inter { n = Int(bufs[0].mDataByteSize) / (4 * max(1, Int(bufs[0].mNumberChannels))) } else { n = Int(bufs[0].mDataByteSize) / 4 }
            guard n > 0 else { return }
            let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
            defer { l.deallocate(); r.deallocate() }
            if inter {
                let c = max(1, Int(bufs[0].mNumberChannels))
                for i in 0..<n { l[i] = d0[i * c]; r[i] = d0[i * c + (c > 1 ? 1 : 0)] }
            } else {
                let d1 = bufs.count > 1 ? (bufs[1].mData?.assumingMemoryBound(to: Float.self) ?? d0) : d0
                for i in 0..<n { l[i] = d0[i]; r[i] = d1[i] }
            }
            _ = ch
            sink(l, r, n)
        }
        guard st == noErr, let p = pid else { stop(); throw Self.err(4, "no IOProc on the tap (\(st))") }
        procID = p
        st = AudioDeviceStart(a, p)
        guard st == noErr else { stop(); throw Self.err(5, "the tap would not start (\(st)): System Audio Recording not allowed?") }
        running = true
    }

    func stop() {
        running = false
        if let p = procID, aggID != kAudioObjectUnknown { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p) }
        procID = nil
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }
    deinit { stop() }
}
