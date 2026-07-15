#import "BrowserAddressBarRowView.h"
#import "BrowserAddressBarActionGroup.h"
#import "SBTextField.h"

static const CGFloat kResizeHandleWidth = 10.0;
static const CGFloat kSecurityBadgeSpacing = 6.0;

@interface BrowserAddressBarRowView ()
@property (nonatomic, strong, nullable) NSLayoutConstraint *securityBadgeWidthConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *securityBadgeSpacingConstraint;
@property (nonatomic, assign) CGFloat securityBadgeIntrinsicWidth;
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

        actionGroup.layoutContainer = self;

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

        [self addSubview:addressField];
        [self addSubview:actionGroup];

        BrowserAddressBarEdgeResizeView *resizeHandle = [[BrowserAddressBarEdgeResizeView alloc] initWithFrame:NSZeroRect];
        resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:resizeHandle positioned:NSWindowAbove relativeTo:actionGroup];

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
            [addressField.trailingAnchor constraintEqualToAnchor:actionGroup.leadingAnchor],

            [actionGroup.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [actionGroup.topAnchor constraintEqualToAnchor:self.topAnchor],
            [actionGroup.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [resizeHandle.trailingAnchor constraintEqualToAnchor:actionGroup.leadingAnchor],
            [resizeHandle.topAnchor constraintEqualToAnchor:self.topAnchor],
            [resizeHandle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [resizeHandle.widthAnchor constraintEqualToConstant:kResizeHandleWidth],
        ]];
        [NSLayoutConstraint activateConstraints:constraints];

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
