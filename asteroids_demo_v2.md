# Asteroids Demo Review v2

## Executive Summary

`asteroids_demo.ss` is a strong small game demo and a good MacScheme example. It already captures the core Asteroids feel: inertia, wraparound movement, asteroid splitting, simple vector-style rendering, and a clean recursive frame loop.

That said, it is still closer to a **solid prototype** than to a faithful recreation of classic Asteroids. The biggest gaps are not cosmetic; they are gameplay and progression features. There is also one especially important behavior issue: when the field is cleared, the game currently restarts with **score reset to 0 and lives reset to 3**, which breaks the arcade progression loop.

This document does three things:

1. Reviews the game itself.
2. Reviews the existing `asteroids_demo_review.md`.
3. Proposes a prioritized `v2` roadmap based on features classic Asteroids actually relies on.

---

## 1. Review of the Game

## What the game already does well

### 1.1 Core feel is correct
The demo gets the most important Asteroids ingredients right:

- ship rotation plus thrust-based inertia
- velocity persistence with light damping
- bullets inheriting some ship momentum
- screen wrap on ship, bullets, and asteroids
- large-to-medium-to-small asteroid splitting
- immediate restart/game-over loop suitable for a demo

That means the game is already fun in the most important way: moving and shooting feels like Asteroids instead of like a top-down shooter.

### 1.2 The program structure is good Scheme
The overall style is reasonable and pleasant:

- the game state is threaded explicitly through a tail-recursive loop
- helper procedures separate drawing, updating, collision, spawning, and scoring
- entities are lightweight vectors with named accessors, which is a practical choice for a demo
- list recursion is used consistently and clearly

This is good “small functional game” Scheme. It is not trying to be overly abstract, which is the right call for a project of this size.

### 1.3 The rendering choices fit the genre
Using line art and circle outlines is a good match for classic vector Asteroids. The code also wisely avoids overcomplicating the visuals. The result is readable, fast, and stylistically coherent with the rest of the engine demos.

---

## 2. Code Quality Notes

## What looks strong

### 2.1 State flow is easy to follow
The high-level flow is straightforward:

- read input
- update ship movement
- optionally fire
- update bullets, asteroids, and puffs
- resolve collisions
- branch into ship-hit, field-clear, game-over, or normal-render path
- render and recurse

For a game example, this is very understandable.

### 2.2 The helper breakdown is sensible
The following separations are especially good:

- `spawn-asteroid` / `spawn-asteroids`
- `update-bullets`, `update-asteroids`, `update-puffs`
- `split-asteroid`
- `resolve-asteroids`
- `draw-ship`, `draw-bullets`, `draw-asteroids`, `draw-puffs`, `draw-hud`

This is a good “flat but organized” structure.

## What should change

### 2.3 The field-clear branch resets progression
This is the most important gameplay problem.

When all asteroids are destroyed, the code launches a fresh wave, but it also resets:

- score to `0`
- lives to `3`
- bullets to empty
- ship position and state to default

Resetting bullets and repositioning the ship is reasonable. Resetting score and lives is not. In classic Asteroids, clearing a wave advances the game; it does not start a new game.

This should be treated as the first fix in a real `v2`.

### 2.4 `resolve-asteroids` is the right idea, but a little dense
`resolve-asteroids` works, but it is the hardest procedure in the file to read. Reasons:

- nested recursion inside nested recursion
- multiple `cadr` / `caddr` / `cadddr` style unpacking
- rebuilding bullet lists using `append` and `reverse`

For a small demo this is acceptable, but if the game grows to support saucers, saucer bullets, score-based extra lives, and wave scaling, this area will become the first maintenance pain point.

A `v2` would benefit from replacing the raw positional list return value with a named structure or at least a clearer convention.

### 2.5 Collision checks are correct but not especially cheap
The current collision logic uses Euclidean distance with `sqrt`. That is fine at this scale, but classic Asteroids-style games do a lot of repeated collision tests. Comparing squared distances would be a clean optimization if the entity count grows.

### 2.6 Rendering/state branches repeat work
The game-over, ship-hit, field-clear, and normal play branches all perform slightly different versions of the same scene rendering work. This is not wrong, but it suggests a missing `render-scene` style helper.

### 2.7 There is at least one unused helper
`clamp` appears to be unused. That is minor, but it suggests the file would benefit from one cleanup pass now that the demo has stabilized.

---

## 3. Is it “reasonable Scheme”?

Yes.

More specifically, it is good **practical Scheme for a compact real-time game**:

- explicit state threading instead of hidden global mutation
- lots of tiny helpers instead of one giant update function
- direct math and direct data layout
- recursion used where another language might use `for` loops

I would not push this toward a heavier abstraction style unless the game is going to keep growing. The current style is honest, readable, and well sized for the problem.

The one place where I would become more structured is once new entities arrive. If `v2` adds saucers, saucer bullets, wave state, extra-life thresholds, and hyperspace logic, then the current “one long loop with many scalar parameters” will start to fight back. At that point a single explicit world record becomes worthwhile.

---

## 4. Missing Features Compared to Classic Asteroids

This is the biggest omission in the first review. The current demo captures the basic loop, but classic Asteroids relies on several systems that are still absent.

## High-priority missing features

### 4.1 Wave progression
Classic Asteroids escalates over time. The current demo respawns the same style of field every time.

