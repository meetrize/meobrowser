#import "SBTextField.h"
#import "SBTextInputConfiguration.h"

@interface SBStandardTextFieldCell : NSTextFieldCell
@end

static BOOL SBTextFieldIsActivelyEditing(SBTextField *field) {
    if (![field isKindOfClass:[SBTextField class]]) {
        return NO;
    }
    NSText *editor = field.currentEditor;
    if (!editor) {
        return NO;
    }
    id firstResponder = field.window.firstResponder;
    return firstResponder == editor || firstResponder == field;
}

static void SBTextFieldSelectAllText(SBTextField *field) {
    if (field.stringValue.length == 0) {
        return;
    }
    NSText *editor = field.currentEditor;
    if (editor) {
        [editor setSelectedRange:NSMakeRange(0, field.stringValue.length)];
        return;
    }
    [field selectText:nil];
    editor = field.currentEditor;
    if (editor) {
        [editor setSelectedRange:NSMakeRange(0, field.stringValue.length)];
    }
}

static void SBTextFieldConsumeMouseUpEvents(void) {
    while (YES) {
        NSEvent *next = [NSApp nextEventMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged)
                                           untilDate:[NSDate distantFuture]
                                              inMode:NSEventTrackingRunLoopMode
                                             dequeue:YES];
        if (next.type == NSEventTypeLeftMouseUp) {
            break;
        }
    }
}

@implementation SBStandardTextFieldCell

- (BOOL)trackMouse:(NSEvent *)event
            inRect:(NSRect)cellFrame
            ofView:(NSView *)controlView
      untilMouseUp:(BOOL)untilMouseUp {
    SBTextField *field = ([controlView isKindOfClass:[SBTextField class]] ? (SBTextField *)controlView : nil);
    if (field && field.selectsAllOnMouseFocus && !SBTextFieldIsActivelyEditing(field)) {
        [field.window makeFirstResponder:field];
        SBTextFieldSelectAllText(field);
        __weak SBTextField *weakField = field;
        dispatch_async(dispatch_get_main_queue(), ^{
            SBTextFieldSelectAllText(weakField);
        });
        if (untilMouseUp) {
            SBTextFieldConsumeMouseUpEvents();
        }
        return YES;
    }
    return [super trackMouse:event inRect:cellFrame ofView:controlView untilMouseUp:untilMouseUp];
}

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
