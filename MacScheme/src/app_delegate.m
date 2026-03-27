#import "app_delegate.h"
#import <MetalKit/MetalKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <WebKit/WebKit.h>
#include <signal.h>
#include <unistd.h>
#include <pthread.h>
#include <semaphore.h>
#import "scheme_text_grid.h"
#include "scheme.h"

// ---------------------------------------------------------------------------
// Scheme eval thread state
// A single persistent pthread owns all Chez Scheme API calls.
// macscheme_eval_async enqueues work here and signals g_scheme_sem.
// ---------------------------------------------------------------------------

typedef NS_ENUM(uint8_t, SchemeRequestKind) {
    SchemeRequestEval = 0,
    SchemeRequestCompletions = 1,
};

typedef struct EvalRequest {
    SchemeRequestKind kind;
    char *expr;           // heap-allocated UTF-8 string (caller frees after dequeue)
    struct EvalRequest *next;
} EvalRequest;

static pthread_t        g_scheme_thread;
static sem_t           *g_scheme_sem   = NULL;
static pthread_mutex_t  g_queue_mutex  = PTHREAD_MUTEX_INITIALIZER;
static EvalRequest     *g_queue_head   = NULL;
static EvalRequest     *g_queue_tail   = NULL;
static volatile sig_atomic_t g_scheme_eval_active = 0;

static void scheme_enqueue(SchemeRequestKind kind, const char *utf8, size_t len) {
    EvalRequest *req = (EvalRequest *)malloc(sizeof(EvalRequest));
    req->kind = kind;
    req->expr = (char *)malloc(len + 1);
    memcpy(req->expr, utf8, len);
    req->expr[len] = '\0';
    req->next = NULL;

    pthread_mutex_lock(&g_queue_mutex);
    if (g_queue_tail) {
        g_queue_tail->next = req;
    } else {
        g_queue_head = req;
    }
    g_queue_tail = req;
    pthread_mutex_unlock(&g_queue_mutex);

    sem_post(g_scheme_sem);
}

static EvalRequest *scheme_dequeue(void) {
    pthread_mutex_lock(&g_queue_mutex);
    EvalRequest *req = g_queue_head;
    if (req) {
        g_queue_head = req->next;
        if (!g_queue_head) g_queue_tail = NULL;
    }
    pthread_mutex_unlock(&g_queue_mutex);
    return req;
}

// Forward declaration — defined below after the AppDelegate interface.
static void *scheme_thread_entry(void *arg);

extern void grid_append_repl_output(const unsigned char *bytes, size_t len, int is_error);
extern void grid_append_repl_prompt(const unsigned char *bytes, size_t len);
extern void grid_set_completions(const unsigned char *prefix_bytes, size_t prefix_len, const char * const *words, size_t count);
extern const unsigned char *grid_copy_repl_history(size_t *out_len);
extern void grid_free_bytes(const unsigned char *bytes, size_t len);
extern void grid_restore_repl_history(const unsigned char *bytes, size_t len);
extern uint64_t grid_get_editor_change_serial(void);
extern void grid_run_editor_syntax_check(uint64_t revision);

