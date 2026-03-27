# MacScheme Graphics Stack

This note explains where MacScheme graphics work happens, and which parts are CPU/software-driven versus GPU/Metal-driven.

## Short version

- The framebuffer API is mostly **software rendering**.
- Metal is used mainly for **presentation** of the finished framebuffer and for the more GPU-oriented sprite path.
- In practice, Scheme code draws into indexed-colour buffers, then the runtime presents the selected front buffer to the screen.

## Main layers

### 1. Scheme-facing API

Scheme code calls functions such as:

- `gfx-screen`
- `gfx-set-target`
- `gfx-line`, `gfx-rect`, `gfx-circle`
- `gfx-blit`, `gfx-blit-scale`, `gfx-blit-flip`
- `gfx-scroll`
- `gfx-flip`
- `gfx-vsync`

Those bindings are exposed in [src/app_delegate.m](src/app_delegate.m).

### 2. Zig graphics core

The core indexed-colour framebuffer implementation lives in [src/vendor/macgui/ed_graphics.zig](src/vendor/macgui/ed_graphics.zig).

This is where MacScheme keeps graphics state such as:

- logical width and height
- backing buffer width and height
- overscan margins
- current target buffer
- front/back buffer selection
- hardware-style scroll offsets
- palette data and palette effects

This file is also where the framebuffer commands are implemented, including:

- primitive drawing
- buffer clears
- scrolling a target buffer
- front/back flip bookkeeping
- command enqueueing for the platform bridge

For the framebuffer path, this is the part that behaves like a classic software graphics engine.

### 3. ObjC / Metal bridge

The macOS-side bridge lives in [src/vendor/macgui/ed_graphics_bridge.m](src/vendor/macgui/ed_graphics_bridge.m).

Its job is to:

- host the embedded Metal view
- allocate and manage Metal buffers/textures
- receive commands from Zig
- upload shared state to the GPU
- present the active front buffer

Think of this layer as the operating-system and renderer glue between Zig's framebuffer logic and Metal.

### 4. Metal shader/presentation layer

The display shader source is in [src/vendor/macgui/embedded_graphics_metal_source.h](src/vendor/macgui/embedded_graphics_metal_source.h).

This layer handles the final on-screen rendering of the chosen front buffer. For the framebuffer display path, it mainly:

- samples the indexed framebuffer
- applies display-time scroll offsets
- converts palette indices into visible pixels
- writes the final image to the drawable

So even when drawing is software-style, presentation is GPU-backed.

### 5. Sprite subsystem

Sprites are a related but separate path, centered in [src/vendor/macgui/sprite.zig](src/vendor/macgui/sprite.zig).

Compared with raw framebuffer drawing, sprites are more GPU-oriented:

- sprite definitions and instance state are managed on the CPU/Zig side
- sprite rendering uses dedicated GPU-side data and shader structures
- the final sprite output is integrated into the rendering pipeline differently from raw framebuffer blits

## What is software and what is GPU?

## Software / CPU-side work

These operations are best thought of as software rendering:

- framebuffer pixel writes
- lines, rectangles, circles, fills
- off-screen buffer drawing
- `gfx-blit`, `gfx-blit-scale`, `gfx-blit-flip`
- `gfx-scroll`
- front/back buffer state tracking
- palette bookkeeping and much of the frame composition logic

If you are using buffers `0` through `7` as tile layers, off-screen canvases, and blitter object sources, you are mostly using the software framebuffer system.

## GPU / Metal-side work

These parts are GPU-backed:

- presenting the final framebuffer to the screen
- applying display-time framebuffer scroll in the presentation shader
- view/window rendering synchronization
- sprite-oriented rendering work

A useful mental model is:

- **CPU/Zig:** build the frame in memory
- **GPU/Metal:** display that frame smoothly

## Typical framebuffer frame lifecycle

For a framebuffer-heavy demo such as a scrolling blitter scene, the flow is roughly:

1. Scheme calls framebuffer commands.
2. The Scheme bindings forward into the Zig graphics runtime.
3. Zig updates the indexed-colour buffers and graphics state.
4. `gfx-flip` swaps front/back buffer selection in the graphics state.
5. The bridge and Metal renderer present the current front buffer.
6. The shader samples the framebuffer and writes the final pixels to the screen.

## Why this feels retro

This architecture is similar to classic home-computer and console graphics models:

- draw into memory buffers
- use off-screen composition buffers
- flip or present a finished frame
- let display hardware show the result cleanly

That is why framebuffer demos in MacScheme feel much closer to classic software blitters than to a modern all-GPU sprite engine.

## Practical rule of thumb

- If you are using `gfx-line`, `gfx-rect`, `gfx-blit`, buffer targets, and front/back flipping, think **software framebuffer**.
- If you are using the sprite system heavily, think **hybrid with more GPU involvement**.
- In both cases, the final visible image is still presented through Metal.
