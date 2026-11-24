# LESSONS: Sound Recorder (Mantra)

Appended, never rewritten. Newest last.

## 31.10.2026, v1

- **IOProcs, not AVAudioEngine.** Inherited from SPECTRAL_ANALYZER (Live.swift): an AVAudioEngine switched to a chosen
  device delivered frames that were all 0.0; an IOProc on the device is the device itself calling.
- **The take in memory, not a file.** "When I close the app, delete the audio": a file would need deleting on quit
  and would survive a crash; memory needs nothing. Rejected: a WAV in ~/Library/Caches deleted on quit and on launch.
- **Never change the output's rate.** The player resamples (linear) instead; Spectral Analyzer set the output's rate,
  which also changes it for every other app on the ADAM.
- **Tests never save the device choice.** The first `--play-test BlackHole` saved BlackHole as the output, so the
  next window opened on BlackHole; `chooseOutput` now saves only in the live app.
- **No microphone request at launch.** The input starts only when the microphone is already allowed; the question
  is asked from PERMISSIONS or the record key, so a test launch never puts a dialog on his screen.
- **Min height 500.** At 480 the footer (v1 / QUIT) fell under the window edge in the off-screen picture.
- **SoundSource's look vs CAMERA.** Marko asked for SoundSource's look, so panels and boxes stay; from CAMERA come
  the colour roles, the record circle, ON/OFF, QUIT and PERMISSIONS.

## 31.10.2026, v2

- **The device's own volume, not a gain in the app.** SoundSource's sliders move the device, so the volume keys and
  his other apps agree with this one. Measured: the ADAM D3V has no main element, only channels 1 and 2; External
  Microphone, BlackHole and MacBook Pro Microphone have element 0. A device with none falls back to the app's gain.
- **The audio threads read plain Bools and Floats**, never the VolumeWatch objects that the main thread replaces.
- **ON TOP** on the first row, a CAMERA toggle word (green on, grey off), `NSWindow.level = .floating`.

## 31.10.2026, v3

- **The CQ's icons are CQ MixPad's own.** Found in the app's binary (CQ MixPad 1.2.2, uncompressed SVGs "KAuto Gain
  Steps"): a knob arc open at the bottom with ✓ green, ? orange, ! orange on a dark disc, an orange gear with a turning
  arrow. Redrawn in SwiftUI, nothing copied.
- **Auto gain in dB when the device knows its range.** One dB step lands where it should (measured on BlackHole:
  -21.9 → -12.0 in one round); a scalar step is only proportional, so it may take more rounds. Rejected: a gain stage
  in the app above 100 %, which would clip at the input before any gain could help.
- **Takes as a list, the waveform as the play key** (Marko). A Take is a class so its playhead can move without
  copying the frames; the tick publishes the meters 30 times a second, which redraws the rows anyway.
- **⌘ read from NSEvent.modifierFlags** at the click's end: SwiftUI's gestures have no modifier on macOS 14.
- **Min width 600**: at 580 the device menu cut "MacBook Pro Microphone".

## 31.10.2026, v4

- **A tap gesture is invisible to Accessibility.** The words (QUIT, OFF, TOP…) were Text with onTapGesture: no AX
  button, nothing to press. `axButton` gives each a label, an identifier and a default action.
- **An app that quits inside an AX action never answers the press.** The first relaunch pressed QUIT, the app quit,
  AXPress came back as an error and the script reported "no QUIT". Now QUIT terminates on the next turn of the main
  loop, and relaunch.swift judges by the app being gone, not by the press's answer.
- **The menu's Quit is the fallback**, for a copy without the button (v3 and older) or with no window open.

## 31.10.2026, v5

- **SAVE sits over the waveform** as an overlay after the waveform's gesture, so its click is its own and never plays
  the take. The words have a dark band behind them (CAMERA v88: words over a picture need a band).
- **A build must not throw takes away.** They exist only in memory, so relaunch.swift counts the `take<N>`
  identifiers and leaves a copy with takes running. This is why every control has a fixed identifier.

## 31.10.2026, v6

- **macOS hides overlay scroll bars** until a trackpad scrolls, so "there is more below" was invisible. The window's
  NSScrollView is set to the legacy style with autohide: drawn whenever the page is taller than the window, gone
  otherwise. The page measures its own height (a PreferenceKey) and gives the bar its 15 pt, so no SAVE or meter goes
  under it. `--shot` prints the scroll view's state, because an off-screen picture barely shows the bar.

## 31.10.2026, v7

- **OFF and QUIT did the same thing here**, and Marko chose OFF: QUIT is gone from this app and from the manifest's
  rule for new apps (swift-apps.md, "No QUIT"). The relaunch presses `off`, then `quit` for older copies, then the menu.

