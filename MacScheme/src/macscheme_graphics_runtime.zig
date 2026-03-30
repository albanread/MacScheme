const std = @import("std");

const max_sprite_size: usize = 512;

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
extern fn gfx_inkey() callconv(.c) f64;
extern fn gfx_keydown(keycode: f64) callconv(.c) f64;
extern fn gfx_screen_width() callconv(.c) f64;
extern fn gfx_screen_height() callconv(.c) f64;
extern fn gfx_screen_active() callconv(.c) f64;
extern fn gfx_buffer_width() callconv(.c) f64;
extern fn gfx_buffer_height() callconv(.c) f64;
extern fn gfx_sprite_load(id: f64, desc: ?*const anyopaque) callconv(.c) void;
extern fn gfx_sprite_def(id: f64, w: f64, h: f64) callconv(.c) void;
extern fn gfx_sprite_data(id: f64, x: f64, y: f64, c: f64) callconv(.c) void;
extern fn gfx_sprite_commit(id: f64) callconv(.c) void;
extern fn gfx_sprite_row(row: f64, data: [*]const u8, count: f64) callconv(.c) void;
extern fn gfx_sprite_begin(id: f64) callconv(.c) void;
extern fn gfx_sprite_end() callconv(.c) void;
extern fn gfx_sprite_palette(id: f64, idx: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_sprite_std_pal(id: f64, pal_id: f64) callconv(.c) void;
extern fn gfx_sprite_frames(id: f64, fw: f64, fh: f64, count: f64) callconv(.c) void;
extern fn gfx_sprite_set_frame(frame: f64) callconv(.c) void;
extern fn gfx_sprite(inst: f64, def: f64, x: f64, y: f64) callconv(.c) void;
extern fn gfx_sprite_pos(inst: f64, x: f64, y: f64) callconv(.c) void;
extern fn gfx_sprite_move(inst: f64, dx: f64, dy: f64) callconv(.c) void;
extern fn gfx_sprite_rot(inst: f64, angle_deg: f64) callconv(.c) void;
extern fn gfx_sprite_scale(inst: f64, sx: f64, sy: f64) callconv(.c) void;
extern fn gfx_sprite_anchor(inst: f64, ax: f64, ay: f64) callconv(.c) void;
extern fn gfx_sprite_show(inst: f64) callconv(.c) void;
extern fn gfx_sprite_hide(inst: f64) callconv(.c) void;
extern fn gfx_sprite_flip(inst: f64, h: f64, v: f64) callconv(.c) void;
extern fn gfx_sprite_alpha(inst: f64, a: f64) callconv(.c) void;
extern fn gfx_sprite_frame(inst: f64, frame: f64) callconv(.c) void;
extern fn gfx_sprite_animate(inst: f64, speed: f64) callconv(.c) void;
extern fn gfx_sprite_priority(inst: f64, pri: f64) callconv(.c) void;
extern fn gfx_sprite_blend(inst: f64, mode: f64) callconv(.c) void;
extern fn gfx_sprite_remove(inst: f64) callconv(.c) void;
extern fn gfx_sprite_remove_all() callconv(.c) void;
extern fn gfx_sprite_fx(inst: f64, fx_type: f64) callconv(.c) void;
extern fn gfx_sprite_fx_param(inst: f64, p1: f64, p2: f64) callconv(.c) void;
extern fn gfx_sprite_fx_colour(inst: f64, r: f64, g: f64, b: f64, a: f64) callconv(.c) void;
extern fn gfx_sprite_glow(inst: f64, radius: f64, intensity: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_sprite_outline(inst: f64, thickness: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_sprite_shadow(inst: f64, ox: f64, oy: f64, r: f64, g: f64, b: f64, a: f64) callconv(.c) void;
extern fn gfx_sprite_tint(inst: f64, factor: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_sprite_flash(inst: f64, speed: f64, r: f64, g: f64, b: f64) callconv(.c) void;
extern fn gfx_sprite_fx_off(inst: f64) callconv(.c) void;
extern fn gfx_sprite_pal_override(inst: f64, def_id: f64) callconv(.c) void;
extern fn gfx_sprite_pal_reset(inst: f64) callconv(.c) void;
extern fn gfx_sprite_x(inst: f64) callconv(.c) f64;
extern fn gfx_sprite_y(inst: f64) callconv(.c) f64;
extern fn gfx_sprite_get_rot(inst: f64) callconv(.c) f64;
extern fn gfx_sprite_visible(inst: f64) callconv(.c) f64;
extern fn gfx_sprite_get_frame(inst: f64) callconv(.c) f64;
extern fn gfx_sprite_hit(a: f64, b: f64) callconv(.c) f64;
extern fn gfx_sprite_count() callconv(.c) f64;
extern fn gfx_sprite_collide(inst: f64, group: f64) callconv(.c) void;
extern fn gfx_sprite_overlap(grp_a: f64, grp_b: f64) callconv(.c) f64;
extern fn gfx_sprite_sync() callconv(.c) void;
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

pub export fn macscheme_gfx_inkey() callconv(.c) i64 {
    return @intFromFloat(gfx_inkey());
}

pub export fn macscheme_gfx_keydown(keycode: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_keydown(toF64ClampedByte(keycode)));
}

pub export fn macscheme_gfx_buffer_width() callconv(.c) i64 {
    return @intFromFloat(gfx_buffer_width());
}

pub export fn macscheme_gfx_buffer_height() callconv(.c) i64 {
    return @intFromFloat(gfx_buffer_height());
}

pub export fn macscheme_gfx_sprite_load(id: i64, path: [*:0]const u8) callconv(.c) void {
    const desc = string_new_utf8(path) orelse return;
    defer string_release(desc);
    gfx_sprite_load(toF64ClampedSpriteDefinition(id), desc);
}

pub export fn macscheme_gfx_sprite_def(id: i64, w: i64, h: i64) callconv(.c) void {
    gfx_sprite_def(toF64ClampedSpriteDefinition(id), toF64ClampedSpriteSize(w), toF64ClampedSpriteSize(h));
}

pub export fn macscheme_gfx_sprite_data(id: i64, x: i64, y: i64, c: i64) callconv(.c) void {
    gfx_sprite_data(toF64ClampedSpriteDefinition(id), toF64ClampedSpriteSize(x), toF64ClampedSpriteSize(y), toF64ClampedSpritePaletteIndex(c));
}

pub export fn macscheme_gfx_sprite_commit(id: i64) callconv(.c) void {
    gfx_sprite_commit(toF64ClampedSpriteDefinition(id));
}

pub export fn macscheme_gfx_sprite_row_ascii(row: i64, text: [*:0]const u8) callconv(.c) void {
    const source = std.mem.sliceTo(text, 0);
    if (source.len == 0) {
        gfx_sprite_row(toF64ClampedSpriteSize(row), &[_]u8{}, 0);
        return;
    }

    var pixels: [max_sprite_size]u8 = undefined;
    const count = @min(source.len, pixels.len);
    for (source[0..count], 0..) |ch, index| {
        pixels[index] = spriteAsciiToPaletteIndex(ch);
    }
    gfx_sprite_row(toF64ClampedSpriteSize(row), &pixels, @floatFromInt(count));
}

pub export fn macscheme_gfx_sprite_begin(id: i64) callconv(.c) void {
    gfx_sprite_begin(toF64ClampedSpriteDefinition(id));
}

pub export fn macscheme_gfx_sprite_end() callconv(.c) void {
    gfx_sprite_end();
}

pub export fn macscheme_gfx_sprite_palette(id: i64, idx: i64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_sprite_palette(toF64ClampedSpriteDefinition(id), toF64ClampedSpritePaletteIndex(idx), toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_sprite_std_pal(id: i64, pal_id: i64) callconv(.c) void {
    gfx_sprite_std_pal(toF64ClampedSpriteDefinition(id), toF64ClampedByte(pal_id));
}

pub export fn macscheme_gfx_sprite_frames(id: i64, fw: i64, fh: i64, count: i64) callconv(.c) void {
    gfx_sprite_frames(toF64ClampedSpriteDefinition(id), toF64ClampedSpriteSize(fw), toF64ClampedSpriteSize(fh), toF64ClampedU16(count));
}

pub export fn macscheme_gfx_sprite_set_frame(frame: i64) callconv(.c) void {
    gfx_sprite_set_frame(toF64ClampedU16(frame));
}

pub export fn macscheme_gfx_sprite(inst: i64, def: i64, x: f64, y: f64) callconv(.c) void {
    gfx_sprite(toF64ClampedSpriteInstance(inst), toF64ClampedSpriteDefinition(def), x, y);
}

pub export fn macscheme_gfx_sprite_pos(inst: i64, x: f64, y: f64) callconv(.c) void {
    gfx_sprite_pos(toF64ClampedSpriteInstance(inst), x, y);
}

pub export fn macscheme_gfx_sprite_move(inst: i64, dx: f64, dy: f64) callconv(.c) void {
    gfx_sprite_move(toF64ClampedSpriteInstance(inst), dx, dy);
}

pub export fn macscheme_gfx_sprite_rot(inst: i64, angle_deg: f64) callconv(.c) void {
    gfx_sprite_rot(toF64ClampedSpriteInstance(inst), angle_deg);
}

pub export fn macscheme_gfx_sprite_scale(inst: i64, sx: f64, sy: f64) callconv(.c) void {
    gfx_sprite_scale(toF64ClampedSpriteInstance(inst), sx, sy);
}

pub export fn macscheme_gfx_sprite_anchor(inst: i64, ax: f64, ay: f64) callconv(.c) void {
    gfx_sprite_anchor(toF64ClampedSpriteInstance(inst), ax, ay);
}

pub export fn macscheme_gfx_sprite_show(inst: i64) callconv(.c) void {
    gfx_sprite_show(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_hide(inst: i64) callconv(.c) void {
    gfx_sprite_hide(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_flip(inst: i64, h: i64, v: i64) callconv(.c) void {
    gfx_sprite_flip(toF64ClampedSpriteInstance(inst), if (h != 0) 1 else 0, if (v != 0) 1 else 0);
}

pub export fn macscheme_gfx_sprite_alpha(inst: i64, alpha: f64) callconv(.c) void {
    gfx_sprite_alpha(toF64ClampedSpriteInstance(inst), clampDouble(alpha, 0.0, 1.0));
}

pub export fn macscheme_gfx_sprite_frame(inst: i64, frame: i64) callconv(.c) void {
    gfx_sprite_frame(toF64ClampedSpriteInstance(inst), toF64ClampedU16(frame));
}

pub export fn macscheme_gfx_sprite_animate(inst: i64, speed: f64) callconv(.c) void {
    gfx_sprite_animate(toF64ClampedSpriteInstance(inst), speed);
}

pub export fn macscheme_gfx_sprite_priority(inst: i64, pri: i64) callconv(.c) void {
    gfx_sprite_priority(toF64ClampedSpriteInstance(inst), toF64ClampedNonNegativeI32(pri));
}

pub export fn macscheme_gfx_sprite_blend(inst: i64, mode: i64) callconv(.c) void {
    gfx_sprite_blend(toF64ClampedSpriteInstance(inst), if (mode != 0) 1 else 0);
}

pub export fn macscheme_gfx_sprite_remove(inst: i64) callconv(.c) void {
    gfx_sprite_remove(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_remove_all() callconv(.c) void {
    gfx_sprite_remove_all();
}

pub export fn macscheme_gfx_sprite_fx(inst: i64, fx_type: i64) callconv(.c) void {
    gfx_sprite_fx(toF64ClampedSpriteInstance(inst), toF64ClampedSpriteFxType(fx_type));
}

pub export fn macscheme_gfx_sprite_fx_param(inst: i64, p1: f64, p2: f64) callconv(.c) void {
    gfx_sprite_fx_param(toF64ClampedSpriteInstance(inst), p1, p2);
}

pub export fn macscheme_gfx_sprite_fx_colour(inst: i64, r: i64, g: i64, b: i64, a: i64) callconv(.c) void {
    gfx_sprite_fx_colour(toF64ClampedSpriteInstance(inst), toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b), toF64ClampedByte(a));
}

pub export fn macscheme_gfx_sprite_glow(inst: i64, radius: f64, intensity: f64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_sprite_glow(toF64ClampedSpriteInstance(inst), radius, intensity, toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_sprite_outline(inst: i64, thickness: f64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_sprite_outline(toF64ClampedSpriteInstance(inst), thickness, toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_sprite_shadow(inst: i64, ox: f64, oy: f64, r: i64, g: i64, b: i64, a: i64) callconv(.c) void {
    gfx_sprite_shadow(toF64ClampedSpriteInstance(inst), ox, oy, toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b), toF64ClampedByte(a));
}

pub export fn macscheme_gfx_sprite_tint(inst: i64, factor: f64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_sprite_tint(toF64ClampedSpriteInstance(inst), factor, toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_sprite_flash(inst: i64, speed: f64, r: i64, g: i64, b: i64) callconv(.c) void {
    gfx_sprite_flash(toF64ClampedSpriteInstance(inst), speed, toF64ClampedByte(r), toF64ClampedByte(g), toF64ClampedByte(b));
}

pub export fn macscheme_gfx_sprite_fx_off(inst: i64) callconv(.c) void {
    gfx_sprite_fx_off(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_pal_override(inst: i64, def_id: i64) callconv(.c) void {
    gfx_sprite_pal_override(toF64ClampedSpriteInstance(inst), toF64ClampedSpriteDefinition(def_id));
}

pub export fn macscheme_gfx_sprite_pal_reset(inst: i64) callconv(.c) void {
    gfx_sprite_pal_reset(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_x(inst: i64) callconv(.c) f64 {
    return gfx_sprite_x(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_y(inst: i64) callconv(.c) f64 {
    return gfx_sprite_y(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_rotation(inst: i64) callconv(.c) f64 {
    return gfx_sprite_get_rot(toF64ClampedSpriteInstance(inst));
}

pub export fn macscheme_gfx_sprite_visible(inst: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_sprite_visible(toF64ClampedSpriteInstance(inst)));
}

pub export fn macscheme_gfx_sprite_current_frame(inst: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_sprite_get_frame(toF64ClampedSpriteInstance(inst)));
}

pub export fn macscheme_gfx_sprite_hit(a: i64, b: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_sprite_hit(toF64ClampedSpriteInstance(a), toF64ClampedSpriteInstance(b)));
}

pub export fn macscheme_gfx_sprite_count() callconv(.c) i64 {
    return @intFromFloat(gfx_sprite_count());
}

pub export fn macscheme_gfx_sprite_collide(inst: i64, group: i64) callconv(.c) void {
    gfx_sprite_collide(toF64ClampedSpriteInstance(inst), toF64ClampedByte(group));
}

pub export fn macscheme_gfx_sprite_overlap(grp_a: i64, grp_b: i64) callconv(.c) i64 {
    return @intFromFloat(gfx_sprite_overlap(toF64ClampedByte(grp_a), toF64ClampedByte(grp_b)));
}

pub export fn macscheme_gfx_sprite_sync() callconv(.c) void {
    gfx_sprite_sync();
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

fn toF64ClampedSpriteDefinition(value: i64) f64 {
    return @floatFromInt(@max(0, @min(1023, value)));
}

fn toF64ClampedSpriteInstance(value: i64) f64 {
    return @floatFromInt(@max(0, @min(511, value)));
}

fn toF64ClampedSpriteSize(value: i64) f64 {
    return @floatFromInt(@max(0, @min(max_sprite_size, value)));
}

fn toF64ClampedSpritePaletteIndex(value: i64) f64 {
    return @floatFromInt(@max(0, @min(15, value)));
}

fn spriteAsciiToPaletteIndex(ch: u8) u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'A'...'F' => 10 + (ch - 'A'),
        'a'...'f' => 10 + (ch - 'a'),
        '.', ' ', '-', '_' => 0,
        else => 0,
    };
}

fn toF64ClampedSpriteFxType(value: i64) f64 {
    return @floatFromInt(@max(0, @min(6, value)));
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

fn clampDouble(value: f64, min_value: f64, max_value: f64) f64 {
    return std.math.clamp(value, min_value, max_value);
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
    _ = macscheme_gfx_inkey;
    _ = macscheme_gfx_keydown;
    _ = macscheme_gfx_buffer_width;
    _ = macscheme_gfx_buffer_height;
    _ = macscheme_gfx_sprite_load;
    _ = macscheme_gfx_sprite_def;
    _ = macscheme_gfx_sprite_data;
    _ = macscheme_gfx_sprite_commit;
    _ = macscheme_gfx_sprite_row_ascii;
    _ = macscheme_gfx_sprite_begin;
    _ = macscheme_gfx_sprite_end;
    _ = macscheme_gfx_sprite_palette;
    _ = macscheme_gfx_sprite_std_pal;
    _ = macscheme_gfx_sprite_frames;
    _ = macscheme_gfx_sprite_set_frame;
    _ = macscheme_gfx_sprite;
    _ = macscheme_gfx_sprite_pos;
    _ = macscheme_gfx_sprite_move;
    _ = macscheme_gfx_sprite_rot;
    _ = macscheme_gfx_sprite_scale;
    _ = macscheme_gfx_sprite_anchor;
    _ = macscheme_gfx_sprite_show;
    _ = macscheme_gfx_sprite_hide;
    _ = macscheme_gfx_sprite_flip;
    _ = macscheme_gfx_sprite_alpha;
    _ = macscheme_gfx_sprite_frame;
    _ = macscheme_gfx_sprite_animate;
    _ = macscheme_gfx_sprite_priority;
    _ = macscheme_gfx_sprite_blend;
    _ = macscheme_gfx_sprite_remove;
    _ = macscheme_gfx_sprite_remove_all;
    _ = macscheme_gfx_sprite_fx;
    _ = macscheme_gfx_sprite_fx_param;
    _ = macscheme_gfx_sprite_fx_colour;
    _ = macscheme_gfx_sprite_glow;
    _ = macscheme_gfx_sprite_outline;
    _ = macscheme_gfx_sprite_shadow;
    _ = macscheme_gfx_sprite_tint;
    _ = macscheme_gfx_sprite_flash;
    _ = macscheme_gfx_sprite_fx_off;
    _ = macscheme_gfx_sprite_pal_override;
    _ = macscheme_gfx_sprite_pal_reset;
    _ = macscheme_gfx_sprite_x;
    _ = macscheme_gfx_sprite_y;
    _ = macscheme_gfx_sprite_rotation;
    _ = macscheme_gfx_sprite_visible;
    _ = macscheme_gfx_sprite_current_frame;
    _ = macscheme_gfx_sprite_hit;
    _ = macscheme_gfx_sprite_count;
    _ = macscheme_gfx_sprite_collide;
    _ = macscheme_gfx_sprite_overlap;
    _ = macscheme_gfx_sprite_sync;
}
