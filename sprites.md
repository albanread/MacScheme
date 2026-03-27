# Sprite Review and Scheme Support Plan

This note reviews:

- how the current GPU sprite system works in MacScheme
- how sprites are used from BASIC today
- how sprites should best be exposed to Scheme

## Summary

The important result is:

- the native runtime already has a fairly complete sprite system
- BASIC already has a rich command surface for it
- Scheme currently exposes none of that sprite functionality
- the best Scheme support is **two-layered**:
  - a low-level runtime-mirroring API
  - a small set of higher-level, idiomatic Scheme helpers

That gives Scheme users full power without forcing them to think in BASIC command syntax.

## 1. How sprites work internally

The current sprite system is implemented in the Mac GUI runtime and is GPU-driven.

Key implementation files:

- [MacScheme/src/vendor/macgui/sprite.zig](MacScheme/src/vendor/macgui/sprite.zig)
- [MacScheme/src/vendor/macgui/ed_graphics.zig](MacScheme/src/vendor/macgui/ed_graphics.zig)
- [MacScheme/src/vendor/macgui/graphics_runtime.zig](MacScheme/src/vendor/macgui/graphics_runtime.zig)
- [MacScheme/src/vendor/macgui/embedded_graphics_metal_source.h](MacScheme/src/vendor/macgui/embedded_graphics_metal_source.h)

### Internal model

There are two separate concepts:

- **sprite definitions**
  - pixel data
  - palette
  - frame layout
  - atlas allocation
- **sprite instances**
  - position
  - rotation
  - scale
  - anchor
  - visibility
  - blend mode
  - animation state
  - effect state
  - collision group

This is a strong model and should be preserved in Scheme.

### Definition lifecycle

A sprite definition can be created in several ways:

- load a `.sprtz` file via `gfx_sprite_load`
- allocate an empty definition via `gfx_sprite_def`
- draw pixels into it with `gfx_sprite_data`
- or redirect normal drawing commands into it with `gfx_sprite_begin` / `gfx_sprite_end`

That last mode is especially important:

- the runtime can temporarily redirect normal graphics drawing into a sprite staging buffer
- then `SPRITE END` automatically commits the staged pixels into the GPU atlas

This means sprites are not only image assets; they can also be generated procedurally with the same primitive drawing system used for the screen.

### Instance lifecycle

An instance is placed separately from the definition:

- `gfx_sprite(inst, def, x, y)` creates or reassigns an instance
- the instance starts inactive visually until `gfx_sprite_show(inst)`
- state can then be modified independently:
  - position / move
  - rotation
  - scale
  - anchor
  - alpha
  - frame
  - animation speed
  - priority
  - additive blending
  - effects
  - collision group

### Rendering model

The sprite renderer is GPU compositing after palette lookup.

Notable properties:

- sprite instances are sorted by priority before GPU sync
- visibility is explicit
- per-instance alpha exists
- additive blending exists
- effects include:
  - glow
  - outline
  - shadow
  - tint
  - flash
  - dissolve support exists in the enum even if not all helper shorthands expose it yet
- collision is bounding-box based, not per-pixel

### Data constraints

From the runtime:

- up to 1024 definitions
- up to 512 instances
- max sprite size 256×256
- 16 palette entries per sprite
- atlas size 2048×2048

That means Scheme support should treat sprite IDs and instance IDs as explicit handles, not allocate arbitrary unbounded objects without care.

## 2. How BASIC uses sprites

The clearest BASIC-facing documentation is in:

- [FasterBASIC-public/editor/src/keywords.yaml](FasterBASIC-public/editor/src/keywords.yaml)
- [FasterBASIC-public/resources/articles/sprite_commands.md](FasterBASIC-public/resources/articles/sprite_commands.md)

## BASIC command style

BASIC uses a broad command family built around `SPRITE` plus related query functions.

### Definition commands

