# TAKEOVER: Mantra Sound Recorder (Mantra)

**Version 6** (31.10.2026) · repo markoboskoauroville/MANTRA_SOUND_RECORDER (private) ·
`/Applications/Mantra Sound Recorder (Mantra).app`, bundle id `community.auroville.mantrasoundrecorder`.
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
- **Takes**: every recording of the session is its own waveform, numbered, oldest on top, with `position / length`.
  **A click on a waveform plays / pauses it** (there is no play key); **⌘-click jumps there and plays**. **SAVE** in each waveform's upper right corner opens a save dialog (the last
  folder, at first ~/Music; name "Take N - d.M.yyyy HH.mm.wav") and writes WAV, stereo, 24 bit, at the take's rate;
  it then reads SAVED in green (hover: the path). One take plays
  at a time; each keeps its playhead. Below them the next take's empty row (red and growing while recording), then
  the record circle and "take N". Space plays / pauses the last played (or the newest).
- **Scroll bar**: the page scrolls; while it is taller than the window a real (legacy, always drawn) scroll bar shows
  at the right and the page narrows by its width, so nothing goes under it (`Scroller`, `ContentHeight`).
- **Footer**: `v1` (dim, opens the latest release), QUIT (red; quits).
- **Accessibility**: every word or shape that acts is an Accessibility button with a label and an identifier
  (`quit`, `off`, `top`, `close`, `permissions`, `record`, `autogain`, `take<N>`, `version`); the sliders are adjustable
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
- **Volume**: `VolumeWatch` moves the device's own volume (kAudioDevicePropertyVolumeScalar, element 0, or each
  channel element as on the ADAM: 1 and 2) and listens to it, so the volume keys and System Settings move the slider.
  A device without a settable volume gets the app's own gain (`inSoft` / `outSoft`, UserDefaults `inGain` / `outGain`),
  applied in the IOProcs.
- **Deleting**: the take is never written to disk. QUIT, OFF and ⌘Q call `forget()` (devices released, arrays
  emptied); a crash leaves nothing either. Closing the window keeps the app ON and the take with it (swift-apps.md).

## The files

| File | What |
|---|---|
| `app/App.swift` | the window (SwiftUI), the colours (`Ink`), keys, `--shot` and `--play-test` |
| `app/Audio.swift` | devices, the ring, meters, recording, playing, permissions |
| `icon/make_icon.swift` | the icon, drawn with the version under it |
| `build.sh` | swiftc, Info.plist, icon, signed "Mantra Apps", copied to /Applications, then the running copy quit and the new one opened |
| `tools/relaunch.swift` | presses the running copy's QUIT through Accessibility (or its menu's Quit), waits for it to go, opens the new one; never kills |

## Building and testing

```sh
./build.sh
```

Every build quits the running copy through Accessibility and opens the new one (Marko, 31.10.2026), unless that
copy holds takes: then it is left running and says so (exit 3). `./build.sh --no-run` only builds.

```sh
"build/Mantra Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --shot docs/window.png 720 520
```

```sh
"build/Mantra Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --play-test BlackHole
```

```sh
"build/Mantra Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --gain-test BlackHole
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
- Auto gain measured on BlackHole only (31.10.2026: -21.9 → -12.0 dB in one round); not yet on a voice, where the
  2 s window may need to be longer.
- v2 volume sliders not yet moved by a hand; the ADAM read back 88 % as SoundSource shows.
- Not tried: device unplugged during recording or playing, devices with more than two channels, a take of more
  than a few minutes (memory: about 23 MB a minute).
