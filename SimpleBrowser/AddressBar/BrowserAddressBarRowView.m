#import "BrowserAddressBarRowView.h"
#import "BrowserAddressBarActionGroup.h"
#import "SBTextField.h"

static const CGFloat kResizeHandleWidth = 10.0;
static const CGFloat kSecurityBadgeSpacing = 6.0;

/// 画在地址栏「下面」的半圆胶囊描边（不依赖 NSTextField 自己的 bezel 绘制）。
@interface BrowserAddressBarCapsuleChromeView : NSView
@end

@implementation BrowserAddressBarCapsuleChromeView

- (BOOL)isOpaque {
    return NO;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect fillRect = self.bounds;
    CGFloat radius = NSHeight(fillRect) * 0.5;
    if (radius < 0.5) {
        return;
    }
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:fillRect
                                                         xRadius:radius
                                                         yRadius:radius];
    NSAppearance *appearance = self.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
    [appearance performAsCurrentDrawingAppearance:^{
        NSAppearanceName match =
            [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
        NSColor *fill = ([match isEqualToString:NSAppearanceNameDarkAqua]
                             ? [NSColor colorWithWhite:1.0 alpha:0.10]
                             : [NSColor colorWithWhite:0.0 alpha:0.06]);
        [fill setFill];
        [path fill];
    }];
}

@end

@interface BrowserAddressBarRowView ()
@property (nonatomic, strong, nullable) NSLayoutConstraint *securityBadgeWidthConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *securityBadgeSpacingConstraint;
@property (nonatomic, assign) CGFloat securityBadgeIntrinsicWidth;
@property (nonatomic, strong, nullable) BrowserAddressBarCapsuleChromeView *capsuleChrome;
@end

@implementation BrowserAddressBarRowView

- (instancetype)initWithAddressField:(SBTextField *)addressField
                       securityBadge:(NSView *)securityBadge
                         actionGroup:(BrowserAddressBarActionGroup *)actionGroup {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _addressField = addressField;
        _securityBadge = securityBadge;
        _actionGroup = actionGroup;

        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

        if (actionGroup) {
            actionGroup.layoutContainer = self;
        }

        if (securityBadge) {
            [self addSubview:securityBadge];
            securityBadge.hidden = YES;
            self.securityBadgeIntrinsicWidth = 0;
            self.securityBadgeWidthConstraint =
                [securityBadge.widthAnchor constraintEqualToConstant:0];
            self.securityBadgeSpacingConstraint =
                [addressField.leadingAnchor constraintEqualToAnchor:securityBadge.trailingAnchor
                                                           constant:0];
        }

        if (addressField.usesCapsuleBezel) {
            BrowserAddressBarCapsuleChromeView *chrome = [[BrowserAddressBarCapsuleChromeView alloc] initWithFrame:NSZeroRect];
            chrome.translatesAutoresizingMaskIntoConstraints = NO;
            self.capsuleChrome = chrome;
            [self addSubview:chrome];
            addressField.bezeled = NO;
            addressField.bordered = NO;
            addressField.drawsBackground = NO;
            addressField.wantsLayer = NO;
            addressField.focusRingType = NSFocusRingTypeNone;
            addressField.cell.focusRingType = NSFocusRingTypeNone;
        }

        [self addSubview:addressField];
        if (self.capsuleChrome) {
            [self addSubview:self.capsuleChrome positioned:NSWindowBelow relativeTo:addressField];
        }

        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
        if (securityBadge) {
            [constraints addObjectsFromArray:@[
                [securityBadge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [securityBadge.centerYAnchor constraintEqualToAnchor:addressField.centerYAnchor],
                [securityBadge.heightAnchor constraintEqualToConstant:18],
                self.securityBadgeWidthConstraint,
                self.securityBadgeSpacingConstraint,
            ]];
        } else {
            [constraints addObject:[addressField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor]];
        }

        [constraints addObjectsFromArray:@[
            [addressField.topAnchor constraintEqualToAnchor:self.topAnchor],
            [addressField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        if (actionGroup) {
            [self addSubview:actionGroup];
            BrowserAddressBarEdgeResizeView *resizeHandle = [[BrowserAddressBarEdgeResizeView alloc] initWithFrame:NSZeroRect];
            resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:resizeHandle positioned:NSWindowAbove relativeTo:actionGroup];

            [constraints addObjectsFromArray:@[
                [addressField.trailingAnchor constraintEqualToAnchor:actionGroup.leadingAnchor],
                [actionGroup.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [actionGroup.topAnchor constraintEqualToAnchor:self.topAnchor],
                [actionGroup.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [resizeHandle.trailingAnchor constraintEqualToAnchor:actionGroup.leadingAnchor],
                [resizeHandle.topAnchor constraintEqualToAnchor:self.topAnchor],
                [resizeHandle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [resizeHandle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],
            ]];

            __weak BrowserAddressBarActionGroup *weakActionGroup = actionGroup;
            resizeHandle.onDragBegan = ^{
                [weakActionGroup beginWidthResize];
            };
            resizeHandle.onDrag = ^(CGFloat deltaX) {
                [weakActionGroup applyWidthDelta:-deltaX];
            };
            resizeHandle.onDragEnded = ^{
                [weakActionGroup endWidthResize];
            };
        } else {
            [constraints addObject:[addressField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]];
        }

        if (self.capsuleChrome) {
            BrowserAddressBarCapsuleChromeView *chrome = self.capsuleChrome;
            [constraints addObjectsFromArray:@[
                [chrome.leadingAnchor constraintEqualToAnchor:addressField.leadingAnchor],
                [chrome.trailingAnchor constraintEqualToAnchor:addressField.trailingAnchor],
                [chrome.topAnchor constraintEqualToAnchor:addressField.topAnchor],
                [chrome.bottomAnchor constraintEqualToAnchor:addressField.bottomAnchor],
            ]];
        }

        [NSLayoutConstraint activateConstraints:constraints];
    }
    return self;
}

- (void)setSecurityBadgeVisible:(BOOL)visible preferredWidth:(CGFloat)preferredWidth {
    if (!self.securityBadge) {
        return;
    }
    CGFloat width = MAX(0, ceil(preferredWidth));
    self.securityBadgeIntrinsicWidth = width;
    self.securityBadge.hidden = !visible;
    self.securityBadgeWidthConstraint.constant = visible ? width : 0;
    self.securityBadgeSpacingConstraint.constant = visible ? kSecurityBadgeSpacing : 0;
    [self setNeedsLayout:YES];
}

@end
