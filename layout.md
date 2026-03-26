# MacScheme Layout Design

This document proposes how the MacScheme GUI should organize and control its three main panes:

- editor
- REPL
- graphics

The goal is to make the app feel useful both as a traditional Scheme editing environment and as an interactive live-coding environment where code, output, and graphics are all visible when needed.

## Goals

A good MacScheme layout system should:

- keep the editor primary for normal Scheme development
- keep the REPL easy to reach without overwhelming the editor
- make the graphics pane feel like a first-class live output surface, not a fixed tax on editing space
- support both mouse/menu users and Scheme-driven users
- allow fast switching between a small number of meaningful layouts
- allow temporary hiding of panes without destroying state
- preserve pane sizes and visibility across layout changes where practical

## Current Layout

Today the app uses a fixed three-pane split:

- a left editor pane
- a right-side vertical stack containing graphics on top and REPL below

Conceptually:

```text
+----------------------+----------------------+
|                      |       Graphics       |
|        Editor        |----------------------|
|                      |         REPL         |
|                      |                      |
+----------------------+----------------------+
```

This is a sensible default because it gives the editor the largest area while keeping both runtime-oriented panes visible.

## What a Scheme User Usually Needs

Different Scheme workflows want different visibility:

### 1. Editing-focused workflow

Most of the time, a Scheme user wants:

- a large editor
- a small but visible REPL
- no graphics pane unless actively working on graphics or teaching/demo code

This suggests the default should favor the editor strongly and allow graphics to be hidden quickly.

### 2. REPL-driven exploration

For interactive development, the user often wants:

- editor visible
- REPL large enough for history and error output
- graphics optional or hidden

This is especially useful for language learning, macro experimentation, and incremental function development.

### 3. Graphics/live-coding workflow

For graphics programming, simulation, or teaching, the user often wants:

- editor visible
- graphics large and prominent
- REPL still available, but smaller or collapsible

This keeps the app feeling like a small live environment rather than just a text editor.

### 4. Output-inspection workflow

Sometimes the user wants to focus on one pane temporarily:

- editor only
- REPL only
- graphics only

These should be treated as temporary layout modes rather than requiring window reconfiguration by hand.

## Recommended Layout Model

The app should support a small number of named layouts instead of arbitrary pane juggling as the first step.

### Core principle

There should always be one active layout preset, plus per-pane visibility flags.

That gives two useful control layers:

- **preset layouts** for fast, meaningful arrangement changes
- **show/hide toggles** for temporary visibility changes

## Recommended Presets

### 1. Balanced

Best general default.

- editor on left
- graphics top-right
- REPL bottom-right
- editor largest

```text
+----------------------+----------------------+
|                      |       Graphics       |
|        Editor        |----------------------|
|                      |         REPL         |
|                      |                      |
+----------------------+----------------------+
```

Use when:

- editing and evaluating frequently
- doing small graphics experiments
- teaching or demoing

### 2. Editor + REPL

Best default for most non-graphics Scheme work.

- editor large
- REPL visible
- graphics hidden

```text
+---------------------------------------------+
|                    Editor                   |
|---------------------------------------------|
|                     REPL                    |
+---------------------------------------------+
```

Use when:

- general Scheme coding
- debugging evaluation errors
- macro work
- file-oriented development

### 3. Editor + Graphics

Best for live graphics work where the REPL is less important.

- editor left or top
- graphics prominent
- REPL hidden

```text
+----------------------+----------------------+
|                      |                      |
|        Editor        |       Graphics       |
|                      |                      |
+----------------------+----------------------+
```

Use when:

- drawing demos
- animation work
- interactive graphics programming

### 4. Focus Editor

- editor only
- REPL hidden
- graphics hidden

Use when:

- reading or writing code for long stretches
- presenting code
- working on structural editing or long forms

### 5. Focus REPL

- REPL only
- editor hidden
- graphics hidden

Use when:

- using the app like an interactive Scheme terminal
- inspecting results, logs, or errors
- teaching evaluation interactively

### 6. Focus Graphics

- graphics only
- editor hidden
- REPL hidden

Use when:

- presenting visual output
- testing rendering
- running a demo or showcase

## Show/Hide Behavior

Each pane should be independently hideable:

- Show Editor
- Show REPL
- Show Graphics

Expected behavior:

- hiding a pane should collapse its split item rather than destroy its view
- showing a pane should restore its previous size if known
- if only one pane remains visible, it should fill the window
- hiding all panes should never be allowed; at least one pane must remain visible

## Suggested Default

The best default for startup is still **Balanced**, but with these refinements:

- editor gets the majority of width
- REPL starts smaller than graphics when graphics is active for demos
- if the graphics pane has never been used in the session, the app may later choose to default to **Editor + REPL** instead

A reasonable long-term approach:

- first release: default to **Balanced**
- later: restore the last-used layout from preferences

## Layout Menu

Add a top-level **Layout** menu.

Recommended items:

### Presets

- Balanced
- Editor + REPL
- Editor + Graphics
- Focus Editor
- Focus REPL
- Focus Graphics

### Visibility toggles

