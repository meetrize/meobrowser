#import "PhoneChatWindowController.h"
#import "PhoneChatStore.h"
#import "PhoneChatModels.h"
#import "PhoneNotificationItem.h"
#import "PhoneNotificationInboxSettings.h"
#import "CompanionChannel.h"
#import "BrowserTransientToast.h"
#import "SBTextField.h"

@interface PhoneChatWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, copy) NSString *contactTitle;
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, copy, nullable) NSString *lastNotificationID;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) SBTextField *inputField;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSArray<PhoneChatMessage *> *messages;
@property (nonatomic, assign) BOOL sendInFlight;
@property (nonatomic, copy, nullable) NSString *pendingRequestID;
@end

@implementation PhoneChatWindowController

static NSMutableDictionary<NSString *, PhoneChatWindowController *> *sOpenWindows;

+ (void)initialize {
    if (self == [PhoneChatWindowController class]) {
        sOpenWindows = [NSMutableDictionary dictionary];
    }
}

+ (void)openOrFocusForNotificationItem:(PhoneNotificationItem *)item {
    if (!item) {
        return;
    }
    // 若会话尚无消息，用当前通知正文作首条入站，避免空窗
    if (item.body.length > 0 && item.title.length > 0) {
        [[PhoneChatStore sharedStore] appendInboundIfNeededForPackageName:item.packageName
                                                                    title:item.title
                                                                     body:item.body
                                                           notificationID:item.itemID
                                                               postTimeMs:item.postTimeMs];
    }
    [self openOrFocusForContact:item.title
                    packageName:item.packageName
                 notificationID:item.itemID];
}

