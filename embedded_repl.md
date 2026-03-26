# Embedded Chez Scheme REPL — Implementation Plan

## 1. Current State (as of this writing)

- PTY, expeditor, `Sscheme_start`, and all VT100 terminal emulation have been removed.
- Chez Scheme runs in-process on a **dedicated `pthread`** that calls `Sbuild_heap` at startup,
  then loops servicing eval requests from a semaphore+queue.
- The REPL pane (grid 1) uses the same native `lines`-based renderer as the editor (grid 0).
- `macscheme_eval_async` enqueues a UTF-8 string; the scheme thread evaluates it via
  `macscheme-eval-string` (a Scheme lambda installed at init), posts the result back to the
  main thread via `dispatch_async(main_queue, ...)`.
- Input handling is now **native multi-line editing** owned by Zig:
  - Enter is smart: complete expressions submit, incomplete expressions insert newline + indent.
  - The current entry is separate from read-only output and supports multi-line cursor motion.
  - Up/down navigate within the entry first, then history at the top/bottom boundary.
  - History stores full multi-line entries, supports prefix search via `Alt-P` / `Alt-N`, and
    persists across launches via a macOS app-support history file.
  - Word motion (`Alt-B` / `Alt-F`), line reindent (`Alt-Tab`), whole-entry reindent (`Alt-Q`),
    paren-match flash/jump (`Ctrl-]` / `Alt-]`), bracket auto-correction, kill/yank, mark,
    clear-entry, and double-`Ctrl-L` output clearing are implemented.
- `Tab` completion is implemented against Chez `environment-symbols`: first `Tab` completes to a
  single match or longest common prefix, repeated `Tab` shows the current candidate list below the
  entry.
- S-expression deletion is implemented via the native Mac equivalents of forward/backward
  sexp delete, and command repeat is implemented as a repeat-prefix state in the REPL.

### 1.1 macOS GUI variations

- On macOS, **Option** key combinations are delivered directly as modifier-bearing key events;
  we handle them in `SchemeTextGrid` and forward them straight to Zig instead of relying on an
  ESC-prefix emulation layer.
- `Ctrl` combinations that Cocoa text handling would normally intercept (including `Ctrl-Space`)
  are also forwarded directly from `SchemeTextGrid` to the REPL command handler.
- The native Mac UI therefore treats `Alt-*` in this document as **Option-* on macOS**.
- `Ctrl-@` and `Ctrl-Space` are handled as the same mark-setting command where the keyboard
  layout produces either variant.
- The expeditor-style repeat prefix `Escape-Ctrl-U` is implemented on macOS as the direct modified
  key chord `Ctrl-Option-U`, since the Cocoa key path forwards modifier-bearing events directly
  instead of synthesizing an ESC-prefixed sequence.

## 2. Goal

Replicate the interactive behaviour of Chez Scheme's **expeditor** (`expression-editor` module)
directly in our native Zig/ObjC UI, without PTY, without VT100 parsing, and without
running the expeditor code itself.  The UI owns all rendering and editing; Scheme only
evaluates expressions and provides two query helpers.

---

## 3. Feature Requirements

### F1 — Smart Enter (multi-line vs. submit)  ★ highest priority
On Enter:
- If the accumulated input text constitutes a **syntactically complete, balanced** Scheme
  expression → submit to Scheme for evaluation.
- If the expression is **incomplete or unbalanced** (e.g. open parens, mid-string) → insert
  a newline and auto-indent the next line.
- If the entry is **empty** → do nothing (no blank eval, no blank history entry).

Determining "balanced" requires asking Scheme (see §5.1).

### F2 — Multi-line entry buffer
- The current input being edited ("the entry") can span multiple visual lines.
- The entry is distinct from the read-only output history above it.
- Backspace at column 0 of a continuation line joins it back to the previous entry line.
- The entry starts after the most recent prompt.

