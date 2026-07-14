#import "BrowserSettingsWindowController.h"
#import "BrowsingPreferences.h"

@interface BrowserSettingsWindowController ()
@property (nonatomic, strong) NSPopUpButton *searchEnginePopUp;
@property (nonatomic, strong) NSTextField *defaultBrowserStatusLabel;
@property (nonatomic, strong) NSButton *setDefaultBrowserButton;
@property (nonatomic, strong) NSButton *clearWebsiteDataButton;
@property (nonatomic, strong) NSTextField *clearWebsiteDataStatusLabel;
@end

@implementation BrowserSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 310)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"设置";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSTextField *searchCaption = [NSTextField labelWithString:@"默认搜索引擎"];
    searchCaption.font = [NSFont systemFontOfSize:13];

    self.searchEnginePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.searchEnginePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchEnginePopUp.controlSize = NSControlSizeRegular;
    self.searchEnginePopUp.target = self;
    self.searchEnginePopUp.action = @selector(searchEngineChanged:);

    for (NSDictionary *engine in [BrowsingPreferences availableSearchEngines]) {
        [self.searchEnginePopUp addItemWithTitle:engine[@"name"]];
        NSMenuItem *item = self.searchEnginePopUp.lastItem;
        item.representedObject = engine[@"id"];
    }
    [self selectCurrentSearchEngineInPopUp];

    NSGridView *searchGrid = [NSGridView gridViewWithViews:@[@[searchCaption, self.searchEnginePopUp]]];
    searchGrid.columnSpacing = 12;
    searchGrid.rowSpacing = 8;
    [searchGrid columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [searchGrid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    NSTextField *searchHint = [NSTextField labelWithString:@"在地址栏输入非网址内容时将使用所选搜索引擎。"];
    searchHint.font = [NSFont systemFontOfSize:11];
    searchHint.textColor = [NSColor secondaryLabelColor];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *browserCaption = [NSTextField labelWithString:@"默认浏览器"];
    browserCaption.font = [NSFont systemFontOfSize:13];

    self.defaultBrowserStatusLabel = [NSTextField labelWithString:@""];
    self.defaultBrowserStatusLabel.font = [NSFont systemFontOfSize:12];
    self.defaultBrowserStatusLabel.textColor = [NSColor secondaryLabelColor];

    self.setDefaultBrowserButton = [NSButton buttonWithTitle:@"设为默认浏览器"
                                                      target:self
                                                      action:@selector(setDefaultBrowserClicked:)];
    self.setDefaultBrowserButton.bezelStyle = NSBezelStyleRounded;
    self.setDefaultBrowserButton.controlSize = NSControlSizeRegular;

    NSStackView *browserRow = [NSStackView stackViewWithViews:@[self.defaultBrowserStatusLabel, self.setDefaultBrowserButton]];
    browserRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    browserRow.alignment = NSLayoutAttributeCenterY;
    browserRow.spacing = 12;
    browserRow.distribution = NSStackViewDistributionFill;

    NSTextField *browserHint = [NSTextField wrappingLabelWithString:@"设为默认后，系统中打开的 http/https 链接将由 MeoBrowser 处理。更改时系统可能会弹出确认对话框。"];
    browserHint.font = [NSFont systemFontOfSize:11];
    browserHint.textColor = [NSColor secondaryLabelColor];
    browserHint.preferredMaxLayoutWidth = 388;

    NSBox *separator2 = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator2.boxType = NSBoxSeparator;
    separator2.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *privacyCaption = [NSTextField labelWithString:@"隐私与数据"];
    privacyCaption.font = [NSFont systemFontOfSize:13];

    self.clearWebsiteDataButton = [NSButton buttonWithTitle:@"清除网站数据…"
                                                     target:self
                                                     action:@selector(clearWebsiteDataClicked:)];
    self.clearWebsiteDataButton.bezelStyle = NSBezelStyleRounded;
    self.clearWebsiteDataButton.controlSize = NSControlSizeRegular;

    self.clearWebsiteDataStatusLabel = [NSTextField labelWithString:@"缓存、Cookie 与网站本地存储"];
    self.clearWebsiteDataStatusLabel.font = [NSFont systemFontOfSize:11];
    self.clearWebsiteDataStatusLabel.textColor = [NSColor secondaryLabelColor];

    NSStackView *privacyRow = [NSStackView stackViewWithViews:@[self.clearWebsiteDataButton, self.clearWebsiteDataStatusLabel]];
    privacyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    privacyRow.alignment = NSLayoutAttributeCenterY;
    privacyRow.spacing = 12;

    NSStackView *root = [NSStackView stackViewWithViews:@[
        searchGrid,
        searchHint,
        separator,
        browserCaption,
        browserRow,
        browserHint,
        separator2,
        privacyCaption,
        privacyRow,
    ]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 10;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *contentView = self.window.contentView;
    [contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [separator.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [separator2.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [browserRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [privacyRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
    ]];

    [self refreshDefaultBrowserStatus];
}

- (void)selectCurrentSearchEngineInPopUp {
    NSString *currentID = [BrowsingPreferences defaultSearchEngineID];
    for (NSInteger i = 0; i < self.searchEnginePopUp.numberOfItems; i++) {
        NSMenuItem *item = [self.searchEnginePopUp itemAtIndex:i];
        if ([item.representedObject isEqual:currentID]) {
            [self.searchEnginePopUp selectItemAtIndex:i];
            return;
        }
    }
}

- (void)refreshDefaultBrowserStatus {
    BOOL isDefault = [BrowsingPreferences isDefaultBrowser];
    if (isDefault) {
        self.defaultBrowserStatusLabel.stringValue = @"当前已是默认浏览器";
        self.setDefaultBrowserButton.enabled = NO;
        self.setDefaultBrowserButton.title = @"已是默认浏览器";
    } else {
        self.defaultBrowserStatusLabel.stringValue = @"当前不是默认浏览器";
        self.setDefaultBrowserButton.enabled = YES;
        self.setDefaultBrowserButton.title = @"设为默认浏览器";
    }
}

- (void)searchEngineChanged:(id)sender {
    (void)sender;
    NSMenuItem *item = self.searchEnginePopUp.selectedItem;
    NSString *engineID = item.representedObject;
    if (![engineID isKindOfClass:[NSString class]]) {
        return;
    }
    [BrowsingPreferences setDefaultSearchEngineID:engineID];
}

- (void)setDefaultBrowserClicked:(id)sender {
    (void)sender;
    self.setDefaultBrowserButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [BrowsingPreferences requestSetAsDefaultBrowserWithCompletion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            BOOL cancelled = ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError)
                || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);
            if (!cancelled) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法设为默认浏览器";
                alert.informativeText = error.localizedDescription.length > 0
                    ? error.localizedDescription
                    : @"请在「系统设置 › 桌面与 Dock › 默认网页浏览器」中手动选择 MeoBrowser。";
                alert.alertStyle = NSAlertStyleWarning;
                [alert beginSheetModalForWindow:strongSelf.window completionHandler:nil];
            }
        }
        [strongSelf refreshDefaultBrowserStatus];
    }];
}