// MacScheme graphics runtime exports.
extern void macscheme_gfx_init(void);
extern void macscheme_gfx_screen(int64_t w, int64_t h, int64_t scale);
extern void macscheme_gfx_screen_close(void);
extern void macscheme_gfx_set_target(int64_t buffer);
extern void macscheme_gfx_pset(int64_t x, int64_t y, int64_t c);
extern int64_t macscheme_gfx_pget(int64_t x, int64_t y);
extern void macscheme_gfx_line(int64_t x1, int64_t y1, int64_t x2, int64_t y2, int64_t c);
extern void macscheme_gfx_cls(int64_t c);
extern void macscheme_gfx_rect(int64_t x, int64_t y, int64_t w, int64_t h, int64_t c, int64_t filled);
extern void macscheme_gfx_circle(int64_t cx, int64_t cy, int64_t r, int64_t c, int64_t filled);
extern void macscheme_gfx_ellipse(int64_t cx, int64_t cy, int64_t rx, int64_t ry, int64_t c, int64_t filled);
extern void macscheme_gfx_triangle(int64_t x1, int64_t y1, int64_t x2, int64_t y2, int64_t x3, int64_t y3, int64_t c, int64_t filled);
extern void macscheme_gfx_fill_area(int64_t x, int64_t y, int64_t c);
extern void macscheme_gfx_scroll_buffer(int64_t dx, int64_t dy, int64_t fill);
extern void macscheme_gfx_blit(int64_t dst, int64_t dx, int64_t dy, int64_t src, int64_t sx, int64_t sy, int64_t w, int64_t h);
extern void macscheme_gfx_blit_solid(int64_t dst, int64_t dx, int64_t dy, int64_t src, int64_t sx, int64_t sy, int64_t w, int64_t h);
extern void macscheme_gfx_blit_scale(int64_t dst, int64_t dx, int64_t dy, int64_t dw, int64_t dh, int64_t src, int64_t sx, int64_t sy, int64_t sw, int64_t sh);
extern void macscheme_gfx_blit_flip(int64_t dst, int64_t dx, int64_t dy, int64_t src, int64_t sx, int64_t sy, int64_t w, int64_t h, int64_t mode);
extern void macscheme_gfx_palette(int64_t idx, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_line_palette(int64_t line, int64_t idx, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_pal_cycle(int64_t slot, int64_t start, int64_t end_idx, int64_t speed, int64_t direction);
extern void macscheme_gfx_pal_cycle_lines(int64_t slot, int64_t index, int64_t ls, int64_t le, int64_t speed, int64_t direction);
extern void macscheme_gfx_pal_fade(int64_t slot, int64_t index, int64_t speed, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_fade_lines(int64_t slot, int64_t index, int64_t ls, int64_t le, int64_t speed, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_pulse(int64_t slot, int64_t index, int64_t speed, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_pulse_lines(int64_t slot, int64_t index, int64_t ls, int64_t le, int64_t speed, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_gradient(int64_t slot, int64_t idx, int64_t ls, int64_t le, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_strobe(int64_t slot, int64_t index, int64_t on, int64_t off, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_strobe_lines(int64_t slot, int64_t index, int64_t ls, int64_t le, int64_t on, int64_t off, int64_t r1, int64_t g1, int64_t b1, int64_t r2, int64_t g2, int64_t b2);
extern void macscheme_gfx_pal_stop(int64_t slot);
extern void macscheme_gfx_pal_stop_all(void);
extern void macscheme_gfx_pal_pause(int64_t slot);
extern void macscheme_gfx_pal_resume(int64_t slot);
extern void macscheme_gfx_reset_palette(void);
extern int64_t macscheme_gfx_draw_text(int64_t x, int64_t y, const char *text, int64_t c, int64_t font_id);
extern int64_t macscheme_gfx_draw_text_int(int64_t x, int64_t y, int64_t val, int64_t c, int64_t font_id);
extern int64_t macscheme_gfx_draw_text_double(int64_t x, int64_t y, double val, int64_t c, int64_t font_id);
extern int64_t macscheme_gfx_text_width(const char *text, int64_t font_id);
extern int64_t macscheme_gfx_text_height(int64_t font_id);
extern void macscheme_gfx_flip(void);
extern void macscheme_gfx_vsync(void);
extern void macscheme_gfx_wait_frames(int64_t n);
extern void macscheme_gfx_set_scroll(int64_t sx, int64_t sy);
extern void macscheme_gfx_cycle(int64_t enabled);
extern int64_t macscheme_gfx_screen_width(void);
extern int64_t macscheme_gfx_screen_height(void);
extern int64_t macscheme_gfx_screen_active(void);
extern int64_t macscheme_gfx_inkey(void);
extern int64_t macscheme_gfx_keydown(int64_t keycode);
extern int64_t macscheme_gfx_buffer_width(void);
extern int64_t macscheme_gfx_buffer_height(void);
extern void macscheme_gfx_sprite_load(int64_t id, const char *path);
extern void macscheme_gfx_sprite_def(int64_t id, int64_t w, int64_t h);
extern void macscheme_gfx_sprite_data(int64_t id, int64_t x, int64_t y, int64_t c);
extern void macscheme_gfx_sprite_commit(int64_t id);
extern void macscheme_gfx_sprite_row_ascii(int64_t row, const char *text);
extern void macscheme_gfx_sprite_begin(int64_t id);
extern void macscheme_gfx_sprite_end(void);
extern void macscheme_gfx_sprite_palette(int64_t id, int64_t idx, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_sprite_std_pal(int64_t id, int64_t pal_id);
extern void macscheme_gfx_sprite_frames(int64_t id, int64_t fw, int64_t fh, int64_t count);
extern void macscheme_gfx_sprite_set_frame(int64_t frame);
extern void macscheme_gfx_sprite(int64_t inst, int64_t def, double x, double y);
extern void macscheme_gfx_sprite_pos(int64_t inst, double x, double y);
extern void macscheme_gfx_sprite_move(int64_t inst, double dx, double dy);
extern void macscheme_gfx_sprite_rot(int64_t inst, double angle_deg);
extern void macscheme_gfx_sprite_scale(int64_t inst, double sx, double sy);
extern void macscheme_gfx_sprite_anchor(int64_t inst, double ax, double ay);
extern void macscheme_gfx_sprite_show(int64_t inst);
extern void macscheme_gfx_sprite_hide(int64_t inst);
extern void macscheme_gfx_sprite_flip(int64_t inst, int64_t h, int64_t v);
extern void macscheme_gfx_sprite_alpha(int64_t inst, double alpha);
extern void macscheme_gfx_sprite_frame(int64_t inst, int64_t frame);
extern void macscheme_gfx_sprite_animate(int64_t inst, double speed);
extern void macscheme_gfx_sprite_priority(int64_t inst, int64_t pri);
extern void macscheme_gfx_sprite_blend(int64_t inst, int64_t mode);
extern void macscheme_gfx_sprite_remove(int64_t inst);
extern void macscheme_gfx_sprite_remove_all(void);
extern void macscheme_gfx_sprite_fx(int64_t inst, int64_t fx_type);
extern void macscheme_gfx_sprite_fx_param(int64_t inst, double p1, double p2);
extern void macscheme_gfx_sprite_fx_colour(int64_t inst, int64_t r, int64_t g, int64_t b, int64_t a);
extern void macscheme_gfx_sprite_glow(int64_t inst, double radius, double intensity, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_sprite_outline(int64_t inst, double thickness, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_sprite_shadow(int64_t inst, double ox, double oy, int64_t r, int64_t g, int64_t b, int64_t a);
extern void macscheme_gfx_sprite_tint(int64_t inst, double factor, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_sprite_flash(int64_t inst, double speed, int64_t r, int64_t g, int64_t b);
extern void macscheme_gfx_sprite_fx_off(int64_t inst);
extern void macscheme_gfx_sprite_pal_override(int64_t inst, int64_t def_id);
extern void macscheme_gfx_sprite_pal_reset(int64_t inst);
extern double macscheme_gfx_sprite_x(int64_t inst);
extern double macscheme_gfx_sprite_y(int64_t inst);
extern double macscheme_gfx_sprite_rotation(int64_t inst);
extern int64_t macscheme_gfx_sprite_visible(int64_t inst);
extern int64_t macscheme_gfx_sprite_current_frame(int64_t inst);
extern int64_t macscheme_gfx_sprite_hit(int64_t a, int64_t b);
extern int64_t macscheme_gfx_sprite_count(void);
extern void macscheme_gfx_sprite_collide(int64_t inst, int64_t group);
extern int64_t macscheme_gfx_sprite_overlap(int64_t grp_a, int64_t grp_b);
extern void macscheme_gfx_sprite_sync(void);
extern void gfx_set_host_view(void *ns_view);

// MacScheme audio runtime exports.
extern double snd_init(void);
extern void snd_shutdown(void);
extern double snd_is_init(void);
extern void snd_stop_all(void);
extern double snd_beep(double freq, double dur);
extern double snd_zap(double freq, double dur);
extern double snd_explode(double size, double dur);
extern double snd_big_explosion(double size, double dur);
extern double snd_small_explosion(double intensity, double dur);
extern double snd_distant_explosion(double distance, double dur);
extern double snd_metal_explosion(double shrapnel, double dur);
extern double snd_bang(double intensity, double dur);
extern double snd_coin(double pitch, double dur);
extern double snd_jump(double power, double dur);
extern double snd_powerup(double intensity, double dur);
extern double snd_hurt(double severity, double dur);
extern double snd_shoot(double power, double dur);
extern double snd_click(double sharpness, double dur);
extern double snd_blip(double pitch, double dur);
extern double snd_pickup(double brightness, double dur);
extern double snd_sweep_up(double start_freq, double end_freq, double dur);
extern double snd_sweep_down(double start_freq, double end_freq, double dur);
extern double snd_random_beep(double seed, double dur);
extern double snd_tone(double freq, double dur, double wave);
extern double snd_note(double midi, double dur, double wave, double a, double d, double s, double r);
extern double snd_noise(double noise_type, double dur);
extern double snd_fm(double carrier, double modulator, double index, double dur);
extern double snd_filtered_tone(double freq, double dur, double wave, double ftype, double cutoff, double reso);
extern double snd_filtered_note(double midi, double dur, double wave, double a, double d, double s, double r, double ftype, double cutoff, double reso);
extern double snd_reverb(double freq, double dur, double wave, double room, double damp, double wet);
extern double snd_delay(double freq, double dur, double wave, double time, double feedback, double mix);
extern double snd_distortion(double freq, double dur, double wave, double drive, double tone_val, double level);
extern void snd_play(double id, double vol, double pan);
extern void snd_play_simple(double id);
extern void snd_stop(void);
extern void snd_stop_one(double id);
extern double snd_is_playing(double id);
extern double snd_get_duration(double id);
extern double snd_free(double id);
extern void snd_free_all(void);
extern void snd_set_volume(double vol);
extern double snd_get_volume(void);
extern double snd_exists(double id);
extern double snd_count(void);
extern double snd_mem(void);
extern double snd_note_to_freq(double midi);
extern double snd_freq_to_note(double freq);
extern double snd_export_wav(double id, void *filename_desc, double vol);
extern double scheme_snd_export_wav(double id, const char *filename, double vol);
extern void mus_play(void *abc_desc, double vol);
extern void mus_play_simple(void *abc_desc);
extern double mus_load(void *abc_desc);
extern double mus_load_compiled(void *blob_ptr, double blob_size);
extern void mus_play_id(double id, double vol);
extern void mus_play_id_simple(double id);
extern void mus_stop(void);
extern void mus_pause(void);
extern void mus_resume(void);
extern void mus_set_volume(double vol);
extern double mus_get_volume(void);
extern double mus_free(double id);
extern void mus_free_all(void);
extern double mus_is_playing(void);
extern double mus_is_playing_id(double id);
extern double mus_state(void);
extern double mus_exists(double id);
extern double mus_count(void);
extern double mus_mem(void);
extern void *mus_get_title(double id);
extern void *mus_get_composer(double id);
extern void *mus_get_key(double id);
extern double mus_get_tempo(double id);
extern void *mus_get_compiled_blob_info(double id);
extern double mus_render(void *abc_desc, double dur, double sr);
extern double mus_render_simple(void *abc_desc);
extern double mus_render_wav(void *abc_desc, void *filename_desc, double dur, double sr);
extern double mus_export_midi(double id, void *filename_desc);
extern void scheme_mus_play(const char *abc, double vol);
extern void scheme_mus_play_simple(const char *abc);
extern double scheme_mus_load(const char *abc);
extern double scheme_mus_render(const char *abc, double dur, double sr);
extern double scheme_mus_render_simple(const char *abc);
extern double scheme_mus_render_wav(const char *abc, const char *filename, double dur, double sr);
extern double scheme_mus_export_midi(double id, const char *filename);

static AppDelegate *g_app_delegate = nil;

typedef NS_ENUM(NSInteger, MacSchemePane) {
    MacSchemePaneEditor = 0,
    MacSchemePaneRepl = 1,
    MacSchemePaneGraphics = 2,
};

typedef NS_ENUM(NSInteger, MacSchemeLayoutPreset) {
    MacSchemeLayoutPresetCustom = 0,
    MacSchemeLayoutPresetBalanced = 1,
    MacSchemeLayoutPresetEditorRepl = 2,
    MacSchemeLayoutPresetEditorGraphics = 3,
    MacSchemeLayoutPresetFocusEditor = 4,
    MacSchemeLayoutPresetFocusRepl = 5,
    MacSchemeLayoutPresetFocusGraphics = 6,
};

static const CGFloat kMacSchemeBalancedMainRatio = 0.60;
static const CGFloat kMacSchemeBalancedRightRatio = 0.525;
static const CGFloat kMacSchemeEditorReplMainRatio = 0.68;
static const CGFloat kMacSchemeEditorGraphicsMainRatio = 0.56;

static CGFloat ClampSplitRatio(CGFloat ratio) {
    if (ratio < 0.15) return 0.15;
    if (ratio > 0.85) return 0.85;
    return ratio;
}

static void MacSchemeActivateApplication(void) {
    if (@available(macOS 14.0, *)) {
        [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateAllWindows];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    }
}

static void MacSchemeDispatchSyncOnMain(dispatch_block_t block) {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static CGFloat FirstSplitSubviewExtent(NSSplitView *splitView) {
    NSArray<NSView *> *subviews = splitView.subviews;
    if (subviews.count < 2) return 0.0;
    NSView *first = subviews.firstObject;
    return splitView.isVertical ? first.frame.size.width : first.frame.size.height;
}

static NSArray<NSString *> *MacSchemeAllowedFileExtensions(void) {
    static NSArray<NSString *> *extensions = nil;
    if (!extensions) {
        extensions = @[@"ss", @"scm"];
    }
    return extensions;
}

static NSString *MacSchemeHistoryPath(void) {
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [appSupport stringByAppendingPathComponent:@"MacScheme"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"repl-history.bin"];
}

static void LoadPersistedReplHistory(void) {
    NSData *data = [NSData dataWithContentsOfFile:MacSchemeHistoryPath()];
    if (data.length == 0) return;
    grid_restore_repl_history((const unsigned char *)data.bytes, data.length);
}

static void SavePersistedReplHistory(void) {
    size_t len = 0;
    const unsigned char *bytes = grid_copy_repl_history(&len);
    if (!bytes || len == 0) return;
    NSData *data = [NSData dataWithBytes:bytes length:len];
    grid_free_bytes(bytes, len);
    [data writeToFile:MacSchemeHistoryPath() atomically:YES];
}

static NSString *MacSchemeGraphicsBootstrapSource(void) {
    return @"(begin "
           "(define macscheme-layout-set "
           "  (foreign-procedure \"macscheme_layout_set\" (integer-64) integer-64)) "
           "(define macscheme-layout-show-pane "
           "  (foreign-procedure \"macscheme_layout_show_pane\" (integer-64) integer-64)) "
           "(define macscheme-layout-hide-pane "
           "  (foreign-procedure \"macscheme_layout_hide_pane\" (integer-64) integer-64)) "
           "(define macscheme-layout-toggle-pane "
           "  (foreign-procedure \"macscheme_layout_toggle_pane\" (integer-64) integer-64)) "
           "(define macscheme-layout-reset "
           "  (foreign-procedure \"macscheme_layout_reset\" () integer-64)) "
           "(define macscheme-layout-current "
           "  (foreign-procedure \"macscheme_layout_current\" () integer-64)) "
           "(define macscheme-layout-pane-visible "
           "  (foreign-procedure \"macscheme_layout_pane_visible\" (integer-64) integer-64)) "
           "(define macscheme-gfx-init "
           "  (foreign-procedure \"macscheme_gfx_init\" () void)) "
           "(define macscheme-gfx-screen "
           "  (foreign-procedure \"macscheme_gfx_screen\" (integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-screen-close "
           "  (foreign-procedure \"macscheme_gfx_screen_close\" () void)) "
           "(define macscheme-gfx-set-target "
           "  (foreign-procedure \"macscheme_gfx_set_target\" (integer-64) void)) "
           "(define macscheme-gfx-pset "
           "  (foreign-procedure \"macscheme_gfx_pset\" (integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pget "
           "  (foreign-procedure \"macscheme_gfx_pget\" (integer-64 integer-64) integer-64)) "
           "(define macscheme-gfx-line "
           "  (foreign-procedure \"macscheme_gfx_line\" (integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-cls "
           "  (foreign-procedure \"macscheme_gfx_cls\" (integer-64) void)) "
           "(define macscheme-gfx-rect "
           "  (foreign-procedure \"macscheme_gfx_rect\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-circle "
           "  (foreign-procedure \"macscheme_gfx_circle\" (integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-ellipse "
           "  (foreign-procedure \"macscheme_gfx_ellipse\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-triangle "
           "  (foreign-procedure \"macscheme_gfx_triangle\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-fill-area "
           "  (foreign-procedure \"macscheme_gfx_fill_area\" (integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-scroll-buffer "
           "  (foreign-procedure \"macscheme_gfx_scroll_buffer\" (integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-blit "
           "  (foreign-procedure \"macscheme_gfx_blit\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-blit-solid "
           "  (foreign-procedure \"macscheme_gfx_blit_solid\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-blit-scale "
           "  (foreign-procedure \"macscheme_gfx_blit_scale\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-blit-flip "
           "  (foreign-procedure \"macscheme_gfx_blit_flip\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-palette "
           "  (foreign-procedure \"macscheme_gfx_palette\" (integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-line-palette "
           "  (foreign-procedure \"macscheme_gfx_line_palette\" (integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-cycle "
           "  (foreign-procedure \"macscheme_gfx_pal_cycle\" (integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-cycle-lines "
           "  (foreign-procedure \"macscheme_gfx_pal_cycle_lines\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-fade "
           "  (foreign-procedure \"macscheme_gfx_pal_fade\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-fade-lines "
           "  (foreign-procedure \"macscheme_gfx_pal_fade_lines\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-pulse "
           "  (foreign-procedure \"macscheme_gfx_pal_pulse\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-pulse-lines "
           "  (foreign-procedure \"macscheme_gfx_pal_pulse_lines\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-gradient "
           "  (foreign-procedure \"macscheme_gfx_pal_gradient\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-strobe "
           "  (foreign-procedure \"macscheme_gfx_pal_strobe\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-strobe-lines "
           "  (foreign-procedure \"macscheme_gfx_pal_strobe_lines\" (integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-pal-stop "
           "  (foreign-procedure \"macscheme_gfx_pal_stop\" (integer-64) void)) "
           "(define macscheme-gfx-pal-stop-all "
           "  (foreign-procedure \"macscheme_gfx_pal_stop_all\" () void)) "
           "(define macscheme-gfx-pal-pause "
           "  (foreign-procedure \"macscheme_gfx_pal_pause\" (integer-64) void)) "
           "(define macscheme-gfx-pal-resume "
           "  (foreign-procedure \"macscheme_gfx_pal_resume\" (integer-64) void)) "
           "(define macscheme-gfx-reset-palette "
           "  (foreign-procedure \"macscheme_gfx_reset_palette\" () void)) "
           "(define macscheme-gfx-draw-text "
           "  (foreign-procedure \"macscheme_gfx_draw_text\" (integer-64 integer-64 string integer-64 integer-64) integer-64)) "
           "(define macscheme-gfx-draw-text-int "
           "  (foreign-procedure \"macscheme_gfx_draw_text_int\" (integer-64 integer-64 integer-64 integer-64 integer-64) integer-64)) "
           "(define macscheme-gfx-draw-text-double "
           "  (foreign-procedure \"macscheme_gfx_draw_text_double\" (integer-64 integer-64 double-float integer-64 integer-64) integer-64)) "
           "(define macscheme-gfx-text-width "
           "  (foreign-procedure \"macscheme_gfx_text_width\" (string integer-64) integer-64)) "
           "(define macscheme-gfx-text-height "
           "  (foreign-procedure \"macscheme_gfx_text_height\" (integer-64) integer-64)) "
           "(define macscheme-gfx-flip "
           "  (foreign-procedure \"macscheme_gfx_flip\" () void)) "
           "(define macscheme-gfx-vsync "
           "  (foreign-procedure \"macscheme_gfx_vsync\" () void)) "
           "(define macscheme-gfx-wait-frames "
           "  (foreign-procedure \"macscheme_gfx_wait_frames\" (integer-64) void)) "
           "(define macscheme-gfx-set-scroll "
           "  (foreign-procedure \"macscheme_gfx_set_scroll\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-cycle "
           "  (foreign-procedure \"macscheme_gfx_cycle\" (integer-64) void)) "
           "(define macscheme-gfx-screen-width "
           "  (foreign-procedure \"macscheme_gfx_screen_width\" () integer-64)) "
           "(define macscheme-gfx-screen-height "
           "  (foreign-procedure \"macscheme_gfx_screen_height\" () integer-64)) "
           "(define macscheme-gfx-screen-active "
           "  (foreign-procedure \"macscheme_gfx_screen_active\" () integer-64)) "
           "(define macscheme-gfx-inkey "
           "  (foreign-procedure \"macscheme_gfx_inkey\" () integer-64)) "
           "(define macscheme-gfx-keydown "
           "  (foreign-procedure \"macscheme_gfx_keydown\" (integer-64) integer-64)) "
           "(define macscheme-gfx-buffer-width "
           "  (foreign-procedure \"macscheme_gfx_buffer_width\" () integer-64)) "
           "(define macscheme-gfx-buffer-height "
           "  (foreign-procedure \"macscheme_gfx_buffer_height\" () integer-64)) "
           "(define macscheme-gfx-sprite-load "
           "  (foreign-procedure \"macscheme_gfx_sprite_load\" (integer-64 string) void)) "
           "(define macscheme-gfx-sprite-def "
           "  (foreign-procedure \"macscheme_gfx_sprite_def\" (integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-data "
           "  (foreign-procedure \"macscheme_gfx_sprite_data\" (integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-commit "
           "  (foreign-procedure \"macscheme_gfx_sprite_commit\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-row-ascii "
           "  (foreign-procedure \"macscheme_gfx_sprite_row_ascii\" (integer-64 string) void)) "
           "(define macscheme-gfx-sprite-begin "
           "  (foreign-procedure \"macscheme_gfx_sprite_begin\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-end "
           "  (foreign-procedure \"macscheme_gfx_sprite_end\" () void)) "
           "(define macscheme-gfx-sprite-palette "
           "  (foreign-procedure \"macscheme_gfx_sprite_palette\" (integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-std-pal "
           "  (foreign-procedure \"macscheme_gfx_sprite_std_pal\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-frames "
           "  (foreign-procedure \"macscheme_gfx_sprite_frames\" (integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-set-frame "
           "  (foreign-procedure \"macscheme_gfx_sprite_set_frame\" (integer-64) void)) "
           "(define macscheme-gfx-sprite "
           "  (foreign-procedure \"macscheme_gfx_sprite\" (integer-64 integer-64 double-float double-float) void)) "
           "(define macscheme-gfx-sprite-pos "
           "  (foreign-procedure \"macscheme_gfx_sprite_pos\" (integer-64 double-float double-float) void)) "
           "(define macscheme-gfx-sprite-move "
           "  (foreign-procedure \"macscheme_gfx_sprite_move\" (integer-64 double-float double-float) void)) "
           "(define macscheme-gfx-sprite-rot "
           "  (foreign-procedure \"macscheme_gfx_sprite_rot\" (integer-64 double-float) void)) "
           "(define macscheme-gfx-sprite-scale "
           "  (foreign-procedure \"macscheme_gfx_sprite_scale\" (integer-64 double-float double-float) void)) "
           "(define macscheme-gfx-sprite-anchor "
           "  (foreign-procedure \"macscheme_gfx_sprite_anchor\" (integer-64 double-float double-float) void)) "
           "(define macscheme-gfx-sprite-show "
           "  (foreign-procedure \"macscheme_gfx_sprite_show\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-hide "
           "  (foreign-procedure \"macscheme_gfx_sprite_hide\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-flip "
           "  (foreign-procedure \"macscheme_gfx_sprite_flip\" (integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-alpha "
           "  (foreign-procedure \"macscheme_gfx_sprite_alpha\" (integer-64 double-float) void)) "
           "(define macscheme-gfx-sprite-frame "
           "  (foreign-procedure \"macscheme_gfx_sprite_frame\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-animate "
           "  (foreign-procedure \"macscheme_gfx_sprite_animate\" (integer-64 double-float) void)) "
           "(define macscheme-gfx-sprite-priority "
           "  (foreign-procedure \"macscheme_gfx_sprite_priority\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-blend "
           "  (foreign-procedure \"macscheme_gfx_sprite_blend\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-remove "
           "  (foreign-procedure \"macscheme_gfx_sprite_remove\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-remove-all "
           "  (foreign-procedure \"macscheme_gfx_sprite_remove_all\" () void)) "
           "(define macscheme-gfx-sprite-fx "
           "  (foreign-procedure \"macscheme_gfx_sprite_fx\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-fx-param "
           "  (foreign-procedure \"macscheme_gfx_sprite_fx_param\" (integer-64 double-float double-float) void)) "
           "(define macscheme-gfx-sprite-fx-colour "
           "  (foreign-procedure \"macscheme_gfx_sprite_fx_colour\" (integer-64 integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-glow "
           "  (foreign-procedure \"macscheme_gfx_sprite_glow\" (integer-64 double-float double-float integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-outline "
           "  (foreign-procedure \"macscheme_gfx_sprite_outline\" (integer-64 double-float integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-shadow "
           "  (foreign-procedure \"macscheme_gfx_sprite_shadow\" (integer-64 double-float double-float integer-64 integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-tint "
           "  (foreign-procedure \"macscheme_gfx_sprite_tint\" (integer-64 double-float integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-flash "
           "  (foreign-procedure \"macscheme_gfx_sprite_flash\" (integer-64 double-float integer-64 integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-fx-off "
           "  (foreign-procedure \"macscheme_gfx_sprite_fx_off\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-pal-override "
           "  (foreign-procedure \"macscheme_gfx_sprite_pal_override\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-pal-reset "
           "  (foreign-procedure \"macscheme_gfx_sprite_pal_reset\" (integer-64) void)) "
           "(define macscheme-gfx-sprite-x "
           "  (foreign-procedure \"macscheme_gfx_sprite_x\" (integer-64) double-float)) "
           "(define macscheme-gfx-sprite-y "
           "  (foreign-procedure \"macscheme_gfx_sprite_y\" (integer-64) double-float)) "
           "(define macscheme-gfx-sprite-rotation "
           "  (foreign-procedure \"macscheme_gfx_sprite_rotation\" (integer-64) double-float)) "
           "(define macscheme-gfx-sprite-visible "
           "  (foreign-procedure \"macscheme_gfx_sprite_visible\" (integer-64) integer-64)) "
           "(define macscheme-gfx-sprite-current-frame "
           "  (foreign-procedure \"macscheme_gfx_sprite_current_frame\" (integer-64) integer-64)) "
           "(define macscheme-gfx-sprite-hit "
           "  (foreign-procedure \"macscheme_gfx_sprite_hit\" (integer-64 integer-64) integer-64)) "
           "(define macscheme-gfx-sprite-count "
           "  (foreign-procedure \"macscheme_gfx_sprite_count\" () integer-64)) "
           "(define macscheme-gfx-sprite-collide "
           "  (foreign-procedure \"macscheme_gfx_sprite_collide\" (integer-64 integer-64) void)) "
           "(define macscheme-gfx-sprite-overlap "
           "  (foreign-procedure \"macscheme_gfx_sprite_overlap\" (integer-64 integer-64) integer-64)) "
           "(define macscheme-gfx-sprite-sync "
           "  (foreign-procedure \"macscheme_gfx_sprite_sync\" () void)) "
           "(define (->int v) (exact (round v))) "
           "(define (->float v) (if (inexact? v) v (exact->inexact v))) "
           "(define (->sound-id v) (->float (->int v))) "
           "(define (->sound-code v) (->float (->int v))) "
           "(define (->music-id v) (->float (->int v))) "
           "(define (->bool v) (not (zero? v))) "
           "(define snd-init "
           "  (foreign-procedure \"snd_init\" () double-float)) "
           "(define snd-shutdown "
           "  (foreign-procedure \"snd_shutdown\" () void)) "
           "(define snd-is-init "
           "  (foreign-procedure \"snd_is_init\" () double-float)) "
           "(define snd-stop-all "
           "  (foreign-procedure \"snd_stop_all\" () void)) "
           "(define snd-beep-raw "
           "  (foreign-procedure \"snd_beep\" (double-float double-float) double-float)) "
           "(define (snd-beep frequency duration) (snd-beep-raw (->float frequency) (->float duration))) "
           "(define snd-zap-raw "
           "  (foreign-procedure \"snd_zap\" (double-float double-float) double-float)) "
           "(define (snd-zap frequency duration) (snd-zap-raw (->float frequency) (->float duration))) "
           "(define snd-explode-raw "
           "  (foreign-procedure \"snd_explode\" (double-float double-float) double-float)) "
           "(define (snd-explode size duration) (snd-explode-raw (->float size) (->float duration))) "
           "(define snd-big-explosion-raw "
           "  (foreign-procedure \"snd_big_explosion\" (double-float double-float) double-float)) "
           "(define (snd-big-explosion size duration) (snd-big-explosion-raw (->float size) (->float duration))) "
           "(define snd-small-explosion-raw "
           "  (foreign-procedure \"snd_small_explosion\" (double-float double-float) double-float)) "
           "(define (snd-small-explosion intensity duration) (snd-small-explosion-raw (->float intensity) (->float duration))) "
           "(define snd-distant-explosion-raw "
           "  (foreign-procedure \"snd_distant_explosion\" (double-float double-float) double-float)) "
           "(define (snd-distant-explosion distance duration) (snd-distant-explosion-raw (->float distance) (->float duration))) "
           "(define snd-metal-explosion-raw "
           "  (foreign-procedure \"snd_metal_explosion\" (double-float double-float) double-float)) "
           "(define (snd-metal-explosion shrapnel duration) (snd-metal-explosion-raw (->float shrapnel) (->float duration))) "
           "(define snd-bang-raw "
           "  (foreign-procedure \"snd_bang\" (double-float double-float) double-float)) "
           "(define (snd-bang intensity duration) (snd-bang-raw (->float intensity) (->float duration))) "
           "(define snd-coin-raw "
           "  (foreign-procedure \"snd_coin\" (double-float double-float) double-float)) "
           "(define (snd-coin pitch duration) (snd-coin-raw (->float pitch) (->float duration))) "
           "(define snd-jump-raw "
           "  (foreign-procedure \"snd_jump\" (double-float double-float) double-float)) "
           "(define (snd-jump power duration) (snd-jump-raw (->float power) (->float duration))) "
           "(define snd-powerup-raw "
           "  (foreign-procedure \"snd_powerup\" (double-float double-float) double-float)) "
           "(define (snd-powerup intensity duration) (snd-powerup-raw (->float intensity) (->float duration))) "
           "(define snd-hurt-raw "
           "  (foreign-procedure \"snd_hurt\" (double-float double-float) double-float)) "
           "(define (snd-hurt severity duration) (snd-hurt-raw (->float severity) (->float duration))) "
           "(define snd-shoot-raw "
           "  (foreign-procedure \"snd_shoot\" (double-float double-float) double-float)) "
           "(define (snd-shoot power duration) (snd-shoot-raw (->float power) (->float duration))) "
           "(define snd-click-raw "
           "  (foreign-procedure \"snd_click\" (double-float double-float) double-float)) "
           "(define (snd-click sharpness duration) (snd-click-raw (->float sharpness) (->float duration))) "
           "(define snd-blip-raw "
           "  (foreign-procedure \"snd_blip\" (double-float double-float) double-float)) "
           "(define (snd-blip pitch duration) (snd-blip-raw (->float pitch) (->float duration))) "
           "(define snd-pickup-raw "
           "  (foreign-procedure \"snd_pickup\" (double-float double-float) double-float)) "
           "(define (snd-pickup brightness duration) (snd-pickup-raw (->float brightness) (->float duration))) "
           "(define snd-sweep-up-raw "
           "  (foreign-procedure \"snd_sweep_up\" (double-float double-float double-float) double-float)) "
           "(define (snd-sweep-up start-frequency end-frequency duration) (snd-sweep-up-raw (->float start-frequency) (->float end-frequency) (->float duration))) "
           "(define snd-sweep-down-raw "
           "  (foreign-procedure \"snd_sweep_down\" (double-float double-float double-float) double-float)) "
           "(define (snd-sweep-down start-frequency end-frequency duration) (snd-sweep-down-raw (->float start-frequency) (->float end-frequency) (->float duration))) "
           "(define snd-random-beep-raw "
           "  (foreign-procedure \"snd_random_beep\" (double-float double-float) double-float)) "
           "(define (snd-random-beep seed duration) (snd-random-beep-raw (->float seed) (->float duration))) "
           "(define snd-tone-raw "
           "  (foreign-procedure \"snd_tone\" (double-float double-float double-float) double-float)) "
           "(define (snd-tone frequency duration waveform) "
           "  (snd-tone-raw (->float frequency) (->float duration) (->sound-code waveform))) "
           "(define snd-note-raw "
           "  (foreign-procedure \"snd_note\" (double-float double-float double-float double-float double-float double-float double-float) double-float)) "
           "(define (snd-note midi-note duration waveform attack decay sustain release) "
           "  (snd-note-raw (->float midi-note) (->float duration) (->sound-code waveform) (->float attack) (->float decay) (->float sustain) (->float release))) "
           "(define snd-noise-raw "
           "  (foreign-procedure \"snd_noise\" (double-float double-float) double-float)) "
           "(define (snd-noise noise-type duration) (snd-noise-raw (->sound-code noise-type) (->float duration))) "
           "(define snd-fm-raw "
           "  (foreign-procedure \"snd_fm\" (double-float double-float double-float double-float) double-float)) "
           "(define (snd-fm carrier-frequency mod-frequency mod-index duration) "
           "  (snd-fm-raw (->float carrier-frequency) (->float mod-frequency) (->float mod-index) (->float duration))) "
           "(define snd-filtered-tone-raw "
           "  (foreign-procedure \"snd_filtered_tone\" (double-float double-float double-float double-float double-float double-float) double-float)) "
           "(define (snd-filtered-tone frequency duration waveform filter-type cutoff resonance) "
           "  (snd-filtered-tone-raw (->float frequency) (->float duration) (->sound-code waveform) (->sound-code filter-type) (->float cutoff) (->float resonance))) "
           "(define snd-filtered-note-raw "
           "  (foreign-procedure \"snd_filtered_note\" (double-float double-float double-float double-float double-float double-float double-float double-float double-float double-float) double-float)) "
           "(define (snd-filtered-note midi-note duration waveform attack decay sustain release filter-type cutoff resonance) "
           "  (snd-filtered-note-raw (->float midi-note) (->float duration) (->sound-code waveform) (->float attack) (->float decay) (->float sustain) (->float release) (->sound-code filter-type) (->float cutoff) (->float resonance))) "
           "(define snd-reverb-raw "
           "  (foreign-procedure \"snd_reverb\" (double-float double-float double-float double-float double-float double-float) double-float)) "
           "(define (snd-reverb frequency duration waveform room-size damping wet) "
           "  (snd-reverb-raw (->float frequency) (->float duration) (->sound-code waveform) (->float room-size) (->float damping) (->float wet))) "
           "(define snd-delay-raw "
           "  (foreign-procedure \"snd_delay\" (double-float double-float double-float double-float double-float double-float) double-float)) "
           "(define (snd-delay frequency duration waveform delay-time feedback mix) "
           "  (snd-delay-raw (->float frequency) (->float duration) (->sound-code waveform) (->float delay-time) (->float feedback) (->float mix))) "
           "(define snd-distortion-raw "
           "  (foreign-procedure \"snd_distortion\" (double-float double-float double-float double-float double-float double-float) double-float)) "
           "(define (snd-distortion frequency duration waveform drive tone level) "
           "  (snd-distortion-raw (->float frequency) (->float duration) (->sound-code waveform) (->float drive) (->float tone) (->float level))) "
           "(define snd-play-raw "
           "  (foreign-procedure \"snd_play\" (double-float double-float double-float) void)) "
           "(define (snd-play-impl id volume pan) "
           "  (snd-play-raw (->sound-id id) (->float volume) (->float pan))) "
           "(define snd-play-simple-raw "
           "  (foreign-procedure \"snd_play_simple\" (double-float) void)) "
           "(define (snd-play-simple id) (snd-play-simple-raw (->sound-id id))) "
           "(define snd-stop "
           "  (foreign-procedure \"snd_stop\" () void)) "
           "(define snd-stop-one-raw "
           "  (foreign-procedure \"snd_stop_one\" (double-float) void)) "
           "(define (snd-stop-one id) (snd-stop-one-raw (->sound-id id))) "
           "(define snd-is-playing-raw "
           "  (foreign-procedure \"snd_is_playing\" (double-float) double-float)) "
           "(define (snd-is-playing id) (snd-is-playing-raw (->sound-id id))) "
           "(define snd-get-duration-raw "
           "  (foreign-procedure \"snd_get_duration\" (double-float) double-float)) "
           "(define (snd-get-duration id) (snd-get-duration-raw (->sound-id id))) "
           "(define snd-free-raw "
           "  (foreign-procedure \"snd_free\" (double-float) double-float)) "
           "(define (snd-free id) (snd-free-raw (->sound-id id))) "
           "(define snd-free-all "
           "  (foreign-procedure \"snd_free_all\" () void)) "
           "(define snd-set-volume-raw "
           "  (foreign-procedure \"snd_set_volume\" (double-float) void)) "
           "(define (snd-set-volume volume) (snd-set-volume-raw (->float volume))) "
           "(define snd-get-volume "
           "  (foreign-procedure \"snd_get_volume\" () double-float)) "
           "(define snd-exists-raw "
           "  (foreign-procedure \"snd_exists\" (double-float) double-float)) "
           "(define (snd-exists id) (snd-exists-raw (->sound-id id))) "
           "(define snd-count "
           "  (foreign-procedure \"snd_count\" () double-float)) "
           "(define snd-mem "
           "  (foreign-procedure \"snd_mem\" () double-float)) "
           "(define snd-note-to-freq-raw "
           "  (foreign-procedure \"snd_note_to_freq\" (double-float) double-float)) "
           "(define (snd-note-to-freq midi-note) (snd-note-to-freq-raw (->float midi-note))) "
           "(define snd-freq-to-note-raw "
           "  (foreign-procedure \"snd_freq_to_note\" (double-float) double-float)) "
           "(define (snd-freq-to-note frequency) (snd-freq-to-note-raw (->float frequency))) "
           "(define snd-export-wav-raw "
           "  (foreign-procedure \"snd_export_wav\" (double-float string double-float) double-float)) "
           "(define (snd-export-wav-impl id path volume) "
           "  (snd-export-wav-raw (->sound-id id) path (->float volume))) "
           "(define mus-play-impl "
           "  (foreign-procedure \"mus_play\" (string double-float) void)) "
           "(define (mus-play-simple value) (mus-play-impl value 1.0)) "
           "(define mus-load "
           "  (foreign-procedure \"mus_load\" (string) double-float)) "
           "(define mus-play-id-raw "
           "  (foreign-procedure \"mus_play_id\" (double-float double-float) void)) "
           "(define (mus-play-id-impl id volume) "
           "  (mus-play-id-raw (->music-id id) (->float volume))) "
           "(define (mus-play-id-simple id) (mus-play-id-impl (->music-id id) 1.0)) "
           "(define mus-stop "
           "  (foreign-procedure \"mus_stop\" () void)) "
           "(define mus-pause "
           "  (foreign-procedure \"mus_pause\" () void)) "
           "(define mus-resume "
           "  (foreign-procedure \"mus_resume\" () void)) "
           "(define mus-set-volume "
           "  (foreign-procedure \"mus_set_volume\" (double-float) void)) "
           "(define mus-get-volume "
           "  (foreign-procedure \"mus_get_volume\" () double-float)) "
           "(define mus-free-raw "
           "  (foreign-procedure \"mus_free\" (double-float) double-float)) "
           "(define (mus-free music-id) (mus-free-raw (->music-id music-id))) "
           "(define mus-free-all "
           "  (foreign-procedure \"mus_free_all\" () void)) "
           "(define mus-is-playing "
           "  (foreign-procedure \"mus_is_playing\" () double-float)) "
           "(define mus-is-playing-id-raw "
           "  (foreign-procedure \"mus_is_playing_id\" (double-float) double-float)) "
           "(define (mus-is-playing-id music-id) (mus-is-playing-id-raw (->music-id music-id))) "
           "(define mus-state "
           "  (foreign-procedure \"mus_state\" () double-float)) "
           "(define mus-exists-raw "
           "  (foreign-procedure \"mus_exists\" (double-float) double-float)) "
           "(define (mus-exists music-id) (mus-exists-raw (->music-id music-id))) "
           "(define mus-count "
           "  (foreign-procedure \"mus_count\" () double-float)) "
           "(define mus-mem "
           "  (foreign-procedure \"mus_mem\" () double-float)) "
           "(define mus-get-tempo-raw "
           "  (foreign-procedure \"mus_get_tempo\" (double-float) double-float)) "
           "(define (mus-get-tempo music-id) (mus-get-tempo-raw (->music-id music-id))) "
           "(define mus-render "
           "  (foreign-procedure \"mus_render\" (string double-float double-float) double-float)) "
           "(define mus-render-simple "
           "  (foreign-procedure \"mus_render_simple\" (string) double-float)) "
           "(define mus-render-wav-impl "
           "  (foreign-procedure \"mus_render_wav\" (string string double-float double-float) double-float)) "
           "(define mus-export-midi-raw "
           "  (foreign-procedure \"mus_export_midi\" (double-float string) double-float)) "
           "(define (mus-export-midi-impl music-id path) (mus-export-midi-raw (->music-id music-id) path)) "
           "(define sound-wave-sine 0) "
           "(define sound-wave-square 1) "
           "(define sound-wave-saw 2) "
           "(define sound-wave-triangle 3) "
           "(define sound-wave-noise 4) "
           "(define sound-wave-pulse 5) "
           "(define sound-noise-white 0) "
           "(define sound-noise-pink 1) "
           "(define sound-noise-brown 2) "
           "(define sound-filter-none 0) "
           "(define sound-filter-lowpass 1) "
           "(define sound-filter-highpass 2) "
           "(define sound-filter-bandpass 3) "
           "(define (sound-waveform-id wave) "
           "  (if (symbol? wave) "
           "      (case wave "
           "        ((sine) sound-wave-sine) "
           "        ((square) sound-wave-square) "
           "        ((saw sawtooth) sound-wave-saw) "
           "        ((triangle) sound-wave-triangle) "
           "        ((noise) sound-wave-noise) "
           "        ((pulse) sound-wave-pulse) "
           "        (else (assertion-violation 'sound-waveform-id \"unknown waveform\" wave))) "
           "      (->int wave))) "
           "(define (sound-noise-id kind) "
           "  (if (symbol? kind) "
           "      (case kind "
           "        ((white) sound-noise-white) "
           "        ((pink) sound-noise-pink) "
           "        ((brown) sound-noise-brown) "
           "        (else (assertion-violation 'sound-noise-id \"unknown noise type\" kind))) "
           "      (->int kind))) "
           "(define (sound-filter-id kind) "
           "  (if (symbol? kind) "
           "      (case kind "
           "        ((none) sound-filter-none) "
           "        ((lowpass low) sound-filter-lowpass) "
           "        ((highpass high) sound-filter-highpass) "
           "        ((bandpass band) sound-filter-bandpass) "
           "        (else (assertion-violation 'sound-filter-id \"unknown filter type\" kind))) "
           "      (->int kind))) "
           "(define (audio-init) (->bool (snd-init))) "
           "(define (audio-shutdown) (snd-shutdown)) "
           "(define (audio-initialized?) (->bool (snd-is-init))) "
           "(define (audio-stop-all) (snd-stop-all)) "
           "(define (sound-play id . rest) "
           "  (case (length rest) "
           "    ((0) (snd-play-simple (->int id))) "
           "    ((1) (snd-play-impl (->int id) (->float (car rest)) 0.0)) "
           "    ((2) (snd-play-impl (->int id) (->float (car rest)) (->float (cadr rest)))) "
           "    (else (assertion-violation 'sound-play \"expected id [volume [pan]]\" (cons id rest))))) "
           "(define sound-volume "
           "  (case-lambda "
           "    (() (snd-get-volume)) "
           "    ((level) (snd-set-volume (->float level))))) "
           "(define (sound-stop) (snd-stop)) "
           "(define (sound-stop-one id) (snd-stop-one (->int id))) "
           "(define (sound-free id) (->bool (snd-free (->int id)))) "
           "(define (sound-free-all) (snd-free-all)) "
           "(define (sound-playing? id) (->bool (snd-is-playing (->int id)))) "
           "(define (sound-duration id) (snd-get-duration (->int id))) "
           "(define (sound-exists? id) (->bool (snd-exists (->int id)))) "
           "(define (sound-count) (->int (snd-count))) "
           "(define (sound-memory-usage) (->int (snd-mem))) "
           "(define (sound-export-wav id path . rest) "
           "  (let ((volume (if (null? rest) 1.0 (->float (car rest))))) "
           "    (->bool (snd-export-wav-impl (->int id) path volume)))) "
           "(define (midi->hz midi-note) (snd-note-to-freq (->float midi-note))) "
           "(define (hz->midi hz) (->int (snd-freq-to-note (->float hz)))) "
           "(define (sound-beep frequency duration) (snd-beep (->float frequency) (->float duration))) "
           "(define (sound-zap frequency duration) (snd-zap (->float frequency) (->float duration))) "
           "(define (sound-explode size duration) (snd-explode (->float size) (->float duration))) "
           "(define (sound-big-explosion size duration) (snd-big-explosion (->float size) (->float duration))) "
           "(define (sound-small-explosion intensity duration) (snd-small-explosion (->float intensity) (->float duration))) "
           "(define (sound-distant-explosion distance duration) (snd-distant-explosion (->float distance) (->float duration))) "
           "(define (sound-metal-explosion shrapnel duration) (snd-metal-explosion (->float shrapnel) (->float duration))) "
           "(define (sound-bang intensity duration) (snd-bang (->float intensity) (->float duration))) "
           "(define (sound-coin pitch duration) (snd-coin (->float pitch) (->float duration))) "
           "(define (sound-jump power duration) (snd-jump (->float power) (->float duration))) "
           "(define (sound-powerup intensity duration) (snd-powerup (->float intensity) (->float duration))) "
           "(define (sound-hurt severity duration) (snd-hurt (->float severity) (->float duration))) "
           "(define (sound-shoot power duration) (snd-shoot (->float power) (->float duration))) "
           "(define (sound-click sharpness duration) (snd-click (->float sharpness) (->float duration))) "
           "(define (sound-blip pitch duration) (snd-blip (->float pitch) (->float duration))) "
           "(define (sound-pickup brightness duration) (snd-pickup (->float brightness) (->float duration))) "
           "(define (sound-sweep-up start-frequency end-frequency duration) (snd-sweep-up (->float start-frequency) (->float end-frequency) (->float duration))) "
           "(define (sound-sweep-down start-frequency end-frequency duration) (snd-sweep-down (->float start-frequency) (->float end-frequency) (->float duration))) "
           "(define (sound-random-beep seed duration) (snd-random-beep (->float seed) (->float duration))) "
           "(define (sound-tone frequency duration waveform) (snd-tone (->float frequency) (->float duration) (sound-waveform-id waveform))) "
           "(define (sound-note midi-note duration waveform attack decay sustain release) "
           "  (snd-note (->float midi-note) (->float duration) (sound-waveform-id waveform) (->float attack) (->float decay) (->float sustain) (->float release))) "
           "(define (sound-noise noise-type duration) (snd-noise (sound-noise-id noise-type) (->float duration))) "
           "(define (sound-fm carrier-frequency mod-frequency mod-index duration) "
           "  (snd-fm (->float carrier-frequency) (->float mod-frequency) (->float mod-index) (->float duration))) "
           "(define (sound-filter-tone frequency duration waveform filter-type cutoff resonance) "
           "  (snd-filtered-tone (->float frequency) (->float duration) (sound-waveform-id waveform) (sound-filter-id filter-type) (->float cutoff) (->float resonance))) "
           "(define (sound-filter-note midi-note duration waveform attack decay sustain release filter-type cutoff resonance) "
           "  (snd-filtered-note (->float midi-note) (->float duration) (sound-waveform-id waveform) (->float attack) (->float decay) (->float sustain) (->float release) (sound-filter-id filter-type) (->float cutoff) (->float resonance))) "
           "(define (sound-reverb frequency duration waveform room-size damping wet) "
           "  (snd-reverb (->float frequency) (->float duration) (sound-waveform-id waveform) (->float room-size) (->float damping) (->float wet))) "
           "(define (sound-delay frequency duration waveform delay-time feedback mix) "
           "  (snd-delay (->float frequency) (->float duration) (sound-waveform-id waveform) (->float delay-time) (->float feedback) (->float mix))) "
           "(define (sound-distortion frequency duration waveform drive tone level) "
           "  (snd-distortion (->float frequency) (->float duration) (sound-waveform-id waveform) (->float drive) (->float tone) (->float level))) "
           "(define (abc . lines) "
           "  (let loop ((rest lines) (out \"\")) "
           "    (cond "
           "      ((null? rest) out) "
           "      ((null? (cdr rest)) (string-append out (car rest))) "
           "      (else (loop (cdr rest) (string-append out (car rest) \"\\n\")))))) "
           "(define (music-play value . rest) "
           "  (case (length rest) "
           "    ((0) (if (string? value) (mus-play-impl value 1.0) (mus-play-id-impl (->music-id value) 1.0))) "
           "    ((1) (if (string? value) (mus-play-impl value (->float (car rest))) (mus-play-id-impl (->music-id value) (->float (car rest))))) "
           "    (else (assertion-violation 'music-play \"expected music/string [volume]\" (cons value rest))))) "
           "(define (music-load abc-text) (mus-load abc-text)) "
           "(define (music-play-id music-id . rest) "
           "  (if (null? rest) "
           "      (mus-play-id-impl (->music-id music-id) 1.0) "
           "      (mus-play-id-impl (->music-id music-id) (->float (car rest))))) "
           "(define (music-stop) (mus-stop)) "
           "(define (music-pause) (mus-pause)) "
           "(define (music-resume) (mus-resume)) "
           "(define music-volume "
           "  (case-lambda "
           "    (() (mus-get-volume)) "
           "    ((level) (mus-set-volume (->float level))))) "
           "(define (music-free music-id) (->bool (mus-free (->music-id music-id)))) "
           "(define (music-free-all) (mus-free-all)) "
           "(define music-playing? "
           "  (case-lambda "
           "    (() (->bool (mus-is-playing))) "
           "    ((music-id) (->bool (mus-is-playing-id (->music-id music-id)))))) "
           "(define (music-state) (->int (mus-state))) "
           "(define (music-exists? music-id) (->bool (mus-exists (->music-id music-id)))) "
           "(define (music-count) (->int (mus-count))) "
           "(define (music-memory-usage) (->int (mus-mem))) "
           "(define (music-tempo music-id) (mus-get-tempo (->music-id music-id))) "
           "(define music-render "
           "  (case-lambda "
           "    ((abc-text) (mus-render-simple abc-text)) "
           "    ((abc-text duration sample-rate) (mus-render abc-text (->float duration) (->float sample-rate))))) "
           "(define (music-render-wav abc-text path . rest) "
           "  (case (length rest) "
           "    ((0) (->bool (mus-render-wav-impl abc-text path 0.0 0.0))) "
           "    ((2) (->bool (mus-render-wav-impl abc-text path (->float (car rest)) (->float (cadr rest))))) "
           "    (else (assertion-violation 'music-render-wav \"expected abc path [duration sample-rate]\" (cons abc-text (cons path rest)))))) "
           "(define (music-export-midi music-id path) "
           "  (->bool (mus-export-midi-impl (->music-id music-id) path))) "
           "(define (gfx-set-default-palette!) "
           "  (begin "
           "    (macscheme-gfx-palette 16 0 0 0) "
           "    (macscheme-gfx-palette 17 255 255 255) "
           "    (macscheme-gfx-palette 18 255 0 0) "
           "    (macscheme-gfx-palette 19 0 255 0) "
           "    (macscheme-gfx-palette 20 0 0 255) "
           "    (macscheme-gfx-palette 21 255 255 0) "
           "    (macscheme-gfx-palette 22 0 255 255) "
           "    (macscheme-gfx-palette 23 255 0 255) "
           "    (macscheme-gfx-palette 24 255 128 0) "
           "    (macscheme-gfx-palette 25 128 128 128) "
           "    (macscheme-gfx-palette 26 64 64 64) "
           "    (macscheme-gfx-palette 27 255 128 128) "
           "    (macscheme-gfx-palette 28 128 255 128) "
           "    (macscheme-gfx-palette 29 128 128 255) "
           "    (macscheme-gfx-palette 30 255 220 128) "
           "    (macscheme-gfx-palette 31 220 220 220))) "
           "(define (gfx-init) (macscheme-gfx-init)) "
           "(define (gfx-screen-close) (macscheme-gfx-screen-close)) "
            "(define (gfx-screen w h scale) "
            "  (macscheme-gfx-screen (->int w) (->int h) (->int scale)) "
            "  (gfx-reset)) "
           "(define (gfx-set-target buffer) (macscheme-gfx-set-target (->int buffer))) "
           "(define (gfx-pset x y c) "
           "  (macscheme-gfx-pset (->int x) (->int y) (->int c))) "
           "(define (gfx-pget x y) "
           "  (macscheme-gfx-pget (->int x) (->int y))) "
           "(define (gfx-line x1 y1 x2 y2 c) "
           "  (macscheme-gfx-line (->int x1) (->int y1) (->int x2) (->int y2) (->int c))) "
           "(define (gfx-reset) "
           "  (macscheme-gfx-reset-palette) "
           "  (gfx-set-default-palette!) "
           "  (macscheme-gfx-cls 16)) "
           "(define (gfx-cls c) "
           "  (macscheme-gfx-cls (->int c))) "
           "(define (gfx-rect x y w h c) "
           "  (macscheme-gfx-rect (->int x) (->int y) (->int w) (->int h) (->int c) 1)) "
           "(define (gfx-rect-outline x y w h c) "
           "  (macscheme-gfx-rect (->int x) (->int y) (->int w) (->int h) (->int c) 0)) "
           "(define (gfx-recti x y w h c) (gfx-rect x y w h c)) "
           "(define (gfx-circle x y r c) "
           "  (macscheme-gfx-circle (->int x) (->int y) (->int r) (->int c) 1)) "
           "(define (gfx-circle-outline x y r c) "
           "  (macscheme-gfx-circle (->int x) (->int y) (->int r) (->int c) 0)) "
           "(define (gfx-ellipse x y rx ry c) "
           "  (macscheme-gfx-ellipse (->int x) (->int y) (->int rx) (->int ry) (->int c) 1)) "
           "(define (gfx-ellipse-outline x y rx ry c) "
           "  (macscheme-gfx-ellipse (->int x) (->int y) (->int rx) (->int ry) (->int c) 0)) "
           "(define (gfx-triangle x1 y1 x2 y2 x3 y3 c) "
           "  (macscheme-gfx-triangle (->int x1) (->int y1) (->int x2) (->int y2) (->int x3) (->int y3) (->int c) 1)) "
           "(define (gfx-triangle-outline x1 y1 x2 y2 x3 y3 c) "
           "  (macscheme-gfx-triangle (->int x1) (->int y1) (->int x2) (->int y2) (->int x3) (->int y3) (->int c) 0)) "
           "(define (gfx-fill x y c) "
           "  (macscheme-gfx-fill-area (->int x) (->int y) (->int c))) "
           "(define (gfx-scroll dx dy fill) "
           "  (macscheme-gfx-scroll-buffer (->int dx) (->int dy) (->int fill))) "
           "(define (gfx-blit dst dx dy src sx sy w h) "
           "  (macscheme-gfx-blit (->int dst) (->int dx) (->int dy) (->int src) (->int sx) (->int sy) (->int w) (->int h))) "
           "(define (gfx-blit-solid dst dx dy src sx sy w h) "
           "  (macscheme-gfx-blit-solid (->int dst) (->int dx) (->int dy) (->int src) (->int sx) (->int sy) (->int w) (->int h))) "
           "(define (gfx-blit-scale dst dx dy dw dh src sx sy sw sh) "
           "  (macscheme-gfx-blit-scale (->int dst) (->int dx) (->int dy) (->int dw) (->int dh) (->int src) (->int sx) (->int sy) (->int sw) (->int sh))) "
           "(define (gfx-blit-flip dst dx dy src sx sy w h mode) "
           "  (macscheme-gfx-blit-flip (->int dst) (->int dx) (->int dy) (->int src) (->int sx) (->int sy) (->int w) (->int h) (->int mode))) "
           "(define (gfx-pal idx r g b) "
           "  (macscheme-gfx-palette (->int idx) (->int r) (->int g) (->int b))) "
           "(define (gfx-line-pal line idx r g b) "
           "  (macscheme-gfx-line-palette (->int line) (->int idx) (->int r) (->int g) (->int b))) "
           "(define (gfx-pal-cycle slot start end speed direction) "
           "  (macscheme-gfx-pal-cycle (->int slot) (->int start) (->int end) (->int speed) (->int direction))) "
           "(define (gfx-pal-cycle-lines slot index y0 y1 speed direction) "
           "  (macscheme-gfx-pal-cycle-lines (->int slot) (->int index) (->int y0) (->int y1) (->int speed) (->int direction))) "
           "(define (gfx-pal-fade slot index speed r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-fade (->int slot) (->int index) (->int speed) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-fade-lines slot index y0 y1 speed r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-fade-lines (->int slot) (->int index) (->int y0) (->int y1) (->int speed) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-pulse slot index speed r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-pulse (->int slot) (->int index) (->int speed) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-pulse-lines slot index y0 y1 speed r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-pulse-lines (->int slot) (->int index) (->int y0) (->int y1) (->int speed) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-gradient slot index y0 y1 r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-gradient (->int slot) (->int index) (->int y0) (->int y1) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-strobe slot index on off r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-strobe (->int slot) (->int index) (->int on) (->int off) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-strobe-lines slot index y0 y1 on off r1 g1 b1 r2 g2 b2) "
           "  (macscheme-gfx-pal-strobe-lines (->int slot) (->int index) (->int y0) (->int y1) (->int on) (->int off) (->int r1) (->int g1) (->int b1) (->int r2) (->int g2) (->int b2))) "
           "(define (gfx-pal-stop slot) (macscheme-gfx-pal-stop (->int slot))) "
           "(define (gfx-pal-stop-all) (macscheme-gfx-pal-stop-all)) "
           "(define (gfx-pal-pause slot) (macscheme-gfx-pal-pause (->int slot))) "
           "(define (gfx-pal-resume slot) (macscheme-gfx-pal-resume (->int slot))) "
           "(define (gfx-clear r g b) "
           "  (gfx-pal 16 r g b) "
           "  (macscheme-gfx-cls 16)) "
           "(define (gfx-text x y text c) "
           "  (macscheme-gfx-draw-text (->int x) (->int y) text (->int c) 0)) "
           "(define (gfx-text-small x y text c) "
           "  (macscheme-gfx-draw-text (->int x) (->int y) text (->int c) 1)) "
           "(define (gfx-text-int x y val c) "
           "  (macscheme-gfx-draw-text-int (->int x) (->int y) (->int val) (->int c) 0)) "
           "(define (gfx-text-int-small x y val c) "
           "  (macscheme-gfx-draw-text-int (->int x) (->int y) (->int val) (->int c) 1)) "
           "(define (gfx-text-num x y val c) "
           "  (macscheme-gfx-draw-text-double (->int x) (->int y) val (->int c) 0)) "
           "(define (gfx-text-num-small x y val c) "
           "  (macscheme-gfx-draw-text-double (->int x) (->int y) val (->int c) 1)) "
           "(define (gfx-text-width text) (macscheme-gfx-text-width text 0)) "
           "(define (gfx-text-width-small text) (macscheme-gfx-text-width text 1)) "
           "(define (gfx-text-height) (macscheme-gfx-text-height 0)) "
           "(define (gfx-text-height-small) (macscheme-gfx-text-height 1)) "
           "(define (gfx-flip) (macscheme-gfx-flip)) "
           "(define (gfx-vsync) (macscheme-gfx-vsync)) "
           "(define (gfx-wait n) (macscheme-gfx-wait-frames (->int n))) "
           "(define (gfx-scroll-pos sx sy) "
           "  (macscheme-gfx-set-scroll (->int sx) (->int sy))) "
            "(define (gfx-cycle on) "
            "  (macscheme-gfx-cycle (if on 1 0))) "
           "(define (gfx-width) (macscheme-gfx-screen-width)) "
           "(define (gfx-height) (macscheme-gfx-screen-height)) "
           "(define (gfx-active?) (not (zero? (macscheme-gfx-screen-active)))) "
               "(define gfx-key-name-table "
               "  '((0 . a) (1 . s) (2 . d) (3 . f) (4 . h) (5 . g) (6 . z) (7 . x) (8 . c) (9 . v) "
               "    (11 . b) (12 . q) (13 . w) (14 . e) (15 . r) (16 . y) (17 . t) (31 . o) (32 . u) "
               "    (34 . i) (35 . p) (37 . l) (38 . j) (40 . k) (45 . n) (46 . m) (49 . space) "
               "    (36 . return) (48 . tab) (51 . backspace) (53 . escape) (55 . command) "
               "    (56 . shift) (58 . option) (59 . control) (123 . left) (124 . right) "
               "    (125 . down) (126 . up))) "
               "(define gfx-key-alias-table "
               "  '((a . 0) (s . 1) (d . 2) (f . 3) (h . 4) (g . 5) (z . 6) (x . 7) (c . 8) (v . 9) "
               "    (b . 11) (q . 12) (w . 13) (e . 14) (r . 15) (y . 16) (t . 17) (o . 31) (u . 32) "
               "    (i . 34) (p . 35) (l . 37) (j . 38) (k . 40) (n . 45) (m . 46) (space . 49) "
               "    (return . 36) (enter . 36) (tab . 48) (backspace . 51) (delete . 51) (escape . 53) "
               "    (esc . 53) (command . 55) (cmd . 55) (shift . 56) (option . 58) (alt . 58) "
               "    (control . 59) (ctrl . 59) (left . 123) (right . 124) (down . 125) (up . 126))) "
               "(define (gfx-key-name keycode) "
               "  (let ((entry (assv (->int keycode) gfx-key-name-table))) "
               "    (and entry (cdr entry)))) "
               "(define (gfx-key-code key) "
               "  (cond "
               "    ((integer? key) (->int key)) "
               "    ((symbol? key) "
               "     (let ((entry (assq key gfx-key-alias-table))) "
               "       (if entry "
               "           (cdr entry) "
               "           (assertion-violation 'gfx-key-code \"unknown key name\" key)))) "
               "    ((string? key) (gfx-key-code (string->symbol (string-downcase key)))) "
               "    (else (assertion-violation 'gfx-key-code \"expected key symbol, string, or integer keycode\" key)))) "
               "(define (gfx-key-pressed? key) "
               "  (not (zero? (macscheme-gfx-keydown (gfx-key-code key))))) "
               "(define gfx-key-down? gfx-key-pressed?) "
               "(define (gfx-read-key-code) "
               "  (let ((code (macscheme-gfx-inkey))) "
               "    (and (not (zero? code)) code))) "
               "(define (gfx-read-key) "
               "  (let ((code (gfx-read-key-code))) "
               "    (and code (or (gfx-key-name code) code)))) "
           "(define (gfx-buffer-width) (macscheme-gfx-buffer-width)) "
           "(define (gfx-buffer-height) (macscheme-gfx-buffer-height)) "
           "(define (gfx-sprite-load id path) "
           "  (macscheme-gfx-sprite-load (->int id) path)) "
           "(define (gfx-sprite-def id w h) "
           "  (macscheme-gfx-sprite-def (->int id) (->int w) (->int h))) "
           "(define (gfx-sprite-data id x y colour-index) "
           "  (macscheme-gfx-sprite-data (->int id) (->int x) (->int y) (->int colour-index))) "
           "(define (gfx-sprite-commit id) "
           "  (macscheme-gfx-sprite-commit (->int id))) "
           "(define (gfx-sprite-row row pattern) "
           "  (macscheme-gfx-sprite-row-ascii (->int row) pattern)) "
           "(define (gfx-sprite-begin id) "
           "  (macscheme-gfx-sprite-begin (->int id))) "
           "(define (gfx-sprite-end) (macscheme-gfx-sprite-end)) "
           "(define (gfx-sprite-palette id idx r g b) "
           "  (macscheme-gfx-sprite-palette (->int id) (->int idx) (->int r) (->int g) (->int b))) "
           "(define (gfx-sprite-std-pal id palette-id) "
           "  (macscheme-gfx-sprite-std-pal (->int id) (->int palette-id))) "
           "(define (gfx-sprite-frames id fw fh count) "
           "  (macscheme-gfx-sprite-frames (->int id) (->int fw) (->int fh) (->int count))) "
           "(define (gfx-sprite-set-frame frame) "
           "  (macscheme-gfx-sprite-set-frame (->int frame))) "
           "(define (gfx-sprite inst def x y) "
           "  (let ((inst-id (->int inst))) "
           "    (macscheme-gfx-sprite inst-id (->int def) (->float x) (->float y)) "
           "    (macscheme-gfx-sprite-show inst-id))) "
           "(define (gfx-sprite-pos inst x y) "
           "  (macscheme-gfx-sprite-pos (->int inst) (->float x) (->float y))) "
           "(define (gfx-sprite-move inst dx dy) "
           "  (macscheme-gfx-sprite-move (->int inst) (->float dx) (->float dy))) "
           "(define (gfx-sprite-rot inst angle-degrees) "
           "  (macscheme-gfx-sprite-rot (->int inst) (->float angle-degrees))) "
           "(define (gfx-sprite-scale inst sx sy) "
           "  (macscheme-gfx-sprite-scale (->int inst) (->float sx) (->float sy))) "
           "(define (gfx-sprite-anchor inst ax ay) "
           "  (macscheme-gfx-sprite-anchor (->int inst) (->float ax) (->float ay))) "
           "(define (gfx-sprite-show inst) "
           "  (macscheme-gfx-sprite-show (->int inst))) "
           "(define (gfx-sprite-hide inst) "
           "  (macscheme-gfx-sprite-hide (->int inst))) "
           "(define (gfx-sprite-flip inst flip-h flip-v) "
           "  (macscheme-gfx-sprite-flip (->int inst) (if flip-h 1 0) (if flip-v 1 0))) "
           "(define (gfx-sprite-alpha inst a) "
           "  (macscheme-gfx-sprite-alpha (->int inst) (->float a))) "
           "(define (gfx-sprite-frame inst n) "
           "  (macscheme-gfx-sprite-frame (->int inst) (->int n))) "
           "(define (gfx-sprite-animate inst speed) "
           "  (macscheme-gfx-sprite-animate (->int inst) (->float speed))) "
           "(define (gfx-sprite-priority inst p) "
           "  (macscheme-gfx-sprite-priority (->int inst) (->int p))) "
           "(define (gfx-sprite-blend inst mode) "
           "  (macscheme-gfx-sprite-blend (->int inst) (if mode 1 0))) "
           "(define (gfx-sprite-remove inst) "
           "  (macscheme-gfx-sprite-remove (->int inst))) "
           "(define (gfx-sprite-remove-all) (macscheme-gfx-sprite-remove-all)) "
           "(define (gfx-sprite-fx inst effect-type) "
           "  (macscheme-gfx-sprite-fx (->int inst) (->int effect-type))) "
           "(define (gfx-sprite-fx-param inst p1 p2) "
           "  (macscheme-gfx-sprite-fx-param (->int inst) (->float p1) (->float p2))) "
           "(define (gfx-sprite-fx-colour inst r g b a) "
           "  (macscheme-gfx-sprite-fx-colour (->int inst) (->int r) (->int g) (->int b) (->int a))) "
           "(define (gfx-sprite-glow inst radius intensity r g b) "
           "  (macscheme-gfx-sprite-glow (->int inst) (->float radius) (->float intensity) (->int r) (->int g) (->int b))) "
           "(define (gfx-sprite-outline inst thickness r g b) "
           "  (macscheme-gfx-sprite-outline (->int inst) (->float thickness) (->int r) (->int g) (->int b))) "
           "(define (gfx-sprite-shadow inst ox oy r g b a) "
           "  (macscheme-gfx-sprite-shadow (->int inst) (->float ox) (->float oy) (->int r) (->int g) (->int b) (->int a))) "
           "(define (gfx-sprite-tint inst factor r g b) "
           "  (macscheme-gfx-sprite-tint (->int inst) (->float factor) (->int r) (->int g) (->int b))) "
           "(define (gfx-sprite-flash inst speed r g b) "
           "  (macscheme-gfx-sprite-flash (->int inst) (->float speed) (->int r) (->int g) (->int b))) "
           "(define (gfx-sprite-fx-off inst) "
           "  (macscheme-gfx-sprite-fx-off (->int inst))) "
           "(define (gfx-sprite-pal-override inst def-id) "
           "  (macscheme-gfx-sprite-pal-override (->int inst) (->int def-id))) "
           "(define (gfx-sprite-pal-reset inst) "
           "  (macscheme-gfx-sprite-pal-reset (->int inst))) "
           "(define (gfx-sprite-x inst) (macscheme-gfx-sprite-x (->int inst))) "
           "(define (gfx-sprite-y inst) (macscheme-gfx-sprite-y (->int inst))) "
           "(define (gfx-sprite-rotation inst) (macscheme-gfx-sprite-rotation (->int inst))) "
           "(define (gfx-sprite-visible? inst) "
           "  (not (zero? (macscheme-gfx-sprite-visible (->int inst))))) "
           "(define (gfx-sprite-current-frame inst) "
           "  (macscheme-gfx-sprite-current-frame (->int inst))) "
           "(define (gfx-sprite-hit a b) "
           "  (not (zero? (macscheme-gfx-sprite-hit (->int a) (->int b))))) "
           "(define (gfx-sprite-count) (macscheme-gfx-sprite-count)) "
           "(define (gfx-sprite-collide inst group) "
           "  (macscheme-gfx-sprite-collide (->int inst) (->int group))) "
           "(define (gfx-sprite-overlap group-a group-b) "
           "  (not (zero? (macscheme-gfx-sprite-overlap (->int group-a) (->int group-b))))) "
           "(define (gfx-sprite-sync) (macscheme-gfx-sprite-sync)) "
           "(define (sprite-create! def-id w h) "
           "  (gfx-sprite-def def-id w h)) "
           "(define (sprite-load! def-id path) "
           "  (gfx-sprite-load def-id path)) "
           "(define (sprite-instance! inst-id def-id x y) "
           "  (gfx-sprite inst-id def-id x y)) "
           "(define (sprite-pattern-width rows) "
           "  (cond "
           "    ((null? rows) 0) "
           "    ((vector? rows) (sprite-pattern-width (vector->list rows))) "
           "    (else (string-length (car rows))))) "
           "(define (sprite-pattern-height rows) "
           "  (cond "
           "    ((null? rows) 0) "
           "    ((vector? rows) (vector-length rows)) "
           "    (else (length rows)))) "
           "(define (sprite-pattern->list rows) "
           "  (cond "
           "    ((vector? rows) (vector->list rows)) "
           "    ((list? rows) rows) "
           "    (else (assertion-violation 'sprite-pattern->list \"expected list or vector of strings\" rows)))) "
           "(define (sprite-from-rows! def-id rows) "
           "  (let* ((rows (sprite-pattern->list rows)) "
           "         (h (sprite-pattern-height rows)) "
           "         (w (sprite-pattern-width rows))) "
           "    (when (or (zero? w) (zero? h)) "
           "      (assertion-violation 'sprite-from-rows! \"rows must be non-empty\" rows)) "
           "    (for-each (lambda (row) "
           "                (unless (= (string-length row) w) "
           "                  (assertion-violation 'sprite-from-rows! \"all rows must have the same width\" rows))) "
           "              rows) "
           "    (gfx-sprite-def def-id w h) "
           "    (with-sprite-canvas def-id "
           "      (gfx-cls 0) "
           "      (let loop ((row-index 0) (rest rows)) "
           "        (unless (null? rest) "
           "          (gfx-sprite-row row-index (car rest)) "
           "          (loop (+ row-index 1) (cdr rest))))) "
           "    def-id)) "
           "(define (sprite-show! inst) (gfx-sprite-show inst)) "
           "(define (sprite-hide! inst) (gfx-sprite-hide inst)) "
           "(define (sprite-move! inst dx dy) (gfx-sprite-move inst dx dy)) "
           "(define (sprite-position! inst x y) (gfx-sprite-pos inst x y)) "
           "(define (sprite-scale! inst sx sy) (gfx-sprite-scale inst sx sy)) "
           "(define (sprite-rotate! inst deg) (gfx-sprite-rot inst deg)) "
           "(define (sprite-frame! inst n) (gfx-sprite-frame inst n)) "
           "(define (sprite-animate! inst speed) (gfx-sprite-animate inst speed)) "
           "(define-syntax with-sprite-canvas "
           "  (syntax-rules () "
           "    ((_ sprite-id body ...) "
           "     (begin "
           "       (gfx-sprite-begin sprite-id) "
           "       (dynamic-wind "
           "         (lambda () #f) "
           "         (lambda () body ...) "
           "         (lambda () (gfx-sprite-end))))))) "
           "(define (gfx-line-pal-band y0 y1 idx r g b) "
           "  (let loop ((y (exact (round y0))) (end (exact (round y1)))) "
           "    (when (<= y end) "
           "      (gfx-line-pal y idx r g b) "
           "      (loop (+ y 1) end)))) "
           "(define (gfx-demo-line-palette) "
           "  (begin "
           "    (gfx-reset) "
           "    (gfx-recti 24 16 208 128 17) "
           "    (gfx-line-pal-band 16 47 2 255 32 32) "
           "    (gfx-line-pal-band 48 79 2 255 220 32) "
           "    (gfx-line-pal-band 80 111 2 32 220 255) "
           "    (gfx-line-pal-band 112 143 2 255 32 220) "
           "    (gfx-flip))) "
                        "(define (layout-symbol->id sym) "
                        "  (case sym "
                        "    ((balanced) 1) "
                        "    ((editor-repl) 2) "
                        "    ((editor-graphics) 3) "
                        "    ((focus-editor) 4) "
                        "    ((focus-repl) 5) "
                        "    ((focus-graphics) 6) "
                        "    (else 0))) "
                        "(define (layout-id->symbol n) "
                        "  (case n "
                        "    ((1) 'balanced) "
                        "    ((2) 'editor-repl) "
                        "    ((3) 'editor-graphics) "
                        "    ((4) 'focus-editor) "
                        "    ((5) 'focus-repl) "
                        "    ((6) 'focus-graphics) "
                        "    (else 'custom))) "
                        "(define (layout-pane->id pane) "
                        "  (case pane "
                        "    ((editor) 0) "
                        "    ((repl) 1) "
                        "    ((graphics) 2) "
                        "    (else -1))) "
                        "(define (layout-set! sym) "
                        "  (let ((id (layout-symbol->id sym))) "
                        "    (and (positive? id) (not (zero? (macscheme-layout-set id)))))) "
                        "(define (layout-reset!) (not (zero? (macscheme-layout-reset)))) "
                        "(define (layout-current) (layout-id->symbol (macscheme-layout-current))) "
                        "(define (layout-pane-visible? pane) "
                        "  (let ((id (layout-pane->id pane))) "
                        "    (and (>= id 0) (not (zero? (macscheme-layout-pane-visible id)))))) "
                        "(define (layout-show-pane! pane) "
                        "  (let ((id (layout-pane->id pane))) "
                        "    (and (>= id 0) (not (zero? (macscheme-layout-show-pane id)))))) "
                        "(define (layout-hide-pane! pane) "
                        "  (let ((id (layout-pane->id pane))) "
                        "    (and (>= id 0) (not (zero? (macscheme-layout-hide-pane id)))))) "
                        "(define (layout-toggle-pane! pane) "
                        "  (let ((id (layout-pane->id pane))) "
                        "    (and (>= id 0) (not (zero? (macscheme-layout-toggle-pane id)))))) "
                        "(define (layout-visible-panes) "
                        "  (let ((out '())) "
                        "    (when (layout-pane-visible? 'editor) (set! out (append out '(editor)))) "
                        "    (when (layout-pane-visible? 'repl) (set! out (append out '(repl)))) "
                        "    (when (layout-pane-visible? 'graphics) (set! out (append out '(graphics)))) "
                        "    out)) "
             "(define (macscheme-set-console-size! rows cols) "
             "  (putenv \"LINES\" (format \"~a\" rows)) "
             "  (putenv \"COLUMNS\" (format \"~a\" cols))) "
             "(define (repl-ping) 'pong)) "
           ")";
}

static NSString *MacSchemeResourceBasePath(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleResources = bundle.resourcePath;
    if (bundleResources.length > 0) {
        NSString *petite = [bundleResources stringByAppendingPathComponent:@"petite.boot"];
        NSString *scheme = [bundleResources stringByAppendingPathComponent:@"scheme.boot"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:petite] &&
            [[NSFileManager defaultManager] fileExistsAtPath:scheme]) {
            return bundleResources;
        }
    }

    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd.length > 0) {
        NSString *cwdResources = [cwd stringByAppendingPathComponent:@"resources"];
        NSString *petite = [cwdResources stringByAppendingPathComponent:@"petite.boot"];
        NSString *scheme = [cwdResources stringByAppendingPathComponent:@"scheme.boot"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:petite] &&
            [[NSFileManager defaultManager] fileExistsAtPath:scheme]) {
            return cwdResources;
        }
    }

    return bundleResources ?: @"resources";
}

static NSString *MacSchemeDocsRootPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = fm.currentDirectoryPath ?: @"";
    NSArray<NSString *> *candidates = @[
        [[MacSchemeResourceBasePath() stringByAppendingPathComponent:@"docs"] stringByStandardizingPath],
        [[cwd stringByAppendingPathComponent:@"../docs"] stringByStandardizingPath],
        [[cwd stringByAppendingPathComponent:@"docs"] stringByStandardizingPath],
    ];

    for (NSString *candidate in candidates) {
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) {
            return candidate;
        }
    }

    return candidates.firstObject;
}

static NSURL *MacSchemeHelpEntryURL(void) {
    NSString *docsRoot = MacSchemeDocsRootPath();
    if (docsRoot.length == 0) return nil;

    NSArray<NSString *> *entryCandidates = @[@"index.html", @"csug/csug.html", @"tspl4/index.html"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *relativePath in entryCandidates) {
        NSString *candidate = [docsRoot stringByAppendingPathComponent:relativePath];
        if ([fm fileExistsAtPath:candidate]) {
            return [NSURL fileURLWithPath:candidate];
        }
    }
    return nil;
}

static NSString *MacSchemeHelpFallbackHTML(void) {
    NSString *docsRoot = MacSchemeDocsRootPath() ?: @"(unknown)";
    NSString *escapedRoot = [[docsRoot stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
                             stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    return [NSString stringWithFormat:
            @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
             "<meta name='viewport' content='width=device-width, initial-scale=1'>"
             "<title>MacScheme Help</title>"
             "<style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:52rem;margin:3rem auto;padding:0 1.25rem;line-height:1.6;background:#101419;color:#eef2f7}a{color:#68b5ff}code{background:rgba(255,255,255,.08);padding:.1rem .35rem;border-radius:6px}</style>"
             "</head><body><h1>MacScheme Help</h1><p>The packaged help files were not found.</p><p>Expected docs folder: <code>%@</code></p><p>Rebuild or repackage MacScheme with the bundled docs to restore the help viewer home page and offline references.</p></body></html>",
            escapedRoot];
}

static void layoutSchemeHelpWindow(NSWindow *helpWindow) {
    if (!helpWindow) return;

    NSWindow *editorWindow = g_app_delegate.window ?: [NSApp mainWindow];
    if (editorWindow == helpWindow) {
        editorWindow = [NSApp keyWindow];
    }
    if (editorWindow == helpWindow) {
        editorWindow = nil;
    }

    NSScreen *screen = editorWindow ? editorWindow.screen : [NSScreen mainScreen];
    if (!screen) return;

    NSRect screenFrame = screen.visibleFrame;
    const CGFloat gap = 8.0;
    const CGFloat desiredHelpWidth = 480.0;
    const CGFloat minHelpWidth = 360.0;

    if (editorWindow) {
        NSRect editorFrame = editorWindow.frame;

        if (editorFrame.origin.x < screenFrame.origin.x) {
            editorFrame.origin.x = screenFrame.origin.x;
        }
        if (editorFrame.origin.y < screenFrame.origin.y) {
            editorFrame.origin.y = screenFrame.origin.y;
        }
        if (NSMaxY(editorFrame) > NSMaxY(screenFrame)) {
            editorFrame.origin.y = NSMaxY(screenFrame) - editorFrame.size.height;
        }

        CGFloat availableRight = NSMaxX(screenFrame) - NSMaxX(editorFrame) - gap;
        if (availableRight < desiredHelpWidth) {
            CGFloat maxShiftLeft = editorFrame.origin.x - screenFrame.origin.x;
            CGFloat needed = desiredHelpWidth - availableRight;
            CGFloat shift = MIN(maxShiftLeft, needed);
            editorFrame.origin.x -= shift;
            availableRight += shift;

            if (availableRight < desiredHelpWidth) {
                CGFloat minEditorWidth = editorWindow.minSize.width;
                CGFloat reduce = desiredHelpWidth - availableRight;
                CGFloat newWidth = MAX(minEditorWidth, editorFrame.size.width - reduce);
                availableRight += (editorFrame.size.width - newWidth);
                editorFrame.size.width = newWidth;
            }
        }

        [editorWindow setFrame:editorFrame display:YES animate:YES];

        availableRight = NSMaxX(screenFrame) - NSMaxX(editorFrame) - gap;
        CGFloat helpWidth = MIN(desiredHelpWidth, availableRight);
        if (helpWidth < minHelpWidth) {
            helpWidth = MIN(minHelpWidth, availableRight);
        }
        if (helpWidth < 200.0) {
            helpWidth = MAX(200.0, availableRight);
        }

        CGFloat helpX = NSMaxX(editorFrame) + gap;
        CGFloat helpHeight = screenFrame.size.height;
        CGFloat helpY = screenFrame.origin.y;

        if (helpX + helpWidth > NSMaxX(screenFrame)) {
            helpX = NSMaxX(screenFrame) - helpWidth;
        }

        [helpWindow setFrame:NSMakeRect(helpX, helpY, helpWidth, helpHeight)
                     display:YES
                     animate:YES];
    } else {
        CGFloat helpWidth = MIN(desiredHelpWidth, screenFrame.size.width);
        CGFloat helpX = NSMaxX(screenFrame) - helpWidth;
        [helpWindow setFrame:NSMakeRect(helpX,
                                        screenFrame.origin.y,
                                        helpWidth,
                                        screenFrame.size.height)
                     display:YES
                     animate:YES];
    }
}

@interface MacSchemeHelpWindowController : NSWindowController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSView *navigationBar;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *homeButton;
- (void)showHomePage;
- (void)navigateBack;
- (void)navigateForward;
- (BOOL)canNavigateBack;
- (BOOL)canNavigateForward;
- (void)updateNavigationControls;
@end

@implementation MacSchemeHelpWindowController

- (instancetype)init {
    NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
    const CGFloat defaultWidth = 480.0;
    const CGFloat defaultHeight = 640.0;
    NSRect windowRect = NSMakeRect(screenRect.origin.x + (screenRect.size.width - defaultWidth) * 0.5,
                                   screenRect.origin.y + (screenRect.size.height - defaultHeight) * 0.5,
                                   defaultWidth,
                                   defaultHeight);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Scheme Help"];

    self = [super initWithWindow:window];
    if (self) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        NSView *contentView = window.contentView;
        const CGFloat navBarHeight = 38.0;

        _navigationBar = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                                  contentView.bounds.size.height - navBarHeight,
                                                                  contentView.bounds.size.width,
                                                                  navBarHeight)];
        _navigationBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        _navigationBar.wantsLayer = YES;
        _navigationBar.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.96 alpha:0.96].CGColor;

        _backButton = [NSButton buttonWithTitle:@"Back" target:self action:@selector(navigateBack)];
        _backButton.frame = NSMakeRect(12, 7, 56, 24);
        _backButton.bezelStyle = NSBezelStyleRounded;

        _forwardButton = [NSButton buttonWithTitle:@"Forward" target:self action:@selector(navigateForward)];
        _forwardButton.frame = NSMakeRect(74, 7, 72, 24);
        _forwardButton.bezelStyle = NSBezelStyleRounded;

        _homeButton = [NSButton buttonWithTitle:@"Home" target:self action:@selector(showHomePage)];
        _homeButton.frame = NSMakeRect(152, 7, 60, 24);
        _homeButton.bezelStyle = NSBezelStyleRounded;

        [_navigationBar addSubview:_backButton];
        [_navigationBar addSubview:_forwardButton];
        [_navigationBar addSubview:_homeButton];

        _webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0,
                                                               0,
                                                               contentView.bounds.size.width,
                                                               contentView.bounds.size.height - navBarHeight)
                                      configuration:config];
        _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _webView.navigationDelegate = self;
        [contentView addSubview:_webView];
        [contentView addSubview:_navigationBar];
        [self updateNavigationControls];
    }
    return self;
}

- (void)showHomePage {
    layoutSchemeHelpWindow(self.window);
    if (!self.window.isVisible) {
        [self showWindow:nil];
    }
    [self.window makeKeyAndOrderFront:nil];

    NSURL *entryURL = MacSchemeHelpEntryURL();
    if (entryURL) {
        NSURL *docsRootURL = [NSURL fileURLWithPath:MacSchemeDocsRootPath() isDirectory:YES];
        [self.webView loadFileURL:entryURL allowingReadAccessToURL:docsRootURL];
    } else {
        [self.webView loadHTMLString:MacSchemeHelpFallbackHTML() baseURL:nil];
    }
    [self updateNavigationControls];
}

- (void)navigateBack {
    layoutSchemeHelpWindow(self.window);
    if (!self.window.isVisible) {
        [self showWindow:nil];
    }
    [self.window makeKeyAndOrderFront:nil];
    if (self.webView.canGoBack) {
        [self.webView goBack];
    }
    [self updateNavigationControls];
}

- (void)navigateForward {
    layoutSchemeHelpWindow(self.window);
    if (!self.window.isVisible) {
        [self showWindow:nil];
    }
    [self.window makeKeyAndOrderFront:nil];
    if (self.webView.canGoForward) {
        [self.webView goForward];
    }
    [self updateNavigationControls];
}

- (BOOL)canNavigateBack {
    return self.webView.canGoBack;
}

- (BOOL)canNavigateForward {
    return self.webView.canGoForward;
}

- (void)updateNavigationControls {
    self.backButton.enabled = self.webView.canGoBack;
    self.forwardButton.enabled = self.webView.canGoForward;
    self.homeButton.enabled = YES;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    [self updateNavigationControls];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    [self updateNavigationControls];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    (void)error;
    [self updateNavigationControls];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    (void)error;
    [self updateNavigationControls];
}

@end

static MacSchemeHelpWindowController *gMacSchemeHelpController = nil;

static NSString *CurrentEditorPath(void) {
    size_t pathLen = 0;
    const uint8_t *pathBytes = grid_get_editor_file_path(&pathLen);
    NSString *path = nil;
    if (pathBytes && pathLen > 0) {
        path = [[NSString alloc] initWithBytes:pathBytes length:pathLen encoding:NSUTF8StringEncoding];
        grid_free_bytes(pathBytes, pathLen);
    }
    return path;
}

static BOOL WriteEditorBufferToPath(NSString *path, NSError **outError) {
    size_t textLen = 0;
    const uint8_t *textBytes = grid_copy_text(0, &textLen);
    if (!textBytes) return NO;
    NSData *data = [NSData dataWithBytes:textBytes length:textLen];
    grid_free_bytes(textBytes, textLen);
    return [data writeToFile:path options:NSDataWritingAtomic error:outError];
}

typedef NS_ENUM(NSInteger, MacSchemeThemeId) {
    MacSchemeThemeFasterBASIC = 0,
    MacSchemeThemeNeon,
    MacSchemeThemeRetro,
    MacSchemeThemeRetroCRT,
    MacSchemeThemeRetroAmberCRT,
    MacSchemeThemePaperWhite,
    MacSchemeThemeC64,
    MacSchemeThemeDracula,
    MacSchemeThemeMonokai,
    MacSchemeThemeSynthwave,
    MacSchemeThemeTokyoNight,
    MacSchemeThemeGruvboxDark,
    MacSchemeThemeSolarizedDarkPlus,
    MacSchemeThemeNordMidnight,
    MacSchemeThemeOneDarkVibrant,
};

static NSArray<NSString *> *MacSchemeThemeNames(void) {
    static NSArray<NSString *> *names = nil;
    if (names == nil) {
        names = @[
            @"Faster",
            @"Neon",
            @"Retro",
            @"Retro CRT",
            @"Retro Amber CRT",
            @"Paper White",
            @"Commodore 64",
            @"Dracula",
            @"Monokai",
            @"Synthwave '84",
            @"Tokyo Night",
            @"Gruvbox Dark",
            @"Solarized Dark+",
            @"Nord Midnight",
            @"One Dark Vibrant",
        ];
    }
    return names;
}

static NSInteger MacSchemeCurrentTheme(void) {
    return (NSInteger)grid_get_theme();
}

static NSMenuItem *AddMenuItem(NSMenu *menu, NSString *title, SEL action, NSString *keyEquivalent, NSEventModifierFlags modifiers, id target) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:keyEquivalent ?: @""];
    item.keyEquivalentModifierMask = modifiers;
    item.target = target;
    [menu addItem:item];
    return item;
}

static NSMenuItem *AddFunctionKeyMenuItem(NSMenu *menu, NSString *title, SEL action, unichar functionKey, id target) {
    NSString *keyEquivalent = [NSString stringWithCharacters:&functionKey length:1];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:keyEquivalent];
    item.keyEquivalentModifierMask = 0;
    item.target = target;
    [menu addItem:item];
    return item;
}

static NSMenuItem *AddModifiedFunctionKeyMenuItem(NSMenu *menu, NSString *title, SEL action, unichar functionKey, NSEventModifierFlags modifiers, id target) {
    NSString *keyEquivalent = [NSString stringWithCharacters:&functionKey length:1];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:keyEquivalent];
    item.keyEquivalentModifierMask = modifiers;
    item.target = target;
    [menu addItem:item];
    return item;
}

