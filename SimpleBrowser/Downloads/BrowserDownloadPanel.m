#import "BrowserDownloadPanel.h"
#import "BrowserDownloadManager.h"
#import "BrowserDownloadItem.h"

static const CGFloat kRowHeight = 52.0;
static const CGFloat kPanelWidth = 360.0;
static const CGFloat kPanelCornerRadius = 8.0;
static const CGFloat kMaxVisibleRows = 6.0;
static const CGFloat kHeaderHeight = 36.0;

@interface BrowserDownloadFlippedView : NSView
@end

@implementation BrowserDownloadFlippedView
- (BOOL)isFlipped { return YES; }
@end

@class BrowserDownloadRowView;

@interface BrowserDownloadPanel (RowActions)
- (void)rowDidClickReveal:(BrowserDownloadRowView *)row;
- (void)rowDidClickOpen:(BrowserDownloadRowView *)row;
- (void)rowDidClickCancel:(BrowserDownloadRowView *)row;
- (void)rowDidClickRemove:(BrowserDownloadRowView *)row;
@end

@interface BrowserDownloadRowView : NSView <NSDraggingSource>
@property (nonatomic, strong) BrowserDownloadItem *item;
@property (nonatomic, weak) BrowserDownloadPanel *panel;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSButton *primaryButton;
@property (nonatomic, strong) NSButton *secondaryButton;
@property (nonatomic, assign) NSPoint dragStart;
@property (nonatomic, assign) BOOL didStartDrag;
@end

@implementation BrowserDownloadRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _titleLabel = [self makeLabelWithFont:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
                                         color:[NSColor labelColor]];
        _subtitleLabel = [self makeLabelWithFont:[NSFont systemFontOfSize:11]
                                            color:[NSColor secondaryLabelColor]];

        _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _progressBar.style = NSProgressIndicatorStyleBar;
        _progressBar.indeterminate = NO;
        _progressBar.minValue = 0;
        _progressBar.maxValue = 1;
        _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_progressBar setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

        _primaryButton = [self makeTinyButton];
        _secondaryButton = [self makeTinyButton];

        [self addSubview:_titleLabel];
        [self addSubview:_subtitleLabel];
        [self addSubview:_progressBar];
        [self addSubview:_primaryButton];
        [self addSubview:_secondaryButton];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_primaryButton.leadingAnchor constant:-8],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_primaryButton.leadingAnchor constant:-8],

            [_progressBar.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_progressBar.trailingAnchor constraintEqualToAnchor:_primaryButton.leadingAnchor constant:-10],
            [_progressBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
            [_progressBar.heightAnchor constraintEqualToConstant:4],

            [_secondaryButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_secondaryButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_secondaryButton.widthAnchor constraintEqualToConstant:28],
            [_secondaryButton.heightAnchor constraintEqualToConstant:28],

            [_primaryButton.trailingAnchor constraintEqualToAnchor:_secondaryButton.leadingAnchor constant:-2],
            [_primaryButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_primaryButton.widthAnchor constraintEqualToConstant:28],
            [_primaryButton.heightAnchor constraintEqualToConstant:28],
        ]];
    }
    return self;
}

- (NSTextField *)makeLabelWithFont:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSButton *)makeTinyButton {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = [NSColor secondaryLabelColor];
    }
    return button;
}

- (NSImage *)symbolNamed:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:12
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return [image imageWithSymbolConfiguration:config];
    }
    return nil;
}

