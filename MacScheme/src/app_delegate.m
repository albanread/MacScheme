#import "app_delegate.h"
#import <MetalKit/MetalKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
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
extern int64_t macscheme_gfx_buffer_width(void);
extern int64_t macscheme_gfx_buffer_height(void);
extern void gfx_set_host_view(void *ns_view);

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

static NSArray<UTType *> *MacSchemeAllowedContentTypes(void) {
    static NSArray<UTType *> *types = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<UTType *> *built = [NSMutableArray array];
        for (NSString *ext in @[@"ss", @"scm", @"sls", @"sld", @"sch", @"txt"]) {
            UTType *type = [UTType typeWithFilenameExtension:ext conformingToType:UTTypeText];
            if (type) [built addObject:type];
        }
        if (UTTypePlainText) [built addObject:UTTypePlainText];
        types = [built copy];
    });
    return types;
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
           "(define macscheme-gfx-buffer-width "
           "  (foreign-procedure \"macscheme_gfx_buffer_width\" () integer-64)) "
           "(define macscheme-gfx-buffer-height "
           "  (foreign-procedure \"macscheme_gfx_buffer_height\" () integer-64)) "
           "(define (->int v) (exact (round v))) "
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
           "(define (gfx-buffer-width) (macscheme-gfx-buffer-width)) "
           "(define (gfx-buffer-height) (macscheme-gfx-buffer-height)) "
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
static NSMenuItem *AddMenuItem(NSMenu *menu, NSString *title, SEL action, NSString *keyEquivalent, NSEventModifierFlags modifiers, id target) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:keyEquivalent ?: @""];
    item.keyEquivalentModifierMask = modifiers;
    item.target = target;
    [menu addItem:item];
    return item;
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
- (BOOL)applyLayoutPreset:(MacSchemeLayoutPreset)preset;
- (BOOL)setPane:(MacSchemePane)pane visible:(BOOL)visible;
- (BOOL)isPaneVisible:(MacSchemePane)pane;
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

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
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
    return YES;
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
        NSString *result = EvaluateSchemeExpression(expr, &isError);

        dispatch_async(dispatch_get_main_queue(), ^{
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
    AddMenuItem(appMenu, [NSString stringWithFormat:@"About %@", appName], @selector(orderFrontStandardAboutPanel:), @"", 0, NSApp);
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
    AddMenuItem(editMenu, @"Copy", @selector(copy:), @"c", NSEventModifierFlagCommand, nil);
    AddMenuItem(editMenu, @"Paste", @selector(paste:), @"v", NSEventModifierFlagCommand, nil);

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

    NSMenuItem *schemeRoot = [[NSMenuItem alloc] initWithTitle:@"Scheme" action:nil keyEquivalent:@""];
    [mainMenu addItem:schemeRoot];
    NSMenu *schemeMenu = [[NSMenu alloc] initWithTitle:@"Scheme"];
    [schemeRoot setSubmenu:schemeMenu];
    AddMenuItem(schemeMenu, @"Evaluate Selection", @selector(evaluateSelectionOrForm:), @"e", NSEventModifierFlagCommand, self);
    AddMenuItem(schemeMenu, @"Evaluate Top-Level Form", @selector(evaluateTopLevelForm:), @"\r", NSEventModifierFlagCommand, self);
    AddMenuItem(schemeMenu, @"Evaluate Buffer", @selector(evaluateBuffer:), @"b", NSEventModifierFlagCommand, self);

    [NSApp setMainMenu:mainMenu];
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
    grid_on_key_down(0, 14, 8);
}

- (void)evaluateTopLevelForm:(id)sender {
    (void)sender;
    grid_on_key_down(0, 36, 8);
}

- (void)evaluateBuffer:(id)sender {
    (void)sender;
    grid_on_key_down(0, 11, 8);
}

- (void)undo:(id)sender {
    (void)sender;
    grid_on_key_down(0, 6, 8);
}

- (void)redo:(id)sender {
    (void)sender;
    grid_on_key_down(0, 6, 9);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    (void)aNotification;
    g_app_delegate = self;
    self.schemeReady = NO;
    [self installMainMenu];

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
    [NSApp activateIgnoringOtherApps:YES];
    LoadPersistedReplHistory();
    dispatch_async(dispatch_get_main_queue(), ^{
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    NSLog(@"MacScheme window frame=%@ visible=%d key=%d main=%d", NSStringFromRect(self.window.frame), self.window.isVisible, self.window.isKeyWindow, self.window.isMainWindow);
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
    Sforeign_symbol("macscheme_gfx_buffer_width", (void *)macscheme_gfx_buffer_width);
    Sforeign_symbol("macscheme_gfx_buffer_height", (void *)macscheme_gfx_buffer_height);
    Sforeign_symbol("macscheme_layout_set", (void *)macscheme_layout_set);
    Sforeign_symbol("macscheme_layout_show_pane", (void *)macscheme_layout_show_pane);
    Sforeign_symbol("macscheme_layout_hide_pane", (void *)macscheme_layout_hide_pane);
    Sforeign_symbol("macscheme_layout_toggle_pane", (void *)macscheme_layout_toggle_pane);
    Sforeign_symbol("macscheme_layout_reset", (void *)macscheme_layout_reset);
    Sforeign_symbol("macscheme_layout_current", (void *)macscheme_layout_current);
    Sforeign_symbol("macscheme_layout_pane_visible", (void *)macscheme_layout_pane_visible);
    ptr eval_string = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                             Scall1(Stop_level_value(Sstring_to_symbol("read")),
                                    Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                                           Sstring("(lambda (s) (guard (ex [else (list #t (with-output-to-string (lambda () (display-condition ex))))]) (list #f (with-output-to-string (lambda () (write (eval (read (open-input-string s)) (interaction-environment))))))))"))));
    Sset_top_level_value(Sstring_to_symbol("macscheme-eval-string"), eval_string);

    ptr load_string = Scall1(Stop_level_value(Sstring_to_symbol("eval")),
                             Scall1(Stop_level_value(Sstring_to_symbol("read")),
                                    Scall1(Stop_level_value(Sstring_to_symbol("open-input-string")),
                                           Sstring("(lambda (path) (guard (ex [else (list #t (with-output-to-string (lambda () (display-condition ex))))]) (with-input-from-file path (lambda () (let loop ((last (void)) (saw? #f)) (let ((form (read))) (if (eof-object? form) (list #f (if saw? (with-output-to-string (lambda () (write last))) \"\")) (loop (eval form (interaction-environment)) #t))))))))"))));
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
    panel.allowedContentTypes = MacSchemeAllowedContentTypes();
    panel.allowsOtherFileTypes = YES;
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
    panel.allowedContentTypes = MacSchemeAllowedContentTypes();

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
