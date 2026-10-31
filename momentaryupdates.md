# Mantra Sound Recorder: requests, word for word

## 31.10.2026, v1

> Please build in Swift Sound Recorder, call it Mantra Sound Recorder. For now it is just a simple application which records audio, plays audio and then when I close the app deletes the audio. So it has record button, play button and show audio as a waveform while it's playing. When I close it delete is audio. And it has input output, drop down menus. Sound source which is now open on the screen should be user interface for audio input and audio output and audio input and audio output VOOMeters. And overall look. Okay.

| # | Item | Status |
|---|---|---|
| 1 | Swift app "Mantra Sound Recorder (Mantra)", signed Mantra Apps, in /Applications | done in v1, waiting for Marko's test |
| 2 | Record button, play button | done in v1, waiting for Marko's test |
| 3 | Waveform shown while playing | done in v1, waiting for Marko's test |
| 4 | Audio deleted when the app closes | done in v1, waiting for Marko's test |
| 5 | Input and output drop-down menus | done in v1, waiting for Marko's test |
| 6 | Input and output VU meters | done in v1, waiting for Marko's test |
| 7 | The look of SoundSource (as open on screen 31.10.2026) | done in v1, waiting for Marko's test |

## 31.10.2026, v2

> I clicked permissions, now it's recording. The permissions become invisible once permissions are set. This is for every of my app. Permission is only visible on a screen when permissions are not set, so user can click on it. In this application I am missing the controlling input and output volume. And that's all. Please build it.

| # | Item | Status |
|---|---|---|
| 1 | PERMISSIONS visible only while a permission is missing, in every app (already the rule: MANTRA_MANIFEST swift-apps.md; v1 does it) | done: v1 and v2 already hide it once allowed (seen in his window, 31.10.2026); the rule is MANTRA_MANIFEST swift-apps.md |
| 2 | Input volume and output volume controls | done in v2 |

> Also add a toggle button always on top in the main user interface.

| # | Item | Status |
|---|---|---|
| 3 | Always-on-top toggle in the main window | done in v2 |

## 31.10.2026, v3

> Please add auto gain option the same as in my CQ mixer series. The same icon I am going to press and when it detects the right level it's going to adjust the gain automatically and then quits.

| # | Item | Status |
|---|---|---|
| 1 | AUTO GAIN on the input, CQ's Gain Assistant icons (knob arc: gear working, ? waiting, ! failed, ✓ done, from CQ MixPad 1.2.2's own "KAuto Gain Steps" graphics), sets the level and stops by itself | done in v3; measured on a tone in BlackHole: -21.9 → -12.0 dB in one step, ✓, off |

> So idea with this app will be that in this session every time I record the new waveform is opening up with the only play button of course and the next one is for new recording automatically opening. so I can easily compare recordings and play button is actually pressing on the waveform itself. So in that sense we can save on user interface. Put only waveform, I can click on to play and pause. And if I want to jump on different parts of the waveform, I press command and then I click on that part.

| # | Item | Status |
|---|---|---|
| 2 | Every recording is its own waveform in a list; a new empty one opens for the next recording | done in v3 |
| 3 | No play button: a click on a waveform plays / pauses it | done in v3 |
| 4 | ⌘-click on a waveform jumps there | done in v3 |

> Please shorten this on top text. Just put top.

| # | Item | Status |
|---|---|---|
| 5 | "ON TOP" becomes "TOP" | done in v3 |

## 31.10.2026, v4

> Please when you make new version close this one which is running and run the new one.Why can't you quit? Make this application accessibility compatible and close it through accessibility please.

| # | Item | Status |
|---|---|---|
| 1 | Every control an Accessibility button (QUIT, OFF, TOP, ✕, PERMISSIONS, record, auto gain, each take, sliders) | done in v4 |
| 2 | build.sh quits the running copy through Accessibility (QUIT, or the menu's Quit) and opens the new one | done in v4: measured, v2 quit by its menu, v4 by its QUIT button, the new one opened |

## 31.10.2026, v5

> Now you can add the save button in upper right corner of each waveform.

| # | Item | Status |
|---|---|---|
| 1 | SAVE in the upper right corner of each take's waveform | in progress |
