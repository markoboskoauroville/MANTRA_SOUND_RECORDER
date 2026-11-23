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
import ScreenCaptureKit
import CoreMedia

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

    /// v17: the usual rates this device really offers (kAudioDevicePropertyAvailableNominalSampleRates), ascending
    static let standardRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
    static func supportedRates(_ id: AudioDeviceID) -> [Double] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyAvailableNominalSampleRates, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var rs = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &rs) == noErr else { return [] }
        return standardRates.filter { s in rs.contains { s >= $0.mMinimum - 0.5 && s <= $0.mMaximum + 0.5 } }
    }

    /// v17: asks the device for a nominal rate and waits up to half a second for it to say it took it
    static func setRate(_ id: AudioDeviceID, _ want: Double) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = Float64(want)
        guard AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &v) == noErr else { return false }
        for _ in 0..<20 {
            if abs(rate(id) - want) < 0.5 { return true }
            Thread.sleep(forTimeInterval: 0.025)
        }
        return abs(rate(id) - want) < 0.5
    }

    private static func u32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var v = UInt32(0); var sz = UInt32(4)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v) == noErr ? Int(v) : 0
    }

    /// v16: what the device and its first stream add on their own, in frames: latency + safety offset + stream latency
    static func latencyFrames(_ id: AudioDeviceID, input: Bool) -> Int {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var total = u32(id, kAudioDevicePropertyLatency, scope) + u32(id, kAudioDevicePropertySafetyOffset, scope)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size >= 4 {
            var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ids) == noErr, let s = ids.first {
                total += u32(s, kAudioStreamPropertyLatency, kAudioObjectPropertyScopeGlobal)
            }
        }
        return total
    }

    /// v16: the device's buffer size range (frames), when it says it
    static func bufferRange(_ id: AudioDeviceID) -> (Int, Int)? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSizeRange, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var r = AudioValueRange(); var sz = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &r) == noErr, r.mMaximum >= r.mMinimum, r.mMaximum > 0 else { return nil }
        return (Int(r.mMinimum), Int(r.mMaximum))
    }

    static func bufferFrames(_ id: AudioDeviceID) -> Int { u32(id, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal) }

    /// v16: asks for `want` frames, clamped to the device's range; returns what the device now says, nil when it refused
    static func setBuffer(_ id: AudioDeviceID, _ want: Int) -> Int? {
        var n = want
        if let r = bufferRange(id) { n = min(max(n, r.0), r.1) }
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = UInt32(n)
        let st = AudioObjectSetPropertyData(id, &a, 0, nil, 4, &v)
        let now = bufferFrames(id)
        if st != noErr && now == 0 { return nil }
        return now > 0 ? now : (st == noErr ? n : nil)
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

    /// v3, for the auto gain: the device's volume in dB and its range, when it says them
    var decibels: Float? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeDecibels, mScope: scope, mElement: elements[0])
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { return nil }
        var v = Float32(0); var sz = UInt32(4)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &v) == noErr ? v : nil
    }

    var dbRange: (Float, Float)? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeRangeDecibels, mScope: scope, mElement: elements[0])
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var r = AudioValueRange(); var sz = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &r) == noErr, r.mMaximum > r.mMinimum else { return nil }
        return (Float(r.mMinimum), Float(r.mMaximum))
    }

    func setDecibels(_ db: Float) {
        for e in elements {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeDecibels, mScope: scope, mElement: e)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { continue }
            var x = Float32(db)
            AudioObjectSetPropertyData(dev, &a, 0, nil, 4, &x)
        }
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

/// One recording: its frames, its waveform, where its playhead is. v3 (Marko, 31.10.2026: "every time I record the new
/// waveform is opening up ... so I can easily compare recordings"): the session keeps every take, in memory only.
final class Take: Identifiable {
    let id: Int
    let rate: Double
    /// v17: the bit depth SAVE writes (16, 24, or 32 = float), fixed when the take starts
    let bits: Int
    var l: [Float] = [], r: [Float] = []
    var peaks: [Float] = []
    var cursor: Double = 0
    /// v5: where SAVE last wrote it
    var savedTo: URL?
    let made = Date()
    init(id: Int, rate: Double, bits: Int = 24) { self.id = id; self.rate = rate; self.bits = bits }
    var frames: Int { l.count }
    var seconds: Double { Double(frames) / rate }
    var position: Double { cursor / rate }
}

/// CQ's Gain Assistant, step by step (the "KAuto Gain Steps" of CQ MixPad): ? listening, gear adjusting, ✓ done, ! failed.
enum GainStep: Equatable { case idle, listening, adjusting, done, failed }

final class Recorder: ObservableObject {
    @Published var inputs: [Device] = []
    @Published var outputs: [Device] = []
    @Published private(set) var inUID = ""
    @Published private(set) var outUID = ""
    @Published private(set) var recording = false
    @Published private(set) var inMeter = Meter()
    @Published private(set) var outMeter = Meter()
    @Published var error: String?
    static let block = 256

