#import "BrowserSelectionTranslationPresenter.h"

@interface BrowserSelectionTranslationPresenter () <NSPopoverDelegate>
@property (nonatomic, strong, nullable) NSPopover *popover;
@property (nonatomic, strong, nullable) NSViewController *contentController;
@property (nonatomic, strong, nullable) NSTextField *resultLabel;
@property (nonatomic, copy, nullable) NSString *lastTranslated;
@end

@implementation BrowserSelectionTranslationPresenter

+ (instancetype)sharedPresenter {
    static BrowserSelectionTranslationPresenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (void)dismiss {
    if (self.popover.isShown) {
        [self.popover performClose:nil];
    }
    self.popover = nil;
    self.contentController = nil;
    self.resultLabel = nil;
}

- (void)showTranslatedText:(NSString *)translated
              originalText:(NSString *)original
                  relativeTo:(NSView *)view {
    (void)original;
    if (translated.length == 0 || view == nil || view.window == nil) {
        return;
    }
    self.lastTranslated = [translated copy];

    NSWindow *host = view.window;
    NSScreen *screen = host.screen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;

    const CGFloat padX = 12.0;
    const CGFloat padY = 10.0;
    const CGFloat maxContentWidth = MIN(420.0, MAX(200.0, NSWidth(visible) * 0.42));
    const CGFloat maxContentHeight = MAX(60.0, NSHeight(visible) * 0.55);

    NSFont *font = [NSFont systemFontOfSize:13];
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    NSAttributedString *attr =
        [[NSAttributedString alloc] initWithString:translated attributes:attrs];

    NSSize natural = [attr boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                        options:(NSStringDrawingUsesLineFragmentOrigin |
                                                 NSStringDrawingUsesFontLeading)].size;
    CGFloat contentWidth = MIN(maxContentWidth, MAX(120.0, ceil(natural.width) + 2.0));
    NSSize wrapped = [attr boundingRectWithSize:NSMakeSize(contentWidth, CGFLOAT_MAX)
                                        options:(NSStringDrawingUsesLineFragmentOrigin |
                                                 NSStringDrawingUsesFontLeading)].size;
    CGFloat contentHeight = MIN(maxContentHeight, ceil(wrapped.height) + 2.0);
    if (contentHeight >= maxContentHeight - 1.0 && contentWidth < maxContentWidth) {
        contentWidth = maxContentWidth;
        wrapped = [attr boundingRectWithSize:NSMakeSize(contentWidth, CGFLOAT_MAX)
                                     options:(NSStringDrawingUsesLineFragmentOrigin |
                                              NSStringDrawingUsesFontLeading)].size;
        contentHeight = MIN(maxContentHeight, ceil(wrapped.height) + 2.0);
    }

    NSSize popoverSize = NSMakeSize(contentWidth + padX * 2.0,
                                    contentHeight + padY * 2.0);

    if (self.popover == nil) {
        [self buildPopover];
    }

    self.resultLabel.font = font;
    self.resultLabel.stringValue = translated;
    self.resultLabel.preferredMaxLayoutWidth = contentWidth;
    self.contentController.preferredContentSize = popoverSize;

    // 锚定到指针附近（相对 webView 左上区域），更像 tooltip。
    NSPoint mouse = [host mouseLocationOutsideOfEventStream];
    NSPoint inView = [view convertPoint:mouse fromView:nil];
    CGFloat anchorW = 2.0;
    NSRect anchor = NSMakeRect(inView.x - anchorW * 0.5, inView.y - anchorW * 0.5, anchorW, anchorW);
    // 若坐标异常，退回视图中上部。
    if (!NSPointInRect(inView, view.bounds)) {
        anchor = NSMakeRect(NSMidX(view.bounds) - 1.0, NSMaxY(view.bounds) - 48.0, 2.0, 2.0);
    }

    if (self.popover.isShown) {
        [self.popover close];
    }
    [self.popover showRelativeToRect:anchor ofView:view preferredEdge:NSRectEdgeMaxY];
}

- (void)buildPopover {
    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.font = [NSFont systemFontOfSize:13];
    label.textColor = [NSColor labelColor];
    label.selectable = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.resultLabel = label;

    [root addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:root.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-10],
        [label.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:12],
        [label.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
    ]];

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = root;
    self.contentController = vc;

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = vc;
    popover.behavior = NSPopoverBehaviorTransient; // 点外部关闭
    popover.animates = YES;
    popover.delegate = self;
    self.popover = popover;
}

- (void)popoverDidClose:(NSNotification *)notification {
    (void)notification;
    self.popover = nil;
    self.contentController = nil;
    self.resultLabel = nil;
}

@end
