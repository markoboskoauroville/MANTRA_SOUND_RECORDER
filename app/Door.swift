// THE DOOR: the Star API functions of Sound Recorder (Mantra), JSON over HTTP on 127.0.0.1:8869, reached through
// STAR_API (`star fn "sound recorder" record.suno '{"out":"..."}'` or POST :8863/apps/sound recorder/fn/record.suno).
// Task 89, 10.11.2026 (Marko: "We are developing API always for my Star app, which include new functions to record sound
// from browser or whatever is happening"). Functions: record.app, record.suno, record.status, record.stop, permissions.
import Foundation
import Network
import AppKit

final class Door {
    static let shared = Door()
    static let port: UInt16 = 8869
    private var listener: NWListener?
    private let q = DispatchQueue(label: "door")
    // the job in progress or the last one
    private var job: [String: Any] = ["state": "idle"]
    private let lock = NSLock()
    private func setJob(_ k: String, _ v: Any) { lock.lock(); job[k] = v; lock.unlock() }
    private func getJob() -> [String: Any] { lock.lock(); defer { lock.unlock() }; return job }
    private var session: SunoSession?

    func start() {
        guard listener == nil, let l = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Door.port)!) else { return }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: q); listener = l
        // the registry the Star API reads
        let dir = NSHomeDirectory() + "/.config/star-fns"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let reg: [String: Any] = ["app": "Sound Recorder (Mantra)", "port": Int(Door.port),
            "functions": ["record.app": "{bundle, out, gain_db?, seconds?} record one app's sound (ScreenCaptureKit); stops at seconds or record.stop",
                          "record.suno": "{out, url?} record the song playing in Suno in Firefox, from its start to its end, one WAV; returns at once, see record.status",
                          "record.status": "{} recording?, elapsed, left, title, duration, file, last result",
                          "record.stop": "{} stop and save the take now", "permissions": "{} granted / missing permissions"]]
        if let d = try? JSONSerialization.data(withJSONObject: reg, options: [.prettyPrinted]) { try? d.write(to: URL(fileURLWithPath: dir + "/sound-recorder.json")) }
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: q)
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else { c.cancel(); return }
            let first = text.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let path = first.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let body = text.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
            let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            let fn = path.hasPrefix("/fn/") ? String(path.dropFirst(4)) : String(path.dropFirst())
            let out = self.call(fn, args)
            let json = (try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted])) ?? Data("{}".utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
            c.send(content: Data(head.utf8) + json, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private func expand(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
    private func main<T>(_ f: () -> T) -> T { DispatchQueue.main.sync(execute: f) }

    func call(_ fn: String, _ a: [String: Any]) -> [String: Any] {
        switch fn {
        case "permissions":
            var granted: [String] = [], missing: [String] = []
            for p in ["Screen Recording", "Microphone"] { (Permissions.allowed(p) ? { granted.append(p) } : { missing.append(p) })() }
            return ["ok": true, "granted": granted, "missing": missing]
        case "record.status":
            let j = getJob()
            let rec = main { REC.recording }, el = main { REC.elapsedNow }
            var r: [String: Any] = ["ok": true, "recording": rec, "elapsed": (el * 10).rounded() / 10, "job": j]
            if let s = session, s.lastDuration > 0 { r["duration"] = s.lastDuration; r["left"] = max(0, s.lastDuration - el) }
            return r
        case "record.stop":
            guard main({ REC.recording }) else { return ["ok": false, "message": "not recording"] }
            session?.cancel = true
            return ["ok": true, "message": "stopping; see record.status"]
        case "record.app", "record.suno":
            guard !main({ REC.recording }), (getJob()["state"] as? String) != "recording" else { return ["ok": false, "message": "already recording"] }
            guard Permissions.allowed("Screen Recording") else { return ["ok": false, "message": "Screen Recording is not allowed for Sound Recorder (Mantra)", "missing": ["Screen Recording"]] }
            guard let out = a["out"] as? String else { return ["ok": false, "message": "out (file path) is required"] }
            let gain = (a["gain_db"] as? Double) ?? -3
            main { REC.appGain = Float(pow(10, gain / 20)) }
            let url = expand(out)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let started = Date()
            setJob("state", "recording"); setJob("file", url.path); setJob("kind", fn); setJob("started", ISO8601DateFormatter().string(from: started))
            let sess = SunoSession(REC); session = sess
            let bundle = (a["bundle"] as? String) ?? "org.mozilla.firefox"
            let secs = a["seconds"] as? Double
            let song = a["url"] as? String
            DispatchQueue.global().async {
                var take: Take?
                if fn == "record.suno" {
                    if let u = song { _ = Firefox.run(["-t", "suno", "open", u], timeout: 60); Thread.sleep(forTimeInterval: 2) }
                    take = (a["wait_for_play"] as? Bool == true ? sess.recordWhenPressed : { sess.recordSong(log: $0) })({ [weak self] m in self?.setJob("note", m) })
                    _ = 0 // { [weak self] m in self?.setJob("note", m) })
                    self.setJob("title", Firefox.probe().title)
                } else {
                    take = sess.recordApp(bundle: bundle, seconds: secs)
                }
                guard let t = take else {
                    self.setJob("state", "failed"); self.setJob("error", sess.failure ?? self.main { REC.error ?? "no take" })
                    self.setJob("action", "record again: the partial take was deleted")
                    try? FileManager.default.removeItem(at: url); return }
                do {
                    try Recorder.writeWAV(t, to: url)
                    var peak: Float = 0
                    for i in 0..<t.frames { peak = max(peak, abs(t.l[i]), abs(t.r[i])) }
                    self.setJob("state", "done"); self.setJob("seconds", (t.seconds * 100).rounded() / 100)
                    self.setJob("peak_dbfs", (20 * log10(Double(max(peak, 0.00001))) * 10).rounded() / 10)
                    self.setJob("suno_duration", sess.lastDuration)
                } catch { self.setJob("state", "failed"); self.setJob("error", "save failed: \(error)") }
            }
            return ["ok": true, "message": "recording started; poll record.status", "file": url.path]
        default:
            return ["ok": false, "message": "functions: record.app record.suno record.status record.stop permissions"]
        }
    }
}
