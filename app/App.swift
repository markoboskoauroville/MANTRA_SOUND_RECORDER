// Mantra Sound Recorder (Mantra): record, play, see the waveform; the take is gone when the app quits.
//
// Marko, 31.10.2026: "SoundSource which is now open on the screen should be user interface for audio input and audio
// output and audio input and audio output VU meters. And overall look." So the window is SoundSource's: a dark
// ground, rounded panels, an Output row and a green Input row, each with its meter and its device menu.
import SwiftUI
import AppKit

let VERSION = 7
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
    @State private var contentHeight: CGFloat = 0
    let margin: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            ScrollViewReader { sv in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    TopRow(missing: missing)
                    DevicesPanel(r: r)
                    TakesPanel(r: r)
                    Footer()
                }
                // v6: the page leaves room for the scroll bar while there is one, so nothing goes under it
                .frame(width: max(0, g.size.width - 2 * margin - (contentHeight > g.size.height + 0.5 ? Scroller.width : 0)),
                       alignment: .leading)
                .padding(.horizontal, margin).padding(.bottom, margin)
                .background(GeometryReader { c in Color.clear.preference(key: ContentHeight.self, value: c.size.height) })
                .background(Scroller())
            }
            .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
            .onChange(of: r.takes.count) { withAnimation { sv.scrollTo("next", anchor: .bottom) } }
            .onChange(of: r.recording) { if r.recording { withAnimation { sv.scrollTo("next", anchor: .bottom) } } }
            }
        }
        .ignoresSafeArea(.container, edges: .top)          // the top row sits in the hidden title bar, beside the traffic lights
        .background(Ink.ground)
        .frame(minWidth: 600, idealWidth: 720, maxWidth: .infinity, minHeight: 520, idealHeight: 540, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let m = Permissions.missing
            if m != missing { missing = m; r.permissionsChanged() }
        }
    }
}

// v6 (Marko, 31.10.2026: "build in a scrolling bar for this application if waveforms or other user interface parts are
// going out of the user interface"): the window's scroll view gets a real, always-drawn scroll bar (the legacy style,
// not the overlay one that macOS hides until a trackpad scrolls), shown only while the page is taller than the window.
struct Scroller: NSViewRepresentable {
    static let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    func makeNSView(context: Context) -> NSView { let v = NSView(); DispatchQueue.main.async { Self.apply(v) }; return v }
    func updateNSView(_ v: NSView, context: Context) { DispatchQueue.main.async { Self.apply(v) } }
    static func apply(_ v: NSView) {
        guard let s = v.enclosingScrollView else { return }
        s.hasVerticalScroller = true
        s.autohidesScrollers = true
        if s.scrollerStyle != .legacy { s.scrollerStyle = .legacy }
        s.verticalScroller?.knobStyle = .light
    }
}

struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// ON / OFF, the name, PERMISSIONS while one is missing, ✕ (MANTRA_MANIFEST swift-apps.md)
struct TopRow: View {
    let missing: [String]
    // v2 (Marko, 31.10.2026: "add a toggle button always on top in the main user interface"): green = above every window
    @AppStorage("onTop") private var onTop = false
    var body: some View {
        ZStack {
            (Text("Mantra Sound").fontWeight(.bold) + Text(" Recorder").fontWeight(.regular))
                .font(.system(size: 15)).foregroundStyle(Ink.text)
            HStack(spacing: 10) {
                Spacer().frame(width: 64)                   // the traffic lights
                Text("ON").foregroundStyle(Ink.green)
                Text("OFF").foregroundStyle(Ink.grey)
                    .contentShape(Rectangle()).onTapGesture { NSApp.terminate(nil) }
                    .axButton("Off", id: "off") { DispatchQueue.main.async { NSApp.terminate(nil) } }
                Spacer()
                // v3: "Just put top" (Marko, 31.10.2026)
                Text("TOP").foregroundStyle(onTop ? Ink.green : Ink.grey)
                    .contentShape(Rectangle()).onTapGesture { onTop.toggle(); TopRow.float(onTop) }
                    .axButton("Top", id: "top", value: onTop ? "on" : "off") { onTop.toggle(); TopRow.float(onTop) }
                    .help("Always on top: green, the window stays above every other window")
                if !missing.isEmpty {
                    Text("PERMISSIONS").foregroundStyle(Ink.amber)
                        .contentShape(Rectangle()).onTapGesture { Permissions.openMissing() }
                        .axButton("Permissions", id: "permissions") { Permissions.openMissing() }
                        .help("The microphone is not allowed yet: a click opens its page in System Settings")
                }
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.grey)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
                    .onTapGesture { NSApp.keyWindow?.performClose(nil) }
                    .axButton("Close window", id: "close") { (NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible })?.performClose(nil) }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .frame(height: 30)
        .onAppear { DispatchQueue.main.async { TopRow.float(onTop) } }
    }