- (void)configureWithItem:(BrowserDownloadItem *)item {
    self.item = item;
    self.titleLabel.stringValue = item.filename ?: @"下载";
    NSMutableString *subtitle = [[NSMutableString alloc] init];
    if (item.sourceHost.length > 0) {
        [subtitle appendString:item.sourceHost];
        [subtitle appendString:@" · "];
    }
    [subtitle appendString:item.statusDescription ?: @""];
    self.subtitleLabel.stringValue = subtitle;

    BOOL active = (item.state == BrowserDownloadStatePending || item.state == BrowserDownloadStateDownloading);
    self.progressBar.hidden = !active;
    if (active) {
        if (item.hasKnownTotalUnitCount) {
            self.progressBar.indeterminate = NO;
            self.progressBar.doubleValue = item.progress;
        } else {
            self.progressBar.indeterminate = YES;
            [self.progressBar startAnimation:nil];
        }
    } else {
        [self.progressBar stopAnimation:nil];
    }

    self.primaryButton.target = self;
    self.secondaryButton.target = self;
    self.secondaryButton.hidden = NO;

    if (active) {
        self.primaryButton.hidden = YES;
        self.secondaryButton.image = [self symbolNamed:@"xmark.circle"];
        self.secondaryButton.toolTip = @"取消";
        self.secondaryButton.action = @selector(cancelClicked:);
    } else if (item.state == BrowserDownloadStateCompleted && item.destinationURL) {
        self.primaryButton.hidden = NO;
        self.primaryButton.image = [self symbolNamed:@"folder"];
        self.primaryButton.toolTip = @"在 Finder 中显示";
        self.primaryButton.action = @selector(revealClicked:);
        self.secondaryButton.image = [self symbolNamed:@"arrow.up.right.square"];
        self.secondaryButton.toolTip = @"打开";
        self.secondaryButton.action = @selector(openClicked:);
    } else {
        self.primaryButton.hidden = YES;
        self.secondaryButton.image = [self symbolNamed:@"trash"];
        self.secondaryButton.toolTip = @"清除";
        self.secondaryButton.action = @selector(removeClicked:);
    }

    self.toolTip = item.destinationURL.path ?: item.sourceURL.absoluteString;
}

- (void)revealClicked:(id)sender {
    (void)sender;
    [self.panel rowDidClickReveal:self];
}

- (void)openClicked:(id)sender {
    (void)sender;
    [self.panel rowDidClickOpen:self];
}

- (void)cancelClicked:(id)sender {
    (void)sender;
    [self.panel rowDidClickCancel:self];
}

- (void)removeClicked:(id)sender {
    (void)sender;
    [self.panel rowDidClickRemove:self];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragStart = event.locationInWindow;
    self.didStartDrag = NO;
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.item.state != BrowserDownloadStateCompleted || !self.item.destinationURL) {
        [super mouseDragged:event];
        return;
    }
    if (self.didStartDrag) {
        return;
    }
    NSPoint loc = event.locationInWindow;
    CGFloat dx = loc.x - self.dragStart.x;
    CGFloat dy = loc.y - self.dragStart.y;
    if ((dx * dx + dy * dy) < 16.0) {
        return;
    }
    self.didStartDrag = YES;
    NSURL *fileURL = self.item.destinationURL;
    NSDraggingItem *draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:fileURL];
    [draggingItem setDraggingFrame:self.bounds contents:nil];
    [self beginDraggingSessionWithItems:@[draggingItem] event:event source:self];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session;
    (void)context;
    return NSDragOperationCopy;
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.didStartDrag &&
        self.item.state == BrowserDownloadStateCompleted &&
        self.item.destinationURL &&
        event.clickCount == 1) {
        [self.panel rowDidClickReveal:self];
    } else if (!self.didStartDrag &&
               self.item.state == BrowserDownloadStateCompleted &&
               self.item.destinationURL &&
               event.clickCount == 2) {
        [self.panel rowDidClickOpen:self];
    }
    [super mouseUp:event];
}

@end

@interface BrowserDownloadPanel () <NSWindowDelegate>
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *rowsContainer;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSMutableArray<BrowserDownloadRowView *> *rowViews;
@property (nonatomic, strong, nullable) id localMouseMonitor;
@property (nonatomic, strong, nullable) id localKeyMonitor;
@end

@implementation BrowserDownloadPanel