    /// the takes of this session, oldest first; the one being recorded is `current` until it stops
    @Published private(set) var takes: [Take] = []
    @Published private(set) var current: Take?
    @Published private(set) var playingID: Int?
    /// Space plays this one: the last played, or the newest
    private(set) var lastID: Int?
    private var nextID = 1
    var nextNumber: Int { nextID }
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
    // v10 (Marko, 1.11.2026: "gain can be above 100% while using the auto gain"): the app's own boost on top of the
    // input's volume, 1 = none, up to maxBoost (v11: +32 dB). The auto gain raises it once the volume is at its top,
    // and the slider right of its 0 dB mark. Shown in dB (v11), never in %.
    @Published private(set) var inBoost: Float = 1
    // v11 (Marko, 1.11.2026: "maximum ... over the scale of 0 dB is 32 dB ... and I can do it also with the slider")
    static let maxBoostDB: Float = 32
    static let maxBoost: Float = pow(10, maxBoostDB / 20)
    /// v11 (Marko, 1.11.2026: "slider always reflects ... the level of dBs. It's an indicator"): the sliders are a dB
    /// scale, -60 dB at the left (the far left is silence), the device's top, then for the input the boost to +32 dB.
    static let sliderLow: Float = -60
    private func devTopDB(input: Bool) -> Float { ((input ? inWatch : outWatch)?.dbRange?.1) ?? 0 }
    func sliderHigh(input: Bool) -> Float { input ? max(Self.maxBoostDB, devTopDB(input: true)) : devTopDB(input: false) }
    /// where the 0 dB mark sits on the slider (only the input has room above it)
    var inZeroAt: Float { (0 - Self.sliderLow) / (sliderHigh(input: true) - Self.sliderLow) }
    func sliderPos(input: Bool) -> Float {
        guard let d = gainDB(input: input) else { return 0 }
        return min(max((d - Self.sliderLow) / (sliderHigh(input: input) - Self.sliderLow), 0), 1)
    }
    func setSlider(input: Bool, _ p: Float) {
        let p = min(max(p, 0), 1)
        let w = input ? inWatch : outWatch
        if p < 0.005 { if input { setBoost(1) }; setVolume(input: input, 0); return }
        let db = Self.sliderLow + p * (sliderHigh(input: input) - Self.sliderLow)
        let top = devTopDB(input: input)
        let devDB = min(db, top)
        if input { setBoost(pow(10, min(max(db - top, 0), Self.maxBoostDB) / 20)) }
        if let w = w, let r = w.dbRange, w.decibels != nil {
            w.setDecibels(min(max(devDB, r.0), r.1))
            if input { inVolume = w.value } else { outVolume = w.value }
        } else {
            let v = min(pow(10, devDB / 20), 1)
            if input { setInput(v) } else { setVolume(input: false, v) }
        }
    }
    // read by the audio threads: plain flags, not the watch objects
    private var inOnDeviceFlag = false, outOnDeviceFlag = false

    // the output: a copy of the playing take the audio thread reads, at the output's own rate (linear interpolation)
    private var outDev: AudioDeviceID = 0, outProc: AudioDeviceIOProcID?
    private var playingTake: Take?
    private var pL: UnsafeMutablePointer<Float>?, pR: UnsafeMutablePointer<Float>?
    private var pN = 0
    private var pPos: Double = 0, pStep: Double = 1
    private var pDone = false
    private var rawOutL: Float = 0, rawOutR: Float = 0

    // v16, INPUT MONITORING (Marko, 24.11.2026: "Listen to me on the input when I click on the icon of the microphone"):
    // a second, lock-free ring (one writer: the input's audio thread, one reader: the output's) that the output IOProc mixes
    // into what it plays. Nothing is allocated and no lock is taken on either thread; the counters are 64-bit words
    // published with a memory barrier.
    static let monitorSizes = [32, 64, 128, 256, 512, 1024]
    @Published private(set) var monitorOn = false
    @Published private(set) var monitorBuf = 128
    @Published private(set) var monitorNote: String?
    @Published private(set) var monitorInfo: String?
    private static let monCap = 1 << 15, monMask = (1 << 15) - 1
    private let monL = UnsafeMutablePointer<Float>.allocate(capacity: Recorder.monCap)
    private let monR = UnsafeMutablePointer<Float>.allocate(capacity: Recorder.monCap)
    private let monW = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private var monFlag = false                      // read by the audio threads
    private var monChunk = 0                         // the writer's last chunk, in frames
    private var mPos: Double = 0, mStep: Double = 1, mPrimed = false   // the reader's own state

    // v17, RECORDING FORMAT (Marko, 24.11.2026: "options of Sound Recorder quality, number of bits, and sample rate"):
    // bits 16 / 24 / 32 float for the saved WAV, the input's sample rate (0 = Auto: whatever the device runs at), and a
    // quality preset that sets both. The take is held as 32-bit float; the bits are applied when SAVE writes it.
    static let bitOptions = [16, 24, 32]
    struct Preset { let id: String, name: String, bits: Int, rate: Double }
    static let presets: [Preset] = [
        Preset(id: "cd", name: "CD: 16 bit / 44.1 kHz", bits: 16, rate: 44100),
        Preset(id: "standard", name: "Standard: 24 bit / 48 kHz", bits: 24, rate: 48000),
        Preset(id: "studio", name: "Studio: 24 bit / 96 kHz", bits: 24, rate: 96000),
        Preset(id: "max", name: "Max: 32 bit float / 192 kHz (or the device's top)", bits: 32, rate: 192000),
    ]
    @Published private(set) var recBits = 24
    @Published private(set) var recRate: Double = 0
    @Published private(set) var recQuality = "custom"
    @Published private(set) var rateNote: String?
    @Published private(set) var availRates: [Double] = []
    var rateLocked: Bool { inUID.hasPrefix("app:") }