`v2` should add:

- wave counter
- increasing asteroid count or speed
- preserved score and lives across waves
- short “next wave” transition instead of a hard reset

### 4.2 Flying saucers / UFOs
A major part of classic Asteroids is the saucer threat. It changes the pacing from “clear rocks” to “manage cross-screen pressure and aimed enemy fire.”

`v2` should add:

- occasional saucer spawn
- small and/or large saucer variants
- saucer movement across the screen
- saucer bullets
- score values for destroying saucers

If only one classic feature gets added beyond wave progression, this is the one.

### 4.3 Extra lives by score threshold
Classic Asteroids rewards sustained survival and scoring. The current demo has lives, but no long-term reward loop.

`v2` should add:

- extra ship every N points
- tracking of the next extra-life threshold

### 4.4 Safe respawn logic
The current game gives temporary invulnerability, which is good, but it still respawns the ship in a fixed central location. Classic Asteroids tries hard not to place the ship directly into unavoidable chaos.

`v2` should add one of these:

- safe-center respawn only if the area is clear
- delayed respawn until the center is safe
- search for a safe spawn zone

## Medium-priority missing features

### 4.5 Hyperspace
Hyperspace is one of the most recognizable classic mechanics. It is risky, dramatic, and helps recover from impossible situations.

`v2` should add:

- a hyperspace input
- random relocation
- optional failure chance, matching arcade behavior more closely
- brief invulnerability or a post-warp risk rule, depending on desired authenticity

### 4.6 Classic shot limits / firing behavior
Original Asteroids did not allow unlimited fire density. Shot count and cadence are a big part of the feel.

`v2` should consider:

- maximum simultaneous bullets
- slightly more arcade-authentic fire cadence
- maybe a cleaner distinction between bullet lifetime and bullet cap

### 4.7 Better ship death presentation
The current puff effect is enough for a prototype, but classic Asteroids has a more dramatic ship breakup feel.

`v2` could add:

- line-fragment ship explosion pieces
- a slightly longer death pause
- stronger audio feedback for death vs asteroid destruction

### 4.8 Screen-edge wrap presentation
Movement wraps mechanically, but the rendering does not try to draw duplicate edge ghosts. That means objects can visually “pop” at the border rather than feeling continuous.

This is not mandatory, but it would improve polish a lot.

## Lower-priority but valuable features

### 4.9 Score table / high-score memory
This matters if the game becomes something players return to rather than just a demo.

### 4.10 Attract mode / title screen
Helpful for presentation, not essential for core play.

### 4.11 Audio pacing and heartbeat tension
Classic Asteroids uses a heartbeat-like progression to ratchet tension. A modernized equivalent would help a lot.

---

## 5. Review of `asteroids_demo_review.md`

The current review is useful, but incomplete.

## What it gets right

- It correctly identifies the game as a functional recursive loop.
- It correctly praises the helper decomposition.
- It correctly notes that the code is reasonable Scheme.
- It gives sensible implementation suggestions like collision optimization and reducing repeated render code.

So the existing review is not wrong. It is a good first-pass architectural review.

## What it misses

### 5.1 It is too generous about gameplay completeness
The current review reads a little like the game is already a finished Asteroids interpretation. It is not. It is a strong prototype with good fundamentals.

### 5.2 It misses the biggest gameplay bug
The review does not mention that clearing the field resets score and lives. That is the most important design issue in the file because it breaks progression.

### 5.3 It focuses more on code style than on game design
That is fine if the only question is “is this reasonable Scheme?”, but once the topic is Asteroids, classic gameplay systems matter just as much as data structures.

### 5.4 It suggests `define-record-type` too strongly
That suggestion is defensible, but it is probably not the highest-value next move.

For this file, the order of importance is more like:

1. fix progression
2. add wave structure
3. add saucers
4. add safe respawn / extra lives / hyperspace
5. only then consider heavier structural refactors if the file becomes crowded

In other words: the first review is more compiler-and-style oriented than player-and-design oriented.

---

## 6. Recommended `v2` Scope

If the goal is to make a real `asteroids_demo_v2.ss` later, this is the order I would use.

## Phase 1: Fix the foundation

1. Preserve score across waves.
2. Preserve lives across waves.
3. Add a wave counter.
4. Increase difficulty per wave.
5. Clean up duplicated render branches.

## Phase 2: Add classic identity

6. Add saucers.
7. Add saucer bullets.
8. Add extra-life thresholds.
9. Add safe respawn logic.
10. Add hyperspace.

## Phase 3: Add polish

11. Add ship-fragment explosion effects.
12. Add wrap-edge ghost rendering.
13. Improve sound pacing and tension.
14. Add title/high-score presentation if desired.

---

## 7. Final Recommendation

The current Asteroids demo is good enough to keep and build on. It should not be thrown away or heavily rewritten.

My recommendation is:

- keep the current functional style
- keep vectors/accessors unless the file grows substantially
- treat progression fixes as mandatory
- treat saucers as the most important missing classic feature
- treat hyperspace and extra lives as the next layer that makes it feel truly like Asteroids instead of “asteroids-like”

So the headline is:

**Good Scheme. Good prototype. Not yet a complete Asteroids.**

And the best next step is not a structural rewrite. It is a gameplay-completeness pass.
