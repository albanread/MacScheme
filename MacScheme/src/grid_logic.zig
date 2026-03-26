const MAX_EDITOR_UNDO: usize = 256;
const std = @import("std");
const ed_buffer = @import("editor/ed_buffer.zig");
const RopeBuffer = ed_buffer.RopeBuffer;

const allocator = std.heap.c_allocator;

extern fn macscheme_eval_async(bytes: [*]const u8, len: usize) void;
extern fn macscheme_get_completions(bytes: [*]const u8, len: usize) void;

pub const EdUniforms = extern struct {
    viewport_width: f32,
    viewport_height: f32,
    cell_width: f32,
    cell_height: f32,
    atlas_width: f32,
    atlas_height: f32,
    time: f32,
    effects_mode: f32,
};

pub const GlyphInstance = extern struct {
    pos_x: f32,
    pos_y: f32,
    uv_x: f32,
    uv_y: f32,
    fg: [4]u8,
    bg: [4]u8,
    flags: u32,
};

pub const EdFrameData = extern struct {
    instances: ?[*]const GlyphInstance,
    instance_count: u32,
    _pad0: u32 = 0,
    uniforms: EdUniforms,
    clear_r: f32,
    clear_g: f32,
    clear_b: f32,
    clear_a: f32,
};

pub const GlyphAtlasInfo = extern struct {
    atlas_width: f32,
    atlas_height: f32,
    cell_width: f32,
    cell_height: f32,
    cols: u32,
    rows: u32,
    first_codepoint: u32,
    glyph_count: u32,
    ascent: f32,
    descent: f32,
    leading: f32,
    _pad: u32,
};

const FLAG_CURSOR: u32 = 1 << 2;
const FLAG_BRACKET_MATCH: u32 = 1 << 3;

const MAX_GRIDS = 2;
const MAX_LINES = 2048;
const MAX_PERSISTED_HISTORY = 500;
const MAX_VISIBLE_COMPLETIONS = 7;

const Line = std.ArrayListUnmanaged(u32);
const LineList = std.ArrayListUnmanaged(Line);
const ByteList = std.ArrayListUnmanaged(u8);
const HistoryList = std.ArrayListUnmanaged([]u8);
const EditorUndoList = std.ArrayListUnmanaged(EditorUndoState);
const CompletionList = std.ArrayListUnmanaged([]u8);

const Key = struct {
    const A: u32 = 0;
    const B: u32 = 11;
    const C: u32 = 8;
    const D: u32 = 2;
    const E: u32 = 14;
    const F: u32 = 3;
    const G: u32 = 5;
    const K: u32 = 40;
    const L: u32 = 37;
    const N: u32 = 45;
    const P: u32 = 35;
    const Q: u32 = 12;
    const SPACE: u32 = 49;
    const TWO: u32 = 19;
    const U: u32 = 32;
    const W: u32 = 13;
    const Y: u32 = 16;
    const Z: u32 = 6;
    const RIGHT_BRACKET: u32 = 30;
    const LEFT: u32 = 123;
    const RIGHT: u32 = 124;
    const DOWN: u32 = 125;
    const UP: u32 = 126;
    const ESCAPE: u32 = 53;
    const BACKSPACE: u32 = 51;
    const DELETE: u32 = 117;
    const ENTER: u32 = 36;
    const KEYPAD_ENTER: u32 = 76;
    const HOME: u32 = 115;
    const END: u32 = 119;
    const TAB: u32 = 48;
};

const Mods = struct {
    const SHIFT: u32 = 1;
    const CONTROL: u32 = 2;
    const ALT: u32 = 4;
    const COMMAND: u32 = 8;
};

const GridTheme = struct {
    clear: [4]f32,
    fg: [4]u8,
    bg: [4]u8,
    selection_bg: [4]u8 = .{ 52, 74, 110, 255 },
    cursor_bg: [4]u8,
    prompt_fg: [4]u8,
    // syntax highlight colors (editor only)
    comment_fg: [4]u8 = .{ 100, 120, 100, 255 },
    string_fg: [4]u8 = .{ 230, 180, 80, 255 },
    keyword_fg: [4]u8 = .{ 90, 200, 255, 255 },
    number_fg: [4]u8 = .{ 180, 255, 140, 255 },
    paren_fg: [4]u8 = .{ 160, 160, 200, 255 },
    bracket_match_bg: [4]u8 = .{ 60, 80, 120, 255 },
    unbalanced_bg: [4]u8 = .{ 120, 48, 48, 255 },
};

const EntryPos = struct {
    row: usize,
    col: usize,
};

const EditorRange = struct {
    start: usize,
    end: usize,
};
const EditorUndoState = struct {
    text: []u8,
    cursor_offset: usize,
    selection_start: ?usize,
    selection_end: ?usize,
    modified: bool,
};

const FlashState = struct {
    pos: EntryPos,
    until_time: f32,
};

const Completeness = enum {
    incomplete,
    complete,
    err,
};

const OpenDelimiter = struct {
    cp: u32,
    row: usize,
    col: usize,
};