### F3 — Cursor navigation within the entry
- Left/Right move one character, wrapping across entry lines.
- Up/Down within the entry navigate between entry lines (not history) when the entry has
  more than one line.
- Up on the first entry line → history backward (only if entry is unmodified or empty).
- Down on the last entry line → history forward (only if entry is unmodified or empty).
- Home / Ctrl-A → beginning of current entry line.
- End / Ctrl-E → end of current entry line.
- Ctrl-Left / Alt-B → backward word.
- Ctrl-Right / Alt-F → forward word.

### F4 — History
- Up/Down (when at boundary of entry) navigate through submitted expression history.
- History entries are stored as complete multi-line strings (not line-by-line).
- History is kept in memory per session; persistence across sessions is a later concern.
- Duplicate consecutive entries are not stored.
- Prefix search: Alt-P searches backward for the history entry whose start matches the
  current entry text.  Alt-N searches forward.

### F5 — Auto-indent
- When Enter inserts a continuation line, compute the correct indentation column:
  - Default: 2 spaces relative to the nearest enclosing open paren.
  - If the first token after `(` is a known special form (`define`, `lambda`, `let`, `if`,
    `cond`, `begin`, `when`, `unless`, `do`, `case`, `and`, `or`, `letrec`, `let*`,
    `let-values`, `define-syntax`, `syntax-rules`, `guard`, `parameterize`,
    `with-exception-handler`, `call-with-values`, etc.) use 2-space body indent.
  - Otherwise align with the first argument after the operator (standard Lisp style).
- Indentation is computed entirely in Zig (no Scheme call needed — it's purely syntactic).
- Alt-Tab / Escape-Tab → re-indent the current line.
- Alt-Q / Escape-Q → re-indent all lines of the current entry.

### F6 — Paren flash / match highlight
- When `(`, `)`, `[`, or `]` is typed, briefly move the cursor to the matching delimiter
  for ~100 ms, then return.
- If the matching delimiter is not in the visible entry, flash to the nearest edge instead.
- Ctrl-] → flash to matching delimiter on demand.
- Alt-] → jump (goto) the matching delimiter permanently.
- Auto-correct close paren: if `)` is typed but the matching open is `[`, insert `]` instead
  (and vice versa).

### F7 — Kill buffer and yank
- Ctrl-K: delete from cursor to end of current entry line; if already at EOL, join with next
  entry line.  Deleted text goes to kill buffer.
- Ctrl-U: delete entire current entry line content (leave empty line), add to kill buffer.
- Ctrl-W: delete from mark to cursor, add to kill buffer.
- Ctrl-Y: yank (insert) kill buffer contents at cursor.
- Ctrl-@ / Ctrl-Space: set mark.

### F8 — Entry-level deletion
- Ctrl-G: clear the entire current entry.
- Ctrl-C: clear entry and reset history cursor to end.
- Escape-Ctrl-K / Escape-Delete: delete the sexp starting at cursor.
- Escape-Backspace: delete the sexp to the left of cursor.

Current implementation note:
- On macOS, forward sexp delete is bound to **Option-Delete** and backward sexp delete is bound to
  **Option-Backspace**, which map cleanly onto the native modified-key event stream.

### F9 — Identifier completion (Tab)
- Tab with an identifier to the left of cursor: complete it from the list of symbols bound
  in the interaction environment.
- Tab pressed twice: show all completions as a temporary display below the entry.
- Completion list is fetched from Scheme once per Tab press (see §5.2).

Current implementation note:
- On macOS, the first `Tab` requests completions asynchronously from the Scheme thread; once the
  results arrive, the REPL inserts the longest common completion suffix when available.
- A repeated `Tab` on the same prefix reveals up to the first few matching candidates directly
  below the editable entry.

### F10 — Ctrl-D / EOF
- Ctrl-D with non-empty entry: delete character under cursor.
- Ctrl-D with empty entry: ignored (we do not exit the REPL).

### F11 — Ctrl-L redisplay
- Ctrl-L: redraw the visible entry in place.
- Ctrl-L pressed twice: clear the entire output log and redisplay only the current entry.

