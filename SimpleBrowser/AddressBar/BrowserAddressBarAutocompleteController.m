#import "BrowserAddressBarAutocompleteController.h"
#import "BrowserShortcutSuggestionPanel.h"
#import "BrowserShortcutStore.h"
#import "BrowserShortcutItem.h"
#import "SBTextField.h"

static const NSTimeInterval kQueryDebounceInterval = 0.05;
static const NSTimeInterval kDismissFocusDelay = 0.15;
static const NSUInteger kSuggestionLimit = 8;

@interface BrowserAddressBarAutocompleteController () <BrowserShortcutSuggestionPanelDelegate, NSWindowDelegate>
@property (nonatomic, strong) BrowserShortcutSuggestionPanel *panel;
@property (nonatomic, copy) NSArray<BrowserShortcutItem *> *matches;
@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, assign) BOOL panelVisible;
@property (nonatomic, strong) dispatch_block_t pendingQueryBlock;
@property (nonatomic, strong) dispatch_block_t pendingDismissBlock;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, assign) BOOL applyingInlineAutocomplete;
@property (nonatomic, assign) BOOL hasActiveInlineAutocomplete;
/// 用户用 Backspace/Delete 清掉内联补全后，同一查询不再自动补上，直到输入变化。
@property (nonatomic, assign) BOOL inlineAutocompleteSuppressed;
@property (nonatomic, copy) NSString *suppressedForQuery;
@end

@implementation BrowserAddressBarAutocompleteController

- (instancetype)initWithAddressField:(SBTextField *)addressField {
    self = [super init];
    if (self) {
        _addressField = addressField;
        _selectedIndex = 0;
        _panel = [[BrowserShortcutSuggestionPanel alloc] init];
        _panel.suggestionDelegate = self;
    }
    return self;
}

- (void)install {
    if (self.installed) {
        return;
    }
    self.installed = YES;

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(addressFieldTextDidChange:)
                   name:NSControlTextDidChangeNotification
                 object:self.addressField];
    [center addObserver:self
               selector:@selector(addressFieldDidBeginEditing:)
                   name:NSControlTextDidBeginEditingNotification
                 object:self.addressField];
    [center addObserver:self
               selector:@selector(addressFieldDidEndEditing:)
                   name:NSControlTextDidEndEditingNotification
                 object:self.addressField];
    [center addObserver:self
               selector:@selector(windowDidResize:)
                   name:NSWindowDidResizeNotification
                 object:nil];
}

- (void)uninstall {
    if (!self.installed) {
        return;
    }
    self.installed = NO;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self dismissPanelImmediately];
}

- (void)dealloc {
    [self uninstall];
}

- (BOOL)isPanelVisible {
    return self.panelVisible;
}

- (NSWindow *)hostWindow {
    return [self.delegate windowForAutocompleteController:self];
}

- (NSRect)anchorRectOnScreen {
    SBTextField *field = self.addressField;
    if (!field || !field.window) {
        return NSZeroRect;
    }
    NSRect bounds = field.bounds;
    NSRect inWindow = [field convertRect:bounds toView:nil];
    return [field.window convertRectToScreen:inWindow];
}

#pragma mark - Query

- (void)addressFieldTextDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.applyingInlineAutocomplete) {
        return;
    }
    self.hasActiveInlineAutocomplete = NO;
    // 输入内容变了则解除「删除后抑制」；同一前缀下的删除由 delete 键处理。
    NSString *typed = [self userTypedQueryFromAddressField];
    if (self.inlineAutocompleteSuppressed &&
        ![typed isEqualToString:self.suppressedForQuery ?: @""]) {
        self.inlineAutocompleteSuppressed = NO;
        self.suppressedForQuery = nil;
    }
    [self scheduleQuery];
}

- (void)addressFieldDidBeginEditing:(NSNotification *)notification {
    (void)notification;
    [self cancelPendingDismiss];
    [self scheduleQuery];
}