const GridState = struct {
    grid_id: usize = 0,
    viewport_width: f32 = 0,
    viewport_height: f32 = 0,
    backing_scale: f32 = 1,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    preferred_col: usize = 0,
    entry_cursor_row: usize = 0,
    entry_cursor_col: usize = 0,
    entry_preferred_col: usize = 0,
    entry_modified: bool = false,
    instances: std.ArrayListUnmanaged(GlyphInstance) = .{},
    lines: LineList = .{},
    prompt: Line = .{},
    entry: LineList = .{},
    history: HistoryList = .{},
    kill_buf: Line = .{},
    mark: ?EntryPos = null,
    completions: CompletionList = .{},
    completion_prefix: ?[]u8 = null,
    completion_request_prefix: ?[]u8 = null,
    completion_menu_visible: bool = false,
    completion_tab_count: usize = 0,
    repeat_count: usize = 0,
    repeat_collecting: bool = false,
    history_cursor: usize = 0,
    history_saved_entry: ?[]u8 = null,
    flash: ?FlashState = null,
    last_ctrl_l_time: f32 = -1000,
    initialized: bool = false,
    editor_buffer: ?RopeBuffer = null,
    editor_cursor_offset: usize = 0,
    editor_file_path: ?[]u8 = null,
    editor_modified: bool = false,
    editor_selection_start: ?usize = null,
    editor_selection_end: ?usize = null,
    editor_undo: EditorUndoList = .{},
    editor_redo: EditorUndoList = .{},

    fn ensureInit(self: *GridState, grid_id: usize) void {
        if (self.initialized) return;
        self.initialized = true;
        self.grid_id = grid_id;

        appendEmptyLine(&self.lines) catch unreachable;

        if (grid_id == 0) {
            self.ensureEditorBuffer();
        } else {
            appendEmptyLine(&self.entry) catch unreachable;
            self.setPromptUtf8("> ");
            self.history_cursor = 0;
        }
    }

    fn deinit(self: *GridState) void {
        freeLineList(&self.lines);
        freeLineList(&self.entry);
        self.prompt.deinit(allocator);
        freeHistoryList(&self.history);
        self.kill_buf.deinit(allocator);
        self.clearCompletions();
        if (self.completion_request_prefix) |prefix| allocator.free(prefix);
        if (self.history_saved_entry) |saved| allocator.free(saved);
        if (self.editor_buffer) |*buffer| {
            buffer.deinit();
            self.editor_buffer = null;
        }
        if (self.editor_file_path) |path| {
            allocator.free(path);
            self.editor_file_path = null;
        }
        freeEditorUndoList(&self.editor_undo);
        freeEditorUndoList(&self.editor_redo);
        self.instances.deinit(allocator);
    }

    fn ensureEditorBuffer(self: *GridState) void {
        if (self.editor_buffer != null) return;

        var buffer = RopeBuffer.init(allocator) catch unreachable;
        buffer.insertUtf8(0, "; MacScheme editor\n(define (square x) (* x x))\n\n") catch {};
        self.editor_cursor_offset = buffer.length();
        self.editor_buffer = buffer;
        self.syncEditorCursorFromOffset(true);
    }

    fn editorBuffer(self: *GridState) *RopeBuffer {
        self.ensureEditorBuffer();
        return &self.editor_buffer.?;
    }

    fn editorBufferConst(self: *const GridState) *const RopeBuffer {
        return &self.editor_buffer.?;
    }

    fn syncEditorCursorFromOffset(self: *GridState, update_preferred: bool) void {
        const line_col = self.editorBuffer().offsetToLineCol(self.editor_cursor_offset);
        self.cursor_row = line_col.line;
        self.cursor_col = line_col.col;
        if (update_preferred) self.preferred_col = self.cursor_col;
    }

    fn clearEditorSelection(self: *GridState) void {
        self.editor_selection_start = null;
        self.editor_selection_end = null;
    }

    fn markEditorEdited(self: *GridState) void {
        self.editor_modified = true;
    }

    fn markEditorSaved(self: *GridState) void {
        self.editor_modified = false;
    }

    fn clearEditorUndoHistory(self: *GridState) void {
        freeEditorUndoList(&self.editor_undo);
        freeEditorUndoList(&self.editor_redo);
    }

    fn captureEditorUndoState(self: *const GridState) ?EditorUndoState {
        const buf = self.editorBufferConst();
        const utf8 = buf.toUtf8() catch return null;
        return .{
            .text = utf8,
            .cursor_offset = self.editor_cursor_offset,
            .selection_start = self.editor_selection_start,
            .selection_end = self.editor_selection_end,
            .modified = self.editor_modified,
        };
    }

    fn pushEditorUndoSnapshot(self: *GridState) void {
        const snapshot = self.captureEditorUndoState() orelse return;
        self.editor_undo.append(allocator, snapshot) catch {
            allocator.free(snapshot.text);
            return;
        };
        trimEditorUndoList(&self.editor_undo, MAX_EDITOR_UNDO);
        freeEditorUndoList(&self.editor_redo);
    }

    fn pushEditorRedoSnapshot(self: *GridState) bool {
        const snapshot = self.captureEditorUndoState() orelse return false;
        self.editor_redo.append(allocator, snapshot) catch {
            allocator.free(snapshot.text);
            return false;
        };
        trimEditorUndoList(&self.editor_redo, MAX_EDITOR_UNDO);
        return true;
    }

    fn restoreEditorUndoState(self: *GridState, state: EditorUndoState) void {
        defer allocator.free(state.text);

        if (self.editor_buffer) |*buffer| {
            buffer.deinit();
            self.editor_buffer = null;
        }

        const buffer = RopeBuffer.initFromUtf8(allocator, state.text) catch RopeBuffer.init(allocator) catch unreachable;
        self.editor_buffer = buffer;

        const total = self.editorBufferConst().length();
        self.editor_cursor_offset = @min(state.cursor_offset, total);
        self.editor_selection_start = if (state.selection_start) |start| @min(start, total) else null;
        self.editor_selection_end = if (state.selection_end) |end| @min(end, total) else null;
        self.editor_modified = state.modified;
        self.syncEditorCursorFromOffset(true);
    }

    fn editorUndo(self: *GridState) void {
        if (self.editor_undo.items.len == 0) return;
        if (!self.pushEditorRedoSnapshot()) return;
        const state = self.editor_undo.pop() orelse return;
        self.restoreEditorUndoState(state);
    }

    fn editorRedo(self: *GridState) void {
        if (self.editor_redo.items.len == 0) return;
        const snapshot = self.captureEditorUndoState() orelse return;
        self.editor_undo.append(allocator, snapshot) catch {
            allocator.free(snapshot.text);
            return;
        };
        trimEditorUndoList(&self.editor_undo, MAX_EDITOR_UNDO);
        const state = self.editor_redo.pop() orelse return;
        self.restoreEditorUndoState(state);
    }

    fn setEditorSelection(self: *GridState, start: usize, end: usize) void {
        self.editor_selection_start = start;
        self.editor_selection_end = end;
    }

    fn editorSelectionRange(self: *const GridState) ?EditorRange {
        const start = self.editor_selection_start orelse return null;
        const end = self.editor_selection_end orelse return null;
        if (start == end) return null;
        return EditorRange{
            .start = @min(start, end),
            .end = @max(start, end),
        };
    }

    fn editorFindEnclosingForm(self: *const GridState, target_start: usize, target_end: usize, skip_exact: bool) ?EditorRange {
        const buf = self.editorBufferConst();
        const total = buf.length();

        var stack = std.ArrayListUnmanaged(usize){};
        defer stack.deinit(allocator);

        var candidate_start: ?usize = null;
        var candidate_end: ?usize = null;
        var in_string = false;
        var escape = false;
        var block_depth: usize = 0;
        var i: usize = 0;
        while (i < total) : (i += 1) {
            const c = buf.charAt(i) orelse break;
            if (block_depth > 0) {
                if (c == '|' and i + 1 < total and buf.charAt(i + 1) == '#') {
                    block_depth -= 1;
                    i += 1;
                } else if (c == '#' and i + 1 < total and buf.charAt(i + 1) == '|') {
                    block_depth += 1;
                    i += 1;
                }
                continue;
            }
            if (in_string) {
                if (escape) {
                    escape = false;
                } else if (c == '\\') {
                    escape = true;
                } else if (c == '"') {
                    in_string = false;
                }
                continue;
            }
            if (c == ';') {
                while (i < total) : (i += 1) {
                    if (buf.charAt(i) == '\n') break;
                }
                continue;
            }
            if (c == '#' and i + 1 < total and buf.charAt(i + 1) == '|') {
                block_depth += 1;
                i += 1;
                continue;
            }
            if (c == '"') {
                in_string = true;
                escape = false;
                continue;
            }
            if (c == '(' or c == '[') {
                stack.append(allocator, i) catch return null;
                continue;
            }
            if (c == ')' or c == ']') {
                if (stack.items.len == 0) continue;
                const open = stack.pop() orelse continue;
                const close = i + 1;
                if (open <= target_start and close >= target_end) {
                    const exact_match = open == target_start and close == target_end;
                    if (!skip_exact or !exact_match) {
                        if (candidate_start == null or open >= candidate_start.?) {
                            candidate_start = open;
                            candidate_end = close;
                        }
                    }
                }
            }
        }

        const start = candidate_start orelse return null;
        const end = candidate_end orelse return null;
        return .{ .start = start, .end = end };
    }

    fn editorSexpEndFrom(self: *const GridState, start: usize) ?usize {
        const buf = self.editorBufferConst();
        const total = buf.length();
        var i = start;
        while (i < total) : (i += 1) {
            const c = buf.charAt(i) orelse break;
            if (!isWhitespace(c)) break;
        }
        if (i >= total) return null;
        const c = buf.charAt(i) orelse return null;
        if (c == '(' or c == '[') {
            if (self.editorFindMatchingBracket(i)) |close_off| return close_off + 1;
            return null;
        }
        if (c == '"') {
            i += 1;
            var escape = false;
            while (i < total) : (i += 1) {
                const sc = buf.charAt(i) orelse break;
                if (escape) {
                    escape = false;
                } else if (sc == '\\') {
                    escape = true;
                } else if (sc == '"') {
                    return i + 1;
                }
            }
            return total;
        }
        const atom_start = i;
        while (i < total) : (i += 1) {
            const ac = buf.charAt(i) orelse break;
            if (tokenTerminator(ac)) break;
        }
        if (i == atom_start) return null;
        return i;
    }

    fn editorSexpStartBefore(self: *const GridState, end: usize) ?usize {
        const buf = self.editorBufferConst();
        if (end == 0) return null;
        var i = end;
        while (i > 0) {
            i -= 1;
            const c = buf.charAt(i) orelse continue;
            if (!isWhitespace(c)) {
                i += 1;
                break;
            }
            if (i == 0) return null;
        }
        if (i == 0) return null;
        i -= 1;
        const c = buf.charAt(i) orelse return null;
        if (c == ')' or c == ']') return self.editorFindMatchingBracket(i);
        if (c == '"') {
            if (i == 0) return @as(usize, 0);
            var j = i;
            while (j > 0) {
                j -= 1;
                const sc = buf.charAt(j) orelse break;
                if (sc == '"') {
                    var k = j;
                    var slashes: usize = 0;
                    while (k > 0) {
                        k -= 1;
                        if (buf.charAt(k) == '\\') slashes += 1 else break;
                    }
                    if (slashes % 2 == 0) return j;
                }
            }
            return @as(usize, 0);
        }
        while (i > 0) {
            i -= 1;
            const ac = buf.charAt(i) orelse break;
            if (tokenTerminator(ac)) return i + 1;
            if (i == 0) break;
        }
        return i;
    }

    fn replaceEditorUtf8(self: *GridState, bytes: []const u8) void {
        if (self.editor_buffer) |*buffer| {
            buffer.deinit();
            self.editor_buffer = null;
        }

        const buffer = RopeBuffer.initFromUtf8(allocator, bytes) catch RopeBuffer.init(allocator) catch unreachable;
        self.editor_cursor_offset = 0;
        self.editor_buffer = buffer;
        self.markEditorSaved();
        self.clearEditorUndoHistory();
        self.clearEditorSelection();
        self.syncEditorCursorFromOffset(true);
    }

    fn insertEditorUtf8(self: *GridState, bytes: []const u8) void {
        self.pushEditorUndoSnapshot();
        const cps = ed_buffer.utf8ToCodepoints(allocator, bytes) catch return;
        defer allocator.free(cps);

        var buffer = self.editorBuffer();
        buffer.insert(self.editor_cursor_offset, cps) catch return;
        self.editor_cursor_offset += cps.len;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn editorLineCount(self: *const GridState) usize {
        return if (self.editor_buffer) |buffer| buffer.lineCount() else 1;
    }

    fn currentEditorLine(self: *GridState) *Line {
        return &self.lines.items[self.cursor_row];
    }

    fn currentEditorLineConst(self: *const GridState) *const Line {
        return &self.lines.items[self.cursor_row];
    }

    fn currentEntryLine(self: *GridState) *Line {
        return &self.entry.items[self.entry_cursor_row];
    }

    fn currentEntryLineConst(self: *const GridState) *const Line {
        return &self.entry.items[self.entry_cursor_row];
    }

    fn appendUtf8LineToEditor(self: *GridState, text: []const u8, move_cursor: bool) void {
        for (text) |c| {
            self.insertEditorCodepoint(@as(u32, c));
        }
        if (!move_cursor) {
            self.cursor_row = self.lines.items.len - 1;
            self.cursor_col = self.lines.items[self.cursor_row].items.len;
            self.preferred_col = self.cursor_col;
        }
    }

    fn insertEditorCodepoint(self: *GridState, cp: u32) void {
        if (cp == '\r') return;
        if (cp == '\n') {
            self.insertEditorNewline();
            return;
        }

        self.pushEditorUndoSnapshot();
        var buffer = self.editorBuffer();
        buffer.insertChar(self.editor_cursor_offset, cp) catch return;
        self.editor_cursor_offset += 1;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    // Typing an opening delimiter: insert the pair and leave cursor between them.
    fn editorTypedOpenDelimiter(self: *GridState, open: u32, close: u32) void {
        self.pushEditorUndoSnapshot();
        var buffer = self.editorBuffer();
        // Insert close at cursor first, then open at the same position (pushing close right).
        buffer.insertChar(self.editor_cursor_offset, close) catch return;
        buffer.insertChar(self.editor_cursor_offset, open) catch {
            buffer.delete(self.editor_cursor_offset, 1) catch {}; // remove close
            return;
        };
        self.editor_cursor_offset += 1; // cursor sits after open, before close
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    // Typing a closing delimiter: skip over it if the char at the cursor already is that closer.
    fn editorTypedCloseOrSkip(self: *GridState, close: u32) void {
        const buf = self.editorBufferConst();
        if (buf.charAt(self.editor_cursor_offset) == close) {
            self.editor_cursor_offset += 1;
            self.syncEditorCursorFromOffset(true);
        } else {
            self.insertEditorCodepoint(close);
        }
    }

    // Typing a double-quote: skip over if already at ", otherwise insert a pair "".
    fn editorTypedQuote(self: *GridState) void {
        const buf = self.editorBufferConst();
        if (buf.charAt(self.editor_cursor_offset) == '"') {
            self.editor_cursor_offset += 1;
            self.syncEditorCursorFromOffset(true);
        } else {
            self.editorTypedOpenDelimiter('"', '"');
        }
    }

    fn insertEditorNewline(self: *GridState) void {
        self.pushEditorUndoSnapshot();
        // Compute indent for the new line before inserting.
        const indent = self.editorComputeIndentAtCursor();
        // Insert the newline character.
        var buffer = self.editorBuffer();
        buffer.insertChar(self.editor_cursor_offset, '\n') catch return;
        self.editor_cursor_offset += 1;
        // Insert indent spaces.
        if (indent > 0) {
            var i: usize = 0;
            while (i < indent) : (i += 1) {
                buffer.insertChar(self.editor_cursor_offset, ' ') catch break;
                self.editor_cursor_offset += 1;
            }
        }
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    // Compute the indent level that a new line after `end` should have.
    // Scans backward through the rope to find the innermost open delimiter
    // and returns the column it was on + 2 (standard Lisp indent).
    fn editorComputeIndentBeforeOffset(self: *const GridState, end: usize) usize {
        const buf = self.editorBufferConst();
        if (end == 0) return 0;

        var stack: std.ArrayListUnmanaged(struct { col: usize, open_cp: u32 }) = .{};
        defer stack.deinit(allocator);

        var in_string = false;
        var escape = false;
        var block_depth: usize = 0;
        var col: usize = 0;

        var i: usize = 0;
        while (i < end) : (i += 1) {
            const cp = buf.charAt(i) orelse break;
            // Track column within current line
            if (cp == '\n') {
                col = 0;
                escape = false;
                continue;
            }
            defer col += 1;

            if (block_depth > 0) {
                if (cp == '#' and i + 1 < end and buf.charAt(i + 1) == '|') {
                    block_depth += 1;
                } else if (cp == '|' and i + 1 < end and buf.charAt(i + 1) == '#') {
                    if (block_depth > 0) block_depth -= 1;
                }
                continue;
            }
            if (in_string) {
                if (escape) escape = false else if (cp == '\\') escape = true else if (cp == '"') in_string = false;
                continue;
            }
            if (cp == ';') {
                // skip to end of line
                while (i + 1 < end) {
                    i += 1;
                    const nc = buf.charAt(i) orelse break;
                    if (nc == '\n') {
                        col = 0;
                        break;
                    }
                    col += 1;
                }
                continue;
            }
            if (cp == '#' and i + 1 < end and buf.charAt(i + 1) == '|') {
                block_depth += 1;
                continue;
            }
            if (cp == '"') {
                in_string = true;
                escape = false;
                continue;
            }
            if (cp == '(' or cp == '[') {
                stack.append(allocator, .{ .col = col, .open_cp = cp }) catch {};
                continue;
            }
            if (cp == ')' or cp == ']') {
                if (stack.items.len > 0) _ = stack.pop();
                continue;
            }
        }

        if (stack.items.len == 0) return 0;
        const top = stack.items[stack.items.len - 1];
        return top.col + 2;
    }

    fn editorComputeIndentAtCursor(self: *GridState) usize {
        return self.editorComputeIndentBeforeOffset(self.editor_cursor_offset);
    }

    fn editorCountLeadingSpaces(self: *const GridState, line_start: usize) usize {
        const buf = self.editorBufferConst();
        var count: usize = 0;
        var i: usize = line_start;
        while (i < buf.length()) : (i += 1) {
            const cp = buf.charAt(i) orelse break;
            if (cp == ' ') {
                count += 1;
            } else if (cp == '\n' or cp != ' ') {
                break;
            }
        }
        return count;
    }

    fn editorAdjustOffsetForIndentChange(offset: *usize, line_start: usize, old_spaces: usize, new_spaces: usize) void {
        if (new_spaces > old_spaces) {
            if (offset.* >= line_start) offset.* += new_spaces - old_spaces;
            return;
        }

        const remove = old_spaces - new_spaces;
        if (offset.* >= line_start + remove)
            offset.* -= remove
        else if (offset.* > line_start)
            offset.* = line_start;
    }

    fn editorIndentLineAtRow(
        self: *GridState,
        row: usize,
        cursor_offset: *usize,
        selection_start: ?*usize,
        selection_end: ?*usize,
    ) bool {
        const line_start = self.editorBufferConst().lineStart(row) orelse return false;
        const existing_spaces = self.editorCountLeadingSpaces(line_start);
        const target = self.editorComputeIndentBeforeOffset(line_start);
        if (target == existing_spaces) return false;

        var buffer = self.editorBuffer();
        if (target > existing_spaces) {
            const extra = target - existing_spaces;
            var i: usize = 0;
            while (i < extra) : (i += 1) {
                buffer.insertChar(line_start, ' ') catch return false;
            }
        } else {
            buffer.delete(line_start, existing_spaces - target) catch return false;
        }

        editorAdjustOffsetForIndentChange(cursor_offset, line_start, existing_spaces, target);
        if (selection_start) |start| editorAdjustOffsetForIndentChange(start, line_start, existing_spaces, target);
        if (selection_end) |end| editorAdjustOffsetForIndentChange(end, line_start, existing_spaces, target);
        return true;
    }

    // Indent the current editor line to the computed indent level (Tab key).
    fn editorIndentCurrentLine(self: *GridState) void {
        self.pushEditorUndoSnapshot();
        if (!self.editorIndentLineAtRow(self.cursor_row, &self.editor_cursor_offset, null, null)) return;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn editorReindentSelectionOrCurrentLine(self: *GridState) void {
        const selection = self.editorSelectionRange() orelse {
            self.editorIndentCurrentLine();
            return;
        };

        self.pushEditorUndoSnapshot();

        const buf = self.editorBufferConst();
        const start_row = buf.offsetToLineCol(selection.start).line;
        var end_offset = selection.end;
        if (end_offset > selection.start and buf.charAt(end_offset - 1) == '\n') {
            end_offset -= 1;
        }
        const end_row = buf.offsetToLineCol(end_offset).line;

        var cursor_offset = self.editor_cursor_offset;
        var selection_start = selection.start;
        var selection_end = selection.end;
        var changed = false;
        var row = start_row;
        while (row <= end_row) : (row += 1) {
            if (self.editorIndentLineAtRow(row, &cursor_offset, &selection_start, &selection_end)) {
                changed = true;
            }
        }
        if (!changed) return;

        self.editor_cursor_offset = cursor_offset;
        self.setEditorSelection(selection_start, selection_end);
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    // Find the offset of the bracket that matches the one at `search_offset`.
    // Returns null if no delimiter there or no match found.
    // `search_offset` is the offset of the delimiter to match (not the cursor).
    fn editorFindMatchingBracket(self: *const GridState, search_offset: usize) ?usize {
        const buf = self.editorBufferConst();
        const cp_at = buf.charAt(search_offset) orelse return null;
        const forward = cp_at == '(' or cp_at == '[';
        const backward = cp_at == ')' or cp_at == ']';
        if (!forward and !backward) return null;

        var depth: i32 = 0;
        var in_string = false;
        var escape = false;
        var block_depth: usize = 0;
        const total = buf.length();

        if (forward) {
            var i = search_offset;
            while (i < total) : (i += 1) {
                const c = buf.charAt(i) orelse break;
                if (block_depth > 0) {
                    if (c == '|' and i + 1 < total and buf.charAt(i + 1) == '#') {
                        block_depth -= 1;
                        i += 1;
                    } else if (c == '#' and i + 1 < total and buf.charAt(i + 1) == '|') {
                        block_depth += 1;
                        i += 1;
                    }
                    continue;
                }
                if (in_string) {
                    if (escape) escape = false else if (c == '\\') escape = true else if (c == '"') in_string = false;
                    continue;
                }
                if (c == ';') {
                    while (i < total) : (i += 1) {
                        if (buf.charAt(i) == '\n') break;
                    }
                    continue;
                }
                if (c == '#' and i + 1 < total and buf.charAt(i + 1) == '|') {
                    block_depth += 1;
                    i += 1;
                    continue;
                }
                if (c == '"') {
                    in_string = true;
                    escape = false;
                    continue;
                }
                if (c == '(' or c == '[') depth += 1 else if (c == ')' or c == ']') {
                    depth -= 1;
                    if (depth == 0) return i;
                }
            }
        } else {
            // scan backward from search_offset-1 to 0
            if (search_offset == 0) return null;
            // rebuild state from start to find the match
            // simple approach: scan full buffer forward, maintain a stack
            var stack = std.ArrayListUnmanaged(usize){};
            defer stack.deinit(allocator);
            var j: usize = 0;
            var in_s = false;
            var esc = false;
            var bcd: usize = 0;
            while (j <= search_offset) : (j += 1) {
                const c = buf.charAt(j) orelse break;
                if (bcd > 0) {
                    if (c == '|' and j + 1 <= search_offset and buf.charAt(j + 1) == '#') {
                        bcd -= 1;
                        j += 1;
                    } else if (c == '#' and j + 1 <= search_offset and buf.charAt(j + 1) == '|') {
                        bcd += 1;
                        j += 1;
                    }
                    continue;
                }
                if (in_s) {
                    if (esc) esc = false else if (c == '\\') esc = true else if (c == '"') in_s = false;
                    continue;
                }
                if (c == ';') {
                    while (j < total) : (j += 1) {
                        if (buf.charAt(j) == '\n') break;
                    }
                    continue;
                }
                if (c == '#' and j + 1 < total and buf.charAt(j + 1) == '|') {
                    bcd += 1;
                    j += 1;
                    continue;
                }
                if (c == '"') {
                    in_s = true;
                    esc = false;
                    continue;
                }
                if (c == '(' or c == '[') {
                    stack.append(allocator, j) catch {};
                } else if (c == ')' or c == ']') {
                    if (j == search_offset) {
                        const open = stack.pop();
                        return open;
                    }
                    if (stack.items.len > 0) _ = stack.pop();
                }
            }
            return null;
        }

        return null;
    }

    // Return the offset of the delimiter the cursor is adjacent to (cursor or cursor-1).
    // Returns null if neither position is a delimiter.
    fn editorBracketUnderCursor(self: *const GridState) ?usize {
        const buf = self.editorBufferConst();
        const off = self.editor_cursor_offset;
        // prefer character at cursor
        if (off < buf.length()) {
            const cp = buf.charAt(off) orelse 0;
            if (cp == '(' or cp == ')' or cp == '[' or cp == ']') return off;
        }
        // then character before cursor
        if (off > 0) {
            const cp = buf.charAt(off - 1) orelse 0;
            if (cp == '(' or cp == ')' or cp == '[' or cp == ']') return off - 1;
        }
        return null;
    }

    fn editorEvalRange(self: *const GridState, start: usize, end: usize) void {
        if (end <= start) return;
        const buf = self.editorBufferConst();
        const slice = buf.slice(start, end) catch return;
        defer allocator.free(slice);
        const utf8 = ed_buffer.codepointsToUtf8(allocator, slice) catch return;
        defer allocator.free(utf8);
        if (utf8.len == 0) return;
        macscheme_eval_async(utf8.ptr, utf8.len);
    }

    fn editorEvalSelection(self: *GridState) bool {
        const range = self.editorSelectionRange() orelse return false;
        self.editorEvalRange(range.start, range.end);
        return true;
    }

    // Send the top-level form that contains the cursor to the REPL.
    fn editorEvalTopLevelForm(self: *GridState) void {
        const buf = self.editorBufferConst();
        const total = buf.length();

        // Scan backward to find the start of the top-level form:
        // look for a '(' or '[' at column 0 (line start) at or before cursor.
        var form_start: usize = 0;
        var found_start = false;
        {
            var line: usize = self.cursor_row;
            while (true) {
                const ls = buf.lineStart(line) orelse 0;
                const cp = buf.charAt(ls) orelse 0;
                if (cp == '(' or cp == '[') {
                    form_start = ls;
                    found_start = true;
                    break;
                }
                if (line == 0) break;
                line -= 1;
            }
        }
        if (!found_start) return;

        // Scan forward from form_start to find the balanced end.
        var depth: i32 = 0;
        var in_string = false;
        var escape = false;
        var block_depth: usize = 0;
        var form_end: usize = form_start;
        var i = form_start;
        while (i < total) : (i += 1) {
            const c = buf.charAt(i) orelse break;
            if (block_depth > 0) {
                if (c == '|' and i + 1 < total and buf.charAt(i + 1) == '#') {
                    block_depth -= 1;
                    i += 1;
                } else if (c == '#' and i + 1 < total and buf.charAt(i + 1) == '|') {
                    block_depth += 1;
                    i += 1;
                }
                continue;
            }
            if (in_string) {
                if (escape) escape = false else if (c == '\\') escape = true else if (c == '"') in_string = false;
                continue;
            }
            if (c == ';') {
                while (i < total) : (i += 1) {
                    if (buf.charAt(i) == '\n') break;
                }
                continue;
            }
            if (c == '#' and i + 1 < total and buf.charAt(i + 1) == '|') {
                block_depth += 1;
                i += 1;
                continue;
            }
            if (c == '"') {
                in_string = true;
                escape = false;
                continue;
            }
            if (c == '(' or c == '[') depth += 1 else if (c == ')' or c == ']') {
                depth -= 1;
                if (depth == 0) {
                    form_end = i + 1;
                    break;
                }
            }
        }
        if (form_end <= form_start) return;

        // Extract and send.
        self.editorEvalRange(form_start, form_end);
    }

    // Send the entire editor buffer to the REPL as a single expression block.
    fn editorEvalBuffer(self: *GridState) void {
        const buf = self.editorBufferConst();
        const utf8 = buf.toUtf8() catch return;
        defer allocator.free(utf8);
        if (utf8.len == 0) return;
        macscheme_eval_async(utf8.ptr, utf8.len);
    }

    fn editorBackspace(self: *GridState) void {
        if (self.editor_cursor_offset == 0) return;
        self.pushEditorUndoSnapshot();
        const buf = self.editorBufferConst();
        const before = buf.charAt(self.editor_cursor_offset - 1) orelse 0;
        const at_cursor = buf.charAt(self.editor_cursor_offset) orelse 0;
        const is_empty_pair = (before == '(' and at_cursor == ')') or
            (before == '[' and at_cursor == ']') or
            (before == '"' and at_cursor == '"');
        var buffer = self.editorBuffer();
        if (is_empty_pair) {
            buffer.delete(self.editor_cursor_offset - 1, 2) catch return;
        } else {
            buffer.delete(self.editor_cursor_offset - 1, 1) catch return;
        }
        self.editor_cursor_offset -= 1;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn editorDeleteForward(self: *GridState) void {
        var buffer = self.editorBuffer();
        if (self.editor_cursor_offset >= buffer.length()) return;

        self.pushEditorUndoSnapshot();
        buffer.delete(self.editor_cursor_offset, 1) catch return;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn editorMoveLeft(self: *GridState) void {
        if (self.editor_cursor_offset == 0) return;
        self.editor_cursor_offset -= 1;
        self.syncEditorCursorFromOffset(true);
    }

    fn editorMoveRight(self: *GridState) void {
        const buffer = self.editorBuffer();
        if (self.editor_cursor_offset >= buffer.length()) return;
        self.editor_cursor_offset += 1;
        self.syncEditorCursorFromOffset(true);
    }

    fn editorMoveUp(self: *GridState) void {
        if (self.cursor_row == 0) return;
        self.editor_cursor_offset = self.editorBuffer().lineColToOffset(self.cursor_row - 1, self.preferred_col);
        self.syncEditorCursorFromOffset(false);
    }

    fn editorMoveDown(self: *GridState) void {
        const buffer = self.editorBuffer();
        if (self.cursor_row + 1 >= buffer.lineCount()) return;
        self.editor_cursor_offset = buffer.lineColToOffset(self.cursor_row + 1, self.preferred_col);
        self.syncEditorCursorFromOffset(false);
    }

    fn editorMoveHome(self: *GridState) void {
        self.editor_cursor_offset = self.editorBuffer().lineColToOffset(self.cursor_row, 0);
        self.syncEditorCursorFromOffset(true);
    }

    fn editorMoveEnd(self: *GridState) void {
        const buffer = self.editorBuffer();
        const range = buffer.lineRange(self.cursor_row) orelse {
            self.editor_cursor_offset = buffer.length();
            self.syncEditorCursorFromOffset(true);
            return;
        };
        self.editor_cursor_offset = range.end;
        self.syncEditorCursorFromOffset(true);
    }

    // Move forward past the next complete S-expression (list or atom).
    // Skips leading whitespace, then:
    //   - on '(' or '[': jumps to just after the matching close.
    //   - on '"': jumps to just after the closing quote.
    //   - on anything else: jumps to the end of the atom.
    fn editorMoveSexpForward(self: *GridState) void {
        const buf = self.editorBufferConst();
        const total = buf.length();
        var i = self.editor_cursor_offset;
        // Skip leading whitespace.
        while (i < total) : (i += 1) {
            const c = buf.charAt(i) orelse break;
            if (!isWhitespace(c)) break;
        }
        if (i >= total) return;
        const c = buf.charAt(i) orelse return;
        if (c == '(' or c == '[') {
            // Use the existing balanced-bracket scanner.
            if (self.editorFindMatchingBracket(i)) |close_off| {
                self.editor_cursor_offset = close_off + 1;
            } else {
                self.editor_cursor_offset = total;
            }
        } else if (c == '"') {
            // Walk forward to the closing quote, honouring backslash escapes.
            i += 1;
            var escape = false;
            while (i < total) : (i += 1) {
                const sc = buf.charAt(i) orelse break;
                if (escape) {
                    escape = false;
                } else if (sc == '\\') {
                    escape = true;
                } else if (sc == '"') {
                    i += 1;
                    break;
                }
            }
            self.editor_cursor_offset = i;
        } else {
            // Atom: advance until the next token terminator.
            while (i < total) : (i += 1) {
                const ac = buf.charAt(i) orelse break;
                if (tokenTerminator(ac)) break;
            }
            self.editor_cursor_offset = i;
        }
        self.syncEditorCursorFromOffset(true);
    }

    // Move backward past the previous complete S-expression (list or atom).
    // Skips trailing whitespace, then:
    //   - on ')' or ']': jumps to the matching open.
    //   - on '"': scans backward for the opening quote.
    //   - on anything else: jumps to the start of the atom.
    fn editorMoveSexpBackward(self: *GridState) void {
        const buf = self.editorBufferConst();
        if (self.editor_cursor_offset == 0) return;
        var i = self.editor_cursor_offset;
        // Skip trailing whitespace backward.
        while (i > 0) {
            i -= 1;
            const c = buf.charAt(i) orelse continue;
            if (!isWhitespace(c)) {
                i += 1; // restore: i is now one past the non-whitespace char
                break;
            }
            if (i == 0) return; // only whitespace before cursor
        }
        if (i == 0) return;
        i -= 1; // step onto the last non-whitespace char
        const c = buf.charAt(i) orelse return;
        if (c == ')' or c == ']') {
            if (self.editorFindMatchingBracket(i)) |open_off| {
                self.editor_cursor_offset = open_off;
            } else {
                self.editor_cursor_offset = 0;
            }
        } else if (c == '"') {
            // Scan backward for the unescaped opening quote.
            // We walk char by char; escapes are tricky going backward, so we
            // scan forward from each candidate to verify. For typical code
            // lengths this is fine.
            if (i == 0) {
                self.editor_cursor_offset = 0;
            } else {
                var j = i; // j points to the closing quote
                // Walk backward looking for a '"' that is not preceded by '\'
                var found: usize = 0;
                while (j > 0) {
                    j -= 1;
                    const sc = buf.charAt(j) orelse break;
                    if (sc == '"') {
                        // Count preceding backslashes.
                        var k = j;
                        var slashes: usize = 0;
                        while (k > 0) {
                            k -= 1;
                            if (buf.charAt(k) == '\\') slashes += 1 else break;
                        }
                        if (slashes % 2 == 0) {
                            found = j;
                            break;
                        }
                    }
                }
                self.editor_cursor_offset = found;
            }
        } else {
            // Atom: scan backward to the start.
            while (i > 0) {
                i -= 1;
                const ac = buf.charAt(i) orelse break;
                if (tokenTerminator(ac)) {
                    i += 1;
                    break;
                }
                if (i == 0) break; // landed at the very first char
            }
            self.editor_cursor_offset = i;
        }
        self.syncEditorCursorFromOffset(true);
    }

    fn editorSelectEnclosingForm(self: *GridState) void {
        const current = self.editorSelectionRange();
        const target_start = if (current) |range| range.start else self.editor_cursor_offset;
        const target_end = if (current) |range| range.end else self.editor_cursor_offset;
        if (self.editorFindEnclosingForm(target_start, target_end, true)) |range| {
            self.setEditorSelection(range.start, range.end);
            self.editor_cursor_offset = range.end;
            self.syncEditorCursorFromOffset(true);
        }
    }

    fn editorWrapSelectionInParentheses(self: *GridState) bool {
        const range = self.editorSelectionRange() orelse return false;
        self.pushEditorUndoSnapshot();
        var buffer = self.editorBuffer();

        buffer.insertChar(range.end, ')') catch return false;
        buffer.insertChar(range.start, '(') catch {
            buffer.delete(range.end, 1) catch {};
            return false;
        };

        self.setEditorSelection(range.start, range.end + 2);
        self.editor_cursor_offset = range.end + 2;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
        return true;
    }

    fn editorSlurpForward(self: *GridState) void {
        const target = self.editorSelectionRange();
        const target_start = if (target) |range| range.start else self.editor_cursor_offset;
        const target_end = if (target) |range| range.end else self.editor_cursor_offset;
        const enclosing = self.editorFindEnclosingForm(target_start, target_end, false) orelse return;
        const next_end = self.editorSexpEndFrom(enclosing.end) orelse return;
        if (next_end <= enclosing.end) return;

        self.pushEditorUndoSnapshot();
        var buffer = self.editorBuffer();
        const close_cp = buffer.charAt(enclosing.end - 1) orelse return;
        buffer.delete(enclosing.end - 1, 1) catch return;
        buffer.insertChar(next_end - 1, close_cp) catch return;
        self.clearEditorSelection();
        self.editor_cursor_offset = next_end;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn editorBarfForward(self: *GridState) void {
        const target = self.editorSelectionRange();
        const target_start = if (target) |range| range.start else self.editor_cursor_offset;
        const target_end = if (target) |range| range.end else self.editor_cursor_offset;
        const enclosing = self.editorFindEnclosingForm(target_start, target_end, false) orelse return;
        const last_start = self.editorSexpStartBefore(enclosing.end - 1) orelse return;
        if (last_start <= enclosing.start + 1) return;

        const buf = self.editorBufferConst();
        var insert_at = last_start;
        while (insert_at > enclosing.start + 1) {
            const prev = buf.charAt(insert_at - 1) orelse break;
            if (!isWhitespace(prev)) break;
            insert_at -= 1;
        }

        self.pushEditorUndoSnapshot();
        var buffer = self.editorBuffer();
        const close_cp = buffer.charAt(enclosing.end - 1) orelse return;
        buffer.delete(enclosing.end - 1, 1) catch return;
        buffer.insertChar(insert_at, close_cp) catch return;
        self.clearEditorSelection();
        self.editor_cursor_offset = insert_at + 1;
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn editorSpliceEnclosingForm(self: *GridState) void {
        const target = self.editorSelectionRange();
        const target_start = if (target) |range| range.start else self.editor_cursor_offset;
        const target_end = if (target) |range| range.end else self.editor_cursor_offset;
        const enclosing = self.editorFindEnclosingForm(target_start, target_end, false) orelse return;
        if (enclosing.end <= enclosing.start + 1) return;

        self.pushEditorUndoSnapshot();
        var buffer = self.editorBuffer();
        buffer.delete(enclosing.end - 1, 1) catch return;
        buffer.delete(enclosing.start, 1) catch return;

        const new_start = enclosing.start;
        const new_end = enclosing.end - 2;
        if (new_end > new_start) {
            self.setEditorSelection(new_start, new_end);
            self.editor_cursor_offset = new_end;
        } else {
            self.clearEditorSelection();
            self.editor_cursor_offset = new_start;
        }
        self.markEditorEdited();
        self.syncEditorCursorFromOffset(true);
    }

    fn setPromptUtf8(self: *GridState, text: []const u8) void {
        self.prompt.clearRetainingCapacity();
        appendUtf8ToLine(&self.prompt, text) catch return;
    }

    fn clearSavedEntry(self: *GridState) void {
        if (self.history_saved_entry) |saved| allocator.free(saved);
        self.history_saved_entry = null;
    }

    fn markEntryEdited(self: *GridState) void {
        self.entry_modified = true;
        self.resetCompletionInteraction();
        if (self.history_cursor == self.history.items.len) {
            self.clearSavedEntry();
        }
    }

    fn entryIsWhitespaceOnly(self: *const GridState) bool {
        for (self.entry.items) |line| {
            for (line.items) |cp| {
                if (!isWhitespace(cp)) return false;
            }
        }
        return true;
    }

    fn entryInsertCodepoint(self: *GridState, cp: u32) void {
        if (cp == '\r') return;
        if (cp == '\n') {
            self.entryInsertNewline();
            return;
        }

        var line = self.currentEntryLine();
        line.insert(allocator, self.entry_cursor_col, cp) catch return;
        self.entry_cursor_col += 1;
        self.entry_preferred_col = self.entry_cursor_col;
        self.markEntryEdited();
    }

    fn entryInsertNewline(self: *GridState) void {
        if (self.entry.items.len >= MAX_LINES) return;

        var tail: Line = .{};
        var line = self.currentEntryLine();
        if (self.entry_cursor_col < line.items.len) {
            tail.appendSlice(allocator, line.items[self.entry_cursor_col..]) catch return;
            line.shrinkRetainingCapacity(self.entry_cursor_col);
        }

        self.entry.insert(allocator, self.entry_cursor_row + 1, tail) catch {
            tail.deinit(allocator);
            return;
        };

        self.entry_cursor_row += 1;
        self.entry_cursor_col = 0;
        self.entry_preferred_col = 0;
        self.markEntryEdited();
    }

    fn entryInsertIndent(self: *GridState, indent: usize) void {
        var i: usize = 0;
        while (i < indent) : (i += 1) {
            self.entryInsertCodepoint(' ');
        }
    }

    fn entryBackspace(self: *GridState) void {
        if (self.entry_cursor_col > 0) {
            var line = self.currentEntryLine();
            _ = line.orderedRemove(self.entry_cursor_col - 1);
            self.entry_cursor_col -= 1;
            self.entry_preferred_col = self.entry_cursor_col;
            self.markEntryEdited();
            return;
        }
        if (self.entry_cursor_row == 0) return;

        const old_row = self.entry_cursor_row;
        const new_col = self.entry.items[old_row - 1].items.len;
        self.entry.items[old_row - 1].appendSlice(allocator, self.entry.items[old_row].items) catch return;
        self.entry.items[old_row].deinit(allocator);
        _ = self.entry.orderedRemove(old_row);
        self.entry_cursor_row -= 1;
        self.entry_cursor_col = new_col;
        self.entry_preferred_col = new_col;
        self.markEntryEdited();
    }

    fn entryDeleteForward(self: *GridState) void {
        var line = self.currentEntryLine();
        if (self.entry_cursor_col < line.items.len) {
            _ = line.orderedRemove(self.entry_cursor_col);
            self.markEntryEdited();
            return;
        }
        if (self.entry_cursor_row + 1 >= self.entry.items.len) return;

        line.appendSlice(allocator, self.entry.items[self.entry_cursor_row + 1].items) catch return;
        self.entry.items[self.entry_cursor_row + 1].deinit(allocator);
        _ = self.entry.orderedRemove(self.entry_cursor_row + 1);
        self.markEntryEdited();
    }

    fn entryMoveLeft(self: *GridState) void {
        if (self.entry_cursor_col > 0) {
            self.entry_cursor_col -= 1;
        } else if (self.entry_cursor_row > 0) {
            self.entry_cursor_row -= 1;
            self.entry_cursor_col = self.entry.items[self.entry_cursor_row].items.len;
        }
        self.entry_preferred_col = self.entry_cursor_col;
    }

    fn entryMoveRight(self: *GridState) void {
        const line_len = self.currentEntryLine().items.len;
        if (self.entry_cursor_col < line_len) {
            self.entry_cursor_col += 1;
        } else if (self.entry_cursor_row + 1 < self.entry.items.len) {
            self.entry_cursor_row += 1;
            self.entry_cursor_col = 0;
        }
        self.entry_preferred_col = self.entry_cursor_col;
    }

    fn canNavigateHistory(self: *const GridState) bool {
        return !self.entry_modified or self.entryIsWhitespaceOnly();
    }

    fn entryMoveUp(self: *GridState) void {
        if (self.entry_cursor_row > 0) {
            self.entry_cursor_row -= 1;
            self.entry_cursor_col = @min(self.entry_preferred_col, self.entry.items[self.entry_cursor_row].items.len);
            return;
        }
        if (self.canNavigateHistory()) self.historyUp();
    }

    fn entryMoveDown(self: *GridState) void {
        if (self.entry_cursor_row + 1 < self.entry.items.len) {
            self.entry_cursor_row += 1;
            self.entry_cursor_col = @min(self.entry_preferred_col, self.entry.items[self.entry_cursor_row].items.len);
            return;
        }
        if (self.canNavigateHistory()) self.historyDown();
    }

    fn entryMoveHome(self: *GridState) void {
        self.entry_cursor_col = 0;
        self.entry_preferred_col = 0;
    }

    fn entryMoveEnd(self: *GridState) void {
        self.entry_cursor_col = self.currentEntryLine().items.len;
        self.entry_preferred_col = self.entry_cursor_col;
    }

    fn clearEntry(self: *GridState) void {
        freeLineList(&self.entry);
        appendEmptyLine(&self.entry) catch unreachable;
        self.entry_cursor_row = 0;
        self.entry_cursor_col = 0;
        self.entry_preferred_col = 0;
        self.entry_modified = false;
        self.mark = null;
        self.flash = null;
        self.resetCompletionInteraction();
    }

    fn clearOutput(self: *GridState) void {
        freeLineList(&self.lines);
        appendEmptyLine(&self.lines) catch unreachable;
    }

    fn replaceEntryFromUtf8(self: *GridState, text: []const u8) void {
        freeLineList(&self.entry);
        appendEmptyLine(&self.entry) catch unreachable;
        decodeUtf8IntoLineList(&self.entry, text) catch return;
        if (self.entry.items.len == 0) {
            appendEmptyLine(&self.entry) catch unreachable;
        }
        self.entry_cursor_row = self.entry.items.len - 1;
        self.entry_cursor_col = self.entry.items[self.entry_cursor_row].items.len;
        self.entry_preferred_col = self.entry_cursor_col;
        self.entry_modified = false;
        self.mark = null;
        self.flash = null;
        self.resetCompletionInteraction();
    }

    fn snapshotEntryUtf8(self: *const GridState) ?[]u8 {
        return lineListToUtf8(allocator, &self.entry) catch null;
    }

    fn resetHistoryCursor(self: *GridState) void {
        self.history_cursor = self.history.items.len;
        self.clearSavedEntry();
    }

    fn pushHistory(self: *GridState, text: []const u8) void {
        if (text.len == 0) {
            self.history_cursor = self.history.items.len;
            return;
        }
        if (self.history.items.len > 0 and std.mem.eql(u8, self.history.items[self.history.items.len - 1], text)) {
            self.history_cursor = self.history.items.len;
            return;
        }

        const copy = allocator.dupe(u8, text) catch return;
        self.history.append(allocator, copy) catch {
            allocator.free(copy);
            return;
        };
        self.history_cursor = self.history.items.len;
    }

    fn historyUp(self: *GridState) void {
        if (self.history.items.len == 0 or self.history_cursor == 0) return;
        if (self.history_cursor == self.history.items.len and self.history_saved_entry == null) {
            self.history_saved_entry = self.snapshotEntryUtf8();
        }
        self.history_cursor -= 1;
        self.replaceEntryFromUtf8(self.history.items[self.history_cursor]);
    }

    fn historyDown(self: *GridState) void {
        if (self.history.items.len == 0 or self.history_cursor >= self.history.items.len) return;
        self.history_cursor += 1;
        if (self.history_cursor == self.history.items.len) {
            if (self.history_saved_entry) |saved| {
                self.replaceEntryFromUtf8(saved);
            } else {
                self.clearEntry();
            }
            self.clearSavedEntry();
            self.history_cursor = self.history.items.len;
            return;
        }
        self.replaceEntryFromUtf8(self.history.items[self.history_cursor]);
    }

    fn historyPrefixSearch(self: *GridState, forward: bool) void {
        if (self.history.items.len == 0) return;

        const prefix = self.snapshotEntryUtf8() orelse return;
        defer allocator.free(prefix);

        if (self.history_cursor == self.history.items.len and self.history_saved_entry == null) {
            self.history_saved_entry = allocator.dupe(u8, prefix) catch null;
        }

        var index: isize = if (forward)
            @as(isize, @intCast(self.history_cursor)) + 1
        else if (self.history_cursor == self.history.items.len)
            @as(isize, @intCast(self.history.items.len)) - 1
        else
            @as(isize, @intCast(self.history_cursor)) - 1;

        while (index >= 0 and index < @as(isize, @intCast(self.history.items.len))) : (index += if (forward) 1 else -1) {
            const candidate = self.history.items[@as(usize, @intCast(index))];
            if (std.mem.startsWith(u8, candidate, prefix)) {
                self.history_cursor = @as(usize, @intCast(index));
                self.replaceEntryFromUtf8(candidate);
                return;
            }
        }
    }

    fn setFlash(self: *GridState, pos: EntryPos) void {
        self.flash = .{ .pos = pos, .until_time = g_time + 0.1 };
    }

    fn activeFlashPos(self: *GridState) ?EntryPos {
        if (self.flash) |flash| {
            if (g_time <= flash.until_time) return flash.pos;
            self.flash = null;
        }
        return null;
    }

    fn moveCursorTo(self: *GridState, pos: EntryPos) void {
        if (pos.row >= self.entry.items.len) return;
        self.entry_cursor_row = pos.row;
        self.entry_cursor_col = @min(pos.col, self.entry.items[pos.row].items.len);
        self.entry_preferred_col = self.entry_cursor_col;
    }

    fn setMark(self: *GridState) void {
        self.mark = .{ .row = self.entry_cursor_row, .col = self.entry_cursor_col };
    }

    fn clearCompletionEntries(self: *GridState) void {
        for (self.completions.items) |item| allocator.free(item);
        self.completions.clearRetainingCapacity();
        if (self.completion_prefix) |prefix| allocator.free(prefix);
        self.completion_prefix = null;
    }

    fn clearCompletions(self: *GridState) void {
        self.clearCompletionEntries();
        self.completions.deinit(allocator);
        self.completions = .{};
        self.completion_menu_visible = false;
        self.completion_tab_count = 0;
    }

    fn resetCompletionInteraction(self: *GridState) void {
        self.completion_menu_visible = false;
        self.completion_tab_count = 0;
    }

    fn setCompletionRequestPrefix(self: *GridState, prefix: []const u8) void {
        if (self.completion_request_prefix) |old| allocator.free(old);
        self.completion_request_prefix = allocator.dupe(u8, prefix) catch null;
    }

    fn setCompletions(self: *GridState, prefix: []const u8, words: []const []const u8) void {
        self.clearCompletionEntries();
        self.completion_prefix = allocator.dupe(u8, prefix) catch null;
        for (words) |word| {
            const duped = allocator.dupe(u8, word) catch continue;
            self.completions.append(allocator, duped) catch allocator.free(duped);
        }
    }

    fn completionPrefixMatches(self: *const GridState, prefix: []const u8) bool {
        return if (self.completion_prefix) |stored| std.mem.eql(u8, stored, prefix) else false;
    }

    fn appendUtf8IntoEntry(self: *GridState, bytes: []const u8) void {
        var i: usize = 0;
        while (i < bytes.len) {
            const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
                i += 1;
                continue;
            };
            if (i + len > bytes.len) break;
            const cp = std.unicode.utf8Decode(bytes[i .. i + len]) catch {
                i += len;
                continue;
            };
            if (cp == '\n') {
                self.entryInsertNewline();
            } else if (cp != '\r') {
                self.entryInsertCodepoint(cp);
            }
            i += len;
        }
    }

    fn extractCompletionPrefix(self: *const GridState) ?[]u8 {
        var start = EntryPos{ .row = self.entry_cursor_row, .col = self.entry_cursor_col };
        while (!(start.row == 0 and start.col == 0)) {
            const prev = entryBeforePosition(self, start.row, start.col);
            const cp = codepointAt(self, prev) orelse break;
            if (!isWordCodepoint(cp)) break;
            start = prev;
        }
        if (entryPosCompare(start, .{ .row = self.entry_cursor_row, .col = self.entry_cursor_col }) == 0) return null;
        return entryRangeToUtf8(self, start, .{ .row = self.entry_cursor_row, .col = self.entry_cursor_col });
    }

    fn applyCompletionResults(self: *GridState, prefix: []const u8) bool {
        if (!self.completionPrefixMatches(prefix) or self.completions.items.len == 0) return false;
        const best = longestCommonCompletionPrefix(self.completions.items);
        if (best.len <= prefix.len) return false;
        self.appendUtf8IntoEntry(best[prefix.len..]);
        return true;
    }

    fn handleCompletionTab(self: *GridState) void {
        const prefix = self.extractCompletionPrefix() orelse return;
        defer allocator.free(prefix);

        if (self.completionPrefixMatches(prefix)) {
            self.completion_tab_count += 1;
            if (self.completion_tab_count >= 2 and self.completions.items.len > 1) {
                self.completion_menu_visible = true;
                return;
            }
            if (self.applyCompletionResults(prefix)) {
                self.completion_tab_count = 0;
                self.completion_menu_visible = false;
            }
            return;
        }

        self.resetCompletionInteraction();
        self.completion_tab_count = 1;
        self.setCompletionRequestPrefix(prefix);
        macscheme_get_completions(prefix.ptr, prefix.len);
    }

    fn replaceKillBuffer(self: *GridState, text: []const u32) void {
        self.kill_buf.clearRetainingCapacity();
        self.kill_buf.appendSlice(allocator, text) catch {};
    }

    fn deleteRange(self: *GridState, a: EntryPos, b: EntryPos, capture_kill: bool) bool {
        var start = a;
        var end = b;
        if (entryPosCompare(start, end) > 0) {
            const tmp = start;
            start = end;
            end = tmp;
        }
        if (entryPosCompare(start, end) == 0) return false;

        var killed: Line = .{};
        defer if (!capture_kill) killed.deinit(allocator);

        if (start.row == end.row) {
            const line = &self.entry.items[start.row];
            killed.appendSlice(allocator, line.items[start.col..end.col]) catch {};

            var rebuilt: Line = .{};
            rebuilt.appendSlice(allocator, line.items[0..start.col]) catch {
                rebuilt.deinit(allocator);
                return false;
            };
            rebuilt.appendSlice(allocator, line.items[end.col..]) catch {
                rebuilt.deinit(allocator);
                return false;
            };
            line.deinit(allocator);
            self.entry.items[start.row] = rebuilt;
        } else {
            const start_line = &self.entry.items[start.row];
            const end_line = &self.entry.items[end.row];

            killed.appendSlice(allocator, start_line.items[start.col..]) catch {};
            var row = start.row + 1;
            while (row < end.row) : (row += 1) {
                killed.append(allocator, '\n') catch {};
                killed.appendSlice(allocator, self.entry.items[row].items) catch {};
            }
            killed.append(allocator, '\n') catch {};
            killed.appendSlice(allocator, end_line.items[0..end.col]) catch {};

            var rebuilt: Line = .{};
            rebuilt.appendSlice(allocator, start_line.items[0..start.col]) catch {
                rebuilt.deinit(allocator);
                return false;
            };
            rebuilt.appendSlice(allocator, end_line.items[end.col..]) catch {
                rebuilt.deinit(allocator);
                return false;
            };

            start_line.deinit(allocator);
            self.entry.items[start.row] = rebuilt;

            row = end.row;
            while (row > start.row) : (row -= 1) {
                self.entry.items[row].deinit(allocator);
                _ = self.entry.orderedRemove(row);
            }
        }

        if (capture_kill) self.replaceKillBuffer(killed.items);
        self.moveCursorTo(start);
        self.mark = null;
        self.markEntryEdited();
        return true;
    }

    fn killToEndOfLine(self: *GridState) void {
        const line_len = self.currentEntryLine().items.len;
        const start = EntryPos{ .row = self.entry_cursor_row, .col = self.entry_cursor_col };
        if (self.entry_cursor_col < line_len) {
            _ = self.deleteRange(start, .{ .row = self.entry_cursor_row, .col = line_len }, true);
            return;
        }
        if (self.entry_cursor_row + 1 >= self.entry.items.len) {
            self.kill_buf.clearRetainingCapacity();
            return;
        }
        _ = self.deleteRange(start, .{ .row = self.entry_cursor_row + 1, .col = 0 }, true);
    }

    fn killCurrentLine(self: *GridState) void {
        const row = self.entry_cursor_row;
        const line_len = self.entry.items[row].items.len;
        _ = self.deleteRange(.{ .row = row, .col = 0 }, .{ .row = row, .col = line_len }, true);
    }

    fn killMarkedRegion(self: *GridState) void {
        const mark = self.mark orelse return;
        _ = self.deleteRange(mark, .{ .row = self.entry_cursor_row, .col = self.entry_cursor_col }, true);
    }

    fn yankKillBuffer(self: *GridState) void {
        if (self.kill_buf.items.len == 0) return;
        for (self.kill_buf.items) |cp| {
            if (cp == '\n') {
                self.entryInsertNewline();
            } else {
                self.entryInsertCodepoint(cp);
            }
        }
    }

    fn moveWordLeft(self: *GridState) void {
        var pos = EntryPos{ .row = self.entry_cursor_row, .col = self.entry_cursor_col };
        if (pos.row == 0 and pos.col == 0) return;

        pos = entryBeforePosition(self, pos.row, pos.col);
        while (true) {
            const cp = codepointAt(self, pos) orelse break;
            if (isWordCodepoint(cp)) break;
            if (pos.row == 0 and pos.col == 0) {
                self.moveCursorTo(pos);
                return;
            }
            pos = entryBeforePosition(self, pos.row, pos.col);
        }

        while (!(pos.row == 0 and pos.col == 0)) {
            const prev = entryBeforePosition(self, pos.row, pos.col);
            const prev_cp = codepointAt(self, prev) orelse break;
            if (!isWordCodepoint(prev_cp)) break;
            pos = prev;
        }

        self.moveCursorTo(pos);
    }

    fn moveWordRight(self: *GridState) void {
        var pos = EntryPos{ .row = self.entry_cursor_row, .col = self.entry_cursor_col };
        while (true) {
            const cp = codepointAt(self, pos) orelse {
                if (!advanceAnyPosition(self, &pos)) return;
                continue;
            };
            if (isWordCodepoint(cp)) break;
            if (!advanceAnyPosition(self, &pos)) return;
        }

        while (true) {
            const cp = codepointAt(self, pos) orelse break;
            if (!isWordCodepoint(cp)) break;
            if (!advanceAnyPosition(self, &pos)) {
                const last_row = self.entry.items.len - 1;
                self.moveCursorTo(.{ .row = last_row, .col = self.entry.items[last_row].items.len });
                return;
            }
        }

        self.moveCursorTo(pos);
    }

    fn flashMatchingDelimiterNearCursor(self: *GridState, move_cursor: bool) void {
        const target = matchingTargetNearCursor(self) orelse return;
        const match = findMatchingDelimiter(self, target) orelse return;
        if (move_cursor) {
            self.moveCursorTo(match);
        } else {
            self.setFlash(match);
        }
    }

    fn handleCtrlL(self: *GridState) void {
        if (g_time - self.last_ctrl_l_time <= 0.35) {
            self.clearOutput();
        }
        self.last_ctrl_l_time = g_time;
    }

    fn beginRepeatPrefix(self: *GridState) void {
        self.repeat_collecting = true;
        self.repeat_count = 0;
    }

    fn appendRepeatDigit(self: *GridState, digit: u32) bool {
        if (!self.repeat_collecting) return false;
        if (digit < '0' or digit > '9') return false;
        self.repeat_count = self.repeat_count * 10 + @as(usize, digit - '0');
        return true;
    }

    fn consumeRepeatCount(self: *GridState) usize {
        if (!self.repeat_collecting) return 1;
        self.repeat_collecting = false;
        const count = if (self.repeat_count == 0) 4 else self.repeat_count;
        self.repeat_count = 0;
        return count;
    }

    fn cancelRepeatPrefix(self: *GridState) void {
        self.repeat_collecting = false;
        self.repeat_count = 0;
    }

    fn deleteSexpForward(self: *GridState) void {
        const start = skipEntryWhitespaceForward(self, .{ .row = self.entry_cursor_row, .col = self.entry_cursor_col });
        const end = findForwardSexpEnd(self, start) orelse return;
        _ = self.deleteRange(start, end, true);
    }

    fn deleteSexpBackward(self: *GridState) void {
        const end = skipEntryWhitespaceBackward(self, .{ .row = self.entry_cursor_row, .col = self.entry_cursor_col });
        const start = findBackwardSexpStart(self, end) orelse return;
        _ = self.deleteRange(start, end, true);
    }

    fn ensureOutputWritableLine(self: *GridState) *Line {
        if (self.lines.items.len == 0) {
            appendEmptyLine(&self.lines) catch unreachable;
        }
        return &self.lines.items[self.lines.items.len - 1];
    }

    fn promptBaseRow(self: *const GridState) usize {
        if (self.lines.items.len == 0) return 0;
        const last = &self.lines.items[self.lines.items.len - 1];
        if (last.items.len == 0) return self.lines.items.len - 1;
        return self.lines.items.len;
    }

    fn appendOutputCodepoint(self: *GridState, cp: u32) void {
        if (cp == '\r') return;
        if (cp == '\n') {
            if (self.lines.items.len >= MAX_LINES) return;
            appendEmptyLine(&self.lines) catch return;
            return;
        }
        var line = self.ensureOutputWritableLine();
        line.append(allocator, cp) catch {};
    }

    fn appendOutputUtf8(self: *GridState, bytes: []const u8) void {
        var i: usize = 0;
        while (i < bytes.len) {
            const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
                i += 1;
                continue;
            };
            if (i + len > bytes.len) break;
            const cp = std.unicode.utf8Decode(bytes[i .. i + len]) catch {
                i += len;
                continue;
            };
            self.appendOutputCodepoint(cp);
            i += len;
        }
    }

    fn appendPromptAndEntryToOutput(self: *GridState) void {
        const base_row = self.promptBaseRow();
        if (base_row == self.lines.items.len) {
            appendEmptyLine(&self.lines) catch return;
        }

        var first_line = &self.lines.items[base_row];
        first_line.appendSlice(allocator, self.prompt.items) catch return;
        first_line.appendSlice(allocator, self.entry.items[0].items) catch return;

        var row: usize = 1;
        while (row < self.entry.items.len) : (row += 1) {
            appendEmptyLine(&self.lines) catch return;
            self.lines.items[self.lines.items.len - 1].appendSlice(allocator, self.entry.items[row].items) catch return;
        }

        if (self.lines.items.len == 0 or self.lines.items[self.lines.items.len - 1].items.len != 0) {
            appendEmptyLine(&self.lines) catch {};
        }
    }

    fn reindentCurrentEntryLine(self: *GridState) void {
        const indent = computeIndentForRow(self, self.entry_cursor_row);
        self.setEntryLineIndent(self.entry_cursor_row, indent);
    }

    fn reindentAllEntryLines(self: *GridState) void {
        var row: usize = 1;
        while (row < self.entry.items.len) : (row += 1) {
            const indent = computeIndentForRow(self, row);
            self.setEntryLineIndent(row, indent);
        }
    }

    fn setEntryLineIndent(self: *GridState, row: usize, indent: usize) void {
        if (row >= self.entry.items.len) return;
        var line = &self.entry.items[row];
        var old_indent: usize = 0;
        while (old_indent < line.items.len and (line.items[old_indent] == ' ' or line.items[old_indent] == '\t')) : (old_indent += 1) {}
        if (old_indent == indent and !containsTabs(line.items[0..old_indent])) return;

        var rebuilt: Line = .{};
        var i: usize = 0;
        while (i < indent) : (i += 1) rebuilt.append(allocator, ' ') catch {
            rebuilt.deinit(allocator);
            return;
        };
        rebuilt.appendSlice(allocator, line.items[old_indent..]) catch {
            rebuilt.deinit(allocator);
            return;
        };

        line.deinit(allocator);
        line.* = rebuilt;

        if (self.entry_cursor_row == row) {
            if (self.entry_cursor_col <= old_indent) {
                self.entry_cursor_col = indent;
            } else {
                self.entry_cursor_col = indent + (self.entry_cursor_col - old_indent);
            }
            if (self.entry_cursor_col > line.items.len) self.entry_cursor_col = line.items.len;
            self.entry_preferred_col = self.entry_cursor_col;
        }
        self.markEntryEdited();
    }
};

var g_time: f32 = 0;
var g_atlas: GlyphAtlasInfo = .{
    .atlas_width = 0,
    .atlas_height = 0,
    .cell_width = 8,
    .cell_height = 16,
    .cols = 16,
    .rows = 6,
    .first_codepoint = 0x20,
    .glyph_count = 95,
    .ascent = 0,
    .descent = 0,
    .leading = 0,
    ._pad = 0,
};
var g_grids: [MAX_GRIDS]GridState = .{ .{}, .{} };

fn themeFor(grid_id: usize) GridTheme {
    return if (grid_id == 0)
        .{
            .clear = .{ 0.08, 0.09, 0.11, 1.0 },
            .fg = .{ 235, 239, 244, 255 },
            .bg = .{ 20, 24, 31, 255 },
            .cursor_bg = .{ 128, 184, 255, 255 },
            .prompt_fg = .{ 235, 239, 244, 255 },
            .comment_fg = .{ 100, 120, 100, 255 },
            .string_fg = .{ 230, 180, 80, 255 },
            .keyword_fg = .{ 90, 200, 255, 255 },
            .number_fg = .{ 180, 255, 140, 255 },
            .paren_fg = .{ 160, 160, 200, 255 },
        }
    else
        .{
            .clear = .{ 0.03, 0.09, 0.06, 1.0 },
            .fg = .{ 193, 255, 193, 255 },
            .bg = .{ 8, 20, 13, 255 },
            .cursor_bg = .{ 120, 255, 160, 255 },
            .prompt_fg = .{ 255, 220, 150, 255 },
        };
}

fn clampGridId(grid_id: i32) usize {
    return if (grid_id <= 0) 0 else if (grid_id >= MAX_GRIDS) MAX_GRIDS - 1 else @as(usize, @intCast(grid_id));
}

fn appendEmptyLine(list: *LineList) !void {
    try list.append(allocator, .{});
}

fn freeLineList(list: *LineList) void {
    for (list.items) |*line| line.deinit(allocator);
    list.deinit(allocator);
    list.* = .{};
}

fn freeHistoryList(list: *HistoryList) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
    list.* = .{};
}

fn freeEditorUndoList(list: *EditorUndoList) void {
    for (list.items) |item| allocator.free(item.text);
    list.deinit(allocator);
    list.* = .{};
}

fn trimEditorUndoList(list: *EditorUndoList, max_len: usize) void {
    while (list.items.len > max_len) {
        const oldest = list.orderedRemove(0);
        allocator.free(oldest.text);
    }
}

fn appendUtf8ToLine(line: *Line, bytes: []const u8) !void {
    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > bytes.len) break;
        const cp = std.unicode.utf8Decode(bytes[i .. i + len]) catch {
            i += len;
            continue;
        };
        if (cp != '\n' and cp != '\r') {
            try line.append(allocator, cp);
        }
        i += len;
    }
}

fn decodeUtf8IntoLineList(list: *LineList, bytes: []const u8) !void {
    if (list.items.len == 0) try appendEmptyLine(list);

    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > bytes.len) break;
        const cp = std.unicode.utf8Decode(bytes[i .. i + len]) catch {
            i += len;
            continue;
        };
        if (cp == '\r') {
            i += len;
            continue;
        }
        if (cp == '\n') {
            try appendEmptyLine(list);
        } else {
            try list.items[list.items.len - 1].append(allocator, cp);
        }
        i += len;
    }
}

fn appendCodepointUtf8(out: *ByteList, cp: u32) !void {
    if (cp > 0x10FFFF) return;
    var buf: [4]u8 = undefined;
    const scalar: u21 = @intCast(cp);
    const len = std.unicode.utf8Encode(scalar, &buf) catch return;
    try out.appendSlice(allocator, buf[0..len]);
}

fn lineListToUtf8(alloc: std.mem.Allocator, list: *const LineList) ![]u8 {
    var out: ByteList = .{};
    errdefer out.deinit(alloc);

    for (list.items, 0..) |line, row| {
        for (line.items) |cp| {
            if (cp > 0x10FFFF) continue;
            var buf: [4]u8 = undefined;
            const scalar: u21 = @intCast(cp);
            const len = std.unicode.utf8Encode(scalar, &buf) catch continue;
            try out.appendSlice(alloc, buf[0..len]);
        }
        if (row + 1 < list.items.len) {
            try out.append(alloc, '\n');
        }
    }

    return try out.toOwnedSlice(alloc);
}

fn entryRangeToUtf8(grid: *const GridState, start: EntryPos, end: EntryPos) ?[]u8 {
    var out: ByteList = .{};
    errdefer out.deinit(allocator);

    var pos = start;
    while (entryPosCompare(pos, end) < 0) {
        const cp = codepointAt(grid, pos) orelse {
            if (pos.row + 1 > end.row) break;
            out.append(allocator, '\n') catch return null;
            pos.row += 1;
            pos.col = 0;
            continue;
        };
        appendCodepointUtf8(&out, cp) catch return null;
        if (!advanceAnyPosition(grid, &pos)) break;
    }

    return out.toOwnedSlice(allocator) catch null;
}

fn longestCommonCompletionPrefix(items: []const []u8) []const u8 {
    if (items.len == 0) return "";
    var common_len = items[0].len;
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        common_len = @min(common_len, items[i].len);
        var j: usize = 0;
        while (j < common_len and items[0][j] == items[i][j]) : (j += 1) {}
        common_len = j;
    }
    return items[0][0..common_len];
}

fn isWhitespace(cp: u32) bool {
    return cp == ' ' or cp == '\t' or cp == '\n' or cp == '\r';
}

fn containsTabs(text: []const u32) bool {
    for (text) |cp| if (cp == '\t') return true;
    return false;
}

fn visibleCols(grid: *const GridState) usize {
    if (g_atlas.cell_width <= 0 or grid.viewport_width <= 0) return 1;
    return @max(1, @as(usize, @intFromFloat(@floor(grid.viewport_width / g_atlas.cell_width))));
}

fn visibleRows(grid: *const GridState) usize {
    if (g_atlas.cell_height <= 0 or grid.viewport_height <= 0) return 1;
    return @max(1, @as(usize, @intFromFloat(@floor(grid.viewport_height / g_atlas.cell_height))));
}

fn atlasUv(cp: u32) struct { x: f32, y: f32 } {
    const fallback_index: u32 = 0;
    const index = if (cp >= g_atlas.first_codepoint and cp < g_atlas.first_codepoint + g_atlas.glyph_count)
        cp - g_atlas.first_codepoint
    else
        fallback_index;

    const col = index % g_atlas.cols;
    const row = index / g_atlas.cols;
    return .{
        .x = @as(f32, @floatFromInt(col)) * g_atlas.cell_width,
        .y = @as(f32, @floatFromInt(row)) * g_atlas.cell_height,
    };
}

fn appendCellWithColours(grid: *GridState, row: usize, col: usize, cp: u32, flags: u32, fg: [4]u8, bg: [4]u8, cursor_bg: [4]u8) void {
    const uv = atlasUv(cp);
    grid.instances.append(allocator, .{
        .pos_x = @as(f32, @floatFromInt(col)) * g_atlas.cell_width,
        .pos_y = @as(f32, @floatFromInt(row)) * g_atlas.cell_height,
        .uv_x = uv.x,
        .uv_y = uv.y,
        .fg = fg,
        .bg = if ((flags & FLAG_CURSOR) != 0) cursor_bg else bg,
        .flags = flags & ~FLAG_BRACKET_MATCH, // strip internal flag before GPU
    }) catch {};
}

fn appendCell(grid: *GridState, row: usize, col: usize, cp: u32, flags: u32, theme: GridTheme) void {
    appendCellWithColours(grid, row, col, cp, flags, theme.fg, theme.bg, theme.cursor_bg);
}

fn codepointAt(grid: *const GridState, pos: EntryPos) ?u32 {
    if (pos.row >= grid.entry.items.len) return null;
    const line = &grid.entry.items[pos.row];
    if (pos.col >= line.items.len) return null;
    return line.items[pos.col];
}

fn advanceEntryPosition(grid: *const GridState, pos: *EntryPos, end: EntryPos) bool {
    if (pos.row > end.row or (pos.row == end.row and pos.col >= end.col)) return false;
    const line = &grid.entry.items[pos.row];
    if (pos.col + 1 < line.items.len) {
        pos.col += 1;
        return true;
    }
    if (pos.row < end.row) {
        pos.row += 1;
        pos.col = 0;
        return true;
    }
    pos.col = line.items.len;
    return false;
}

fn entryBeforePosition(grid: *const GridState, row: usize, col: usize) EntryPos {
    if (row == 0 and col == 0) return .{ .row = 0, .col = 0 };
    if (col > 0) return .{ .row = row, .col = col - 1 };
    const prev_row = row - 1;
    return .{ .row = prev_row, .col = grid.entry.items[prev_row].items.len };
}

fn entryPosCompare(a: EntryPos, b: EntryPos) i2 {
    if (a.row < b.row) return -1;
    if (a.row > b.row) return 1;
    if (a.col < b.col) return -1;
    if (a.col > b.col) return 1;
    return 0;
}

fn advanceAnyPosition(grid: *const GridState, pos: *EntryPos) bool {
    if (pos.row >= grid.entry.items.len) return false;
    const line = &grid.entry.items[pos.row];
    if (pos.col < line.items.len) {
        pos.col += 1;
        if (pos.col <= line.items.len) return true;
    }
    if (pos.row + 1 >= grid.entry.items.len) return false;
    pos.row += 1;
    pos.col = 0;
    return true;
}

fn skipEntryWhitespaceForward(grid: *const GridState, start: EntryPos) EntryPos {
    var pos = start;
    while (true) {
        const cp = codepointAt(grid, pos) orelse {
            if (!advanceAnyPosition(grid, &pos)) break;
            continue;
        };
        if (!isWhitespace(cp)) break;
        if (!advanceAnyPosition(grid, &pos)) break;
    }
    return pos;
}

fn skipEntryWhitespaceBackward(grid: *const GridState, end: EntryPos) EntryPos {
    var pos = end;
    while (!(pos.row == 0 and pos.col == 0)) {
        const prev = entryBeforePosition(grid, pos.row, pos.col);
        const cp = codepointAt(grid, prev) orelse break;
        if (!isWhitespace(cp)) break;
        pos = prev;
    }
    return pos;
}

fn tokenTerminator(cp: u32) bool {
    return isWhitespace(cp) or cp == '(' or cp == ')' or cp == '[' or cp == ']' or cp == '"' or cp == ';';
}

fn isWordCodepoint(cp: u32) bool {
    if (tokenTerminator(cp)) return false;
    if (cp <= 0x7F) {
        return std.ascii.isAlphanumeric(@as(u8, @intCast(cp))) or cp == '-' or cp == '_' or cp == '?' or cp == '!' or cp == '*' or cp == '/' or cp == '<' or cp == '>' or cp == '=';
    }
    return true;
}

fn tokenEqualsAscii(token: []const u32, ascii: []const u8) bool {
    if (token.len != ascii.len) return false;
    for (token, ascii) |cp, b| {
        if (cp != @as(u32, b)) return false;
    }
    return true;
}

fn isSpecialForm(token: []const u32) bool {
    const forms = [_][]const u8{
        "define", "lambda", "let", "let*", "letrec",        "let-values",   "if",    "cond",         "begin",                  "when",             "unless",
        "do",     "case",   "and", "or",   "define-syntax", "syntax-rules", "guard", "parameterize", "with-exception-handler", "call-with-values",
    };
    for (forms) |form| {
        if (tokenEqualsAscii(token, form)) return true;
    }
    return false;
}

fn findInnermostOpen(grid: *const GridState, end: EntryPos) ?OpenDelimiter {
    var stack: std.ArrayListUnmanaged(OpenDelimiter) = .{};
    defer stack.deinit(allocator);

    var row: usize = 0;
    var in_string = false;
    var escape = false;
    var block_comment_depth: usize = 0;

    while (row <= end.row and row < grid.entry.items.len) : (row += 1) {
        const line = &grid.entry.items[row];
        const limit = if (row == end.row) end.col else line.items.len;
        var col: usize = 0;
        while (col < limit) : (col += 1) {
            const cp = line.items[col];
            if (block_comment_depth > 0) {
                if (cp == '#' and col + 1 < limit and line.items[col + 1] == '|') {
                    block_comment_depth += 1;
                    col += 1;
                } else if (cp == '|' and col + 1 < limit and line.items[col + 1] == '#') {
                    block_comment_depth -= 1;
                    col += 1;
                }
                continue;
            }
            if (in_string) {
                if (escape) {
                    escape = false;
                } else if (cp == '\\') {
                    escape = true;
                } else if (cp == '"') {
                    in_string = false;
                }
                continue;
            }
            if (cp == ';') break;
            if (cp == '#' and col + 1 < limit and line.items[col + 1] == '|') {
                block_comment_depth += 1;
                col += 1;
                continue;
            }
            if (cp == '"') {
                in_string = true;
                escape = false;
                continue;
            }
            if (cp == '(' or cp == '[') {
                stack.append(allocator, .{ .cp = cp, .row = row, .col = col }) catch return null;
                continue;
            }
            if (cp == ')' or cp == ']') {
                if (stack.items.len == 0) return null;
                const open = stack.items[stack.items.len - 1];
                if (!delimitersMatch(open.cp, cp)) return null;
                _ = stack.pop();
            }
        }
    }

    if (stack.items.len == 0) return null;
    return stack.items[stack.items.len - 1];
}

fn delimitersMatch(open: u32, close: u32) bool {
    return (open == '(' and close == ')') or (open == '[' and close == ']');
}

fn matchingCloseDelimiter(open: u32) ?u32 {
    return switch (open) {
        '(' => ')',
        '[' => ']',
        else => null,
    };
}

fn isDelimiter(cp: u32) bool {
    return cp == '(' or cp == ')' or cp == '[' or cp == ']';
}

fn matchingTargetNearCursor(grid: *const GridState) ?EntryPos {
    const at_cursor = EntryPos{ .row = grid.entry_cursor_row, .col = grid.entry_cursor_col };
    if (codepointAt(grid, at_cursor)) |cp| {
        if (isDelimiter(cp)) return at_cursor;
    }
    if (grid.entry_cursor_row == 0 and grid.entry_cursor_col == 0) return null;
    const before = entryBeforePosition(grid, grid.entry_cursor_row, grid.entry_cursor_col);
    if (codepointAt(grid, before)) |cp| {
        if (isDelimiter(cp)) return before;
    }
    return null;
}

fn positionAfter(grid: *const GridState, pos: EntryPos) EntryPos {
    var out = pos;
    _ = advanceAnyPosition(grid, &out);
    return out;
}

fn findForwardSexpEnd(grid: *const GridState, start: EntryPos) ?EntryPos {
    const cp = codepointAt(grid, start) orelse return null;
    if (cp == '(' or cp == '[') {
        const close = findMatchingDelimiter(grid, start) orelse return null;
        return positionAfter(grid, close);
    }
    if (cp == ')' or cp == ']') {
        return positionAfter(grid, start);
    }

    var pos = start;
    while (true) {
        const here = codepointAt(grid, pos) orelse return pos;
        if (tokenTerminator(here)) return pos;
        if (!advanceAnyPosition(grid, &pos)) return pos;
    }
}

fn findBackwardSexpStart(grid: *const GridState, end: EntryPos) ?EntryPos {
    if (end.row == 0 and end.col == 0) return null;
    var pos = entryBeforePosition(grid, end.row, end.col);
    const cp = codepointAt(grid, pos) orelse return null;

    if (cp == ')' or cp == ']') {
        return findMatchingDelimiter(grid, pos);
    }
    if (cp == '(' or cp == '[') {
        return pos;
    }

    while (!(pos.row == 0 and pos.col == 0)) {
        const prev = entryBeforePosition(grid, pos.row, pos.col);
        const prev_cp = codepointAt(grid, prev) orelse break;
        if (tokenTerminator(prev_cp)) break;
        pos = prev;
    }
    return pos;
}

fn findMatchingDelimiter(grid: *const GridState, pos: EntryPos) ?EntryPos {
    const cp = codepointAt(grid, pos) orelse return null;
    return switch (cp) {
        ')', ']' => findOpenForClose(grid, pos),
        '(', '[' => findCloseForOpen(grid, pos),
        else => null,
    };
}

fn findOpenForClose(grid: *const GridState, close_pos: EntryPos) ?EntryPos {
    var stack: std.ArrayListUnmanaged(OpenDelimiter) = .{};
    defer stack.deinit(allocator);

    var row: usize = 0;
    var in_string = false;
    var escape = false;
    var block_comment_depth: usize = 0;

    while (row <= close_pos.row and row < grid.entry.items.len) : (row += 1) {
        const line = &grid.entry.items[row];
        const limit = if (row == close_pos.row) close_pos.col + 1 else line.items.len;
        var col: usize = 0;
        while (col < limit and col < line.items.len) : (col += 1) {
            const cp = line.items[col];
            if (block_comment_depth > 0) {
                if (cp == '#' and col + 1 < line.items.len and line.items[col + 1] == '|') {
                    block_comment_depth += 1;
                    col += 1;
                } else if (cp == '|' and col + 1 < line.items.len and line.items[col + 1] == '#') {
                    block_comment_depth -= 1;
                    col += 1;
                }
                continue;
            }
            if (in_string) {
                if (escape) {
                    escape = false;
                } else if (cp == '\\') {
                    escape = true;
                } else if (cp == '"') {
                    in_string = false;
                }
                continue;
            }
            if (cp == ';') break;
            if (cp == '#' and col + 1 < line.items.len and line.items[col + 1] == '|') {
                block_comment_depth += 1;
                col += 1;
                continue;
            }
            if (cp == '"') {
                in_string = true;
                escape = false;
                continue;
            }
            if (cp == '(' or cp == '[') {
                stack.append(allocator, .{ .cp = cp, .row = row, .col = col }) catch return null;
                continue;
            }
            if (cp == ')' or cp == ']') {
                if (stack.items.len == 0) return null;
                const open = stack.items[stack.items.len - 1];
                if (!delimitersMatch(open.cp, cp)) return null;
                _ = stack.pop();
                if (row == close_pos.row and col == close_pos.col) return .{ .row = open.row, .col = open.col };
            }
        }
    }

    return null;
}

fn findCloseForOpen(grid: *const GridState, open_pos: EntryPos) ?EntryPos {
    const open_cp = codepointAt(grid, open_pos) orelse return null;
    var expected: std.ArrayListUnmanaged(u32) = .{};
    defer expected.deinit(allocator);
    expected.append(allocator, matchingCloseDelimiter(open_cp) orelse return null) catch return null;

    var pos = open_pos;
    if (!advanceAnyPosition(grid, &pos)) return null;

    var in_string = false;
    var escape = false;
    var block_comment_depth: usize = 0;

    while (true) {
        const cp = codepointAt(grid, pos) orelse {
            if (!advanceAnyPosition(grid, &pos)) break;
            continue;
        };
        const line = &grid.entry.items[pos.row];

        if (block_comment_depth > 0) {
            if (cp == '#' and pos.col + 1 < line.items.len and line.items[pos.col + 1] == '|') {
                block_comment_depth += 1;
                _ = advanceAnyPosition(grid, &pos);
            } else if (cp == '|' and pos.col + 1 < line.items.len and line.items[pos.col + 1] == '#') {
                block_comment_depth -= 1;
                _ = advanceAnyPosition(grid, &pos);
            }
            if (!advanceAnyPosition(grid, &pos)) break;
            continue;
        }
        if (in_string) {
            if (escape) {
                escape = false;
            } else if (cp == '\\') {
                escape = true;
            } else if (cp == '"') {
                in_string = false;
            }
            if (!advanceAnyPosition(grid, &pos)) break;
            continue;
        }
        if (cp == ';') {
            pos.row += 1;
            pos.col = 0;
            continue;
        }
        if (cp == '#' and pos.col + 1 < line.items.len and line.items[pos.col + 1] == '|') {
            block_comment_depth += 1;
            _ = advanceAnyPosition(grid, &pos);
            if (!advanceAnyPosition(grid, &pos)) break;
            continue;
        }
        if (cp == '"') {
            in_string = true;
            escape = false;
            if (!advanceAnyPosition(grid, &pos)) break;
            continue;
        }
        if (cp == '(' or cp == '[') {
            expected.append(allocator, matchingCloseDelimiter(cp) orelse return null) catch return null;
        } else if (cp == ')' or cp == ']') {
            if (expected.items.len == 0) return null;
            const want = expected.items[expected.items.len - 1];
            if (cp != want) return null;
            _ = expected.pop();
            if (expected.items.len == 0) return pos;
        }

        if (!advanceAnyPosition(grid, &pos)) break;
    }

    return null;
}

fn expressionCompleteness(grid: *const GridState) Completeness {
    var saw_non_ws = false;
    var in_string = false;
    var escape = false;
    var block_comment_depth: usize = 0;
    var stack: std.ArrayListUnmanaged(u32) = .{};
    defer stack.deinit(allocator);

    for (grid.entry.items) |line| {
        var col: usize = 0;
        while (col < line.items.len) : (col += 1) {
            const cp = line.items[col];
            if (block_comment_depth > 0) {
                if (cp == '#' and col + 1 < line.items.len and line.items[col + 1] == '|') {
                    block_comment_depth += 1;
                    col += 1;
                } else if (cp == '|' and col + 1 < line.items.len and line.items[col + 1] == '#') {
                    block_comment_depth -= 1;
                    col += 1;
                }
                continue;
            }
            if (in_string) {
                saw_non_ws = true;
                if (escape) {
                    escape = false;
                } else if (cp == '\\') {
                    escape = true;
                } else if (cp == '"') {
                    in_string = false;
                }
                continue;
            }
            if (cp == ';') break;
            if (cp == '#' and col + 1 < line.items.len and line.items[col + 1] == '|') {
                saw_non_ws = true;
                block_comment_depth += 1;
                col += 1;
                continue;
            }
            if (isWhitespace(cp)) continue;
            saw_non_ws = true;
            switch (cp) {
                '"' => {
                    in_string = true;
                    escape = false;
                },
                '(', '[' => stack.append(allocator, cp) catch return .incomplete,
                ')', ']' => {
                    if (stack.items.len == 0) return .err;
                    const open = stack.pop().?;
                    if (!delimitersMatch(open, cp)) return .err;
                },
                else => {},
            }
        }
    }

    if (!saw_non_ws) return .incomplete;
    if (in_string or block_comment_depth > 0 or stack.items.len > 0) return .incomplete;
    return .complete;
}

fn computeIndentForContinuation(grid: *const GridState, row: usize, col: usize) usize {
    const before = entryBeforePosition(grid, row, col);
    return computeIndentFromPosition(grid, before);
}

fn computeIndentForRow(grid: *const GridState, row: usize) usize {
    if (row == 0) return 0;
    const before = entryBeforePosition(grid, row, 0);
    return computeIndentFromPosition(grid, before);
}

fn computeIndentFromPosition(grid: *const GridState, end: EntryPos) usize {
    const open = findInnermostOpen(grid, .{ .row = end.row, .col = end.col + 1 }) orelse return 0;
    return analyzeIndentAfterOpen(grid, open, .{ .row = end.row, .col = end.col + 1 });
}

fn analyzeIndentAfterOpen(grid: *const GridState, open: OpenDelimiter, end: EntryPos) usize {
    var pos = EntryPos{ .row = open.row, .col = open.col };
    _ = advanceEntryPosition(grid, &pos, end);

    var operator: std.ArrayListUnmanaged(u32) = .{};
    defer operator.deinit(allocator);

    var state: enum { seek_operator, read_operator, seek_arg } = .seek_operator;
    var in_string = false;
    var escape = false;
    var block_comment_depth: usize = 0;
    var first_arg_col: ?usize = null;

    while (true) {
        if (pos.row > end.row or (pos.row == end.row and pos.col >= end.col)) break;
        const cp = codepointAt(grid, pos) orelse break;

        if (block_comment_depth > 0) {
            if (cp == '#' and codepointAt(grid, .{ .row = pos.row, .col = pos.col + 1 }) == '|') {
                block_comment_depth += 1;
                if (!advanceEntryPosition(grid, &pos, end)) break;
            } else if (cp == '|' and codepointAt(grid, .{ .row = pos.row, .col = pos.col + 1 }) == '#') {
                block_comment_depth -= 1;
                if (!advanceEntryPosition(grid, &pos, end)) break;
            }
            if (!advanceEntryPosition(grid, &pos, end)) break;
            continue;
        }

        if (in_string) {
            if (escape) {
                escape = false;
            } else if (cp == '\\') {
                escape = true;
            } else if (cp == '"') {
                in_string = false;
            }
            if (!advanceEntryPosition(grid, &pos, end)) break;
            continue;
        }

        if (cp == ';') {
            pos.row += 1;
            pos.col = 0;
            continue;
        }
        if (cp == '#' and codepointAt(grid, .{ .row = pos.row, .col = pos.col + 1 }) == '|') {
            block_comment_depth += 1;
            if (!advanceEntryPosition(grid, &pos, end)) break;
            if (!advanceEntryPosition(grid, &pos, end)) break;
            continue;
        }
        if (cp == '"') {
            in_string = true;
            escape = false;
            if (!advanceEntryPosition(grid, &pos, end)) break;
            continue;
        }

        switch (state) {
            .seek_operator => {
                if (!isWhitespace(cp)) {
                    if (tokenTerminator(cp)) return open.col + 2;
                    state = .read_operator;
                    operator.append(allocator, cp) catch return open.col + 2;
                }
            },
            .read_operator => {
                if (tokenTerminator(cp)) {
                    state = .seek_arg;
                    if (!isWhitespace(cp)) {
                        first_arg_col = pos.col;
                        break;
                    }
                } else {
                    operator.append(allocator, cp) catch return open.col + 2;
                }
            },
            .seek_arg => {
                if (!isWhitespace(cp)) {
                    first_arg_col = pos.col;
                    break;
                }
            },
        }

        if (!advanceEntryPosition(grid, &pos, end)) break;
    }

    if (operator.items.len == 0) return open.col + 2;
    if (isSpecialForm(operator.items)) return open.col + 2;
    if (first_arg_col) |col| return col;
    return open.col + 2;
}

// Syntax token kinds for the editor highlighter.
const SyntaxKind = enum { normal, comment, string, keyword, number, paren };

// Tokenize one line of the editor buffer and write per-column SyntaxKind into `out`.
// `out` must have length >= line.len.
fn syntaxColorLine(line: []const u32, out: []SyntaxKind, in_string_in: bool, in_block_comment_in: *usize) bool {
    var in_string = in_string_in;
    var block_depth = in_block_comment_in.*;
    var escape = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const cp = line[i];
        if (block_depth > 0) {
            out[i] = .comment;
            if (cp == '#' and i + 1 < line.len and line[i + 1] == '|') {
                block_depth += 1;
                i += 1;
                if (i < out.len) out[i] = .comment;
            } else if (cp == '|' and i + 1 < line.len and line[i + 1] == '#') {
                block_depth -= 1;
                i += 1;
                if (i < out.len) out[i] = .comment;
            }
            continue;
        }
        if (in_string) {
            out[i] = .string;
            if (escape) {
                escape = false;
            } else if (cp == '\\') {
                escape = true;
            } else if (cp == '"') {
                in_string = false;
            }
            continue;
        }
        // line comment — rest of line
        if (cp == ';') {
            while (i < line.len) : (i += 1) out[i] = .comment;
            break;
        }
        // block comment open
        if (cp == '#' and i + 1 < line.len and line[i + 1] == '|') {
            block_depth += 1;
            out[i] = .comment;
            i += 1;
            out[i] = .comment;
            continue;
        }
        // string open
        if (cp == '"') {
            in_string = true;
            out[i] = .string;
            escape = false;
            continue;
        }
        // parens / brackets
        if (cp == '(' or cp == ')' or cp == '[' or cp == ']') {
            out[i] = .paren;
            continue;
        }
        // numbers: leading digit or #e/#i/#b/#o/#x/#d prefix
        if ((cp >= '0' and cp <= '9') or
            (cp == '#' and i + 1 < line.len and (line[i + 1] == 'e' or line[i + 1] == 'i' or line[i + 1] == 'b' or line[i + 1] == 'o' or line[i + 1] == 'x' or line[i + 1] == 'd' or line[i + 1] == 'E' or line[i + 1] == 'I')))
        {
            // scan token
            var j = i;
            while (j < line.len and !tokenTerminator(line[j])) : (j += 1) {}
            var k = i;
            while (k < j) : (k += 1) out[k] = .number;
            i = j - 1;
            continue;
        }
        // identifiers / keywords
        if (!isWhitespace(cp) and cp != '#') {
            var j = i;
            while (j < line.len and !tokenTerminator(line[j])) : (j += 1) {}
            const tok = line[i..j];
            const kind: SyntaxKind = if (isSpecialForm(tok)) .keyword else .normal;
            var k = i;
            while (k < j) : (k += 1) out[k] = kind;
            i = j - 1;
            continue;
        }
        out[i] = .normal;
    }
    in_block_comment_in.* = block_depth;
    return in_string;
}

fn syntaxFg(kind: SyntaxKind, theme: GridTheme) [4]u8 {
    return switch (kind) {
        .normal => theme.fg,
        .comment => theme.comment_fg,
        .string => theme.string_fg,
        .keyword => theme.keyword_fg,
        .number => theme.number_fg,
        .paren => theme.paren_fg,
    };
}

fn renderEditor(grid: *GridState, theme: GridTheme, cols: usize, rows: usize) void {
    // Scroll so cursor stays visible.
    const half = rows / 2;
    const start_row = if (grid.cursor_row + 1 > rows)
        @max(grid.cursor_row + 1 - rows, if (grid.cursor_row >= half) grid.cursor_row - half else 0)
    else
        0;
    const line_count = grid.editorLineCount();
    const buf = grid.editorBufferConst();

    // Compute bracket match positions for this frame.
    var match_a: ?usize = null; // the delimiter the cursor is on/before
    var match_b: ?usize = null; // its partner
    if (grid.editorBracketUnderCursor()) |bracket_off| {
        match_a = bracket_off;
        match_b = grid.editorFindMatchingBracket(bracket_off);
    }
    const selection = grid.editorSelectionRange();

    // Persistent syntax state across lines (string / block-comment spans)
    var in_string = false;
    var block_depth: usize = 0;
    // Fast-forward state to start_row
    if (start_row > 0) {
        var r: usize = 0;
        while (r < start_row) : (r += 1) {
            const fline = grid.editorBufferConst().getLine(r) catch null;
            if (fline) |fl| {
                defer allocator.free(fl);
                const tmp = allocator.alloc(SyntaxKind, fl.len) catch {
                    in_string = false;
                    block_depth = 0;
                    continue;
                };
                defer allocator.free(tmp);
                in_string = syntaxColorLine(fl, tmp, in_string, &block_depth);
            }
        }
    }

    var screen_row: usize = 0;
    while (screen_row < rows) : (screen_row += 1) {
        const doc_row = start_row + screen_row;
        const maybe_line = if (doc_row < line_count) grid.editorBufferConst().getLine(doc_row) catch null else null;
        defer if (maybe_line) |line| allocator.free(line);

        var syntax_kinds: ?[]SyntaxKind = null;
        if (maybe_line) |line| {
            if (allocator.alloc(SyntaxKind, line.len)) |sk| {
                in_string = syntaxColorLine(line, sk, in_string, &block_depth);
                syntax_kinds = sk;
            } else |_| {}
        }
        defer if (syntax_kinds) |sk| allocator.free(sk);

        var col: usize = 0;
        while (col < cols) : (col += 1) {
            var cp: u32 = ' ';
            var flags: u32 = 0;
            var fg = theme.fg;
            var cell_bg = theme.bg;
            if (maybe_line) |line| {
                if (col < line.len) {
                    cp = line[col];
                    if (syntax_kinds) |sk| fg = syntaxFg(sk[col], theme);
                }
                if (doc_row == grid.cursor_row and col == grid.cursor_col) flags |= FLAG_CURSOR;
                const cell_off = buf.lineColToOffset(doc_row, col);
                if (selection) |range| {
                    if (cell_off >= range.start and cell_off < range.end) {
                        cell_bg = theme.selection_bg;
                    }
                }
                if (match_a != null and match_b == null and cell_off == match_a.?) {
                    cell_bg = theme.unbalanced_bg;
                } else if ((match_a != null and cell_off == match_a.?) or (match_b != null and cell_off == match_b.?)) {
                    cell_bg = theme.bracket_match_bg;
                }
            } else if (doc_row == grid.cursor_row and col == grid.cursor_col) {
                flags |= FLAG_CURSOR;
            }
            appendCellWithColours(grid, screen_row, col, cp, flags, fg, cell_bg, theme.cursor_bg);
        }
    }

    if (grid.cursor_row >= start_row and grid.cursor_row < start_row + rows and grid.cursor_col >= cols) {
        appendCellWithColours(grid, grid.cursor_row - start_row, cols - 1, ' ', FLAG_CURSOR, theme.fg, theme.bg, theme.cursor_bg);
    }
}

fn renderRepl(grid: *GridState, theme: GridTheme, cols: usize, rows: usize) void {
    const prompt_base_row = grid.promptBaseRow();
    const completion_rows = if (grid.completion_menu_visible)
        @min(grid.completions.items.len, @as(usize, MAX_VISIBLE_COMPLETIONS)) + if (grid.completions.items.len > MAX_VISIBLE_COMPLETIONS) @as(usize, 1) else 0
    else
        0;
    const total_rows = prompt_base_row + grid.entry.items.len + completion_rows;
    const flash_pos = grid.activeFlashPos();
    const cursor_pos = flash_pos orelse EntryPos{ .row = grid.entry_cursor_row, .col = grid.entry_cursor_col };
    const cursor_doc_row = prompt_base_row + cursor_pos.row;
    const cursor_doc_col = if (cursor_pos.row == 0) grid.prompt.items.len + cursor_pos.col else cursor_pos.col;
    const start_row = if (cursor_doc_row + 1 > rows) cursor_doc_row + 1 - rows else 0;

    var screen_row: usize = 0;
    while (screen_row < rows) : (screen_row += 1) {
        const doc_row = start_row + screen_row;
        var col: usize = 0;
        while (col < cols) : (col += 1) {
            var cp: u32 = ' ';
            var fg = theme.fg;
            var flags: u32 = 0;

            if (doc_row < total_rows) {
                if (doc_row < prompt_base_row) {
                    const line = &grid.lines.items[doc_row];
                    if (col < line.items.len) cp = line.items[col];
                } else {
                    const entry_row = doc_row - prompt_base_row;
                    if (entry_row < grid.entry.items.len) {
                        if (entry_row == 0 and col < grid.prompt.items.len) {
                            cp = grid.prompt.items[col];
                            fg = theme.prompt_fg;
                        } else {
                            const line = &grid.entry.items[entry_row];
                            const content_col = if (entry_row == 0) col -| grid.prompt.items.len else col;
                            if (content_col < line.items.len) cp = line.items[content_col];
                        }
                    } else if (grid.completion_menu_visible) {
                        const completion_index = entry_row - grid.entry.items.len;
                        if (completion_index < completion_rows) {
                            fg = theme.prompt_fg;
                            if (grid.completions.items.len > MAX_VISIBLE_COMPLETIONS and completion_index + 1 == completion_rows) {
                                const remaining = grid.completions.items.len - MAX_VISIBLE_COMPLETIONS;
                                var more_buf: [32]u8 = undefined;
                                const more_text = std.fmt.bufPrint(&more_buf, "… {d} more", .{remaining}) catch "…";
                                if (col < more_text.len) cp = more_text[col];
                            } else {
                                const word = grid.completions.items[completion_index];
                                if (col == 0) {
                                    cp = '›';
                                } else if (col == 1) {
                                    cp = ' ';
                                } else {
                                    const word_col = col - 2;
                                    if (word_col < word.len) cp = word[word_col];
                                }
                            }
                        }
                    }
                }
                if (doc_row == cursor_doc_row and col == cursor_doc_col) flags |= FLAG_CURSOR;
            }

            appendCellWithColours(grid, screen_row, col, cp, flags, fg, theme.bg, theme.cursor_bg);
        }
    }

    if (cursor_doc_row >= start_row and cursor_doc_row < start_row + rows and cursor_doc_col >= cols) {
        appendCellWithColours(grid, cursor_doc_row - start_row, cols - 1, ' ', FLAG_CURSOR, theme.fg, theme.bg, theme.cursor_bg);
    }
}

fn submitRepl(grid: *GridState) void {
    if (grid.entryIsWhitespaceOnly()) return;

    switch (expressionCompleteness(grid)) {
        .incomplete => {
            const indent = computeIndentForContinuation(grid, grid.entry_cursor_row, grid.entry_cursor_col);
            grid.entryInsertNewline();
            grid.entryInsertIndent(indent);
        },
        .complete, .err => {
            const utf8 = grid.snapshotEntryUtf8() orelse return;
            defer allocator.free(utf8);

            grid.pushHistory(utf8);
            grid.appendPromptAndEntryToOutput();
            grid.clearEntry();
            grid.resetHistoryCursor();
            macscheme_eval_async(utf8.ptr, utf8.len);
        },
    }
}

fn replInsertDelimiter(grid: *GridState, codepoint: u32) void {
    var cp = codepoint;

    if (cp == ')' or cp == ']') {
        if (findInnermostOpen(grid, .{ .row = grid.entry_cursor_row, .col = grid.entry_cursor_col })) |open| {
            cp = if (open.cp == '[') ']' else ')';
        }
    }

    grid.entryInsertCodepoint(cp);

    if (cp == ')' or cp == ']') {
        const close_pos = entryBeforePosition(grid, grid.entry_cursor_row, grid.entry_cursor_col);
        if (findMatchingDelimiter(grid, close_pos)) |match| {
            grid.setFlash(match);
        }
    }
}

fn pasteIntoGrid(grid: *GridState, bytes: []const u8) void {
    if (grid.grid_id == 0) {
        grid.insertEditorUtf8(bytes);
        return;
    }

    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > bytes.len) break;
        const cp = std.unicode.utf8Decode(bytes[i .. i + len]) catch {
            i += len;
            continue;
        };
        if (grid.grid_id == 1) {
            if (cp == '\n') {
                grid.entryInsertNewline();
            } else if (cp != '\r') {
                grid.entryInsertCodepoint(cp);
            }
        }
        i += len;
    }
}

