#import "BrowserTabDragGhostController.h"
#import "BrowserTabItemView.h"
#import "BrowserTabStripView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kGhostInStripAlpha = 0.88;
static const CGFloat kGhostDetachAlpha = 0.90;
static const CGFloat kGhostForeignAlpha = 0.85;
static const CGFloat kGhostDetachScale = 1.0;
static const CGFloat kDetachTitlebarHeight = 44.0;
static const CGFloat kDetachToolbarHeight = 36.0;
static const CGFloat kDetachTrafficLightInset = 78.0;
static const CGFloat kDetachCornerRadius = 10.0;
static const CGFloat kDetachMinWindowWidth = 420.0;
static const CGFloat kDetachMinWindowHeight = 300.0;
static const CGFloat kDetachMaxPreviewLongEdge = 900.0;

@interface BrowserTabDragGhostController ()
@property (nonatomic, strong, nullable) NSPanel *panel;
@property (nonatomic, strong, nullable) NSView *windowChromeView;
@property (nonatomic, strong, nullable) NSView *titlebarView;
@property (nonatomic, strong, nullable) NSView *toolbarView;
@property (nonatomic, strong, nullable) NSView *trafficLightsView;
@property (nonatomic, strong, nullable) NSImageView *imageView;
@property (nonatomic, strong, nullable) NSImageView *contentImageView;
@property (nonatomic, strong, nullable) NSTextField *badgeLabel;
@property (nonatomic, assign) NSPoint grabPointInSource;
@property (nonatomic, assign) NSPoint activeGrabPoint;
@property (nonatomic, assign) NSSize tabSourceSize;
@property (nonatomic, assign) NSSize detachWindowSize;
@property (nonatomic, assign) NSSize activeSize;
@property (nonatomic, strong, nullable) NSImage *tabImage;
@property (nonatomic, strong, nullable) NSImage *detachContentImage;
@property (nonatomic, assign, readwrite) BrowserTabDragGhostStyle style;
@property (nonatomic, assign) BOOL animatingOut;
@property (nonatomic, assign) NSUInteger captureGeneration;
@end

@implementation BrowserTabDragGhostController

- (BOOL)visible {
    return self.panel != nil && self.panel.isVisible;
}

- (NSSize)ghostSize {
    return self.activeSize.width > 0 ? self.activeSize : self.tabSourceSize;
}

- (NSSize)normalizedDetachSize:(NSSize)windowSize {
    CGFloat width = MAX(windowSize.width, kDetachMinWindowWidth);
    CGFloat height = MAX(windowSize.height, kDetachMinWindowHeight);
    CGFloat longEdge = MAX(width, height);
    if (longEdge > kDetachMaxPreviewLongEdge) {
        CGFloat scale = kDetachMaxPreviewLongEdge / longEdge;
        width = floor(width * scale);
        height = floor(height * scale);
    }
    return NSMakeSize(width, height);
}

- (NSView *)makeTrafficLightDotWithColor:(NSColor *)color {
    NSView *dot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    dot.wantsLayer = YES;
    dot.layer.cornerRadius = 5.0;
    dot.layer.backgroundColor = color.CGColor;
    return dot;
}

