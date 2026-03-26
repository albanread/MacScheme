# MacScheme Editor Behaviors

This document is the implementation specification for the MacScheme Editor panel. It defines the expected editing model, visual behavior, menu structure, and runtime integration for editing Scheme code in a way that feels both native on macOS and familiar to Lisp and Scheme users.

The editor should combine four ideas:

*   **Native macOS document behavior:** predictable file handling, menu commands, focus behavior, undo/redo, and shortcuts.
*   **Scheme-aware structure editing:** editing should preserve balanced forms where practical and make common list operations easy.
*   **Direct REPL integration:** code in the editor should flow naturally into the running Chez Scheme backend.
*   **Readable presentation:** syntax highlighting, bracket matching, and indentation should make nested Scheme code comfortable to work with.

## 0. Product Goals

*   Make editing Scheme source feel safer than plain text editing.
*   Preserve standard macOS expectations for document-based applications.
*   Support both beginners using menus and experienced Schemers using keyboard-driven workflows.
*   Keep the initial implementation lightweight: structural editing should be useful even before a full parser exists.

## 0.1 Initial Non-Goals

These capabilities are explicitly out of scope for the first editor implementation:

*   Full semantic analysis of Scheme modules and libraries.
*   Refactoring tools such as rename-symbol across files.
*   Inline evaluation result overlays inside the editor buffer.
*   Multi-file project navigator or package manager UI.

## 1. Structural S-Expression Editing ("Paredit-Lite")

Instead of treating code purely as a sequence of characters, the editor assists the user by understanding the underlying syntax tree (parenthesis nesting).

*   **Auto-Pairing:** Typing an opening delimiter (`(`, `[`, `"`) automatically inserts the closing pair (`()`, `[]`, `""`) and places the cursor between them.
*   **Skip-Over Closing Delimiters:** If the cursor is immediately before an auto-inserted closing delimiter and the user types that same delimiter, the cursor advances instead of inserting a duplicate character.
*   **Safe Deletion:** Pressing `Backspace` or `Delete` on a parenthesis only succeeds if the paired list is empty (e.g., `()`). If the list contains elements, the editor prevents accidental unbalanced deletion, requiring the user to either empty the list first or use a forced delete command.
*   **Wrap / Unwrap:**
    *   *Wrap*: Selecting an expression and typing `(` wraps it in a new list: `foo` → `(foo)`.
    *   *Splice/Unwrap*: Removes the surrounding parentheses of the current list, promoting its contents up a level: `(a (b c) d)` → `(a b c d)`.
*   **Structural Slurp and Barf:**
    *   *Slurp*: Pull the next adjacent S-expression *into* the current list. 
        *   Before: `(a b) c` → After: `(a b c)`
    *   *Barf*: Push the last element of the current list *out* of the list.
        *   Before: `(a b c)` → After: `(a b) c`

### Default Structural Editing Rules

*   Structural protections are enabled by default in the editor panel.
*   Pasting text is always allowed, even if it temporarily creates unbalanced text; the editor should highlight the problem instead of blocking paste.
*   A menu-visible command should exist to perform a **forced delete** when the user intentionally wants raw text behavior.
*   String literals and comments must suppress list-editing commands when the cursor is inside them unless the command clearly targets raw text.

## 2. Scheme-Aware Indentation

Lisp indentation is semantic. The editor calculates indentation dynamically based on the current nesting depth and the first symbol of the list.

*   **Semantic Alignment:** If the first symbol is a standard function, subsequent lines align with the first argument.
    ```scheme
    (some-func arg1
               arg2)
    ```
*   **Special Forms:** If the first symbol is a recognized special form or macro (e.g., `define`, `let`, `lambda`, `if`, `cond`), the body is indented by exactly 2 spaces from the opening parenthesis.
    ```scheme
    (define (foo x)
      (let ((y 10))
        (+ x y)))
    ```