fn serializeGridDocument(grid: *const GridState) ?[]u8 {
    if (grid.grid_id == 0) {
        return grid.editorBufferConst().toUtf8() catch null;
    }

    var out: ByteList = .{};
    errdefer out.deinit(allocator);

    const prompt_base_row = grid.promptBaseRow();
    var row: usize = 0;
    while (row < prompt_base_row) : (row += 1) {
        for (grid.lines.items[row].items) |cp| appendCodepointUtf8(&out, cp) catch return null;
        tryAppendNewline(&out);
    }

    for (grid.prompt.items) |cp| appendCodepointUtf8(&out, cp) catch return null;
    for (grid.entry.items[0].items) |cp| appendCodepointUtf8(&out, cp) catch return null;
    row = 1;
    while (row < grid.entry.items.len) : (row += 1) {
        tryAppendNewline(&out);
        for (grid.entry.items[row].items) |cp| appendCodepointUtf8(&out, cp) catch return null;
    }

    return out.toOwnedSlice(allocator) catch null;
}

fn tryAppendNewline(out: *ByteList) void {
    out.append(allocator, '\n') catch {};
}

fn historyToNulSeparated(alloc: std.mem.Allocator, history: *const HistoryList) ![]u8 {
    var out: ByteList = .{};
    errdefer out.deinit(alloc);

    const start_index = history.items.len -| MAX_PERSISTED_HISTORY;
    for (history.items[start_index..], 0..) |item, index| {
        try out.appendSlice(alloc, item);
        if (index + 1 < history.items.len - start_index) {
            try out.append(alloc, 0);
        }
    }

    return try out.toOwnedSlice(alloc);
}

