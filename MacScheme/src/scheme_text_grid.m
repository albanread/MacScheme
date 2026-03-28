#import "scheme_text_grid.h"
#import "app_delegate.h"
#import "editor/embedded_glyph_metal_source.h"
#import "metal_grid_types.h"
#include <mach/mach_time.h>
#include <math.h>
#include <Carbon/Carbon.h>
#include <CoreText/CoreText.h>

// ─── Shared Metal state (one device, one command queue, shared pipelines) ───

static id<MTLDevice>              g_sharedDevice          = nil;
static id<MTLCommandQueue>        g_sharedCommandQueue     = nil;
static id<MTLRenderPipelineState> g_sharedGlyphPipelineState = nil;
static id<MTLTexture>             g_sharedAtlasTexture     = nil;
static id<MTLSamplerState>        g_sharedSampler          = nil;
static __weak SchemeTextGrid *    g_activeGrid             = nil;
static BOOL                       g_installedKeyMonitor    = NO;
static float                      g_cellWidth              = 8.0f;
static float                      g_cellHeight             = 16.0f;

// ─── Timing helpers ─────────────────────────────────────────────────────────

static mach_timebase_info_data_t g_timebase = {0};
static uint64_t                  g_start_time = 0;

static double getTimeSeconds(void) {
    if (g_start_time == 0) {
        mach_timebase_info(&g_timebase);
        g_start_time = mach_absolute_time();
    }
    uint64_t now     = mach_absolute_time();
    uint64_t elapsed = now - g_start_time;
    double   nanos   = (double)elapsed * (double)g_timebase.numer / (double)g_timebase.denom;
    return nanos / 1e9;
}

// ─── Modifier helpers ────────────────────────────────────────────────────────

static uint32_t modifiersFromNSEvent(NSEvent *event) {
    NSEventModifierFlags f = event.modifierFlags;
    uint32_t m = 0;
    if (f & NSEventModifierFlagShift)   m |= 1;
    if (f & NSEventModifierFlagControl) m |= 2;
    if (f & NSEventModifierFlagOption)  m |= 4;
    if (f & NSEventModifierFlagCommand) m |= 8;
    return m;
}

typedef NS_ENUM(uint32_t, MacSchemeGridKey) {
    MacSchemeGridKeyLeft        = 123,
    MacSchemeGridKeyRight       = 124,
    MacSchemeGridKeyDown        = 125,
    MacSchemeGridKeyUp          = 126,
    MacSchemeGridKeyBackspace   = 51,
    MacSchemeGridKeyDelete      = 117,
    MacSchemeGridKeyEnter       = 36,
    MacSchemeGridKeyPageUp      = 116,
    MacSchemeGridKeyPageDown    = 121,
    MacSchemeGridKeyHome        = 115,
    MacSchemeGridKeyEnd         = 119,
};

static BOOL commandSelectorToGridKey(SEL selector, uint32_t *outKeyCode) {
    if (selector == @selector(moveLeft:))              { *outKeyCode = MacSchemeGridKeyLeft; return YES; }
    if (selector == @selector(moveRight:))             { *outKeyCode = MacSchemeGridKeyRight; return YES; }
    if (selector == @selector(moveUp:))                { *outKeyCode = MacSchemeGridKeyUp; return YES; }
    if (selector == @selector(moveDown:))              { *outKeyCode = MacSchemeGridKeyDown; return YES; }
    if (selector == @selector(moveToBeginningOfLine:)) { *outKeyCode = MacSchemeGridKeyHome; return YES; }
    if (selector == @selector(moveToEndOfLine:))       { *outKeyCode = MacSchemeGridKeyEnd; return YES; }
    if (selector == @selector(pageUp:) || selector == @selector(scrollPageUp:)) {
        *outKeyCode = MacSchemeGridKeyPageUp;
        return YES;
    }
    if (selector == @selector(pageDown:) || selector == @selector(scrollPageDown:)) {
        *outKeyCode = MacSchemeGridKeyPageDown;
        return YES;
    }
    if (selector == @selector(deleteForward:))         { *outKeyCode = MacSchemeGridKeyDelete; return YES; }
    if (selector == @selector(deleteBackward:))        { *outKeyCode = MacSchemeGridKeyBackspace; return YES; }
    if (selector == @selector(insertNewline:))         { *outKeyCode = MacSchemeGridKeyEnter; return YES; }
    return NO;
}