- (void)clearWebsiteDataClicked:(id)sender {
    (void)sender;
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"清除网站数据？";
    confirm.informativeText = @"将删除 Cookie、缓存与网站本地存储。已打开的标签页不会关闭，但登录状态可能会失效。";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"清除"];
    [confirm addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) {
            return;
        }
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.clearWebsiteDataButton.enabled = NO;
        strongSelf.clearWebsiteDataStatusLabel.stringValue = @"正在清除…";
        [BrowsingPreferences clearWebsiteDataWithCompletion:^(NSError * _Nullable error) {
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            innerSelf.clearWebsiteDataButton.enabled = YES;
            if (error) {
                innerSelf.clearWebsiteDataStatusLabel.stringValue = @"清除失败";
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"无法清除网站数据";
                alert.informativeText = error.localizedDescription ?: @"未知错误";
                alert.alertStyle = NSAlertStyleWarning;
                [alert beginSheetModalForWindow:innerSelf.window completionHandler:nil];
            } else {
                innerSelf.clearWebsiteDataStatusLabel.stringValue = @"已清除";
            }
        }];
    }];
}

- (void)showWindow:(id)sender {
    [self selectCurrentSearchEngineInPopUp];
    [self refreshDefaultBrowserStatus];
    self.clearWebsiteDataStatusLabel.stringValue = @"缓存、Cookie 与网站本地存储";
    [super showWindow:sender];
}

@end