- (void)addressFieldDidEndEditing:(NSNotification *)notification {
    (void)notification;
    [self scheduleDismissAfterFocusLoss];
}

- (void)windowDidResize:(NSNotification *)notification {
    NSWindow *hostWindow = [self hostWindow];
    if (!hostWindow || notification.object != hostWindow) {
        return;
    }
    if (self.panelVisible) {
        [self.panel updateWithItems:self.matches
                              query:self.currentQuery
                     selectedIndex:self.selectedIndex
                        anchorRect:[self anchorRectOnScreen]];
    }
}

- (void)scheduleQuery {
    if (self.pendingQueryBlock) {
        dispatch_block_cancel(self.pendingQueryBlock);
        self.pendingQueryBlock = nil;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        BrowserAddressBarAutocompleteController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingQueryBlock = nil;
        [strongSelf performQuery];
    });
    self.pendingQueryBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kQueryDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

/// 若地址栏正显示内联补全（后缀选中），查询只用用户真正键入的前缀。
- (NSString *)userTypedQueryFromAddressField {
    NSString *raw = self.addressField.stringValue ?: @"";
    NSText *editor = self.addressField.currentEditor;
    if (editor) {
        NSRange sel = editor.selectedRange;
        if (sel.location > 0 && sel.length > 0 && NSMaxRange(sel) == raw.length) {
            raw = [raw substringToIndex:sel.location];
        }
    }
    return [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)performQuery {
    NSString *trimmed = [self userTypedQueryFromAddressField];
    if (trimmed.length == 0) {
        [self dismissPanelImmediately];
        return;
    }

    NSArray<BrowserShortcutItem *> *matches = [BrowserShortcutStore shortcutsMatchingQuery:trimmed limit:kSuggestionLimit];
    if (matches.count == 0) {
        // 仅在确有内联补全时才回写文本；否则会把光标强行挪到行末，破坏中间/开头连续输入。
        if (self.hasActiveInlineAutocomplete) {
            [self revertInlineAutocompleteToTypedQuery:trimmed];
        }
        [self dismissPanelImmediately];
        return;
    }

    BOOL queryChanged = ![trimmed isEqualToString:self.currentQuery];
    self.currentQuery = trimmed;
    self.matches = matches;
    if (queryChanged || self.selectedIndex >= matches.count) {
        self.selectedIndex = 0;
    }

    self.panelVisible = YES;
    [self.panel updateWithItems:matches
                          query:trimmed
                 selectedIndex:self.selectedIndex
                    anchorRect:[self anchorRectOnScreen]];
    [self applyInlineAutocompleteIfPossible];
}

- (void)refreshMatchesIfNeeded {
    if (self.panelVisible) {
        [self performQuery];
    }
}

#pragma mark - Inline autocomplete

/// 内联补全只在「末尾输入」时安全：插入点在行末，或已有延伸到行末的补全选区。
- (BOOL)shouldApplyInlineAutocompleteAtCurrentCaret {
    NSText *editor = self.addressField.currentEditor;
    if (!editor) {
        return NO;
    }
    NSString *raw = self.addressField.stringValue ?: @"";
    NSRange sel = editor.selectedRange;
    if (sel.location == NSNotFound) {
        return NO;
    }
    if (sel.length == 0) {
        return sel.location == raw.length;
    }
    // 已有内联后缀选中（前缀 + 选中到行末）时允许继续刷新补全。
    return sel.location > 0 && NSMaxRange(sel) == raw.length;
}

- (nullable NSString *)inlineSuggestionForItem:(BrowserShortcutItem *)item query:(NSString *)query {
    if (query.length == 0 || item.urlString.length == 0) {
        return nil;
    }

    NSString *q = query.lowercaseString;
    NSURL *url = [NSURL URLWithString:item.urlString];
    NSString *host = url.host ?: @"";
    NSString *bareHost = host;
    if ([bareHost.lowercaseString hasPrefix:@"www."]) {
        bareHost = [bareHost substringFromIndex:4];
    }

    NSMutableArray<NSString *> *candidates = [[NSMutableArray alloc] init];
    void (^addCandidate)(NSString *) = ^(NSString *value) {
        if (value.length == 0) {
            return;
        }
        for (NSString *existing in candidates) {
            if ([existing caseInsensitiveCompare:value] == NSOrderedSame) {
                return;
            }
        }
        [candidates addObject:value];
    };

    addCandidate(bareHost);
    addCandidate(host);

    NSString *path = url.path;
    if (path.length > 0 && ![path isEqualToString:@"/"]) {
        addCandidate([bareHost stringByAppendingString:path]);
        addCandidate([host stringByAppendingString:path]);
    }

    NSString *withoutScheme = item.urlString;
    NSString *lowerURL = withoutScheme.lowercaseString;
    if ([lowerURL hasPrefix:@"https://"]) {
        withoutScheme = [withoutScheme substringFromIndex:8];
    } else if ([lowerURL hasPrefix:@"http://"]) {
        withoutScheme = [withoutScheme substringFromIndex:7];
    }
    addCandidate(withoutScheme);
    addCandidate(item.urlString);

    for (NSString *candidate in candidates) {
        if (candidate.length > q.length && [candidate.lowercaseString hasPrefix:q]) {
            return candidate;
        }
    }
    return nil;
}

- (void)applyInlineAutocompleteIfPossible {
    BrowserShortcutItem *item = [self selectedItem];
    NSString *query = self.currentQuery;
    if (!item || query.length == 0) {
        return;
    }

    // 在地址中间/开头编辑时不要改写 stringValue，否则光标会跳到行末。
    if (![self shouldApplyInlineAutocompleteAtCurrentCaret]) {
        return;
    }

    if (self.inlineAutocompleteSuppressed &&
        [query isEqualToString:self.suppressedForQuery ?: @""]) {
        return;
    }
    if (self.inlineAutocompleteSuppressed) {
        self.inlineAutocompleteSuppressed = NO;
        self.suppressedForQuery = nil;
    }

    NSString *suggestion = [self inlineSuggestionForItem:item query:query];
    if (!suggestion) {
        if (self.hasActiveInlineAutocomplete) {
            [self revertInlineAutocompleteToTypedQuery:query];
        }
        return;
    }

    NSString *suffix = [suggestion substringFromIndex:query.length];
    NSString *full = [query stringByAppendingString:suffix];
    [self setAddressFieldText:full selectingFrom:query.length];
    self.hasActiveInlineAutocomplete = (suffix.length > 0);
}

/// Backspace/Delete：去掉内联补全后缀，保留已输入前缀，并抑制立即再次补全。
- (BOOL)clearInlineAutocompleteForDelete {
    if (!self.hasActiveInlineAutocomplete) {
        return NO;
    }
    NSString *typed = self.currentQuery.length > 0 ? self.currentQuery : [self userTypedQueryFromAddressField];
    [self revertInlineAutocompleteToTypedQuery:typed];
    self.inlineAutocompleteSuppressed = YES;
    self.suppressedForQuery = [typed copy];
    return YES;
}

- (void)setAddressFieldText:(NSString *)text selectingFrom:(NSUInteger)prefixLength {
    self.applyingInlineAutocomplete = YES;
    self.addressField.stringValue = text ?: @"";
    NSText *editor = self.addressField.currentEditor;
    if (!editor) {
        [self.addressField.window makeFirstResponder:self.addressField];
        editor = self.addressField.currentEditor;
    }
    if (editor) {
        NSUInteger length = text.length;
        if (prefixLength > length) {
            prefixLength = length;
        }
        [editor setSelectedRange:NSMakeRange(prefixLength, length - prefixLength)];
    }
    self.applyingInlineAutocomplete = NO;
}

- (void)revertInlineAutocompleteToTypedQuery:(NSString *)typed {
    NSString *value = typed ?: @"";
    self.applyingInlineAutocomplete = YES;
    self.addressField.stringValue = value;
    NSText *editor = self.addressField.currentEditor;
    if (editor) {
        [editor setSelectedRange:NSMakeRange(value.length, 0)];
    }
    self.applyingInlineAutocomplete = NO;
    self.hasActiveInlineAutocomplete = NO;
}

- (BOOL)acceptInlineAutocompleteIfNeeded {
    if (!self.hasActiveInlineAutocomplete) {
        return NO;
    }
    NSText *editor = self.addressField.currentEditor;
    NSString *text = self.addressField.stringValue ?: @"";
    if (!editor) {
        self.hasActiveInlineAutocomplete = NO;
        return NO;
    }
    NSRange sel = editor.selectedRange;
    if (sel.length > 0 && NSMaxRange(sel) == text.length) {
        [editor setSelectedRange:NSMakeRange(text.length, 0)];
        self.hasActiveInlineAutocomplete = NO;
        return YES;
    }
    self.hasActiveInlineAutocomplete = NO;
    return NO;
}

#pragma mark - Panel lifecycle

- (void)dismissPanel {
    [self dismissPanelImmediately];
}

- (void)dismissPanelImmediately {
    [self cancelPendingDismiss];
    self.panelVisible = NO;
    self.matches = @[];
    self.currentQuery = @"";
    self.selectedIndex = 0;
    self.hasActiveInlineAutocomplete = NO;
    self.inlineAutocompleteSuppressed = NO;
    self.suppressedForQuery = nil;
    [self.panel dismissPanel];
}

- (void)scheduleDismissAfterFocusLoss {
    [self cancelPendingDismiss];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        BrowserAddressBarAutocompleteController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingDismissBlock = nil;
        NSWindow *hostWindow = [strongSelf hostWindow];
        if (hostWindow.firstResponder == strongSelf.addressField.currentEditor) {
            return;
        }
        [strongSelf dismissPanelImmediately];
    });
    self.pendingDismissBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDismissFocusDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)cancelPendingDismiss {
    if (self.pendingDismissBlock) {
        dispatch_block_cancel(self.pendingDismissBlock);
        self.pendingDismissBlock = nil;
    }
}