static int lineDeltaFromScrollEvent(NSEvent *event) {
    CGFloat dy = event.scrollingDeltaY;
    if (fabs(dy) < 0.01) return 0;

    if (event.hasPreciseScrollingDeltas) {
        CGFloat scaled = dy / MAX(g_cellHeight * 0.75f, 1.0f);
        int lines = (int)lround(scaled);
        if (lines == 0) {
            lines = dy > 0 ? 1 : -1;
        }
        return -lines;
    }

    int lines = (int)lround(dy);
    if (lines == 0) {
        lines = dy > 0 ? 1 : -1;
    }
    return -lines;
}

static BOOL isFunctionKeyCharacter(unichar c) {
    switch (c) {
        case NSUpArrowFunctionKey:
        case NSDownArrowFunctionKey:
        case NSLeftArrowFunctionKey:
        case NSRightArrowFunctionKey:
        case NSHomeFunctionKey:
        case NSEndFunctionKey:
        case NSDeleteFunctionKey:
        case NSPageUpFunctionKey:
        case NSPageDownFunctionKey:
            return YES;
        default:
            return NO;
    }
}

static void gridCellForEvent(SchemeTextGrid *grid, NSEvent *event, int *outRow, int *outCol) {
    NSPoint pointInView = [grid convertPoint:event.locationInWindow fromView:nil];
    NSPoint pointInBacking = [grid convertPointToBacking:pointInView];
    NSSize sizeInBacking = [grid convertSizeToBacking:grid.bounds.size];

    CGFloat maxX = sizeInBacking.width > 1.0 ? sizeInBacking.width - 1.0 : 0.0;
    CGFloat maxY = sizeInBacking.height > 1.0 ? sizeInBacking.height - 1.0 : 0.0;
    CGFloat x = fmin(fmax(pointInBacking.x, 0.0), maxX);
    CGFloat yFromTop = fmin(fmax(sizeInBacking.height - pointInBacking.y - 1.0, 0.0), maxY);

    *outCol = (int)floor(x / MAX(g_cellWidth, 1.0f));
    *outRow = (int)floor(yFromTop / MAX(g_cellHeight, 1.0f));
}

@interface SchemeTextGrid ()

@property (nonatomic, assign) int contextMenuRow;
@property (nonatomic, assign) int contextMenuCol;

@end

// ─── Glyph Atlas Builder ─────────────────────────────────────────────────────
//
// Ported directly from FasterBASIC-public/editor/macgui/ed_metal_bridge.m.
// Renders printable ASCII (0x20–0x7E) into an RGBA texture and sends the
// atlas info to Zig via grid_set_atlas_info().

