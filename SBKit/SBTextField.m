#import "SBTextField.h"
#import "SBTextFieldLayout.h"
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

- (NSRect)compactTextRectForBounds:(NSRect)theRect upwardBias:(CGFloat)upwardBias {
    NSRect area = [self textAreaRectForBounds:theRect];
    NSView *controlView = self.controlView;
    if (![controlView isKindOfClass:[SBTextField class]] ||
        !((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        return area;
    }
    SBTextField *field = (SBTextField *)controlView;
    area = SBTextFieldApplyCompactInsets(area);
    // 先下扩文字区（外框不变），再应用上边距，避免字底下移后被裁。
    area = SBTextFieldApplyBottomExtend(area, field.compactTextBottomExtend, controlView);
    area = SBTextFieldApplyTopInsetWithUpwardBias(area,
                                                 field.compactTextTopInset,
                                                 upwardBias,
                                                 controlView);
    return area;
}

- (NSRect)verticallyCenteredEditingRectForBounds:(NSRect)theRect {
    NSRect area = [self textAreaRectForBounds:theRect];
    NSView *controlView = self.controlView;
    area = SBTextFieldApplyCompactInsets(area);
    if ([controlView isKindOfClass:[SBTextField class]]) {
        area = SBTextFieldApplyBottomExtend(area,
                                            ((SBTextField *)controlView).compactTextBottomExtend,
                                            controlView);
    }
    CGFloat lineHeight = SBTextFieldLineHeight(self.font);
    if (lineHeight < 1.0) {
        lineHeight = NSHeight(area);
    }
    NSRect centered = SBTextFieldVerticallyCenteredRect(area, lineHeight);
    // 居中后再上移（光学微调；地址栏可用 compactTextUpwardBiasWhenEditing）。
    return SBTextFieldApplyUpwardBias(centered, [self editingUpwardBias], controlView);
}

- (CGFloat)idleUpwardBias {
    NSView *controlView = self.controlView;
    if (![controlView isKindOfClass:[SBTextField class]]) {
        return 0;
    }
    return ((SBTextField *)controlView).compactTextUpwardBias;
}

- (CGFloat)editingUpwardBias {
    NSView *controlView = self.controlView;
    if (![controlView isKindOfClass:[SBTextField class]]) {
        return 0;
    }
    return ((SBTextField *)controlView).compactTextUpwardBiasWhenEditing;
}

- (BOOL)centersWhenEditing {
    NSView *controlView = self.controlView;
    return [controlView isKindOfClass:[SBTextField class]]
        && ((SBTextField *)controlView).centersCompactTextWhenEditing;
}

- (void)prepareFieldEditor:(NSText *)textObj {
    if (![textObj isKindOfClass:[NSTextView class]]) {
        return;
    }
    NSTextView *textView = (NSTextView *)textObj;
    textView.textContainerInset = NSMakeSize(0, 0);
    if (textView.textContainer) {
        textView.textContainer.lineFragmentPadding = 0;
    }
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        SBTextField *field = (SBTextField *)controlView;
        if (field.currentEditor && [self centersWhenEditing]) {
            return [self verticallyCenteredEditingRectForBounds:theRect];
        }
        CGFloat bias = field.currentEditor ? [self editingUpwardBias] : [self idleUpwardBias];
        return [self compactTextRectForBounds:theRect upwardBias:bias];
    }
    return [super drawingRectForBounds:[self textAreaRectForBounds:theRect]];
}

- (NSRect)titleRectForBounds:(NSRect)theRect {
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        NSRect compact = [self compactTextRectForBounds:theRect upwardBias:[self idleUpwardBias]];
        return SBTextFieldTopAlignedTitleRect(compact, self.font, controlView);
    }
    return [super titleRectForBounds:[self textAreaRectForBounds:theRect]];
}

- (void)editWithFrame:(NSRect)rect
               inView:(NSView *)controlView
               editor:(NSText *)textObj
             delegate:(nullable id)delegate
                event:(nullable NSEvent *)event {
    NSRect adjusted = rect;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        if ([self centersWhenEditing]) {
            adjusted = [self verticallyCenteredEditingRectForBounds:controlView.bounds];
        } else {
            adjusted = [self compactTextRectForBounds:controlView.bounds
                                          upwardBias:[self editingUpwardBias]];
        }
    } else {
        adjusted = [self drawingRectForBounds:controlView.bounds];
    }
    [self prepareFieldEditor:textObj];
    [super editWithFrame:adjusted inView:controlView editor:textObj delegate:delegate event:event];
    [self prepareFieldEditor:textObj];
}

- (void)selectWithFrame:(NSRect)rect
                 inView:(NSView *)controlView
                 editor:(NSText *)textObj
               delegate:(nullable id)delegate
                  start:(NSInteger)selStart
                 length:(NSInteger)selLength {
    NSRect adjusted = rect;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        if ([self centersWhenEditing]) {
            adjusted = [self verticallyCenteredEditingRectForBounds:controlView.bounds];
        } else {
            adjusted = [self compactTextRectForBounds:controlView.bounds
                                          upwardBias:[self editingUpwardBias]];
        }
    } else {
        adjusted = [self drawingRectForBounds:controlView.bounds];
    }
    [self prepareFieldEditor:textObj];
    [super selectWithFrame:adjusted
                    inView:controlView
                    editor:textObj
                  delegate:delegate
                     start:selStart
                    length:selLength];
    [self prepareFieldEditor:textObj];
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

- (void)setCompactTextTopInset:(CGFloat)compactTextTopInset {
    CGFloat value = MAX(0.0, compactTextTopInset);
    if (fabs(_compactTextTopInset - value) < 0.25) {
        return;
    }
    _compactTextTopInset = value;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)setCompactTextUpwardBias:(CGFloat)compactTextUpwardBias {
    CGFloat value = MAX(0.0, compactTextUpwardBias);
    if (fabs(_compactTextUpwardBias - value) < 0.25) {
        return;
    }
    _compactTextUpwardBias = value;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)setCompactTextUpwardBiasWhenEditing:(CGFloat)compactTextUpwardBiasWhenEditing {
    CGFloat value = MAX(0.0, compactTextUpwardBiasWhenEditing);
    if (fabs(_compactTextUpwardBiasWhenEditing - value) < 0.25) {
        return;
    }
    _compactTextUpwardBiasWhenEditing = value;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)setCentersCompactTextWhenEditing:(BOOL)centersCompactTextWhenEditing {
    if (_centersCompactTextWhenEditing == centersCompactTextWhenEditing) {
        return;
    }
    _centersCompactTextWhenEditing = centersCompactTextWhenEditing;
    [self setNeedsDisplay:YES];
    [self syncFieldEditorFrameWithContentInsets];
}

- (void)setCompactTextBottomExtend:(CGFloat)compactTextBottomExtend {
    CGFloat value = MAX(0.0, compactTextBottomExtend);
    if (fabs(_compactTextBottomExtend - value) < 0.25) {
        return;
    }
    _compactTextBottomExtend = value;
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