- `SPRITE DEF id, w, h`
- `SPRITE DATA id, x, y, colour_index`
- `SPRITE COMMIT id`
- `SPRITE PALETTE id, idx, r, g, b`
- `SPRITE STD PAL id, palette_id`
- `SPRITE FRAMES id, fw, fh, count`
- `SPRITE LOAD id, "file.sprtz"`
- `SPRITE BEGIN id`
- `SPRITE END`
- `SPRITE ROW row, ...`

### Instance commands

- `SPRITE inst, def, x, y`
- `SPRITE SHOW inst`
- `SPRITE HIDE inst`
- `SPRITE REMOVE inst`
- `SPRITE REMOVE ALL`
- `SPRITE POS inst, x, y`
- `SPRITE MOVE inst, dx, dy`
- `SPRITE ROT inst, angle_degrees`
- `SPRITE SCALE inst, sx, sy`
- `SPRITE ANCHOR inst, ax, ay`
- `SPRITE FLIP inst, h, v`
- `SPRITE ALPHA inst, a`
- `SPRITE PRIORITY inst, pri`
- `SPRITE BLEND inst, mode`
- `SPRITE FRAME inst, n`
- `SPRITE ANIMATE inst, speed`

### Effects and palette override

- `SPRITE GLOW inst, radius, r, g, b`
- `SPRITE OUTLINE inst, thickness, r, g, b`
- `SPRITE SHADOW inst, ox, oy, a, r, g, b`
- `SPRITE TINT inst, factor, r, g, b`
- `SPRITE FLASH inst, speed, r, g, b`
- `SPRITE FX inst, effect_type`
- `SPRITE PAL OVERRIDE inst, def_id`
- `SPRITE PAL RESET inst`

### Collision and queries

- `SPRITE COLLIDE inst, group`
- `SPRITE SYNC`
- `SPRITEX(inst)`
- `SPRITEY(inst)`
- `SPRITEGETROT(inst)`
- `SPRITEVISIBLE(inst)`
- `SPRITEGETFRAME(inst)`
- `SPRITEHIT(a, b)`
- `SPRITECOUNT()`
- `SPRITEOVERLAP(groupA, groupB)`

## BASIC workflow shape

BASIC’s design is imperative and command-oriented.

A typical flow is:

1. define or load a sprite
2. optionally set palette / frames
3. place an instance
4. show it
5. mutate instance state over time
6. query collisions or positions as needed

That is a very good match for the runtime internals.

## 3. What Scheme currently has

Scheme currently documents and exposes framebuffer drawing, palette, text, blitting, and palette effects in:

- [MacScheme/graphics.md](MacScheme/graphics.md)
- [MacScheme/src/app_delegate.m](MacScheme/src/app_delegate.m)
- [MacScheme/src/macscheme_graphics_runtime.zig](MacScheme/src/macscheme_graphics_runtime.zig)

But it does **not** currently expose sprite functions.

That is the core gap.

More specifically:

- low-level runtime exports for sprites exist in [MacScheme/src/vendor/macgui/graphics_runtime.zig](MacScheme/src/vendor/macgui/graphics_runtime.zig)
- the current Scheme bootstrap in [MacScheme/src/app_delegate.m](MacScheme/src/app_delegate.m) registers many `macscheme_gfx_*` functions
- sprite exports are not part of that bootstrap yet
- [MacScheme/src/macscheme_graphics_runtime.zig](MacScheme/src/macscheme_graphics_runtime.zig) currently wraps drawing/palette/text APIs, but not the sprite API

So the missing work is not the sprite engine itself; it is the Scheme bridge and API design.

## 4. Best way to support sprites in Scheme

The best support is not to invent a completely different model.

Instead:

### Recommendation

Expose sprites in two layers.

#### Layer 1: low-level direct bindings

Provide a near-1:1 Scheme API matching the native runtime.

This is useful because:

- it maps directly to the existing engine
- it makes docs easy to write
- it allows advanced users to access everything
- it mirrors the BASIC surface where that is already proven

#### Layer 2: idiomatic Scheme helpers

Add a smaller set of friendlier wrappers for common use.

This is useful because:

- Scheme users often prefer composable procedures over command families
- keyword-heavy BASIC subcommands do not feel natural in Scheme
- helpers can package state in more readable ways without hiding the engine

## 5. Recommended low-level Scheme API

The low-level names should use the existing `gfx-` style from `graphics.md`.

### Definition operations

```scheme
(gfx-sprite-load id path)
(gfx-sprite-def id w h)
(gfx-sprite-data id x y colour-index)
(gfx-sprite-row row bytevector count)
(gfx-sprite-commit id)
(gfx-sprite-begin id)
(gfx-sprite-end)
(gfx-sprite-palette id idx r g b)
(gfx-sprite-std-pal id palette-id)
(gfx-sprite-frames id fw fh count)
(gfx-sprite-set-frame frame)
```

### Instance operations

```scheme
(gfx-sprite inst def x y)
(gfx-sprite-pos inst x y)
(gfx-sprite-move inst dx dy)
(gfx-sprite-rot inst angle-degrees)
(gfx-sprite-scale inst sx sy)
(gfx-sprite-anchor inst ax ay)
(gfx-sprite-show inst)
(gfx-sprite-hide inst)
(gfx-sprite-flip inst flip-h flip-v)
(gfx-sprite-alpha inst a)
(gfx-sprite-frame inst n)
(gfx-sprite-animate inst speed)
(gfx-sprite-priority inst p)
(gfx-sprite-blend inst mode)
(gfx-sprite-remove inst)
(gfx-sprite-remove-all)
(gfx-sprite-sync)
```

### Effects

```scheme
(gfx-sprite-fx inst effect-type)
(gfx-sprite-fx-param inst p1 p2)
(gfx-sprite-fx-colour inst r g b a)
(gfx-sprite-glow inst radius intensity r g b)
(gfx-sprite-outline inst thickness r g b)
(gfx-sprite-shadow inst ox oy r g b a)
(gfx-sprite-tint inst factor r g b)
(gfx-sprite-flash inst speed r g b)
(gfx-sprite-fx-off inst)
```

### Palette override and collision

```scheme
(gfx-sprite-pal-override inst def-id)
(gfx-sprite-pal-reset inst)
(gfx-sprite-collide inst group)
(gfx-sprite-hit a b)
(gfx-sprite-overlap group-a group-b)
```

### Queries

```scheme
(gfx-sprite-x inst)
(gfx-sprite-y inst)
(gfx-sprite-rotation inst)
(gfx-sprite-visible? inst)
(gfx-sprite-current-frame inst)
(gfx-sprite-count)
```

## 6. Recommended idiomatic Scheme helpers

These should sit on top of the low-level layer.

### A. Construction helpers

```scheme
(sprite-create! def-id w h)
(sprite-load! def-id path)
(sprite-instance! inst-id def-id x y)
```

These are just naming conveniences, but they make the most common actions clearer.

### B. Scoped sprite drawing

The runtime already supports `SPRITE BEGIN` / `SPRITE END`, which is perfect for a Scheme wrapper macro.

Recommended helper:

```scheme
(with-sprite-canvas sprite-id
  (gfx-cls 0)
  (gfx-circle 8 8 7 3)
  (gfx-rect-outline 0 0 16 16 2))
```

This should expand roughly to:

```scheme
(gfx-sprite-begin sprite-id)
(dynamic-wind
  (lambda () #f)
  (lambda () ...body...)
  (lambda () (gfx-sprite-end)))
```

This is likely the single most Scheme-friendly sprite feature to add.

### C. Property helpers

Optional convenience wrappers:

```scheme
(sprite-show! inst)
(sprite-hide! inst)
(sprite-move! inst dx dy)
(sprite-position! inst x y)
(sprite-scale! inst sx sy)
(sprite-rotate! inst deg)
(sprite-frame! inst n)
(sprite-animate! inst speed)
```

These are not strictly necessary if the `gfx-` names are already ergonomic enough.

### D. Effect helpers with symbols

Scheme should prefer symbols over numeric effect codes.

Example:

```scheme
(sprite-effect! inst 'glow #:radius 8 #:intensity 1.5 #:colour '(255 200 0))
```

But for a first version, a simple mapping helper is enough:

```scheme
(sprite-effect! inst 'glow p1 p2 r g b a)
```

with symbols mapped to:

- `'none`
- `'glow`
- `'outline`
- `'shadow`
- `'tint`
- `'flash`
- `'dissolve`

That keeps Scheme readable without forcing the low-level API to grow too much.

## 7. What Scheme should not copy from BASIC literally

A few BASIC patterns should not be ported directly.

### Avoid one giant `sprite` dispatcher function

In BASIC, `SPRITE` acts like a command family with subcommands.

That is natural in BASIC but awkward in Scheme.

Do **not** make the primary Scheme API look like this:

```scheme
(sprite 'def id w h)
(sprite 'show inst)
(sprite 'move inst dx dy)
```

That style is less discoverable and less idiomatic than separate procedures.

### Avoid forcing everything through strings or lists

Definitions and instances already have numeric identities in the runtime.

It is fine for Scheme to use explicit numeric handles at the low level. That matches the engine.

### Avoid hiding explicit commit/sync semantics entirely

The runtime has meaningful explicit points:

- commit sprite data
- end sprite canvas
- sync instance updates

Scheme helpers can reduce ceremony, but the underlying model should remain visible because it matters for performance and predictability.

## 8. Recommended first implementation in Scheme

The best first implementation is intentionally narrow.

### Phase 1

Expose the low-level runtime needed for the full core workflow:

- define / load sprite
- set palette / frames
- begin / end sprite canvas
- create instance
- show / hide
- position / move / rotate / scale / anchor
- frame / animate
- collision queries
- count / position / visibility queries

### Phase 2

Add the best Scheme helper:

- `with-sprite-canvas`

Then optionally add:

- symbol-based effect mapping
- a few convenience setters like `sprite-show!`

### Phase 3

Expand docs in [MacScheme/graphics.md](MacScheme/graphics.md) with a dedicated sprite section and examples.

## 9. Best practical Scheme examples

### Procedural sprite definition

```scheme
(gfx-sprite-def 0 16 16)
(with-sprite-canvas 0
  (gfx-cls 0)
  (gfx-circle 8 8 7 3)
  (gfx-rect-outline 0 0 16 16 2))
```

This is better than forcing users to set pixels one by one.

### Instance placement

```scheme
(gfx-sprite 0 0 120 80)
(gfx-sprite-show 0)
(gfx-sprite-scale 0 4 4)
(gfx-sprite-animate 0 0.2)
(gfx-sprite-glow 0 8 1.0 255 200 0)
```

### Collision test

```scheme
(gfx-sprite-collide 0 1)
(gfx-sprite-collide 1 2)
(when (not (zero? (gfx-sprite-overlap 1 2)))
  (display "collision!\n"))
```

### Suggested higher-level wrapper style

```scheme
(sprite-instance! 1 0 120 80)
(sprite-show! 1)
(sprite-effect! 1 'outline 1 0 255 255 255 255)
```

## 10. Recommendation for this repo

The best next implementation step is:

1. add sprite exports to [MacScheme/src/macscheme_graphics_runtime.zig](MacScheme/src/macscheme_graphics_runtime.zig)
2. register them in the Scheme bootstrap in [MacScheme/src/app_delegate.m](MacScheme/src/app_delegate.m)
3. document them in [MacScheme/graphics.md](MacScheme/graphics.md)
4. add `with-sprite-canvas` as the first high-value Scheme helper

That would immediately make the current GPU sprite engine available to Scheme users in a way that feels native to the rest of the MacScheme graphics API.

## Bottom line

The runtime is already strong.

BASIC proves the engine is designed around:

- explicit definitions
- explicit instances
- explicit visibility
- explicit effect/collision controls

Scheme should adopt the same core model, but present it as:

- small, named procedures instead of a single `SPRITE` command family
- a low-level complete API
- a few carefully chosen Scheme-first helpers, especially `with-sprite-canvas`
