# MacScheme Graphics Commands

The Scheme graphics pane is an indexed-colour framebuffer hosted in the top-right pane.

Drawing commands update the current target buffer only. Nothing is shown until you call `gfx-flip`.

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

## Implemented commands

### Setup and frame control

- `gfx-init`
  - Initializes the graphics runtime.

- `(gfx-screen w h scale)`
  - Sets the logical screen size and scale, resets the palette, and clears the back buffer to black.

- `gfx-screen-close`
  - Closes the graphics screen.

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
