#import "SBSecureTextField.h"
#import "SBTextInputConfiguration.h"

@implementation SBSecureTextField

+ (instancetype)standardField {
    SBSecureTextField *field = [[self alloc] initWithFrame:NSZeroRect];
    [SBTextInputConfiguration configureSecureTextField:field];
    return field;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [SBTextInputConfiguration configureSecureTextField:self];
    }
    return self;
}

@end