- (void)ensureBrowserChromeSubviews {
    if (self.titlebarView) {
        return;
    }
    NSView *chrome = self.windowChromeView;
    if (!chrome) {
        return;
    }

    NSView *titlebar = [[NSView alloc] initWithFrame:NSZeroRect];
    titlebar.wantsLayer = YES;
    titlebar.hidden = YES;
    [chrome addSubview:titlebar positioned:NSWindowBelow relativeTo:self.imageView];

    NSView *lights = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 52, 12)];
    lights.wantsLayer = YES;
    NSArray<NSColor *> *colors = @[
        [NSColor colorWithCalibratedRed:1.0 green:0.38 blue:0.35 alpha:0.95],
        [NSColor colorWithCalibratedRed:1.0 green:0.74 blue:0.25 alpha:0.95],
        [NSColor colorWithCalibratedRed:0.30 green:0.78 blue:0.35 alpha:0.95],
    ];
    CGFloat x = 0;
    for (NSColor *color in colors) {
        NSView *dot = [self makeTrafficLightDotWithColor:color];
        NSRect frame = dot.frame;
        frame.origin = NSMakePoint(x, 1);
        dot.frame = frame;
        [lights addSubview:dot];
        x += 14.0;
    }
    lights.hidden = YES;
    [titlebar addSubview:lights];

    NSView *toolbar = [[NSView alloc] initWithFrame:NSZeroRect];
    toolbar.wantsLayer = YES;
    toolbar.hidden = YES;
    [chrome addSubview:toolbar positioned:NSWindowBelow relativeTo:self.imageView];

    // 内容图放在 chrome 最底层，标签叠在标题栏上。
    if (self.contentImageView) {
        [chrome addSubview:self.contentImageView positioned:NSWindowBelow relativeTo:toolbar];
    }

    self.titlebarView = titlebar;
    self.trafficLightsView = lights;
    self.toolbarView = toolbar;
}

- (void)beginWithSourceView:(NSView *)sourceView
          grabPointInSource:(NSPoint)grabPointInSource
               afterCapture:(void (^ _Nullable)(void))afterCapture {
    [self endAndRemoveImmediately];

    if (!sourceView || NSWidth(sourceView.bounds) < 1 || NSHeight(sourceView.bounds) < 1) {
        if (afterCapture) {
            afterCapture();
        }
        return;
    }

    self.grabPointInSource = grabPointInSource;
    self.activeGrabPoint = grabPointInSource;
    self.tabSourceSize = sourceView.bounds.size;
    self.activeSize = self.tabSourceSize;
    self.detachWindowSize = NSZeroSize;
    self.detachContentImage = nil;
    self.tabImage = nil;
    self.style = BrowserTabDragGhostStyleInStrip;
    self.animatingOut = NO;

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, self.tabSourceSize.width, self.tabSourceSize.height)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = NO;
    NSWindow *parentWindow = sourceView.window;
    NSInteger floating = (NSInteger)NSFloatingWindowLevel;
    NSInteger minLevel = parentWindow ? ((NSInteger)parentWindow.level + 1) : floating;
    panel.level = (NSWindowLevel)MAX(floating, minLevel);
    panel.ignoresMouseEvents = YES;
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSView *content = panel.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor clearColor].CGColor;

    NSView *chrome = [[NSView alloc] initWithFrame:content.bounds];
    chrome.wantsLayer = YES;
    chrome.layer.backgroundColor = [NSColor clearColor].CGColor;
    chrome.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:chrome];

    NSImageView *contentImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    contentImageView.imageScaling = NSImageScaleAxesIndependently;
    contentImageView.wantsLayer = YES;
    contentImageView.hidden = YES;
    [chrome addSubview:contentImageView];

    // 先挂廉价占位跟手；截图放到下一拍，避免 commit 边沿同步 cacheDisplay。
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:content.bounds];
    imageView.imageScaling = NSImageScaleAxesIndependently;
    imageView.wantsLayer = YES;
    imageView.alphaValue = kGhostInStripAlpha;
    imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    imageView.layer.cornerRadius = 6.0;
    imageView.layer.masksToBounds = YES;
    imageView.layer.backgroundColor = BrowserTabActiveFillColor().CGColor;
    imageView.layer.shadowColor = [NSColor blackColor].CGColor;
    imageView.layer.shadowOpacity = 0.25;
    imageView.layer.shadowRadius = 8.0;
    imageView.layer.shadowOffset = CGSizeMake(0, -2);
    [chrome addSubview:imageView];

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
    [chrome addSubview:badge];

    self.panel = panel;
    self.windowChromeView = chrome;
    self.imageView = imageView;
    self.contentImageView = contentImageView;
    self.badgeLabel = badge;
    [self ensureBrowserChromeSubviews];

    NSUInteger generation = ++self.captureGeneration;
    __weak typeof(self) weakSelf = self;
    __weak NSView *weakSource = sourceView;
    void (^finish)(void) = ^{
        if (afterCapture) {
            afterCapture();
        }
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        NSView *strongSource = weakSource;
        if (!strongSelf) {
            finish();
            return;
        }
        if (strongSelf.captureGeneration != generation || strongSelf.panel == nil) {
            return;
        }
        if (strongSource && NSWidth(strongSource.bounds) >= 1 && NSHeight(strongSource.bounds) >= 1
            && !strongSource.hidden) {
            NSBitmapImageRep *rep =
                [strongSource bitmapImageRepForCachingDisplayInRect:strongSource.bounds];
            if (rep) {
                [strongSource cacheDisplayInRect:strongSource.bounds toBitmapImageRep:rep];
                if (strongSelf.captureGeneration == generation && strongSelf.imageView != nil) {
                    NSImage *image = [[NSImage alloc] initWithSize:strongSource.bounds.size];
                    [image addRepresentation:rep];
                    strongSelf.tabImage = image;
                    strongSelf.imageView.image = image;
                    strongSelf.imageView.layer.backgroundColor = [NSColor clearColor].CGColor;
                    if (strongSelf.style != BrowserTabDragGhostStyleDetach) {
                        strongSelf.imageView.layer.masksToBounds = NO;
                    }
                }
            }
        }
        if (strongSelf.captureGeneration != generation) {
            return;
        }
        finish();
    });
}

