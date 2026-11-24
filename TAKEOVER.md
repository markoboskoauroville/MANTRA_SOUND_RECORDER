# TAKEOVER: Sound Recorder (Mantra)

**Version 18** (24.11.2026: App recorder panel, any running app, Stereo/Mono, permissions without restart) · Version 17 (24.11.2026: recording format Quality / Bits / Sample rate, automatic self-update) · Version 16 (24.11.2026: input monitoring, built by GitHub Actions) · Version 15 (10.11.2026: "App audio (<app>)" inputs, BlackHole not offered) · Version 14 (10.11.2026, task 99: Chrome through a CoreAudio process tap) · Version 13 (10.11.2026: the Chrome channel) · Version 12 (10.11.2026, task 89: Firefox app capture, Suno panel) · Version 11 (1.11.2026) · **closed by Marko 1.11.2026** (before: closed at v8, 31.10.2026) · repo markoboskoauroville/MANTRA_SOUND_RECORDER (private) ·
`/Applications/Sound Recorder (Mantra).app`, bundle id `community.auroville.mantrasoundrecorder`.
The reasons behind the choices are in [LESSONS.md](LESSONS.md).

## What it is

Marko's simple recorder: record, play, see the waveform; nothing kept after the app quits. Its look is SoundSource's
(Rogue Amoeba), as it was open on his screen on 31.10.2026: a dark ground, rounded panels, an Output row and a green
Input row, each with its meter and device menu.

## The window, top to bottom

- **First row** (in the hidden title bar, beside the traffic lights): ON (green) / OFF (grey; quits), the name
  centred, TOP (green: the window floats above every other window; kept in UserDefaults `onTop`), PERMISSIONS (amber, only while the microphone is not allowed; a click asks once, then opens the
  Microphone page of System Settings), ✕ (closes the window, the app stays on).
- **Devices**: Output and Input rows: icon, name, a volume slider (SoundSource's: green track, white knob) with its % over a stereo meter (L over R, -60…0 dBFS, green to -12, amber to -3,
  red above, white tick = peak held 1.5 s, the bar falls 24 dB/s), the held peak in dB, the device menu. The input
  menu is locked while recording. Choices are kept in UserDefaults by device UID; a vanished device falls back to
  the Mac's default. An amber line under the rows shows a device error.
