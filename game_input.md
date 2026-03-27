# MacScheme Game Input

This note documents keyboard input for games running in MacScheme’s graphics pane/window.

## Summary

MacScheme now supports game-style keyboard input through the graphics view itself.

- the graphics view receives key events when it has focus
- opening the graphics surface gives the graphics view focus automatically
- clicking inside the graphics pane/window re-focuses it for keyboard input
- Scheme can both poll current key state and read queued key presses

For gameplay, use current key state for continuous controls like movement, and queued key reads for one-shot actions like menu navigation or entering initials.

A runnable example is available at [MacScheme/examples/game_input_demo.ss](MacScheme/examples/game_input_demo.ss).

## Focus model

Keyboard input goes to the graphics view only while it is focused.

In practice:

- `(gfx-screen ...)` creates the graphics surface and focuses it
- clicking inside the graphics pane/window focuses it again
- if the app/window loses focus, pressed keys are cleared so controls do not stick

This is intended to make game loops reliable for controls such as left/right, thrust, jump, fire, pause, and menu selection.

## Scheme API

### `(gfx-key-pressed? key)`

Returns `#t` while a key is currently held down.

Accepted input forms:

- a symbol like `'left`, `'space`, `'a`, `'d`
- a string like `"left"`, `"space"`, `"a"`
- a raw macOS virtual key code integer

Examples:

```scheme
(gfx-key-pressed? 'left)
(gfx-key-pressed? 'space)
(gfx-key-pressed? 'a)
(gfx-key-pressed? 123)
```

Alias: `(gfx-key-down? key)`

### `(gfx-read-key-code)`

Reads the next queued key press and returns its raw key code, or `#f` if no key press is waiting.

This is useful when you want discrete button presses instead of continuous held-state polling.

```scheme
(let ((code (gfx-read-key-code)))
  (when code
    (display code)
    (newline)))
```

### `(gfx-read-key)`

Reads the next queued key press and returns:

- a symbolic key name such as `'left`, `'space`, or `'a` when MacScheme knows the code
- the raw integer key code for unmapped keys
- `#f` if no key press is waiting

```scheme
(let ((key (gfx-read-key)))
  (when key
    (display key)
    (newline)))
```

### `(gfx-key-code key)`

Converts a symbol/string/raw key value into the macOS virtual key code MacScheme uses internally.

```scheme
(gfx-key-code 'left)   ; => 123
(gfx-key-code 'space)  ; => 49
(gfx-key-code "a")    ; => 0
```

### `(gfx-key-name code)`

Converts a raw key code back to a symbolic name when one is known.

```scheme
(gfx-key-name 123) ; => left
(gfx-key-name 49)  ; => space
(gfx-key-name 0)   ; => a
```

If a code has no built-in name mapping, the function returns `#f`.

## Common key names

MacScheme currently provides stable built-in names for these keys:

### Direction keys

- `'left`
- `'right`
- `'up`
- `'down`

### Action / utility keys

- `'space`
- `'return` (alias: `'enter`)
- `'tab`
- `'escape` (alias: `'esc`)
- `'backspace` (alias: `'delete`)

### Modifier keys

- `'shift`
- `'control` (alias: `'ctrl`)
- `'option` (alias: `'alt`)
- `'command` (alias: `'cmd`)

### Letter keys

The letters currently mapped by name are:

- `'a` `'b` `'c` `'d` `'e` `'f` `'g` `'h` `'i` `'j` `'k` `'l`
- `'m` `'n` `'o` `'p` `'q` `'r` `'s` `'t` `'u` `'v` `'w` `'x` `'y` `'z`

These are enough for common control layouts such as:

- arrows for movement
- space for fire/jump
- `a` / `d` for left/right
- `w` / `s` for thrust/brake or menu navigation

## Recommended usage patterns

### 1. Continuous movement

Use `gfx-key-pressed?` inside the frame loop.

```scheme
(when (gfx-key-pressed? 'left)
  (set! player-x (- player-x 2)))

(when (gfx-key-pressed? 'right)
  (set! player-x (+ player-x 2)))

(when (gfx-key-pressed? 'space)
  (player-fire!))
```

### 2. Event-style menu input

Use `gfx-read-key` when you want one action per key press.

```scheme
(let ((key (gfx-read-key)))
  (cond
    ((eq? key 'up) (menu-select-prev!))
    ((eq? key 'down) (menu-select-next!))
    ((or (eq? key 'return) (eq? key 'space)) (menu-activate!))
    (else #f)))
```

### 3. Custom bindings

Store symbolic names and resolve them through `gfx-key-pressed?`.

```scheme
(define controls
  '((left . a)
    (right . d)
    (fire . space)))

(define (control-pressed? action)
  (let ((entry (assq action controls)))
    (and entry (gfx-key-pressed? (cdr entry)))))
```

## Notes on key codes

The raw integer codes exposed here are macOS virtual key codes.

That means:

- polling by symbolic name is the most readable choice for game code
- reading the raw code is still useful for rebinding systems or debugging
- `gfx-key-name` and `gfx-key-code` let you move between readable names and raw codes

For portable game logic inside MacScheme, prefer symbolic names in gameplay code and keep raw key codes only for tools or configuration.