*   **Intelligent Tab:** Pressing `Tab` does not insert a raw tab character. Instead, it re-indents the current line (or selected block) to its structurally correct depth. Pressing `Return` automatically applies the correct indentation for the new line.

### Indentation Defaults

*   The editor uses spaces, never hard tab characters, for Scheme source indentation.
*   The default indentation width for body forms is 2 spaces.
*   Pressing `Shift-Tab` should reduce indentation for the current line or selected region in a structure-aware way where possible.
*   A future extension may allow custom indentation rules for user macros, but the initial implementation should recognize core Chez/Scheme forms only.

## 3. Editor-to-REPL Integration

The editor panel acts as a live conduit to the underlying Chez Scheme runtime.

*   **Evaluate Current Form:** Send the top-level S-expression under (or immediately preceding) the cursor to the REPL for immediate evaluation.
*   **Evaluate Buffer:** Reload the entire editor panel's content into the runtime.
*   **Live Context (Signatures & Docs):** Inspecting a symbol fetches its signature from the active Chez environment.
*   **Macroexpansion:** Request the macro-expanded version of the current S-expression (useful for debugging `syntax-case` or `define-syntax`).

### REPL Integration Defaults

*   Evaluation commands should report errors in the REPL panel and visually indicate the relevant editor region when possible.
*   Evaluating the current form should prefer the enclosing top-level form rather than the smallest nested list.
*   Evaluating the full buffer should save the buffer first if the user has enabled auto-save-on-evaluate; otherwise it should evaluate the current unsaved editor contents directly.
*   Long-running evaluation must remain interruptible via a menu item and keyboard shortcut.

## 4. Proposed macOS Keybindings

These bindings map traditional Lisp editing concepts onto standard macOS modifier keys (`Cmd` for app/global actions, `Option` for words/structure, `Ctrl` for legacy terminal/Emacs actions).

### Navigation & Selection
*   `Option-Right` / `Option-Left`: Move forward/backward by *S-expression* (skipping over entire lists or atoms).
*   `Cmd-Up` / `Cmd-Down`: Move up/down a level in the parenthesis tree (into or out of a list).
*   `Option-Up`: Expand the current text selection to encompass the entire enclosing S-expression.

### Structural Editing
*   `Option-Delete` / `Option-Backspace`: Kill the previous S-expression (already standard in the REPL).
*   `Ctrl-Option-Up`: Splice / unwrap the enclosing list.
*   `Ctrl-Option-Right`: Slurp forward (pull next S-expression into the current list).
*   `Ctrl-Option-Left`: Barf forward (push the last S-expression out of the current list).
*   *Note*: The standard mapping for Paredit slurp/barf often uses `Ctrl-Right/Left`, but macOS reserves these for Mission Control workspace switching. `Ctrl-Option` avoids this collision.

### Evaluation & REPL Interaction
*   `Cmd-Enter` (or `Cmd-E`): Evaluate the current top-level S-expression.
*   `Cmd-B`: Evaluate the entire Editor Buffer.
*   `Cmd-I`: Show inspector or macro-expansion for the current form.

## 5. Visual Feedback & Rendering

To assist with reading dense Scheme code, the editor provides contextual visual cues.

*   **Syntax Highlighting:** Live tokenization and coloring of Scheme elements:
    *   **Keywords / Special Forms:** `define`, `lambda`, `let`, `if`, `cond`, etc.
    *   **Literals:** Strings (`"..."`), Numbers (`42`, `#x2A`), Characters (`#\A`), Booleans (`#t`, `#f`).
    *   **Comments:** Line comments (`;;`) and block comments (`#| ... |#`).
    *   **Quoted Forms:** Differentiating quoted symbols (`'foo`) from evaluated variables.
*   **Visual Bracket Matching:** 
    *   When the cursor is adjacent to an opening or closing parenthesis (or bracket/brace), the corresponding matching pair is highlighted.
    *   *Rainbow Parentheses (Optional):* Distinct colors for different nesting depths to easily track deeply nested S-expressions at a glance.
    *   *Unbalanced Indicator:* Immediate visual warning (e.g., red highlighting) if a closing parenthesis is typed without a corresponding opening pair.