- **Auto gain** (the Input row, CQ's Gain Assistant): a knob arc with an orange gear. Pressed (or A): ? listens for
  sound (15 s), the gear turns while it measures the loudest peak for 2 s and moves the input's volume (in dB when the
  device says its dB range, otherwise the scalar or the app's gain) until that peak is within 1.5 dB of -12 dBFS
  (up to 8 rounds); then a green ✓ for 4 s and it is off. ! and an amber line when it fails. A line under the rows
  says what it is doing.
- **Above 0 dB (v10, v11, 1.11.2026):** everything is in dB, never %. The sliders are dB scales, linear in dB:
  -60 dB at the left (far left = silence) up to the device's top; the Input slider goes on past a 0 dB mark into the
  app's own boost, to +32 dB (amber). The auto gain raises the volume to its top first, then the boost; down, the
  boost goes first. The slider is the indicator: it follows the auto gain. Boost saved in defaults as `inBoost`.
  `--slider-test <input>` sets positions and reads the dB back.
- **Input monitoring (v16, 24.11.2026)**: the Input row's mic tile is a switch (AX button `monitor`, label "Input monitoring"; green when on; UserDefaults `monitorOn`, off by default). On, a row opens under the Input row: "Monitoring buffer" with a menu of 32 / 64 / 128 / 256 / 512 / 1024 frames, each with its milliseconds at the input's rate (`monitorBuf`, default 128), a dim "about N ms through your devices" line (latencies read from CoreAudio), an amber "feedback risk: use headphones" always, and an amber line when a device refuses or clamps the size.
- **Format row (v17, 24.11.2026)**: under the Input (and monitoring) row, three menus with AX identifiers `quality`, `bits`, `rate`, locked while recording. Quality presets (CD 16/44.1, Standard 24/48, Studio 24/96, Max 32 float/192 or the device's top, Custom when bits and rate match none; `recQuality`), Bits 16 / 24 / 32 float (`recBits`, default 24; applied by SAVE, 16 bit with TPDF dither; the take is held as float and carries its bits from the moment it starts), Sample rate Auto (the device's) or a rate the input really offers (`recRate`, read from kAudioDevicePropertyAvailableNominalSampleRates; the input and, if it offers the rate, the output device are set; an amber line when the input refuses). A dim line gives the size per minute. App-audio inputs have a fixed rate: the rate menu is grey with a note. The take's rate is read back from the device when recording starts.
- **Channels (v18)**: a fourth Format menu, AX `channels`, Stereo (default) / Mono (`recChannels`), locked while recording. A mono take stores the L+R average on both sides while it is drained (so it plays on both outputs and no clipping), `Take.mono` is fixed at the start, SAVE writes a 1-channel WAV (16 bit dither on one channel), the size line halves. Presets only set bits and rate; monitoring and meters are untouched.
- **App recorder (v18)**: the panel that was "Suno" is "App recorder", collapsible (header AX `apprec`, state `apprecOpen`, default open). Its App menu (AX `apprec-menu`) lists "App audio (<name>)" for every running Dock app (NSWorkspace, updated when apps launch or quit, also in the Input menu); choosing one makes it the Input. Backend: CoreAudio process tap (`ProcTap.preferred`: Chrome/Edge/Brave, or any app CoreAudio already lists a process for), Firefox and silent apps ScreenCaptureKit. The Suno clocks and button are a small sub-section "Suno" (AX `apprec-suno`, `apprecSuno`, default closed; the Firefox poll runs only while it is open).
- **Permissions (v18)**: the window checks every second and when the app becomes active; a granted microphone opens the input at once, the system question is asked at start while undetermined. An app input that failed is retried every 3 s. Screen Recording granted: the source is reopened; if macOS still refuses after 3 s the app relaunches itself (only with no takes), else an amber line. Why a prompt came with every version: v17 as installed from the release is ad hoc (designated requirement = the build's cdhash; measured with `codesign -dr -`, installed app equals the release zip), so TCC saw a new app each build. The updater's script signs "Mantra Apps" (requirement = bundle id + the certificate), so from the first self-updated version on it is stable; the transition v17 to v18 asks once. The install log is ~/Library/Logs/MantraSoundRecorder-update.log (shows the requirement).
- **Self-update (v17)**: app/Updater.swift (from kits/mac-updater, automatic, no question). At start (not in test modes) it reads the Latest release of the public repo through api.github.com (curl), downloads app.zip to ~/Library/Caches/<bundle id>/update, unpacks it; with no takes and no recording a detached script waits for the quit, signs "Mantra Apps", swaps it in and reopens; with takes it waits ("vN ready: installs when you quit", footer status next to vN, rechecked every 20 s) and swaps at quit (OFF / quit) without reopening. Footer status: checking, downloading, updating.
- **Takes**: every recording of the session is its own waveform, numbered, oldest on top, with `position / length`.
  **A click on a waveform plays / pauses it** (there is no play key); **⌘-click jumps there and plays**. **SAVE** in each waveform's upper right corner opens a save dialog (the last
  folder, at first ~/Music; name "Take N - d.M.yyyy HH.mm.wav") and writes WAV, stereo, at the take's rate and bits (v17: 16 / 24 / 32 float, default 24);
  it then reads SAVED in green (hover: the path). One take plays
  at a time; each keeps its playhead. Below them the next take's empty row (red and growing while recording), then
  the record circle and "take N". Space plays / pauses the last played (or the newest).
- **Scroll bar**: the page scrolls; while it is taller than the window a real (legacy, always drawn) scroll bar shows
  at the right and the page narrows by its width, so nothing goes under it (`Scroller`, `ContentHeight`).
- **Footer**: `vN` (dim, opens the latest release). No QUIT since v7: OFF on the first row quits.
- **Accessibility**: every word or shape that acts is an Accessibility button with a label and an identifier
  (`off`, `top`, `close`, `permissions`, `record`, `autogain`, `take<N>`, `version`); the sliders are adjustable
  (± 5 %). `axButton` in app/App.swift.
- Keys: **R** record / stop, **Space** the last take, **A** auto gain.

## The model

- `Recorder` (app/Audio.swift) owns everything. CoreAudio IOProcs straight on the devices
  (`AudioDeviceCreateIOProcIDWithBlock`), never AVAudioEngine.
- The **input** IOProc runs whenever the microphone is allowed (the meter always moves); it writes stereo float
  frames into a `Ring` (a mono device is doubled to both sides). 30 times a second the main thread drains the ring
  into the take (`takeL`, `takeR`) while recording, and makes the waveform: the loudest sample of every 256 frames.
- The **output** IOProc runs only while playing. It reads a copy of the take at the output device's own rate (step
  = take rate / output rate, linear interpolation), so the device's rate is never changed.
