// THE DOOR: the Star API functions of Sound Recorder (Mantra), JSON over HTTP on 127.0.0.1:8869, reached through
// STAR_API (`star fn "sound recorder" record.suno '{"out":"..."}'` or POST :8863/apps/sound recorder/fn/record.suno).
// Task 89, 10.11.2026 (Marko: "We are developing API always for my Star app, which include new functions to record sound
// from browser or whatever is happening"). Functions: record.app, record.suno, record.status, record.stop, permissions.
// v13 (10.11.2026, task 99): the Chrome channel. The extension Chrome Suno Controller (repo CHROME_SUNO_CONTROLLER) polls
// chrome.poll once a second; sunoctl / Claude put commands in with chrome.send and read them back with chrome.result.
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
    // v13: the Chrome channel (commands for the extension, its replies, its last heartbeat)
    private var cq: [[String: Any]] = []
    private var results: [String: [String: Any]] = [:]
    private var chromeState: [String: Any] = [:]
    private var chromeSeen: Date?
    private var nextId = 1

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
                          "record.stop": "{} stop and save the take now", "permissions": "{} granted / missing permissions",
                          "chrome.send": "{cmd, args} a command for the Chrome Suno Controller extension (state, list, open, play, pause, record, create); returns id",
                          "chrome.result": "{id} the extension's answer, or pending",
                          "chrome.state": "{} the extension's last heartbeat (page, player) and its age",
                          "chrome.poll": "{state} (the extension) heartbeat; returns the waiting commands",
                          "chrome.reply": "{id, result} (the extension) the answer to a command"]]
        if let d = try? JSONSerialization.data(withJSONObject: reg, options: [.prettyPrinted]) { try? d.write(to: URL(fileURLWithPath: dir + "/sound-recorder.json")) }
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: q)
        read(c, Data())
    }
    /// reads until the head is in and the body has its Content-Length (lyrics can be longer than one packet)
    private func read(_ c: NWConnection, _ acc: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, done, err in
            guard let self = self else { c.cancel(); return }
            var buf = acc; if let d = data { buf.append(d) }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
                let len = head.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                if buf.count - r.upperBound >= len || done || err != nil { self.answer(c, head, Data(buf[r.upperBound...])); return }
            } else if done || err != nil || buf.count > 1_000_000 { c.cancel(); return }
            self.read(c, buf)
        }
    }
    private func answer(_ c: NWConnection, _ head: String, _ body: Data) {
        let first = head.components(separatedBy: "\r\n").first ?? ""
        let parts = first.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let path = parts.dropFirst().first.map(String.init) ?? "/"
        let cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\n"
        if method == "OPTIONS" {
            let h = "HTTP/1.1 204 No Content\r\n\(cors)Content-Length: 0\r\nConnection: close\r\n\r\n"
            c.send(content: Data(h.utf8), completion: .contentProcessed { _ in c.cancel() }); return
        }
        let args = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let fn = path.hasPrefix("/fn/") ? String(path.dropFirst(4)) : String(path.dropFirst())
        let out = self.call(fn, args)
        let json = (try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted])) ?? Data("{}".utf8)
        let h = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\(cors)Content-Length: \(json.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(h.utf8) + json, completion: .contentProcessed { _ in c.cancel() })
    }

    private func expand(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
    private func main<T>(_ f: () -> T) -> T { DispatchQueue.main.sync(execute: f) }

    func call(_ fn: String, _ a: [String: Any]) -> [String: Any] {
        switch fn {
        case "permissions":
            var granted: [String] = [], missing: [String] = []
            for p in ["Screen Recording", "Microphone"] { (Permissions.allowed(p) ? { granted.append(p) } : { missing.append(p) })() }
            return ["ok": true, "granted": granted, "missing": missing]
        case "chrome.send":
            guard let cmd = a["cmd"] as? String else { return ["ok": false, "message": "cmd is required"] }
            lock.lock(); let id = "c\(nextId)"; nextId += 1
            cq.append(["id": id, "cmd": cmd, "args": a["args"] ?? [String: Any]()]); lock.unlock()
            let age = chromeSeen.map { Date().timeIntervalSince($0) } ?? 9999
            return ["ok": true, "id": id, "extension_seen_s": (age * 10).rounded() / 10,
                    "message": age < 5 ? "queued" : "queued, but the extension has not polled for \(Int(age)) s (is Chrome open with Chrome Suno Controller?)"]
        case "chrome.poll":
            lock.lock(); chromeSeen = Date(); if let st = a["state"] as? [String: Any] { chromeState = st }
            let out = cq; cq = []; lock.unlock()
            return ["ok": true, "commands": out]
        case "chrome.reply":
            guard let id = a["id"] as? String else { return ["ok": false, "message": "id is required"] }
            lock.lock(); results[id] = (a["result"] as? [String: Any]) ?? ["value": a["result"] ?? NSNull()]; lock.unlock()
            return ["ok": true]
        case "chrome.result":
            guard let id = a["id"] as? String else { return ["ok": false, "message": "id is required"] }
            lock.lock(); let r = results[id]; lock.unlock()
            return r.map { ["ok": true, "done": true, "result": $0] } ?? ["ok": true, "done": false, "message": "pending"]
        case "chrome.state":
            lock.lock(); defer { lock.unlock() }
            let age = chromeSeen.map { Date().timeIntervalSince($0) } ?? -1
            return ["ok": true, "connected": age >= 0 && age < 5, "seen_s": (age * 10).rounded() / 10, "state": chromeState]
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
            lock.lock(); job = [:]; lock.unlock()          // v13: a fresh job, no notes or errors left from the last take
            setJob("state", "recording"); setJob("file", url.path); setJob("kind", fn); setJob("started", ISO8601DateFormatter().string(from: started))
            let sess = SunoSession(REC); session = sess
            let bundle = (a["bundle"] as? String) ?? "org.mozilla.firefox"
            let secs = a["seconds"] as? Double
            let song = a["url"] as? String
            let trim = (a["trim"] as? Bool) ?? false
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
                if trim, let t0 = take { take = Door.trimmed(t0) }
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
            return ["ok": false, "message": "functions: record.app record.suno record.status record.stop permissions chrome.send chrome.result chrome.state chrome.poll chrome.reply"]
        }
    }
}

extension Door {
    /// v13: the digital silence before the first sound and after the last one cut off (below -70 dBFS), 50 ms kept each side
    static func trimmed(_ t: Take) -> Take {
        let th: Float = 0.000316, n = t.frames
        var a = 0; while a < n && abs(t.l[a]) < th && abs(t.r[a]) < th { a += 1 }
        var b = n - 1; while b > a && abs(t.l[b]) < th && abs(t.r[b]) < th { b -= 1 }
        if a >= b { return t }
        let pad = Int(t.rate * 0.05)
        let s = max(0, a - pad), e = min(n, b + 1 + pad)
        t.l = Array(t.l[s..<e]); t.r = Array(t.r[s..<e])
        return t
    }
}