typedef NS_ENUM(uint32_t, MacSchemeEditorKeyCode) {
    MacSchemeEditorKeyF = 3,
    MacSchemeEditorKeyQ = 12,
    MacSchemeEditorKeyW = 13,
    MacSchemeEditorKeyE = 14,
    MacSchemeEditorKeyB = 11,
    MacSchemeEditorKeyUp = 126,
    MacSchemeEditorKeyLeft = 123,
    MacSchemeEditorKeyRight = 124,
    MacSchemeEditorKeyEnter = 36,
    MacSchemeEditorKeyTab = 48,
};

static const uint32_t MacSchemeGridModShift = 1;
static const uint32_t MacSchemeGridModControl = 2;
static const uint32_t MacSchemeGridModAlt = 4;
static const uint32_t MacSchemeGridModCommand = 8;

static NSInteger MacSchemeGraphicsModeTag(int64_t width, int64_t height) {
    return (NSInteger)((((uint64_t)width & 0xFFFFu) << 16) | ((uint64_t)height & 0xFFFFu));
}

static int64_t MacSchemeGraphicsModeWidth(NSInteger tag) {
    return (int64_t)(((uint64_t)tag >> 16) & 0xFFFFu);
}

static int64_t MacSchemeGraphicsModeHeight(NSInteger tag) {
    return (int64_t)((uint64_t)tag & 0xFFFFu);
}

