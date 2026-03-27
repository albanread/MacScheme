# Sound and Music Support Plan for MacScheme

This note reviews how audio works in FasterBASIC, what exists in the current MacScheme tree, and how to add Scheme-friendly sound and music support without forcing Scheme users into a BASIC-shaped API.

## Summary

FasterBASIC exposes three distinct audio layers:

- `SOUND` for short slot-based sound effects
- `MUSIC` for ABC-based music loading, playback, rendering, and export
- `VS` (VoiceScript) for persistent real-time synth voices

MacScheme currently exposes none of these capabilities to Scheme. The current MacScheme source tree contains graphics and sprite runtime support, but no corresponding audio runtime or Scheme bridge. However, the FasterBASIC repository already includes a usable macOS audio stack that appears portable:

- `editor/macgui/audio_runtime.zig`
- `editor/macgui/audio/fb_audio_shim.h`
- `editor/macgui/audio/fb_audio_shim.mm`
- `editor/macgui/audio/FBAudioManager.mm`
- `editor/macgui/audio/MidiEngine.mm`
- `editor/macgui/audio/CoreAudioEngine.cpp`
- `editor/macgui/audio/VoiceController.cpp`
- `editor/macgui/audio/SynthEngine.cpp`
- `editor/macgui/audio/SoundBank.cpp`
- `editor/macgui/audio/MusicBank.cpp`

That means the likely implementation path is to adapt or vendor this audio stack into MacScheme, then expose a more idiomatic Scheme API on top.

## How BASIC Audio Works

### 1. `SOUND`: slot-based sound effects

`SOUND` has a two-step workflow:

1. Create or synthesize a sound into a slot.
2. Trigger playback from that slot as often as needed.

This is a good fit for gameplay SFX because creation and playback are separated.

Capabilities visible in the current BASIC docs/runtime:

- built-in arcade-style SFX presets (`COIN`, `JUMP`, `SHOOT`, `EXPLODE`, etc.)
- custom synthesis (`TONE`, `NOTE`, `NOISE`, `FM`)
- filtered variants and baked effects (`REVERB`, `DELAY`, `DISTORT`)
- playback control (`PLAY`, `STOP`, `FREE`, `FREE ALL`, `VOLUME`)
- utility/query support in the runtime (`is_playing`, duration, existence, memory use, WAV export)

The underlying native model is not actually “slot only”; the C/Zig runtime returns raw sound IDs, and BASIC maps user-visible slots on top.

### 2. `MUSIC`: ABC notation music

`MUSIC` is the score/music layer.

Documented workflow:

1. Write ABC notation.
2. Load it into a slot or ID.
3. Play by slot/ID.

Important details from the docs:

- slot-based playback is the practical path
- compile-time ABC literals are the strongest BASIC path
- music can also be rendered offline into sound-bank data or WAV
- MIDI export exists for loaded music

The runtime surface supports:

- direct ABC playback from strings
- loading ABC strings into a bank
- loading compiled music blobs
- play/stop/pause/resume/volume
- metadata access (`title`, `composer`, `key`, `tempo`)
- offline render to sound memory or WAV
- export MIDI

### 3. `VS`: real-time synth voices

`VS` is a persistent control-rate synthesizer. BASIC code updates voice state; the audio engine renders continuously.

Capabilities visible in the docs/runtime:

- per-voice waveform, frequency, MIDI note, note name, pulse width
- ADSR, gate, volume, pan, master level
- global filter with per-voice routing
- ring modulation, sync, portamento, detune
- per-voice delay
- LFO assignment to pitch/volume/filter/pulse
- physical-model parameters and trigger
- reset, active-count, playing state
- recording control, save-to-sound, playback, WAV output

This is the most expressive layer, but also the least “Scheme-obvious” if exposed one-to-one without some shaping.

## What Exists in MacScheme Right Now

MacScheme currently has:

- a graphics runtime bridge
- sprite support layered on top of that bridge
- editor metadata copied from FasterBASIC, including `SOUND`, `MUSIC`, and `VS` keyword descriptions in `src/editor/keywords.yaml`

MacScheme currently does not appear to have:

- a vendored audio runtime under `src/vendor/macgui`
- audio C/ObjC/C++ sources included in `build.zig`
- Scheme bootstrap bindings for audio functions
- audio documentation for Scheme users

So today the audio/editor help text is ahead of the actual Scheme runtime.

## Design Goals for Scheme

The Scheme layer should preserve the useful structure of the BASIC system, but not simply mimic BASIC syntax.

Goals:

- keep quick game SFX easy
- support deterministic music workflows for game states and loops
- expose live synth control in a stateful, composable way
- avoid forcing users to manually manage low-level numeric IDs when a higher-level wrapper is clearer
- still allow raw-ID access for advanced or performance-sensitive code