static BOOL buildGlyphAtlas(id<MTLDevice> device, const char *fontName, float fontSize, float scale) {
    float scaledSize = fontSize * scale;

    CFStringRef cfName = CFStringCreateWithCString(NULL, fontName, kCFStringEncodingUTF8);
    CTFontRef   ctFont = CTFontCreateWithName(cfName, (CGFloat)scaledSize, NULL);
    CFRelease(cfName);

    if (!ctFont) {
        NSLog(@"MacScheme: Failed to create font '%s', falling back to Menlo", fontName);
        ctFont = CTFontCreateWithName(CFSTR("Menlo"), (CGFloat)scaledSize, NULL);
        if (!ctFont) {
            NSLog(@"MacScheme: FATAL — cannot create any font");
            return NO;
        }
    }

    CGFloat ascent  = CTFontGetAscent(ctFont);
    CGFloat descent = CTFontGetDescent(ctFont);
    CGFloat leading = CTFontGetLeading(ctFont);

    // Cell dimensions from space-character advance
    CGGlyph spaceGlyph;
    UniChar spaceChar = ' ';
    CTFontGetGlyphsForCharacters(ctFont, &spaceChar, &spaceGlyph, 1);
    CGSize adv;
    CTFontGetAdvancesForGlyphs(ctFont, kCTFontOrientationDefault, &spaceGlyph, &adv, 1);

    float cellW = (float)ceil(adv.width);
    float cellH = (float)ceil(ascent + descent + leading);
    if (cellW < 4.0f)  cellW = 8.0f;
    if (cellH < 8.0f)  cellH = 16.0f;

    // Atlas layout: 95 printable ASCII glyphs, 16 cols × 6 rows
    uint32_t firstCp     = 0x20;
    uint32_t glyphCount  = 95;
    uint32_t cols        = 16;
    uint32_t rows        = 6;

    uint32_t texW = ((uint32_t)ceil(cellW * (float)cols) + 3) & ~3u;
    uint32_t texH = ((uint32_t)ceil(cellH * (float)rows) + 3) & ~3u;

    size_t   bpp    = 4;
    size_t   stride = texW * bpp;
    uint8_t *bitmap = (uint8_t *)calloc(texH * stride, 1);
    if (!bitmap) { CFRelease(ctFont); return NO; }

    CGColorSpaceRef cs  = CGColorSpaceCreateDeviceRGB();
    CGContextRef    ctx = CGBitmapContextCreate(bitmap, texW, texH, 8, stride, cs,
                                                kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(bitmap); CFRelease(ctFont); return NO; }

    // Flip so row-0 is at top (Metal convention)
    CGContextTranslateCTM(ctx, 0, (CGFloat)texH);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1.0, -1.0));

    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextSetShouldAntialias(ctx, YES);
    CGContextSetShouldSmoothFonts(ctx, YES);
    CGContextSetAllowsFontSmoothing(ctx, YES);

    for (uint32_t i = 0; i < glyphCount; i++) {
        uint32_t cp   = firstCp + i;
        uint32_t col  = i % cols;
        uint32_t row  = i / cols;

        float cellX    = (float)col * cellW;
        float cellY    = (float)row * cellH;
        float baselineX = cellX;
        float baselineY = cellY + (float)ascent;

        UniChar uc = (UniChar)cp;
        CFStringRef     charStr = CFStringCreateWithCharacters(NULL, &uc, 1);
        CFStringRef     keys[]  = { kCTFontAttributeName };
        CFTypeRef       vals[]  = { ctFont };
        CFDictionaryRef attrs   = CFDictionaryCreate(NULL,
                                                     (const void **)keys,
                                                     (const void **)vals, 1,
                                                     &kCFCopyStringDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        CFAttributedStringRef attrStr = CFAttributedStringCreate(NULL, charStr, attrs);
        CTLineRef line = CTLineCreateWithAttributedString(attrStr);

        CGContextSetTextPosition(ctx, (CGFloat)baselineX, (CGFloat)baselineY);
        CTLineDraw(line, ctx);

        CFRelease(line);
        CFRelease(attrStr);
        CFRelease(attrs);
        CFRelease(charStr);
    }

    CGContextFlush(ctx);

    // Upload to Metal texture
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:texW
        height:texH
        mipmapped:NO];
    texDesc.usage       = MTLTextureUsageShaderRead;
    texDesc.storageMode = MTLStorageModeShared;

    g_sharedAtlasTexture = [device newTextureWithDescriptor:texDesc];
    if (!g_sharedAtlasTexture) {
        CGContextRelease(ctx);
        free(bitmap);
        CFRelease(ctFont);
        return NO;
    }

    [g_sharedAtlasTexture replaceRegion:MTLRegionMake2D(0, 0, texW, texH)
                            mipmapLevel:0
                              withBytes:bitmap
                            bytesPerRow:stride];

    // Send atlas metrics to Zig
    struct GlyphAtlasInfo info = {
        .atlas_width     = (float)texW,
        .atlas_height    = (float)texH,
        .cell_width      = cellW,
        .cell_height     = cellH,
        .cols            = cols,
        .rows            = rows,
        .first_codepoint = firstCp,
        .glyph_count     = glyphCount,
        .ascent          = (float)ascent,
        .descent         = (float)descent,
        .leading         = (float)leading,
        ._pad            = 0,
    };
    g_cellWidth = cellW;
    g_cellHeight = cellH;
    grid_set_atlas_info(&info);

    CGContextRelease(ctx);
    free(bitmap);
    CFRelease(ctFont);

    NSLog(@"MacScheme: Glyph atlas built — %ux%u, cell %.0fx%.0f, font '%s' %.0fpt (scale %.1f)",
          texW, texH, cellW, cellH, fontName, fontSize, scale);
    return YES;
}

// ─── SchemeTextGrid ──────────────────────────────────────────────────────────

@implementation SchemeTextGrid

