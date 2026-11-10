// SUNO: the song's time read from the Suno page in Marko's Firefox (firefoxctl, WebDriver BiDi: the player's
// currentTime and duration), a take that stops by itself at the song's end, one whole take per song, saved as WAV.
// Task 89, 10.11.2026. Nothing is changed in the system's audio in or out: the sound is Firefox's own (AppTap).
import Foundation
import AppKit

struct SunoState: Equatable {
    var ok = false, playing = false, ended = false
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
    static func eval(_ js: String) -> String { run(["-t", "suno", "eval", js]) }

    static let probeJS = """
    (()=>{const a=[...document.querySelectorAll('audio,video')].filter(x=>x.duration>5).sort((x,y)=>y.duration-x.duration)[0];\
    return a?JSON.stringify({t:a.currentTime,d:a.duration,p:!a.paused,e:a.ended,title:document.title}):'{}'})()
    """
    static func probe() -> SunoState {
        guard let data = eval(probeJS).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let d = j["d"] as? Double else { return SunoState() }
        return SunoState(ok: true, playing: j["p"] as? Bool ?? false, ended: j["e"] as? Bool ?? false,
                         t: j["t"] as? Double ?? 0, d: d, title: (j["title"] as? String ?? "").replacingOccurrences(of: " | Suno", with: ""))
    }
    static let restartJS = "(()=>{const a=[...document.querySelectorAll('audio,video')].filter(x=>x.duration>5).sort((x,y)=>y.duration-x.duration)[0];if(!a)return 'none';a.pause();a.currentTime=0;a.play();return 'ok'})()"
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
    init(_ r: Recorder) { self.r = r }

    /// runs on a background thread; returns the take (nil on failure)
    func recordSong(startPlayback: Bool = true, log: @escaping (String) -> Void = { _ in }) -> Take? {
        var s = Firefox.probe()
        guard s.ok else { log("no Suno player in the page"); return nil }
        DispatchQueue.main.sync { r.chooseInput(Recorder.fireUID) }
        var waited = 0.0
        while !(DispatchQueue.main.sync { r.appReady }) && waited < 15 { Thread.sleep(forTimeInterval: 0.2); waited += 0.2 }
        guard DispatchQueue.main.sync(execute: { r.appReady }) else { log("Firefox audio did not start: \(DispatchQueue.main.sync { r.error ?? "?" })"); return nil }
        _ = Firefox.eval(Firefox.pauseJS); Thread.sleep(forTimeInterval: 0.5)
        DispatchQueue.main.sync { r.record() }
        if startPlayback { _ = Firefox.eval(Firefox.restartJS) }
        running = true
        var lastLog = Date.distantPast
        var seenPlaying = false, idle = 0
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            s = Firefox.probe()
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
        return take
    }
}

extension Recorder { static let fireUID = "app:org.mozilla.firefox" }