- (instancetype)init {
    self = [super initWithContentRect:NSZeroRect
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.hasShadow = YES;
        self.opaque = NO;
        self.backgroundColor = NSColor.clearColor;
        self.level = NSPopUpMenuWindowLevel;
        self.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary;
        if (@available(macOS 10.14, *)) {
            self.appearance = NSApp.effectiveAppearance;
        }
        if (@available(macOS 10.12, *)) {
            self.hidesOnDeactivate = NO;
        }

        _rowViews = [[NSMutableArray alloc] init];

        _effectView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
        _effectView.material = NSVisualEffectMaterialPopover;
        _effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _effectView.state = NSVisualEffectStateActive;
        _effectView.wantsLayer = YES;
        _effectView.layer.cornerRadius = kPanelCornerRadius;
        _effectView.layer.masksToBounds = YES;
        _effectView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _titleLabel.editable = NO;
        _titleLabel.selectable = NO;
        _titleLabel.bezeled = NO;
        _titleLabel.drawsBackground = NO;
        _titleLabel.stringValue = @"下载";
        _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        _titleLabel.textColor = [NSColor labelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _clearButton = [NSButton buttonWithTitle:@"清空已完成" target:self action:@selector(clearFinished:)];
        _clearButton.bezelStyle = NSBezelStyleInline;
        _clearButton.bordered = NO;
        _clearButton.font = [NSFont systemFontOfSize:11];
        if (@available(macOS 10.14, *)) {
            _clearButton.contentTintColor = [NSColor secondaryLabelColor];
        }
        _clearButton.translatesAutoresizingMaskIntoConstraints = NO;

        _emptyLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _emptyLabel.editable = NO;
        _emptyLabel.selectable = NO;
        _emptyLabel.bezeled = NO;
        _emptyLabel.drawsBackground = NO;
        _emptyLabel.stringValue = @"暂无下载";
        _emptyLabel.alignment = NSTextAlignmentCenter;
        _emptyLabel.font = [NSFont systemFontOfSize:12];
        _emptyLabel.textColor = [NSColor secondaryLabelColor];
        _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _rowsContainer = [[BrowserDownloadFlippedView alloc] initWithFrame:NSZeroRect];
        _rowsContainer.translatesAutoresizingMaskIntoConstraints = NO;

        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.drawsBackground = NO;
        _scrollView.borderType = NSNoBorder;
        _scrollView.documentView = _rowsContainer;
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;

        NSView *contentView = [[NSView alloc] initWithFrame:NSZeroRect];
        self.contentView = contentView;
        [contentView addSubview:_effectView];
        [_effectView addSubview:_titleLabel];
        [_effectView addSubview:_clearButton];
        [_effectView addSubview:_scrollView];
        [_effectView addSubview:_emptyLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_effectView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [_effectView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [_effectView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [_effectView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_effectView.leadingAnchor constant:12],
            [_titleLabel.topAnchor constraintEqualToAnchor:_effectView.topAnchor constant:10],

            [_clearButton.trailingAnchor constraintEqualToAnchor:_effectView.trailingAnchor constant:-10],
            [_clearButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],

            [_scrollView.topAnchor constraintEqualToAnchor:_effectView.topAnchor constant:kHeaderHeight],
            [_scrollView.leadingAnchor constraintEqualToAnchor:_effectView.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:_effectView.trailingAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:_effectView.bottomAnchor constant:-4],

            [_emptyLabel.centerXAnchor constraintEqualToAnchor:_effectView.centerXAnchor],
            [_emptyLabel.centerYAnchor constraintEqualToAnchor:_scrollView.centerYAnchor],
        ]];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (void)presentAnchoredToRect:(NSRect)anchorRectOnScreen {
    [self reloadFromManager];

    CGFloat contentHeight = MAX((CGFloat)self.manager.items.count, 1.0) * kRowHeight;
    CGFloat visibleHeight = MIN(contentHeight, kMaxVisibleRows * kRowHeight);
    CGFloat panelHeight = visibleHeight + kHeaderHeight + 8.0;

    // 与地址栏右侧按钮组对齐：面板右缘对齐锚点右缘
    NSRect panelFrame = NSMakeRect(NSMaxX(anchorRectOnScreen) - kPanelWidth,
                                   anchorRectOnScreen.origin.y - panelHeight - 4.0,
                                   kPanelWidth,
                                   panelHeight);
    // 夹在屏幕可见区内
    NSScreen *screen = NSScreen.mainScreen;
    if (screen) {
        NSRect visible = screen.visibleFrame;
        if (NSMinX(panelFrame) < NSMinX(visible)) {
            panelFrame.origin.x = NSMinX(visible) + 4;
        }
        if (NSMaxX(panelFrame) > NSMaxX(visible)) {
            panelFrame.origin.x = NSMaxX(visible) - kPanelWidth - 4;
        }
        if (NSMinY(panelFrame) < NSMinY(visible)) {
            panelFrame.origin.y = NSMinY(visible) + 4;
        }
    }

    [self setFrame:panelFrame display:YES];
    [self orderFrontRegardless];
    [self installDismissalMonitors];
}

- (void)dismissPanel {
    [self removeDismissalMonitors];
    [self orderOut:nil];
    [self.panelDelegate downloadPanelDidRequestClose:self];
}

- (void)reloadFromManager {
    for (NSView *row in self.rowViews) {
        [row removeFromSuperview];
    }
    [self.rowViews removeAllObjects];

    NSArray<BrowserDownloadItem *> *items = self.manager.items ?: @[];
    BOOL empty = items.count == 0;
    self.emptyLabel.hidden = !empty;
    self.clearButton.enabled = !empty;
    self.scrollView.hidden = empty;

    CGFloat width = kPanelWidth;
    CGFloat contentHeight = MAX((CGFloat)items.count, 1.0) * kRowHeight;
    self.rowsContainer.frame = NSMakeRect(0, 0, width, contentHeight);

    for (NSUInteger i = 0; i < items.count; i++) {
        NSRect rowFrame = NSMakeRect(0, i * kRowHeight, width, kRowHeight);
        BrowserDownloadRowView *row = [[BrowserDownloadRowView alloc] initWithFrame:rowFrame];
        row.panel = self;
        [row configureWithItem:items[i]];
        [self.rowsContainer addSubview:row];
        [self.rowViews addObject:row];
    }

    if (self.isVisible) {
        CGFloat visibleHeight = MIN(MAX((CGFloat)items.count, 1.0) * kRowHeight, kMaxVisibleRows * kRowHeight);
        CGFloat panelHeight = visibleHeight + kHeaderHeight + 8.0;
        NSRect frame = self.frame;
        CGFloat bottom = NSMaxY(frame);
        frame.size.height = panelHeight;
        frame.origin.y = bottom - panelHeight;
        [self setFrame:frame display:YES];
    }
}

- (void)clearFinished:(id)sender {
    (void)sender;
    [self.manager clearFinishedItems];
}

- (void)rowDidClickReveal:(BrowserDownloadRowView *)row {
    [self.manager revealItemInFinder:row.item];
}

- (void)rowDidClickOpen:(BrowserDownloadRowView *)row {
    [self.manager openItem:row.item];
}

- (void)rowDidClickCancel:(BrowserDownloadRowView *)row {
    [self.manager cancelItem:row.item];
}

- (void)rowDidClickRemove:(BrowserDownloadRowView *)row {
    [self.manager removeItem:row.item];
}

#pragma mark - Dismissal monitors

- (void)installDismissalMonitors {
    [self removeDismissalMonitors];
    __weak typeof(self) weakSelf = self;
    self.localMouseMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                              handler:^NSEvent *(NSEvent *event) {
            BrowserDownloadPanel *panel = weakSelf;
            if (!panel || !panel.isVisible) {
                return event;
            }
            NSWindow *eventWindow = event.window;
            if (eventWindow == panel) {
                return event;
            }
            // 点击下载按钮本身由外部 toggle，这里只处理点在浏览器窗口其他区域
            NSPoint screenPoint = [eventWindow convertPointToScreen:event.locationInWindow];
            if (NSPointInRect(screenPoint, panel.dismissExclusionRectOnScreen)) {
                return event;
            }
            if (!NSPointInRect(screenPoint, panel.frame)) {
                [panel dismissPanel];
            }
            return event;
        }];
    self.localKeyMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                              handler:^NSEvent *(NSEvent *event) {
            if (event.keyCode == 53) { // Esc
                [weakSelf dismissPanel];
                return nil;
            }
            return event;
        }];
}

- (void)removeDismissalMonitors {
    if (self.localMouseMonitor) {
        [NSEvent removeMonitor:self.localMouseMonitor];
        self.localMouseMonitor = nil;
    }
    if (self.localKeyMonitor) {
        [NSEvent removeMonitor:self.localKeyMonitor];
        self.localKeyMonitor = nil;
    }
}

- (void)dealloc {
    [self removeDismissalMonitors];
}

@end
