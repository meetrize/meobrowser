#import "SBTextInputConfiguration.h"

@implementation SBTextInputConfiguration

+ (void)configureSingleLineTextField:(NSTextField *)textField {
    textField.editable = YES;
    textField.selectable = YES;
    textField.bezelStyle = NSTextFieldSquareBezel;
    textField.focusRingType = NSFocusRingTypeDefault;
    textField.font = [NSFont systemFontOfSize:13];
    textField.cell.wraps = NO;
    textField.cell.scrollable = YES;
}

+ (void)configureSecureTextField:(NSSecureTextField *)textField {
    [self configureSingleLineTextField:textField];
}

+ (void)configureMultiLineTextView:(NSTextView *)textView {
    textView.editable = YES;
    textView.selectable = YES;
    textView.allowsUndo = YES;
    textView.font = [NSFont systemFontOfSize:13];
    textView.textContainerInset = NSMakeSize(4, 4);
    textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

@end
