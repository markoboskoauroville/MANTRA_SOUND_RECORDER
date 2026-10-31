# TAKEOVER: Mantra Sound Recorder (Mantra)

**Version 2** (31.10.2026) · repo markoboskoauroville/MANTRA_SOUND_RECORDER (private) ·
`/Applications/Mantra Sound Recorder (Mantra).app`, bundle id `community.auroville.mantrasoundrecorder`.
The reasons behind the choices are in [LESSONS.md](LESSONS.md).

## What it is

Marko's simple recorder: record, play, see the waveform; nothing kept after the app quits. Its look is SoundSource's
(Rogue Amoeba), as it was open on his screen on 31.10.2026: a dark ground, rounded panels, an Output row and a green
Input row, each with its meter and device menu.

## The window, top to bottom

- **First row** (in the hidden title bar, beside the traffic lights): ON (green) / OFF (grey; quits), the name
  centred, ON TOP (green: the window floats above every other window; kept in UserDefaults `onTop`), PERMISSIONS (amber, only while the microphone is not allowed; a click asks once, then opens the
  Microphone page of System Settings), ✕ (closes the window, the app stays on).
- **Devices**: Output and Input rows: icon, name, a volume slider (SoundSource's: green track, white knob) with its % over a stereo meter (L over R, -60…0 dBFS, green to -12, amber to -3,
  red above, white tick = peak held 1.5 s, the bar falls 24 dB/s), the held peak in dB, the device menu. The input
  menu is locked while recording. Choices are kept in UserDefaults by device UID; a vanished device falls back to
  the Mac's default. An amber line under the rows shows a device error.
- **Recorder**: the waveform (green played, grey to come, white playhead; red and growing while recording; a click or
  drag moves the playhead), the record circle (ring round a red dot; recording: filled red with MM:SS), the play key
  (▶ / ■), the time `position / length`, "in memory only · gone when the app quits".
- **Footer**: `v1` (dim, opens the latest release), QUIT (red; quits).
- Keys: **R** record / stop, **Space** play / stop.

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
| `build.sh` | swiftc, Info.plist, icon, signed "Mantra Apps", copied to /Applications |

## Building and testing

```sh
./build.sh
```

```sh
"build/Mantra Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --shot docs/window.png 720 520
```

```sh
"build/Mantra Sound Recorder (Mantra).app/Contents/MacOS/MantraSoundRecorder" --play-test BlackHole
```

`--shot` draws the window off screen with a test take; `--play-test <name>` plays a 3 s 440 Hz test take to the output
whose name contains the word and never changes the saved choice. Test audio goes to BlackHole, never the ADAM.

## What has never been proven

- **No real recording yet**: the app has no Microphone permission until Marko grants it; the input IOProc, the
  ring drain and the live red waveform have not run with a real signal.
- Playback into BlackHole 2ch was measured (31.10.2026): 3.05 s of 440 Hz arrived; the level was ~17 dB under the
  take because BlackHole's own volume slider attenuates (seen before in Spectral Analyzer).
- v2 volume sliders not yet moved by a hand; the ADAM read back 88 % as SoundSource shows.
- Not tried: device unplugged during recording or playing, devices with more than two channels, a take of more
  than a few minutes (memory: about 23 MB a minute).