    static func float(_ on: Bool) {
        for w in NSApp.windows where w.contentView is NSHostingView<Root> || w.title.hasPrefix("Mantra Sound Recorder") {
            w.level = on ? .floating : .normal
        }
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
                      volume: r.outVolume, onDevice: r.outOnDevice, setVolume: { r.setVolume(input: false, $0) },
                      devices: r.outputs, uid: r.outUID, enabled: true, fill: Ink.rowGrey,
                      extra: AnyView(Color.clear.frame(width: 30, height: 30))) { r.chooseOutput($0) }
            DeviceRow(icon: "mic.fill", name: "Input", meter: r.inMeter,
                      volume: r.inVolume, onDevice: r.inOnDevice, setVolume: { r.setVolume(input: true, $0) },
                      devices: r.inputs, uid: r.inUID, enabled: !r.recording, fill: Ink.rowGreen,
                      extra: AnyView(AutoGainKey(r: r))) { r.chooseInput($0) }
            if let n = r.gainNote {
                Text(n).font(.system(size: 11, design: .monospaced)).foregroundStyle(r.gain == .failed ? Ink.amber : Ink.text)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.top, 6)
            }
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
    let volume: Float
    let onDevice: Bool
    let setVolume: (Float) -> Void
    let devices: [Device]
    let uid: String
    let enabled: Bool
    let fill: Color
    var extra: AnyView = AnyView(EmptyView())
    let choose: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Ink.text)
                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Ink.tile))
            Text(name).font(.system(size: 14)).foregroundStyle(Ink.text).frame(width: 62, alignment: .leading)
            extra
            VStack(spacing: 6) {
                VolumeSlider(label: name + " volume", value: volume, set: setVolume).frame(height: 16)
                    .help(onDevice ? "The device's own volume (the volume keys move it too)" : "This device has no volume of its own: the app's gain")
                MeterView(m: meter).frame(height: 11)
            }
            .frame(minWidth: 80)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(Int((volume * 100).rounded())) %").font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(readout).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.dim)
            }
            .foregroundStyle(Ink.text).frame(width: 64, alignment: .trailing)
            Picker("", selection: Binding(get: { uid }, set: { choose($0) })) {
                ForEach(devices) { d in Text(d.name).tag(d.uid) }
            }
            .labelsHidden().pickerStyle(.menu).disabled(!enabled)
            .frame(minWidth: 196, maxWidth: 240)
        }
        .padding(.horizontal, 14).frame(height: 56)
        .background(fill)
    }

    var readout: String {
        let p = max(meter.holdL, meter.holdR)
        return p <= -60 ? "−∞ dB" : String(format: "%.1f dB", p)
    }
}

/// SoundSource's slider: a green track up to the value, a white knob; a click or drag sets it.
struct VolumeSlider: View {
    var label = "Volume"
    let value: Float
    let set: (Float) -> Void
    var body: some View {
        GeometryReader { g in
            let knobW: CGFloat = 20, w = max(1, g.size.width - knobW)
            let x = w * CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.well).frame(height: 5).padding(.horizontal, knobW / 2)
                Capsule().fill(Ink.green).frame(width: x + knobW / 2, height: 5)
                RoundedRectangle(cornerRadius: 5).fill(Color.white).frame(width: knobW, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1).offset(x: x)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in set(Float((v.location.x - knobW / 2) / w)) })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) %")
        .accessibilityAdjustableAction { d in set(value + (d == .increment ? 0.05 : -0.05)) }
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

