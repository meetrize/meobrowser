#import "BrowserTabDragGhostController.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kGhostInStripAlpha = 0.88;
static const CGFloat kGhostDetachAlpha = 0.78;
static const CGFloat kGhostForeignAlpha = 0.85;
static const CGFloat kGhostDetachScale = 1.03;

@interface BrowserTabDragGhostController ()
@property (nonatomic, strong, nullable) NSPanel *panel;
@property (nonatomic, strong, nullable) NSImageView *imageView;
@property (nonatomic, strong, nullable) NSTextField *badgeLabel;
@property (nonatomic, assign) NSPoint grabPointInSource;
@property (nonatomic, assign) NSSize sourceSize;
@property (nonatomic, assign, readwrite) BrowserTabDragGhostStyle style;
@property (nonatomic, assign) BOOL animatingOut;
@end

@implementation BrowserTabDragGhostController

- (BOOL)visible {
    return self.panel != nil && self.panel.isVisible;
}

- (NSSize)ghostSize {
    return self.sourceSize;
}

- (void)beginWithSourceView:(NSView *)sourceView grabPointInSource:(NSPoint)grabPointInSource {
    [self endAndRemoveImmediately];

    if (!sourceView || NSWidth(sourceView.bounds) < 1 || NSHeight(sourceView.bounds) < 1) {
        return;
    }

    self.grabPointInSource = grabPointInSource;
    self.sourceSize = sourceView.bounds.size;
    self.style = BrowserTabDragGhostStyleInStrip;
    self.animatingOut = NO;

    NSBitmapImageRep *rep =
        [sourceView bitmapImageRepForCachingDisplayInRect:sourceView.bounds];
    if (!rep) {
        return;
    }
    [sourceView cacheDisplayInRect:sourceView.bounds toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:sourceView.bounds.size];
    [image addRepresentation:rep];

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, self.sourceSize.width, self.sourceSize.height)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = NO;
    panel.level = NSFloatingWindowLevel;
    panel.ignoresMouseEvents = YES;
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSView *content = panel.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor clearColor].CGColor;

    NSImageView *imageView = [[NSImageView alloc] initWithFrame:content.bounds];
    imageView.image = image;
    imageView.imageScaling = NSImageScaleAxesIndependently;
    imageView.wantsLayer = YES;
    imageView.alphaValue = kGhostInStripAlpha;
    imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    imageView.layer.cornerRadius = 6.0;
    imageView.layer.masksToBounds = NO;
    imageView.layer.shadowColor = [NSColor blackColor].CGColor;
    imageView.layer.shadowOpacity = 0.25;
    imageView.layer.shadowRadius = 8.0;
    imageView.layer.shadowOffset = CGSizeMake(0, -2);
    [content addSubview:imageView];

    NSTextField *badge = [NSTextField labelWithString:@"新窗口"];
    badge.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
    badge.textColor = [NSColor whiteColor];
    badge.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.85];
    badge.drawsBackground = YES;
    badge.bezeled = NO;
    badge.editable = NO;
    badge.selectable = NO;
    badge.alignment = NSTextAlignmentCenter;
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 8.0;
    badge.layer.masksToBounds = YES;
    badge.hidden = YES;
    [badge sizeToFit];
    NSRect badgeFrame = badge.frame;
    badgeFrame.size.width += 10.0;
    badgeFrame.size.height = MAX(NSHeight(badgeFrame), 16.0);
    badgeFrame.origin.x = NSWidth(content.bounds) - NSWidth(badgeFrame) - 4.0;
    badgeFrame.origin.y = 4.0;
    badge.frame = badgeFrame;
    badge.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:badge];

    self.panel = panel;
    self.imageView = imageView;
    self.badgeLabel = badge;
}

- (void)moveToScreenPoint:(NSPoint)screenPoint {
    if (!self.panel || self.animatingOut) {
        return;
    }

    CGFloat scale = (self.style == BrowserTabDragGhostStyleDetach) ? kGhostDetachScale : 1.0;
    NSSize size = NSMakeSize(self.sourceSize.width * scale, self.sourceSize.height * scale);
    NSPoint origin = NSMakePoint(screenPoint.x - self.grabPointInSource.x * scale,
                                 screenPoint.y - self.grabPointInSource.y * scale);
    [self.panel setFrame:NSMakeRect(origin.x, origin.y, size.width, size.height) display:YES];
    if (!self.panel.isVisible) {
        [self.panel orderFrontRegardless];
    }
}

- (void)setDetachMode:(BOOL)detachMode animated:(BOOL)animated {
    [self setStyle:(detachMode ? BrowserTabDragGhostStyleDetach : BrowserTabDragGhostStyleInStrip)
          animated:animated];
}

