#import "SBTextField.h"
#import "SBTextFieldLayout.h"
#import "SBTextInputConfiguration.h"

@interface SBStandardTextFieldCell : NSTextFieldCell
@end

@interface SBTextField ()
@property (nonatomic, assign) NSInteger selectAllGeneration;
/// 失焦后下一次鼠标点击应全选；全选或已聚焦再点后清掉。
@property (nonatomic, assign) BOOL needsSelectAllOnMouseFocus;
/// 窗口常在 mouseDown 送达前就 makeFirstResponder→selectText；本次点击须保持全选。
@property (nonatomic, assign) BOOL preserveSelectAllThroughFocusClick;
@property (nonatomic, assign) BOOL ignoringSelectTextSideEffects;
- (void)meo_noteEndedEditingForMouseFocusSelectAll;
- (void)meo_applySelectAllOnMouseFocus;
@end

static void SBTextFieldSelectAllText(SBTextField *field) {
    NSString *value = field.stringValue ?: @"";
    if (value.length == 0) {
        return;
    }
    NSText *editor = field.currentEditor;
    if (!editor) {
        field.ignoringSelectTextSideEffects = YES;
        [field selectText:nil];
        field.ignoringSelectTextSideEffects = NO;
        editor = field.currentEditor;
    }
    if (editor) {
        [editor setSelectedRange:NSMakeRange(0, value.length)];
    }
}

static NSUInteger SBTextFieldInsertionIndex(NSTextView *editor, NSPoint windowPoint) {
    NSPoint local = [editor convertPoint:windowPoint fromView:nil];
    NSUInteger idx = [editor characterIndexForInsertionAtPoint:local];
    NSUInteger len = editor.string.length;
    return MIN(idx, len);
}

static void SBTextFieldTrackSelectionFromIndex(NSTextView *editor, NSUInteger anchorIndex) {
    NSWindow *window = editor.window;
    if (!window) {
        return;
    }
    while (YES) {
        NSEvent *next = [window nextEventMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged)
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];
        if (next == nil || next.type == NSEventTypeLeftMouseUp) {
            break;
        }
        NSUInteger idx = SBTextFieldInsertionIndex(editor, next.locationInWindow);
        NSUInteger start = MIN(anchorIndex, idx);
        NSUInteger end = MAX(anchorIndex, idx);
        [editor setSelectedRange:NSMakeRange(start, end - start)];
    }
}

static void SBTextFieldConsumeMouseUpEvents(void) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.45];
    while (YES) {
        NSEvent *next = [NSApp nextEventMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged)
                                           untilDate:deadline
                                              inMode:NSEventTrackingRunLoopMode
                                             dequeue:YES];
        if (next == nil || next.type == NSEventTypeLeftMouseUp) {
            break;
        }
    }
}

static void SBTextFieldLog(NSString *msg, SBTextField *field) {
    NSRange sel = field.currentEditor ? field.currentEditor.selectedRange : NSMakeRange(NSNotFound, 0);
    NSString *line = [NSString stringWithFormat:
                      @"%@ | needSelAll=%d editor=%p len=%lu sel=%@\n",
                      msg,
                      field.needsSelectAllOnMouseFocus,
                      field.currentEditor,
                      (unsigned long)(field.stringValue.length),
                      sel.location == NSNotFound ? @"nil" : NSStringFromRange(sel)];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/meo-address-focus.log"]) {
        [@"" writeToFile:@"/tmp/meo-address-focus.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/meo-address-focus.log"];
    [fh seekToEndOfFile];
    [fh writeData:data];
    [fh closeFile];
}

@implementation SBStandardTextFieldCell

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

