#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
@property (strong) NSWindow *window;
@property (strong) NSSplitViewController *splitViewController;
@property (assign) BOOL schemeReady;

- (void)openEditorFile;
- (void)saveEditorFile;
- (void)saveEditorFileAs;
- (void)revertEditorFile;
- (void)showSchemeHelp:(id)sender;

@end