- (void)prepareDetachPreviewWithWindowSize:(NSSize)windowSize
                              contentImage:(NSImage *)contentImage {
    self.detachWindowSize = [self normalizedDetachSize:windowSize];
    self.detachContentImage = contentImage;
    if (self.style == BrowserTabDragGhostStyleDetach) {
        [self applyDetachWindowLayoutAnimated:NO];
    }
}

- (void)updateDetachContentImage:(NSImage *)contentImage {
    self.detachContentImage = contentImage;
    if (self.style == BrowserTabDragGhostStyleDetach && self.contentImageView) {
        self.contentImageView.image = contentImage;
        self.contentImageView.hidden = NO;
        self.contentImageView.alphaValue = 1.0;
    }
}

- (NSPoint)detachGrabPointForWindowSize:(NSSize)windowSize {
    // 与 applyDetachWindowLayout 同一套标题栏几何，抓取点落在独立标签上。
    CGFloat titleH = kDetachTitlebarHeight;
    CGFloat toolbarH = kDetachToolbarHeight;
    if (windowSize.height < titleH + toolbarH + 80.0) {
        toolbarH = MAX(24.0, windowSize.height * 0.12);
        titleH = MAX(28.0, windowSize.height * 0.14);
    }
    CGFloat contentH = MAX(1.0, windowSize.height - titleH - toolbarH);
    CGFloat tabW = MIN(MAX(self.tabSourceSize.width, 96.0),
                       MAX(96.0, windowSize.width - kDetachTrafficLightInset - 72.0));
    CGFloat tabH = MIN(MAX(self.tabSourceSize.height, 24.0), MAX(24.0, titleH - 10.0));
    CGFloat tabX = kDetachTrafficLightInset;
    CGFloat tabY = contentH + toolbarH + MAX(4.0, (titleH - tabH) * 0.5);
    CGFloat grabX = tabX + MIN(MAX(self.grabPointInSource.x, 0.0), tabW);
    CGFloat grabY = tabY + MIN(MAX(self.grabPointInSource.y, 0.0), tabH);
    grabX = MIN(MAX(grabX, 8.0), MAX(8.0, windowSize.width - 8.0));
    grabY = MIN(MAX(grabY, contentH + toolbarH), MAX(0.0, windowSize.height - 4.0));
    return NSMakePoint(grabX, grabY);
}

- (void)layoutBadgeInBounds:(NSRect)bounds {
    if (!self.badgeLabel) {
        return;
    }
    [self.badgeLabel sizeToFit];
    NSRect badgeFrame = self.badgeLabel.frame;
    badgeFrame.size.width += 10.0;
    badgeFrame.size.height = MAX(NSHeight(badgeFrame), 16.0);
    badgeFrame.origin.x = NSWidth(bounds) - NSWidth(badgeFrame) - 8.0;
    badgeFrame.origin.y = NSHeight(bounds) - badgeFrame.size.height - 8.0;
    self.badgeLabel.frame = badgeFrame;
    self.badgeLabel.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
}