// ---------------------------------------------------------------- the takes
// v3 (Marko, 31.10.2026): "every time I record the new waveform is opening up ... and the next one is for new recording
// automatically opening ... play button is actually pressing on the waveform itself ... I can click on to play and
// pause. And if I want to jump on different parts of the waveform, I press command and then I click on that part."
struct TakesPanel: View {
    @ObservedObject var r: Recorder
    var body: some View {
        Panel(title: "Takes", right: AnyView(
            Text(r.takes.isEmpty ? "in memory only · gone when the app quits" : "\(r.takes.count) · in memory only · gone when the app quits")
                .font(.system(size: 11)).foregroundStyle(Ink.dim))) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(r.takes) { t in TakeRow(r: r, t: t) }
                NextRow(r: r).id("next")
                HStack(spacing: 16) {
                    RecordKey(r: r)
                    VStack(alignment: .leading, spacing: 3) {
                        if r.recording {
                            (Text("REC  ").foregroundStyle(Ink.red) + Text(clock(r.current?.seconds ?? 0)).foregroundStyle(Ink.text))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        } else {
                            Text("take \(r.nextNumber)").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Ink.text)
                        }
                        Text("R record · click a take: play / pause · ⌘-click: jump · Space: the last · A: auto gain")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

/// a take: its number and time above, its waveform; the waveform is the play key
struct TakeRow: View {
    @ObservedObject var r: Recorder
    let t: Take
    var body: some View {
        let on = r.playingID == t.id
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(t.id)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(on ? Ink.green : Ink.text)
                if on { Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Ink.green) }
                Spacer()
                Text("\(clock(t.position)) / \(clock(t.seconds))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.dim)
            }
            GeometryReader { g in
                Wave(peaks: t.peaks, span: t.peaks.count, played: t.frames > 0 ? t.cursor / Double(t.frames) : 0,
                     ink: on ? Ink.green : Ink.green.opacity(0.55), rest: Ink.grey, head: on || t.cursor > 0, lit: on)
                    .contentShape(Rectangle())
                    .axButton("Take \(t.id)", id: "take\(t.id)", value: "\(on ? "playing" : "paused") \(clock(t.position)) of \(clock(t.seconds))") { r.toggle(t) }
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        if NSEvent.modifierFlags.contains(.command) { r.jump(t, Double(v.location.x / max(1, g.size.width))) }
                        else { r.toggle(t) }
                    })
                    .overlay(alignment: .topTrailing) { SaveKey(r: r, t: t).padding(6) }
            }
            .frame(height: 74)
        }
    }
}

/// SAVE in the waveform's upper right corner (v5); SAVED in green once written, the file's name on hover; again saves again
struct SaveKey: View {
    @ObservedObject var r: Recorder
    let t: Take
    var body: some View {
        let saved = t.savedTo != nil
        Text(saved ? "SAVED" : "SAVE")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(saved ? Ink.green : Ink.text)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.55)))
            .contentShape(Rectangle())
            .onTapGesture { r.save(t) }
            .axButton("Save take \(t.id)", id: "save\(t.id)", value: t.savedTo?.lastPathComponent) { r.save(t) }
            .help(t.savedTo.map { "Saved as " + $0.path } ?? "Save take \(t.id) as a WAV file")
    }
}

/// the empty row that waits for the next take; red and growing while it records
struct NextRow: View {
    @ObservedObject var r: Recorder
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(r.nextNumber)").font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(r.recording ? Ink.red : Ink.dim)
                Spacer()
            }
            ZStack {
                let p = r.current?.peaks ?? []
                Wave(peaks: p, span: max(p.count, Int(10 * r.inRate) / Recorder.block), played: 0,
                     ink: Ink.red, rest: Ink.red, head: false, lit: r.recording)
                if !r.recording {
                    Text(r.canRecord ? "● or R records take \(r.nextNumber)" : "the microphone is not allowed yet: PERMISSIONS, top right")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.dim)
                        .multilineTextAlignment(.center).padding()
                }
            }
            .frame(height: 74)
        }
    }
}