+ (void)initializeSharedGraphicsWithDevice:(id<MTLDevice>)device scale:(float)scale {
    if (g_sharedDevice != nil) return;
    g_sharedDevice       = device;
    g_sharedCommandQueue = [device newCommandQueue];

    // ── Shader compilation ──────────────────────────────────────────────
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kEmbeddedGlyphMetalSource
                                                  options:nil
                                                    error:&error];
    if (!library) {
        NSLog(@"MacScheme: Shader compile error: %@", error);
        return;
    }

    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];

    // Glyph pipeline (samples atlas texture)
    desc.label          = @"MacScheme Glyph";
    desc.vertexFunction   = [library newFunctionWithName:@"glyph_vertex"];
    desc.fragmentFunction = [library newFunctionWithName:@"glyph_fragment"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.colorAttachments[0].blendingEnabled             = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
    desc.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
    g_sharedGlyphPipelineState = [device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!g_sharedGlyphPipelineState)
        NSLog(@"MacScheme: Glyph pipeline error: %@", error);

    // Sampler
    MTLSamplerDescriptor *sampDesc = [[MTLSamplerDescriptor alloc] init];
    sampDesc.minFilter    = MTLSamplerMinMagFilterLinear;
    sampDesc.magFilter    = MTLSamplerMinMagFilterLinear;
    sampDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sampDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    g_sharedSampler = [device newSamplerStateWithDescriptor:sampDesc];

    // Build CoreText glyph atlas
    buildGlyphAtlas(device, "Menlo", 13.0f, scale);
}

+ (void)installGlobalKeyMonitor {
    if (g_installedKeyMonitor) return;
    g_installedKeyMonitor = YES;

    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent *event) {
        if ((event.modifierFlags & NSEventModifierFlagCommand) == 0) {
            return event;
        }

        NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
        SchemeTextGrid *grid = g_activeGrid;
        if (!grid) return event;

        if ([chars isEqualToString:@"c"]) {
            [grid copy:nil];
            return nil;
        }
        if ([chars isEqualToString:@"x"]) {
            [grid cut:nil];
            return nil;
        }
        if ([chars isEqualToString:@"v"]) {
            [grid paste:nil];
            return nil;
        }
        return event;
    }];
}