- **Monitoring (v16)**: the input IOProc (and the App-audio sink) also writes the gained frames into `monL/monR`, a second ring of 32768 frames whose write counter is a 64-bit word published with `OSMemoryBarrier()`: one writer, one reader, no lock, no allocation. The ONE output IOProc (`startOutputProc`) now runs while a take plays OR monitoring is on; it mixes the take and the ring (linear resampling by input rate / output rate), applies the output volume (device's own, else `outSoft`), clamps to ±1. It waits until one input chunk + one output buffer have arrived, skips to that target when the ring holds more than three times that (latency never grows), and goes silent and waits again on an underrun. `applyMonitor()` sets `kAudioDevicePropertyBufferFrameSize` on both devices (clamped to their range) and recomputes the estimate; it runs on toggle, buffer, input or output change. pause() stops the proc before a take is freed and restarts it for monitoring. forget() (OFF, quit) switches monitoring off; the saved choice stays. Monitoring is never recorded (the take reads the main ring only).
- **Volume**: `VolumeWatch` moves the device's own volume (kAudioDevicePropertyVolumeScalar, element 0, or each
  channel element as on the ADAM: 1 and 2) and listens to it, so the volume keys and System Settings move the slider.
  A device without a settable volume gets the app's own gain (`inSoft` / `outSoft`, UserDefaults `inGain` / `outGain`),
  applied in the IOProcs.
- **Deleting**: the take is never written to disk. OFF and ⌘Q call `forget()` (devices released, arrays
  emptied); a crash leaves nothing either. Closing the window keeps the app ON and the take with it (swift-apps.md).

## The files

| File | What |
|---|---|
| `app/App.swift` | the window (SwiftUI), the colours (`Ink`), keys, `--shot` and `--play-test` |
| `app/Audio.swift` | devices, the ring, meters, recording, playing, permissions |
| `icon/make_icon.swift` | the icon, drawn with the version under it |
| `build.sh` | swiftc, Info.plist, icon, signed "Mantra Apps", copied to /Applications, then the running copy quit and the new one opened |
| `tools/relaunch.swift` | presses the running copy's OFF (QUIT in v4–v6) through Accessibility (or its menu's Quit), waits for it to go, opens the new one; never kills |

## Building and testing

```sh
./build.sh
```

Every build quits the running copy through Accessibility and opens the new one (Marko, 31.10.2026), unless that
copy holds takes: then it is left running and says so (exit 3). `./build.sh --no-run` only builds.

```sh
"build/Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --shot docs/window.png 720 520
```

```sh
"build/Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --play-test BlackHole
```

```sh
"build/Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --gain-test BlackHole
```

`--save-test <file.wav>` writes a 3 s test take through the SAVE writer. `--gain-test` runs the auto gain on that input (play a tone into it with sox first) and puts its volume back.

`--shot` draws the window off screen with a test take; `--play-test <name>` plays a 3 s 440 Hz test take to the output
whose name contains the word and never changes the saved choice. Test audio goes to BlackHole, never the ADAM.

## What has never been proven

- **No real recording yet**: the app has no Microphone permission until Marko grants it; the input IOProc, the
  ring drain and the live red waveform have not run with a real signal.
- Playback into BlackHole 2ch was measured (31.10.2026): 3.05 s of 440 Hz arrived; the level was ~17 dB under the
  take because BlackHole's own volume slider attenuates (seen before in Spectral Analyzer).
