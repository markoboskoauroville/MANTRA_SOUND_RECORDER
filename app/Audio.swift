// THE SOUND: the devices, the take, the meters.
//
// Marko, 31.10.2026: "a simple application which records audio, plays audio and then when I close the app deletes
// the audio." The take lives only in memory: nothing is written to the disk, so quitting (QUIT, OFF, ⌘Q, a crash)
// leaves nothing behind, and there is no file to forget to delete.
//
// CoreAudio IOProcs straight on the two devices, as Spectral Analyzer v5 learned: an AVAudioEngine switched to a
// device ran and delivered frames that were all 0.0 (SPECTRAL_ANALYZER Live.swift, 3.10.2026). The input runs
// whenever the microphone is allowed, so its meter always moves; the output runs only while the take plays.
import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import AppKit

struct Device: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let inputs: Int
    let outputs: Int
}

enum Devices {
    static func all() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { Device(id: $0, name: string($0, kAudioObjectPropertyName), uid: string($0, kAudioDevicePropertyDeviceUID),
                                inputs: channels($0, kAudioObjectPropertyScopeInput), outputs: channels($0, kAudioObjectPropertyScopeOutput)) }
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func rate(_ id: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var r = Float64(0); var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &r)
        return r > 0 ? r : 48000
    }

    private static func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var s: Unmanaged<CFString>? = nil; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &s) == noErr, let v = s else { return "?" }
        return v.takeRetainedValue() as String
    }

    private static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16); defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// v2, THE VOLUME (Marko, 31.10.2026: "I am missing the controlling input and output volume"): the device's own
/// volume, as SoundSource's sliders move it, so the volume keys and System Settings move the same slider. A device
/// with no volume of its own (BlackHole's input, some interfaces) gets the app's gain instead.
final class VolumeWatch {
    let dev: AudioDeviceID
    private let scope: AudioObjectPropertyScope
    private let elements: [UInt32]
    private var block: AudioObjectPropertyListenerBlock?

    init?(dev: AudioDeviceID, input: Bool, onChange: @escaping (Float) -> Void) {
        self.dev = dev
        scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var found: [UInt32] = []
        for e: UInt32 in 0...8 {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: e)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue {
                found.append(e)
                if e == 0 { break }                       // the main element is the whole device
            }
        }
        guard !found.isEmpty else { return nil }
        elements = found
        let blk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in if let v = self?.value { onChange(v) } }
        for e in elements {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: e)
            AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main, blk)
        }
        block = blk
    }

    deinit {
        guard let blk = block else { return }
        for e in elements {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: e)
            AudioObjectRemovePropertyListenerBlock(dev, &a, DispatchQueue.main, blk)
        }
    }

    var value: Float {
        var sum: Float = 0
        for e in elements {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: e)
            var v = Float32(0); var sz = UInt32(4)
            AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &v)
            sum += v
        }
        return sum / Float(elements.count)
    }

    func set(_ v: Float) {
        for e in elements {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: e)
            var x = Float32(v)
            AudioObjectSetPropertyData(dev, &a, 0, nil, 4, &x)
        }
    }
}

/// Stereo frames from the input's audio thread to the main thread (Spectral Analyzer's ring, as it is).
final class Ring {
    let cap = 1 << 19
    var l: [Float], r: [Float]
    private(set) var written: Int64 = 0
    private var lock = os_unfair_lock()
    init() { l = [Float](repeating: 0, count: cap); r = l }

    func write(_ pl: UnsafePointer<Float>, _ pr: UnsafePointer<Float>, _ n: Int) {
        os_unfair_lock_lock(&lock)
        var w = Int(written % Int64(cap))
        for i in 0..<n { l[w] = pl[i]; r[w] = pr[i]; w += 1; if w == cap { w = 0 } }
        written += Int64(n)
        os_unfair_lock_unlock(&lock)
    }

    func read(_ pos: inout Int64, _ ol: UnsafeMutablePointer<Float>, _ or: UnsafeMutablePointer<Float>, _ n: Int) -> Int {
        os_unfair_lock_lock(&lock)
        let w = written
        if w - pos > Int64(cap / 2) { pos = w - Int64(n) }
        let avail = Int(max(0, min(Int64(n), w - pos)))
        var p = Int(pos % Int64(cap))
        for i in 0..<avail { ol[i] = l[p]; or[i] = r[p]; p += 1; if p == cap { p = 0 } }
        os_unfair_lock_unlock(&lock)
        pos += Int64(avail)
        return avail
    }