static void MacSchemeApplyDefaultGraphicsPalette(void) {
    macscheme_gfx_reset_palette();
    macscheme_gfx_palette(16, 0, 0, 0);
    macscheme_gfx_palette(17, 255, 255, 255);
    macscheme_gfx_palette(18, 255, 0, 0);
    macscheme_gfx_palette(19, 0, 255, 0);
    macscheme_gfx_palette(20, 0, 0, 255);
    macscheme_gfx_palette(21, 255, 255, 0);
    macscheme_gfx_palette(22, 0, 255, 255);
    macscheme_gfx_palette(23, 255, 0, 255);
    macscheme_gfx_palette(24, 255, 128, 0);
    macscheme_gfx_palette(25, 128, 128, 128);
    macscheme_gfx_palette(26, 64, 64, 64);
    macscheme_gfx_palette(27, 255, 128, 128);
    macscheme_gfx_palette(28, 128, 255, 128);
    macscheme_gfx_palette(29, 128, 128, 255);
    macscheme_gfx_palette(30, 255, 220, 128);
    macscheme_gfx_palette(31, 220, 220, 220);
}

static void MacSchemeClearAllGraphicsBuffers(int64_t colourIndex) {
    for (int64_t buffer = 0; buffer < 8; buffer++) {
        macscheme_gfx_set_target(buffer);
        macscheme_gfx_cls(colourIndex);
    }
    macscheme_gfx_set_target(1);
}

