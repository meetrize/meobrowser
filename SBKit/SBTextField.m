#import "SBTextField.h"
#import "SBTextInputConfiguration.h"

@interface SBStandardTextFieldCell : NSTextFieldCell
@end

@implementation SBStandardTextFieldCell

- (NSRect)textAreaRectForBounds:(NSRect)theRect {
    NSRect area = theRect;
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBTextField class]]) {
        CGFloat inset = ((SBTextField *)controlView).trailingContentInset;
        if (inset > 0) {
            area.size.width = MAX(0, NSWidth(area) - inset);
        }
    }
    return area;
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    return [super drawingRectForBounds:[self textAreaRectForBounds:theRect]];
}

- (NSRect)titleRectForBounds:(NSRect)theRect {
    return [super titleRectForBounds:[self textAreaRectForBounds:theRect]];
}

@end

@implementation SBTextField

+ (Class)cellClass {
    return [SBStandardTextFieldCell class];
}

+ (instancetype)standardField {
    SBTextField *field = [[self alloc] initWithFrame:NSZeroRect];
    [SBTextInputConfiguration configureSingleLineTextField:field];
    return field;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [SBTextInputConfiguration configureSingleLineTextField:self];
    }
    return self;
}

@end
