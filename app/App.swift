// Mantra Sound Recorder (Mantra): record, play, see the waveform; the take is gone when the app quits.
//
// Marko, 31.10.2026: "SoundSource which is now open on the screen should be user interface for audio input and audio
// output and audio input and audio output VU meters. And overall look." So the window is SoundSource's: a dark
// ground, rounded panels, an Output row and a green Input row, each with its meter and its device menu.
import SwiftUI
import AppKit

let VERSION = 1
let RELEASES = URL(string: "https://github.com/markoboskoauroville/MANTRA_SOUND_RECORDER/releases/latest")!

enum Ink {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    static let ground = hex(0x1F1F20)     // SoundSource's window
    static let panel = hex(0x2A2A2B)      // its rounded sections
    static let line = hex(0x3A3A3C)
    static let rowGrey = hex(0x353536)    // the Output row
    static let rowGreen = hex(0x346A47)   // the Input row, green as SoundSource's
    static let tile = hex(0x48484A)
    static let well = hex(0x161617)       // under the meters and the waveform
    static let text = hex(0xECECEC)
    static let dim = hex(0x9A9A9E)
    static let green = hex(0x33D17A)      // CAMERA: on
    static let grey = hex(0x7A8087)       // off
    static let amber = hex(0xE8A33D)      // warning
    static let dark = hex(0x33383E)       // cannot act
    static let red = hex(0xFF3B30)        // recording
    static let ring = hex(0xC8CDD2)
}

func clock(_ s: Double) -> String {
    let t = max(0, s)
    return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
}

// ---------------------------------------------------------------- the window
struct Root: View {
    @ObservedObject var r: Recorder
    @State private var missing = Permissions.missing
    let margin: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    TopRow(missing: missing)
                    DevicesPanel(r: r)
                    RecorderPanel(r: r)
                    Footer()
                }
                .frame(width: max(0, g.size.width - 2 * margin), alignment: .leading)
                .padding(.horizontal, margin).padding(.bottom, margin)
            }
            .scrollIndicators(.never)
        }
        .ignoresSafeArea(.container, edges: .top)          // the top row sits in the hidden title bar, beside the traffic lights
        .background(Ink.ground)
        .frame(minWidth: 580, idealWidth: 720, maxWidth: .infinity, minHeight: 500, idealHeight: 520, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let m = Permissions.missing
            if m != missing { missing = m; r.permissionsChanged() }
        }
    }
}

/// ON / OFF, the name, PERMISSIONS while one is missing, ✕ (MANTRA_MANIFEST swift-apps.md)
struct TopRow: View {
    let missing: [String]
    var body: some View {
        ZStack {
            (Text("Mantra Sound").fontWeight(.bold) + Text(" Recorder").fontWeight(.regular))
                .font(.system(size: 15)).foregroundStyle(Ink.text)
            HStack(spacing: 10) {
                Spacer().frame(width: 64)                   // the traffic lights
                Text("ON").foregroundStyle(Ink.green)
                Text("OFF").foregroundStyle(Ink.grey)
                    .contentShape(Rectangle()).onTapGesture { NSApp.terminate(nil) }
                Spacer()
                if !missing.isEmpty {
                    Text("PERMISSIONS").foregroundStyle(Ink.amber)
                        .contentShape(Rectangle()).onTapGesture { Permissions.openMissing() }
                        .help("The microphone is not allowed yet: a click opens its page in System Settings")
                }
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.grey)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
                    .onTapGesture { NSApp.keyWindow?.performClose(nil) }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .frame(height: 30)
    }
}

struct Panel<Content: View>: View {
    let title: String
    var right: AnyView = AnyView(EmptyView())
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Ink.text)
                Spacer()
                right
            }
            .padding(.horizontal, 14).frame(height: 36)
            content
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Ink.panel))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line, lineWidth: 1))
    }
}

// ---------------------------------------------------------------- devices
struct DevicesPanel: View {
    @ObservedObject var r: Recorder
    var body: some View {
        Panel(title: "Devices", right: AnyView(HStack(spacing: 0) {
            Text("Level").frame(maxWidth: .infinity)
            Text("Device").frame(width: 230)
        }.font(.system(size: 11)).foregroundStyle(Ink.dim).padding(.leading, 160))) {
            DeviceRow(icon: "speaker.wave.2.fill", name: "Output", meter: r.outMeter,
                      devices: r.outputs, uid: r.outUID, enabled: true, fill: Ink.rowGrey) { r.chooseOutput($0) }
            DeviceRow(icon: "mic.fill", name: "Input", meter: r.inMeter,
                      devices: r.inputs, uid: r.inUID, enabled: !r.recording, fill: Ink.rowGreen) { r.chooseInput($0) }
            if let e = r.error {
                Text(e).font(.system(size: 11)).foregroundStyle(Ink.amber)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.vertical, 6)
            }
            Spacer().frame(height: 6)
        }
    }
}

