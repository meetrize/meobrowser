#import "BrowserTabDropPlaceholderView.h"

@implementation BrowserTabDropPlaceholderView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6.0;
        self.layer.borderWidth = 1.0;
        [self updateAppearance];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateAppearance];
}

- (void)updateAppearance {
    NSColor *accent = [NSColor controlAccentColor];
    self.layer.backgroundColor = [accent colorWithAlphaComponent:0.12].CGColor;
    self.layer.borderColor = [accent colorWithAlphaComponent:0.4].CGColor;
}

- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

@end
