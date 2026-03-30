# MacScheme Background Gradients: Sky and Land

The MacScheme graphics engine has a unique retro-inspired feature: **per-line palette gradients**.

Because MacScheme natively targets 2D, retro-style games, you often don't want to draw thousands of lines or invoke full-screen pixel manipulation in Scheme just to render a colorful sky or floor. Instead, you can use the palette engine to interpolate colors on a line-by-line basis for specific palette index slots. 

## The `gfx-pal-gradient` command

The `gfx-pal-gradient` command creates a smooth vertical transition of color across a target run of scanlines for one of the indexed-color slots. 

### Syntax
```scheme
(gfx-pal-gradient slot index y0 y1 r1 g1 b1 r2 g2 b2)
```
- **`slot`**: The effect channel to run this gradient on (0..15).
- **`index`**: The per-line palette index to mutate (2..15). Indices 0 and 1 are reserved (transparent, black), and 16..255 are strictly global.
- **`y0`** and **`y1`**: The top and bottom scanlines on the screen where the gradient applies. 
- **`r1 g1 b1`**: The RGB color at the top of the gradient.
- **`r2 g2 b2`**: The RGB color at the bottom of the gradient.

### Example: Towers of Hanoi

In the Towers of Hanoi demo, we replace a noisy, expensive, pixel plot routine with two simple gradients mapped to palette index 2 (for the sky) and 3 (for the base/land).

```scheme
; Setup palettes (sky and land)
(gfx-pal-gradient 0 2 0 base-y 40 100 240 160 210 255)
(gfx-pal-gradient 1 3 base-y height 120 180 80 40 100 40)
```

Look closely at the resulting draw function:

```scheme
(define (draw-background frame)
  (gfx-rect 0 0 width base-y 2)
  (gfx-rect 0 base-y width (- height base-y) 3))
```

Instead of looping over every pixel or line, we just draw two massive flat rectangles. One fills the top to `base-y` with color index `2`. The other fills the rest of the screen with color index `3`. 

Because index `2` and `3` have been told (via `gfx-pal-gradient`) to interpolate per-scanline, those flat rectangles magically stretch beautiful gradients across the whole screen during the final rendering.  

## Technical Implementation

MacScheme's rendering stack separates logic into **software-side composition** (the indexed color buffers manipulated by Scheme) and **GPU-side presentation** (Metal shader logic). How do gradients actually get applied without costing CPU time?

### GPU-Side Palette Animation

The real magic happens inside the Metal shader pipeline, specifically during the `palette_animate` and `palette_lookup` compute passes in `embedded_graphics_metal_source.h`.

1. **Memory Structure**: Instead of a traditional 256-color palette globally clamped to the screen, MacScheme passes two palettes to the GPU via Shared buffers. One is a standard 240-entry global palette buffer, and the second is a matrix: `buffer_height * 16`. Every single horizontal line has its own local 16-color lookup!

2. **Compute Pass 1 (`palette_animate`)**: Before the graphics engine converts to real colors, a compute kernel spins up to map active effects. When it encounters your `gfx-pal-gradient` effect bound to a `slot`, it loops down every `y` scanline from your `y0` to `y1`. For each scanline, it calculates the raw interpolated RGB between `(r1, g1, b1)` and `(r2, g2, b2)`. It then writes that calculated color directly into the per-line scratch buffer at `line_pal_work[line * 16 + index]`.

3. **Compute Pass 2 (`palette_lookup`)**: Another compute pass runs to read your software buffers (the `gfx-rect` you drew on CPU) so they can be cast onto textures. When the shader sweeps over the `y` coordinate and asks "what color is index 2 for this pixel?" it doesn't do a global lookup. It checks `line_pal_work[gid.y * 16 + 2]`. 

### Why is this efficient?
This allows Scheme to do what it is good at—game logic—while completely side-stepping expensive loop-heavy graphics manipulation. In Scheme, you update an indexed buffer exactly once. The GPU dynamically sweeps the scanlines to determine output color per-line every 16ms independently. 