- SAVE's dialog not yet used by a hand (the writer was measured: 2 ch, 48 kHz, 24 bit, 3.00 s). The relaunch's
  "holds takes, not quit" path has not yet met a copy with takes.
- Auto gain measured on BlackHole only (31.10.2026: -21.9 → -12.0 dB in one round; v10, 1.11.2026: a -20 dBFS tone
  arriving at -38.8 dB → -12.0 dB at 251 %, the volume to its top and +8 dB boost); not yet on a voice, where the
  2 s window may need to be longer.
- v2 volume sliders not yet moved by a hand; the ADAM read back 88 % as SoundSource shows.
- Not tried: device unplugged during recording or playing, devices with more than two channels, a take of more
  than a few minutes (memory: about 23 MB a minute).


## v12 (10.11.2026): recording Suno without touching the system audio

Marko: "record suno without changing anything in my system audio in and out ... no out only in" and "fix audio output of
voice engine to adam audio out so it doesnt become a part of record".

- **Way chosen: (a) ScreenCaptureKit, per-app capture of Firefox** (`AppTap` in app/Audio.swift). Input menu entry
  "Firefox audio (app capture, no BlackHole)"; BlackHole is not needed and the Mac's default input/output are never
  read-modify-written (the app only reads defaults). The voice engine is another process, so it is never in the take.
  Output menu has "None (no output)". (b) SoundSource routing was not needed. Needs **Screen Recording** for the app
  (Marko allows it once); capture gain -3 dB (`appGain` 0.708) because the Suno masters peak at 0 dBFS.
- **Suno panel**: once a second `firefoxctl -t suno eval` reads the page's player (the longest audio element: currentTime,
  duration): ELAPSED, LEFT, SONG. **REC SONG** (AX button, so `star press "sound recorder" "REC SONG"` through the Star
  API works) records from 0, starts the page's player (clicks Playbar Play when no audio element yet), stops 0.8 s after
  the player ends, saves one whole WAV to ~/Music/Suno. No live meter is needed.
