# MacScheme Graphics Commands

The Scheme graphics pane is an indexed-colour framebuffer hosted in the top-right pane.

Drawing commands update the current target buffer only. Nothing is shown until you call `gfx-flip`.

For a higher-level overview of how the framebuffer, Zig runtime, bridge, and Metal presentation layers fit together, see [graphics_stack.md](graphics_stack.md).

## App menu controls

MacScheme now exposes a native **Graphics** menu for common pane-level actions:

- **Graphics → Clear**
  - Clears the graphics buffers to palette index `16` without changing the current palette entries.
  - This is useful when you want to wipe the pane quickly from the GUI without re-running Scheme code.

- **Graphics → Classic**
  - Includes `256 × 160`, `320 × 200`, `320 × 240`, `512 × 320`, `640 × 400`, and `640 × 480`.

- **Graphics → Wide**
  - Includes `720 × 480`, `800 × 450`, and `854 × 480`.

- **Graphics → Classic / Wide resolution presets**
  - Recreates the embedded graphics surface at a common logical resolution.
  - Selecting a preset makes sure the Graphics pane is visible, recreates the backing buffers, reapplies the default MacScheme palette, clears to black, and presents the new framebuffer.

The checked resolution in the menu reflects the current active graphics size.

## Example files

Try these small Scheme demos:

- [examples/graphics_primitives_demo.ss](examples/graphics_primitives_demo.ss)
- [examples/graphics_bounce_demo.ss](examples/graphics_bounce_demo.ss)
- [examples/parallax_blitter_demo.ss](examples/parallax_blitter_demo.ss)
- [examples/sprite_demo.ss](examples/sprite_demo.ss)
- [examples/sprite_shapes_demo.ss](examples/sprite_shapes_demo.ss)
- [examples/sprite_mixed_demo.ss](examples/sprite_mixed_demo.ss)

From the MacScheme project directory, load one with:

```scheme
(load "examples/graphics_primitives_demo.ss")
```

## Rendering model

- Build a frame with one or more drawing commands.
- Call `gfx-flip` to present the current back buffer.
- Call `gfx-vsync` or `gfx-wait` to pace animation.
- Use `gfx-set-target` if you want to draw into one of the extra buffers instead of the current back buffer.

Example:

```scheme
(gfx-reset)
(gfx-rect 24 16 208 128 17)
(gfx-text 32 32 "HELLO" 18)
(gfx-flip)
```

For a sprite-focused example that draws circles, boxes, triangles, and pill-like capsules into sprite definitions with different base sizes and then animates them around the screen, load [examples/sprite_shapes_demo.ss](examples/sprite_shapes_demo.ss).

For a mixed sprite scene that combines `sprite-from-rows!` sprites with primitive-authored sprite definitions in the same animation, load [examples/sprite_mixed_demo.ss](examples/sprite_mixed_demo.ss).

### Sprite cookbook

- Use `sprite-from-rows!` when:
  - you want to sketch small pixel-art sprites directly in source
  - the sprite shape is easiest to think about as rows of palette indices
  - you want the sprite dimensions inferred automatically from the row data
  - good examples: [examples/sprite_demo.ss](examples/sprite_demo.ss) and [examples/sprite_mixed_demo.ss](examples/sprite_mixed_demo.ss)

- Use `with-sprite-canvas` plus drawing primitives when:
  - you want circles, boxes, triangles, lines, or other geometric shapes
  - you want to generate multiple sprite sizes procedurally
  - you want to reuse the framebuffer-style drawing API while authoring sprites
  - good examples: [examples/sprite_shapes_demo.ss](examples/sprite_shapes_demo.ss) and [examples/sprite_mixed_demo.ss](examples/sprite_mixed_demo.ss)

- Mix both approaches when:
  - some sprites are hand-authored pixel art and others are procedural shapes
  - you want a scene with distinct art styles or rapidly generated variants
  - you want to prototype gameplay with simple primitive sprites while keeping hero or icon sprites row-authored

## Implemented commands

### Setup and frame control

- `gfx-init`
  - Initializes the graphics runtime.

- `(gfx-screen w h scale)`
  - Sets the logical screen size and scale, resets the palette, and clears the back buffer to black.

- `gfx-screen-close`
  - Closes the graphics screen.

## Embedded pane lifecycle

MacScheme embeds the graphics runtime inside the app’s Graphics pane instead of always using the runtime’s standalone window mode.

When the pane is reinitialized with a new `gfx-screen` size or a resolution preset from the app menu, the host-pane path now performs a full teardown before creating replacement buffers:

- old Metal buffers and textures are released
- Zig-side framebuffer and palette pointers are cleared before those resources are dropped
- the old embedded `MTKView` is detached and renderer/device state is reset
- the new graphics surface is then allocated and rebound cleanly