### Rendering Defaults

*   Matching bracket highlighting should be enabled by default.
*   Rainbow parentheses should be optional and user-toggleable.
*   The active line should be subtly highlighted.
*   Selection rendering must remain legible when nested delimiters are also highlighted.
*   The editor should support a monospaced default font suitable for code and preserve Unicode Scheme identifiers.

## 6. macOS Menu Structure & File Operations

To make the application feel like a first-class macOS citizen while serving Schemers' workflows, the standard menu bar will expose both standard file operations and Lisp-specific commands. This ensures discoverability for complex key chords.

### File Menu
*   **New / Open... / Save / Save As...:** Standard macOS file operations (`Cmd-N`, `Cmd-O`, `Cmd-S`, `Cmd-Shift-S`), targeting `.ss`, `.scm`, and `.sls` extensions.
*   **Open Recent:** Standard macOS recent-document submenu.
*   **Revert to Saved:** Restore the editor buffer from disk after confirmation if there are unsaved changes.
*   **Load File into REPL...:** Directly prompts for a Scheme file and runs `(load "...")` in the Chez Scheme runtime without necessarily opening it in the editor panel.
*   **Save a Copy...:** Standard macOS-style export/save-copy behavior for creating a duplicate without changing the current document identity.

### Edit -> Structural (Submenu)
Since Paredit-style chords can be difficult to memorize initially, exposing them in the menu aids discoverability:
*   **Wrap in Parentheses:** (`Option-Shift-9` or `Ctrl-Option-W`)
*   **Splice (Unwrap):** Removes surrounding parentheses.
*   **Slurp Forward:** Pull next item into list (`Ctrl-Option-Right`).
*   **Barf Forward:** Push last item out of list (`Ctrl-Option-Left`).
*   **Re-indent S-expression:** Automatically fixes formatting for the current selection or top-level form without manually hitting `Tab` on every line.
*   **Select Enclosing Form:** Expands selection to the current enclosing list.
*   **Balance / Check Parentheses:** Reports whether the current buffer is balanced and, when possible, moves to the nearest mismatch.

### Scheme / Evaluate Menu
A dedicated menu for runtime state and execution manipulation:
*   **Evaluate Buffer:** (`Cmd-B`)
*   **Evaluate Top-Level Form:** (`Cmd-Enter` or `Cmd-E`)
*   **Evaluate Selection:** If there is a selection, evaluate exactly that text; otherwise disabled.
*   **Load Current File:** Save if needed and evaluate via `(load ...)` using the file path rather than buffer text.
*   **Compile Current File:** For workflows that expect compile/load behavior from a menu command.
*   **Macroexpand Form:** (`Cmd-I` or `Cmd-Option-M`)
*   **Apropos / Search Symbol...:** Search for symbols available in the current environment.
*   **Describe Symbol:** Show documentation or binding details for the symbol at point.
*   **Interrupt Evaluation:** (`Cmd-.`) - Crucial for halting infinite loops or long-running computations (sends a break signal/interrupt to the native Chez thread).
*   **Clear REPL:** (`Cmd-K`) - Wipes the REPL panel's visual grid output.
*   **Restart Scheme Backend:** Kills the current Chez Scheme environment and boots a fresh one, clearing all top-level definitions to give the user a clean slate.

## 7. Expected Document Behavior on macOS

The editor panel should behave like a standard macOS document editor whenever possible.

*   Opening a Scheme file creates or reuses an editor document window/panel and marks the current file path clearly in the title bar.
*   Unsaved changes should use the standard macOS edited indicator and close-confirmation behavior.
*   `Cmd-W` closes the current document view; if it has unsaved changes, the system should prompt appropriately.
*   Undo and redo use the platform defaults (`Cmd-Z`, `Cmd-Shift-Z`) and operate on structural commands as single coherent actions where practical.
*   Drag-and-drop of `.scm`, `.ss`, or `.sls` files into the app should open them in the editor.