## Scheme-Friendly API Shape

The Scheme API should probably have three layers mirroring the engine model:

- sound effects
- music/ABC
- live voices

### A. Sound effects API

Recommended style: return sound IDs from constructors, and provide optional helpers for user-managed slot tables.

Candidate primitives:

- `(audio-init)`
- `(audio-shutdown)`
- `(audio-stop-all)`
- `(sound-volume [level])`

- `(sound-beep frequency duration)`
- `(sound-zap frequency duration)`
- `(sound-explode size duration)`
- `(sound-coin pitch duration)`
- `(sound-jump power duration)`
- `(sound-shoot power duration)`
- `(sound-tone freq dur waveform)`
- `(sound-note midi dur waveform attack decay sustain release)`
- `(sound-noise noise-type dur)`
- `(sound-fm carrier mod-freq mod-index dur)`
- `(sound-filter-tone freq dur waveform filter-type cutoff resonance)`
- `(sound-filter-note midi dur waveform a d s r filter-type cutoff resonance)`

- `(sound-play sound-id)`
- `(sound-play sound-id volume)`
- `(sound-play sound-id volume pan)`
- `(sound-stop)`
- `(sound-stop-one sound-id)`
- `(sound-free sound-id)`
- `(sound-free-all)`
- `(sound-playing? sound-id)`
- `(sound-duration sound-id)`
- `(sound-exists? sound-id)`
- `(sound-export-wav sound-id path [volume])`

Scheme-friendly constants/helpers:

- waveform symbols: `'sine`, `'square`, `'saw`, `'triangle`, `'noise`, `'pulse`
- noise symbols: `'white`, `'pink`, `'brown`
- filter symbols: `'none`, `'lowpass`, `'highpass`, `'bandpass`
- `(midi->hz n)` and `(hz->midi hz)`

Higher-level convenience that would be very Scheme-like:

- `(define coin-sfx (sound-coin 1.1 0.10))`
- `(play-sfx coin-sfx)` as alias for `(sound-play coin-sfx)`
- `(define sfx (make-hashtable equal-hash equal?))` plus helper functions like `(sfx-put! table 'coin sound-id)` and `(sfx-play table 'coin)`

That keeps the engine ID model but makes reusable sound libraries pleasant.

### B. Music / ABC API

Recommended style: treat ABC as data, and support both immediate playback and explicit music objects/IDs.

Candidate primitives:

- `(music-play abc-string)`
- `(music-play abc-string volume)`
- `(music-load abc-string)` -> `music-id`
- `(music-load-file path)` -> `music-id`
- `(music-play-id music-id)`
- `(music-play-id music-id volume)`
- `(music-stop)`
- `(music-pause)`
- `(music-resume)`
- `(music-volume [level])`
- `(music-free music-id)`
- `(music-free-all)`
- `(music-playing?)`
- `(music-playing-id? music-id)`
- `(music-title music-id)`
- `(music-composer music-id)`
- `(music-key music-id)`
- `(music-tempo music-id)`
- `(music-render abc-string [duration sample-rate])` -> `sound-id`
- `(music-render-wav abc-string path [duration sample-rate])`
- `(music-export-midi music-id path)`

Scheme-friendly additions:

- `(abc lines ...)` macro or helper that joins lines with newlines
- `(music-load-abc lines ...)` convenience wrapper
- `(define theme (music-load (abc "X:1" "T:Theme" "K:C" "CDEF|")))`

This is likely the most natural way for Scheme code to express small game loops without string-escaping pain.

### C. Live voice / synth API

Recommended style: two layers.

1. a thin low-level bridge mirroring the runtime
2. a small higher-level API for voices as persistent instruments

Low-level candidates:

- `(vs-reset)`
- `(vs-waveform voice waveform)`
- `(vs-frequency voice hz)`
- `(vs-note voice midi-note)`
- `(vs-note-name voice name)`
- `(vs-pulse voice width)`
- `(vs-envelope voice a d s r)`
- `(vs-gate voice on?)`
- `(vs-volume voice level)`
- `(vs-pan voice position)`
- `(vs-master [level])`
- `(vs-filter-type type)`
- `(vs-filter-cutoff hz)`
- `(vs-filter-resonance q)`
- `(vs-filter-enabled on?)`
- `(vs-filter-route voice on?)`
- `(vs-ring voice source-voice)`
- `(vs-sync voice source-voice)`
- `(vs-portamento voice seconds)`
- `(vs-detune voice cents)`
- `(vs-delay-enabled voice on?)`
- `(vs-delay-time voice seconds)`
- `(vs-delay-feedback voice amount)`
- `(vs-delay-mix voice mix)`
- `(vs-lfo-waveform lfo waveform)`
- `(vs-lfo-rate lfo hz)`
- `(vs-lfo-reset lfo)`
- `(vs-lfo-pitch voice lfo depth-cents)`
- `(vs-lfo-volume voice lfo depth)`
- `(vs-lfo-filter voice lfo depth-hz)`
- `(vs-lfo-pulse voice lfo depth)`
- `(vs-physical-model voice model)`
- `(vs-physical-damping voice value)`
- `(vs-physical-brightness voice value)`
- `(vs-physical-excitation voice value)`
- `(vs-physical-resonance voice value)`
- `(vs-physical-tension voice value)`
- `(vs-physical-pressure voice value)`
- `(vs-physical-trigger voice)`
- `(vs-active-count)`
- `(vs-playing?)`
- `(vs-record-start)`
- `(vs-record-tempo bpm)`
- `(vs-record-wait beats)`
- `(vs-record-save [volume])` -> `sound-id`
- `(vs-record-play [volume])`
- `(vs-record-wav path)`

