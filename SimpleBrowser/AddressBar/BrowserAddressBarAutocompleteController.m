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

- (void)performQuery {
    NSString *raw = self.addressField.stringValue ?: @"";
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        [self dismissPanelImmediately];
        return;
    }

    NSArray<BrowserShortcutItem *> *matches = [BrowserShortcutStore shortcutsMatchingQuery:trimmed limit:kSuggestionLimit];
    if (matches.count == 0) {
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
}

- (void)refreshMatchesIfNeeded {
    if (self.panelVisible) {
        [self performQuery];
    }
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
    self.addressField.stringValue = item.urlString;
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
}

#pragma mark - Keyboard

- (BOOL)handleCommandBySelector:(SEL)commandSelector textView:(NSTextView *)textView {
    (void)textView;

    if (commandSelector == @selector(cancel:)) {
        if (self.panelVisible) {
            [self dismissPanelImmediately];
            return YES;
        }
        return NO;
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
}

@end