export fn grid_append_repl_output(bytes: [*]const u8, len: usize, is_error: i32) void {
    _ = is_error;
    var grid = &g_grids[1];
    grid.ensureInit(1);
    grid.appendOutputUtf8(bytes[0..len]);
}

export fn grid_append_repl_prompt(bytes: [*]const u8, len: usize) void {
    var grid = &g_grids[1];
    grid.ensureInit(1);
    grid.setPromptUtf8(bytes[0..len]);
}

export fn grid_copy_repl_history(out_len: *usize) ?[*]const u8 {
    var grid = &g_grids[1];
    grid.ensureInit(1);
    const owned = historyToNulSeparated(allocator, &grid.history) catch return null;
    out_len.* = owned.len;
    return owned.ptr;
}

export fn grid_free_bytes(bytes: ?[*]const u8, len: usize) void {
    const ptr = bytes orelse return;
    if (len == 0) return;
    const slice = @as([*]u8, @ptrCast(@constCast(ptr)))[0..len];
    allocator.free(slice);
}

export fn grid_restore_repl_history(bytes: [*]const u8, len: usize) void {
    var grid = &g_grids[1];
    grid.ensureInit(1);

    freeHistoryList(&grid.history);
    grid.history_cursor = 0;
    grid.clearSavedEntry();

    var start: usize = 0;
    var i: usize = 0;
    while (i <= len) : (i += 1) {
        if (i == len or bytes[i] == 0) {
            const item = bytes[start..i];
            if (item.len > 0) {
                grid.pushHistory(item);
            }
            start = i + 1;
        }
    }
    grid.resetHistoryCursor();
}

