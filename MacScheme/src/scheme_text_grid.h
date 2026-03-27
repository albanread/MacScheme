#import <MetalKit/MetalKit.h>
#import <Cocoa/Cocoa.h>
#import "metal_grid_types.h"

// C-API exposed by Zig
extern void grid_on_resize(int grid_id, float width, float height, float scale);
extern struct EdFrameData grid_on_frame(int grid_id, double dt);
extern void grid_on_key_down(int grid_id, uint32_t keycode, uint32_t mods);
extern void grid_on_mouse_double_click(int grid_id, int row, int col, uint32_t mods);
extern void grid_on_mouse_down(int grid_id, int row, int col, uint32_t mods);
extern void grid_on_mouse_drag(int grid_id, int row, int col, uint32_t mods);
extern void grid_on_mouse_up(int grid_id, int row, int col, uint32_t mods);
extern void grid_on_scroll(int grid_id, int delta_rows);
extern void grid_on_text(int grid_id, uint32_t codepoint);
extern void grid_paste_text(int grid_id, const uint8_t *bytes, size_t len);
extern const uint8_t *grid_copy_text(int grid_id, size_t *out_len);
extern const uint8_t *grid_copy_selection_text(int grid_id, size_t *out_len);
extern const uint8_t *grid_cut_selection_text(int grid_id, size_t *out_len);
extern void grid_replace_text(int grid_id, const uint8_t *bytes, size_t len);
extern void grid_free_bytes(const uint8_t *bytes, size_t len);
extern void grid_set_editor_file_path(const uint8_t *bytes, size_t len);
extern void grid_set_editor_modified(int modified);
extern int grid_get_editor_modified(void);
extern const uint8_t *grid_get_editor_file_path(size_t *out_len);
extern void grid_append_repl_prompt(const uint8_t *bytes, size_t len);
extern void grid_clear_repl(void);
extern void grid_repl_set_terminal_size(int cols, int rows);
extern void grid_set_theme(int theme_id);
extern int grid_get_theme(void);

@interface SchemeTextGrid : MTKView <NSTextInputClient, MTKViewDelegate>

@property (nonatomic, assign) int gridId;
@property (nonatomic, strong) NSMutableArray<NSEvent *> *pendingKeyEvents;
@property (nonatomic, assign) double lastFrameTime;
@property (nonatomic, assign) float backingScale;

// Shared pipeline state and atlas across all instances
+ (void)initializeSharedGraphicsWithDevice:(id<MTLDevice>)device scale:(float)scale;

- (instancetype)initWithFrame:(NSRect)frameRect gridId:(int)gridId;

@end
