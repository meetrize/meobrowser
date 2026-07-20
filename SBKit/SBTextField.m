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
        SBTextField *field = (SBTextField *)controlView;
        CGFloat leading = field.leadingContentInset;
        CGFloat trailing = field.trailingContentInset;
        if (leading > 0) {
            area.origin.x += leading;
            area.size.width = MAX(0, NSWidth(area) - leading);
        }
        if (trailing > 0) {
            area.size.width = MAX(0, NSWidth(area) - trailing);
        }
    }
    return area;
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSRect area = [self textAreaRectForBounds:theRect];
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        // 水平保留少量 bezel 边距；垂直留 2pt，避免 24pt 高输入框裁切下行。
        return NSInsetRect(area, 3.0, 2.0);
    }
    return [super drawingRectForBounds:area];
}

- (NSRect)titleRectForBounds:(NSRect)theRect {
    NSRect area = [self textAreaRectForBounds:theRect];
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        return NSInsetRect(area, 3.0, 2.0);
    }
    return [super titleRectForBounds:area];
}

- (void)editWithFrame:(NSRect)rect
               inView:(NSView *)controlView
               editor:(NSText *)textObj
             delegate:(nullable id)delegate
                event:(nullable NSEvent *)event {
    NSRect adjusted = [self drawingRectForBounds:controlView.bounds];
    [super editWithFrame:adjusted inView:controlView editor:textObj delegate:delegate event:event];
}

- (void)selectWithFrame:(NSRect)rect
                 inView:(NSView *)controlView
                 editor:(NSText *)textObj
               delegate:(nullable id)delegate
                  start:(NSInteger)selStart
                 length:(NSInteger)selLength {
    NSRect adjusted = [self drawingRectForBounds:controlView.bounds];
    [super selectWithFrame:adjusted
                    inView:controlView
                    editor:textObj
                  delegate:delegate
                     start:selStart
                    length:selLength];
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

- (void)setLeadingContentInset:(CGFloat)leadingContentInset {
    if (fabs(_leadingContentInset - leadingContentInset) < 0.5) {
        return;
    }
    _leadingContentInset = leadingContentInset;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)setTrailingContentInset:(CGFloat)trailingContentInset {
    if (fabs(_trailingContentInset - trailingContentInset) < 0.5) {
        return;
    }
    _trailingContentInset = trailingContentInset;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)setUsesCompactVerticalTextInsets:(BOOL)usesCompactVerticalTextInsets {
    if (_usesCompactVerticalTextInsets == usesCompactVerticalTextInsets) {
        return;
    }
    _usesCompactVerticalTextInsets = usesCompactVerticalTextInsets;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)syncFieldEditorFrameWithContentInsets {
    NSText *editor = self.currentEditor;
    if (!editor) {
        return;
    }
    NSRect frame = [self.cell drawingRectForBounds:self.bounds];
    if (!NSEqualRects(editor.frame, frame)) {
        editor.frame = frame;
    }
}

@end