@interface AppDelegate ()
@property (strong) NSSplitViewController *rightSplitController;
@property (strong) NSSplitViewItem *editorSplitItem;
@property (strong) NSSplitViewItem *rightSplitItem;
@property (strong) NSSplitViewItem *graphicsSplitItem;
@property (strong) NSSplitViewItem *replSplitItem;
@property (assign) BOOL editorPaneVisible;
@property (assign) BOOL replPaneVisible;
@property (assign) BOOL graphicsPaneVisible;
@property (assign) CGFloat savedMainSplitRatio;
@property (assign) CGFloat savedRightSplitRatio;
@property (assign) MacSchemeLayoutPreset currentLayoutPreset;
@property (strong) NSTimer *syntaxCheckTimer;
@property (assign) uint64_t lastSyntaxCheckedRevision;
- (void)showAboutDialog:(id)sender;
- (void)showSchemeHelp:(id)sender;
- (void)showSchemeHelpHome:(id)sender;
- (void)showSchemeHelpBack:(id)sender;
- (void)showSchemeHelpForward:(id)sender;
- (void)stopScheme:(id)sender;
- (BOOL)applyLayoutPreset:(MacSchemeLayoutPreset)preset;
- (BOOL)setPane:(MacSchemePane)pane visible:(BOOL)visible;
- (BOOL)isPaneVisible:(MacSchemePane)pane;
- (void)selectTheme:(id)sender;
- (void)cycleTheme:(id)sender;
- (void)clearGraphics:(id)sender;
- (void)selectGraphicsMode:(id)sender;
- (void)moveBackwardSexp:(id)sender;
- (void)moveForwardSexp:(id)sender;
- (void)selectEnclosingForm:(id)sender;
- (void)wrapSelectionInParentheses:(id)sender;
- (void)spliceEnclosingForm:(id)sender;
- (void)slurpForward:(id)sender;
- (void)barfForward:(id)sender;
- (void)reindentCurrentLine:(id)sender;
- (void)reindentSelectionOrLine:(id)sender;
- (void)formatSourceCode:(id)sender;
- (void)tickSyntaxCheck:(NSTimer *)timer;
@end

@interface GraphicsPlaceholderView : NSView
{
    uint32_t _globalPalette[240];
    uint32_t _linePalette[160][16];
}
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, assign) uint8_t *pixelBuffer;
@property (nonatomic, assign) NSUInteger pixelWidth;
@property (nonatomic, assign) NSUInteger pixelHeight;
@property (nonatomic, assign) BOOL paletteCycleEnabled;
@property (nonatomic, strong) NSTimer *animationTimer;
@end

@implementation GraphicsPlaceholderView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.fillColor = [NSColor colorWithCalibratedRed:0.10 green:0.20 blue:0.30 alpha:1.0];
        _pixelWidth = 256;
        _pixelHeight = 160;
        _pixelBuffer = calloc(_pixelWidth * _pixelHeight, 1);

        for (NSUInteger i = 0; i < 240; i++) {
            uint8_t v = (uint8_t)i;
            _globalPalette[i] = 0xFF000000u | ((uint32_t)v << 16) | ((uint32_t)v << 8) | (uint32_t)v;
        }

        uint32_t defaults[16] = {
            0xFF101820u, 0xFF3FA34Du, 0xFFE0FBFCu, 0xFFF4A261u,
            0xFFE63946u, 0xFF457B9Du, 0xFFA8DADCu, 0xFF2A9D8Fu,
            0xFFE9C46Au, 0xFF264653u, 0xFFD62828u, 0xFF8ECAE6u,
            0xFFFFB703u, 0xFFFB8500u, 0xFFCDB4DBu, 0xFFFFFFFFu,
        };
        for (NSUInteger y = 0; y < 160; y++) {
            for (NSUInteger i = 0; i < 16; i++) {
                _linePalette[y][i] = defaults[i];
            }
        }
        self.wantsLayer = YES;
    }
    return self;
}

- (void)dealloc {
    if (_animationTimer) {
        [_animationTimer invalidate];
    }
    if (_pixelBuffer) {
        free(_pixelBuffer);
    }
}

- (BOOL)isFlipped { return YES; }

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    if (!ctx || !self.pixelBuffer) {
        [self.fillColor setFill];
        NSRectFill(dirtyRect);
        return;
    }

    size_t count = self.pixelWidth * self.pixelHeight;
    uint32_t *rgba = malloc(count * sizeof(uint32_t));
    if (!rgba) return;

    for (NSUInteger y = 0; y < self.pixelHeight; y++) {
        for (NSUInteger x = 0; x < self.pixelWidth; x++) {
            size_t i = y * self.pixelWidth + x;
            uint8_t idx = self.pixelBuffer[i];
            if (idx < 16) {
                rgba[i] = _linePalette[y][idx];
            } else {
                rgba[i] = _globalPalette[idx - 16];
            }
        }
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmp = CGBitmapContextCreate(rgba,
                                             self.pixelWidth,
                                             self.pixelHeight,
                                             8,
                                             self.pixelWidth * sizeof(uint32_t),
                                             colorSpace,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!bmp) {
        free(rgba);
        return;
    }

    CGImageRef image = CGBitmapContextCreateImage(bmp);
    CGContextRelease(bmp);
    free(rgba);
    if (!image) return;

    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, 0, self.bounds.size.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextDrawImage(ctx, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height), image);
    CGContextRestoreGState(ctx);
    CGImageRelease(image);
}

- (void)clearIndex:(uint8_t)index {
    if (!self.pixelBuffer) return;
    memset(self.pixelBuffer, index, self.pixelWidth * self.pixelHeight);
    [self setNeedsDisplay:YES];
}

- (void)fillRectX:(NSInteger)x y:(NSInteger)y width:(NSInteger)w height:(NSInteger)h index:(uint8_t)index {
    if (!self.pixelBuffer) return;
    NSInteger x0 = MAX(0, x);
    NSInteger y0 = MAX(0, y);
    NSInteger x1 = MIN((NSInteger)self.pixelWidth, x + w);
    NSInteger y1 = MIN((NSInteger)self.pixelHeight, y + h);
    if (x1 <= x0 || y1 <= y0) return;

    for (NSInteger yy = y0; yy < y1; yy++) {
        memset(self.pixelBuffer + yy * self.pixelWidth + x0, index, (size_t)(x1 - x0));
    }
    [self setNeedsDisplay:YES];
}

- (void)setPaletteIndex:(uint8_t)index red:(uint8_t)r green:(uint8_t)g blue:(uint8_t)b {
    if (index < 16) {
        for (NSUInteger y = 0; y < self.pixelHeight; y++) {
            _linePalette[y][index] = 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
        }
    } else {
        _globalPalette[index - 16] = 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
    }
    [self setNeedsDisplay:YES];
}

- (void)setLinePaletteLine:(NSUInteger)line index:(uint8_t)index red:(uint8_t)r green:(uint8_t)g blue:(uint8_t)b {
    if (line >= self.pixelHeight || index >= 16) return;
    _linePalette[line][index] = 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
    [self setNeedsDisplay:YES];
}

- (void)tickPaletteCycle:(NSTimer *)timer {
    (void)timer;
    if (!self.paletteCycleEnabled) return;
    uint32_t last = _globalPalette[15];
    for (NSInteger i = 15; i > 0; i--) {
        _globalPalette[i] = _globalPalette[i - 1];
    }
    _globalPalette[0] = last;
    [self setNeedsDisplay:YES];
}

- (void)setPaletteCycleEnabled:(BOOL)paletteCycleEnabled {
    _paletteCycleEnabled = paletteCycleEnabled;
    if (paletteCycleEnabled) {
        if (!self.animationTimer) {
            self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.08
                                                                   target:self
                                                                 selector:@selector(tickPaletteCycle:)
                                                                 userInfo:nil
                                                                  repeats:YES];
        }
    } else {
        [self.animationTimer invalidate];
        self.animationTimer = nil;
    }
}

@end

static void appendReplText(NSString *text, BOOL isError) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        const char *fallback = "<encoding error>\n";
        grid_append_repl_output((const unsigned char *)fallback, strlen(fallback), isError ? 1 : 0);
        return;
    }
    grid_append_repl_output((const unsigned char *)data.bytes, data.length, isError ? 1 : 0);
}

static void appendReplPrompt(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    grid_append_repl_prompt((const unsigned char *)data.bytes, data.length);
}

static void appendReplTextAsync(NSString *text, BOOL isError) {
    if (text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        appendReplText(text, isError);
    });
}

void macscheme_repl_write_output(const char *utf8) {
    if (!utf8) return;
    NSString *text = [[NSString alloc] initWithUTF8String:utf8];
    if (!text) return;
    appendReplTextAsync(text, NO);
}

void macscheme_repl_write_error(const char *utf8) {
    if (!utf8) return;
    NSString *text = [[NSString alloc] initWithUTF8String:utf8];
    if (!text) return;
    appendReplTextAsync(text, YES);
}

static NSString *SchemeObjectToNSString(ptr value) {
    if (Sstringp(value)) {
        iptr len = Sstring_length(value);
        NSMutableString *out = [NSMutableString stringWithCapacity:(NSUInteger)len];
        for (iptr i = 0; i < len; i++) {
            unsigned int cp = (unsigned int)Sstring_ref(value, i);
            if (cp <= 0xFFFF) {
                [out appendFormat:@"%C", (unichar)cp];
            } else {
                cp -= 0x10000;
                unichar high = (unichar)((cp >> 10) + 0xD800);
                unichar low  = (unichar)((cp & 0x3FF) + 0xDC00);
                [out appendFormat:@"%C%C", high, low];
            }
        }
        return out;
    }

    if (Ssymbolp(value)) {
        ptr s = Ssymbol_to_string(value);
        return SchemeObjectToNSString(s);
    }

    if (Sfixnump(value)) {
        return [NSString stringWithFormat:@"%ld", (long)Sfixnum_value(value)];
    }

    if (Sbooleanp(value)) {
        return Sboolean_value(value) ? @"#t" : @"#f";
    }

    if (Snullp(value)) return @"()";
    if (Seof_objectp(value)) return @"#<eof>";
    if (value == Svoid) return @"";
    return @"#<object>";
}

