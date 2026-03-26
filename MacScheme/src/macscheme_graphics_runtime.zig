extern fn ed_graphics_init() callconv(.c) void;
extern fn gfx_screen(width: f64, height: f64, scale: f64) callconv(.c) void;
extern fn gfx_screen_close() callconv(.c) void;
extern fn gfx_set_target(buffer: f64) callconv(.c) void;
extern fn gfx_pset(x: f64, y: f64, c: f64) callconv(.c) void;
extern fn gfx_pget(x: f64, y: f64) callconv(.c) f64;
extern fn gfx_line(x1: f64, y1: f64, x2: f64, y2: f64, c: f64) callconv(.c) void;
extern fn gfx_rect(x: f64, y: f64, w: f64, h: f64, index: f64, filled: f64) callconv(.c) void;
extern fn gfx_circle(cx: f64, cy: f64, r: f64, c: f64, filled: f64) callconv(.c) void;
extern fn gfx_ellipse(cx: f64, cy: f64, rx: f64, ry: f64, c: f64, filled: f64) callconv(.c) void;
extern fn gfx_triangle(x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64, c: f64, filled: f64) callconv(.c) void;
extern fn gfx_fill_area(x: f64, y: f64, c: f64) callconv(.c) void;
extern fn gfx_cls(index: f64) callconv(.c) void;
extern fn gfx_scroll_buffer(dx: f64, dy: f64, fill: f64) callconv(.c) void;
extern fn gfx_blit(dst: f64, dx: f64, dy: f64, src: f64, sx: f64, sy: f64, w: f64, h: f64) callconv(.c) void;
extern fn gfx_blit_solid(dst: f64, dx: f64, dy: f64, src: f64, sx: f64, sy: f64, w: f64, h: f64) callconv(.c) void;
extern fn gfx_blit_scale(dst: f64, dx: f64, dy: f64, dw: f64, dh: f64, src: f64, sx: f64, sy: f64, sw: f64, sh: f64) callconv(.c) void;
extern fn gfx_blit_flip(dst: f64, dx: f64, dy: f64, src: f64, sx: f64, sy: f64, w: f64, h: f64, mode: f64) callconv(.c) void;
extern fn gfx_palette(index: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_line_palette(line: f64, index: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_reset_palette() callconv(.c) void;
extern fn gfx_pal_cycle(slot: f64, start: f64, end_idx: f64, speed: f64, direction: f64) callconv(.c) void;
extern fn gfx_pal_cycle_lines(slot: f64, index: f64, ls: f64, le: f64, speed: f64, direction: f64) callconv(.c) void;
extern fn gfx_pal_fade(slot: f64, index: f64, speed: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_fade_lines(slot: f64, index: f64, ls: f64, le: f64, speed: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_pulse(slot: f64, index: f64, speed: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_pulse_lines(slot: f64, index: f64, ls: f64, le: f64, speed: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_gradient(slot: f64, idx: f64, ls: f64, le: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_strobe(slot: f64, index: f64, on: f64, off: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_strobe_lines(slot: f64, index: f64, ls: f64, le: f64, on: f64, off: f64, r1: f64, g1: f64, b1: f64, r2: f64, g2: f64, b2: f64) callconv(.c) void;
extern fn gfx_pal_stop(slot: f64) callconv(.c) void;
extern fn gfx_pal_stop_all() callconv(.c) void;
extern fn gfx_pal_pause(slot: f64) callconv(.c) void;
extern fn gfx_pal_resume(slot: f64) callconv(.c) void;
extern fn gfx_draw_text(x: f64, y: f64, desc: ?*const anyopaque, c: f64, font_id: f64) callconv(.c) f64;
extern fn gfx_draw_text_int(x: f64, y: f64, val: i64, c: f64, font_id: f64) callconv(.c) f64;
extern fn gfx_draw_text_double(x: f64, y: f64, val: f64, c: f64, font_id: f64) callconv(.c) f64;
extern fn gfx_text_width(desc: ?*const anyopaque, font_id: f64) callconv(.c) f64;
extern fn gfx_text_height(font_id: f64) callconv(.c) f64;
extern fn gfx_flip() callconv(.c) void;
extern fn gfx_vsync() callconv(.c) void;
extern fn gfx_wait_frames(n: f64) callconv(.c) void;
extern fn gfx_set_scroll(sx: f64, sy: f64) callconv(.c) void;
extern fn gfx_screen_width() callconv(.c) f64;
extern fn gfx_screen_height() callconv(.c) f64;
extern fn gfx_screen_active() callconv(.c) f64;
extern fn gfx_buffer_width() callconv(.c) f64;
extern fn gfx_buffer_height() callconv(.c) f64;
extern fn string_new_utf8(cstr: [*:0]const u8) callconv(.c) ?*anyopaque;
extern fn string_release(desc: ?*anyopaque) callconv(.c) void;

pub export fn macscheme_gfx_init() callconv(.c) void {
    ed_graphics_init();
}

pub export fn macscheme_gfx_screen(width: i64, height: i64, scale: i64) callconv(.c) void {
    gfx_screen(toF64ClampedU16(width), toF64ClampedU16(height), toF64ClampedU16(scale));
}

pub export fn macscheme_gfx_screen_close() callconv(.c) void {
    gfx_screen_close();
}

pub export fn macscheme_gfx_set_target(buffer: i64) callconv(.c) void {
    gfx_set_target(toF64ClampedBufferIndex(buffer));
}

pub export fn macscheme_gfx_pset(x: i64, y: i64, c: i64) callconv(.c) void {
    gfx_pset(toF64ClampedI32(x), toF64ClampedI32(y), toF64ClampedByte(c));
}

pub export fn macscheme_gfx_pget(x: i64, y: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_pget(toF64ClampedI32(x), toF64ClampedI32(y)));
}

pub export fn macscheme_gfx_line(x1: i64, y1: i64, x2: i64, y2: i64, c: i64) callconv(.c) void {
    gfx_line(toF64ClampedI32(x1), toF64ClampedI32(y1), toF64ClampedI32(x2), toF64ClampedI32(y2), toF64ClampedByte(c));
}

pub export fn macscheme_gfx_cls(index: i64) callconv(.c) void {
    gfx_cls(toF64ClampedByte(index));
}

pub export fn macscheme_gfx_rect(x: i64, y: i64, w: i64, h: i64, index: i64, filled: i64) callconv(.c) void {
    if (w <= 0 or h <= 0) return;
    gfx_rect(toF64ClampedI32(x), toF64ClampedI32(y), toF64ClampedI32(w - 1), toF64ClampedI32(h - 1), toF64ClampedByte(index), if (filled != 0) 1 else 0);
}

pub export fn macscheme_gfx_circle(cx: i64, cy: i64, r: i64, c: i64, filled: i64) callconv(.c) void {
    if (r < 0) return;
    gfx_circle(toF64ClampedI32(cx), toF64ClampedI32(cy), toF64ClampedI32(r), toF64ClampedByte(c), if (filled != 0) 1 else 0);
}

pub export fn macscheme_gfx_ellipse(cx: i64, cy: i64, rx: i64, ry: i64, c: i64, filled: i64) callconv(.c) void {
    if (rx < 0 or ry < 0) return;
    gfx_ellipse(toF64ClampedI32(cx), toF64ClampedI32(cy), toF64ClampedI32(rx), toF64ClampedI32(ry), toF64ClampedByte(c), if (filled != 0) 1 else 0);
}

pub export fn macscheme_gfx_triangle(x1: i64, y1: i64, x2: i64, y2: i64, x3: i64, y3: i64, c: i64, filled: i64) callconv(.c) void {
    gfx_triangle(toF64ClampedI32(x1), toF64ClampedI32(y1), toF64ClampedI32(x2), toF64ClampedI32(y2), toF64ClampedI32(x3), toF64ClampedI32(y3), toF64ClampedByte(c), if (filled != 0) 1 else 0);
}

pub export fn macscheme_gfx_fill_area(x: i64, y: i64, c: i64) callconv(.c) void {
    gfx_fill_area(toF64ClampedI32(x), toF64ClampedI32(y), toF64ClampedByte(c));
}

pub export fn macscheme_gfx_scroll_buffer(dx: i64, dy: i64, fill: i64) callconv(.c) void {
    gfx_scroll_buffer(toF64ClampedI32(dx), toF64ClampedI32(dy), toF64ClampedByte(fill));
}

pub export fn macscheme_gfx_blit(dst: i64, dx: i64, dy: i64, src: i64, sx: i64, sy: i64, w: i64, h: i64) callconv(.c) void {
    gfx_blit(toF64ClampedBufferIndex(dst), toF64ClampedI32(dx), toF64ClampedI32(dy), toF64ClampedBufferIndex(src), toF64ClampedI32(sx), toF64ClampedI32(sy), toF64ClampedNonNegativeI32(w), toF64ClampedNonNegativeI32(h));
}

pub export fn macscheme_gfx_blit_solid(dst: i64, dx: i64, dy: i64, src: i64, sx: i64, sy: i64, w: i64, h: i64) callconv(.c) void {
    gfx_blit_solid(toF64ClampedBufferIndex(dst), toF64ClampedI32(dx), toF64ClampedI32(dy), toF64ClampedBufferIndex(src), toF64ClampedI32(sx), toF64ClampedI32(sy), toF64ClampedNonNegativeI32(w), toF64ClampedNonNegativeI32(h));
}

pub export fn macscheme_gfx_blit_scale(dst: i64, dx: i64, dy: i64, dw: i64, dh: i64, src: i64, sx: i64, sy: i64, sw: i64, sh: i64) callconv(.c) void {
    gfx_blit_scale(toF64ClampedBufferIndex(dst), toF64ClampedI32(dx), toF64ClampedI32(dy), toF64ClampedNonNegativeI32(dw), toF64ClampedNonNegativeI32(dh), toF64ClampedBufferIndex(src), toF64ClampedI32(sx), toF64ClampedI32(sy), toF64ClampedNonNegativeI32(sw), toF64ClampedNonNegativeI32(sh));
}

pub export fn macscheme_gfx_blit_flip(dst: i64, dx: i64, dy: i64, src: i64, sx: i64, sy: i64, w: i64, h: i64, mode: i64) callconv(.c) void {
    gfx_blit_flip(toF64ClampedBufferIndex(dst), toF64ClampedI32(dx), toF64ClampedI32(dy), toF64ClampedBufferIndex(src), toF64ClampedI32(sx), toF64ClampedI32(sy), toF64ClampedNonNegativeI32(w), toF64ClampedNonNegativeI32(h), toF64ClampedByte(mode));
}

pub export fn macscheme_gfx_palette(index: i64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_palette(toF64ClampedByte(index), toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_line_palette(line: i64, index: i64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_line_palette(toF64ClampedU16(line), toF64ClampedNibble(index), toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_pal_cycle(slot: i64, start: i64, end_idx: i64, speed: i64, direction: i64) callconv(.c) void {
    gfx_pal_cycle(toF64ClampedEffectSlot(slot), toF64ClampedByte(start), toF64ClampedByte(end_idx), toF64ClampedPositive(speed), toF64Signed(direction));
}

pub export fn macscheme_gfx_pal_cycle_lines(slot: i64, index: i64, ls: i64, le: i64, speed: i64, direction: i64) callconv(.c) void {
    gfx_pal_cycle_lines(toF64ClampedEffectSlot(slot), toF64ClampedNibble(index), toF64ClampedU16(ls), toF64ClampedU16(le), toF64ClampedPositive(speed), toF64Signed(direction));
}

pub export fn macscheme_gfx_pal_fade(slot: i64, index: i64, speed: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_fade(toF64ClampedEffectSlot(slot), toF64ClampedByte(index), toF64ClampedPositive(speed), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_fade_lines(slot: i64, index: i64, ls: i64, le: i64, speed: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_fade_lines(toF64ClampedEffectSlot(slot), toF64ClampedNibble(index), toF64ClampedU16(ls), toF64ClampedU16(le), toF64ClampedPositive(speed), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_pulse(slot: i64, index: i64, speed: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_pulse(toF64ClampedEffectSlot(slot), toF64ClampedByte(index), toF64ClampedPositive(speed), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_pulse_lines(slot: i64, index: i64, ls: i64, le: i64, speed: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_pulse_lines(toF64ClampedEffectSlot(slot), toF64ClampedNibble(index), toF64ClampedU16(ls), toF64ClampedU16(le), toF64ClampedPositive(speed), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_gradient(slot: i64, idx: i64, ls: i64, le: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_gradient(toF64ClampedEffectSlot(slot), toF64ClampedNibble(idx), toF64ClampedU16(ls), toF64ClampedU16(le), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_strobe(slot: i64, index: i64, on: i64, off: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_strobe(toF64ClampedEffectSlot(slot), toF64ClampedByte(index), toF64ClampedPositive(on), toF64ClampedPositive(off), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_strobe_lines(slot: i64, index: i64, ls: i64, le: i64, on: i64, off: i64, r1: i64, g1: i64, b1: i64, r2: i64, g2: i64, b2: i64) callconv(.c) void {
    gfx_pal_strobe_lines(toF64ClampedEffectSlot(slot), toF64ClampedNibble(index), toF64ClampedU16(ls), toF64ClampedU16(le), toF64ClampedPositive(on), toF64ClampedPositive(off), toF64ClampedByte(r1), toF64ClampedByte(g1), toF64ClampedByte(b1), toF64ClampedByte(r2), toF64ClampedByte(g2), toF64ClampedByte(b2));
}

pub export fn macscheme_gfx_pal_stop(slot: i64) callconv(.c) void {
    gfx_pal_stop(toF64ClampedEffectSlot(slot));
}

pub export fn macscheme_gfx_pal_stop_all() callconv(.c) void {
    gfx_pal_stop_all();
}

pub export fn macscheme_gfx_pal_pause(slot: i64) callconv(.c) void {
    gfx_pal_pause(toF64ClampedEffectSlot(slot));
}

pub export fn macscheme_gfx_pal_resume(slot: i64) callconv(.c) void {
    gfx_pal_resume(toF64ClampedEffectSlot(slot));
}

pub export fn macscheme_gfx_draw_text(x: i64, y: i64, text: [*:0]const u8, c: i64, font_id: i64) callconv(.c) i64 {
    const desc = string_new_utf8(text) orelse return x;
    defer string_release(desc);
    return @intFromFloat(gfx_draw_text(toF64ClampedI32(x), toF64ClampedI32(y), desc, toF64ClampedByte(c), toF64ClampedFont(font_id)));
}

pub export fn macscheme_gfx_draw_text_int(x: i64, y: i64, val: i64, c: i64, font_id: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_draw_text_int(toF64ClampedI32(x), toF64ClampedI32(y), val, toF64ClampedByte(c), toF64ClampedFont(font_id)));
}

pub export fn macscheme_gfx_draw_text_double(x: i64, y: i64, val: f64, c: i64, font_id: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_draw_text_double(toF64ClampedI32(x), toF64ClampedI32(y), val, toF64ClampedByte(c), toF64ClampedFont(font_id)));
}

pub export fn macscheme_gfx_text_width(text: [*:0]const u8, font_id: i64) callconv(.c) i64 {
    const desc = string_new_utf8(text) orelse return 0;
    defer string_release(desc);
    return @intFromFloat(gfx_text_width(desc, toF64ClampedFont(font_id)));
}

pub export fn macscheme_gfx_text_height(font_id: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_text_height(toF64ClampedFont(font_id)));
}

pub export fn macscheme_gfx_flip() callconv(.c) void {
    gfx_flip();
}

pub export fn macscheme_gfx_vsync() callconv(.c) void {
    gfx_vsync();
}

pub export fn macscheme_gfx_wait_frames(n: i64) callconv(.c) void {
    gfx_wait_frames(toF64ClampedNonNegativeI32(n));
}

pub export fn macscheme_gfx_set_scroll(sx: i64, sy: i64) callconv(.c) void {
    gfx_set_scroll(toF64ClampedI32(sx), toF64ClampedI32(sy));
}

pub export fn macscheme_gfx_reset_palette() callconv(.c) void {
    gfx_reset_palette();
}

pub export fn macscheme_gfx_cycle(enabled: i64) callconv(.c) void {
    if (enabled != 0) {
        gfx_pal_cycle(0, 16, 31, 1, 1);
    } else {
        gfx_pal_stop_all();
    }
}

pub export fn macscheme_gfx_screen_width() callconv(.c) i64 {
    return @intFromFloat(gfx_screen_width());
}

pub export fn macscheme_gfx_screen_height() callconv(.c) i64 {
    return @intFromFloat(gfx_screen_height());
}

pub export fn macscheme_gfx_screen_active() callconv(.c) i64 {
    return @intFromFloat(gfx_screen_active());
}

pub export fn macscheme_gfx_buffer_width() callconv(.c) i64 {
    return @intFromFloat(gfx_buffer_width());
}

pub export fn macscheme_gfx_buffer_height() callconv(.c) i64 {
    return @intFromFloat(gfx_buffer_height());
}

fn toF64ClampedByte(value: i64) f64 {
    return @floatFromInt(@max(0, @min(255, value)));
}

fn toF64ClampedNibble(value: i64) f64 {
    return @floatFromInt(@max(0, @min(15, value)));
}

fn toF64ClampedU16(value: i64) f64 {
    return @floatFromInt(@max(0, @min(65535, value)));
}

fn toF64ClampedBufferIndex(value: i64) f64 {
    return @floatFromInt(@max(0, @min(7, value)));
}

fn toF64ClampedEffectSlot(value: i64) f64 {
    return @floatFromInt(@max(0, @min(31, value)));
}

fn toF64ClampedFont(value: i64) f64 {
    return @floatFromInt(@max(0, @min(1, value)));
}

fn toF64ClampedPositive(value: i64) f64 {
    return @floatFromInt(@max(1, @min(2147483647, value)));
}

fn toF64Signed(value: i64) f64 {
    return @floatFromInt(value);
}

fn toF64ClampedI32(value: i64) f64 {
    const min_i32: i64 = -2147483648;
    const max_i32: i64 = 2147483647;
    return @floatFromInt(@max(min_i32, @min(max_i32, value)));
}

fn toF64ClampedNonNegativeI32(value: i64) f64 {
    return @floatFromInt(@max(0, @min(2147483647, value)));
}

comptime {
    _ = macscheme_gfx_init;
    _ = macscheme_gfx_screen;
    _ = macscheme_gfx_screen_close;
    _ = macscheme_gfx_set_target;
    _ = macscheme_gfx_pset;
    _ = macscheme_gfx_pget;
    _ = macscheme_gfx_line;
    _ = macscheme_gfx_cls;
    _ = macscheme_gfx_rect;
    _ = macscheme_gfx_circle;
    _ = macscheme_gfx_ellipse;
    _ = macscheme_gfx_triangle;
    _ = macscheme_gfx_fill_area;
    _ = macscheme_gfx_scroll_buffer;
    _ = macscheme_gfx_blit;
    _ = macscheme_gfx_blit_solid;
    _ = macscheme_gfx_blit_scale;
    _ = macscheme_gfx_blit_flip;
    _ = macscheme_gfx_palette;
    _ = macscheme_gfx_line_palette;
    _ = macscheme_gfx_pal_cycle;
    _ = macscheme_gfx_pal_cycle_lines;
    _ = macscheme_gfx_pal_fade;
    _ = macscheme_gfx_pal_fade_lines;
    _ = macscheme_gfx_pal_pulse;
    _ = macscheme_gfx_pal_pulse_lines;
    _ = macscheme_gfx_pal_gradient;
    _ = macscheme_gfx_pal_strobe;
    _ = macscheme_gfx_pal_strobe_lines;
    _ = macscheme_gfx_pal_stop;
    _ = macscheme_gfx_pal_stop_all;
    _ = macscheme_gfx_pal_pause;
    _ = macscheme_gfx_pal_resume;
    _ = macscheme_gfx_draw_text;
    _ = macscheme_gfx_draw_text_int;
    _ = macscheme_gfx_draw_text_double;
    _ = macscheme_gfx_text_width;
    _ = macscheme_gfx_text_height;
    _ = macscheme_gfx_flip;
    _ = macscheme_gfx_vsync;
    _ = macscheme_gfx_wait_frames;
    _ = macscheme_gfx_set_scroll;
    _ = macscheme_gfx_reset_palette;
    _ = macscheme_gfx_cycle;
    _ = macscheme_gfx_screen_width;
    _ = macscheme_gfx_screen_height;
    _ = macscheme_gfx_screen_active;
    _ = macscheme_gfx_buffer_width;
    _ = macscheme_gfx_buffer_height;
}