## 8. Rollout Plan

To keep implementation tractable, the editor should be built in phases.

### Phase 1: Core Text Editing

*   ✅ Open (`Cmd+O`) — NSOpenPanel, UTF-8 load, window title update.
*   ✅ Save (`Cmd+S`) — NSSavePanel on first save, atomic write, path persisted in rope state.
*   ✅ Save As (`Cmd+Shift+S`) — forces NSSavePanel even if a path already exists, writes atomically, and updates the document path/title.
*   ✅ Revert to Saved (`Cmd+R`) — confirms, then reloads the current editor file from disk.
*   ✅ Syntax highlighting — single-pass tokenizer per line; colors: keywords (cyan), strings (amber), numbers (green), parens (grey-blue), comments (dark green). State (string/block-comment) threads across lines.
*   ✅ Scheme-aware indentation on `Return` — `editorComputeIndentAtCursor()` scans rope for innermost open delimiter; inserts newline then spaces.
*   ✅ `Tab` re-indents current line — `editorIndentCurrentLine()` adds/removes leading spaces to match computed indent.
*   ✅ Region re-indent (`Option-Q`) — re-indents every selected line using the same structure-aware indentation rules as `Tab`, and falls back to the current line when there is no selection.
*   ✅ Bracket matching highlight — `editorBracketUnderCursor()` + `editorFindMatchingBracket()` light up both delimiter pair cells with `bracket_match_bg` every frame.
*   ✅ Unbalanced delimiter warning — an adjacent unmatched delimiter is highlighted with a warning background when no balancing partner is found.
*   ✅ Unsaved-changes indicator in title bar — editor mutations set a dirty bit and the macOS document edited indicator tracks it live.

### Phase 1.5: Editor-to-REPL (implement next)

*   ✅ `Cmd+Enter` — scans backward to find top-level form at column 0, scans forward to balanced close, sends to REPL via `macscheme_eval_async`.
*   ✅ `Cmd+B` — sends entire buffer UTF-8 to REPL via `macscheme_eval_async`.

### Phase 2: Structural Editing

*   ✅ Auto-pairing — typing `(` inserts `()` and places cursor between; same for `[` → `[]`, `"` → `""`.
*   ✅ Skip-over closing delimiter — typing `)`, `]`, or `"` when cursor is immediately before that char advances the cursor instead of inserting.
*   ✅ Safe deletion of empty pairs — Backspace when cursor is between `()`, `[]`, or `""` deletes both characters.
*   ✅ `Option+Right` / `Option+Left` — `editorMoveSexpForward()` / `editorMoveSexpBackward()` skip whitespace, traverse lists with balanced-delimiter scanning, and stop at atom boundaries.
*   ✅ Select enclosing form (`Option-Up`) — tracks an editor selection range, highlights it in the grid, and expands to the next enclosing list on repeated use.
*   ✅ Wrap selection in parentheses — typing `(` with an active editor selection inserts surrounding parens and keeps the wrapped form selected.
*   ✅ Splice / unwrap surrounding list — `Ctrl+Option+Up` removes the enclosing delimiters and keeps the unwrapped contents selected.
*   ✅ Slurp / Barf — `Ctrl+Option+Right` moves the enclosing close delimiter past the next S-expression, and `Ctrl+Option+Left` pushes the last enclosed S-expression back out.
*   ✅ Structural undo grouping — editor mutations capture pre-edit snapshots, so structural commands undo as single steps with `Cmd+Z` and redo with `Cmd+Shift+Z`.

### Phase 3: Runtime Integration

*   ✅ Evaluate selection — `Cmd+E` evaluates the current selection when one exists; otherwise it falls back to the current top-level form.
*   ⬜ Interrupt execution (`Cmd+.`).
*   ⬜ Macroexpand form.
*   ⬜ Describe symbol / apropos.
*   ⬜ Restart Scheme backend.

