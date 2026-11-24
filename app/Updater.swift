// Updater.swift (v17, v18: the install log ~/Library/Logs/MantraSoundRecorder-update.log shows the designated requirement): the app replaces itself from its own GitHub releases. Based on MANTRA_MANIFEST kits/mac-updater, but
// automatic (Marko, 24.11.2026): no question; and never while takes are unsaved in memory.
//
// At start (in the background): the Latest release of the public repo through the unauthenticated GitHub API (curl).
// A tag vN with N > VERSION: app.zip is downloaded to ~/Library/Caches/<bundle id>/update and unpacked. With no takes and
// no recording, a detached script waits for this app to quit, signs the new copy "Mantra Apps" (the Accessibility and
// Microphone permissions stay), swaps it in at the same path and opens it. With takes, nothing is quit: the status
// reads "vN ready: installs when you quit", the swap happens when the app is quit (OFF, quit) without reopening, and
// when the takes are gone (every 20 s a check) it installs at once. Nothing newer, no network: silent.
import AppKit
import SwiftUI

final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "markoboskoauroville/MANTRA_SOUND_RECORDER"
    static let asset = "app.zip"
    static let sign = "Mantra Apps"

    /// the dim words in the footer beside vN; empty = nothing to say
    @Published private(set) var status = ""
    private var ready: URL?
    private var readyVersion = 0
    private var busy = false
    private var installing = false
    private var timer: Timer?

    private var cache: URL {
        let id = Bundle.main.bundleIdentifier ?? "community.auroville.mantrasoundrecorder"
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/\(id)/update")
    }

    func checkAtStart(delay: Double = 5) {
        guard !busy else { return }
        busy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.status = "checking for an update" }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            let found = self.findAndDownload()
            DispatchQueue.main.async {
                self.busy = false
                if let (v, app) = found { self.ready = app; self.readyVersion = v; self.tryInstall() }
                else { self.status = "" }
            }
        }
    }

    private func findAndDownload() -> (Int, URL)? {
        guard let out = Self.run("/usr/bin/curl", ["-sL", "-m", "20", "-H", "Accept: application/vnd.github+json",
                                                   "https://api.github.com/repos/\(Self.repo)/releases/latest"]),
              let j = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let tag = j["tag_name"] as? String, let v = Int(tag.filter(\.isNumber)) else { Self.log("no release info"); return nil }
        guard v > VERSION else { Self.log("v\(VERSION) is the newest (Latest is \(tag))"); return nil }
        guard let assets = j["assets"] as? [[String: Any]],
              let a = assets.first(where: { ($0["name"] as? String) == Self.asset }),
              let url = a["browser_download_url"] as? String else { Self.log("no \(Self.asset) in \(tag)"); return nil }
        let fm = FileManager.default
        let dir = cache.appendingPathComponent(tag)
        let zip = dir.appendingPathComponent(Self.asset)
        let unpacked = dir.appendingPathComponent("app")
        let appName = (Bundle.main.bundlePath as NSString).lastPathComponent
        let newApp = unpacked.appendingPathComponent(appName)
        if !fm.fileExists(atPath: newApp.path) {          // never the same version twice
            DispatchQueue.main.async { self.status = "downloading v\(v)" }
            try? fm.removeItem(at: cache)
            try? fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            guard Self.run("/usr/bin/curl", ["-sfL", "-m", "600", "-o", zip.path, url]) != nil,
                  Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) != nil,
                  fm.fileExists(atPath: newApp.path) else { Self.log("download of \(tag) failed"); try? fm.removeItem(at: dir); return nil }
        }
        Self.log("v\(v) downloaded")
        return (v, newApp)
    }

    /// installs now when nothing would be lost; otherwise waits for the quit or for the takes to be gone
    private func tryInstall() {
        guard let app = ready, !installing else { return }
        if REC.takes.isEmpty && !REC.recording && REC.current == nil {
            timer?.invalidate(); timer = nil
            status = "updating to v\(readyVersion)"
            launch(app, reopen: true)
            installing = true
            // a moment for the status to show, then the app quits and the script swaps it in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
        } else {
            status = "v\(readyVersion) ready: installs when you quit"
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.tryInstall() }
            }
        }
    }

    /// called from applicationWillTerminate: a ready update is swapped in after the quit (not reopened)
    func installOnQuit() {
        guard let app = ready, !installing else { return }
        installing = true
        launch(app, reopen: false)
    }

    private func launch(_ newApp: URL, reopen: Bool) {
        let target = Bundle.main.bundlePath
        let script = cache.appendingPathComponent("install.sh")
        let sh = """
        #!/bin/sh
        T="$1"; N="$2"; P="$3"; S="$4"; O="$5"; C="$6"
        while kill -0 "$P" 2>/dev/null; do sleep 0.2; done
        xattr -dr com.apple.quarantine "$N" 2>/dev/null
        L="$HOME/Library/Logs/MantraSoundRecorder-update.log"; mkdir -p "$HOME/Library/Logs"
        echo "$(date) installing over $T" >> "$L"
        codesign --force -s "$S" "$N" >> "$L" 2>&1 || { echo "codesign with $S FAILED: update not installed" >> "$L"; [ "$O" = "1" ] && open "$T"; exit 1; }
        codesign -dr - "$N" >> "$L" 2>&1
        rm -rf "$T.old"; mv "$T" "$T.old" || { [ "$O" = "1" ] && open "$T"; exit 1; }
        if ditto "$N" "$T"; then rm -rf "$T.old"; else rm -rf "$T"; mv "$T.old" "$T"; fi
        rm -rf "$C"
        [ "$O" = "1" ] && open "$T"
        exit 0
        """
        do { try sh.write(to: script, atomically: true, encoding: .utf8) } catch { Self.log("script failed: \(error)"); installing = false; return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, target, newApp.path, String(getpid()), Self.sign, reopen ? "1" : "0", cache.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { Self.log("install failed: \(error)"); installing = false; return }
        Self.log("installing \(newApp.path) over \(target)")
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> String? {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    static func log(_ s: String) { NSLog("[Updater] %@", s) }
}