- (BOOL)usesCapsuleBezel {
    NSView *controlView = self.controlView;
    return [controlView isKindOfClass:[SBTextField class]]
        && ((SBTextField *)controlView).usesCapsuleBezel;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if ([self usesCapsuleBezel]) {
        [self drawInteriorWithFrame:controlView.bounds inView:controlView];
        return;
    }
    [super drawWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (![controlView isKindOfClass:[SBTextField class]]) {
        [super drawInteriorWithFrame:cellFrame inView:controlView];
        return;
    }
    SBTextField *field = (SBTextField *)controlView;
    if (field.leadingContentInset < 0.5 && field.trailingContentInset < 0.5 && !field.usesCapsuleBezel) {
        [super drawInteriorWithFrame:cellFrame inView:controlView];
        return;
    }

    if (field.currentEditor != nil) {
        return;
    }

    NSRect titleRect = [self idleTitleRectForControlView:controlView];
    if (NSIsEmptyRect(titleRect) || NSWidth(titleRect) < 1.0) {
        return;
    }

    if (self.stringValue.length == 0) {
        NSAttributedString *placeholder = self.placeholderAttributedString;
        if (!placeholder && self.placeholderString.length > 0) {
            NSDictionary *attrs = @{
                NSForegroundColorAttributeName: NSColor.placeholderTextColor,
                NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize],
            };
            placeholder = [[NSAttributedString alloc] initWithString:self.placeholderString
                                                          attributes:attrs];
        }
        [placeholder drawInRect:titleRect];
        return;
    }

    NSMutableAttributedString *text = [self.attributedStringValue mutableCopy];
    if (text.length == 0) {
        return;
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = self.lineBreakMode;
    style.alignment = self.alignment;
    [text addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, text.length)];
    [text drawInRect:titleRect];
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSView *controlView = self.controlView;
    if ([controlView isKindOfClass:[SBTextField class]] &&
        ((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        SBTextField *field = (SBTextField *)controlView;
        if (field.usesCapsuleBezel) {
            return [self idleTitleRectForControlView:controlView];
        }
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
    NSRect adjusted = [self editingFrameForControlView:controlView];
    [self prepareFieldEditor:textObj];
    [super editWithFrame:adjusted inView:controlView editor:textObj delegate:delegate event:event];
    [self prepareFieldEditor:textObj];
    if (!NSEqualRects(textObj.frame, adjusted)) {
        textObj.frame = adjusted;
    }
    [controlView setNeedsDisplay:YES];
}

- (void)selectWithFrame:(NSRect)rect
                 inView:(NSView *)controlView
                 editor:(NSText *)textObj
               delegate:(nullable id)delegate
                  start:(NSInteger)selStart
                 length:(NSInteger)selLength {
    NSRect adjusted = [self editingFrameForControlView:controlView];
    [self prepareFieldEditor:textObj];
    [super selectWithFrame:adjusted
                    inView:controlView
                    editor:textObj
                  delegate:delegate
                     start:selStart
                    length:selLength];
    [self prepareFieldEditor:textObj];
    if (!NSEqualRects(textObj.frame, adjusted)) {
        textObj.frame = adjusted;
    }
    [controlView setNeedsDisplay:YES];
}

- (NSRect)editingFrameForControlView:(NSView *)controlView {
    if (![controlView isKindOfClass:[SBTextField class]]) {
        return [self drawingRectForBounds:controlView.bounds];
    }
    SBTextField *field = (SBTextField *)controlView;
    if (field.usesCapsuleBezel) {
        return [self idleTitleRectForControlView:controlView];
    }
    if (field.usesCompactVerticalTextInsets && [self centersWhenEditing]) {
        return [self verticallyCenteredEditingRectForBounds:controlView.bounds];
    }
    if (field.usesCompactVerticalTextInsets) {
        return [self compactTextRectForBounds:controlView.bounds
                                  upwardBias:[self editingUpwardBias]];
    }
    return [self drawingRectForBounds:controlView.bounds];
}

- (NSRect)idleTitleRectForControlView:(NSView *)controlView {
    if (![controlView isKindOfClass:[SBTextField class]] ||
        !((SBTextField *)controlView).usesCompactVerticalTextInsets) {
        return [self titleRectForBounds:controlView.bounds];
    }
    NSRect compact = [self compactTextRectForBounds:controlView.bounds
                                        upwardBias:[self idleUpwardBias]];
    return SBTextFieldTopAlignedTitleRect(compact, self.font, controlView);
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
        _needsSelectAllOnMouseFocus = YES;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self
               selector:@selector(meo_controlTextDidEndEditing:)
                   name:NSControlTextDidEndEditingNotification
                 object:self];
        // 网页获焦时地址栏未必立刻收到 EndEditing；用此通知保证下次点击会全选。
        [nc addObserver:self
               selector:@selector(meo_webViewDidBecomeFirstResponder:)
                   name:@"BrowserWebViewDidBecomeFirstResponder"
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)meo_webViewDidBecomeFirstResponder:(NSNotification *)notification {
    if (!self.selectsAllOnMouseFocus) {
        return;
    }
    id obj = notification.object;
    if ([obj isKindOfClass:[NSView class]] && ((NSView *)obj).window != self.window) {
        return;
    }
    // 确保结束编辑，否则下次点击会打到 field editor，mouseDown 全选路径进不去。
    if (self.currentEditor != nil) {
        [self.window endEditingFor:self];
    }
    [self meo_noteEndedEditingForMouseFocusSelectAll];
}

- (void)setSelectsAllOnMouseFocus:(BOOL)selectsAllOnMouseFocus {
    _selectsAllOnMouseFocus = selectsAllOnMouseFocus;
    if (selectsAllOnMouseFocus) {
        self.needsSelectAllOnMouseFocus = YES;
    }
}

- (void)meo_controlTextDidEndEditing:(NSNotification *)notification {
    (void)notification;
    [self meo_noteEndedEditingForMouseFocusSelectAll];
}

- (void)meo_noteEndedEditingForMouseFocusSelectAll {
    if (!self.selectsAllOnMouseFocus) {
        return;
    }
    self.needsSelectAllOnMouseFocus = YES;
    SBTextFieldLog(@"endEditing → needSelAll=YES", self);
}

- (void)meo_applySelectAllOnMouseFocus {
    NSInteger generation = ++self.selectAllGeneration;
    self.needsSelectAllOnMouseFocus = NO;
    SBTextFieldSelectAllText(self);
    SBTextFieldLog(@"applied selectAll", self);

    __weak SBTextField *weakSelf = self;
    void (^reassert)(void) = ^{
        SBTextField *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.selectAllGeneration != generation) {
            return;
        }
        if (!strongSelf.currentEditor) {
            return;
        }
        SBTextFieldSelectAllText(strongSelf);
        SBTextFieldLog(@"reassert selectAll", strongSelf);
    };
    dispatch_async(dispatch_get_main_queue(), reassert);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), reassert);
}

