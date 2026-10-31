# LESSONS: Mantra Sound Recorder

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