Higher-level helpers worth adding:

- `(with-voice voice body ...)`
- `(voice-note-on voice midi)` and `(voice-note-off voice)`
- `(voice-patch! voice '((waveform . saw) (attack . 0.01) (decay . 0.08) (sustain . 0.6) (release . 0.15)))`
- `(play-note voice midi dur)` helper that gates on, waits externally or schedules release later

If we later want a more Lispy layer, we could define patches as alists/records and apply them with one call, but the first version should stay close to the runtime.

## Proposed Implementation Strategy

### Phase 1: Port the native audio stack into MacScheme

Bring the FasterBASIC audio runtime into MacScheme with minimal semantic changes:

- vendor/copy the macOS audio sources into MacScheme
- update `MacScheme/build.zig` to compile them
- link required frameworks (`AVFoundation`, `AudioToolbox`, `CoreAudio`, likely `CoreMIDI`, possibly `AudioUnit`/`Accelerate` depending on source usage)
- expose a MacScheme-local Zig bridge similar to `macscheme_graphics_runtime.zig`

This phase should not yet design a fancy Scheme API; it should focus on getting a working native backend.

### Phase 2: Expose thin Scheme bindings

Add `foreign-procedure` declarations and direct wrappers in `app_delegate.m`.

This would mirror what was done for graphics and sprites:

- low-level C/Zig bridge functions exported from Zig
- Scheme wrappers with symbol/boolean conversions
- careful argument validation where it materially improves usability

At the end of this phase, Scheme should already be able to:

- create and play SFX
- load/play/stop music
- control VS voices directly

### Phase 3: Add Scheme-friendly convenience helpers

Layer ergonomic helpers on top of the thin bridge:

- symbolic waveform/filter/model names
- ABC helpers for multiline strings
- simple sound-library helpers
- voice patch helpers
- optional `define-sfx` or `make-sfx-bank` helpers if they feel worthwhile in actual examples

This is where the API becomes pleasant rather than merely complete.

### Phase 4: Document and example-drive the surface

Add a new audio section to the Scheme docs, with examples focused on:

- UI/game SFX
- title/theme music via ABC
- live synth alerts/drones
- rendering generated music or VS output into reusable sound effects

## Proposed File-Level Work

Likely MacScheme changes:

- add a new vendored audio subtree under `MacScheme/src/vendor/macgui/audio/`
- add a new Zig bridge file, likely `MacScheme/src/macscheme_audio_runtime.zig`
- update `MacScheme/build.zig`
- extend `MacScheme/src/app_delegate.m` bootstrap bindings
- add docs, likely a new audio section or standalone note in the MacScheme docs

## API Naming Notes

To stay consistent with existing graphics naming, there are two reasonable choices:

1. use short names like `sound-play`, `music-load`, `vs-note`
2. prefix everything with `audio-` or `gfx-`-style names like `audio-sound-play`

Recommendation:

- use `sound-*`, `music-*`, and `vs-*`

Reasoning:

- these are short and readable
- they match the conceptual subsystems already present in BASIC docs
- they avoid awkwardly deep prefixes

## Open Questions

Before implementation, a few details should be checked in the ported runtime:

- whether the FasterBASIC audio sources depend on editor-specific infrastructure outside the audio subtree
- whether any source files assume BASIC runtime slot management that MacScheme must replace
- whether the music compiled-blob path is worth exposing in Scheme immediately, or only later
- whether any thread-affinity guarantees differ when called from embedded Chez Scheme rather than the BASIC JIT worker
- whether any editor-specific stub files currently linked into MacScheme would conflict with real audio symbols

## Recommended First Deliverable

The first practical milestone for MacScheme should be:

- `sound-*` support for procedural SFX
- `music-load` / `music-play-id` / `music-stop` for ABC playback
- a minimal `vs-*` core: waveform, note/frequency, envelope, gate, volume, reset

That would already unlock a lot of useful Scheme programs while keeping the initial port manageable.