### F12 — Command repeat
- Escape-Ctrl-U followed by digits, then a command: repeat that command N times.
- Escape-Ctrl-U with no digits: repeat 4 times (default).

Current implementation note:
- On macOS, this is invoked as **Ctrl-Option-U**, followed by optional digits and then either a
  REPL command key or inserted text.

---

## 4. Division of Responsibility

### 4.1 Scheme side (app_delegate.m + Scheme bootstrap)

Scheme does **only two things** on behalf of the UI:

| Helper | What it does | How called |
|---|---|---|
| `macscheme-expression-complete?` | Given a UTF-8 string, attempts `(read (open-input-string s))`. Returns `#t` if a complete expression was read and the string is at end-of-file (possibly with trailing whitespace), `#f` if more input is needed, `#e` (the symbol `error`) if the string is syntactically invalid. | Synchronous C call on the Scheme pthread: `macscheme_expression_complete(bytes, len)` → returns `int`: 0=incomplete, 1=complete, 2=error |
| `macscheme-get-completions` | Given a UTF-8 identifier prefix string, returns a Scheme list of matching symbol names from `(interaction-environment)`. | Async, same pattern as `macscheme_eval_async` but posts the result list back via `grid_set_completions` |

The eval lambda `macscheme-eval-string` already handles evaluation + error capture.

The Scheme pthread owns all Scheme API calls; **no other thread may call Chez C API**.

### 4.2 UI side (grid_logic.zig)

Everything else is Zig:

- **Entry buffer**: a `std.ArrayListUnmanaged` of lines (each a `std.ArrayListUnmanaged(u32)`)
  representing the current multi-line input being edited.  Separate from the read-only
  output `lines` array.
- **Cursor**: tracked as `(entry_row, entry_col)` within the entry buffer.
- **Smart Enter**: call `macscheme_expression_complete` synchronously; branch on result.
- **Auto-indent**: pure Zig function scanning the entry buffer for open parens.
- **Paren matching**: pure Zig scan of the entry buffer.
- **History**: `std.ArrayListUnmanaged` of multi-line entry snapshots (each snapshot is a
  `[]const u8` UTF-8 string).
- **Kill buffer**: a single `std.ArrayListUnmanaged(u32)`.
- **Mark**: an optional `(row, col)` position within the entry.
- **Word movement**: pure Zig scan.
- **Rendering**: the output log (read-only) is rendered exactly as now; the entry is rendered
  below the last output line as an editable region with a distinct cursor colour.

---

## 5. New C Bridge Functions

### 5.1 `macscheme_expression_complete`

```c
// Returns: 0 = incomplete (more input needed)
//          1 = complete (submit)
//          2 = syntax error (submit anyway, Scheme will report the error)
int macscheme_expression_complete(const unsigned char *utf8, size_t len);
```

Implemented in `app_delegate.m`, called **synchronously** from the Scheme pthread.
Because `submitRepl` in `grid_logic.zig` already dispatches to the Scheme pthread via
`macscheme_eval_async`, the check can happen **on the main thread** by calling a tiny
synchronous Scheme helper.

**Design note**: this function must be called from the Scheme pthread (to avoid Chez API
thread-affinity violations).  The simplest approach: before enqueuing an eval request,
the UI posts a "check-completeness" request to the Scheme queue and **blocks** (on a
semaphore) until the result comes back.  This is safe because it is called from the main
thread while the Scheme thread is idle (waiting on the eval semaphore).

Alternative (simpler, no blocking): implement the balance check purely in Zig by counting
unescaped parens/brackets and tracking string/comment state.  This is 99% correct for
practical use and avoids any cross-thread call.  **Use this for the first implementation.**

### 5.2 `macscheme_get_completions` (Tab completion)

```c
// Async. Posts results back via grid_set_completions(words, count).
void macscheme_get_completions(const unsigned char *prefix, size_t len);
```