## 31.10.2026, v8

- **A warning outlives its reason.** "in memory only · gone when the app quits" was needed while nothing could be kept; with
  SAVE on every take it was only text in the way (Marko). The rule itself stays in TAKEOVER.

## 1.11.2026, v10 and v11

- **Percent is not a unit for gain.** v10 showed the auto gain's boost as 251 %; Marko: a percentage is a "material" unit,
  the peak goes to -12 dB, so the gain is read in dB. Every level, readout and message is in dB now.
- **The slider is the indicator.** A slider that is linear in volume hides where the gain really is; v11 makes the slider
  a dB scale (-60 … 0 mark … +32 dB) computed from the gain itself, so the auto gain moving the level moves the knob.
  Measured round trip: positions 0.2/0.5/0.652/0.8/1.0 ↔ -41.6/-14.0/0.0/+13.6/+32.0 dB.
- **The ceiling is his to set.** v10 capped the boost at +20 dB on my own guess; he set it at +32 dB above 0 dB, reachable
  by hand as well as by the auto gain. Ask or take the gear's number (the CQ), don't invent a limit.
- **BlackHole's input volume at 71 % costs ~19 dB**, and the auto gain listens only above -45 dB: a -40 or -30 dBFS test
  tone never woke it. -25 dBFS (arriving -43.8 dB) is the quietest test that still needs the boost (+13 dB).
- **My slip:** a Python slice ending at the first "    }\n" matched inside a deeper "        }\n" and left a stray brace;
  cut by a marker line, not by an indentation fragment.


## 10.11.2026 (v13, task 99)

- OBS's per-app audio on macOS is ScreenCaptureKit with a display filter that includes one application. Our AppTap was
  already that, so "do it like OBS" meant pointing it at Chrome, not new code. Read the reference before rewriting.
- The capture is the whole of Chrome: any other Chrome tab that sounds gets into the take. The extension mutes other
  audible tabs during a take and gives them back after.
- A job dictionary that is only ever added to keeps old errors: the probe on 10.11.2026 said "done" and "no take" at
  once. Start every job empty.
- A relaunch was held back by 3 takes that were all already on disk (door jobs write their WAV): checked the files
  before using `relaunch.swift --force`.

## 10.11.2026 (v14)

- "Do it like OBS" was not enough for Chrome: ScreenCaptureKit's per-app filter misses Chrome's AudioService helper,
  the probe was silent although the song played. Measure the peak of a real take before calling a source done
  (a 3 s probe of nothing proves only that the stream starts).
- CoreAudio process taps (macOS 14.2+) take a list of processes, so an app whose sound comes from helpers is tapped by
  bundle prefix. The consent prompt blocks inside AudioDeviceCreateIOProcIDWithBlock until answered.


## 24.11.2026 (v16, input monitoring)

- Monitoring cannot be zero delay on the Mac: the round trip is input latency + safety offset + input buffer + the ring + output buffer + output latency. The ring must hold one input chunk plus one output buffer or the two devices' unaligned callbacks underrun; so a chosen buffer of B frames costs about 4 B plus the devices' own latency, and the window's estimate line says it.
- One output IOProc serves the take and the monitor; stop it before freeing the take's memory (AudioDeviceStop waits for the running callback), then make it again for monitoring.
- A lock-free ring in Swift without the Atomics package: aligned 64-bit counter plus OSMemoryBarrier() between the data and the counter.


## 24.11.2026 (v17)

- Changing a device's nominal rate is asynchronous: set it, then poll the read-back (up to 0.5 s) before opening the IOProc; the take's rate is the rate read back, never the one asked for.
- A self-updater must never quit an app that holds unsaved memory: install at once only with no takes, otherwise at the quit.

## 24.11.2026, v18

- **A permission prompt per version = an ad hoc signature.** CI signs `-` (cdhash requirement); a release zip unpacked by hand stays ad hoc. Only the updater's `codesign -s "Mantra Apps"` (identifier + certificate leaf) is stable. Never unpack a release into /Applications without re-signing.
- **Mono is made at drain time**, not at save: the stored take is the mixdown on both sides, so waveform, playback and the WAV agree.
- **Screen Recording may need a relaunch** even after it is granted; the app tries to reopen the source, then relaunches itself when no takes would be lost.
- **`open` is a Swift keyword-ish word**: the panel's state is `isOpen`.

## The app list follows what is running (24.11.2026, v19)

Chrome stayed in the list after closing because v18 added it (and Firefox) as permanent entries and only appended running apps. The list is now rebuilt from live state each time (running apps that own a window), the approach of OBS Studio's mac-capture (apps from the system's shareable content, with windows), written independently (OBS is GPLv2; no code copied).