    // v3: auto gain
    @Published private(set) var gain: GainStep = .idle
    @Published private(set) var gainNote: String?
    static let gainTarget: Float = -12           // the loudest peak, dBFS: where the meter turns from green to amber
    private var gStart = Date(), gPeak: Float = -90, gRound = 0, gListenStart = Date()

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
        if d.object(forKey: "inBoost") != nil { inBoost = min(max(d.float(forKey: "inBoost"), 1), Self.maxBoost) }
        if live {
            if d.object(forKey: "recBits") != nil, Self.bitOptions.contains(d.integer(forKey: "recBits")) { recBits = d.integer(forKey: "recBits") }
            if d.object(forKey: "recRate") != nil { let r = d.double(forKey: "recRate"); recRate = Devices.standardRates.contains(r) ? r : 0 }
            if let q = d.string(forKey: "recQuality"), q == "custom" || Self.presets.contains(where: { $0.id == q }) { recQuality = q }
        }
        monW.initialize(to: 0); monL.initialize(repeating: 0, count: Self.monCap); monR.initialize(repeating: 0, count: Self.monCap)
        if live {
            monitorOn = d.bool(forKey: "monitorOn")
            if d.object(forKey: "monitorBuf") != nil, Self.monitorSizes.contains(d.integer(forKey: "monitorBuf")) { monitorBuf = d.integer(forKey: "monitorBuf") }
        }
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
        if let s = saved, list.contains(where: { $0.uid == s }) || (s.hasPrefix("app:") && !s.isEmpty && saved != nil) { return saved! }
        return list.first(where: { $0.id == def })?.uid ?? list.first?.uid ?? ""
    }

    private func refreshDevices() {
        let all = Devices.all()
        // v15 (Marko, 10.11.2026: "don't mention black hole. Just write in the inputs: "App audio" in the parentheses. Which
        // app is that"): the app sources read "App audio (<app>)", and the BlackHole device is not offered as an input
        inputs = all.filter { $0.inputs > 0 && !$0.name.localizedCaseInsensitiveContains("blackhole") }
            + [Device(id: 0, name: "App audio (Google Chrome)", uid: Recorder.chromeUID, inputs: 2, outputs: 0),
               Device(id: 0, name: "App audio (Firefox)", uid: Recorder.fireUID, inputs: 2, outputs: 0)]
        outputs = [Device(id: 0, name: "None (no output)", uid: "none", inputs: 0, outputs: 2)] + all.filter { $0.outputs > 0 }
    }

    private func devicesChanged() {
        refreshDevices()
        let i = pick(inUID, inputs, Devices.defaultDevice(input: true))
        let o = pick(outUID, outputs, Devices.defaultDevice(input: false))
        if i != inUID { if recording { stopRecording() }; stopAutoGain(); inUID = i; startInput() }
        if o != outUID { pause(restart: false); outUID = o; applyMonitor() }
        watchVolumes()
    }

    // ---------------------------------------------------------------- the volumes
    private func watchVolumes() {
        let i = inputs.first { $0.uid == inUID && $0.id != 0 }, o = outputs.first { $0.uid == outUID && $0.id != 0 }
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
            setBoost(1)                                   // by hand: the slider is the whole gain again
            setInput(v)
        } else {
            if let w = outWatch { w.set(v) } else { outSoft = v; if live { UserDefaults.standard.set(v, forKey: "outGain") } }
            outVolume = v
        }
    }

    private func setInput(_ v: Float) {
        if let w = inWatch { w.set(v) } else { inSoft = v; if live { UserDefaults.standard.set(v, forKey: "inGain") } }
        inVolume = v
    }

    func setBoost(_ b: Float) {
        inBoost = min(max(b, 1), Self.maxBoost)
        if live { UserDefaults.standard.set(inBoost, forKey: "inBoost") }
    }

    /// v11 (Marko, 1.11.2026: "convert percentage ... to dB"): the whole gain in dB as the window shows it, the device's
    /// own dB when it says them (else 20·log10 of the volume), plus the boost; nil = silent (−∞)
    func gainDB(input: Bool) -> Float? {
        let w = input ? inWatch : outWatch, v = input ? inVolume : outVolume
        let base: Float? = w?.decibels ?? (v > 0.0001 ? 20 * log10(v) : nil)
        guard let b = base else { return nil }
        return b + (input ? 20 * log10(inBoost) : 0)
    }
    var inGainText: String { Self.dbText(gainDB(input: true)) }
    static func dbText(_ d: Float?) -> String {
        guard let d = d else { return "−∞ dB" }
        let r = (d * 10).rounded() / 10
        return r == 0 ? "0.0 dB" : String(format: "%@%.1f dB", r > 0 ? "+" : "−", abs(r))
    }

    // ---------------------------------------------------------------- choosing
    func chooseInput(_ uid: String) {
        guard uid != inUID, !recording else { return }
        stopAutoGain()
        setBoost(1)
        inUID = uid
        if live { UserDefaults.standard.set(uid, forKey: "input") }
        watchVolumes()
        startInput()
    }

    func chooseOutput(_ uid: String) {
        guard uid != outUID else { return }
        let was = playingTake
        pause(restart: false)
        outUID = uid
        if live { UserDefaults.standard.set(uid, forKey: "output") }   // a test never changes his choice
        watchVolumes()
        applyMonitor()
        if let t = was { play(t) }
    }

    func chooseInput(named part: String) -> Bool {
        // the tests (--gain-test BlackHole) may name a device the menu hides: look in every device
        guard let d = (inputs + Devices.all().filter { $0.inputs > 0 }).first(where: { $0.name.localizedCaseInsensitiveContains(part) }) else { return false }
        chooseInput(d.uid)
        return true
    }

    var inputVolumeOnDevice: Float? { inWatch?.value }
    func setInputVolumeOnDevice(_ v: Float) { inWatch?.set(v) }

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
    private var tap: AppSource?
    /// 10.11.2026 (task 89): Firefox's own sound through ScreenCaptureKit, in place of a device. The system's output and
    /// input are never touched, so the voice engine (its own process) can never get into the take.
    var appGain: Float = 0.708                         // -3 dB headroom: the Suno masters peak at 0 dBFS
    @Published private(set) var appError: String?

    private func startApp() {
        let sinkFn: (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void = { [weak self] l, r, n in
            guard let self = self else { return }
            let g = self.appGain
            var pl: Float = 0, pr: Float = 0
            let ml = UnsafeMutablePointer<Float>.allocate(capacity: n), mr = UnsafeMutablePointer<Float>.allocate(capacity: n)
            for i in 0..<n { ml[i] = l[i] * g; mr[i] = r[i] * g; pl = max(pl, abs(ml[i])); pr = max(pr, abs(mr[i])) }
            self.ring.write(ml, mr, n)
            if self.monFlag { self.monitorWrite(ml, mr, n) }
            ml.deallocate(); mr.deallocate()
            self.rawInL = max(self.rawInL, pl); self.rawInR = max(self.rawInR, pr)
        }
        let bundle = String(self.inUID.dropFirst(4))
        // v14: Chrome plays everything from its AudioService helper, which ScreenCaptureKit does not give to Chrome:
        // a CoreAudio process tap on all of Chrome's processes. Other apps keep ScreenCaptureKit (as OBS).
        let t: AppSource = ProcTap.wanted(bundle) ? ProcTap(sink: sinkFn) : AppTap(sink: sinkFn)
        tap = t
        inRate = 48000
        availRates = []; rateNote = nil
        Task { @MainActor in
            do { try await t.start(bundle: bundle); self.inRate = t.rate; self.appError = nil; self.error = nil }
            catch { self.appError = "\(self.inUID.contains("Chrome") ? "Chrome" : "Firefox") audio would not start: \(error.localizedDescription). \(t is ProcTap ? "System Audio Recording" : "Screen Recording") must be allowed for this app."
                    self.error = self.appError; self.tap = nil }
        }
    }
    var elapsedNow: Double { current?.seconds ?? 0 }
    var inLevelDB: Float { inMeter.holdL }
    var appReady: Bool { tap?.running == true }

    private func startInput() {
        stopInput()
        defer { applyMonitor() }
        if inUID.hasPrefix("app:") { guard live else { return }; startApp(); return }
        if live { applyRate() }
        guard live, !inUID.hasPrefix("app:"), Permissions.allowed("Microphone"),
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
                    let g = (self.inOnDeviceFlag ? 1 : self.inSoft) * self.inBoost
                    if g != 1 { for i in 0..<n { l[i] *= g; r[i] *= g } }
                    for i in 0..<n { pl = max(pl, abs(l[i])); pr = max(pr, abs(r[i])) }
                    self.ring.write(l.baseAddress!, r.baseAddress!, n)
                    if self.monFlag { self.monitorWrite(l.baseAddress!, r.baseAddress!, n) }
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
        tap?.stop(); tap = nil
        rawInL = 0; rawInR = 0
    }

    var canRecord: Bool { inProc != nil || appReady }

    // ---------------------------------------------------------------- recording
    func toggleRecord() { recording ? stopRecording() : record() }

    /// a take that did not finish is deleted from the session, never kept
    func discard(_ t: Take) { takes.removeAll { $0.id == t.id }; if let u = t.savedTo { try? FileManager.default.removeItem(at: u) } }

    func record(preroll: Double = 0) {
        guard !recording else { return }
        guard inProc != nil || appReady else { if !inUID.hasPrefix("app:") { Permissions.openMissing() }; return }
        pause()
        stopAutoGain()
        if let d = inputs.first(where: { $0.uid == inUID && $0.id != 0 }), !inUID.hasPrefix("app:") { inRate = Devices.rate(d.id) }   // v17: the rate the device really runs at
        let t = Take(id: nextID, rate: inRate, bits: recBits)
        t.l.reserveCapacity(Int(inRate) * 60); t.r.reserveCapacity(Int(inRate) * 60)
        current = t
        blockMax = 0; blockN = 0
        readPos = max(0, ring.fill() - Int64(preroll * inRate))
        recording = true
        if !inUID.hasPrefix("app:") { RecordingFlag.set(true) }     // only a system-wide input holds the voice; the per-app Firefox capture never hears it
    }

    /// the take joins the list, and the empty row below it waits for the next one
    func stopRecording() {
        guard recording, let t = current else { return }
        drain()
        if blockN > 0 { t.peaks.append(blockMax); blockMax = 0; blockN = 0 }
        recording = false
        RecordingFlag.set(false)
        current = nil
        if t.frames > 1 { takes.append(t); lastID = t.id; nextID += 1 }
    }

    /// what the input wrote since the last tick, into the take and its waveform
    private func drain() {
        guard let t = current else { return }
        while true {
            let n = dL.withUnsafeMutableBufferPointer { l in
                dR.withUnsafeMutableBufferPointer { r in ring.read(&readPos, l.baseAddress!, r.baseAddress!, l.count) }
            }
            if n == 0 { break }
            t.l.append(contentsOf: dL[0..<n]); t.r.append(contentsOf: dR[0..<n])
            for i in 0..<n {
                blockMax = max(blockMax, abs(dL[i]), abs(dR[i])); blockN += 1
                if blockN == Self.block { t.peaks.append(blockMax); blockMax = 0; blockN = 0 }
            }
        }
    }

    // ---------------------------------------------------------------- playing: a click on a take
    func toggle(_ t: Take) { playingID == t.id ? pause() : play(t) }

    /// Space: the last one played, or the newest
    func toggleLast() {
        if playingID != nil { pause(); return }
        if let t = takes.first(where: { $0.id == lastID }) ?? takes.last { play(t) }
    }

    /// ⌘-click: jump there, and play from there
    func jump(_ t: Take, _ fraction: Double) {
        guard t.frames > 1 else { return }
        let f = min(max(fraction, 0), 1) * Double(t.frames - 1)
        t.cursor = f
        if playingID == t.id { pPos = f } else { play(t) }
        objectWillChange.send()
    }

    func play(_ t: Take) {
        guard !recording, t.frames > 1, let dev = outputs.first(where: { $0.uid == outUID }), dev.id != 0 else { return }
        pause(restart: false)
        if t.cursor >= Double(t.frames - 2) { t.cursor = 0 }
        let n = t.frames
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        t.l.withUnsafeBufferPointer { l.update(from: $0.baseAddress!, count: n) }
        t.r.withUnsafeBufferPointer { r.update(from: $0.baseAddress!, count: n) }
        pL = l; pR = r; pN = n
        pPos = t.cursor; pStep = t.rate / Devices.rate(dev.id); pDone = false
        playingTake = t
        if !startOutputProc() { playingTake = nil; freePlayback(); return }
        error = nil
        playingID = t.id; lastID = t.id
    }

    /// the playhead stays where it stopped; the next click goes on from there. v16: monitoring goes on (the proc is made
    /// again without the take) unless `restart` is false.
    func pause(restart: Bool = true) {
        stopOutputProc()
        if let t = playingTake { t.cursor = min(pPos, Double(t.frames)) }
        freePlayback()
        playingTake = nil; playingID = nil
        if restart && live && monitorOn && monFlag { startOutputProc() }
    }

    private func freePlayback() {
        pL?.deallocate(); pR?.deallocate(); pL = nil; pR = nil; pN = 0
    }

    private func stopOutputProc() {
        if let p = outProc { AudioDeviceStop(outDev, p); AudioDeviceDestroyIOProcID(outDev, p) }
        outProc = nil
    }

    /// v16: the ONE output IOProc. It plays the take when there is one (pL non-nil) and mixes the monitoring ring in when
    /// monFlag is set; it runs while either is on. It is always stopped before a take's memory is freed.
    @discardableResult
    private func startOutputProc() -> Bool {
        guard outProc == nil, let dev = outputs.first(where: { $0.uid == outUID }), dev.id != 0 else { return false }
        outDev = dev.id
        mStep = inRate / Devices.rate(dev.id); mPrimed = false
        var op: AudioDeviceIOProcID?
        var st = AudioDeviceCreateIOProcIDWithBlock(&op, outDev, nil) { [weak self] _, _, _, outData, _ in
            guard let self = self else { return }
            let list = UnsafeMutableAudioBufferListPointer(outData)
            guard list.count > 0, let o0 = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let ch = Int(list[0].mNumberChannels)
            let n = Int(list[0].mDataByteSize) / 4 / max(1, ch)
            let o1: UnsafeMutablePointer<Float>? = (ch == 1 && list.count >= 2) ? list[1].mData?.assumingMemoryBound(to: Float.self) : nil
            for b in (o1 == nil ? 1 : 2)..<max(list.count, o1 == nil ? 1 : 2) {
                if let m = list[b].mData { memset(m, 0, Int(list[b].mDataByteSize)) }
            }
            let L = self.pL, R = self.pR
            var pos = self.pPos
            let step = self.pStep, N = self.pN
            var pl: Float = 0, pr: Float = 0
            let g = self.outOnDeviceFlag ? 1 : self.outSoft
            // the monitoring ring: wait until one chunk plus one output buffer has arrived, then read at the rate ratio;
            // too much in the ring: skip to the target (latency never grows); too little: silence, wait again
            var mon = false
            var mp = self.mPos
            let mstep = self.mStep
            if self.monFlag {
                OSMemoryBarrier()
                let w = Double(self.monW.pointee)
                let need = Double(n) * mstep + 1
                let target = Double(self.monChunk) + Double(n) * mstep
                if !self.mPrimed, w >= target { mp = w - target; self.mPrimed = true }
                if self.mPrimed {
                    let avail = w - mp
                    if avail > 3 * target + need { mp = w - target }
                    if w - mp < need { self.mPrimed = false } else { mon = true }
                }
            } else { self.mPrimed = false }
            for i in 0..<n {
                var l: Float = 0, r: Float = 0
                if let L = L, let R = R {
                    let k = Int(pos)
                    if k + 1 < N {
                        let f = Float(pos - Double(k))
                        l = L[k] + (L[k + 1] - L[k]) * f; r = R[k] + (R[k + 1] - R[k]) * f
                        pos += step
                    } else { self.pDone = true }
                }
                if mon {
                    let k = Int(mp), f = Float(mp - Double(k))
                    let i0 = k & Recorder.monMask, i1 = (k + 1) & Recorder.monMask
                    l += self.monL[i0] + (self.monL[i1] - self.monL[i0]) * f
                    r += self.monR[i0] + (self.monR[i1] - self.monR[i0]) * f
                    mp += mstep
                }
                l *= g; r *= g
                l = min(max(l, -1), 1); r = min(max(r, -1), 1)
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
            if L != nil { self.pPos = pos }
            if mon { self.mPos = mp }
            self.rawOutL = max(self.rawOutL, pl); self.rawOutR = max(self.rawOutR, pr)
        }
        if st != noErr || op == nil { error = "the output would not open (\(st))"; return false }
        outProc = op
        st = AudioDeviceStart(outDev, op)
        if st != noErr { error = "the output would not start (\(st))"; stopOutputProc(); return false }
        return true
    }

    // ---------------------------------------------------------------- v16: input monitoring
    /// the input's audio thread: frames into the monitoring ring (no lock, no allocation)
    private func monitorWrite(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ n: Int) {
        var w = monW.pointee
        for i in 0..<n {
            let k = Int(w) & Self.monMask
            monL[k] = l[i]; monR[k] = r[i]
            w += 1
        }
        monChunk = n
        OSMemoryBarrier()
        monW.pointee = w
    }

    func toggleMonitor() {
        monitorOn.toggle()
        if live { UserDefaults.standard.set(monitorOn, forKey: "monitorOn") }
        applyMonitor()
    }

    func setMonitorBuf(_ f: Int) {
        guard Self.monitorSizes.contains(f) else { return }
        monitorBuf = f
        if live { UserDefaults.standard.set(f, forKey: "monitorBuf") }
        applyMonitor()
    }

    func bufferLabel(_ f: Int) -> String { String(format: "%d frames - %.1f ms", f, Double(f) / max(1, inRate) * 1000) }

    /// sets the buffer size on both devices, starts or stops the output proc, writes the estimate line
    func applyMonitor() {
        guard live else { return }
        monitorNote = nil; monitorInfo = nil
        monFlag = monitorOn
        if !monitorOn {
            if playingTake == nil { stopOutputProc() }
            return
        }
        guard let od = outputs.first(where: { $0.uid == outUID }), od.id != 0 else {
            monitorNote = "Monitoring needs an output device: choose one in the Output row."
            return
        }
        var notes: [String] = []
        var inFrames = 0, inLat = 0
        let idev = inputs.first(where: { $0.uid == inUID && $0.id != 0 })
        if let d = idev {
            if let a = Devices.setBuffer(d.id, monitorBuf) {
                inFrames = a
                if a != monitorBuf { notes.append("the input takes \(a) frames at the nearest") }
            } else { notes.append("the input would not take a buffer of \(monitorBuf) frames"); inFrames = Devices.bufferFrames(d.id) }
            inLat = Devices.latencyFrames(d.id, input: true)
        } else { inFrames = 480 }                               // an app's audio arrives in chunks of about 10 ms
        var outFrames = 0
        if let a = Devices.setBuffer(od.id, monitorBuf) {
            outFrames = a
            if a != monitorBuf { notes.append("the output takes \(a) frames at the nearest") }
        } else { notes.append("the output would not take a buffer of \(monitorBuf) frames"); outFrames = Devices.bufferFrames(od.id) }
        let outLat = Devices.latencyFrames(od.id, input: false)
        let oRate = Devices.rate(od.id)
        mStep = inRate / oRate
        if playingTake == nil { stopOutputProc(); startOutputProc() }
        let tin = Double(inFrames + inLat) / max(1, inRate)
        let ring = (Double(inFrames) + Double(outFrames) * mStep) / max(1, inRate)
        let tout = Double(outFrames + outLat) / max(1, oRate)
        let ms = (tin + ring + tout) * 1000
        monitorInfo = String(format: "about %.1f ms through your devices", ms)
        if !notes.isEmpty { monitorNote = notes.joined(separator: "; ") + "." }
    }

    // ---------------------------------------------------------------- v17: the recording format
    /// the rate a take would have now: the chosen one when the device took it, else what the input runs at
    var effectiveRate: Double { inRate }

    /// "about 17 MB per minute, stereo"
    var sizeText: String {
        let mb = effectiveRate * 2 * Double(recBits / 8) * 60 / 1_000_000
        return String(format: "about %.0f MB per minute, stereo", mb)
    }

    func rateLabel(_ r: Double) -> String { String(format: "%g kHz", r / 1000) }
    var qualityName: String { Self.presets.first(where: { $0.id == recQuality })?.name ?? "Custom" }

    private func saveFormat() {
        guard live else { return }
        let d = UserDefaults.standard
        d.set(recBits, forKey: "recBits"); d.set(recRate, forKey: "recRate"); d.set(recQuality, forKey: "recQuality")
    }

    /// the quality that bits and rate add up to: a preset when they match one, else custom
    private func matchQuality() -> String {
        for p in Self.presets {
            let rate = p.id == "max" ? (availRates.max() ?? p.rate) : p.rate
            if p.bits == recBits && recRate == rate { return p.id }
        }
        return "custom"
    }

    func setBits(_ b: Int) {
        guard !recording, Self.bitOptions.contains(b) else { return }
        recBits = b; recQuality = matchQuality(); saveFormat()
    }

    /// 0 = Auto. The input device (and the output device, when it offers the rate) is asked to run at it.
    func setRate(_ r: Double) {
        guard !recording, !rateLocked else { return }
        recRate = r; recQuality = matchQuality(); saveFormat()
        applyRateNow()
    }

    func setQuality(_ id: String) {
        guard !recording else { return }
        guard let p = Self.presets.first(where: { $0.id == id }) else { recQuality = "custom"; saveFormat(); return }
        recBits = p.bits
        if !rateLocked {
            let want = id == "max" ? (availRates.max() ?? p.rate) : p.rate
            // the nearest rate the input really offers, when it does not offer this one
            recRate = availRates.isEmpty || availRates.contains(want) ? want : (availRates.min(by: { abs($0 - want) < abs($1 - want) }) ?? want)
        }
        recQuality = id; saveFormat()
        if !rateLocked { applyRateNow() }
    }

    private func applyRateNow() {
        guard live else { return }
        pause(restart: false)                       // a take playing keeps its own step: stop it before a device changes rate
        if inUID.hasPrefix("app:") { return }
        stopAutoGain()
        startInput()                                // applies the rate, reads it back, restarts the monitoring
    }

    /// reads what the input offers, sets the chosen rate on it (and on the output when it offers it), reads the real rate back
    private func applyRate() {
        rateNote = nil
        guard let d = inputs.first(where: { $0.uid == inUID && $0.id != 0 }) else { availRates = []; return }
        availRates = Devices.supportedRates(d.id)
        inRate = Devices.rate(d.id)
        guard recRate > 0 else { return }
        if abs(inRate - recRate) > 0.5 {
            if !(availRates.contains(recRate) && Devices.setRate(d.id, recRate)) {
                rateNote = "The input would not switch to \(rateLabel(recRate)); it runs at \(rateLabel(Devices.rate(d.id)))."
            }
            inRate = Devices.rate(d.id)
        }
        if let od = outputs.first(where: { $0.uid == outUID && $0.id != 0 }), abs(Devices.rate(od.id) - recRate) > 0.5,
           Devices.supportedRates(od.id).contains(recRate) {
            _ = Devices.setRate(od.id, recRate)     // an output that will not follow is resampled as before
        }
    }

    // ---------------------------------------------------------------- saving
    // v5 (Marko, 31.10.2026: "add the save button in upper right corner of each waveform"): SAVE asks where (the last
    // folder, at first ~/Music) and writes the take as it is: WAV, stereo, 24 bit, at the take's rate.
    func save(_ t: Take) {
        let panel = NSSavePanel()
        panel.title = "Save take \(t.id)"
        panel.allowedContentTypes = [.wav]
        let f = DateFormatter(); f.dateFormat = "d.M.yyyy HH.mm"
        panel.nameFieldStringValue = "Take \(t.id) - \(f.string(from: t.made)).wav"
        let d = UserDefaults.standard
        panel.directoryURL = URL(fileURLWithPath: d.string(forKey: "saveFolder") ?? (NSHomeDirectory() + "/Music"))
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self = self else { return }
            do {
                try Self.writeWAV(t, to: url)
                t.savedTo = url
                d.set(url.deletingLastPathComponent().path, forKey: "saveFolder")
                self.error = nil
            } catch { self.error = "take \(t.id) was not saved: \(error.localizedDescription)" }
            self.objectWillChange.send()
        }
        if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) { panel.beginSheetModal(for: w, completionHandler: done) }
        else { done(panel.runModal()) }
    }

    static func writeWAV(_ t: Take, to url: URL) throws {
        let bits = Self.bitOptions.contains(t.bits) ? t.bits : 24
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: t.rate, AVNumberOfChannelsKey: 2,
                                       AVLinearPCMBitDepthKey: bits, AVLinearPCMIsFloatKey: bits == 32, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 65536
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)) else { return }
        var at = 0
        var seed: UInt32 = 2463534242                       // xorshift for the dither
        func rnd() -> Float { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return Float(seed) / 4294967296.0 }
        while at < t.frames {
            let n = min(chunk, t.frames - at)
            t.l.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress! + at, count: n) }
            t.r.withUnsafeBufferPointer { buf.floatChannelData![1].update(from: $0.baseAddress! + at, count: n) }
            if bits == 16 {                                  // v17: TPDF dither, +-1 LSB, before the cut to 16 bit
                let lsb: Float = 1.0 / 32768.0
                for c in 0..<2 {
                    let p = buf.floatChannelData![c]
                    for i in 0..<n { p[i] = min(max(p[i] + (rnd() - rnd()) * lsb, -1), 1) }
                }
            }
            buf.frameLength = AVAudioFrameCount(n)
            try file.write(from: buf)
            at += n
        }
    }

    // ---------------------------------------------------------------- auto gain
    // Marko, 31.10.2026: "auto gain option the same as in my CQ mixer series ... when it detects the right level it's
    // going to adjust the gain automatically and then quits." Press: it listens (?) for sound; heard, it measures the
    // loudest peak for 2 s and moves the input's volume so that peak lands on -12 dBFS, again until it is within
    // 1.5 dB (the gear); then ✓ for 4 s and it is off by itself. ! when no sound came in 15 s or the volume ran out.
    func toggleAutoGain() {
        if gain == .listening || gain == .adjusting { stopAutoGain(); return }
        guard !recording else { return }
        guard inProc != nil || appReady else { if !inUID.hasPrefix("app:") { Permissions.openMissing() }; return }
        gain = .listening; gListenStart = Date(); gRound = 0
        gainNote = "AUTO GAIN: sing or play as loud as you will record"
    }

    private func stopAutoGain() { gain = .idle; gainNote = nil }

    private func failGain(_ why: String) { gain = .failed; gStart = Date(); gainNote = "AUTO GAIN: " + why }

    /// moves the input by `delta` dB; false when it cannot move further that way. Up: the volume to its top first,
    /// then the boost (v10). Down: the boost back to 1 first, then the volume.
    private func nudgeInput(_ delta: Float) -> Bool {
        var left = delta, moved = false
        if left < 0, inBoost > 1 {
            let b = max(inBoost * pow(10, left / 20), 1)
            left -= 20 * log10(b / inBoost); setBoost(b); moved = true
        }
        if abs(left) >= 0.2 {
            let used = nudgeVolume(left)
            if used != 0 { moved = true; left -= used }
        }
        if left >= 0.2, inBoost < Self.maxBoost {
            let b = min(inBoost * pow(10, left / 20), Self.maxBoost)
            if b - inBoost > 0.004 { setBoost(b); moved = true }
        }
        return moved
    }

    /// moves the input's volume (the device's, or the app's gain up to 100 %); the dB it really moved
    private func nudgeVolume(_ delta: Float) -> Float {
        if let w = inWatch, let db = w.decibels, let range = w.dbRange {
            let to = min(max(db + delta, range.0), range.1)
            if abs(to - db) < 0.2 { return 0 }
            w.setDecibels(to); inVolume = w.value
            return to - db
        }
        let v = inWatch?.value ?? inSoft
        let nv = min(max((v > 0 ? v : 0.01) * pow(10, delta / 20), 0), 1)
        if abs(nv - v) < 0.004 { return 0 }
        setInput(nv)
        if let w = inWatch { inVolume = w.value }
        return v > 0 && nv > 0 ? 20 * log10(nv / v) : delta
    }

    private func stepAutoGain(_ peakNow: Float) {
        let now = Date()
        switch gain {
        case .idle: break
        case .listening:
            if peakNow > -45 { gain = .adjusting; gStart = now; gPeak = peakNow; gainNote = "AUTO GAIN: listening… keep going" }
            else if now.timeIntervalSince(gListenStart) > 15 { failGain("no sound came in for 15 s") }
        case .adjusting:
            if now < gStart { break }                                 // the new volume settling
            gPeak = max(gPeak, peakNow)
            guard now.timeIntervalSince(gStart) >= 2 else { break }
            if gPeak < -45 { gain = .listening; gListenStart = now; gainNote = "AUTO GAIN: waiting for sound"; break }
            let delta = Self.gainTarget - gPeak
            if abs(delta) <= 1.5 {
                gain = .done; gStart = now
                gainNote = String(format: "AUTO GAIN: set, the loudest peak at %.1f dB, the input gain %@", gPeak, inGainText)
            } else if gRound >= 8 {
                failGain("the level would not settle; try again")
            } else if !nudgeInput(delta) {
                failGain(delta > 0 ? "too quiet even with the +32 dB boost: closer to the microphone" : "too loud even at the lowest volume")
            } else {
                gRound += 1; gPeak = -90; gStart = now.addingTimeInterval(0.3)
            }
        case .done, .failed:
            if now.timeIntervalSince(gStart) > 4 { stopAutoGain() }
        }
    }

    // ---------------------------------------------------------------- 30 times a second
    private func tick() {
        let dt = 1.0 / 30
        if recording { drain() }
        if let t = playingTake {
            t.cursor = pPos
            if pDone { pause(); t.cursor = 0 }
        }
        stepAutoGain(Meter.db(max(rawInL, rawInR)))
        var m = inMeter; m.feed(rawInL, rawInR, dt: dt); rawInL = 0; rawInR = 0; inMeter = m
        var o = outMeter; o.feed(rawOutL, rawOutR, dt: dt); rawOutL = 0; rawOutR = 0; outMeter = o
    }

    // ---------------------------------------------------------------- the end
    /// QUIT, OFF, ⌘Q: the devices let go and the takes are forgotten. They were never on the disk.
    func forget() {
        monFlag = false                                     // v16: monitoring is off when the app ends (the saved choice stays)
        pause(restart: false)
        stopInput()
        recording = false
        current = nil
        takes = []
    }

    // ---------------------------------------------------------------- tests
    /// a take made of sound instead of a microphone: a tone at -12 dBFS that swells and fades
    @discardableResult
    func addTestTake(seconds s: Double = 6, hz: Double = 440, shape: Double = 1.7) -> Take {
        let t = Take(id: nextID, rate: 48000)
        nextID += 1
        let n = Int(t.rate * s)
        t.l = [Float](repeating: 0, count: n); t.r = t.l
        for i in 0..<n {
            let x = Double(i) / t.rate
            let env = 0.55 + 0.45 * sin(x * shape) * sin(x * 0.6 + 0.4)
            let v = Float(0.25 * env * sin(2 * .pi * hz * x))
            t.l[i] = v; t.r[i] = v * 0.8
        }
        t.peaks = stride(from: 0, to: n, by: Self.block).map { s in
            var m: Float = 0
            for i in s..<min(n, s + Self.block) { m = max(m, abs(t.l[i]), abs(t.r[i])) }
            return m
        }
        takes.append(t); lastID = t.id
        return t
    }

    /// for the picture only: take `id` as if playing at `fraction`, the meters showing these levels
    func pose(playing id: Int, at fraction: Double, inDB: (Float, Float), outDB: (Float, Float), gain g: GainStep = .idle, boost: Float = 1) {
        inBoost = boost
        if let t = takes.first(where: { $0.id == id }) { t.cursor = fraction * Double(t.frames); playingID = id }
        inMeter = Meter(l: inDB.0, r: inDB.1, holdL: inDB.0 + 3, holdR: inDB.1 + 2)
        outMeter = Meter(l: outDB.0, r: outDB.1, holdL: outDB.0 + 2, holdR: outDB.1 + 4)
        gain = g
        if g == .adjusting { gainNote = "AUTO GAIN: listening… keep going" }
        timer?.invalidate()
    }

    var playing: Bool { playingID != nil }
}