This keeps embedded reconfiguration aligned with the standalone window lifecycle and prevents the graphics state from holding stale pointers into freed resources.

- `gfx-reset`
  - Restores the default palette and clears the current target buffer to palette index `16` (black).

- `gfx-flip`
  - Presents the current back buffer.

- `gfx-vsync`
  - Waits for the renderer sync point.

- `(gfx-wait n)`
  - Waits for `n` display frames.

### Queries

- `gfx-width`
  - Returns the logical screen width.

- `gfx-height`
  - Returns the logical screen height.

- `gfx-active?`
  - Returns `#t` when graphics mode is active.

- `gfx-buffer-width`
  - Returns the backing buffer width, including overscan.

- `gfx-buffer-height`
  - Returns the backing buffer height, including overscan.

- `(gfx-pget x y)`
  - Returns the palette index at pixel `(x, y)`.

### Target buffers and scrolling

- `(gfx-set-target buffer)`
  - Selects which buffer subsequent drawing commands modify.
  - Valid buffers are `0` through `7`.

- `(gfx-scroll dx dy fill)`
  - Scrolls the current target buffer by `(dx, dy)` and fills exposed pixels with palette index `fill`.

- `(gfx-scroll-pos sx sy)`
  - Sets the displayed screen scroll offset.

### Pixels and primitives

- `(gfx-cls c)`
  - Clears the current target buffer to palette index `c`.

- `(gfx-clear r g b)`
  - Sets palette index `16` to RGB `(r g b)` and clears the current target buffer to index `16`.

- `(gfx-pset x y c)`
  - Sets one pixel to palette index `c`.

- `(gfx-line x1 y1 x2 y2 c)`
  - Draws a line using palette index `c`.

- `(gfx-rect x y w h c)`
  - Draws a filled rectangle using palette index `c`.

- `(gfx-rect-outline x y w h c)`
  - Draws a rectangle outline using palette index `c`.

- `(gfx-recti x y w h c)`
  - Alias for `gfx-rect`.

- `(gfx-circle x y r c)`
  - Draws a filled circle.

- `(gfx-circle-outline x y r c)`
  - Draws a circle outline.

- `(gfx-ellipse x y rx ry c)`
  - Draws a filled ellipse.

- `(gfx-ellipse-outline x y rx ry c)`
  - Draws an ellipse outline.

- `(gfx-triangle x1 y1 x2 y2 x3 y3 c)`
  - Draws a filled triangle.

- `(gfx-triangle-outline x1 y1 x2 y2 x3 y3 c)`
  - Draws a triangle outline.

- `(gfx-fill x y c)`
  - Flood-fills from `(x, y)` with palette index `c`.

### Text

- `(gfx-text x y text c)`
  - Draws a string using the default font.

- `(gfx-text-small x y text c)`
  - Draws a string using the small font.

- `(gfx-text-int x y value c)`
  - Draws an integer value using the default font.

- `(gfx-text-int-small x y value c)`
  - Draws an integer value using the small font.

- `(gfx-text-num x y value c)`
  - Draws a floating-point value using the default font.

- `(gfx-text-num-small x y value c)`
  - Draws a floating-point value using the small font.

- `(gfx-text-width text)`
  - Returns the width of a string in the default font.

- `(gfx-text-width-small text)`
  - Returns the width of a string in the small font.

- `gfx-text-height`
  - Returns the default font height.

- `gfx-text-height-small`
  - Returns the small font height.

### Blitting
- `(gfx-blit dst dx dy src sx sy w h)`

## Sprites

The sprite system sits alongside the framebuffer API.

- Sprite definitions store pixels, palette entries, and frame layout.
- Sprite instances store position, visibility, rotation, scale, animation, and effects.
- Use `gfx-sprite-sync` before `gfx-flip` when you want the latest instance changes reflected in the rendered frame.

### Definition setup

- `(gfx-sprite-load id path)`
  - Loads a sprite definition from a `.sprtz` file.

- `(gfx-sprite-def id w h)`
  - Creates an empty sprite definition.

- `(gfx-sprite-data id x y colour-index)`
  - Sets one pixel in the CPU-side definition staging buffer.

- `(gfx-sprite-row row pattern)`
  - Writes one whole row into the active sprite canvas from a compact ASCII pattern string.
  - Digits `0` through `9` map to palette indices `0` through `9`.
  - Letters `A` through `F` or `a` through `f` map to indices `10` through `15`.
  - `.`, space, `-`, and `_` map to transparent index `0`.

- `(gfx-sprite-commit id)`
  - Uploads staged sprite pixels to the GPU atlas.

- `(gfx-sprite-palette id idx r g b)`
  - Sets one of the sprite-local palette entries `0` through `15`.