static NSString *EvaluateSchemeExpression(NSString *input, BOOL *outError) {
    *outError = NO;

    ptr proc = Stop_level_value(Sstring_to_symbol("macscheme-eval-string"));
    if (!Sprocedurep(proc)) {
        *outError = YES;
        return @"macscheme-eval-string is not available";
    }

    ptr arg = Sstring_utf8(input.UTF8String, (iptr)[input lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    ptr result = Scall1(proc, arg);

    if (Spairp(result)) {
        ptr tag = Scar(result);
        ptr rest = Scdr(result);
        if (Spairp(rest)) {
            ptr text_value = Scar(rest);
            if (Sbooleanp(tag)) {
                *outError = Sboolean_value(tag);
            }
            NSString *text = SchemeObjectToNSString(text_value);
            if (text) return text;
        }
    }

    NSString *text = SchemeObjectToNSString(result);
    if (!text) {
        *outError = YES;
        return @"<evaluation failed>";
    }
    return text;
}

static NSArray<NSString *> *EvaluateSchemeCompletions(NSString *prefix) {
    ptr proc = Stop_level_value(Sstring_to_symbol("macscheme-get-completions"));
    if (!Sprocedurep(proc)) {
        return @[];
    }

    ptr arg = Sstring_utf8(prefix.UTF8String, (iptr)[prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    ptr result = Scall1(proc, arg);
    NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet];

    ptr list = result;
    while (Spairp(list)) {
        NSString *text = SchemeObjectToNSString(Scar(list));
        if (text.length > 0) {
            [out addObject:text];
        }
        list = Scdr(list);
    }

    return [[out array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

// Called from the Zig grid when the user submits an expression.
// Enqueues the expression for the dedicated Scheme pthread to evaluate.
void macscheme_eval_async(const unsigned char *bytes, size_t len) {
    if (!g_app_delegate || !g_app_delegate.schemeReady || !bytes || len == 0) return;
    scheme_enqueue(SchemeRequestEval, (const char *)bytes, len);
}

void macscheme_get_completions(const unsigned char *bytes, size_t len) {
    if (!g_app_delegate || !g_app_delegate.schemeReady || !bytes) return;
    scheme_enqueue(SchemeRequestCompletions, (const char *)bytes, len);
}

int64_t macscheme_layout_set(int64_t preset) {
    if (!g_app_delegate) return 0;
    __block BOOL ok = NO;
    MacSchemeDispatchSyncOnMain(^{
        ok = [g_app_delegate applyLayoutPreset:(MacSchemeLayoutPreset)preset];
    });
    return ok ? 1 : 0;
}

int64_t macscheme_layout_show_pane(int64_t pane) {
    if (!g_app_delegate) return 0;
    __block BOOL ok = NO;
    MacSchemeDispatchSyncOnMain(^{
        ok = [g_app_delegate setPane:(MacSchemePane)pane visible:YES];
    });
    return ok ? 1 : 0;
}

int64_t macscheme_layout_hide_pane(int64_t pane) {
    if (!g_app_delegate) return 0;
    __block BOOL ok = NO;
    MacSchemeDispatchSyncOnMain(^{
        ok = [g_app_delegate setPane:(MacSchemePane)pane visible:NO];
    });
    return ok ? 1 : 0;
}

int64_t macscheme_layout_toggle_pane(int64_t pane) {
    if (!g_app_delegate) return 0;
    __block BOOL ok = NO;
    MacSchemeDispatchSyncOnMain(^{
        BOOL visible = [g_app_delegate isPaneVisible:(MacSchemePane)pane];
        ok = [g_app_delegate setPane:(MacSchemePane)pane visible:!visible];
    });
    return ok ? 1 : 0;
}

int64_t macscheme_layout_reset(void) {
    return macscheme_layout_set(MacSchemeLayoutPresetBalanced);
}

int64_t macscheme_layout_current(void) {
    if (!g_app_delegate) return MacSchemeLayoutPresetCustom;
    __block int64_t current = MacSchemeLayoutPresetCustom;
    MacSchemeDispatchSyncOnMain(^{
        current = g_app_delegate.currentLayoutPreset;
    });
    return current;
}

int64_t macscheme_layout_pane_visible(int64_t pane) {
    if (!g_app_delegate) return 0;
    __block BOOL visible = NO;
    MacSchemeDispatchSyncOnMain(^{
        visible = [g_app_delegate isPaneVisible:(MacSchemePane)pane];
    });
    return visible ? 1 : 0;
}

@implementation AppDelegate

- (NSUInteger)visiblePaneCount {
    NSUInteger count = 0;
    if (self.editorPaneVisible) count++;
    if (self.replPaneVisible) count++;
    if (self.graphicsPaneVisible) count++;
    return count;
}

- (BOOL)isPaneVisible:(MacSchemePane)pane {
    switch (pane) {
        case MacSchemePaneEditor: return self.editorPaneVisible;
        case MacSchemePaneRepl: return self.replPaneVisible;
        case MacSchemePaneGraphics: return self.graphicsPaneVisible;
    }
    return NO;
}

- (MacSchemeLayoutPreset)derivedLayoutPreset {
    BOOL editor = self.editorPaneVisible;
    BOOL repl = self.replPaneVisible;
    BOOL graphics = self.graphicsPaneVisible;
    if (editor && repl && graphics) return MacSchemeLayoutPresetBalanced;
    if (editor && repl && !graphics) return MacSchemeLayoutPresetEditorRepl;
    if (editor && !repl && graphics) return MacSchemeLayoutPresetEditorGraphics;
    if (editor && !repl && !graphics) return MacSchemeLayoutPresetFocusEditor;
    if (!editor && repl && !graphics) return MacSchemeLayoutPresetFocusRepl;
    if (!editor && !repl && graphics) return MacSchemeLayoutPresetFocusGraphics;
    return MacSchemeLayoutPresetCustom;
}

- (void)captureVisibleSplitRatios {
    if (self.editorSplitItem && self.rightSplitItem && !self.editorSplitItem.isCollapsed && !self.rightSplitItem.isCollapsed) {
        CGFloat width = self.splitViewController.splitView.bounds.size.width;
        if (width > 1.0) {
            self.savedMainSplitRatio = ClampSplitRatio(FirstSplitSubviewExtent(self.splitViewController.splitView) / width);
        }
    }
    if (self.graphicsSplitItem && self.replSplitItem && !self.graphicsSplitItem.isCollapsed && !self.replSplitItem.isCollapsed) {
        CGFloat height = self.rightSplitController.splitView.bounds.size.height;
        if (height > 1.0) {
            self.savedRightSplitRatio = ClampSplitRatio(FirstSplitSubviewExtent(self.rightSplitController.splitView) / height);
        }
    }
}

- (void)applyPaneVisibilityWithMainRatio:(CGFloat)mainRatio rightRatio:(CGFloat)rightRatio {
    if (!self.editorPaneVisible && !self.replPaneVisible && !self.graphicsPaneVisible) {
        self.editorPaneVisible = YES;
    }

    BOOL rightVisible = self.replPaneVisible || self.graphicsPaneVisible;
    self.editorSplitItem.collapsed = !self.editorPaneVisible;
    self.rightSplitItem.collapsed = !rightVisible;
    self.graphicsSplitItem.collapsed = !self.graphicsPaneVisible;
    self.replSplitItem.collapsed = !self.replPaneVisible;

    [self.window layoutIfNeeded];
    [self.splitViewController.view layoutSubtreeIfNeeded];
    [self.rightSplitController.view layoutSubtreeIfNeeded];

    if (self.editorPaneVisible && rightVisible) {
        CGFloat width = self.splitViewController.splitView.bounds.size.width;
        if (width > 1.0) {
            [self.splitViewController.splitView setPosition:width * ClampSplitRatio(mainRatio) ofDividerAtIndex:0];
        }
    }
    if (self.graphicsPaneVisible && self.replPaneVisible) {
        CGFloat height = self.rightSplitController.splitView.bounds.size.height;
        if (height > 1.0) {
            [self.rightSplitController.splitView setPosition:height * ClampSplitRatio(rightRatio) ofDividerAtIndex:0];
        }
    }

    [self.window layoutIfNeeded];
}

- (void)updateLayoutMenuState {
    [NSApp.mainMenu update];
}

- (BOOL)applyLayoutPreset:(MacSchemeLayoutPreset)preset {
    CGFloat mainRatio = self.savedMainSplitRatio > 0.0 ? self.savedMainSplitRatio : kMacSchemeBalancedMainRatio;
    CGFloat rightRatio = self.savedRightSplitRatio > 0.0 ? self.savedRightSplitRatio : kMacSchemeBalancedRightRatio;

    switch (preset) {
        case MacSchemeLayoutPresetBalanced:
            self.editorPaneVisible = YES;
            self.replPaneVisible = YES;
            self.graphicsPaneVisible = YES;
            mainRatio = kMacSchemeBalancedMainRatio;
            rightRatio = kMacSchemeBalancedRightRatio;
            break;
        case MacSchemeLayoutPresetEditorRepl:
            self.editorPaneVisible = YES;
            self.replPaneVisible = YES;
            self.graphicsPaneVisible = NO;
            mainRatio = kMacSchemeEditorReplMainRatio;
            break;
        case MacSchemeLayoutPresetEditorGraphics:
            self.editorPaneVisible = YES;
            self.replPaneVisible = NO;
            self.graphicsPaneVisible = YES;
            mainRatio = kMacSchemeEditorGraphicsMainRatio;
            break;
        case MacSchemeLayoutPresetFocusEditor:
            self.editorPaneVisible = YES;
            self.replPaneVisible = NO;
            self.graphicsPaneVisible = NO;
            break;
        case MacSchemeLayoutPresetFocusRepl:
            self.editorPaneVisible = NO;
            self.replPaneVisible = YES;
            self.graphicsPaneVisible = NO;
            break;
        case MacSchemeLayoutPresetFocusGraphics:
            self.editorPaneVisible = NO;
            self.replPaneVisible = NO;
            self.graphicsPaneVisible = YES;
            break;
        default:
            return NO;
    }

    self.savedMainSplitRatio = ClampSplitRatio(mainRatio);
    self.savedRightSplitRatio = ClampSplitRatio(rightRatio);
    [self applyPaneVisibilityWithMainRatio:self.savedMainSplitRatio rightRatio:self.savedRightSplitRatio];
    self.currentLayoutPreset = preset;
    [self updateLayoutMenuState];
    return YES;
}

- (BOOL)setPane:(MacSchemePane)pane visible:(BOOL)visible {
    if (pane < MacSchemePaneEditor || pane > MacSchemePaneGraphics) return NO;
    if ([self isPaneVisible:pane] == visible) return YES;
    if (!visible && [self visiblePaneCount] <= 1) return NO;

    [self captureVisibleSplitRatios];
    switch (pane) {
        case MacSchemePaneEditor: self.editorPaneVisible = visible; break;
        case MacSchemePaneRepl: self.replPaneVisible = visible; break;
        case MacSchemePaneGraphics: self.graphicsPaneVisible = visible; break;
    }

    [self applyPaneVisibilityWithMainRatio:self.savedMainSplitRatio rightRatio:self.savedRightSplitRatio];
    self.currentLayoutPreset = [self derivedLayoutPreset];
    [self updateLayoutMenuState];
    return YES;
}

- (void)selectLayoutPreset:(id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : 0;
    [self applyLayoutPreset:(MacSchemeLayoutPreset)tag];
}

- (void)toggleLayoutPane:(id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : -1;
    if (tag < MacSchemePaneEditor || tag > MacSchemePaneGraphics) return;
    BOOL visible = [self isPaneVisible:(MacSchemePane)tag];
    [self setPane:(MacSchemePane)tag visible:!visible];
}

- (void)resetLayout:(id)sender {
    (void)sender;
    [self applyLayoutPreset:MacSchemeLayoutPresetBalanced];
}

- (void)selectTheme:(id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : 0;
    grid_set_theme((int)tag);
}

- (void)cycleTheme:(id)sender {
    (void)sender;
    NSInteger current = MacSchemeCurrentTheme();
    NSInteger next = (current + 1) % MacSchemeThemeNames().count;
    grid_set_theme((int)next);
}

- (void)clearGraphics:(id)sender {
    (void)sender;
    if (macscheme_gfx_screen_active() == 0) return;
    MacSchemeClearAllGraphicsBuffers(16);
}

- (void)selectGraphicsMode:(id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : 0;
    int64_t width = MacSchemeGraphicsModeWidth(tag);
    int64_t height = MacSchemeGraphicsModeHeight(tag);
    if (width <= 0 || height <= 0) return;

    [self setPane:MacSchemePaneGraphics visible:YES];
    macscheme_gfx_screen(width, height, 1);
    MacSchemeApplyDefaultGraphicsPalette();
    macscheme_gfx_cls(16);
    macscheme_gfx_flip();
    [NSApp.mainMenu update];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(stopScheme:)) {
        return self.schemeReady && g_scheme_eval_active != 0;
    }
    if (menuItem.action == @selector(moveBackwardSexp:) ||
        menuItem.action == @selector(moveForwardSexp:) ||
        menuItem.action == @selector(selectEnclosingForm:) ||
        menuItem.action == @selector(spliceEnclosingForm:) ||
        menuItem.action == @selector(slurpForward:) ||
        menuItem.action == @selector(barfForward:) ||
        menuItem.action == @selector(reindentCurrentLine:) ||
        menuItem.action == @selector(reindentSelectionOrLine:) ||
        menuItem.action == @selector(formatSourceCode:)) {
        return [self editorGridView] != nil;
    }
    if (menuItem.action == @selector(wrapSelectionInParentheses:)) {
        return [self editorGridView] != nil && [self editorHasSelection];
    }
    if (menuItem.action == @selector(selectLayoutPreset:)) {
        menuItem.state = (menuItem.tag == self.currentLayoutPreset) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (menuItem.action == @selector(toggleLayoutPane:)) {
        BOOL visible = [self isPaneVisible:(MacSchemePane)menuItem.tag];
        menuItem.state = visible ? NSControlStateValueOn : NSControlStateValueOff;
        if (visible && [self visiblePaneCount] <= 1) {
            return NO;
        }
        return YES;
    }
    if (menuItem.action == @selector(selectTheme:)) {
        menuItem.state = (menuItem.tag == MacSchemeCurrentTheme()) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (menuItem.action == @selector(clearGraphics:)) {
        return macscheme_gfx_screen_active() != 0;
    }
    if (menuItem.action == @selector(selectGraphicsMode:)) {
        int64_t width = macscheme_gfx_screen_width();
        int64_t height = macscheme_gfx_screen_height();
        menuItem.state = (macscheme_gfx_screen_active() != 0 &&
                          width == MacSchemeGraphicsModeWidth(menuItem.tag) &&
                          height == MacSchemeGraphicsModeHeight(menuItem.tag)) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (menuItem.action == @selector(showSchemeHelpBack:)) {
        return gMacSchemeHelpController ? [gMacSchemeHelpController canNavigateBack] : NO;
    }
    if (menuItem.action == @selector(showSchemeHelpForward:)) {
        return gMacSchemeHelpController ? [gMacSchemeHelpController canNavigateForward] : NO;
    }
    return YES;
}

- (void)showAboutDialog:(id)sender {
    (void)sender;
    NSString *appName = NSProcessInfo.processInfo.processName ?: @"MacScheme";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.1";
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";
    NSString *applicationVersion = [NSString stringWithFormat:@"%@ (Build %@)\nIncludes Chez Scheme 10.4.0", version, build];

    NSDictionary<NSAboutPanelOptionKey, id> *options = @{
        NSAboutPanelOptionApplicationName: appName,
        NSAboutPanelOptionApplicationVersion: applicationVersion,
        NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:
            @"Interactive Scheme editor, REPL, and graphics workspace for macOS.\n\nBuilt around Chez Scheme and bundled with Chez Scheme 10.4.0."]
    };

    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

- (void)showSchemeHelp:(id)sender {
    (void)sender;
    if (!gMacSchemeHelpController) {
        gMacSchemeHelpController = [[MacSchemeHelpWindowController alloc] init];
    }
    [gMacSchemeHelpController showHomePage];
}

- (void)showSchemeHelpHome:(id)sender {
    [self showSchemeHelp:sender];
}

- (void)showSchemeHelpBack:(id)sender {
    (void)sender;
    if (!gMacSchemeHelpController) return;
    [gMacSchemeHelpController navigateBack];
}

- (void)showSchemeHelpForward:(id)sender {
    (void)sender;
    if (!gMacSchemeHelpController) return;
    [gMacSchemeHelpController navigateForward];
}

// ---------------------------------------------------------------------------
// Scheme pthread entry point.
// This thread owns ALL Chez Scheme API calls for the lifetime of the app.
// It calls Sbuild_heap (which registers this thread as the primary Scheme
// thread), then loops servicing eval requests from macscheme_eval_async.
// ---------------------------------------------------------------------------
static void *scheme_thread_entry(void *arg) {
    AppDelegate *self = (__bridge AppDelegate *)arg;
    [self initScheme];

    // After init, loop forever servicing eval requests.
    while (1) {
        if (g_scheme_sem) sem_wait(g_scheme_sem);

        EvalRequest *req = scheme_dequeue();
        if (!req) continue;

        SchemeRequestKind kind = req->kind;
        NSString *expr = [[NSString alloc] initWithUTF8String:req->expr];
        free(req->expr);
        free(req);

        if (!expr) {
            dispatch_async(dispatch_get_main_queue(), ^{
                const char *prompt = "> ";
                grid_append_repl_prompt((const unsigned char *)prompt, strlen(prompt));
            });
            continue;
        }

        if (kind == SchemeRequestCompletions) {
            NSArray<NSString *> *results = EvaluateSchemeCompletions(expr);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSData *prefixData = [expr dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
                NSUInteger count = results.count;
                const char **words = count > 0 ? (const char **)calloc(count, sizeof(char *)) : NULL;
                for (NSUInteger i = 0; i < count; i++) {
                    words[i] = strdup(results[i].UTF8String ?: "");
                }
                grid_set_completions((const unsigned char *)prefixData.bytes, prefixData.length, words, count);
                for (NSUInteger i = 0; i < count; i++) {
                    free((void *)words[i]);
                }
                free(words);
            });
            continue;
        }

        BOOL isError = NO;
        g_scheme_eval_active = 1;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp.mainMenu update];
        });
        NSString *result = EvaluateSchemeExpression(expr, &isError);
        g_scheme_eval_active = 0;

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp.mainMenu update];
            if (result.length > 0) {
                NSData *data = [result dataUsingEncoding:NSUTF8StringEncoding];
                if (data) {
                    grid_append_repl_output((const unsigned char *)data.bytes,
                                           data.length, isError ? 1 : 0);
                }
            }
            const char *prompt = "> ";
            grid_append_repl_prompt((const unsigned char *)prompt, strlen(prompt));
        });
    }

    return NULL;
}
- (void)installMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSString *appName = NSProcessInfo.processInfo.processName ?: @"MacScheme";

    NSMenuItem *appRoot = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appRoot];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    [appRoot setSubmenu:appMenu];
    AddMenuItem(appMenu, [NSString stringWithFormat:@"About %@", appName], @selector(showAboutDialog:), @"", 0, self);
    [appMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(appMenu, [NSString stringWithFormat:@"Quit %@", appName], @selector(terminate:), @"q", NSEventModifierFlagCommand, NSApp);

    NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileRoot];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileRoot setSubmenu:fileMenu];
    AddMenuItem(fileMenu, @"Open…", @selector(openDocument:), @"o", NSEventModifierFlagCommand, self);
    AddMenuItem(fileMenu, @"Save", @selector(saveDocument:), @"s", NSEventModifierFlagCommand, self);
    AddMenuItem(fileMenu, @"Save As…", @selector(saveDocumentAs:), @"S", NSEventModifierFlagCommand | NSEventModifierFlagShift, self);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(fileMenu, @"Revert to Saved", @selector(revertDocumentToSaved:), @"r", NSEventModifierFlagCommand, self);

    NSMenuItem *editRoot = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editRoot];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editRoot setSubmenu:editMenu];
    AddMenuItem(editMenu, @"Undo", @selector(undo:), @"z", NSEventModifierFlagCommand, self);
    AddMenuItem(editMenu, @"Redo", @selector(redo:), @"Z", NSEventModifierFlagCommand | NSEventModifierFlagShift, self);
    [editMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(editMenu, @"Cut", @selector(cut:), @"x", NSEventModifierFlagCommand, nil);
    AddMenuItem(editMenu, @"Copy", @selector(copy:), @"c", NSEventModifierFlagCommand, nil);
    AddMenuItem(editMenu, @"Paste", @selector(paste:), @"v", NSEventModifierFlagCommand, nil);

    NSMenuItem *sourceRoot = [[NSMenuItem alloc] initWithTitle:@"Source" action:nil keyEquivalent:@""];
    [mainMenu addItem:sourceRoot];
    NSMenu *sourceMenu = [[NSMenu alloc] initWithTitle:@"Source"];
    [sourceRoot setSubmenu:sourceMenu];
    AddModifiedFunctionKeyMenuItem(sourceMenu, @"Move Backward S-Expression", @selector(moveBackwardSexp:), NSLeftArrowFunctionKey, NSEventModifierFlagOption, self);
    AddModifiedFunctionKeyMenuItem(sourceMenu, @"Move Forward S-Expression", @selector(moveForwardSexp:), NSRightArrowFunctionKey, NSEventModifierFlagOption, self);
    AddModifiedFunctionKeyMenuItem(sourceMenu, @"Select Enclosing Form", @selector(selectEnclosingForm:), NSUpArrowFunctionKey, NSEventModifierFlagOption, self);
    [sourceMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(sourceMenu, @"Wrap Selection in Parentheses", @selector(wrapSelectionInParentheses:), @"w", NSEventModifierFlagControl | NSEventModifierFlagOption, self);
    AddModifiedFunctionKeyMenuItem(sourceMenu, @"Splice / Unwrap Enclosing Form", @selector(spliceEnclosingForm:), NSUpArrowFunctionKey, NSEventModifierFlagControl | NSEventModifierFlagOption, self);
    AddModifiedFunctionKeyMenuItem(sourceMenu, @"Slurp Forward", @selector(slurpForward:), NSRightArrowFunctionKey, NSEventModifierFlagControl | NSEventModifierFlagOption, self);
    AddModifiedFunctionKeyMenuItem(sourceMenu, @"Barf Forward", @selector(barfForward:), NSLeftArrowFunctionKey, NSEventModifierFlagControl | NSEventModifierFlagOption, self);
    [sourceMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(sourceMenu, @"Re-indent Current Line", @selector(reindentCurrentLine:), @"\t", 0, self);
    AddMenuItem(sourceMenu, @"Re-indent Selection or Line", @selector(reindentSelectionOrLine:), @"q", NSEventModifierFlagOption, self);
    AddMenuItem(sourceMenu, @"Format Source Code", @selector(formatSourceCode:), @"F", NSEventModifierFlagOption | NSEventModifierFlagShift, self);

    NSMenuItem *layoutRoot = [[NSMenuItem alloc] initWithTitle:@"Layout" action:nil keyEquivalent:@""];
    [mainMenu addItem:layoutRoot];
    NSMenu *layoutMenu = [[NSMenu alloc] initWithTitle:@"Layout"];
    [layoutRoot setSubmenu:layoutMenu];
    AddMenuItem(layoutMenu, @"Balanced", @selector(selectLayoutPreset:), @"1", NSEventModifierFlagCommand, self).tag = MacSchemeLayoutPresetBalanced;
    AddMenuItem(layoutMenu, @"Editor + REPL", @selector(selectLayoutPreset:), @"2", NSEventModifierFlagCommand, self).tag = MacSchemeLayoutPresetEditorRepl;
    AddMenuItem(layoutMenu, @"Editor + Graphics", @selector(selectLayoutPreset:), @"3", NSEventModifierFlagCommand, self).tag = MacSchemeLayoutPresetEditorGraphics;
    AddMenuItem(layoutMenu, @"Focus Editor", @selector(selectLayoutPreset:), @"4", NSEventModifierFlagCommand, self).tag = MacSchemeLayoutPresetFocusEditor;
    AddMenuItem(layoutMenu, @"Focus REPL", @selector(selectLayoutPreset:), @"5", NSEventModifierFlagCommand, self).tag = MacSchemeLayoutPresetFocusRepl;
    AddMenuItem(layoutMenu, @"Focus Graphics", @selector(selectLayoutPreset:), @"6", NSEventModifierFlagCommand, self).tag = MacSchemeLayoutPresetFocusGraphics;
    [layoutMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(layoutMenu, @"Show Editor", @selector(toggleLayoutPane:), @"e", NSEventModifierFlagCommand | NSEventModifierFlagOption, self).tag = MacSchemePaneEditor;
    AddMenuItem(layoutMenu, @"Show REPL", @selector(toggleLayoutPane:), @"r", NSEventModifierFlagCommand | NSEventModifierFlagOption, self).tag = MacSchemePaneRepl;
    AddMenuItem(layoutMenu, @"Show Graphics", @selector(toggleLayoutPane:), @"g", NSEventModifierFlagCommand | NSEventModifierFlagOption, self).tag = MacSchemePaneGraphics;
    [layoutMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(layoutMenu, @"Reset Layout", @selector(resetLayout:), @"0", NSEventModifierFlagCommand, self);

    NSMenuItem *graphicsRoot = [[NSMenuItem alloc] initWithTitle:@"Graphics" action:nil keyEquivalent:@""];
    [mainMenu addItem:graphicsRoot];
    NSMenu *graphicsMenu = [[NSMenu alloc] initWithTitle:@"Graphics"];
    [graphicsRoot setSubmenu:graphicsMenu];
    AddMenuItem(graphicsMenu, @"Clear", @selector(clearGraphics:), @"k", NSEventModifierFlagCommand, self);
    [graphicsMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *classicModesRoot = [[NSMenuItem alloc] initWithTitle:@"Classic" action:nil keyEquivalent:@""];
    [graphicsMenu addItem:classicModesRoot];
    NSMenu *classicModesMenu = [[NSMenu alloc] initWithTitle:@"Classic"];
    [classicModesRoot setSubmenu:classicModesMenu];
    AddMenuItem(classicModesMenu, @"256 × 160", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(256, 160);
    AddMenuItem(classicModesMenu, @"320 × 200", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(320, 200);
    AddMenuItem(classicModesMenu, @"320 × 240", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(320, 240);
    AddMenuItem(classicModesMenu, @"512 × 320", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(512, 320);
    AddMenuItem(classicModesMenu, @"640 × 400", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(640, 400);
    AddMenuItem(classicModesMenu, @"640 × 480", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(640, 480);

    NSMenuItem *wideModesRoot = [[NSMenuItem alloc] initWithTitle:@"Wide" action:nil keyEquivalent:@""];
    [graphicsMenu addItem:wideModesRoot];
    NSMenu *wideModesMenu = [[NSMenu alloc] initWithTitle:@"Wide"];
    [wideModesRoot setSubmenu:wideModesMenu];
    AddMenuItem(wideModesMenu, @"720 × 480", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(720, 480);
    AddMenuItem(wideModesMenu, @"800 × 450", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(800, 450);
    AddMenuItem(wideModesMenu, @"854 × 480", @selector(selectGraphicsMode:), @"", 0, self).tag = MacSchemeGraphicsModeTag(854, 480);

    NSMenuItem *themeRoot = [[NSMenuItem alloc] initWithTitle:@"Theme" action:nil keyEquivalent:@""];
    [mainMenu addItem:themeRoot];
    NSMenu *themeMenu = [[NSMenu alloc] initWithTitle:@"Theme"];
    [themeRoot setSubmenu:themeMenu];
    AddMenuItem(themeMenu, @"Next Theme", @selector(cycleTheme:), @"t", NSEventModifierFlagCommand, self);
    [themeMenu addItem:[NSMenuItem separatorItem]];
    for (NSInteger i = 0; i < MacSchemeThemeNames().count; i++) {
        AddMenuItem(themeMenu, MacSchemeThemeNames()[i], @selector(selectTheme:), @"", 0, self).tag = i;
    }

    NSMenuItem *schemeRoot = [[NSMenuItem alloc] initWithTitle:@"Scheme" action:nil keyEquivalent:@""];
    [mainMenu addItem:schemeRoot];
    NSMenu *schemeMenu = [[NSMenu alloc] initWithTitle:@"Scheme"];
    [schemeRoot setSubmenu:schemeMenu];
    AddMenuItem(schemeMenu, @"Stop", @selector(stopScheme:), @".", NSEventModifierFlagCommand, self);
    [schemeMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(schemeMenu, @"Evaluate Selection", @selector(evaluateSelectionOrForm:), @"e", NSEventModifierFlagCommand, self);
    AddMenuItem(schemeMenu, @"Evaluate Top-Level Form", @selector(evaluateTopLevelForm:), @"\r", NSEventModifierFlagCommand, self);
    AddMenuItem(schemeMenu, @"Evaluate Buffer", @selector(evaluateBuffer:), @"b", NSEventModifierFlagCommand, self);

    NSMenuItem *helpRoot = [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    [mainMenu addItem:helpRoot];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpRoot setSubmenu:helpMenu];
    AddFunctionKeyMenuItem(helpMenu, @"Scheme Documentation", @selector(showSchemeHelp:), NSF1FunctionKey, self);
    [helpMenu addItem:[NSMenuItem separatorItem]];
    AddMenuItem(helpMenu, @"Back", @selector(showSchemeHelpBack:), @"", 0, self);
    AddMenuItem(helpMenu, @"Forward", @selector(showSchemeHelpForward:), @"", 0, self);
    AddMenuItem(helpMenu, @"Home", @selector(showSchemeHelpHome:), @"", 0, self);
    [NSApp setHelpMenu:helpMenu];

    [NSApp setMainMenu:mainMenu];
    NSLog(@"MacScheme installMainMenu: delegate=%@ mainMenuItems=%ld", NSApp.delegate, (long)NSApp.mainMenu.itemArray.count);
}

- (SchemeTextGrid *)editorGridView {
    NSView *view = self.editorSplitItem.viewController.view;
    return [view isKindOfClass:[SchemeTextGrid class]] ? (SchemeTextGrid *)view : nil;
}

- (BOOL)editorHasSelection {
    size_t selectionLength = 0;
    const uint8_t *selectionBytes = grid_copy_selection_text(0, &selectionLength);
    if (selectionBytes) {
        grid_free_bytes(selectionBytes, selectionLength);
    }
    return selectionLength > 0;
}

- (void)focusEditorGrid {
    [self setPane:MacSchemePaneEditor visible:YES];
    SchemeTextGrid *editorGrid = [self editorGridView];
    if (editorGrid) {
        [self.window makeFirstResponder:editorGrid];
    }
}

- (void)dispatchEditorKeyCode:(uint32_t)keyCode modifiers:(uint32_t)modifiers {
    if (![self editorGridView]) {
        NSBeep();
        return;
    }
    [self focusEditorGrid];
    grid_on_key_down(0, keyCode, modifiers);
}

- (void)openDocument:(id)sender {
    (void)sender;
    [self openEditorFile];
}

- (void)saveDocument:(id)sender {
    (void)sender;
    [self saveEditorFile];
}

- (void)saveDocumentAs:(id)sender {
    (void)sender;
    [self saveEditorFileAs];
}

- (void)revertDocumentToSaved:(id)sender {
    (void)sender;
    [self revertEditorFile];
}

- (void)evaluateSelectionOrForm:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyE modifiers:MacSchemeGridModCommand];
}

- (void)evaluateTopLevelForm:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyEnter modifiers:MacSchemeGridModCommand];
}

- (void)evaluateBuffer:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyB modifiers:MacSchemeGridModCommand];
}

- (void)stopScheme:(id)sender {
    (void)sender;
    if (!self.schemeReady || g_scheme_eval_active == 0) return;

    int killResult = pthread_kill(g_scheme_thread, SIGINT);
    if (killResult != 0) {
        NSString *message = [NSString stringWithFormat:@"Interrupt failed (%d)", killResult];
        appendReplText(message, YES);
        appendReplText(@"\n", YES);
    }
}

- (void)undo:(id)sender {
    (void)sender;
    grid_on_key_down(0, 6, 8);
}

- (void)redo:(id)sender {
    (void)sender;
    grid_on_key_down(0, 6, 9);
}

- (void)moveBackwardSexp:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyLeft modifiers:MacSchemeGridModAlt];
}

- (void)moveForwardSexp:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyRight modifiers:MacSchemeGridModAlt];
}

- (void)selectEnclosingForm:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyUp modifiers:MacSchemeGridModAlt];
}

- (void)wrapSelectionInParentheses:(id)sender {
    (void)sender;
    if (![self editorHasSelection]) {
        NSBeep();
        return;
    }
    [self focusEditorGrid];
    grid_on_text(0, '(');
}

- (void)spliceEnclosingForm:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyUp modifiers:MacSchemeGridModControl | MacSchemeGridModAlt];
}

