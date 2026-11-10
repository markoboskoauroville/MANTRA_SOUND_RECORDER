// SUNO: the song's time read from the Suno page in Marko's Firefox (firefoxctl, WebDriver BiDi: the player's
// currentTime and duration), a take that stops by itself at the song's end, one whole take per song, saved as WAV.
// Task 89, 10.11.2026. Nothing is changed in the system's audio in or out: the sound is Firefox's own (AppTap).
import Foundation
import AppKit

struct SunoState: Equatable {
    var ok = false, onSong = false, playing = false, ended = false
    var t = 0.0, d = 0.0
    var title = ""
    var remaining: Double { max(0, d - t) }
}

enum Firefox {
    static let ctl = NSHomeDirectory() + "/.local/bin/firefoxctl"
    static func run(_ args: [String], timeout: Double = 20) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: ctl); p.arguments = args
        var env = ProcessInfo.processInfo.environment; env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let end = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate() }
        return String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    static func runTool(_ name: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/" + name); p.arguments = args
        var env = ProcessInfo.processInfo.environment; env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let end = Date().addingTimeInterval(30)
        while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate() }
        return String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    static func eval(_ js: String) -> String { run(["-t", "suno", "eval", js]) }

    static let probeJS = """
    (()=>{const a=[...document.querySelectorAll('audio,video')].filter(x=>x.duration>5).sort((x,y)=>y.duration-x.duration)[0];\
    const s=location.pathname.startsWith('/song/');return a?JSON.stringify({t:a.currentTime,d:a.duration,p:!a.paused,e:a.ended,title:document.title,s:s}):JSON.stringify({s:s,title:document.title})})()
    """
    static func probe() -> SunoState {
        guard let data = eval(probeJS).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return SunoState() }
        let title = (j["title"] as? String ?? "").replacingOccurrences(of: " | Suno", with: "")
        guard let d = j["d"] as? Double else { return SunoState(ok: false, onSong: j["s"] as? Bool ?? false, title: title) }
        return SunoState(ok: true, onSong: j["s"] as? Bool ?? false, playing: j["p"] as? Bool ?? false, ended: j["e"] as? Bool ?? false,
                         t: j["t"] as? Double ?? 0, d: d, title: title)
    }
    static let restartJS = "(()=>{const a=[...document.querySelectorAll('audio,video')].filter(x=>x.duration>5).sort((x,y)=>y.duration-x.duration)[0];if(!a){const b=document.querySelector('button[aria-label=\"Playbar: Play button\"]')||document.querySelector('button[aria-label=\"Play\"]');if(b){b.click();return 'clicked'}return 'none'}a.pause();a.currentTime=0;a.play();return 'ok'})()"
    static let pauseJS = "(()=>{document.querySelectorAll('audio,video').forEach(a=>a.pause());return 'ok'})()"
}

/// The page's player, looked at once a second while the window is open (and the page has a song).
final class SunoWatch: ObservableObject {
    @Published var state = SunoState()
    private var timer: Timer?
    private var busy = false
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, !self.busy else { return }
            self.busy = true
            DispatchQueue.global().async {
                let s = Firefox.probe()
                DispatchQueue.main.async { if s != self.state { self.state = s }; self.busy = false }
            }
        }
    }
}

enum Clock {
    static func mmss(_ s: Double) -> String { let n = Int(s.rounded(.down)); return String(format: "%d:%02d", n / 60, n % 60) }
}

/// One song, one whole take: record from the start, stop 0.8 s after the player ends, keep it as a WAV.
final class SunoSession: ObservableObject {
    @Published var note = ""
    @Published var running = false
    let r: Recorder
    var lastDuration = 0.0
    var cancel = false
    init(_ r: Recorder) { self.r = r }