- `(gfx-sprite-std-pal id palette-id)`
  - Requests a standard palette for a sprite definition.

- `(gfx-sprite-frames id fw fh count)`
  - Declares frame dimensions and frame count for an animation strip.

- `(gfx-sprite-set-frame frame)`
  - Selects the active frame viewport while drawing inside a sprite canvas.

### Drawing into a sprite

- `(gfx-sprite-begin id)`
  - Redirects drawing commands into sprite definition `id` instead of the screen.

- `(gfx-sprite-end)`
  - Ends sprite-canvas drawing and commits the result.

- `(with-sprite-canvas sprite-id body ...)`
  - Convenience macro that wraps `gfx-sprite-begin` / `gfx-sprite-end` with `dynamic-wind`.

Example:

```scheme
(gfx-sprite-def 0 16 16)
(with-sprite-canvas 0
  (gfx-cls 0)
  (gfx-circle 8 8 7 3)
  (gfx-rect-outline 0 0 16 16 2))
```

Row-oriented example:

```scheme
(sprite-from-rows! 1
  '("..2222.."
    ".233332."
    "23333332"
    "23322332"
    "23333332"
    ".233332."
    "..2222.."))
```

### Instance control

- `(gfx-sprite inst def x y)`
  - Creates or reassigns sprite instance `inst` to definition `def`.

- `(gfx-sprite-show inst)` / `(gfx-sprite-hide inst)`
  - Shows or hides an instance.

- `(gfx-sprite-pos inst x y)`
  - Sets absolute position.

- `(gfx-sprite-move inst dx dy)`
  - Moves by a delta.

- `(gfx-sprite-rot inst angle-degrees)`
  - Sets rotation in degrees.

- `(gfx-sprite-scale inst sx sy)`
  - Sets horizontal and vertical scale.

- `(gfx-sprite-anchor inst ax ay)`
  - Sets the anchor point used for rotation and scaling.

- `(gfx-sprite-flip inst flip-h flip-v)`
  - Enables horizontal and vertical flipping.

- `(gfx-sprite-alpha inst a)`
  - Sets transparency in the range `0.0` to `1.0`.

- `(gfx-sprite-frame inst n)`
  - Chooses the current animation frame.

- `(gfx-sprite-animate inst speed)`
  - Sets automatic animation speed.

- `(gfx-sprite-priority inst p)`
  - Sets draw priority.

- `(gfx-sprite-blend inst mode)`
  - Chooses blend mode; `#f` means normal and any true value means additive.

- `(gfx-sprite-remove inst)`
  - Removes one instance.

- `(gfx-sprite-remove-all)`
  - Removes all instances.

### Effects and palette override

- `(gfx-sprite-fx inst effect-type)`
  - Sets a low-level numeric effect code.

- `(gfx-sprite-fx-param inst p1 p2)`
  - Sets effect parameters.

- `(gfx-sprite-fx-colour inst r g b a)`
  - Sets the effect colour.

- `(gfx-sprite-glow inst radius intensity r g b)`
  - Applies a glow effect.

- `(gfx-sprite-outline inst thickness r g b)`
  - Applies an outline effect.

- `(gfx-sprite-shadow inst ox oy r g b a)`
  - Applies a shadow effect.

- `(gfx-sprite-tint inst factor r g b)`
  - Applies a tint effect.

- `(gfx-sprite-flash inst speed r g b)`
  - Applies a flash effect.

- `(gfx-sprite-fx-off inst)`
  - Clears sprite effects.

- `(gfx-sprite-pal-override inst def-id)`
  - Makes an instance use another definition's palette.

- `(gfx-sprite-pal-reset inst)`
  - Restores the instance to its own definition palette.

### Queries and collision

- `(gfx-sprite-x inst)` / `(gfx-sprite-y inst)`
  - Returns the current instance position.

- `(gfx-sprite-rotation inst)`
  - Returns the current rotation in degrees.

- `(gfx-sprite-visible? inst)`
  - Returns `#t` when the instance is visible.

- `(gfx-sprite-current-frame inst)`
  - Returns the current frame index.

- `(gfx-sprite-count)`
  - Returns the number of active instances.

- `(gfx-sprite-collide inst group)`
  - Assigns an instance to a collision group.

- `(gfx-sprite-hit a b)`
  - Returns `#t` when two instances overlap.

- `(gfx-sprite-overlap group-a group-b)`
  - Returns `#t` when any instance in one group overlaps any instance in the other.

- `(gfx-sprite-sync)`
  - Pushes current sprite instance state to the GPU.

### Convenience helpers

- `(sprite-create! def-id w h)`
  - Alias for `gfx-sprite-def`.

- `(sprite-load! def-id path)`
  - Alias for `gfx-sprite-load`.