- (void)setBrowserChromeHidden:(BOOL)hidden {
    self.titlebarView.hidden = hidden;
    self.toolbarView.hidden = hidden;
    self.trafficLightsView.hidden = hidden;
}

- (void)applyTabOnlyLayout {
    NSSize size = self.tabSourceSize;
    self.activeSize = size;
    self.activeGrabPoint = self.grabPointInSource;

    if (self.panel) {
        self.panel.hasShadow = NO;
        NSRect frame = self.panel.frame;
        frame.size = size;
        [self.panel setFrame:frame display:NO];
        self.windowChromeView.frame = NSMakeRect(0, 0, size.width, size.height);
        self.windowChromeView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }

    self.windowChromeView.alphaValue = 1.0;
    self.windowChromeView.layer.backgroundColor = [NSColor clearColor].CGColor;
    self.windowChromeView.layer.cornerRadius = 0.0;
    self.windowChromeView.layer.masksToBounds = NO;
    self.windowChromeView.layer.borderWidth = 0.0;
    self.windowChromeView.layer.shadowOpacity = 0.0;

    [self setBrowserChromeHidden:YES];

    self.contentImageView.hidden = YES;
    self.contentImageView.alphaValue = 0.0;
    self.contentImageView.image = nil;
    self.contentImageView.frame = NSZeroRect;

    self.imageView.hidden = NO;
    self.imageView.alphaValue = (self.style == BrowserTabDragGhostStyleForeign)
        ? kGhostForeignAlpha
        : kGhostInStripAlpha;
    self.imageView.frame = NSMakeRect(0, 0, size.width, size.height);
    self.imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.imageView.layer.cornerRadius = 6.0;
    self.imageView.layer.masksToBounds = (self.tabImage == nil);
    self.imageView.layer.shadowOpacity = 0.25;
    self.imageView.layer.shadowRadius = 8.0;
    self.imageView.layer.shadowOffset = CGSizeMake(0, -2);
    self.imageView.layer.borderWidth = 0.0;
    if (self.tabImage) {
        self.imageView.image = self.tabImage;
        self.imageView.layer.backgroundColor = [NSColor clearColor].CGColor;
    } else {
        self.imageView.image = nil;
        self.imageView.layer.backgroundColor = BrowserTabActiveFillColor().CGColor;
    }
    [self.windowChromeView addSubview:self.imageView positioned:NSWindowAbove relativeTo:nil];
    if (self.badgeLabel) {
        [self.windowChromeView addSubview:self.badgeLabel positioned:NSWindowAbove relativeTo:self.imageView];
    }

    [self layoutBadgeInBounds:NSMakeRect(0, 0, size.width, size.height)];
}