- (instancetype)initWithFrame:(NSRect)frameRect gridId:(int)gridId {
    self = [super initWithFrame:frameRect device:MTLCreateSystemDefaultDevice()];
    if (self) {
        self.gridId           = gridId;
        self.contextMenuRow   = -1;
        self.contextMenuCol   = -1;
        self.pendingKeyEvents = [NSMutableArray array];
        self.colorPixelFormat          = MTLPixelFormatBGRA8Unorm;
        self.preferredFramesPerSecond  = 60;
        self.enableSetNeedsDisplay     = NO;
        self.paused                    = NO;
        self.delegate                  = self;

        if (g_sharedDevice == nil) {
            float scale = [NSScreen mainScreen].backingScaleFactor;
            [SchemeTextGrid initializeSharedGraphicsWithDevice:self.device scale:(float)scale];
        }
        [SchemeTextGrid installGlobalKeyMonitor];
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView      { return YES; }
- (BOOL)wantsUpdateLayer      { return YES; }

- (BOOL)becomeFirstResponder {
    g_activeGrid = self;
    return [super becomeFirstResponder];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    g_activeGrid = self;
    [self.window makeFirstResponder:self];
    int row = 0;
    int col = 0;
    gridCellForEvent(self, event, &row, &col);
    if (event.clickCount >= 2) {
        grid_on_mouse_double_click(self.gridId, row, col, modifiersFromNSEvent(event));
    } else {
        grid_on_mouse_down(self.gridId, row, col, modifiersFromNSEvent(event));
    }
}

- (void)mouseDragged:(NSEvent *)event {
    g_activeGrid = self;
    int row = 0;
    int col = 0;
    gridCellForEvent(self, event, &row, &col);
    grid_on_mouse_drag(self.gridId, row, col, modifiersFromNSEvent(event));
}

- (void)mouseUp:(NSEvent *)event {
    g_activeGrid = self;
    int row = 0;
    int col = 0;
    gridCellForEvent(self, event, &row, &col);
    grid_on_mouse_up(self.gridId, row, col, modifiersFromNSEvent(event));
}

- (void)scrollWheel:(NSEvent *)event {
    g_activeGrid = self;
    [self.window makeFirstResponder:self];
    if (self.gridId != 0) {
        [super scrollWheel:event];
        return;
    }
    int deltaRows = lineDeltaFromScrollEvent(event);
    if (deltaRows != 0) {
        grid_on_scroll(self.gridId, deltaRows);
    } else {
        [super scrollWheel:event];
    }
}

- (BOOL)hasCopyableSelection {
    size_t len = 0;
    const uint8_t *bytes = grid_copy_selection_text(self.gridId, &len);
    if (bytes) {
        grid_free_bytes(bytes, len);
    }
    return bytes != NULL && len > 0;
}

- (BOOL)hasPasteboardText {
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    return text.length > 0;
}

- (void)clearRepl:(id)sender {
    (void)sender;
    if (self.gridId != 1) return;
    grid_clear_repl();
}

- (void)gotoDefinitionFromContextMenu:(id)sender {
    (void)sender;
    if (self.gridId != 0) return;

    BOOL jumped = NO;
    if (self.contextMenuRow >= 0 && self.contextMenuCol >= 0) {
        jumped = grid_editor_goto_definition_at(self.contextMenuRow, self.contextMenuCol) != 0;
    } else {
        jumped = grid_editor_goto_definition() != 0;
    }

    if (!jumped) {
        NSBeep();
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    g_activeGrid = self;
    [self.window makeFirstResponder:self];

    self.contextMenuRow = -1;
    self.contextMenuCol = -1;
    if (self.gridId == 0) {
        int row = 0;
        int col = 0;
        gridCellForEvent(self, event, &row, &col);
        self.contextMenuRow = row;
        self.contextMenuCol = col;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context"];
    menu.autoenablesItems = NO;

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
    copyItem.target = self;
    copyItem.enabled = [self hasCopyableSelection];
    [menu addItem:copyItem];

    NSMenuItem *pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@""];
    pasteItem.target = self;
    pasteItem.enabled = [self hasPasteboardText];
    [menu addItem:pasteItem];

    if (self.gridId == 0) {
        BOOL canGoto = self.contextMenuRow >= 0 && self.contextMenuCol >= 0 &&
                       grid_editor_can_goto_definition_at(self.contextMenuRow, self.contextMenuCol) != 0;
        if (canGoto) {
            [menu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *gotoItem = [[NSMenuItem alloc] initWithTitle:@"Go to Definition" action:@selector(gotoDefinitionFromContextMenu:) keyEquivalent:@""];
            gotoItem.target = self;
            gotoItem.enabled = YES;
            [menu addItem:gotoItem];
        }
    }

    if (self.gridId == 1) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"Clear REPL" action:@selector(clearRepl:) keyEquivalent:@""];
        clearItem.target = self;
        clearItem.enabled = YES;
        [menu addItem:clearItem];
    }

    return menu;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    g_activeGrid = self;
    if (event.keyCode == 0x7A && modifiersFromNSEvent(event) == 0) {
        AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
        [delegate showSchemeHelp:nil];
        return YES;
    }

    if ((event.modifierFlags & NSEventModifierFlagCommand) == 0) {
        return [super performKeyEquivalent:event];
    }

    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;

    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
    if ([chars isEqualToString:@"c"]) {
        [self copy:nil];
        return YES;
    }
    if ([chars isEqualToString:@"x"]) {
        [self cut:nil];
        return YES;
    }
    if ([chars isEqualToString:@"v"]) {
        [self paste:nil];
        return YES;
    }
    if ([chars isEqualToString:@"o"] && self.gridId == 0) {
        AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
        [delegate openEditorFile];
        return YES;
    }
    if ([chars isEqualToString:@"s"] && self.gridId == 0) {
        AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
        if (shiftDown) {
            [delegate saveEditorFileAs];
        } else {
            [delegate saveEditorFile];
        }
        return YES;
    }
    if ([chars isEqualToString:@"r"] && self.gridId == 0) {
        AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
        [delegate revertEditorFile];
        return YES;
    }
    if ([chars isEqualToString:@"z"] && self.gridId == 0) {
        grid_on_key_down(self.gridId, event.keyCode, modifiersFromNSEvent(event));
        return YES;
    }

    return [super performKeyEquivalent:event];
}

- (void)copy:(id)sender {
    (void)sender;
    size_t len = 0;
    const uint8_t *bytes = grid_copy_selection_text(self.gridId, &len);
    if (bytes == NULL || len == 0) return;

    NSString *text = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
    grid_free_bytes(bytes, len);
    if (!text) return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)cut:(id)sender {
    (void)sender;
    size_t len = 0;
    const uint8_t *bytes = grid_cut_selection_text(self.gridId, &len);
    if (bytes == NULL || len == 0) return;

    NSString *text = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
    grid_free_bytes(bytes, len);
    if (!text) return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)paste:(id)sender {
    (void)sender;
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (text.length == 0) return;

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || data.length == 0) return;
    grid_paste_text(self.gridId, (const uint8_t *)data.bytes, data.length);
}

// ── Keyboard ────────────────────────────────────────────────────────────────

- (void)keyDown:(NSEvent *)event {
    g_activeGrid = self;
    uint32_t mods = modifiersFromNSEvent(event);
    if (self.gridId == 1 && (mods & (2 | 4)) != 0 && (mods & 8) == 0) {
        grid_on_key_down(self.gridId, event.keyCode, mods);
        return;
    }
    [self.pendingKeyEvents addObject:event];
    [self interpretKeyEvents:@[event]];     // may call insertText:
    // If interpretKeyEvents didn't consume it, forward raw keycode
    if ([self.pendingKeyEvents containsObject:event]) {
        [self.pendingKeyEvents removeObject:event];
        grid_on_key_down(self.gridId, event.keyCode, mods);
    }
}

// ── NSTextInputClient ────────────────────────────────────────────────────────

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    g_activeGrid = self;
    NSString *text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString *)string string]
                     : (NSString *)string;
    if (text.length == 1 && isFunctionKeyCharacter([text characterAtIndex:0])) {
        return;
    }
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        grid_on_text(self.gridId, (uint32_t)c);
    }
    [self.pendingKeyEvents removeAllObjects];
}