export fn grid_set_completions(prefix_bytes: [*]const u8, prefix_len: usize, words: ?[*]const [*:0]const u8, count: usize) void {
    var grid = &g_grids[1];
    grid.ensureInit(1);

    const prefix = prefix_bytes[0..prefix_len];
    var slices: std.ArrayListUnmanaged([]const u8) = .{};
    defer slices.deinit(allocator);

    if (words) |ptrs| {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const word_ptr = ptrs[i];
            const word = std.mem.span(word_ptr);
            slices.append(allocator, word) catch break;
        }
    }

    grid.setCompletions(prefix, slices.items);
    if (grid.completion_request_prefix) |pending| {
        allocator.free(pending);
        grid.completion_request_prefix = null;
    }

    const current_prefix = grid.extractCompletionPrefix();
    defer if (current_prefix) |buf| allocator.free(buf);
    if (current_prefix) |buf| {
        if (std.mem.eql(u8, buf, prefix)) {
            if (grid.completion_tab_count >= 2 and grid.completions.items.len > 1) {
                grid.completion_menu_visible = true;
            } else if (grid.completion_tab_count >= 1) {
                if (grid.applyCompletionResults(prefix)) {
                    grid.completion_tab_count = 0;
                    grid.completion_menu_visible = false;
                }
            }
        }
    }
}