/// The loudest sample of each column, mirrored round the middle line: `ink` up to `played`, `rest` after it.
struct Wave: View {
    let peaks: [Float]
    let span: Int
    let played: Double
    let ink: Color, rest: Color
    let head: Bool
    let lit: Bool
    var body: some View {
        Canvas { c, size in
            c.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(Ink.well))
            if lit { c.stroke(Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 8), with: .color(ink.opacity(0.5)), lineWidth: 1) }
            let mid = size.height / 2
            c.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Ink.line))
            guard !peaks.isEmpty, span > 0 else { return }
            let step: CGFloat = 2
            let cols = Int(size.width / step)
            let playX = size.width * CGFloat(played)
            let usable = mid - 5
            for col in 0..<cols {
                let a = col * span / cols, b = max(a + 1, (col + 1) * span / cols)
                if a >= peaks.count { break }
                var m: Float = 0
                for i in a..<min(b, peaks.count) { m = max(m, peaks[i]) }
                let h = max(1, CGFloat(min(m, 1)) * usable)
                let x = CGFloat(col) * step
                c.fill(Path(CGRect(x: x, y: mid - h, width: step * 0.7, height: 2 * h)), with: .color(x < playX ? ink : rest))
            }
            if head {
                c.fill(Path(CGRect(x: min(playX, size.width - 1.5), y: 0, width: 1.5, height: size.height)), with: .color(.white))
            }
        }
    }
}

/// CAMERA's record circle: a ring round a red dot; recording, filled red with the time in white.
struct RecordKey: View {
    @ObservedObject var r: Recorder
    var body: some View {
        let able = r.canRecord || Permissions.missing.contains("Microphone")
        ZStack {
            if r.recording {
                let s = r.current?.seconds ?? 0
                Circle().fill(Ink.red)
                Text(String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60))
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            } else {
                Circle().stroke(able ? Ink.ring : Ink.dark, lineWidth: 2)
                Circle().fill(able ? Ink.red : Ink.dark).frame(width: 20, height: 20)
            }
        }
        .frame(width: 48, height: 48).contentShape(Circle())
        .onTapGesture { r.toggleRecord() }
        .axButton("Record", id: "record", value: r.recording ? "recording" : "stopped") { r.toggleRecord() }
        .help("Record (R)")
    }
}

/// CQ's Gain Assistant key, drawn as CQ MixPad draws its steps: a knob's arc open at the bottom, and inside it the
/// orange gear (press me; turning while it adjusts), ? listening for sound, a green ✓ done, ! on a dark disc failed.
struct AutoGainKey: View {
    @ObservedObject var r: Recorder
    static let orange = Ink.hex(0xFF5A00)
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).rotation(.degrees(135))
                .stroke(r.gain == .idle ? Ink.ring : Ink.text, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            switch r.gain {
            case .idle:
                Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(Self.orange)
            case .listening:
                Text("?").font(.system(size: 15, weight: .heavy)).foregroundStyle(Self.orange)
            case .adjusting:
                TimelineView(.animation) { tl in
                    Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(Self.orange)
                        .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate * 180))
                }
            case .done:
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Ink.green)
            case .failed:
                Circle().fill(Ink.dark).padding(5)
                Text("!").font(.system(size: 13, weight: .heavy)).foregroundStyle(Self.orange)
            }
        }
        .frame(width: 30, height: 30).contentShape(Circle())
        .opacity(r.recording ? 0.35 : 1)
        .onTapGesture { r.toggleAutoGain() }
        .axButton("Auto gain", id: "autogain", value: "\(r.gain)") { r.toggleAutoGain() }
        .help("Auto gain (A): sing or play as loud as you will; the input is set so the loudest peak sits at -12 dB, then it stops")
    }
}