```zig
// Called on main thread by Scheme pthread result dispatch.
export fn grid_set_completions(words: [*]const [*]const u8, count: usize) void;
```

---

## 6. Data Model Changes in `grid_logic.zig`

### Current `GridState` (grid 1 relevant fields)
```
lines: [][]u32          -- ALL lines including output and current input
cursor_row/col          -- position in `lines`
repl_prompt_len         -- how many codepoints on last line are prompt (read-only)
history: [][]u32        -- single-line history entries
history_cursor: usize
```

### New `GridState` additions for grid 1
```
// Entry buffer (the current editable multi-line input)
entry: [][]u32          -- lines of the current entry (mutable, editable)
entry_cursor_row: usize -- cursor row within entry
entry_cursor_col: usize -- cursor col within entry

// Entry state
entry_modified: bool    -- true if user has typed since last history move
preferred_col: usize    -- desired col for up/down movement

// History (now stores complete multi-line entries as UTF-8 strings)
history: [][]u8         -- each item is a heap-allocated UTF-8 snapshot
history_cursor: usize

// Kill buffer
kill_buf: []u32

// Mark (for Ctrl-W)
mark: ?struct { row: usize, col: usize }

// Completion state
completions: ?[][]u8    -- current completion list (null = no active completion)
completion_prefix_len: usize
```

The `repl_prompt_len` field is removed.  The prompt is now the last item in `lines`
(read-only output), and the entry is a separate buffer rendered below it.

---

## 7. Rendering Changes

The render loop in `grid_on_frame` (grid 1):

1. Render the read-only output `lines` as before (scrolled so the bottom is visible).
2. On the line immediately following the last output line, render the **prompt** (e.g. `"> "`)
   using the prompt colour.
3. Render the **entry** lines, starting on the same line as the prompt, with the cursor
   drawn at `(entry_cursor_row, entry_cursor_col + prompt_len_if_row0)`.
4. Continuation lines (entry rows > 0) are indented visually by their stored indent level;
   no extra prefix is drawn (the indentation is part of the entry text).
5. **Paren flash**: when active, draw the flash-target character with a highlight colour for
   one render frame, then clear the flash state.

---

## 8. Implementation Phases

### Phase 1 — Entry buffer + smart Enter
1. Add `entry: [][]u32` and `entry_cursor_*` to `GridState`.
2. Route all typing (grid 1) into `entry` instead of `lines`.
3. Implement the Zig-side balance checker (`isExpressionComplete(entry) -> enum{incomplete, complete, error}`).
4. On Enter: check balance → if complete, serialise entry to UTF-8, push history, append
   entry to output `lines`, call `macscheme_eval_async`; if incomplete, insert newline +
   auto-indent into entry.
5. Update renderer to draw entry below output.

### Phase 2 — Auto-indent
1. `computeIndent(entry, row) -> usize`: scan entry from start, track paren depth, find
   innermost unclosed `(` or `[`, apply special-form or argument-align heuristic.
2. Wire into Enter (incomplete branch) and into Escape-Tab / Escape-Q.

### Phase 3 — Multi-line cursor + history
1. Up/Down within entry navigate between entry rows first; cross boundary to history only
   when at row 0 (up) or last row (down) and `!entry_modified`.
2. History stores full UTF-8 snapshots; restoring a history entry reconstructs `entry` from
   the stored string (split on `\n`).
3. Alt-P / Alt-N prefix search.

### Phase 4 — Paren matching
1. `findMatchingDelimiter(entry, row, col) -> ?{row, col}`: scan entry string, skipping
   strings and comments, track bracket stack.
2. On `(`, `)`, `[`, `]` typed: record flash target + flash start time; render loop
   draws cursor at flash target while `now - flash_start < 100ms`, then restores.
3. Ctrl-] flash on demand; Alt-] goto.