- (void)selectText:(id)sender {
    [super selectText:sender];
    if (!self.selectsAllOnMouseFocus || self.ignoringSelectTextSideEffects) {
        return;
    }
    NSEvent *e = NSApp.currentEvent;
    BOOL fromMouse = (e != nil &&
                      (e.type == NSEventTypeLeftMouseDown ||
                       e.type == NSEventTypeLeftMouseUp ||
                       e.type == NSEventTypeLeftMouseDragged));
    // 已全选。鼠标聚焦：等 mouseDown 保持全选；⌘L：下次点击再落光标。
    self.needsSelectAllOnMouseFocus = NO;
    self.preserveSelectAllThroughFocusClick = fromMouse;
    SBTextFieldLog(fromMouse ? @"selectText fromMouse → preserve" : @"selectText (key) → next click caret",
                   self);
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.selectsAllOnMouseFocus) {
        [super mouseDown:event];
        return;
    }

    NSEventModifierFlags mods =
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL extendMods = (mods & (NSEventModifierFlagShift | NSEventModifierFlagCommand |
                               NSEventModifierFlagOption | NSEventModifierFlagControl)) != 0;

    // 系统已在 mouseDown 前 selectText 全选：本拍点击必须保持全选，绝不能落光标。
    if (self.preserveSelectAllThroughFocusClick && event.clickCount < 2 && !extendMods) {
        SBTextFieldLog(@"mouseDown KEEP selectAll (selectText raced ahead)", self);
        self.preserveSelectAllThroughFocusClick = NO;
        [self meo_applySelectAllOnMouseFocus];
        SBTextFieldConsumeMouseUpEvents();
        [self meo_applySelectAllOnMouseFocus];
        return;
    }

    // 失焦后的第一次点击（系统未抢先 selectText）：自行全选。
    if (self.needsSelectAllOnMouseFocus && event.clickCount < 2 && !extendMods) {
        SBTextFieldLog(@"mouseDown SELECT ALL path", self);

        NSResponder *fr = self.window.firstResponder;
        if ([fr isKindOfClass:[NSView class]]) {
            for (NSView *v = (NSView *)fr; v != nil; v = v.superview) {
                if ([v isKindOfClass:NSClassFromString(@"WKWebView")]) {
                    [self.window makeFirstResponder:self.window];
                    break;
                }
            }
        }

        self.preserveSelectAllThroughFocusClick = NO;
        [self.window makeFirstResponder:self];
        [self meo_applySelectAllOnMouseFocus];
        SBTextFieldConsumeMouseUpEvents();
        [self meo_applySelectAllOnMouseFocus];
        return;
    }

    // 已聚焦后再点：取消全选，光标落在点击处（可拖选）。
    SBTextFieldLog(@"mouseDown CARET path", self);
    self.needsSelectAllOnMouseFocus = NO;
    self.preserveSelectAllThroughFocusClick = NO;
    self.selectAllGeneration += 1;

    NSText *editor = self.currentEditor;
    if ([editor isKindOfClass:[NSTextView class]] && event.clickCount < 2 && !extendMods) {
        NSTextView *tv = (NSTextView *)editor;
        NSUInteger idx = SBTextFieldInsertionIndex(tv, event.locationInWindow);
        [tv setSelectedRange:NSMakeRange(idx, 0)];
        SBTextFieldTrackSelectionFromIndex(tv, idx);
        return;
    }

    [super mouseDown:event];
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