+ (void)openOrFocusForContact:(NSString *)contact
                  packageName:(NSString *)packageName
               notificationID:(NSString *)notificationID {
    NSString *pkg = packageName.length > 0 ? packageName : PhoneChatStoreWeChatPackageName;
    NSString *title = [contact stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (title.length == 0) {
        return;
    }
    PhoneChatThread *thread = [[PhoneChatStore sharedStore] ensureThreadForPackageName:pkg title:title];
    PhoneChatWindowController *existing = sOpenWindows[thread.threadID];
    if (existing) {
        existing.lastNotificationID = notificationID;
        [existing reloadMessagesScrollingToEnd:YES];
        [existing.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [existing focusInput];
        return;
    }
    PhoneChatWindowController *wc = [[PhoneChatWindowController alloc] initWithThread:thread
                                                                      notificationID:notificationID];
    sOpenWindows[thread.threadID] = wc;
    [wc showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [wc focusInput];
}

- (instancetype)initWithThread:(PhoneChatThread *)thread notificationID:(NSString *)notificationID {
    NSRect rect = NSMakeRect(0, 0, 420, 560);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = [NSString stringWithFormat:@"微信 · %@", thread.title];
    window.minSize = NSMakeSize(320, 360);
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        _threadID = thread.threadID;
        _contactTitle = thread.title;
        _packageName = thread.packageName;
        _lastNotificationID = notificationID;
        _messages = @[];
        [self buildUI];
        [self reloadMessagesScrollingToEnd:YES];
        [[PhoneChatStore sharedStore] markThreadRead:thread.threadID];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storeDidChange:)
                                                     name:PhoneChatStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(weChatReplyDidFinish:)
                                                     name:CompanionWeChatReplyDidFinishNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowWillClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:window];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    NSTextField *hint = [NSTextField wrappingLabelWithString:
                         @"仅含手机通知镜像与经 Meo 发出的回复，不是完整微信聊天记录。"];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.selectable = NO;
    [content addSubview:hint];
    self.hintLabel = hint;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.drawsBackground = YES;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.headerView = nil;
    table.rowHeight = 48;
    table.usesAutomaticRowHeights = YES;
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    table.backgroundColor = [NSColor textBackgroundColor];
    if (@available(macOS 11.0, *)) {
        table.style = NSTableViewStylePlain;
    }
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"msg"];
    col.width = 380;
    [table addTableColumn:col];
    table.dataSource = self;
    table.delegate = self;
    scroll.documentView = table;
    [content addSubview:scroll];
    self.scrollView = scroll;
    self.tableView = table;

    SBTextField *field = [SBTextField standardField];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholderString = @"输入回复，⌘↩ 发送";
    field.delegate = self;
    field.target = self;
    field.action = @selector(sendClicked:);
    [content addSubview:field];
    self.inputField = field;

    NSButton *send = [NSButton buttonWithTitle:@"发送" target:self action:@selector(sendClicked:)];
    send.translatesAutoresizingMaskIntoConstraints = NO;
    send.bezelStyle = NSBezelStyleRounded;
    send.keyEquivalent = @"\r";
    send.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [content addSubview:send];
    self.sendButton = send;

    [NSLayoutConstraint activateConstraints:@[
        [hint.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],

        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [scroll.bottomAnchor constraintEqualToAnchor:field.topAnchor constant:-10],

        [field.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [field.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
        [field.heightAnchor constraintEqualToConstant:28],
        [field.trailingAnchor constraintEqualToAnchor:send.leadingAnchor constant:-8],

        [send.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [send.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
        [send.widthAnchor constraintEqualToConstant:64],
    ]];
}

- (void)focusInput {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window makeFirstResponder:self.inputField];
    });
}

- (void)reloadMessagesScrollingToEnd:(BOOL)scrollToEnd {
    self.messages = [[PhoneChatStore sharedStore] messagesForThreadID:self.threadID];
    [self.tableView reloadData];
    if (scrollToEnd && self.messages.count > 0) {
        NSInteger last = (NSInteger)self.messages.count - 1;
        [self.tableView scrollRowToVisible:last];
    }
    PhoneChatThread *t = [[PhoneChatStore sharedStore] threadForID:self.threadID];
    if (t.title.length > 0) {
        self.contactTitle = t.title;
        self.window.title = [NSString stringWithFormat:@"微信 · %@", t.title];
    }
}

#pragma mark - Actions

- (void)sendClicked:(id)sender {
    (void)sender;
    if (self.sendInFlight) {
        [BrowserTransientToast showMessage:@"正在发送…" inWindow:self.window duration:2.0];
        return;
    }
    if (![PhoneNotificationInboxSettings sharedSettings].wechatReplyEnabled) {
        [BrowserTransientToast showMessage:@"请先在「登录助手」开启微信回复（实验）"
                                  inWindow:self.window
                                  duration:2.4];
        return;
    }
    CompanionChannel *channel = [CompanionChannel sharedChannel];
    if (channel.state != CompanionChannelStateConnected) {
        [BrowserTransientToast showMessage:@"请先连接手机 Companion" inWindow:self.window duration:2.4];
        return;
    }
    NSString *text = [self.inputField.stringValue
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        [BrowserTransientToast showMessage:@"回复内容不能为空" inWindow:self.window duration:2.0];
        return;
    }
    if (text.length > 1000) {
        [BrowserTransientToast showMessage:@"回复过长（最多 1000 字）" inWindow:self.window duration:2.0];
        return;
    }

    NSString *requestID = [[NSUUID UUID] UUIDString];
    PhoneChatMessage *msg = [[PhoneChatStore sharedStore] beginOutboundMessageForThreadID:self.threadID
                                                                                     text:text
                                                                                requestID:requestID];
    if (!msg) {
        [BrowserTransientToast showMessage:@"无法创建本地消息" inWindow:self.window duration:2.0];
        return;
    }
    self.sendInFlight = YES;
    self.pendingRequestID = requestID;
    self.sendButton.enabled = NO;
    self.inputField.stringValue = @"";
    [self reloadMessagesScrollingToEnd:YES];

    BOOL ok = [channel requestWeChatReplyWithRequestID:requestID
                                               contact:self.contactTitle
                                                  text:text
                                        notificationId:self.lastNotificationID];
    if (!ok) {
        [[PhoneChatStore sharedStore] markOutboundFailedForRequestID:requestID];
        self.sendInFlight = NO;
        self.pendingRequestID = nil;
        self.sendButton.enabled = YES;
        [BrowserTransientToast showMessage:@"回复请求发送失败（未连接或未配对）"
                                  inWindow:self.window
                                  duration:2.4];
        [self reloadMessagesScrollingToEnd:YES];
        [self focusInput];
    }
}

- (void)weChatReplyDidFinish:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo ?: @{};
    NSString *requestID = info[CompanionWeChatReplyRequestIDKey];
    BOOL ok = [info[CompanionWeChatReplyOKKey] boolValue];
    if (requestID.length > 0) {
        if (ok) {
            [[PhoneChatStore sharedStore] markOutboundSentForRequestID:requestID];
        } else {
            [[PhoneChatStore sharedStore] markOutboundFailedForRequestID:requestID];
        }
    }

    BOOL mine = self.pendingRequestID.length > 0 &&
        (requestID.length == 0 || [requestID isEqualToString:self.pendingRequestID]);
    if (!mine) {
        [self reloadMessagesScrollingToEnd:NO];
        return;
    }

    if (ok) {
        [BrowserTransientToast showMessage:@"已发送" inWindow:self.window duration:1.8];
    } else {
        NSString *message = info[CompanionWeChatReplyMessageKey] ?: @"回复失败";
        NSString *code = info[CompanionWeChatReplyCodeKey] ?: @"";
        NSString *toast = message;
        if ([code isEqualToString:@"disabled"]) {
            toast = @"手机未开启「微信回复」实验开关";
        } else if ([code isEqualToString:@"a11y_required"]) {
            toast = @"请在手机开启 Meo「微信回复」无障碍";
        } else if ([code isEqualToString:@"background_launch_blocked"]) {
            toast = @"请在手机开启「后台弹出界面」";
        }
        [BrowserTransientToast showMessage:toast inWindow:self.window duration:2.8];
    }
    self.sendInFlight = NO;
    self.pendingRequestID = nil;
    self.sendButton.enabled = YES;
    [self reloadMessagesScrollingToEnd:YES];
    [self focusInput];
}