- **CLI** (headless, must be started with `open -n -a` so Screen Recording is the app's):
  `open -n -a "/Applications/Sound Recorder (Mantra).app" --stdout log --args --suno-record <outdir> earth=<song url> ...`
- **Voice and the flag (corrected 10.11.2026, Marko: "it can record audio directly from the tab inside Firefox ... You can talk")**: the app writes ~/.voice/recording.flag (its pid) only while it records a system-wide input (BlackHole, a microphone); the per-app Firefox capture never writes it, so the voice may speak during a Suno take. The voice stays pinned to the ADAM.
  MANTRA_VOICE (`pinned.py`: voiced.py MicGuard.hold, clone.py via tools/adamplay.py), `langsay` and `phonesay` stay silent while the flag's pid lives
  (a stale flag does not hold). The voice engine plays to "ADAM Audio D3V" by name (`pinned.adam_output()`, never BlackHole), whatever the system output is.
- Files: app/Suno.swift (Firefox probe, SunoWatch, SunoSession), app/Audio.swift (AppTap, RecordingFlag), App.swift (SunoPanel, --suno-record).
- Not proven yet: the first real take (waiting for the Screen Recording permission).

- **Star API functions (v12):** door on 127.0.0.1:8869 (app/Door.swift), registered in ~/.config/star-fns/sound-recorder.json, reached by
  `star fn "sound recorder" <function> '<json>'`: `record.app`, `record.suno`, `record.status`, `record.stop`, `permissions`.
  `tools/record_suno_list.py` records a list through them and checks every take (duration, peak, Whisper on the first/last 30 s).
- **Permissions (v12):** one amber button per missing permission at the top (Screen Recording, Microphone), checked at every run, opens its pane, gone when granted.
- Playback: JavaScript play() is refused by Firefox without a gesture, so `tools/suno_play.py` (installed as ~/.local/bin/suno_play) presses Play with a real BiDi pointer click. The take is trimmed at its ends to the song's length (+0.2 s).
- Immune to phones and the voice: only Firefox's own sound is captured.


## v13 (10.11.2026, task 99): Chrome, and the channel to the Chrome extension

Marko moved Suno to Chrome (Cloudflare kept stopping Firefox). The capture is the same as OBS's
(obs-studio plugins/mac-capture/mac-sck-audio-capture.m: `SCContentFilter initWithDisplay:includingApplications:`,
`capturesAudio`, `excludesCurrentProcessAudio`, 2 channels); `AppTap` already did exactly that, so Chrome needed no new
capture code: `record.app {"bundle":"com.google.Chrome"}`. **Wrong, corrected in v14:** the SCK capture of Chrome was
silent (peak -100 dBFS on a playing song).

- Input menu: "Chrome audio (app capture, no BlackHole)" (`Recorder.chromeUID`) beside Firefox.
- The door reads the body by Content-Length (long lyrics), answers OPTIONS and sends CORS headers.
- Each `record.*` starts a fresh job (no note or error left from the take before).
- `record.app` takes `trim: true`: digital silence (below -70 dBFS) cut at both ends, 50 ms kept.
- **The Chrome channel** (door functions): `chrome.send {cmd,args}` → id, `chrome.result {id}`, `chrome.state`;
  the extension calls `chrome.poll {state}` once a second and `chrome.reply {id,result}`. The extension is
  Suno Controller (Mantra), repo CHROME_SUNO_CONTROLLER; the CLI on this side is `sunoctl`.


## v14 (10.11.2026, task 99): Chrome through a CoreAudio process tap

Chrome renders every tab's sound in its AudioService helper ("Google Chrome Helper (Aperitif)", `--utility-sub-type=
audio.mojom.AudioService`, bundle com.google.Chrome.helper). ScreenCaptureKit does not list that helper as an
application and does not give its sound to Chrome, so v13's capture of Chrome was silence. v14 adds `ProcTap`
(app/ProcTap.swift): every CoreAudio process object whose bundle id starts with `com.google.Chrome` (the app and its
helpers) goes into one `CATapDescription(stereoMixdownOfProcesses:)`, private, unmuted (Chrome keeps sounding), read
through a private aggregate device on the default output's clock with an IOProc into the ring. No device is changed.
Firefox (and other single-process apps) keep ScreenCaptureKit (`AppSource` protocol, `ProcTap.wanted(bundle)`).

- Permission: **System Audio Recording** (`NSAudioCaptureUsageDescription`). The first tap shows "Would Like Access to
  Record Your System Audio"; Marko pressed Allow on 10.11.2026. While that prompt waits, `AudioDeviceCreateIOProcIDWithBlock`
  blocks on the main thread and the door stops answering (seen); the take then fails after 15 s.
- Measured 10.11.2026: 5.1 s of a playing Suno song, peak -6.3 dBFS. The whole-song proof is in CHROME_SUNO_CONTROLLER.


## v15 (10.11.2026): "App audio (<app>)"

Marko: "please, in the recorder, don't mention black hole. Just write in the inputs: "App audio" in the parentheses. Which
app is that". The Input menu: the real input devices, then **App audio (Google Chrome)** and **App audio (Firefox)**;
the BlackHole device is not offered as an input (the tests `--gain-test` still find it by name). The Suno panel's line
says "the app's own sound (App audio)". `--inputs` prints the menu's entries (checked 10.11.2026: no BlackHole).


## v16 (24.11.2026): input monitoring

Marko: "Listen to me on the input when I click on the icon of the microphone ... a new drop-down menu opens below this line with buffer size and milliseconds so I can choose how much delay I want to hear. If you can do some magic to have zero delay, let me know." Described in The window and The model above. Zero delay is not possible through the Mac: the input buffer, the output buffer, the devices' own latency and safety offsets cannot be skipped (an interface's own direct monitoring knob is the zero-latency way). Not proven by ear yet (no sound was played on his speakers while building); the first test is Marko's, with headphones. Compiled only by GitHub Actions (.github/workflows/build.yml, release vN Latest); build.sh takes SIGN and NO_INSTALL for the runner.


## v17 (24.11.2026): recording format and self-update

Marko: "add to the interface options of Sound Recorder quality, number of bits, and sample rate." Described under The window. Written without a compiler (GitHub Actions only); the first self-update will be proven when v18 follows v17. The download of app.zip does not go on the Download Monitor (a few MB, by the app itself).