- Show Editor
- Show REPL
- Show Graphics

### Window arrangement

- Reset Layout
- Equalize Visible Panes
- Maximize Editor
- Maximize REPL
- Maximize Graphics

### Persistence

- Save Current Layout as Default
- Restore Default Layout

For the first implementation, only the preset layouts, visibility toggles, and reset command are necessary.

## Scheme Control

The embedded Scheme environment should be able to query and control layout.

This is important because:

- demos may want to reveal graphics automatically
- a teaching script may want to focus the REPL
- a graphics program may want to hide the editor temporarily
- tests or scripted demos can drive the GUI without manual clicking

## Proposed Scheme API

The Scheme side should expose a small, stable interface.

### Query functions

```scheme
(layout-current)              ; => symbol
(layout-visible-panes)        ; => list of symbols
(layout-pane-visible? 'repl)  ; => #t / #f
```

Possible results:

- layout symbols: `'balanced`, `'editor-repl`, `'editor-graphics`, `'focus-editor`, `'focus-repl`, `'focus-graphics`
- pane symbols: `'editor`, `'repl`, `'graphics`

### Command functions

```scheme
(layout-set! 'balanced)
(layout-show-pane! 'graphics)
(layout-hide-pane! 'repl)
(layout-toggle-pane! 'repl)
(layout-reset!)
```

### Optional future API

```scheme
(layout-set-divider! 'main 0.68)
(layout-set-divider! 'right 0.55)
(layout-save-default!)
```

The first implementation does not need arbitrary divider control from Scheme. Presets plus show/hide commands are enough.

## Native Bridge Design

A small native bridge should exist from Scheme into the Cocoa layout controller.

Conceptually:

```text
Scheme code
  -> foreign-procedure bindings
  -> AppDelegate layout controller
  -> NSSplitViewItem collapsed state / divider positions
```

That means the app should export native functions such as:

- `macscheme_layout_set`
- `macscheme_layout_show_pane`
- `macscheme_layout_hide_pane`
- `macscheme_layout_toggle_pane`
- `macscheme_layout_reset`
- `macscheme_layout_current`
- `macscheme_layout_pane_visible`

Then the startup Scheme bootstrap can define friendly wrappers like:

- `layout-set!`
- `layout-show-pane!`
- `layout-hide-pane!`
- `layout-toggle-pane!`
- `layout-current`

## Internal Model

The app should explicitly track layout state instead of inferring it loosely from split positions.

Suggested model:

- current preset enum
- editor visible flag
- repl visible flag
- graphics visible flag
- remembered main split ratio
- remembered right split ratio
- per-preset default ratios

This matters because:

- presets should be reproducible
- hidden panes should restore sensibly
- Scheme queries should return stable results
- menu checkmarks should stay correct

## Recommended First Implementation

Keep the first implementation narrow and reliable.

### Phase 1

- add a `Layout` menu
- support preset switching
- support show/hide for editor, REPL, graphics
- preserve divider positions when hiding/showing panes
- expose Scheme commands for preset selection and pane visibility

### Phase 2

- add menu checkmarks for active preset and visible panes
- persist last-used layout between launches
- add reset/equalize/maximize commands

### Phase 3

- allow scripted divider ratios
- support saved custom named layouts
- optionally support opening graphics in a separate window

## Recommended First Menu Shortcuts

These should be easy to remember and avoid collisions where possible:

- `Cmd-1` Balanced
- `Cmd-2` Editor + REPL
- `Cmd-3` Editor + Graphics
- `Cmd-4` Focus Editor
- `Cmd-5` Focus REPL
- `Cmd-6` Focus Graphics

Optional toggles:

- `Cmd-Option-E` toggle editor
- `Cmd-Option-R` toggle REPL
- `Cmd-Option-G` toggle graphics

## UX Notes

A few details will matter a lot:

- The editor should never disappear accidentally without an obvious way back.
- If evaluation triggers graphics use, the app may auto-show graphics once, but this should be conservative and predictable.
- When the REPL is hidden, evaluation errors should either reveal it or show a clear inline/macOS alert path so failures are not invisible.
- Layout changes should feel instant and should not recreate views.
- Menu labels should use user language like “Show Graphics” instead of implementation language like “Toggle Split Item 2”.

## Best Practical Default

If choosing one strong recommendation for Scheme users, it is this:

- startup layout: **Balanced**
- most common working layout: **Editor + REPL**
- most important temporary command: **Show/Hide Graphics**

That combination serves both traditional Scheme work and live graphics work without making either feel awkward.

## Implementation Notes for This Repo

Based on the current app structure, the implementation likely belongs in the Cocoa shell around the existing split-view setup in `MacScheme/src/app_delegate.m`.

The current arrangement already maps well to the proposed presets:

- main split: editor vs right-side stack
- right split: graphics vs REPL

That means most layout features can likely be implemented by:

- keeping references to the three `NSSplitViewItem`s
- changing `collapsed` state on each item
- adjusting the main and right divider positions
- updating menu item state
- exporting a few layout-control C functions for the Scheme bridge

This is a good fit for incremental implementation.