- (void)storeDidChange:(NSNotification *)notification {
    NSString *tid = notification.userInfo[PhoneChatStoreThreadIDKey];
    if (tid.length > 0 && ![tid isEqualToString:self.threadID]) {
        return;
    }
    [self reloadMessagesScrollingToEnd:YES];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (self.threadID.length > 0) {
        [sOpenWindows removeObjectForKey:self.threadID];
    }
}

#pragma mark - NSTextFieldDelegate

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)control;
    (void)textView;
    if (commandSelector == @selector(insertNewline:)) {
        // 普通回车发送（单行输入）
        [self sendClicked:nil];
        return YES;
    }
    return NO;
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.messages.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (row < 0 || row >= (NSInteger)self.messages.count) {
        return nil;
    }
    PhoneChatMessage *msg = self.messages[(NSUInteger)row];
    NSString *cid = @"PhoneChatBubble";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:cid owner:self];
    NSTextField *label = nil;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 380, 40)];
        cell.identifier = cid;
        label = [NSTextField wrappingLabelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.identifier = @"bubbleLabel";
        label.font = [NSFont systemFontOfSize:13];
        label.selectable = YES;
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
            [label.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-6],
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
        ]];
    } else {
        for (NSView *v in cell.subviews) {
            if ([v.identifier isEqualToString:@"bubbleLabel"]) {
                label = (NSTextField *)v;
                break;
            }
        }
    }
    if (!label) {
        return cell;
    }

    NSString *prefix = msg.direction == PhoneChatDirectionOut ? @"我" : self.contactTitle;
    NSString *status = @"";
    if (msg.direction == PhoneChatDirectionOut) {
        switch (msg.status) {
            case PhoneChatOutboundStatusSending: status = @"（发送中）"; break;
            case PhoneChatOutboundStatusFailed: status = @"（失败）"; break;
            default: break;
        }
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    NSString *time = [fmt stringFromDate:msg.createdAt] ?: @"";
    label.stringValue = [NSString stringWithFormat:@"%@ %@%@\n%@", prefix, time, status, msg.text ?: @""];
    label.alignment = msg.direction == PhoneChatDirectionOut ? NSTextAlignmentRight : NSTextAlignmentLeft;
    label.textColor = msg.status == PhoneChatOutboundStatusFailed
        ? [NSColor systemRedColor]
        : [NSColor labelColor];
    return cell;
}

@end