// MANTRA_MANIFEST swift-apps.md, PERMISSIONS: the one this app uses is the microphone (every input device, BlackHole too).
enum Permissions {
    /// what this run needs: Screen Recording for the Firefox capture, the Microphone for a real input device
    static var needed: [String] {
        (UserDefaults.standard.string(forKey: "input") ?? "").hasPrefix("app:") ? ["Screen Recording"] : ["Microphone"]
    }
    static func allowed(_ p: String) -> Bool {
        switch p {
        case "Microphone": return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case "Screen Recording": return CGPreflightScreenCaptureAccess()
        default: return true
        }
    }
    static var missing: [String] { needed.filter { !allowed($0) } }
    static func openMissing() { if let p = missing.first { open(p) } }
    static func open(_ p: String) {
        if p == "Microphone", AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }      // the system's own question, once
            return
        }
        let pane = p == "Screen Recording" ? "ScreenCapture" : p
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane)!)
    }
}

/// The voice engine and langsay stay silent while this file exists and its pid lives (task 89, 10.11.2026).
enum RecordingFlag {
    static let url = URL(fileURLWithPath: NSHomeDirectory() + "/.voice/recording.flag")
    static func set(_ on: Bool) {
        if on {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: url, atomically: true, encoding: .utf8)
        } else { try? FileManager.default.removeItem(at: url) }
    }
}