/// vN, plain and dim, a hidden link to the latest build (version-visible.md). v7: no QUIT (Marko, 31.10.2026: "keep the
/// on off and remove quit"); OFF on the first row quits.
struct Footer: View {
    var body: some View {
        HStack {
            Text("v\(VERSION)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.dim)
                .onTapGesture { NSWorkspace.shared.open(RELEASES) }
                .axButton("Version \(VERSION)", id: "version") { NSWorkspace.shared.open(RELEASES) }
            Spacer()
        }
    }
}

// v4 (Marko, 31.10.2026: "Make this application accessibility compatible and close it through accessibility"): every
// word that acts is an Accessibility button with a label and an identifier, so AXPress works on it (tools/relaunch.swift
// presses "off"); a tap gesture alone is invisible to Accessibility.
extension View {
    func axButton(_ label: String, id: String, value: String? = nil, _ action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
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
            case " ": REC.toggleLast(); return nil
            case "r": REC.toggleRecord(); return nil
            case "a": REC.toggleAutoGain(); return nil
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
            .defaultSize(width: 720, height: 540)
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
        if let i = a.firstIndex(of: "--save-test"), i + 1 < a.count {
            // the WAV writer on a 3 s test take: --save-test <file.wav>
            let r = Recorder(live: false)
            do { try Recorder.writeWAV(r.addTestTake(seconds: 3), to: URL(fileURLWithPath: a[i + 1])); exit(0) }
            catch { print(error); exit(1) }
        }
        if let i = a.firstIndex(of: "--gain-test"), i + 1 < a.count {
            // the auto gain on an input whose name contains the word, its volume put back afterwards: --gain-test BlackHole
            exit(gainTest(a[i + 1]) ? 0 : 1)
        }
        RecorderApp.main()
    }

    static func shot(_ path: String, _ w: Double, _ h: Double) -> Bool {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let r = Recorder(live: false)
        r.addTestTake(seconds: 6)
        r.addTestTake(seconds: 4.5, hz: 330, shape: 2.6)
        r.addTestTake(seconds: 7, hz: 520, shape: 1.1)
        r.pose(playing: 2, at: 0.42, inDB: (-21, -24), outDB: (-13, -15), gain: .adjusting)
        let v = NSHostingView(rootView: Root(r: r))
        v.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let win = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = v                                  // never ordered in
        v.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        // v6: the scroll bar, as the scroll view says it is
        func scrolls(_ x: NSView) -> [NSScrollView] { (x as? NSScrollView).map { [$0] } ?? x.subviews.flatMap(scrolls) }
        for sc in scrolls(v) {
            let doc = sc.documentView?.frame.height ?? 0
            print(String(format: "scroll view: page %.0f in %.0f, style %@, bar %@", doc, sc.contentSize.height,
                         sc.scrollerStyle == .legacy ? "legacy (always drawn)" : "overlay",
                         sc.verticalScroller.map { $0.isHidden ? "hidden" : "shown, \(Int($0.frame.width)) wide" } ?? "none"))
        }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return false }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    static func gainTest(_ name: String) -> Bool {
        let d = UserDefaults.standard, savedIn = d.string(forKey: "input")
        let r = Recorder(live: true)
        defer { if let v = savedIn { d.set(v, forKey: "input") } else { d.removeObject(forKey: "input") } }
        guard r.chooseInput(named: name) else { print("no input named \(name)"); return false }
        let before = r.inputVolumeOnDevice
        defer { if let v = before { r.setInputVolumeOnDevice(v) }; r.forget() }
        print("input \(r.inputName), volume before \(before.map { String(format: "%.3f", $0) } ?? "none (app gain)")")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        r.toggleAutoGain()
        var last = ""
        let end = Date().addingTimeInterval(40)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let line = "\(r.gain) \(String(format: "%.3f", r.inVolume)) \(r.gainNote ?? "")"
            if line != last { print(String(format: "%5.1f dB  ", r.inMeter.holdL) + line); last = line }
            if r.gain == .done || r.gain == .failed { break }
        }
        return r.gain == .done
    }

    static func playTest(_ name: String) -> Bool {
        let r = Recorder(live: false)
        guard r.chooseOutput(named: name) else { print("no output named \(name)"); return false }
        let t = r.addTestTake(seconds: 3)
        r.play(t)
        guard r.playing else { print("did not play: \(r.error ?? "?")"); return false }
        var loudest: Float = -90
        let end = Date().addingTimeInterval(6)
        while r.playing && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            loudest = max(loudest, r.outMeter.l)
        }
        print(String(format: "played %.1f s of the test take to %@, the output meter's loudest %.1f dBFS", t.seconds, r.outputName, loudest))
        return !r.playing && loudest > -20
    }
}
