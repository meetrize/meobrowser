#import "BrowserPresentationFullscreenController.h"
#import "BrowserWindowController.h"

@interface BrowserWindowController (PresentationFullscreenHost)
- (BOOL)canEnterPresentationFullscreen;
- (void)presentationFullscreenPrepareToEnter;
- (void)presentationFullscreenApplyChromeHidden:(BOOL)hidden;
- (void)presentationFullscreenLayoutSelectedWebView;
- (void)presentationFullscreenRestoreChromeAfterExit;
@end

@interface BrowserPresentationFullscreenController ()
@property (nonatomic, assign, readwrite, getter=isActive) BOOL active;
@property (nonatomic, assign) BOOL pendingNativeExitCleanup;
@end

@implementation BrowserPresentationFullscreenController

- (BOOL)canEnter {
    BrowserWindowController *wc = self.windowController;
    if (!wc) {
        return NO;
    }
    if (self.active) {
        return YES;
    }
    return [wc canEnterPresentationFullscreen];
}

- (void)toggle {
    if (self.active) {
        [self exit];
    } else {
        [self enter];
    }
}

- (void)enter {
    if (self.active || ![self canEnter]) {
        return;
    }
    BrowserWindowController *wc = self.windowController;
    NSWindow *window = wc.window;
    if (!window) {
        return;
    }

    [wc presentationFullscreenPrepareToEnter];
    self.active = YES;
    self.pendingNativeExitCleanup = NO;
    [wc presentationFullscreenApplyChromeHidden:YES];

    if ((window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        [wc presentationFullscreenLayoutSelectedWebView];
        return;
    }
    [window toggleFullScreen:nil];
}

- (void)exit {
    if (!self.active) {
        return;
    }
    BrowserWindowController *wc = self.windowController;
    NSWindow *window = wc.window;
    if (!window) {
        [self finishExit];
        return;
    }
    if ((window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        self.pendingNativeExitCleanup = YES;
        [window toggleFullScreen:nil];
        return;
    }
    [self finishExit];
}

- (void)windowDidEnterNativeFullscreen {
    if (!self.active) {
        return;
    }
    [self.windowController presentationFullscreenApplyChromeHidden:YES];
    [self.windowController presentationFullscreenLayoutSelectedWebView];
}

- (void)windowDidExitNativeFullscreen {
    if (self.active || self.pendingNativeExitCleanup) {
        [self finishExit];
    }
}

- (void)finishExit {
    self.pendingNativeExitCleanup = NO;
    if (!self.active) {
        return;
    }
    BrowserWindowController *wc = self.windowController;
    self.active = NO;
    if (wc) {
        [wc presentationFullscreenRestoreChromeAfterExit];
    }
}

@end