## 9. Acceptance Criteria

The editor design is considered implemented when the following are true:

*   A user can open a Scheme file, edit it, save it, and reload it using standard macOS document flows.
*   Entering and editing balanced forms feels safe by default and does not frequently produce accidental unbalanced code.
*   Indentation is correct for common Scheme forms without requiring manual spacing on every line.
*   Matching delimiters and syntax categories are visually obvious while editing.
*   A user can evaluate the current form, selection, buffer, or file into the running Chez backend without leaving the editor.
*   The most important structural editing commands are available both as shortcuts and as discoverable menu items.

## 10. Engineering Task List

This section breaks the editor work into implementation tasks that can be completed incrementally.

### Milestone A: Document & Buffer Foundation

*   Add an editor buffer model that stores text, selection, cursor position, dirty state, and file path.
*   Add file loading and saving for `.scm`, `.ss`, and `.sls` documents.
*   Add document lifecycle handling for new, open, save, save as, revert, and close-with-unsaved-changes.
*   Add undo/redo integration so edits and structural commands can be grouped coherently.

### Milestone B: Rendering & Visual Feedback

*   Add syntax tokenization for comments, strings, numbers, booleans, characters, quoted forms, and known special forms.
*   Render syntax-highlighted text in the editor panel.
*   Add bracket matching and nearest mismatch highlighting.
*   Add active-line highlighting and selection rendering that coexists with delimiter highlighting.

### Milestone C: Indentation & Core Editing

*   Add `Return` behavior that inserts a new line and computes Scheme-aware indentation.
*   Add `Tab` and re-indent-region behavior using spaces only.
*   Add special-form indentation rules for common core forms such as `define`, `lambda`, `let`, `let*`, `letrec`, `if`, `cond`, `case`, `begin`, and `syntax-case`.
*   Preserve correct behavior inside comments and string literals.

### Milestone D: Structural Editing

*   Add delimiter auto-pairing and skip-over behavior.
*   Add safe deletion for empty delimiter pairs.
*   Add select-enclosing-form.
*   Add wrap, splice, slurp, and barf commands.
*   Add forced-delete behavior for users who intentionally want raw text editing.

### Milestone E: Menus & Commands

*   Add File menu commands for new, open, open recent, save, save as, save a copy, revert, and load file into REPL.
*   Add an Edit → Structural submenu exposing the main structural editing commands.
*   Add a Scheme / Evaluate menu for evaluating the current form, selection, buffer, and current file.
*   Add interrupt, clear REPL, restart backend, macroexpand, describe symbol, and apropos commands.

### Milestone F: Runtime Integration

*   Add command plumbing from the editor panel to the Chez backend.
*   Add current-form extraction, selection evaluation, and whole-buffer evaluation.
*   Add file-based `load` and compile/load flows.
*   Add error routing from runtime back to the REPL and relevant editor range.

### Implementation Order

The recommended execution order is:

1.  Buffer/document model
2.  Rendering/tokenization
3.  Indentation
4.  Menus and file operations
5.  Structural editing
6.  REPL/runtime integration

### First Coding Slice

The first code implementation should aim to deliver a usable editor shell with these minimum features:

*   Open and save a Scheme file.
*   Display buffer text in an editor panel distinct from the REPL.
*   Highlight comments, strings, and delimiters.
*   Match brackets at the cursor.
*   Support `Return` and `Tab` with Scheme-aware indentation.

### Done Criteria Per Milestone

*   **Milestone A done:** a user can create, open, edit, save, and reopen Scheme documents safely.
*   **Milestone B done:** code is visually easier to read, and delimiter mismatches are obvious.
*   **Milestone C done:** common forms indent correctly during normal typing.
*   **Milestone D done:** structural edits preserve balanced code in typical cases.
*   **Milestone E done:** all major features are discoverable from the macOS menu bar.
*   **Milestone F done:** editor commands can drive the live Scheme runtime without manual copy/paste.
