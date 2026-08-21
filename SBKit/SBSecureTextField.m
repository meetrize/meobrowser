#import "SBSecureTextField.h"
#import "SBTextFieldLayout.h"
#import "SBTextInputConfiguration.h"

@interface SBStandardSecureTextFieldCell : NSSecureTextFieldCell
@end

@implementation SBStandardSecureTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBSecureTextField class]] &&
        ((SBSecureTextField *)controlView).usesCompactVerticalTextInsets) {
        return SBTextFieldApplyCompactInsets(theRect);
    }
    return [super drawingRectForBounds:theRect];
}

- (NSRect)titleRectForBounds:(NSRect)theRect {
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBSecureTextField class]] &&
        ((SBSecureTextField *)controlView).usesCompactVerticalTextInsets) {
        NSRect compact = SBTextFieldApplyCompactInsets(theRect);
        return SBTextFieldTopAlignedTitleRect(compact, self.font, controlView);
    }
    return [super titleRectForBounds:theRect];
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

@implementation SBSecureTextField

+ (Class)cellClass {
    return [SBStandardSecureTextFieldCell class];
}

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