export fn grid_paste_text(grid_id: i32, bytes: [*]const u8, len: usize) void {
    const id = clampGridId(grid_id);
    var grid = &g_grids[id];
    grid.ensureInit(id);
    pasteIntoGrid(grid, bytes[0..len]);
}

export fn grid_replace_text(grid_id: i32, bytes: [*]const u8, len: usize) void {
    const id = clampGridId(grid_id);
    var grid = &g_grids[id];
    grid.ensureInit(id);

    if (id == 0) {
        grid.replaceEditorUtf8(bytes[0..len]);
        return;
    }

    freeLineList(&grid.lines);
    appendEmptyLine(&grid.lines) catch return;
    decodeUtf8IntoLineList(&grid.lines, bytes[0..len]) catch return;
}

/// Store the current file path for the editor (grid 0). Copies the string.
export fn grid_set_editor_file_path(bytes: [*]const u8, len: usize) void {
    var grid = &g_grids[0];
    grid.ensureInit(0);
    if (grid.editor_file_path) |old| allocator.free(old);
    const path = allocator.dupe(u8, bytes[0..len]) catch {
        grid.editor_file_path = null;
        return;
    };
    grid.editor_file_path = path;
}

export fn grid_set_editor_modified(modified: i32) void {
    var grid = &g_grids[0];
    grid.ensureInit(0);
    grid.editor_modified = modified != 0;
}