struct DeviceRow: View {
    let icon: String, name: String
    let meter: Meter
    let devices: [Device]
    let uid: String
    let enabled: Bool
    let fill: Color
    let choose: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Ink.text)
                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Ink.tile))
            Text(name).font(.system(size: 14)).foregroundStyle(Ink.text).frame(width: 62, alignment: .leading)
            MeterView(m: meter).frame(minWidth: 110).frame(height: 18)
            Text(readout).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.text)
                .frame(width: 58, alignment: .trailing)
            Picker("", selection: Binding(get: { uid }, set: { choose($0) })) {
                ForEach(devices) { d in Text(d.name).tag(d.uid) }
            }
            .labelsHidden().pickerStyle(.menu).disabled(!enabled)
            .frame(minWidth: 150, maxWidth: 230)
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(fill)
    }

    var readout: String {
        let p = max(meter.holdL, meter.holdR)
        return p <= -60 ? "−∞ dB" : String(format: "%.1f dB", p)
    }
}

/// Two bars, left over right: green to -12 dBFS, amber to -3, red above; the white tick is the held peak.
struct MeterView: View {
    let m: Meter
    static func x(_ db: Float) -> CGFloat { CGFloat(min(max((db + 60) / 60, 0), 1)) }

    var body: some View {
        Canvas { c, size in
            let h = (size.height - 3) / 2
            for (i, (lvl, hold)) in [(m.l, m.holdL), (m.r, m.holdR)].enumerated() {
                let y = CGFloat(i) * (h + 3)
                let track = CGRect(x: 0, y: y, width: size.width, height: h)
                c.fill(Path(roundedRect: track, cornerRadius: 2), with: .color(Ink.well))
                let w = size.width * Self.x(lvl)
                let zones: [(Float, Float, Color)] = [(-60, -12, Ink.green), (-12, -3, Ink.amber), (-3, 0, Ink.red)]
                for (a, b, col) in zones {
                    let x0 = size.width * Self.x(a), x1 = min(size.width * Self.x(b), w)
                    if x1 > x0 { c.fill(Path(CGRect(x: x0, y: y, width: x1 - x0, height: h)), with: .color(col)) }
                }
                if hold > -60 {
                    let hx = min(size.width - 2, size.width * Self.x(hold))
                    c.fill(Path(CGRect(x: hx, y: y, width: 2, height: h)), with: .color(.white))
                }
            }
            // the scale's marks: -48 -36 -24 -12 -6 -3, faint
            for db: Float in [-48, -36, -24, -12, -6, -3] {
                let x = size.width * Self.x(db)
                c.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Ink.ground.opacity(0.6)))
            }
        }
    }
}

// ---------------------------------------------------------------- the recorder
struct RecorderPanel: View {
    @ObservedObject var r: Recorder
    var body: some View {
        Panel(title: "Recorder", right: AnyView(
            Text(r.frames > 0 ? "\(Int(r.takeRate)) Hz · stereo" : "")
                .font(.system(size: 11)).foregroundStyle(Ink.dim))) {
            VStack(alignment: .leading, spacing: 12) {
                Waveform(r: r).frame(height: 160)
                HStack(spacing: 16) {
                    RecordKey(r: r)
                    PlayKey(r: r)
                    VStack(alignment: .leading, spacing: 2) {
                        if r.recording {
                            (Text("REC  ").foregroundStyle(Ink.red) + Text(clock(r.seconds)).foregroundStyle(Ink.text))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        } else {
                            Text("\(clock(r.position)) / \(clock(r.frames > 0 ? r.seconds : 0))")
                                .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Ink.text)
                        }
                        Text("R record · Space play").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.dim)
                    }
                    Spacer(minLength: 8)
                    Text("in memory only · gone when the app quits")
                        .font(.system(size: 11)).foregroundStyle(Ink.dim)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

/// The take: the loudest sample of each column, mirrored round the middle line. Played part green, the rest grey,
/// the playhead white; while recording red, growing from the left over the first ten seconds, then squeezing.
struct Waveform: View {
    @ObservedObject var r: Recorder

    var body: some View {
        GeometryReader { g in
            Canvas { c, size in
                c.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(Ink.well))
                let mid = size.height / 2
                c.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Ink.line))
                let p = r.peaks
                guard !p.isEmpty else { return }
                let span = r.recording ? max(p.count, Int(10 * r.takeRate) / Recorder.block) : p.count
                let step: CGFloat = 2
                let cols = Int(size.width / step)
                let playX = r.frames > 0 ? size.width * CGFloat(r.cursor / Double(r.frames)) : 0
                let usable = mid - 6
                for col in 0..<cols {
                    let a = col * span / cols, b = max(a + 1, (col + 1) * span / cols)
                    if a >= p.count { break }
                    var m: Float = 0
                    for i in a..<min(b, p.count) { m = max(m, p[i]) }
                    let h = max(1, CGFloat(min(m, 1)) * usable)
                    let x = CGFloat(col) * step
                    let ink: Color = r.recording ? Ink.red : (x < playX ? Ink.green : Ink.grey)
                    c.fill(Path(CGRect(x: x, y: mid - h, width: step * 0.7, height: 2 * h)), with: .color(ink))
                }
                if !r.recording {
                    c.fill(Path(CGRect(x: min(playX, size.width - 1.5), y: 0, width: 1.5, height: size.height)), with: .color(.white))
                }
            }
            .overlay {
                if r.peaks.isEmpty {
                    Text(r.canRecord ? "press ● to record" : "the microphone is not allowed yet: PERMISSIONS, top right")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.dim)
                        .multilineTextAlignment(.center).padding()
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in r.seek(Double(v.location.x / max(1, g.size.width))) })
        }
    }
}

