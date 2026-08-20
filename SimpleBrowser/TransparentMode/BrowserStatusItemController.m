#import "BrowserStatusItemController.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import "BrowserAppInfo.h"

@interface BrowserStatusItemController () <NSMenuDelegate>
@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
@property (nonatomic, strong, nullable) NSMenuItem *toggleTransparentItem;
@property (nonatomic, assign) BOOL installed;
@end

@implementation BrowserStatusItemController

+ (instancetype)sharedController {
    static BrowserStatusItemController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BrowserStatusItemController alloc] init];
    });
    return instance;
}

- (void)install {
    if (self.installed) {
        return;
    }
    self.installed = YES;

    NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    item.button.toolTip = BrowserAppDisplayName ?: @"MeoBrowser";
    item.button.image = [self statusBarImage];
    item.button.imagePosition = NSImageOnly;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MeoBrowser"];
    menu.delegate = self;

    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:@"进入透明模式"
                                                    action:@selector(toggleTransparentModeFromStatusItem:)
                                             keyEquivalent:@""];
    toggle.target = self;
    self.toggleTransparentItem = toggle;
    [menu addItem:toggle];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 MeoBrowser"
                                                  action:@selector(quitMeoBrowser:)
                                           keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quit.target = self;
    [menu addItem:quit];

    item.menu = menu;
    self.statusItem = item;
    [self refreshMenuAppearance];
}

- (NSImage *)statusBarImage {
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:13
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"cube.transparent"
                                    accessibilityDescription:BrowserAppDisplayName];
        if (symbol) {
            image = [symbol imageWithSymbolConfiguration:config];
        }
    }
    if (!image) {
        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (iconPath.length > 0) {
            image = [[NSImage alloc] initWithContentsOfFile:iconPath];
            image.size = NSMakeSize(16, 16);
        }
    }
    if (!image) {
        image = [NSImage imageNamed:NSImageNameApplicationIcon];
        image.size = NSMakeSize(16, 16);
    }
    image.template = YES;
    return image;
}

- (nullable BrowserWindowController *)targetBrowserWindowController {
    id delegate = NSApp.delegate;
    if ([delegate isKindOfClass:[AppDelegate class]]) {
        return [(AppDelegate *)delegate keyBrowserWindowController];
    }
    return nil;
}

- (void)refreshMenuAppearance {
    BrowserWindowController *wc = [self targetBrowserWindowController];
    BOOL on = wc.isTransparentModeEnabled;
    self.toggleTransparentItem.title = on ? @"退出透明模式" : @"进入透明模式";
    self.toggleTransparentItem.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    self.toggleTransparentItem.enabled = (wc != nil);
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    [self refreshMenuAppearance];
}

- (void)toggleTransparentModeFromStatusItem:(id)sender {
    (void)sender;
    BrowserWindowController *wc = [self targetBrowserWindowController];
    if (!wc) {
        return;
    }
    [wc toggleTransparentMode:sender];
    [self refreshMenuAppearance];
}

- (void)quitMeoBrowser:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

@end