- (void)applyDetachWindowLayoutAnimated:(BOOL)animated {
    NSSize windowSize = self.detachWindowSize;
    if (windowSize.width < 1 || windowSize.height < 1) {
        NSSize fallback = self.tabSourceSize;
        fallback.width = MAX(fallback.width * 4.0, kDetachMinWindowWidth);
        fallback.height = MAX(fallback.height * 12.0, kDetachMinWindowHeight);
        windowSize = [self normalizedDetachSize:fallback];
        self.detachWindowSize = windowSize;
    }

    [self ensureBrowserChromeSubviews];

    void (^apply)(void) = ^{
        self.activeSize = windowSize;
        self.activeGrabPoint = [self detachGrabPointForWindowSize:windowSize];

        // 必须先放大 panel/chrome，再摆子视图。
        // 若先按整窗 frame 摆子视图再放大父视图，HeightSizable 会把内容图拉满盖住外框。
        if (self.panel) {
            NSRect frame = self.panel.frame;
            frame.size = windowSize;
            [self.panel setFrame:frame display:NO];
            self.windowChromeView.frame = NSMakeRect(0, 0, windowSize.width, windowSize.height);
            self.windowChromeView.autoresizingMask = NSViewNotSizable;
        }

        NSColor *stripColor = BrowserTabStripFillColor();
        NSColor *chromeFill = [stripColor colorWithAlphaComponent:0.96];
        self.windowChromeView.alphaValue = 1.0;
        self.windowChromeView.layer.backgroundColor = chromeFill.CGColor;
        self.windowChromeView.layer.cornerRadius = kDetachCornerRadius;
        self.windowChromeView.layer.masksToBounds = YES; // 裁切圆角，外框轮廓清晰
        self.windowChromeView.layer.borderWidth = 1.5;
        self.windowChromeView.layer.borderColor =
            [[NSColor colorWithCalibratedWhite:0.35 alpha:0.55] CGColor];
        // masksToBounds=YES 时自带阴影会被裁；改由 panel 阴影表达「窗口感」。
        self.windowChromeView.layer.shadowOpacity = 0.0;
        if (self.panel) {
            self.panel.hasShadow = YES;
        }

        CGFloat titleH = kDetachTitlebarHeight;
        CGFloat toolbarH = kDetachToolbarHeight;
        if (windowSize.height < titleH + toolbarH + 80.0) {
            toolbarH = MAX(24.0, windowSize.height * 0.12);
            titleH = MAX(28.0, windowSize.height * 0.14);
        }
        CGFloat chromeTop = titleH + toolbarH;
        CGFloat contentH = MAX(1.0, windowSize.height - chromeTop);

        // ── 页面内容：只占标题栏+工具栏以下 ──
        self.contentImageView.autoresizingMask = NSViewNotSizable;
        self.contentImageView.frame = NSMakeRect(0, 0, windowSize.width, contentH);
        self.contentImageView.image = self.detachContentImage;
        self.contentImageView.hidden = NO;
        self.contentImageView.alphaValue = 0.95;
        self.contentImageView.wantsLayer = YES;
        self.contentImageView.layer.backgroundColor =
            [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.8].CGColor;
        self.contentImageView.layer.cornerRadius = 0.0;
        self.contentImageView.layer.masksToBounds = YES;
        [self.windowChromeView addSubview:self.contentImageView positioned:NSWindowBelow relativeTo:nil];

        // ── 标题栏（红绿灯 + 独立标签）──
        self.titlebarView.hidden = NO;
        self.titlebarView.autoresizingMask = NSViewNotSizable;
        self.titlebarView.frame = NSMakeRect(0, contentH + toolbarH, windowSize.width, titleH);
        self.titlebarView.layer.backgroundColor = [stripColor colorWithAlphaComponent:1.0].CGColor;
        self.titlebarView.layer.cornerRadius = 0.0;
        self.titlebarView.layer.masksToBounds = YES;
        [self.windowChromeView addSubview:self.titlebarView positioned:NSWindowAbove relativeTo:self.contentImageView];

        self.trafficLightsView.hidden = NO;
        CGFloat lightsH = NSHeight(self.trafficLightsView.bounds);
        CGFloat lightsY = MAX(0.0, (titleH - lightsH) * 0.5);
        self.trafficLightsView.frame = NSMakeRect(14.0, lightsY,
                                                  NSWidth(self.trafficLightsView.bounds),
                                                  lightsH);
        self.trafficLightsView.autoresizingMask = NSViewNotSizable;
        [self.titlebarView addSubview:self.trafficLightsView];

        // ── 工具栏 + 地址栏示意 ──
        self.toolbarView.hidden = NO;
        self.toolbarView.autoresizingMask = NSViewNotSizable;
        self.toolbarView.frame = NSMakeRect(0, contentH, windowSize.width, toolbarH);
        self.toolbarView.layer.backgroundColor =
            [[NSColor windowBackgroundColor] colorWithAlphaComponent:0.98].CGColor;
        [self.windowChromeView addSubview:self.toolbarView positioned:NSWindowAbove relativeTo:self.contentImageView];

        for (NSView *sub in [self.toolbarView.subviews copy]) {
            [sub removeFromSuperview];
        }
        // 底部分隔线
        NSView *toolbarHairline = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, windowSize.width, 1.0)];
        toolbarHairline.wantsLayer = YES;
        toolbarHairline.layer.backgroundColor =
            [[NSColor separatorColor] colorWithAlphaComponent:0.7].CGColor;
        toolbarHairline.autoresizingMask = NSViewNotSizable;
        [self.toolbarView addSubview:toolbarHairline];

        CGFloat barH = MAX(18.0, toolbarH - 12.0);
        NSView *addressBar = [[NSView alloc] initWithFrame:NSMakeRect(12.0,
                                                                      MAX(1.0, (toolbarH - barH) * 0.5),
                                                                      MAX(80.0, windowSize.width - 24.0),
                                                                      barH)];
        addressBar.wantsLayer = YES;
        addressBar.layer.cornerRadius = barH * 0.5;
        addressBar.layer.backgroundColor =
            [[NSColor colorWithCalibratedWhite:0.55 alpha:0.18] CGColor];
        addressBar.layer.borderWidth = 1.0;
        addressBar.layer.borderColor =
            [[NSColor separatorColor] colorWithAlphaComponent:0.5].CGColor;
        addressBar.autoresizingMask = NSViewNotSizable;
        [self.toolbarView addSubview:addressBar];

        // 后退/前进示意点，增强「这是浏览器工具栏」识别度
        for (NSInteger i = 0; i < 2; i++) {
            NSView *nav = [[NSView alloc] initWithFrame:NSMakeRect(18.0 + i * 18.0,
                                                                   MAX(2.0, (toolbarH - 10.0) * 0.5),
                                                                   10.0, 10.0)];
            nav.wantsLayer = YES;
            nav.layer.cornerRadius = 5.0;
            nav.layer.backgroundColor =
                [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.35].CGColor;
            [self.toolbarView addSubview:nav];
        }
        // 地址栏让出左侧导航占位
        NSRect ab = addressBar.frame;
        ab.origin.x = 56.0;
        ab.size.width = MAX(60.0, windowSize.width - 68.0);
        addressBar.frame = ab;

        // ── 独立标签（叠在标题栏上）──
        CGFloat tabW = MIN(MAX(self.tabSourceSize.width, 96.0),
                           MAX(96.0, windowSize.width - kDetachTrafficLightInset - 72.0));
        CGFloat tabH = MIN(MAX(self.tabSourceSize.height, 24.0), MAX(24.0, titleH - 10.0));
        CGFloat tabX = kDetachTrafficLightInset;
        CGFloat tabY = contentH + toolbarH + MAX(4.0, (titleH - tabH) * 0.5);
        self.imageView.hidden = NO;
        self.imageView.autoresizingMask = NSViewNotSizable;
        self.imageView.frame = NSMakeRect(tabX, tabY, tabW, tabH);
        self.imageView.alphaValue = kGhostDetachAlpha;
        self.imageView.layer.cornerRadius = 6.0;
        self.imageView.layer.masksToBounds = YES;
        self.imageView.layer.shadowOpacity = 0.0;
        self.imageView.layer.borderWidth = 0.0;
        if (self.tabImage) {
            self.imageView.image = self.tabImage;
            self.imageView.layer.backgroundColor = [NSColor clearColor].CGColor;
        } else {
            self.imageView.layer.backgroundColor = BrowserTabActiveFillColor().CGColor;
        }
        [self.windowChromeView addSubview:self.imageView positioned:NSWindowAbove relativeTo:self.titlebarView];

        self.badgeLabel.stringValue = @"新窗口";
        self.badgeLabel.alphaValue = 1.0;
        [self layoutBadgeInBounds:NSMakeRect(0, 0, windowSize.width, windowSize.height)];
        self.badgeLabel.hidden = NO;
        self.badgeLabel.autoresizingMask = NSViewNotSizable;
        [self.windowChromeView addSubview:self.badgeLabel positioned:NSWindowAbove relativeTo:self.imageView];

        [self.panel display];
    };

    // 展开时不做隐式动画，避免子视图 frame 被插值拉乱。
    (void)animated;
    apply();
}

