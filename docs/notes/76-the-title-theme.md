## 76. The title theme (2026-10-17)

The user's "game title screen - Main.wav" (Shared drive, Audio/; "it loops
perfectly") is the title screen's music -- the game's first audio.

- `audio/music/title_theme.wav` (48 kHz stereo 16-bit, 212.73 s, 41 MB): kept a
  WAV, not converted, so the loop is sample-exact (an encoder's padding can put
  a gap at an Ogg's loop). Import: `edit/loop_mode=2` (forward), `loop_begin=0`,
  `loop_end=10210909` -- every sample (the importer's -1 put the end one sample
  short), `edit/trim=false`, `compress/mode=2` (QOA, decoded sample-exact).
- `title_screen.gd` `_start_music`: an AudioStreamPlayer ("Music", Master bus)
  fading in from -60 to MUSIC_DB -4 dB over MUSIC_FADE_IN 1.5 s; `_descend`
  fades it out with the fade to black (LOADING_HOLD + LOADING_FADE). Not
  started for `--sandbox` / `--bench` / `--skip-title` (they leave first). No
  volume setting or music bus exists yet.
- Measured (throwaway harness): playing, -4.0 dB after the fade-in; seeked to
  212.4 s it wrapped 212.723 -> 0.006 s and kept playing.