#pragma mark - Selection actions

- (nullable BrowserShortcutItem *)selectedItem {
    if (self.selectedIndex >= self.matches.count) {
        return nil;
    }
    return self.matches[self.selectedIndex];
}

- (BOOL)shouldOpenSelectedShortcutOnEnter {
    return self.panelVisible && self.matches.count > 0;
}

- (void)openSelectedShortcut {
    BrowserShortcutItem *item = [self selectedItem];
    if (!item) {
        return;
    }
    NSURL *url = [NSURL URLWithString:item.urlString];
    if (!url) {
        return;
    }
    [self dismissPanelImmediately];
    [self.delegate autocompleteController:self openURL:url];
}

- (BOOL)completeSelectedShortcutInAddressField {
    BrowserShortcutItem *item = [self selectedItem];
    if (!item) {
        return NO;
    }
    self.applyingInlineAutocomplete = YES;
    self.addressField.stringValue = item.urlString;
    NSText *editor = self.addressField.currentEditor;
    if (editor) {
        [editor setSelectedRange:NSMakeRange(item.urlString.length, 0)];
    }
    self.applyingInlineAutocomplete = NO;
    self.hasActiveInlineAutocomplete = NO;
    [self dismissPanelImmediately];
    [self.addressField.window makeFirstResponder:self.addressField];
    return YES;
}

