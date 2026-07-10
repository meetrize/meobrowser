#import "SBTextView.h"
#import "SBTextInputConfiguration.h"

@implementation SBTextView

+ (instancetype)standardTextView {
    SBTextView *textView = [[self alloc] initWithFrame:NSZeroRect];
    [SBTextInputConfiguration configureMultiLineTextView:textView];
    return textView;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [SBTextInputConfiguration configureMultiLineTextView:self];
    }
    return self;
}

@end