- (void)slurpForward:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyRight modifiers:MacSchemeGridModControl | MacSchemeGridModAlt];
}

- (void)barfForward:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyLeft modifiers:MacSchemeGridModControl | MacSchemeGridModAlt];
}

- (void)reindentCurrentLine:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyTab modifiers:0];
}

- (void)reindentSelectionOrLine:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyQ modifiers:MacSchemeGridModAlt];
}

- (void)formatSourceCode:(id)sender {
    (void)sender;
    [self dispatchEditorKeyCode:MacSchemeEditorKeyF modifiers:MacSchemeGridModAlt | MacSchemeGridModShift];
}

- (void)tickSyntaxCheck:(NSTimer *)timer {
    (void)timer;
    if (!self.schemeReady) return;

    uint64_t revision = grid_get_editor_change_serial();
    if (revision == 0 || revision == self.lastSyntaxCheckedRevision) return;

    grid_run_editor_syntax_check(revision);
    self.lastSyntaxCheckedRevision = revision;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    (void)aNotification;
    g_app_delegate = self;
    self.schemeReady = NO;
    self.lastSyntaxCheckedRevision = 0;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self installMainMenu];

    self.syntaxCheckTimer = [NSTimer timerWithTimeInterval:0.45
                                                    target:self
                                                  selector:@selector(tickSyntaxCheck:)
                                                  userInfo:nil
                                                   repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.syntaxCheckTimer forMode:NSRunLoopCommonModes];

    // Create a named semaphore for the eval queue.
    sem_unlink("/macscheme_eval");
    g_scheme_sem = sem_open("/macscheme_eval", O_CREAT | O_EXCL, 0600, 0);
    if (g_scheme_sem == SEM_FAILED) {
        NSLog(@"sem_open failed: %s", strerror(errno));
        g_scheme_sem = NULL;
    }

    // Spawn the dedicated Scheme thread.
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&g_scheme_thread, &attr, scheme_thread_entry, (__bridge void *)self);
    pthread_attr_destroy(&attr);

    const NSSize initialContentSize = NSMakeSize(1200, 800);
    NSRect frame = NSMakeRect(0, 0, initialContentSize.width, initialContentSize.height);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskResizable |
                                                         NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setReleasedWhenClosed:NO];
    [self.window setTitle:@"MacScheme"];
    [self.window center];
    [self.window setMinSize:NSMakeSize(800, 600)];
    [self.window setIsVisible:YES];

    self.splitViewController = [[NSSplitViewController alloc] init];

    NSViewController *editorVC = [[NSViewController alloc] init];
    editorVC.view = [[SchemeTextGrid alloc] initWithFrame:NSZeroRect gridId:0];

    NSViewController *replVC = [[NSViewController alloc] init];
    replVC.view = [[SchemeTextGrid alloc] initWithFrame:NSZeroRect gridId:1];

    NSViewController *graphicsVC = [[NSViewController alloc] init];
    NSView *graphicsView = [[NSView alloc] initWithFrame:NSZeroRect];
    graphicsView.wantsLayer = YES;
    graphicsView.layer.backgroundColor = NSColor.blackColor.CGColor;
    graphicsVC.view = graphicsView;

    // Register this pane as the host for the real BASIC graphics renderer.
    gfx_set_host_view((__bridge void *)graphicsView);

    self.rightSplitController = [[NSSplitViewController alloc] init];
    self.rightSplitController.splitView.vertical = NO;
    self.graphicsSplitItem = [NSSplitViewItem splitViewItemWithViewController:graphicsVC];
    self.replSplitItem = [NSSplitViewItem splitViewItemWithViewController:replVC];
    self.graphicsSplitItem.minimumThickness = 180.0;
    self.replSplitItem.minimumThickness = 180.0;
    [self.rightSplitController addSplitViewItem:self.graphicsSplitItem];
    [self.rightSplitController addSplitViewItem:self.replSplitItem];

    self.splitViewController.splitView.vertical = YES;
    self.editorSplitItem = [NSSplitViewItem splitViewItemWithViewController:editorVC];
    self.rightSplitItem = [NSSplitViewItem splitViewItemWithViewController:self.rightSplitController];
    self.editorSplitItem.minimumThickness = 320.0;
    self.rightSplitItem.minimumThickness = 280.0;
    [self.splitViewController addSplitViewItem:self.editorSplitItem];
    [self.splitViewController addSplitViewItem:self.rightSplitItem];

    self.splitViewController.view.frame = NSMakeRect(0, 0, initialContentSize.width, initialContentSize.height);
    self.rightSplitController.view.frame = NSMakeRect(0, 0, initialContentSize.width * 0.4, initialContentSize.height);

    self.window.contentViewController = self.splitViewController;
    [self.window setContentSize:initialContentSize];
    [self.window center];
    [self.window layoutIfNeeded];
    self.savedMainSplitRatio = kMacSchemeBalancedMainRatio;
    self.savedRightSplitRatio = kMacSchemeBalancedRightRatio;
    self.editorPaneVisible = YES;
    self.replPaneVisible = YES;
    self.graphicsPaneVisible = YES;
    [self applyLayoutPreset:MacSchemeLayoutPresetBalanced];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    MacSchemeActivateApplication();
    LoadPersistedReplHistory();
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window makeKeyAndOrderFront:nil];
        [self.window orderFrontRegardless];
        MacSchemeActivateApplication();
        NSLog(@"MacScheme startup: delegate=%@ mainMenuItems=%ld active=%d windowVisible=%d key=%d main=%d", NSApp.delegate, (long)NSApp.mainMenu.itemArray.count, NSRunningApplication.currentApplication.active, self.window.isVisible, self.window.isKeyWindow, self.window.isMainWindow);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MacSchemeActivateApplication();
        NSLog(@"MacScheme delayed activate: active=%d frontMenuItems=%ld", NSRunningApplication.currentApplication.active, (long)NSApp.mainMenu.itemArray.count);
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    SavePersistedReplHistory();
}

