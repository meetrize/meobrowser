#import "BrowserAddressBarRowView.h"
#import "BrowserAddressBarActionGroup.h"
#import "SBTextField.h"

static const CGFloat kResizeHandleWidth = 10.0;

@implementation BrowserAddressBarRowView

- (instancetype)initWithAddressField:(SBTextField *)addressField
                         actionGroup:(BrowserAddressBarActionGroup *)actionGroup {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _addressField = addressField;
        _actionGroup = actionGroup;

        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

        actionGroup.layoutContainer = self;

        [self addSubview:addressField];
        [self addSubview:actionGroup];

        BrowserAddressBarEdgeResizeView *resizeHandle = [[BrowserAddressBarEdgeResizeView alloc] initWithFrame:NSZeroRect];
        resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:resizeHandle positioned:NSWindowAbove relativeTo:actionGroup];

        [NSLayoutConstraint activateConstraints:@[
            [addressField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
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

@end
