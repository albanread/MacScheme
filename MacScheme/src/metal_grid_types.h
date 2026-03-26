#include <stdint.h>

// Must match the shader
struct GlyphInstance {
    float pos_x;
    float pos_y;
    float uv_x;
    float uv_y;
    uint8_t fg[4];
    uint8_t bg[4];
    uint32_t flags;
};

struct EdUniforms {
    float viewport_width;
    float viewport_height;
    float cell_width;
    float cell_height;
    float atlas_width;
    float atlas_height;
    float time;
    float effects_mode;
};

struct EdFrameData {
    const struct GlyphInstance *instances;
    uint32_t instance_count;
    uint32_t _pad0;
    struct EdUniforms uniforms;
    float clear_r;
    float clear_g;
    float clear_b;
    float clear_a;
};

// Glyph atlas metadata — set once by ObjC after CoreText atlas build,
// read by Zig each frame to compute UV coordinates.
struct GlyphAtlasInfo {
    float    atlas_width;
    float    atlas_height;
    float    cell_width;
    float    cell_height;
    uint32_t cols;
    uint32_t rows;
    uint32_t first_codepoint;
    uint32_t glyph_count;
    float    ascent;
    float    descent;
    float    leading;
    uint32_t _pad;
};

// Called by scheme_text_grid.m after atlas is built to push info to Zig.
// Defined in grid_logic.zig as an export fn.
extern void grid_set_atlas_info(const struct GlyphAtlasInfo *info);

// Flags
#define FLAG_UNDERLINE      (1u << 0)
#define FLAG_BOLD           (1u << 1)
#define FLAG_CURSOR         (1u << 2)
#define FLAG_STRIKETHROUGH  (1u << 3)
#define FLAG_WAVY_UNDERLINE (1u << 4)
#define FLAG_SELECTION      (1u << 5)
#define FLAG_INVERSE        (1u << 6)
