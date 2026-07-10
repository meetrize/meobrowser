#import "BrowserSettingsWindowController.h"
#import "BrowsingPreferences.h"

@interface BrowserSettingsWindowController ()
@property (nonatomic, strong) NSPopUpButton *searchEnginePopUp;
@end

@implementation BrowserSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 88)
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
    NSTextField *caption = [NSTextField labelWithString:@"默认搜索引擎"];
    caption.font = [NSFont systemFontOfSize:13];

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

    NSGridView *grid = [NSGridView gridViewWithViews:@[@[caption, self.searchEnginePopUp]]];
    grid.columnSpacing = 12;
    grid.rowSpacing = 8;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    NSTextField *hint = [NSTextField labelWithString:@"在地址栏输入非网址内容时将使用所选搜索引擎。"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];

    NSStackView *root = [NSStackView stackViewWithViews:@[grid, hint]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
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
    ]];
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

- (void)searchEngineChanged:(id)sender {
    (void)sender;
    NSMenuItem *item = self.searchEnginePopUp.selectedItem;
    NSString *engineID = item.representedObject;
    if (![engineID isKindOfClass:[NSString class]]) {
        return;
    }
    [BrowsingPreferences setDefaultSearchEngineID:engineID];
}

- (void)showWindow:(id)sender {
    [self selectCurrentSearchEngineInPopUp];
    [super showWindow:sender];
}

@end
