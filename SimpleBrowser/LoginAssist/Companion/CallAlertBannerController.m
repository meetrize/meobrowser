#import "CallAlertBannerController.h"
#import "CallAlertSettings.h"
#import "PhonePolicyStore.h"
#import "SBTextField.h"

NSNotificationName const CallAlertDidUpdateNotification = @"CallAlertDidUpdateNotification";

@interface CallAlertBannerHost : NSObject
@property (nonatomic, weak) NSView *container;
@property (nonatomic, weak) id windowController;
@property (nonatomic, strong) NSView *bannerView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *noteButton;
@property (nonatomic, strong) NSButton *closeButton;
@end

@implementation CallAlertBannerHost
@end

@interface CallAlertBannerController ()
@property (nonatomic, strong) NSMutableArray<CallAlertBannerHost *> *hosts;
@property (nonatomic, copy, nullable) NSDictionary *currentPayload;
@property (nonatomic, copy, nullable) NSString *currentDisplayName;
@property (nonatomic, copy, nullable) NSString *currentTypeLabel;
@property (nonatomic, strong, nullable) NSTimer *autoHideTimer;
@end

@implementation CallAlertBannerController

+ (instancetype)sharedController {
    static CallAlertBannerController *ctrl;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ctrl = [[self alloc] init];
    });
    return ctrl;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hosts = [NSMutableArray array];
    }
    return self;
}

- (void)installInContentContainer:(NSView *)container forWindowController:(id)windowController {
    if (!container) return;
    for (CallAlertBannerHost *h in self.hosts) {
        if (h.container == container) {
            [self refreshHost:h];
            return;
        }
    }
    CallAlertBannerHost *host = [[CallAlertBannerHost alloc] init];
    host.container = container;
    host.windowController = windowController;

    NSView *banner = [[NSView alloc] initWithFrame:NSZeroRect];
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    banner.wantsLayer = YES;
    banner.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.12 green:0.45 blue:0.28 alpha:0.95] CGColor];
    banner.hidden = YES;

    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = NSColor.whiteColor;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    label.drawsBackground = NO;
    label.bordered = NO;
    label.editable = NO;
    label.selectable = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *note = [NSButton buttonWithTitle:@"备注" target:self action:@selector(noteClicked:)];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    note.bezelStyle = NSBezelStyleInline;
    note.bordered = YES;

    NSButton *close = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeClicked:)];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.bezelStyle = NSBezelStyleInline;
    close.bordered = NO;

    [banner addSubview:label];
    [banner addSubview:note];
    [banner addSubview:close];
    [container addSubview:banner positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
        [banner.topAnchor constraintEqualToAnchor:container.topAnchor],
        [banner.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [banner.heightAnchor constraintEqualToConstant:36],
        [label.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:12],
        [label.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-8],
        [close.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [note.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-8],
        [note.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:note.leadingAnchor constant:-8],
    ]];

    host.bannerView = banner;
    host.titleLabel = label;
    host.noteButton = note;
    host.closeButton = close;
    [self.hosts addObject:host];
    [self refreshHost:host];
}

- (void)updateFromPayload:(NSDictionary *)payload
              displayName:(NSString *)displayName
                typeLabel:(NSString *)typeLabel {
    CallAlertSettings *settings = [CallAlertSettings sharedSettings];
    if (!settings.alertEnabled || !settings.bannerEnabled) {
        [self dismiss];
        return;
    }
    self.currentPayload = payload;
    self.currentDisplayName = displayName;
    self.currentTypeLabel = typeLabel;

    NSString *state = [payload[@"state"] isKindOfClass:[NSString class]] ? payload[@"state"] : @"";
    [self.autoHideTimer invalidate];
    self.autoHideTimer = nil;
    if ([state isEqualToString:@"ended"] || [state isEqualToString:@"missed"]) {
        self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:4.0
                                                              target:self
                                                            selector:@selector(dismiss)
                                                            userInfo:nil
                                                             repeats:NO];
    }

    NSMutableArray *dead = [NSMutableArray array];
    for (CallAlertBannerHost *h in self.hosts) {
        if (!h.container || !h.bannerView) {
            [dead addObject:h];
            continue;
        }
        [self refreshHost:h];
    }
    [self.hosts removeObjectsInArray:dead];
    [[NSNotificationCenter defaultCenter] postNotificationName:CallAlertDidUpdateNotification object:self];
}

- (void)refreshHost:(CallAlertBannerHost *)host {
    if (!self.currentPayload) {
        host.bannerView.hidden = YES;
        return;
    }
    NSString *state = [self.currentPayload[@"state"] isKindOfClass:[NSString class]]
        ? self.currentPayload[@"state"] : @"";
    NSString *number = [self.currentPayload[@"number"] isKindOfClass:[NSString class]]
        ? self.currentPayload[@"number"] : @"";
    if (number.length == 0) {
        number = [self.currentPayload[@"numberRaw"] isKindOfClass:[NSString class]]
            ? self.currentPayload[@"numberRaw"] : @"";
    }
    NSString *who = self.currentDisplayName.length > 0 ? self.currentDisplayName
        : (number.length > 0 ? number : @"未知号码");
    NSString *prefix = @"来电";
    if ([state isEqualToString:@"active"]) prefix = @"通话中";
    else if ([state isEqualToString:@"missed"]) prefix = @"未接";
    else if ([state isEqualToString:@"ended"]) prefix = @"结束";

    NSMutableString *text = [NSMutableString stringWithFormat:@"📞 %@  %@  %@", prefix, who, number];
    if (self.currentTypeLabel.length > 0) {
        [text appendFormat:@"  ·  %@", self.currentTypeLabel];
    }
    host.titleLabel.stringValue = text;
    host.bannerView.hidden = NO;
    [host.container addSubview:host.bannerView positioned:NSWindowAbove relativeTo:nil];
}

- (void)dismiss {
    [self.autoHideTimer invalidate];
    self.autoHideTimer = nil;
    self.currentPayload = nil;
    self.currentDisplayName = nil;
    self.currentTypeLabel = nil;
    for (CallAlertBannerHost *h in self.hosts) {
        h.bannerView.hidden = YES;
    }
}

- (void)closeClicked:(id)sender {
    (void)sender;
    [self dismiss];
}

- (void)noteClicked:(id)sender {
    (void)sender;
    NSString *number = [self.currentPayload[@"number"] isKindOfClass:[NSString class]]
        ? self.currentPayload[@"number"] : @"";
    if (number.length == 0) {
        number = [self.currentPayload[@"numberRaw"] isKindOfClass:[NSString class]]
            ? self.currentPayload[@"numberRaw"] : @"";
    }
    if (number.length == 0) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"备注来电号码";
    alert.informativeText = number;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];

    SBTextField *field = [SBTextField standardField];
    field.frame = NSMakeRect(0, 0, 240, 24);
    PhonePolicyEntry *existing = [[PhonePolicyStore sharedStore] entryForNumber:number];
    if (existing.displayName.length > 0) {
        field.stringValue = existing.displayName;
    }
    alert.accessoryView = field;
    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        NSString *name = field.stringValue ?: @"";
        [[PhonePolicyStore sharedStore] upsertDisplayName:name
                                                 category:@"personal"
                                                forNumber:number];
        self.currentDisplayName = name;
        for (CallAlertBannerHost *h in self.hosts) {
            [self refreshHost:h];
        }
    }
}

@end