- (void)setStyle:(BrowserTabDragGhostStyle)style animated:(BOOL)animated {
    if (self.style == style && self.panel) {
        return;
    }
    self.style = style;
    if (!self.panel || !self.imageView) {
        return;
    }

    void (^apply)(void) = ^{
        switch (style) {
            case BrowserTabDragGhostStyleDetach:
                self.imageView.alphaValue = kGhostDetachAlpha;
                self.badgeLabel.stringValue = @"新窗口";
                [self.badgeLabel sizeToFit];
                {
                    NSRect badgeFrame = self.badgeLabel.frame;
                    badgeFrame.size.width += 10.0;
                    badgeFrame.size.height = MAX(NSHeight(badgeFrame), 16.0);
                    badgeFrame.origin.x = NSWidth(self.panel.contentView.bounds) - NSWidth(badgeFrame) - 4.0;
                    badgeFrame.origin.y = 4.0;
                    self.badgeLabel.frame = badgeFrame;
                }
                self.badgeLabel.hidden = NO;
                self.imageView.layer.shadowOpacity = 0.35;
                self.imageView.layer.shadowRadius = 12.0;
                self.imageView.layer.borderWidth = 1.0;
                self.imageView.layer.borderColor =
                    [[NSColor controlAccentColor] colorWithAlphaComponent:0.35].CGColor;
                break;
            case BrowserTabDragGhostStyleForeign:
                self.imageView.alphaValue = kGhostForeignAlpha;
                self.badgeLabel.stringValue = @"移到此窗口";
                [self.badgeLabel sizeToFit];
                {
                    NSRect badgeFrame = self.badgeLabel.frame;
                    badgeFrame.size.width += 10.0;
                    badgeFrame.size.height = MAX(NSHeight(badgeFrame), 16.0);
                    badgeFrame.origin.x = NSWidth(self.panel.contentView.bounds) - NSWidth(badgeFrame) - 4.0;
                    badgeFrame.origin.y = 4.0;
                    self.badgeLabel.frame = badgeFrame;
                }
                self.badgeLabel.hidden = NO;
                self.imageView.layer.shadowOpacity = 0.3;
                self.imageView.layer.shadowRadius = 10.0;
                self.imageView.layer.borderWidth = 1.0;
                self.imageView.layer.borderColor =
                    [[NSColor controlAccentColor] colorWithAlphaComponent:0.45].CGColor;
                break;
            case BrowserTabDragGhostStyleInStrip:
            default:
                self.imageView.alphaValue = kGhostInStripAlpha;
                self.badgeLabel.hidden = YES;
                self.imageView.layer.shadowOpacity = 0.25;
                self.imageView.layer.shadowRadius = 8.0;
                self.imageView.layer.borderWidth = 0.0;
                break;
        }
    };

    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.1;
            apply();
        } completionHandler:nil];
    } else {
        apply();
    }
}

- (BOOL)shouldReduceMotion {
    if (@available(macOS 10.12, *)) {
        return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    }
    return NO;
}

- (void)animateToScreenRect:(NSRect)screenRect completion:(void (^)(void))completion {
    if (!self.panel) {
        if (completion) {
            completion();
        }
        return;
    }

    self.animatingOut = YES;
    if ([self shouldReduceMotion]) {
        [self endAndRemoveImmediately];
        if (completion) {
            completion();
        }
        return;
    }

    NSPanel *panel = self.panel;
    NSImageView *imageView = self.imageView;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.16;
        context.timingFunction =
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [panel.animator setFrame:screenRect display:YES];
        imageView.animator.alphaValue = 0.0;
        self.badgeLabel.animator.hidden = YES;
    } completionHandler:^{
        [self endAndRemoveImmediately];
        if (completion) {
            completion();
        }
    }];
}

- (void)fadeOutWithCompletion:(void (^)(void))completion {
    if (!self.panel) {
        if (completion) {
            completion();
        }
        return;
    }
    self.animatingOut = YES;
    if ([self shouldReduceMotion]) {
        [self endAndRemoveImmediately];
        if (completion) {
            completion();
        }
        return;
    }
    NSImageView *imageView = self.imageView;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.08;
        imageView.animator.alphaValue = 0.0;
        self.badgeLabel.animator.alphaValue = 0.0;
    } completionHandler:^{
        [self endAndRemoveImmediately];
        if (completion) {
            completion();
        }
    }];
}

- (void)endAndRemoveImmediately {
    self.animatingOut = NO;
    if (self.panel) {
        [self.panel orderOut:nil];
        self.panel = nil;
    }
    self.imageView = nil;
    self.badgeLabel = nil;
    self.style = BrowserTabDragGhostStyleInStrip;
}

@end