- (void)doCommandBySelector:(SEL)selector {
    g_activeGrid = self;

    uint32_t keyCode = 0;
    if (commandSelectorToGridKey(selector, &keyCode)) {
        NSEvent *event = self.pendingKeyEvents.lastObject;
        uint32_t mods = event ? modifiersFromNSEvent(event) : 0;
        grid_on_key_down(self.gridId, keyCode, mods);
        [self.pendingKeyEvents removeAllObjects];
        return;
    }

    [super doCommandBySelector:selector];
}

- (void)setMarkedText:(id)s selectedRange:(NSRange)sel replacementRange:(NSRange)rep {
    (void)s; (void)sel; (void)rep;
}
- (void)unmarkText {}
- (NSRange)selectedRange  { return NSMakeRange(NSNotFound, 0); }
- (NSRange)markedRange    { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText     { return NO; }
- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(nullable NSRangePointer)ar {
    (void)r; (void)ar; return nil;
}
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(nullable NSRangePointer)ar {
    (void)r; (void)ar; return NSZeroRect;
}
- (NSUInteger)characterIndexForPoint:(NSPoint)p { (void)p; return NSNotFound; }

// ── MTKViewDelegate ──────────────────────────────────────────────────────────

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    grid_on_resize(self.gridId, (float)size.width, (float)size.height,
                   (float)self.window.backingScaleFactor);
}

- (void)drawInMTKView:(MTKView *)view {
    double now = getTimeSeconds();
    double dt  = now - self.lastFrameTime;
    self.lastFrameTime = now;

    if (self.gridId == 0) {
        BOOL edited = grid_get_editor_modified() != 0;
        if (self.window.isDocumentEdited != edited) {
            [self.window setDocumentEdited:edited];
        }
    }

    struct EdFrameData frame = grid_on_frame(self.gridId, dt);

    MTLRenderPassDescriptor *passDesc = view.currentRenderPassDescriptor;
    if (!passDesc) return;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!drawable) return;

    passDesc.colorAttachments[0].loadAction  = MTLLoadActionClear;
    passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(
        frame.clear_r, frame.clear_g, frame.clear_b, frame.clear_a);

    id<MTLCommandBuffer>        cmd     = [g_sharedCommandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:passDesc];

    if (frame.instance_count > 0 && frame.instances != NULL) {
        NSUInteger byteLen = frame.instance_count * sizeof(struct GlyphInstance);

        // Reuse or create a MTLBuffer — newBufferWithBytes copies once per frame
        id<MTLBuffer> instBuf = [self.device newBufferWithBytes:frame.instances
                                                         length:byteLen
                                                        options:MTLResourceStorageModeShared];

        // Glyph pass: shader blends fg over bg per cell.
        if (g_sharedGlyphPipelineState && g_sharedAtlasTexture) {
            [encoder setRenderPipelineState:g_sharedGlyphPipelineState];
            [encoder setVertexBuffer:instBuf offset:0 atIndex:0];
            [encoder setVertexBytes:&frame.uniforms length:sizeof(struct EdUniforms) atIndex:1];
            [encoder setFragmentTexture:g_sharedAtlasTexture atIndex:0];
            if (g_sharedSampler)
                [encoder setFragmentSamplerState:g_sharedSampler atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                        vertexStart:0
                        vertexCount:6
                      instanceCount:frame.instance_count];
        }
    }

    [encoder endEncoding];
    [cmd presentDrawable:drawable];
    [cmd commit];
}

@end