/// CAMERA's record circle: a ring round a red dot; recording, filled red with the time in white.
struct RecordKey: View {
    @ObservedObject var r: Recorder
    var body: some View {
        let able = r.canRecord || r.recording || Permissions.missing.contains("Microphone")
        ZStack {
            if r.recording {
                Circle().fill(Ink.red)
                Text(String(format: "%02d:%02d", Int(r.seconds) / 60, Int(r.seconds) % 60))
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            } else {
                Circle().stroke(able ? Ink.ring : Ink.dark, lineWidth: 2)
                Circle().fill(able && !r.playing ? Ink.red : Ink.dark).frame(width: 20, height: 20)
            }
        }
        .frame(width: 48, height: 48).contentShape(Circle())
        .onTapGesture { r.toggleRecord() }
        .help("Record (R)")
    }
}

struct PlayKey: View {
    @ObservedObject var r: Recorder
    var body: some View {
        let able = r.canPlay
        ZStack {
            Circle().stroke(able ? Ink.ring : Ink.dark, lineWidth: 2)
            Image(systemName: r.playing ? "stop.fill" : "play.fill")
                .font(.system(size: 17)).foregroundStyle(r.playing ? Ink.green : (able ? .white : Ink.dark))
                .offset(x: r.playing ? 0 : 2)
        }
        .frame(width: 48, height: 48).contentShape(Circle())
        .onTapGesture { r.togglePlay() }
        .help("Play / stop (Space)")
    }
}

/// vN, plain and dim, a hidden link to the latest build (version-visible.md); QUIT, red, bottom right (swift-apps.md)
struct Footer: View {
    var body: some View {
        HStack {
            Text("v\(VERSION)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.dim)
                .onTapGesture { NSWorkspace.shared.open(RELEASES) }
            Spacer()
            Text("QUIT").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Ink.red)
                .contentShape(Rectangle()).onTapGesture { NSApp.terminate(nil) }
        }
    }
}

// ---------------------------------------------------------------- the app
let REC = Recorder()

final class Delegate: NSObject, NSApplicationDelegate {
    private var keys: Any?
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // R records, Space plays; with ⌘ the menus keep their keys
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if !e.modifierFlags.intersection([.command, .control, .option]).isEmpty { return e }
            switch e.charactersIgnoringModifiers?.lowercased() {
            case " ": REC.togglePlay(); return nil
            case "r": REC.toggleRecord(); return nil
            default: return e
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { REC.forget() }
}

struct RecorderApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup("Mantra Sound Recorder (Mantra)") { Root(r: REC) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            .defaultSize(width: 720, height: 520)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

// ---------------------------------------------------------------- the ways in
@main
enum Main {
    static func main() {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--shot"), i + 1 < a.count {
            // the window drawn off screen into a PNG, never shown (screenshots-without-his-screen):
            // --shot <png> [width] [height]
            let w = i + 2 < a.count ? Double(a[i + 2]) ?? 720 : 720, h = i + 3 < a.count ? Double(a[i + 3]) ?? 540 : 540
            exit(shot(a[i + 1], w, h) ? 0 : 1)
        }
        if let i = a.firstIndex(of: "--play-test"), i + 1 < a.count {
            // the test take played to an output whose name contains the word: --play-test BlackHole
            exit(playTest(a[i + 1]) ? 0 : 1)
        }
        RecorderApp.main()
    }

    static func shot(_ path: String, _ w: Double, _ h: Double) -> Bool {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let r = Recorder(live: false)
        r.loadTestTake()
        r.pose(fraction: 0.42, inDB: (-21, -24), outDB: (-13, -15))
        let v = NSHostingView(rootView: Root(r: r))
        v.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let win = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = v                                  // never ordered in
        v.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return false }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    static func playTest(_ name: String) -> Bool {
        let r = Recorder(live: false)
        guard r.chooseOutput(named: name) else { print("no output named \(name)"); return false }
        r.loadTestTake(seconds: 3)
        r.play()
        guard r.playing else { print("did not play: \(r.error ?? "?")"); return false }
        var loudest: Float = -90
        let end = Date().addingTimeInterval(6)
        while r.playing && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            loudest = max(loudest, r.outMeter.l)
        }
        print(String(format: "played %.1f s of the test take to %@, the output meter's loudest %.1f dBFS", r.seconds, r.outputName, loudest))
        return !r.playing && loudest > -20
    }
}
