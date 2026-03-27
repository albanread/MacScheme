# MacScheme Audio

MacScheme now exposes two audio layers to Scheme:

- `sound-*` for generated sound effects
- `music-*` for ABC-based music playback and rendering

This first pass does **not** expose the live synth `VS` layer yet.

## Example Files

Try these small Scheme examples:

- [examples/sound_demo.ss](examples/sound_demo.ss)
- [examples/music_demo.ss](examples/music_demo.ss)
- [examples/music_render_demo.ss](examples/music_render_demo.ss)

From the MacScheme project directory, load one with:

```scheme
(load "examples/sound_demo.ss")
```

## Quick Start

Initialize audio explicitly if you want deterministic startup:

```scheme
(audio-init)
```

You can also rely on lazy initialization when the first sound or music call runs.

Stop everything:

```scheme
(audio-stop-all)
```

Check initialization state:

```scheme
(audio-initialized?)
```

## Sound Effects

### Play a built-in effect

```scheme
(define coin (sound-coin 1.1 0.10))
(sound-play coin)
```

### Control playback

```scheme
(sound-play coin 0.8)
(sound-play coin 0.8 -0.4)
(sound-stop)
(sound-stop-one coin)
(sound-free coin)
```

### Other built-in generators

- `sound-beep`
- `sound-zap`
- `sound-explode`
- `sound-big-explosion`
- `sound-small-explosion`
- `sound-distant-explosion`
- `sound-metal-explosion`
- `sound-bang`
- `sound-coin`
- `sound-jump`
- `sound-powerup`
- `sound-hurt`
- `sound-shoot`
- `sound-click`
- `sound-blip`
- `sound-pickup`
- `sound-sweep-up`
- `sound-sweep-down`
- `sound-random-beep`

### Custom synthesis

```scheme
(define tone (sound-tone 440 0.25 'square))
(sound-play tone)

(define note (sound-note 64 0.4 'saw 0.01 0.08 0.5 0.12))
(sound-play note 0.7)

(define filtered
  (sound-filter-tone 220 0.5 'saw 'lowpass 1200 0.8))
(sound-play filtered)
```

Waveform symbols:

- `'sine`
- `'square`
- `'saw`
- `'triangle`
- `'noise`
- `'pulse`

Noise symbols:

- `'white`
- `'pink`
- `'brown`

Filter symbols:

- `'none`
- `'lowpass`
- `'highpass`
- `'bandpass`

### Sound utilities

```scheme
(sound-volume 0.8)
(sound-volume)
(sound-playing? tone)
(sound-duration tone)
(sound-exists? tone)
(sound-count)
(sound-memory-usage)
(sound-export-wav tone "tone.wav")

(midi->hz 69)
(hz->midi 440)
```

## Music (ABC)

### Build ABC with helper lines

```scheme
(define theme
  (abc
    "X:1"
    "T:Theme"
    "M:4/4"
    "L:1/8"
    "Q:1/4=144"
    "K:C"
    "C2 E2 G2 c2 | b2 a2 g2 e2 |"))
```

### Play inline

```scheme
(music-play theme)
(music-play theme 0.7)
```

### Load and replay by id

```scheme
(define theme-id (music-load theme))
(music-play-id theme-id)
(music-play theme-id 0.8)
```

### Playback control

```scheme
(music-stop)
(music-pause)
(music-resume)
(music-volume 0.75)
(music-volume)
(music-playing?)
(music-playing? theme-id)
```

### Render and export

Render ABC into a reusable sound effect:

```scheme
(define sting (music-render theme))
(sound-play sting)
```

Render with explicit duration and sample rate:

```scheme
(music-render theme 2.0 44100)
```

Export:

```scheme
(music-render-wav theme "theme.wav")
(music-render-wav theme "theme.wav" 4.0 44100)
(music-export-midi theme-id "theme.mid")
```

### Music queries

```scheme
(music-exists? theme-id)
(music-count)
(music-memory-usage)
(music-state)
(music-tempo theme-id)
(music-free theme-id)
(music-free-all)
```

## Notes

- `music-load` is the recommended repeat-play workflow.
- `music-play` and `music-play-id` now compile ABC text at runtime into MacScheme's internal playback format, so Scheme-side music does not depend on static compiler-owned blobs.
- `music-render` is useful when you want ABC-authored material to become a normal `sound-*` asset.
- The current Scheme surface intentionally stops before the live voice synth layer; that can be added later without changing the `sound-*` and `music-*` APIs.
