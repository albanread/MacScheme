#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSSplitViewController *splitViewController;
@property (assign) BOOL schemeReady;

- (void)openEditorFile;
- (void)saveEditorFile;
- (void)saveEditorFileAs;
- (void)revertEditorFile;

@end