- `(sprite-instance! inst-id def-id x y)`
  - Alias for `gfx-sprite`.

- `(sprite-from-rows! def-id rows)`
  - Builds a sprite definition from a list or vector of equal-width row strings.
  - Infers sprite width and height from the rows and draws them through `with-sprite-canvas`.

- `sprite-show!`, `sprite-hide!`, `sprite-move!`, `sprite-position!`, `sprite-scale!`, `sprite-rotate!`, `sprite-frame!`, `sprite-animate!`
  - Thin convenience wrappers over the corresponding `gfx-sprite-*` procedures.

### Recommended frame pattern

```scheme
(gfx-reset)
(gfx-sprite 0 0 120 80)
(gfx-sprite-show 0)
(gfx-sprite-scale 0 4 4)

(let loop ()
  (gfx-cls 16)
  (gfx-sprite-move 0 1 0)
  (gfx-sprite-sync)
  (gfx-flip)
  (gfx-vsync)
  (loop))
```
  - Copies a rectangle from buffer `src` to buffer `dst` using index `0` as transparent.

- `(gfx-blit-solid dst dx dy src sx sy w h)`
  - Copies a rectangle from buffer `src` to buffer `dst` without transparency.

- `(gfx-blit-scale dst dx dy dw dh src sx sy sw sh)`
  - Copies and scales a source rectangle into a destination rectangle.

- `(gfx-blit-flip dst dx dy src sx sy w h mode)`
  - Copies with flip flags in `mode`.

### Palette control

- `(gfx-pal idx r g b)`
  - Sets a global palette entry.
  - Use indices `16` and above for global colours.

- `(gfx-line-pal line idx r g b)`
  - Sets a per-scanline palette entry.
  - Intended for line palette indices `2` through `15`.

- `(gfx-line-pal-band y0 y1 idx r g b)`
  - Applies `gfx-line-pal` across a vertical band of scanlines.

### Palette effects

- `(gfx-cycle on)`
  - Enables or disables the built-in cycle effect for the default range.

- `(gfx-pal-cycle slot start end speed direction)`
  - Cycles global palette entries `start` through `end`.

- `(gfx-pal-cycle-lines slot index y0 y1 speed direction)`
  - Cycles one per-line palette index across a scanline band.

- `(gfx-pal-fade slot index speed r1 g1 b1 r2 g2 b2)`
  - Fades one global palette entry from colour A to colour B.

- `(gfx-pal-fade-lines slot index y0 y1 speed r1 g1 b1 r2 g2 b2)`
  - Fades one per-line palette entry across a scanline band.

- `(gfx-pal-pulse slot index speed r1 g1 b1 r2 g2 b2)`
  - Pulses one global palette entry between two colours.

- `(gfx-pal-pulse-lines slot index y0 y1 speed r1 g1 b1 r2 g2 b2)`
  - Pulses one per-line palette entry across a scanline band.

- `(gfx-pal-gradient slot index y0 y1 r1 g1 b1 r2 g2 b2)`
  - Applies a vertical gradient to a per-line palette entry.

- `(gfx-pal-strobe slot index on off r1 g1 b1 r2 g2 b2)`
  - Strobes one global palette entry between two colours.

- `(gfx-pal-strobe-lines slot index y0 y1 on off r1 g1 b1 r2 g2 b2)`
  - Strobes one per-line palette entry across a scanline band.

- `(gfx-pal-stop slot)`
  - Stops one palette effect slot.

- `gfx-pal-stop-all`
  - Stops all palette effects.

- `(gfx-pal-pause slot)`
  - Pauses one palette effect slot.

- `(gfx-pal-resume slot)`
  - Resumes one paused palette effect slot.

## Default palette

The current startup palette defines these global entries:

- `16` black
- `17` white
- `18` red
- `19` green
- `20` blue
- `21` yellow
- `22` cyan
- `23` magenta
- `24` orange
- `25` grey
- `26` dark grey
- `27` light red
- `28` light green
- `29` light blue
- `30` warm light
- `31` light grey

## Notes on buffers

- The runtime allocates 8 pixel buffers.
- Visible screen flipping currently uses buffers `0` and `1` as the front/back pair.
- Buffers `2` through `7` are available for off-screen drawing and blitting.

## Recommended animation pattern

```scheme
(gfx-set-target 1)
(gfx-cls 16)
(gfx-text 8 8 "FRAME" 17)
(gfx-rect x y 32 32 18)
(gfx-pal-cycle 0 18 23 1 1)
(gfx-flip)
(gfx-vsync)
```

That keeps rendering batched and presents only finished frames.


It exercises:

- batched drawing with explicit `gfx-flip`
- text rendering
- palette gradients
- palette pulse and cycle effects
- animated primitives over several frames