export fn grid_get_editor_modified() i32 {
    const grid = &g_grids[0];
    if (!grid.initialized) return 0;
    return if (grid.editor_modified) 1 else 0;
}

/// Return the current editor file path as an allocated UTF-8 string.
/// Caller must free with grid_free_bytes.
export fn grid_get_editor_file_path(out_len: *usize) ?[*]const u8 {
    const grid = &g_grids[0];
    const path = grid.editor_file_path orelse {
        out_len.* = 0;
        return null;
    };
    const copy = allocator.dupe(u8, path) catch {
        out_len.* = 0;
        return null;
    };
    out_len.* = copy.len;
    return copy.ptr;
}

export fn grid_copy_text(grid_id: i32, out_len: *usize) ?[*]const u8 {
    const id = clampGridId(grid_id);
    var grid = &g_grids[id];
    grid.ensureInit(id);

    const owned = serializeGridDocument(grid) orelse return null;
    out_len.* = owned.len;
    return owned.ptr;
}

export fn grid_set_atlas_info(info: *const GlyphAtlasInfo) void {
    g_atlas = info.*;
}

export fn grid_on_resize(grid_id: i32, width: f32, height: f32, scale: f32) void {
    const id = clampGridId(grid_id);
    g_grids[id].ensureInit(id);
    g_grids[id].viewport_width = width;
    g_grids[id].viewport_height = height;
    g_grids[id].backing_scale = scale;
}