    func fill() -> Int64 { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return written }
}

/// A stereo meter in dBFS: the bar falls 24 dB a second, the peak tick holds 1.5 s.
struct Meter {
    var l: Float = -90, r: Float = -90
    var holdL: Float = -90, holdR: Float = -90
    var holdAgeL = 0.0, holdAgeR = 0.0

    static func db(_ x: Float) -> Float { x > 0.00003 ? 20 * log10(x) : -90 }

    mutating func feed(_ pl: Float, _ pr: Float, dt: Double) {
        let fall = Float(24 * dt)
        l = max(Self.db(pl), l - fall); r = max(Self.db(pr), r - fall)
        holdAgeL += dt; holdAgeR += dt
        if l >= holdL || holdAgeL > 1.5 { holdL = l; holdAgeL = 0 }
        if r >= holdR || holdAgeR > 1.5 { holdR = r; holdAgeR = 0 }
    }
}

final class Recorder: ObservableObject {
    @Published var inputs: [Device] = []
    @Published var outputs: [Device] = []
    @Published private(set) var inUID = ""
    @Published private(set) var outUID = ""
    @Published private(set) var recording = false
    @Published private(set) var playing = false
    @Published private(set) var inMeter = Meter()
    @Published private(set) var outMeter = Meter()
    /// the take's waveform: the loudest sample of every `block` frames
    @Published private(set) var peaks: [Float] = []
    @Published private(set) var frames = 0
    /// where play starts or is, in frames of the take
    @Published private(set) var cursor: Double = 0
    @Published var error: String?
    static let block = 256

    private(set) var takeRate: Double = 48000
    private var takeL: [Float] = [], takeR: [Float] = []
    private var blockMax: Float = 0, blockN = 0

    // the input
    private var inDev: AudioDeviceID = 0, inProc: AudioDeviceIOProcID?
    private(set) var inRate: Double = 48000
    private let ring = Ring()
    private var readPos: Int64 = 0
    private var sL = [Float](repeating: 0, count: 16384), sR = [Float](repeating: 0, count: 16384)
    private var dL = [Float](repeating: 0, count: 16384), dR = [Float](repeating: 0, count: 16384)
    private var rawInL: Float = 0, rawInR: Float = 0

    // v2: the volumes, 0…1; on the device when it has one, otherwise the app's own gain (inSoft, outSoft)
    @Published private(set) var inVolume: Float = 1
    @Published private(set) var outVolume: Float = 1
    @Published private(set) var inOnDevice = false
    @Published private(set) var outOnDevice = false
    private var inWatch: VolumeWatch?, outWatch: VolumeWatch?
    private var inSoft: Float = 1, outSoft: Float = 1
    // read by the audio threads: plain flags, not the watch objects
    private var inWatchless: Bool { !inOnDeviceFlag }
    private var outWatchless: Bool { !outOnDeviceFlag }
    private var inOnDeviceFlag = false, outOnDeviceFlag = false

    // the output: a copy of the take the audio thread reads, at the output's own rate (linear interpolation)
    private var outDev: AudioDeviceID = 0, outProc: AudioDeviceIOProcID?
    private var pL: UnsafeMutablePointer<Float>?, pR: UnsafeMutablePointer<Float>?
    private var pN = 0
    private var pPos: Double = 0, pStep: Double = 1
    private var pDone = false
    private var rawOutL: Float = 0, rawOutR: Float = 0