### Phase 5 — Kill buffer, mark, word movement
1. Kill buffer as `[]u32`; Ctrl-K, Ctrl-U, Ctrl-W append to it; Ctrl-Y inserts it.
2. Mark as optional `{row, col}`; Ctrl-Space / Ctrl-@ sets it.
3. Word movement: Ctrl-Left/Right and Alt-B/F scan for alphanumeric boundaries.

### Phase 6 — Tab completion
1. Implement `macscheme_get_completions` on Scheme side.
2. On Tab: extract identifier to left of cursor, call async completion, store result.
3. On second Tab: render completions below entry as a transient overlay.

Status: implemented for the native macOS REPL path.

### Phase 7 — Polish
1. Ctrl-L redisplay / clear-and-redisplay.
2. Ctrl-D EOF/delete-char.
3. Command repeat (Escape-Ctrl-U).
4. History persistence (write to `~/.macscheme_history` on quit, read on launch).

Status:
- `Ctrl-L` / double-`Ctrl-L` and `Ctrl-D` behavior are implemented.
- History persistence is implemented for the Mac app using an application-support history file.
- Command repeat is implemented for the native Mac REPL path.

---

## 9. Key Bindings Summary

| Key | Action |
|---|---|
| Enter | Smart submit or newline+indent (F1) |
| Backspace | Delete char left; at col 0 join with prev entry line |
| Delete / Ctrl-D | Delete char right (Ctrl-D on empty = no-op) |
| Left / Ctrl-B | Move cursor left one char (wrap across entry lines) |
| Right / Ctrl-F | Move cursor right one char (wrap across entry lines) |
| Up / Ctrl-P | Move up within entry; at top → history backward |
| Down / Ctrl-N | Move down within entry; at bottom → history forward |
| Home / Ctrl-A | Beginning of current entry line |
| End / Ctrl-E | End of current entry line |
| Ctrl-Left / Alt-B | Backward word |
| Ctrl-Right / Alt-F | Forward word |
| Alt-P | History backward by prefix |
| Alt-N | History forward by prefix |
| Tab | Identifier completion (first press complete, second press list) |
| Escape-Tab | Re-indent current line |
| Escape-Q | Re-indent all entry lines |
| `(` `)` `[` `]` | Insert paren + flash match + auto-correct close |
| Ctrl-] | Flash matching delimiter |
| Alt-] | Goto matching delimiter |
| Ctrl-K | Kill to end of line (or join) |
| Ctrl-U | Kill entire entry line |
| Ctrl-W | Kill between mark and cursor |
| Ctrl-Y | Yank kill buffer |
| Ctrl-@ / Ctrl-Space | Set mark |
| Ctrl-G | Clear entry |
| Ctrl-C | Clear entry + reset history cursor |
| Escape-Ctrl-K | Delete sexp forward |
| Escape-Backspace | Delete sexp backward |
| Ctrl-L | Redisplay entry |
| Ctrl-L Ctrl-L | Clear output log + redisplay entry |
| Escape-Ctrl-U | Command repeat prefix |

---

## 10. Files to Change

| File | Changes |
|---|---|
| `MacScheme/src/grid_logic.zig` | All entry buffer logic, balance checker, auto-indent, paren matching, kill buffer, history rewrite, rendering update |
| `MacScheme/src/app_delegate.m` | Add `macscheme_get_completions`; add Scheme-side `macscheme-expression-complete?` if balance check moves to Scheme side |
| `MacScheme/src/app_delegate.h` | No changes expected |
| `MacScheme/src/scheme_text_grid.m` | Add modifier-key handling for Alt/Escape combos (Alt-P, Alt-N, Alt-B, Alt-F, etc.) |

The `ed_terminal.zig` file is not used and remains untouched.

---

## 11. What We Are NOT Doing

- No PTY.
- No VT100/ANSI escape parsing.
- No `Sscheme_start`, no `Senable_expeditor`, no expeditor C/Scheme code.
- No forked subprocess.
- The Scheme thread never blocks waiting for UI input; it only evaluates complete
  expressions when the UI hands them over.
