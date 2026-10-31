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