export fn grid_repl_set_terminal_size(cols: i32, rows: i32) void {
    _ = cols;
    _ = rows;
}

export fn grid_on_frame(grid_id: i32, dt: f64) EdFrameData {
    g_time += @as(f32, @floatCast(dt));

    const id = clampGridId(grid_id);
    var grid = &g_grids[id];
    grid.ensureInit(id);

    const theme = themeFor(id);
    grid.instances.clearRetainingCapacity();

    const cols = visibleCols(grid);
    const rows = visibleRows(grid);
    if (id == 1) {
        renderRepl(grid, theme, cols, rows);
    } else {
        renderEditor(grid, theme, cols, rows);
    }

    return .{
        .instances = if (grid.instances.items.len == 0) null else grid.instances.items.ptr,
        .instance_count = @as(u32, @intCast(grid.instances.items.len)),
        .uniforms = .{
            .viewport_width = if (grid.viewport_width > 0) grid.viewport_width else 1,
            .viewport_height = if (grid.viewport_height > 0) grid.viewport_height else 1,
            .cell_width = if (g_atlas.cell_width > 0) g_atlas.cell_width else 8,
            .cell_height = if (g_atlas.cell_height > 0) g_atlas.cell_height else 16,
            .atlas_width = if (g_atlas.atlas_width > 0) g_atlas.atlas_width else 128,
            .atlas_height = if (g_atlas.atlas_height > 0) g_atlas.atlas_height else 128,
            .time = g_time,
            .effects_mode = 0,
        },
        .clear_r = theme.clear[0],
        .clear_g = theme.clear[1],
        .clear_b = theme.clear[2],
        .clear_a = theme.clear[3],
    };
}

fn handleReplKeyDown(grid: *GridState, keycode: u32, mods: u32) void {
    if ((mods & Mods.CONTROL) != 0 and (mods & Mods.ALT) != 0 and keycode == Key.U) {
        grid.beginRepeatPrefix();
        return;
    }

    if (grid.repeat_collecting) {
        const repeat = grid.consumeRepeatCount();
        var i: usize = 0;
        while (i < repeat) : (i += 1) {
            handleReplKeyDown(grid, keycode, mods);
        }
        return;
    }

    if ((mods & Mods.CONTROL) != 0) {
        switch (keycode) {
            Key.A => {
                grid.entryMoveHome();
                return;
            },
            Key.B => {
                grid.entryMoveLeft();
                return;
            },
            Key.C, Key.G => {
                grid.clearEntry();
                if (keycode == Key.C) grid.resetHistoryCursor();
                return;
            },
            Key.D => {
                if (!grid.entryIsWhitespaceOnly()) grid.entryDeleteForward();
                return;
            },
            Key.E => {
                grid.entryMoveEnd();
                return;
            },
            Key.F => {
                grid.entryMoveRight();
                return;
            },
            Key.L => {
                grid.handleCtrlL();
                return;
            },
            Key.K => {
                grid.killToEndOfLine();
                return;
            },
            Key.N => {
                grid.entryMoveDown();
                return;
            },
            Key.P => {
                grid.entryMoveUp();
                return;
            },
            Key.SPACE, Key.TWO => {
                grid.setMark();
                return;
            },
            Key.U => {
                grid.killCurrentLine();
                return;
            },
            Key.W => {
                grid.killMarkedRegion();
                return;
            },
            Key.RIGHT_BRACKET => {
                grid.flashMatchingDelimiterNearCursor(false);
                return;
            },
            Key.Y => {
                grid.yankKillBuffer();
                return;
            },
            else => {},
        }
    }

    if ((mods & Mods.ALT) != 0) {
        switch (keycode) {
            Key.B => {
                grid.moveWordLeft();
                return;
            },
            Key.BACKSPACE => {
                grid.deleteSexpBackward();
                return;
            },
            Key.DELETE => {
                grid.deleteSexpForward();
                return;
            },
            Key.F => {
                grid.moveWordRight();
                return;
            },
            Key.N => {
                grid.historyPrefixSearch(true);
                return;
            },
            Key.P => {
                grid.historyPrefixSearch(false);
                return;
            },
            Key.Q => {
                grid.reindentAllEntryLines();
                return;
            },
            Key.RIGHT_BRACKET => {
                grid.flashMatchingDelimiterNearCursor(true);
                return;
            },
            else => {},
        }
    }

    switch (keycode) {
        Key.LEFT => grid.entryMoveLeft(),
        Key.RIGHT => grid.entryMoveRight(),
        Key.UP => grid.entryMoveUp(),
        Key.DOWN => grid.entryMoveDown(),
        Key.BACKSPACE => grid.entryBackspace(),
        Key.DELETE => grid.entryDeleteForward(),
        Key.HOME => grid.entryMoveHome(),
        Key.END => grid.entryMoveEnd(),
        Key.ENTER, Key.KEYPAD_ENTER => submitRepl(grid),
        Key.TAB => {
            if ((mods & Mods.ALT) != 0) {
                grid.reindentCurrentEntryLine();
            } else {
                grid.handleCompletionTab();
            }
        },
        else => {},
    }
}

export fn grid_on_key_down(grid_id: i32, keycode: u32, mods: u32) void {
    const id = clampGridId(grid_id);
    var grid = &g_grids[id];
    grid.ensureInit(id);

    if (id == 1) {
        handleReplKeyDown(grid, keycode, mods);
        return;
    }

    switch (keycode) {
        Key.LEFT => {
            grid.clearEditorSelection();
            if ((mods & Mods.CONTROL) != 0 and (mods & Mods.ALT) != 0)
                grid.editorBarfForward()
            else if ((mods & Mods.ALT) != 0)
                grid.editorMoveSexpBackward()
            else
                grid.editorMoveLeft();
        },
        Key.RIGHT => {
            grid.clearEditorSelection();
            if ((mods & Mods.CONTROL) != 0 and (mods & Mods.ALT) != 0)
                grid.editorSlurpForward()
            else if ((mods & Mods.ALT) != 0)
                grid.editorMoveSexpForward()
            else
                grid.editorMoveRight();
        },
        Key.UP => {
            if ((mods & Mods.CONTROL) != 0 and (mods & Mods.ALT) != 0) {
                grid.editorSpliceEnclosingForm();
            } else if ((mods & Mods.ALT) != 0) {
                grid.editorSelectEnclosingForm();
            } else {
                grid.clearEditorSelection();
                grid.editorMoveUp();
            }
        },
        Key.DOWN => {
            grid.clearEditorSelection();
            grid.editorMoveDown();
        },
        Key.BACKSPACE => {
            grid.clearEditorSelection();
            grid.editorBackspace();
        },
        Key.DELETE => {
            grid.clearEditorSelection();
            grid.editorDeleteForward();
        },
        Key.HOME => {
            grid.clearEditorSelection();
            grid.editorMoveHome();
        },
        Key.END => {
            grid.clearEditorSelection();
            grid.editorMoveEnd();
        },
        Key.ENTER, Key.KEYPAD_ENTER => {
            if ((mods & Mods.COMMAND) != 0) {
                grid.editorEvalTopLevelForm();
            } else {
                grid.clearEditorSelection();
                grid.insertEditorNewline();
            }
        },
        Key.TAB => {
            grid.clearEditorSelection();
            grid.editorIndentCurrentLine();
        },
        Key.Q => {
            if ((mods & Mods.ALT) != 0) grid.editorReindentSelectionOrCurrentLine();
        },
        Key.B => {
            if ((mods & Mods.COMMAND) != 0) grid.editorEvalBuffer();
        },
        Key.E => {
            if ((mods & Mods.COMMAND) != 0) {
                if (!grid.editorEvalSelection()) grid.editorEvalTopLevelForm();
            }
        },
        Key.Z => {
            if ((mods & Mods.COMMAND) != 0) {
                if ((mods & Mods.SHIFT) != 0)
                    grid.editorRedo()
                else
                    grid.editorUndo();
            }
        },
        else => {},
    }
}

export fn grid_on_text(grid_id: i32, codepoint: u32) void {
    const id = clampGridId(grid_id);
    var grid = &g_grids[id];
    grid.ensureInit(id);

    if (id == 1 and grid.appendRepeatDigit(codepoint)) return;

    if (id == 1 and grid.repeat_collecting) {
        const repeat = grid.consumeRepeatCount();
        var i: usize = 0;
        while (i < repeat) : (i += 1) {
            switch (codepoint) {
                0 => {},
                0x7f => grid.entryBackspace(),
                '\r', '\n' => submitRepl(grid),
                else => {
                    if (isDelimiter(codepoint)) {
                        replInsertDelimiter(grid, codepoint);
                    } else {
                        grid.entryInsertCodepoint(codepoint);
                    }
                },
            }
        }
        return;
    }

    switch (codepoint) {
        0 => {},
        0x7f => {
            if (id == 1) {
                grid.entryBackspace();
            } else {
                grid.clearEditorSelection();
                grid.editorBackspace();
            }
        },
        '\r', '\n' => {
            if (id == 1) {
                submitRepl(grid);
            } else {
                grid.clearEditorSelection();
                grid.insertEditorNewline();
            }
        },
        else => {
            if (id == 1) {
                if (isDelimiter(codepoint)) {
                    replInsertDelimiter(grid, codepoint);
                } else {
                    grid.entryInsertCodepoint(codepoint);
                }
            } else {
                switch (codepoint) {
                    '(' => {
                        if (!grid.editorWrapSelectionInParentheses()) {
                            grid.clearEditorSelection();
                            grid.editorTypedOpenDelimiter('(', ')');
                        }
                    },
                    '[' => {
                        grid.clearEditorSelection();
                        grid.editorTypedOpenDelimiter('[', ']');
                    },
                    '"' => {
                        grid.clearEditorSelection();
                        grid.editorTypedQuote();
                    },
                    ')' => {
                        grid.clearEditorSelection();
                        grid.editorTypedCloseOrSkip(')');
                    },
                    ']' => {
                        grid.clearEditorSelection();
                        grid.editorTypedCloseOrSkip(']');
                    },
                    else => {
                        grid.clearEditorSelection();
                        grid.insertEditorCodepoint(codepoint);
                    },
                }
            }
        },
    }
}

comptime {
    _ = grid_on_frame;
    _ = grid_on_key_down;
    _ = grid_on_resize;
    _ = grid_on_text;
    _ = grid_set_atlas_info;
    _ = grid_set_completions;
    _ = grid_set_editor_file_path;
    _ = grid_set_editor_modified;
    _ = grid_get_editor_file_path;
    _ = grid_get_editor_modified;
}