- (void)setUsesCapsuleBezel:(BOOL)usesCapsuleBezel {
    if (_usesCapsuleBezel == usesCapsuleBezel) {
        return;
    }
    _usesCapsuleBezel = usesCapsuleBezel;
    [self applyCapsuleBezelStyle];
}

- (void)setBezeled:(BOOL)bezeled {
    [super setBezeled:_usesCapsuleBezel ? NO : bezeled];
}

- (void)setBordered:(BOOL)bordered {
    [super setBordered:_usesCapsuleBezel ? NO : bordered];
}

- (void)setBezelStyle:(NSTextFieldBezelStyle)bezelStyle {
    if (_usesCapsuleBezel) {
        [super setBezelStyle:NSTextFieldSquareBezel];
        [super setBezeled:NO];
        [super setBordered:NO];
        return;
    }
    [super setBezelStyle:bezelStyle];
}

- (void)applyCapsuleBezelStyle {
    if (!_usesCapsuleBezel) {
        self.wantsLayer = NO;
        [super setBezelStyle:NSTextFieldSquareBezel];
        [super setBezeled:YES];
        [super setBordered:YES];
        self.drawsBackground = YES;
        self.focusRingType = NSFocusRingTypeDefault;
        [self setNeedsDisplay:YES];
        return;
    }

    self.wantsLayer = NO;
    if (self.layer) {
        self.layer = nil;
    }
    [super setBezeled:NO];
    [super setBordered:NO];
    self.drawsBackground = NO;
    self.focusRingType = NSFocusRingTypeNone;
    self.cell.focusRingType = NSFocusRingTypeNone;
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque {
    if (_usesCapsuleBezel) {
        return NO;
    }
    return [super isOpaque];
}

- (BOOL)wantsUpdateLayer {
    if (_usesCapsuleBezel) {
        return NO;
    }
    return [super wantsUpdateLayer];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!_usesCapsuleBezel) {
        [super drawRect:dirtyRect];
        return;
    }
    NSTextFieldCell *cell = (NSTextFieldCell *)self.cell;
    [cell drawInteriorWithFrame:self.bounds inView:self];
}

- (void)layout {
    [super layout];
    if (_usesCapsuleBezel) {
        [super setBezeled:NO];
        [super setBordered:NO];
        self.wantsLayer = NO;
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (_usesCapsuleBezel) {
        [self applyCapsuleBezelStyle];
    }
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