- (void)moveToScreenPoint:(NSPoint)screenPoint {
    if (!self.panel || self.animatingOut) {
        return;
    }

    CGFloat scale = (self.style == BrowserTabDragGhostStyleDetach) ? kGhostDetachScale : 1.0;
    NSSize size = NSMakeSize(self.activeSize.width * scale, self.activeSize.height * scale);
    NSPoint origin = NSMakePoint(screenPoint.x - self.activeGrabPoint.x * scale,
                                 screenPoint.y - self.activeGrabPoint.y * scale);
    NSRect newFrame = NSMakeRect(origin.x, origin.y, size.width, size.height);
    // Detach 态只改 origin，避免 contentView 尺寸抖动把 NotSizable 子视图冲乱。
    if (self.style == BrowserTabDragGhostStyleDetach
        && fabs(NSWidth(self.panel.frame) - size.width) < 0.5
        && fabs(NSHeight(self.panel.frame) - size.height) < 0.5) {
        [self.panel setFrameOrigin:origin];
    } else {
        [self.panel setFrame:newFrame display:YES];
    }
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
    BrowserTabDragGhostStyle previous = self.style;
    self.style = style;
    if (!self.panel || !self.imageView) {
        return;
    }

    if (style == BrowserTabDragGhostStyleDetach) {
        [self applyDetachWindowLayoutAnimated:animated];
        return;
    }

    if (previous == BrowserTabDragGhostStyleDetach) {
        // 从整窗收回标签：结构重置不做隐式动画，避免尺寸/图层错位导致影子消失。
        void (^collapse)(void) = ^{
            [self applyTabOnlyLayout];
            if (style == BrowserTabDragGhostStyleForeign) {
                self.imageView.alphaValue = kGhostForeignAlpha;
                self.badgeLabel.stringValue = @"移到此窗口";
                self.badgeLabel.alphaValue = 1.0;
                [self layoutBadgeInBounds:NSMakeRect(0, 0, self.activeSize.width, self.activeSize.height)];
                self.badgeLabel.hidden = NO;
                self.imageView.layer.shadowOpacity = 0.3;
                self.imageView.layer.shadowRadius = 10.0;
                self.imageView.layer.borderWidth = 1.0;
                self.imageView.layer.borderColor =
                    [[NSColor controlAccentColor] colorWithAlphaComponent:0.45].CGColor;
            } else {
                self.badgeLabel.hidden = YES;
                self.badgeLabel.alphaValue = 1.0;
                self.imageView.layer.borderWidth = 0.0;
            }
            [self.panel display];
        };
        if (animated) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.12;
                context.allowsImplicitAnimation = NO;
                collapse();
            } completionHandler:nil];
        } else {
            collapse();
        }
        return;
    }

    void (^apply)(void) = ^{
        [self applyTabOnlyLayout];
        switch (style) {
            case BrowserTabDragGhostStyleForeign:
                self.imageView.alphaValue = kGhostForeignAlpha;
                self.badgeLabel.stringValue = @"移到此窗口";
                self.badgeLabel.alphaValue = 1.0;
                [self layoutBadgeInBounds:NSMakeRect(0, 0, self.activeSize.width, self.activeSize.height)];
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
        self.contentImageView.animator.alphaValue = 0.0;
        self.windowChromeView.animator.alphaValue = 0.0;
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
        self.contentImageView.animator.alphaValue = 0.0;
        self.badgeLabel.animator.alphaValue = 0.0;
        self.windowChromeView.animator.alphaValue = 0.0;
    } completionHandler:^{
        [self endAndRemoveImmediately];
        if (completion) {
            completion();
        }
    }];
}

- (void)endAndRemoveImmediately {
    self.captureGeneration += 1;
    self.animatingOut = NO;
    if (self.panel) {
        [self.panel orderOut:nil];
        self.panel = nil;
    }
    self.windowChromeView = nil;
    self.titlebarView = nil;
    self.toolbarView = nil;
    self.trafficLightsView = nil;
    self.imageView = nil;
    self.contentImageView = nil;
    self.badgeLabel = nil;
    self.tabImage = nil;
    self.detachContentImage = nil;
    self.detachWindowSize = NSZeroSize;
    self.activeSize = NSZeroSize;
    self.style = BrowserTabDragGhostStyleInStrip;
}

@end