- (void)moveSelectionByDelta:(NSInteger)delta {
    if (self.matches.count == 0) {
        return;
    }
    NSInteger count = (NSInteger)self.matches.count;
    NSInteger next = ((NSInteger)self.selectedIndex + delta) % count;
    if (next < 0) {
        next += count;
    }
    self.selectedIndex = (NSUInteger)next;
    [self.panel updateWithItems:self.matches
                          query:self.currentQuery
                 selectedIndex:self.selectedIndex
                    anchorRect:[self anchorRectOnScreen]];
    self.inlineAutocompleteSuppressed = NO;
    self.suppressedForQuery = nil;
    [self applyInlineAutocompleteIfPossible];
}

#pragma mark - Keyboard

- (BOOL)handleCommandBySelector:(SEL)commandSelector textView:(NSTextView *)textView {
    (void)textView;

    if (commandSelector == @selector(cancel:)) {
        if (self.panelVisible || self.hasActiveInlineAutocomplete) {
            NSString *typed = self.currentQuery.length > 0 ? self.currentQuery : [self userTypedQueryFromAddressField];
            [self revertInlineAutocompleteToTypedQuery:typed];
            [self dismissPanelImmediately];
            return YES;
        }
        return NO;
    }

    if (commandSelector == @selector(deleteBackward:) ||
        commandSelector == @selector(deleteForward:) ||
        commandSelector == @selector(deleteWordBackward:) ||
        commandSelector == @selector(deleteWordForward:) ||
        commandSelector == @selector(deleteToBeginningOfLine:) ||
        commandSelector == @selector(deleteToEndOfLine:)) {
        if ([self clearInlineAutocompleteForDelete]) {
            return YES;
        }
    }

    if (commandSelector == @selector(moveRight:) ||
        commandSelector == @selector(moveToEndOfLine:) ||
        commandSelector == @selector(moveToRightEndOfLine:)) {
        if ([self acceptInlineAutocompleteIfNeeded]) {
            return YES;
        }
    }

    // 左移：取消内联选中后缀，光标落在已输入末尾，便于继续 Backspace。
    if (commandSelector == @selector(moveLeft:) ||
        commandSelector == @selector(moveToBeginningOfLine:) ||
        commandSelector == @selector(moveToLeftEndOfLine:)) {
        if (self.hasActiveInlineAutocomplete) {
            NSString *typed = self.currentQuery.length > 0 ? self.currentQuery : [self userTypedQueryFromAddressField];
            [self revertInlineAutocompleteToTypedQuery:typed];
            self.inlineAutocompleteSuppressed = YES;
            self.suppressedForQuery = [typed copy];
            return YES;
        }
    }

    if (!self.panelVisible || self.matches.count == 0) {
        return NO;
    }

    if (commandSelector == @selector(moveDown:)) {
        [self moveSelectionByDelta:1];
        return YES;
    }
    if (commandSelector == @selector(moveUp:)) {
        [self moveSelectionByDelta:-1];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:)) {
        [self openSelectedShortcut];
        return YES;
    }
    if (commandSelector == @selector(insertTab:)) {
        return [self completeSelectedShortcutInAddressField];
    }
    if (commandSelector == @selector(insertBacktab:)) {
        return [self completeSelectedShortcutInAddressField];
    }

    return NO;
}

#pragma mark - BrowserShortcutSuggestionPanelDelegate

- (void)suggestionPanelDidSelectItemAtIndex:(NSUInteger)index {
    (void)index;
}

- (void)suggestionPanelDidOpenItemAtIndex:(NSUInteger)index {
    if (index >= self.matches.count) {
        return;
    }
    self.selectedIndex = index;
    [self openSelectedShortcut];
}

- (void)suggestionPanelDidOpenItemAtIndexInNewTab:(NSUInteger)index {
    if (index >= self.matches.count) {
        return;
    }
    BrowserShortcutItem *item = self.matches[index];
    NSURL *url = [NSURL URLWithString:item.urlString];
    if (!url) {
        return;
    }
    [self dismissPanelImmediately];
    [self.delegate autocompleteController:self openURLInNewTab:url];
}

- (void)suggestionPanelDidHoverItemAtIndex:(NSUInteger)index {
    if (index >= self.matches.count) {
        return;
    }
    self.selectedIndex = index;
    [self.panel setHighlightedIndex:index];
    self.inlineAutocompleteSuppressed = NO;
    self.suppressedForQuery = nil;
    [self applyInlineAutocompleteIfPossible];
}

@end
