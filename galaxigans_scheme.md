# Galaxigans Scheme Demo Architecture & Design

This document details the architecture, rendering, logic, and audio systems underpinning the `galaxigans_scheme_demo.ss` game—a functional-style arcade shooter built for MacScheme.

# Aspects of the demo

Scheme is not a "pure" functional language it embraces side effects when useful. This program leverages this: it crunches all the math and physics immutably in the functional "core", and then right at the boundary (before recursing to the next frame), it fires off all its impure side-effects (the gfx-*, sound-*, and music-* calls).

Scheme supports tail recursion, allowing the use of 
the named let, rather than a traditional while loop you might use in BASIC, C etc.
The state of the games little world moves forward frame by frame.

The various characters in the game (represented as vectors), are destroyed and recreated at their new positions each frame rather than being modified. The scheme garbage collector is fine at cleaning all these vectors and making new ones every 16ms.


## 1. Overall Program Design

The program is structured around a **pure functional core with imperative rendering boundaries**. Unlike traditional object-oriented game engines that mutate entity states every frame, `galaxigans_scheme_demo.ss` models each frame transition as a mathematical function.

### The Main Loop State Machine
The game drives forward using a single, massive tail-recursive `let loop` containing all game state:
*   `frame`, `state`, `stage`, `score`, `lives`
*   Lists of entities: `stars`, `enemies`, `bullets`, `bombs`, `explosions`
*   `seed` for functional random number generation.

The loop handles state transitions (`'intro`, `'playing`, `'stage-clear`, `'game-over`). During each iteration:
1.  **Input Reading:** Polls the window for key inputs (`gfx-read-key`, `gfx-key-pressed?`).
2.  **Logic Updates:** Rebuilds entirely new lists for physics and behavior (`update-bullets`, `update-bombs`, etc.).
3.  **Collision Resolution:** Evaluates hits and removes dead entities. 
4.  **Side Effects (Rendering & Audio):** Imperative `gfx-*`, `sound-*`, and `music-*` calls are invoked to reflect the updated state.
5.  **Recurse:** Loop calls itself via tail recursion passing the newly derived state parameters.

### Functional Entity Management
Entities are implemented as vectors (via `make-star`, `make-enemy`, etc.) with accessor macros (`star-x`, `enemy-mode`). Rather than mutating an enemy's position, the map functions (`update-enemies-list`, `update-enemy`) return brand new copies of the enemy with adjusted vector coordinates.

## 2. Game Logic Mechanics

### Enemy Formations & Behaviors
Enemies possess a finite state machine of their own represented by the `enemy-mode` property:
*   `'formation`: Locked into the grid. Their structural offset is calculated relative to `formation-x` and `formation-y`, meaning the formation moves as a single unified bloc smoothly left/right and shifting down upon hitting screen edges.
*   `'dive`: When launched (`maybe-launch-diver`), an enemy calculates a smooth sine-wave swoop toward the player's position, leaving its slot in the formation.
*   `'return`: Once it drops off the bottom of the screen, the enemy loops back to the top and attempts to seamlessly re-dock into its original formation slot (`enemy-target-col`).

### Collision & Physics
*   Collision handling (like `process-bullets` and `process-bullet-hit-enemies`) evaluates proximity using `distance-squared` purely to avoid costly square-root calculations.
*   Saucers (`update-saucer`) spawn randomly via the functional RNG, providing horizontal fly-bys and dropping targeted bombs above the player.

## 3. Rendering System & Procedural Alien Art

Unlike sprite-based games, Galaxigans Scheme draws everything using MacScheme's procedural primitive batcher (`gfx-line`, `gfx-ellipse`, `gfx-triangle`, `gfx-rect`).

The graphics mode supports blobs (blitter objects) and sprites (gpu accelerated), however a modern mac is fast enough to just 'draw everything - every frame', which is what this demo does.

### Drawing Alien Classes
The `draw-enemy-shape` function builds four unique alien types depending on their `row` parameter:
*   **Row 0 (Top tier):** Uses an ellipse base with a rectangular block and angled line arms.
*   **Row 1:** Aggressive, angular shape composed mostly of triangles.
*   **Row 2:** Circular core with vertical, downward reaching appendages.
*   **Row 3 (Bottom tier):** Small ellipse shape with four sharp, spidery leg lines.

### Animation ("Flapping")
Aliens animate without using sprite sheets. The function calculates a boolean `flap` value based on a combination of the global `frame` count offset by the alien's row/column index. 
```scheme
(flap (< (modulo (+ frame (* 3 (enemy-row enemy)) (enemy-col enemy)) 16) 8))
```
This boolean toggles the Y-axis coordinates of the `gfx-line` primitives used for wings/legs, making the aliens procedurally "wiggle" as they march.

### Smooth Movement & Frame Pacing
The game achieves smooth, arcade-perfect movement through a combination of sub-pixel precision and display synchronization:
*   **Sub-pixel Floating Point Math:** All positional data—such as player coordinates, bullet vectors, and enemy diving paths—is computed using floating-point (`inexact`) arithmetic rather than snapping to integer pixel grids.
*   **Trigonometric Trajectories:** Alien dive attacks use calculated continuous paths (e.g., superimposed sine waves) rather than pre-baked waypoints to generate curvy, organic flight patterns.
*   **Double Buffering & VSync:** At the end of every logic frame, the engine calls `(gfx-flip)` to post the drawn scene to the backbuffer, followed by `(gfx-vsync)` which pauses the thread until the monitor's vertical refresh. This prevents screen tearing and locks the game to a smooth target framerate (typically 60 FPS).

## 4. Audio Architecture

The demo uses two distinct systems for sound representation to replicate an authentic old-school arcade feel.

### Synthesized Sound Effects
In-game transient effects like shooting, explosions, or powerups are driven by parameterized synthesizer commands:
*   `(sound-shoot vol duration)`
*   `(sound-explode vol duration)`
*   `(sound-click vol duration)` - Also used for enemy steps and saucer chirps.

### ABC Notation Music Strings
The game eschews external WAV/MP3 files entirely. Music loops are transcribed using multi-line **ABC notation** string literals hardcoded at the top of the Scheme file. 
*   **Loading:** These strings are wrapped in an `abc` macro and loaded into memory using `(music-load track-data)` during startup. The engine generates MIDI-like playback sequences.
*   **Playback Triggers:** During logical events in the game loop—for instance, finishing a stage or starting the intro—the logic calls `(music-play-id id vol)` (e.g., `stage-alert-id`, `player-explodes-id`).
*   **Transitioning:** The engine halts overlapping conflicting states (like a Game Over hijacking the run) using `(music-stop)` before initiating an explicit victory or defeat track.