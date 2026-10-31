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