/// One app's sound through ScreenCaptureKit (macOS 13+): planar or interleaved float frames to the ring.
protocol AppSource: AnyObject {
    var running: Bool { get }
    var rate: Double { get }
    func start(bundle: String) async throws
    func stop()
}

final class AppTap: NSObject, SCStreamOutput, SCStreamDelegate, AppSource {
    private var stream: SCStream?
    private let sink: (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void
    private(set) var running = false
    let rate: Double = 48000
    private let q = DispatchQueue(label: "apptap")
    init(sink: @escaping (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void) { self.sink = sink }

    func start(bundle: String) async throws {
        let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let app = c.applications.first(where: { $0.bundleIdentifier == bundle }) else {
            throw NSError(domain: "AppTap", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(bundle) is not running"]) }
        guard let disp = c.displays.first else { throw NSError(domain: "AppTap", code: 2, userInfo: [NSLocalizedDescriptionKey: "no display"]) }
        let f = SCContentFilter(display: disp, including: [app], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true; cfg.sampleRate = 48000; cfg.channelCount = 2; cfg.excludesCurrentProcessAudio = true
        cfg.width = 2; cfg.height = 2; cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let s = SCStream(filter: f, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: q)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: q)
        try await s.startCapture()
        stream = s; running = true
    }
    func stop() { running = false; let s = stream; stream = nil; Task { try? await s?.stopCapture() } }
    func stream(_ stream: SCStream, didStopWithError error: Error) { running = false }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return }
        var abl = AudioBufferList(); var bb: CMBlockBuffer?
        var size = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0,
                                                                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16); defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: size,
              blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &bb) == noErr else { return }
        _ = abl
        let bufs = UnsafeMutableAudioBufferListPointer(list)
        let n = CMSampleBufferGetNumSamples(sb)
        guard n > 0, let d0 = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        if planar {
            let d1 = bufs.count > 1 ? (bufs[1].mData?.assumingMemoryBound(to: Float.self) ?? d0) : d0
            for i in 0..<n { l[i] = d0[i]; r[i] = d1[i] }
        } else {
            let ch = max(1, Int(asbd.mChannelsPerFrame))
            for i in 0..<n { l[i] = d0[i * ch]; r[i] = d0[i * ch + (ch > 1 ? 1 : 0)] }
        }
        sink(l, r, n)
    }
}