    private let live: Bool
    private var timer: Timer?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    init(live: Bool = true) {
        self.live = live
        refreshDevices()
        let d = UserDefaults.standard
        inUID = pick(d.string(forKey: "input"), inputs, Devices.defaultDevice(input: true))
        outUID = pick(d.string(forKey: "output"), outputs, Devices.defaultDevice(input: false))
        if d.object(forKey: "inGain") != nil { inSoft = d.float(forKey: "inGain") }
        if d.object(forKey: "outGain") != nil { outSoft = d.float(forKey: "outGain") }
        watchVolumes()
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        guard live else { return }
        // a device plugged in or out: the menus follow, a vanished choice falls back to the Mac's default
        let blk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, blk)
        deviceListener = blk
        startInput()
    }

    private func pick(_ saved: String?, _ list: [Device], _ def: AudioDeviceID) -> String {
        if let s = saved, list.contains(where: { $0.uid == s }) { return s }
        return list.first(where: { $0.id == def })?.uid ?? list.first?.uid ?? ""
    }

    private func refreshDevices() {
        let all = Devices.all()
        inputs = all.filter { $0.inputs > 0 }
        outputs = all.filter { $0.outputs > 0 }
    }

    private func devicesChanged() {
        refreshDevices()
        let i = pick(inUID, inputs, Devices.defaultDevice(input: true))
        let o = pick(outUID, outputs, Devices.defaultDevice(input: false))
        if i != inUID { if recording { stopRecording() }; inUID = i; startInput() }
        if o != outUID { stopPlaying(); outUID = o }
        watchVolumes()
    }

    // ---------------------------------------------------------------- the volumes
    private func watchVolumes() {
        let i = inputs.first { $0.uid == inUID }, o = outputs.first { $0.uid == outUID }
        if inWatch?.dev != i?.id || (inWatch == nil && i != nil) {
            inWatch = i.flatMap { VolumeWatch(dev: $0.id, input: true) { [weak self] v in self?.inVolume = v } }
        }
        if outWatch?.dev != o?.id || (outWatch == nil && o != nil) {
            outWatch = o.flatMap { VolumeWatch(dev: $0.id, input: false) { [weak self] v in self?.outVolume = v } }
        }
        inOnDevice = inWatch != nil; outOnDevice = outWatch != nil
        inOnDeviceFlag = inOnDevice; outOnDeviceFlag = outOnDevice
        inVolume = inWatch?.value ?? inSoft
        outVolume = outWatch?.value ?? outSoft
    }

    func setVolume(input: Bool, _ v: Float) {
        let v = min(max(v, 0), 1)
        if input {
            if let w = inWatch { w.set(v) } else { inSoft = v; if live { UserDefaults.standard.set(v, forKey: "inGain") } }
            inVolume = v
        } else {
            if let w = outWatch { w.set(v) } else { outSoft = v; if live { UserDefaults.standard.set(v, forKey: "outGain") } }
            outVolume = v
        }
    }

    // ---------------------------------------------------------------- choosing
    func chooseInput(_ uid: String) {
        guard uid != inUID, !recording else { return }
        inUID = uid
        if live { UserDefaults.standard.set(uid, forKey: "input") }
        watchVolumes()
        startInput()
    }

    func chooseOutput(_ uid: String) {
        guard uid != outUID else { return }
        let was = playing
        stopPlaying()
        outUID = uid
        if live { UserDefaults.standard.set(uid, forKey: "output") }   // a test never changes his choice
        watchVolumes()
        if was { play() }
    }

    func chooseOutput(named part: String) -> Bool {
        guard let d = outputs.first(where: { $0.name.localizedCaseInsensitiveContains(part) }) else { return false }
        chooseOutput(d.uid)
        return true
    }

    var inputName: String { inputs.first { $0.uid == inUID }?.name ?? "no input" }
    var outputName: String { outputs.first { $0.uid == outUID }?.name ?? "no output" }

    /// the window asks every 2 s; the microphone allowed while the app runs starts the input at once
    func permissionsChanged() { if live && inProc == nil { startInput() } }

    // ---------------------------------------------------------------- the input
    private func startInput() {
        stopInput()
        guard live, Permissions.allowed("Microphone"),
              let dev = inputs.first(where: { $0.uid == inUID }) else { return }
        inDev = dev.id
        inRate = Devices.rate(dev.id)
        var ip: AudioDeviceIOProcID?
        var st = AudioDeviceCreateIOProcIDWithBlock(&ip, inDev, nil) { [weak self] _, inData, _, _, _ in
            guard let self = self else { return }
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard list.count > 0, let d0 = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let ch0 = Int(list[0].mNumberChannels)
            let n = Int(list[0].mDataByteSize) / 4 / max(1, ch0)
            if n == 0 || n > self.sL.count { return }
            var pl: Float = 0, pr: Float = 0
            self.sL.withUnsafeMutableBufferPointer { l in
                self.sR.withUnsafeMutableBufferPointer { r in
                    if ch0 >= 2 {
                        for i in 0..<n { l[i] = d0[i * ch0]; r[i] = d0[i * ch0 + 1] }
                    } else if list.count >= 2, let d1 = list[1].mData?.assumingMemoryBound(to: Float.self) {
                        for i in 0..<n { l[i] = d0[i]; r[i] = d1[i] }
                    } else {
                        for i in 0..<n { l[i] = d0[i]; r[i] = d0[i] }     // a mono microphone: the same on both sides
                    }
                    let g = self.inWatchless ? self.inSoft : 1
                    if g != 1 { for i in 0..<n { l[i] *= g; r[i] *= g } }
                    for i in 0..<n { pl = max(pl, abs(l[i])); pr = max(pr, abs(r[i])) }
                    self.ring.write(l.baseAddress!, r.baseAddress!, n)
                }
            }
            self.rawInL = max(self.rawInL, pl); self.rawInR = max(self.rawInR, pr)
        }
        if st != noErr || ip == nil { error = "the input would not open (\(st))"; return }
        inProc = ip
        st = AudioDeviceStart(inDev, ip)
        if st != noErr { error = "the input would not start (\(st))"; stopInput(); return }
        error = nil
    }

    private func stopInput() {
        if let p = inProc { AudioDeviceStop(inDev, p); AudioDeviceDestroyIOProcID(inDev, p) }
        inProc = nil
        rawInL = 0; rawInR = 0
    }

    var canRecord: Bool { inProc != nil && !playing }

    // ---------------------------------------------------------------- recording
    func toggleRecord() { recording ? stopRecording() : record() }

    func record() {
        guard !playing else { return }
        guard inProc != nil else { Permissions.openMissing(); return }
        takeL = []; takeR = []; peaks = []; frames = 0; cursor = 0
        blockMax = 0; blockN = 0
        takeRate = inRate
        takeL.reserveCapacity(Int(takeRate) * 60); takeR.reserveCapacity(Int(takeRate) * 60)
        readPos = ring.fill()
        recording = true
    }

    func stopRecording() {
        guard recording else { return }
        drain()
        if blockN > 0 { peaks.append(blockMax); blockMax = 0; blockN = 0 }
        recording = false
        cursor = 0
    }

    /// what the input wrote since the last tick, into the take and its waveform
    private func drain() {
        while true {
            let n = dL.withUnsafeMutableBufferPointer { l in
                dR.withUnsafeMutableBufferPointer { r in ring.read(&readPos, l.baseAddress!, r.baseAddress!, l.count) }
            }
            if n == 0 { break }
            takeL.append(contentsOf: dL[0..<n]); takeR.append(contentsOf: dR[0..<n])
            var add: [Float] = []
            for i in 0..<n {
                blockMax = max(blockMax, abs(dL[i]), abs(dR[i])); blockN += 1
                if blockN == Self.block { add.append(blockMax); blockMax = 0; blockN = 0 }
            }
            if !add.isEmpty { peaks.append(contentsOf: add) }
            frames = takeL.count
        }
    }

    // ---------------------------------------------------------------- playing
    var canPlay: Bool { frames > 1 && !recording }

    func togglePlay() { playing ? stopPlaying() : play() }

    func play() {
        guard canPlay, !playing, let dev = outputs.first(where: { $0.uid == outUID }) else { return }
        if cursor >= Double(frames - 2) { cursor = 0 }
        let l = UnsafeMutablePointer<Float>.allocate(capacity: frames), r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        takeL.withUnsafeBufferPointer { l.update(from: $0.baseAddress!, count: frames) }
        takeR.withUnsafeBufferPointer { r.update(from: $0.baseAddress!, count: frames) }
        pL = l; pR = r; pN = frames
        pPos = cursor; pStep = takeRate / Devices.rate(dev.id); pDone = false
        outDev = dev.id
        var op: AudioDeviceIOProcID?
        var st = AudioDeviceCreateIOProcIDWithBlock(&op, outDev, nil) { [weak self] _, _, _, outData, _ in
            guard let self = self, let L = self.pL, let R = self.pR else { return }
            let list = UnsafeMutableAudioBufferListPointer(outData)
            guard list.count > 0, let o0 = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let ch = Int(list[0].mNumberChannels)
            let n = Int(list[0].mDataByteSize) / 4 / max(1, ch)
            let o1: UnsafeMutablePointer<Float>? = (ch == 1 && list.count >= 2) ? list[1].mData?.assumingMemoryBound(to: Float.self) : nil
            for b in (o1 == nil ? 1 : 2)..<max(list.count, o1 == nil ? 1 : 2) {
                if let m = list[b].mData { memset(m, 0, Int(list[b].mDataByteSize)) }
            }
            var pos = self.pPos
            let step = self.pStep, N = self.pN
            var pl: Float = 0, pr: Float = 0
            let g = self.outWatchless ? self.outSoft : 1
            for i in 0..<n {
                var l: Float = 0, r: Float = 0
                let k = Int(pos)
                if k + 1 < N {
                    let f = Float(pos - Double(k))
                    l = L[k] + (L[k + 1] - L[k]) * f; r = R[k] + (R[k + 1] - R[k]) * f
                    pos += step
                    l *= g; r *= g
                } else { self.pDone = true }
                pl = max(pl, abs(l)); pr = max(pr, abs(r))
                if ch >= 2 {
                    o0[i * ch] = l; o0[i * ch + 1] = r
                    if ch > 2 { for c in 2..<ch { o0[i * ch + c] = 0 } }
                } else if let o1 = o1 {
                    o0[i] = l; o1[i] = r
                } else {
                    o0[i] = (l + r) / 2
                }
            }
            self.pPos = pos
            self.rawOutL = max(self.rawOutL, pl); self.rawOutR = max(self.rawOutR, pr)
        }
        if st != noErr || op == nil { error = "the output would not open (\(st))"; freePlayback(); return }
        outProc = op
        st = AudioDeviceStart(outDev, op)
        if st != noErr { error = "the output would not start (\(st))"; stopPlaying(); return }
        error = nil
        playing = true
    }

    func stopPlaying() {
        if let p = outProc { AudioDeviceStop(outDev, p); AudioDeviceDestroyIOProcID(outDev, p) }
        outProc = nil
        if pL != nil { cursor = min(pPos, Double(frames)) }
        freePlayback()
        playing = false
    }

    private func freePlayback() {
        pL?.deallocate(); pR?.deallocate(); pL = nil; pR = nil; pN = 0
    }

    /// a click on the waveform: play from there
    func seek(_ fraction: Double) {
        guard frames > 1, !recording else { return }
        let f = min(max(fraction, 0), 1) * Double(frames - 1)
        if playing { pPos = f }
        cursor = f
    }

    var seconds: Double { Double(frames) / takeRate }
    var position: Double { cursor / takeRate }

    // ---------------------------------------------------------------- 30 times a second
    private func tick() {
        let dt = 1.0 / 30
        if recording { drain() }
        if playing {
            cursor = pPos
            if pDone { stopPlaying(); cursor = 0 }
        }
        var m = inMeter; m.feed(rawInL, rawInR, dt: dt); rawInL = 0; rawInR = 0; inMeter = m
        var o = outMeter; o.feed(rawOutL, rawOutR, dt: dt); rawOutL = 0; rawOutR = 0; outMeter = o
    }

    // ---------------------------------------------------------------- the end
    /// QUIT, OFF, ⌘Q: the devices let go and the take is forgotten. It was never on the disk.
    func forget() {
        stopPlaying()
        stopInput()
        recording = false
        takeL = []; takeR = []; peaks = []; frames = 0; cursor = 0
    }

    // ---------------------------------------------------------------- tests
    /// a take made of sound instead of a microphone: a 440 Hz tone at -12 dBFS that swells and fades
    func loadTestTake(seconds s: Double = 6) {
        takeRate = 48000
        let n = Int(takeRate * s)
        takeL = [Float](repeating: 0, count: n); takeR = takeL
        for i in 0..<n {
            let t = Double(i) / takeRate
            let env = 0.55 + 0.45 * sin(t * 1.7) * sin(t * 0.6 + 0.4)
            let v = Float(0.25 * env * sin(2 * .pi * 440 * t))
            takeL[i] = v; takeR[i] = v * 0.8
        }
        frames = n
        peaks = stride(from: 0, to: n, by: Self.block).map { s in
            var m: Float = 0
            for i in s..<min(n, s + Self.block) { m = max(m, abs(takeL[i]), abs(takeR[i])) }
            return m
        }
        cursor = 0
    }

    /// for the picture only: as if it were playing at `fraction`, the meters showing these levels
    func pose(fraction: Double, inDB: (Float, Float), outDB: (Float, Float)) {
        cursor = fraction * Double(frames)
        playing = true
        inMeter = Meter(l: inDB.0, r: inDB.1, holdL: inDB.0 + 3, holdR: inDB.1 + 2)
        outMeter = Meter(l: outDB.0, r: outDB.1, holdL: outDB.0 + 2, holdR: outDB.1 + 4)
        timer?.invalidate()
    }
}

// MANTRA_MANIFEST swift-apps.md, PERMISSIONS: the one this app uses is the microphone (every input device, BlackHole too).
enum Permissions {
    static let needed = ["Microphone"]
    static func allowed(_ p: String) -> Bool {
        switch p {
        case "Microphone": return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        default: return true
        }
    }
    static var missing: [String] { needed.filter { !allowed($0) } }
    static func openMissing() {
        guard let p = missing.first else { return }
        if p == "Microphone" {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }      // the system's own question, once
                return
            }
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + p)!)
    }
}