- (void)initScheme {
    Sscheme_init(NULL);

    NSString *basePath = MacSchemeResourceBasePath();
    NSString *petitePath = [basePath stringByAppendingPathComponent:@"petite.boot"];
    NSString *schemePath = [basePath stringByAppendingPathComponent:@"scheme.boot"];

    Sregister_boot_file([petitePath UTF8String]);
    Sregister_boot_file([schemePath UTF8String]);
    Sbuild_heap(NULL, NULL);

    // Initialize the hosted graphics pane before exposing Scheme bindings.
    macscheme_gfx_init();
    macscheme_gfx_screen(256, 160, 3);
    macscheme_gfx_reset_palette();
    macscheme_gfx_palette(16, 0, 0, 0);
    macscheme_gfx_palette(17, 255, 255, 255);
    macscheme_gfx_palette(18, 255, 0, 0);
    macscheme_gfx_palette(19, 0, 255, 0);
    macscheme_gfx_palette(20, 0, 0, 255);
    macscheme_gfx_palette(21, 255, 255, 0);
    macscheme_gfx_palette(22, 0, 255, 255);
    macscheme_gfx_palette(23, 255, 0, 255);
    macscheme_gfx_cls(16);
    macscheme_gfx_flip();

    Sforeign_symbol("macscheme_gfx_init", (void *)macscheme_gfx_init);
    Sforeign_symbol("macscheme_gfx_screen", (void *)macscheme_gfx_screen);
    Sforeign_symbol("macscheme_gfx_screen_close", (void *)macscheme_gfx_screen_close);
    Sforeign_symbol("macscheme_gfx_set_target", (void *)macscheme_gfx_set_target);
    Sforeign_symbol("macscheme_gfx_pset", (void *)macscheme_gfx_pset);
    Sforeign_symbol("macscheme_gfx_pget", (void *)macscheme_gfx_pget);
    Sforeign_symbol("macscheme_gfx_line", (void *)macscheme_gfx_line);
    Sforeign_symbol("macscheme_gfx_cls", (void *)macscheme_gfx_cls);
    Sforeign_symbol("macscheme_gfx_rect", (void *)macscheme_gfx_rect);
    Sforeign_symbol("macscheme_gfx_circle", (void *)macscheme_gfx_circle);
    Sforeign_symbol("macscheme_gfx_ellipse", (void *)macscheme_gfx_ellipse);
    Sforeign_symbol("macscheme_gfx_triangle", (void *)macscheme_gfx_triangle);
    Sforeign_symbol("macscheme_gfx_fill_area", (void *)macscheme_gfx_fill_area);
    Sforeign_symbol("macscheme_gfx_scroll_buffer", (void *)macscheme_gfx_scroll_buffer);
    Sforeign_symbol("macscheme_gfx_blit", (void *)macscheme_gfx_blit);
    Sforeign_symbol("macscheme_gfx_blit_solid", (void *)macscheme_gfx_blit_solid);
    Sforeign_symbol("macscheme_gfx_blit_scale", (void *)macscheme_gfx_blit_scale);
    Sforeign_symbol("macscheme_gfx_blit_flip", (void *)macscheme_gfx_blit_flip);
    Sforeign_symbol("macscheme_gfx_palette", (void *)macscheme_gfx_palette);
    Sforeign_symbol("macscheme_gfx_line_palette", (void *)macscheme_gfx_line_palette);
    Sforeign_symbol("macscheme_gfx_pal_cycle", (void *)macscheme_gfx_pal_cycle);
    Sforeign_symbol("macscheme_gfx_pal_cycle_lines", (void *)macscheme_gfx_pal_cycle_lines);
    Sforeign_symbol("macscheme_gfx_pal_fade", (void *)macscheme_gfx_pal_fade);
    Sforeign_symbol("macscheme_gfx_pal_fade_lines", (void *)macscheme_gfx_pal_fade_lines);
    Sforeign_symbol("macscheme_gfx_pal_pulse", (void *)macscheme_gfx_pal_pulse);
    Sforeign_symbol("macscheme_gfx_pal_pulse_lines", (void *)macscheme_gfx_pal_pulse_lines);
    Sforeign_symbol("macscheme_gfx_pal_gradient", (void *)macscheme_gfx_pal_gradient);
    Sforeign_symbol("macscheme_gfx_pal_strobe", (void *)macscheme_gfx_pal_strobe);
    Sforeign_symbol("macscheme_gfx_pal_strobe_lines", (void *)macscheme_gfx_pal_strobe_lines);
    Sforeign_symbol("macscheme_gfx_pal_stop", (void *)macscheme_gfx_pal_stop);
    Sforeign_symbol("macscheme_gfx_pal_stop_all", (void *)macscheme_gfx_pal_stop_all);
    Sforeign_symbol("macscheme_gfx_pal_pause", (void *)macscheme_gfx_pal_pause);
    Sforeign_symbol("macscheme_gfx_pal_resume", (void *)macscheme_gfx_pal_resume);
    Sforeign_symbol("macscheme_gfx_reset_palette", (void *)macscheme_gfx_reset_palette);
    Sforeign_symbol("macscheme_gfx_draw_text", (void *)macscheme_gfx_draw_text);
    Sforeign_symbol("macscheme_gfx_draw_text_int", (void *)macscheme_gfx_draw_text_int);
    Sforeign_symbol("macscheme_gfx_draw_text_double", (void *)macscheme_gfx_draw_text_double);
    Sforeign_symbol("macscheme_gfx_text_width", (void *)macscheme_gfx_text_width);
    Sforeign_symbol("macscheme_gfx_text_height", (void *)macscheme_gfx_text_height);
    Sforeign_symbol("macscheme_gfx_flip", (void *)macscheme_gfx_flip);
    Sforeign_symbol("macscheme_gfx_vsync", (void *)macscheme_gfx_vsync);
    Sforeign_symbol("macscheme_gfx_wait_frames", (void *)macscheme_gfx_wait_frames);
    Sforeign_symbol("macscheme_gfx_set_scroll", (void *)macscheme_gfx_set_scroll);
    Sforeign_symbol("macscheme_gfx_cycle", (void *)macscheme_gfx_cycle);
    Sforeign_symbol("macscheme_gfx_screen_width", (void *)macscheme_gfx_screen_width);
    Sforeign_symbol("macscheme_gfx_screen_height", (void *)macscheme_gfx_screen_height);
    Sforeign_symbol("macscheme_gfx_screen_active", (void *)macscheme_gfx_screen_active);
    Sforeign_symbol("macscheme_gfx_inkey", (void *)macscheme_gfx_inkey);
    Sforeign_symbol("macscheme_gfx_keydown", (void *)macscheme_gfx_keydown);
    Sforeign_symbol("macscheme_gfx_buffer_width", (void *)macscheme_gfx_buffer_width);
    Sforeign_symbol("macscheme_gfx_buffer_height", (void *)macscheme_gfx_buffer_height);
    Sforeign_symbol("macscheme_gfx_sprite_load", (void *)macscheme_gfx_sprite_load);
    Sforeign_symbol("macscheme_gfx_sprite_def", (void *)macscheme_gfx_sprite_def);
    Sforeign_symbol("macscheme_gfx_sprite_data", (void *)macscheme_gfx_sprite_data);
    Sforeign_symbol("macscheme_gfx_sprite_commit", (void *)macscheme_gfx_sprite_commit);
    Sforeign_symbol("macscheme_gfx_sprite_row_ascii", (void *)macscheme_gfx_sprite_row_ascii);
    Sforeign_symbol("macscheme_gfx_sprite_begin", (void *)macscheme_gfx_sprite_begin);
    Sforeign_symbol("macscheme_gfx_sprite_end", (void *)macscheme_gfx_sprite_end);
    Sforeign_symbol("macscheme_gfx_sprite_palette", (void *)macscheme_gfx_sprite_palette);
    Sforeign_symbol("macscheme_gfx_sprite_std_pal", (void *)macscheme_gfx_sprite_std_pal);
    Sforeign_symbol("macscheme_gfx_sprite_frames", (void *)macscheme_gfx_sprite_frames);
    Sforeign_symbol("macscheme_gfx_sprite_set_frame", (void *)macscheme_gfx_sprite_set_frame);
    Sforeign_symbol("macscheme_gfx_sprite", (void *)macscheme_gfx_sprite);
    Sforeign_symbol("macscheme_gfx_sprite_pos", (void *)macscheme_gfx_sprite_pos);
    Sforeign_symbol("macscheme_gfx_sprite_move", (void *)macscheme_gfx_sprite_move);
    Sforeign_symbol("macscheme_gfx_sprite_rot", (void *)macscheme_gfx_sprite_rot);
    Sforeign_symbol("macscheme_gfx_sprite_scale", (void *)macscheme_gfx_sprite_scale);
    Sforeign_symbol("macscheme_gfx_sprite_anchor", (void *)macscheme_gfx_sprite_anchor);
    Sforeign_symbol("macscheme_gfx_sprite_show", (void *)macscheme_gfx_sprite_show);
    Sforeign_symbol("macscheme_gfx_sprite_hide", (void *)macscheme_gfx_sprite_hide);
    Sforeign_symbol("macscheme_gfx_sprite_flip", (void *)macscheme_gfx_sprite_flip);
    Sforeign_symbol("macscheme_gfx_sprite_alpha", (void *)macscheme_gfx_sprite_alpha);
    Sforeign_symbol("macscheme_gfx_sprite_frame", (void *)macscheme_gfx_sprite_frame);
    Sforeign_symbol("macscheme_gfx_sprite_animate", (void *)macscheme_gfx_sprite_animate);
    Sforeign_symbol("macscheme_gfx_sprite_priority", (void *)macscheme_gfx_sprite_priority);
    Sforeign_symbol("macscheme_gfx_sprite_blend", (void *)macscheme_gfx_sprite_blend);
    Sforeign_symbol("macscheme_gfx_sprite_remove", (void *)macscheme_gfx_sprite_remove);
    Sforeign_symbol("macscheme_gfx_sprite_remove_all", (void *)macscheme_gfx_sprite_remove_all);
    Sforeign_symbol("macscheme_gfx_sprite_fx", (void *)macscheme_gfx_sprite_fx);
    Sforeign_symbol("macscheme_gfx_sprite_fx_param", (void *)macscheme_gfx_sprite_fx_param);
    Sforeign_symbol("macscheme_gfx_sprite_fx_colour", (void *)macscheme_gfx_sprite_fx_colour);
    Sforeign_symbol("macscheme_gfx_sprite_glow", (void *)macscheme_gfx_sprite_glow);
    Sforeign_symbol("macscheme_gfx_sprite_outline", (void *)macscheme_gfx_sprite_outline);
    Sforeign_symbol("macscheme_gfx_sprite_shadow", (void *)macscheme_gfx_sprite_shadow);
    Sforeign_symbol("macscheme_gfx_sprite_tint", (void *)macscheme_gfx_sprite_tint);
    Sforeign_symbol("macscheme_gfx_sprite_flash", (void *)macscheme_gfx_sprite_flash);
    Sforeign_symbol("macscheme_gfx_sprite_fx_off", (void *)macscheme_gfx_sprite_fx_off);
    Sforeign_symbol("macscheme_gfx_sprite_pal_override", (void *)macscheme_gfx_sprite_pal_override);
    Sforeign_symbol("macscheme_gfx_sprite_pal_reset", (void *)macscheme_gfx_sprite_pal_reset);
    Sforeign_symbol("macscheme_gfx_sprite_x", (void *)macscheme_gfx_sprite_x);
    Sforeign_symbol("macscheme_gfx_sprite_y", (void *)macscheme_gfx_sprite_y);
    Sforeign_symbol("macscheme_gfx_sprite_rotation", (void *)macscheme_gfx_sprite_rotation);
    Sforeign_symbol("macscheme_gfx_sprite_visible", (void *)macscheme_gfx_sprite_visible);
    Sforeign_symbol("macscheme_gfx_sprite_current_frame", (void *)macscheme_gfx_sprite_current_frame);
    Sforeign_symbol("macscheme_gfx_sprite_hit", (void *)macscheme_gfx_sprite_hit);
    Sforeign_symbol("macscheme_gfx_sprite_count", (void *)macscheme_gfx_sprite_count);
    Sforeign_symbol("macscheme_gfx_sprite_collide", (void *)macscheme_gfx_sprite_collide);
    Sforeign_symbol("macscheme_gfx_sprite_overlap", (void *)macscheme_gfx_sprite_overlap);
    Sforeign_symbol("macscheme_gfx_sprite_sync", (void *)macscheme_gfx_sprite_sync);
    Sforeign_symbol("macscheme_layout_set", (void *)macscheme_layout_set);
    Sforeign_symbol("macscheme_layout_show_pane", (void *)macscheme_layout_show_pane);
    Sforeign_symbol("macscheme_layout_hide_pane", (void *)macscheme_layout_hide_pane);
    Sforeign_symbol("macscheme_layout_toggle_pane", (void *)macscheme_layout_toggle_pane);
    Sforeign_symbol("macscheme_layout_reset", (void *)macscheme_layout_reset);
    Sforeign_symbol("macscheme_layout_current", (void *)macscheme_layout_current);
    Sforeign_symbol("macscheme_layout_pane_visible", (void *)macscheme_layout_pane_visible);
    Sforeign_symbol("snd_init", (void *)snd_init);
    Sforeign_symbol("snd_shutdown", (void *)snd_shutdown);
    Sforeign_symbol("snd_is_init", (void *)snd_is_init);
    Sforeign_symbol("snd_stop_all", (void *)snd_stop_all);
    Sforeign_symbol("snd_beep", (void *)snd_beep);
    Sforeign_symbol("snd_zap", (void *)snd_zap);
    Sforeign_symbol("snd_explode", (void *)snd_explode);
    Sforeign_symbol("snd_big_explosion", (void *)snd_big_explosion);
    Sforeign_symbol("snd_small_explosion", (void *)snd_small_explosion);
    Sforeign_symbol("snd_distant_explosion", (void *)snd_distant_explosion);
    Sforeign_symbol("snd_metal_explosion", (void *)snd_metal_explosion);
    Sforeign_symbol("snd_bang", (void *)snd_bang);
    Sforeign_symbol("snd_coin", (void *)snd_coin);
    Sforeign_symbol("snd_jump", (void *)snd_jump);
    Sforeign_symbol("snd_powerup", (void *)snd_powerup);
    Sforeign_symbol("snd_hurt", (void *)snd_hurt);
    Sforeign_symbol("snd_shoot", (void *)snd_shoot);
    Sforeign_symbol("snd_click", (void *)snd_click);
    Sforeign_symbol("snd_blip", (void *)snd_blip);
    Sforeign_symbol("snd_pickup", (void *)snd_pickup);
    Sforeign_symbol("snd_sweep_up", (void *)snd_sweep_up);
    Sforeign_symbol("snd_sweep_down", (void *)snd_sweep_down);
    Sforeign_symbol("snd_random_beep", (void *)snd_random_beep);
    Sforeign_symbol("snd_tone", (void *)snd_tone);
    Sforeign_symbol("snd_note", (void *)snd_note);
    Sforeign_symbol("snd_noise", (void *)snd_noise);
    Sforeign_symbol("snd_fm", (void *)snd_fm);
    Sforeign_symbol("snd_filtered_tone", (void *)snd_filtered_tone);
    Sforeign_symbol("snd_filtered_note", (void *)snd_filtered_note);
    Sforeign_symbol("snd_reverb", (void *)snd_reverb);
    Sforeign_symbol("snd_delay", (void *)snd_delay);
    Sforeign_symbol("snd_distortion", (void *)snd_distortion);
    Sforeign_symbol("snd_play", (void *)snd_play);
    Sforeign_symbol("snd_play_simple", (void *)snd_play_simple);
    Sforeign_symbol("snd_stop", (void *)snd_stop);
    Sforeign_symbol("snd_stop_one", (void *)snd_stop_one);
    Sforeign_symbol("snd_is_playing", (void *)snd_is_playing);
    Sforeign_symbol("snd_get_duration", (void *)snd_get_duration);
    Sforeign_symbol("snd_free", (void *)snd_free);
    Sforeign_symbol("snd_free_all", (void *)snd_free_all);
    Sforeign_symbol("snd_set_volume", (void *)snd_set_volume);
    Sforeign_symbol("snd_get_volume", (void *)snd_get_volume);
    Sforeign_symbol("snd_exists", (void *)snd_exists);
    Sforeign_symbol("snd_count", (void *)snd_count);
    Sforeign_symbol("snd_mem", (void *)snd_mem);
    Sforeign_symbol("snd_note_to_freq", (void *)snd_note_to_freq);
    Sforeign_symbol("snd_freq_to_note", (void *)snd_freq_to_note);
    Sforeign_symbol("snd_export_wav", (void *)scheme_snd_export_wav);
    Sforeign_symbol("mus_play", (void *)scheme_mus_play);
    Sforeign_symbol("mus_play_simple", (void *)scheme_mus_play_simple);
    Sforeign_symbol("mus_load", (void *)scheme_mus_load);
    Sforeign_symbol("mus_load_compiled", (void *)mus_load_compiled);
    Sforeign_symbol("mus_play_id", (void *)mus_play_id);
    Sforeign_symbol("mus_play_id_simple", (void *)mus_play_id_simple);
    Sforeign_symbol("mus_stop", (void *)mus_stop);
    Sforeign_symbol("mus_pause", (void *)mus_pause);
    Sforeign_symbol("mus_resume", (void *)mus_resume);
    Sforeign_symbol("mus_set_volume", (void *)mus_set_volume);
    Sforeign_symbol("mus_get_volume", (void *)mus_get_volume);
    Sforeign_symbol("mus_free", (void *)mus_free);
    Sforeign_symbol("mus_free_all", (void *)mus_free_all);
    Sforeign_symbol("mus_is_playing", (void *)mus_is_playing);
    Sforeign_symbol("mus_is_playing_id", (void *)mus_is_playing_id);
    Sforeign_symbol("mus_state", (void *)mus_state);
    Sforeign_symbol("mus_exists", (void *)mus_exists);
    Sforeign_symbol("mus_count", (void *)mus_count);
    Sforeign_symbol("mus_mem", (void *)mus_mem);
    Sforeign_symbol("mus_get_title", (void *)mus_get_title);
    Sforeign_symbol("mus_get_composer", (void *)mus_get_composer);
    Sforeign_symbol("mus_get_key", (void *)mus_get_key);
    Sforeign_symbol("mus_get_tempo", (void *)mus_get_tempo);
    Sforeign_symbol("mus_get_compiled_blob_info", (void *)mus_get_compiled_blob_info);
    Sforeign_symbol("mus_render", (void *)scheme_mus_render);
    Sforeign_symbol("mus_render_simple", (void *)scheme_mus_render_simple);
    Sforeign_symbol("mus_render_wav", (void *)scheme_mus_render_wav);
    Sforeign_symbol("mus_export_midi", (void *)scheme_mus_export_midi);
        Sforeign_symbol("macscheme_repl_write_output", (void *)macscheme_repl_write_output);
        Sforeign_symbol("macscheme_repl_write_error", (void *)macscheme_repl_write_error);
        ptr repl_ports = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                    Scall1(Stop_level_value(Sstring_to_symbol("read")),
                        Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                            Sstring("(begin (define macscheme-repl-write-output (foreign-procedure \"macscheme_repl_write_output\" (string) void)) (define macscheme-repl-write-error (foreign-procedure \"macscheme_repl_write_error\" (string) void)) (define (macscheme-make-repl-port writer name) (make-output-port (lambda (msg . args) (case msg ((write-char) (writer (string (car args)))) ((block-write) (let ((str (cadr args)) (count (caddr args))) (when (> count 0) (writer (substring str 0 count))))) ((flush-output-port clear-output-port) (void)) ((close-port) (mark-port-closed! (car args))) ((port-name) name) (else (void)))) \"\")) (define macscheme-gui-output-port (macscheme-make-repl-port macscheme-repl-write-output \"macscheme-stdout\")) (define macscheme-gui-error-port (macscheme-make-repl-port macscheme-repl-write-error \"macscheme-stderr\")))"))));
        (void)repl_ports;
    ptr eval_string = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                             Scall1(Stop_level_value(Sstring_to_symbol("read")),
                                    Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                Sstring("(lambda (s) (call/cc (lambda (interrupt) (parameterize ((keyboard-interrupt-handler (lambda () (interrupt (list #t \"Interrupted\")))) (console-output-port macscheme-gui-output-port) (current-output-port macscheme-gui-output-port) (console-error-port macscheme-gui-error-port) (current-error-port macscheme-gui-error-port)) (guard (ex [else (list #t (with-output-to-string (lambda () (display-condition ex))))]) (let ((port (open-input-string s))) (let loop ((last (void)) (saw? #f)) (let ((form (read port))) (if (eof-object? form) (list #f (if saw? (with-output-to-string (lambda () (write last))) \"\")) (loop (eval form (interaction-environment)) #t))))))))))"))));
    Sset_top_level_value(Sstring_to_symbol("macscheme-eval-string"), eval_string);

    ptr load_string = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                             Scall1(Stop_level_value(Sstring_to_symbol("read")),
                                    Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                     Sstring("(lambda (path) (call/cc (lambda (interrupt) (parameterize ((keyboard-interrupt-handler (lambda () (interrupt (list #t \"Interrupted\")))) (console-output-port macscheme-gui-output-port) (current-output-port macscheme-gui-output-port) (console-error-port macscheme-gui-error-port) (current-error-port macscheme-gui-error-port)) (guard (ex [else (list #t (with-output-to-string (lambda () (display-condition ex))))]) (with-input-from-file path (lambda () (let loop ((last (void)) (saw? #f)) (let ((form (read))) (if (eof-object? form) (list #f (if saw? (with-output-to-string (lambda () (write last))) \"\")) (loop (eval form (interaction-environment)) #t)))))))))))"))));
    Sset_top_level_value(Sstring_to_symbol("macscheme-load-file"), load_string);

        ptr completion_string = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                        Scall1(Stop_level_value(Sstring_to_symbol("read")),
                            Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                                Sstring("(lambda (prefix) (let* ((prefix (if (symbol? prefix) (symbol->string prefix) prefix)) (n (string-length prefix))) (let loop ((syms (environment-symbols (interaction-environment))) (acc '())) (if (null? syms) acc (let* ((sym (car syms)) (name ((if (gensym? sym) gensym->unique-string symbol->string) sym))) (if (and (<= n (string-length name)) (string=? prefix (substring name 0 n))) (loop (cdr syms) (cons name acc)) (loop (cdr syms) acc)))))))"))));
        Sset_top_level_value(Sstring_to_symbol("macscheme-get-completions"), completion_string);

    NSString *graphicsBootstrap = MacSchemeGraphicsBootstrapSource();
    ptr graphics_defs = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                               Scall1(Stop_level_value(Sstring_to_symbol("read")),
                                      Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                                             Sstring([graphicsBootstrap UTF8String]))));
    (void)graphics_defs;

    self.schemeReady = YES;
    NSLog(@"Chez Scheme Initialized Successfully!");

    // Show the banner and first prompt on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        const char *banner = "Chez Scheme Version 10.4.0\n";
        grid_append_repl_output((const unsigned char *)banner, strlen(banner), 0);
        const char *prompt = "> ";
        grid_append_repl_prompt((const unsigned char *)prompt, strlen(prompt));
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)openEditorFile {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Open Scheme File";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = MacSchemeAllowedFileExtensions();
#pragma clang diagnostic pop
    panel.allowsOtherFileTypes = NO;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;

    if ([panel runModal] != NSModalResponseOK) return;
    NSURL *url = panel.URL;
    if (!url) return;

    NSError *err = nil;
    NSString *contents = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
    if (!contents) {
        NSAlert *alert = [NSAlert alertWithError:err];
        [alert runModal];
        return;
    }

    NSData *utf8 = [contents dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) return;
    grid_replace_text(0, (const uint8_t *)utf8.bytes, utf8.length);
    grid_set_editor_modified(0);

    NSString *path = url.path;
    NSData *pathData = [path dataUsingEncoding:NSUTF8StringEncoding];
    if (pathData) grid_set_editor_file_path((const uint8_t *)pathData.bytes, pathData.length);

    [self.window setTitleWithRepresentedFilename:path];
    [self.window setDocumentEdited:NO];
}

- (void)saveEditorFile {
    NSString *existingPath = CurrentEditorPath();

    if (!existingPath) {
        [self saveEditorFileAs];
        return;
    }

    NSError *err = nil;
    BOOL ok = WriteEditorBufferToPath(existingPath, &err);
    if (!ok) {
        NSAlert *alert = [NSAlert alertWithError:err];
        [alert runModal];
        return;
    }

    [self.window setTitleWithRepresentedFilename:existingPath];
    grid_set_editor_modified(0);
    [self.window setDocumentEdited:NO];
}

- (void)saveEditorFileAs {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Scheme File As";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = MacSchemeAllowedFileExtensions();
#pragma clang diagnostic pop
    panel.allowsOtherFileTypes = NO;

    NSString *existingPath = CurrentEditorPath();
    if (existingPath) {
        panel.directoryURL = [NSURL fileURLWithPath:[existingPath stringByDeletingLastPathComponent]];
        panel.nameFieldStringValue = existingPath.lastPathComponent;
    } else {
        panel.nameFieldStringValue = @"untitled.ss";
    }

    if ([panel runModal] != NSModalResponseOK) return;
    NSURL *url = panel.URL;
    if (!url) return;

    NSString *path = url.path;
    NSError *err = nil;
    if (!WriteEditorBufferToPath(path, &err)) {
        NSAlert *alert = [NSAlert alertWithError:err];
        [alert runModal];
        return;
    }

    NSData *pathData = [path dataUsingEncoding:NSUTF8StringEncoding];
    if (pathData) grid_set_editor_file_path((const uint8_t *)pathData.bytes, pathData.length);
    [self.window setTitleWithRepresentedFilename:path];
    grid_set_editor_modified(0);
    [self.window setDocumentEdited:NO];
}

- (void)revertEditorFile {
    NSString *path = CurrentEditorPath();
    if (!path) return;

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Revert to Saved?";
    confirm.informativeText = @"This replaces the current editor contents with the version on disk.";
    [confirm addButtonWithTitle:@"Revert"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSError *err = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (!contents) {
        NSAlert *alert = [NSAlert alertWithError:err];
        [alert runModal];
        return;
    }

    NSData *utf8 = [contents dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) return;
    grid_replace_text(0, (const uint8_t *)utf8.bytes, utf8.length);
    [self.window setTitleWithRepresentedFilename:path];
    grid_set_editor_modified(0);
    [self.window setDocumentEdited:NO];
}

@end