    /// runs on a background thread; returns the take (nil on failure)
    func recordSong(startPlayback: Bool = true, log: @escaping (String) -> Void = { _ in }) -> Take? {
        var s = Firefox.probe()
        guard s.onSong else { log("Firefox is not on a Suno song page"); return nil }
        DispatchQueue.main.sync { r.chooseInput(Recorder.fireUID) }
        var waited = 0.0
        while !(DispatchQueue.main.sync { r.appReady }) && waited < 15 { Thread.sleep(forTimeInterval: 0.2); waited += 0.2 }
        guard DispatchQueue.main.sync(execute: { r.appReady }) else { log("Firefox audio did not start: \(DispatchQueue.main.sync { r.error ?? "?" })"); return nil }
        if s.ok { _ = Firefox.eval(Firefox.pauseJS); Thread.sleep(forTimeInterval: 0.5) }
        DispatchQueue.main.sync { r.record() }
        if startPlayback {
            _ = Firefox.eval(Firefox.restartJS)
            Thread.sleep(forTimeInterval: 1.5)
            if !Firefox.probe().playing { log("autoplay refused: real click"); _ = Firefox.run(["-t", "suno", "eval", "1"], timeout: 5); _ = Firefox.runTool("suno_play", ["play"]) }
        }
        running = true
        var lastLog = Date.distantPast
        var seenPlaying = false, idle = 0
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            if cancel { break }
            s = Firefox.probe()
            if s.ok { lastDuration = s.d }
            if s.playing { seenPlaying = true; idle = 0 }
            if Date().timeIntervalSince(lastLog) > 10 { log("\(s.title) \(Clock.mmss(s.t)) / \(Clock.mmss(s.d)), \(Clock.mmss(s.remaining)) left"); lastLog = Date() }
            let atEnd = s.ok && (s.ended || (seenPlaying && !s.playing && s.t >= s.d - 1.0))
            if atEnd { break }
            if seenPlaying && !s.playing { idle += 1; if idle > 20 { log("the player stopped before the end"); break } }
            if !seenPlaying { idle += 1; if idle > 40 { log("the song never started"); break } }
        }
        Thread.sleep(forTimeInterval: 0.8)
        var take: Take?
        DispatchQueue.main.sync { r.stopRecording(); take = r.takes.last }
        running = false
        _ = Firefox.eval(Firefox.pauseJS)
        if let t = take, lastDuration > 5 { Self.trim(t, to: lastDuration) }
        return take
    }

    /// the page's start-up and the 0.8 s tail are not the song: the take begins 0.05 s before the first sound and is the
    /// song's length plus 0.2 s (one whole take, only its ends are cut, nothing inside it)
    static func trim(_ t: Take, to d: Double) {
        let thr: Float = 0.001                         // -60 dBFS
        var first = 0
        while first < t.frames && max(abs(t.l[first]), abs(t.r[first])) < thr { first += 1 }
        let a = max(0, first - Int(0.05 * t.rate)), b = min(t.frames, a + Int((d + 0.2) * t.rate))
        t.l = Array(t.l[a..<b]); t.r = Array(t.r[a..<b])
        t.peaks = stride(from: 0, to: t.frames, by: 256).map { s in
            var m: Float = 0
            for i in s..<min(t.frames, s + 256) { m = max(m, abs(t.l[i]), abs(t.r[i])) }
            return m
        }
    }
}

extension SunoSession {
    /// one app's sound for `seconds` (nil: until `cancel`), whatever it plays
    func recordApp(bundle: String, seconds: Double?) -> Take? {
        DispatchQueue.main.sync { r.chooseInput("app:" + bundle) }
        var waited = 0.0
        while !(DispatchQueue.main.sync { r.appReady }) && waited < 15 { Thread.sleep(forTimeInterval: 0.2); waited += 0.2 }
        guard DispatchQueue.main.sync(execute: { r.appReady }) else { return nil }
        DispatchQueue.main.sync { r.record() }
        let start = Date()
        while !cancel && (seconds == nil || Date().timeIntervalSince(start) < seconds!) { Thread.sleep(forTimeInterval: 0.2) }
        var take: Take?
        DispatchQueue.main.sync { r.stopRecording(); take = r.takes.last }
        return take
    }
}

extension Recorder { static let fireUID = "app:org.mozilla.firefox" }
