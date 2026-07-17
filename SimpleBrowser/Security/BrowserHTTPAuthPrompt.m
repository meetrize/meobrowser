#import "BrowserHTTPAuthPrompt.h"
#import "SBTextField.h"
#import "SBSecureTextField.h"

@implementation BrowserHTTPAuthPromptResult
@end

@interface BrowserHTTPAuthPromptAccessoryView : NSView <NSTextFieldDelegate>
@property (nonatomic, strong) SBTextField *usernameField;
@property (nonatomic, strong) SBSecureTextField *passwordField;
@property (nonatomic, strong) NSButton *rememberCheckbox;
@property (nonatomic, weak) NSAlert *hostAlert;
@end

@implementation BrowserHTTPAuthPromptAccessoryView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }

    self.usernameField = [SBTextField standardField];
    self.usernameField.placeholderString = @"用户名";
    self.usernameField.frame = NSMakeRect(0, 56, NSWidth(frameRect), 24);
    self.usernameField.autoresizingMask = NSViewWidthSizable;
    self.usernameField.delegate = self;

    self.passwordField = [SBSecureTextField standardField];
    self.passwordField.placeholderString = @"密码";
    self.passwordField.frame = NSMakeRect(0, 28, NSWidth(frameRect), 24);
    self.passwordField.autoresizingMask = NSViewWidthSizable;
    self.passwordField.delegate = self;

    self.rememberCheckbox = [NSButton checkboxWithTitle:@"记住此密码"
                                                 target:nil
                                                 action:nil];
    self.rememberCheckbox.frame = NSMakeRect(0, 0, NSWidth(frameRect), 20);
    self.rememberCheckbox.autoresizingMask = NSViewWidthSizable;
    self.rememberCheckbox.state = NSControlStateValueOn;

    [self addSubview:self.usernameField];
    [self addSubview:self.passwordField];
    [self addSubview:self.rememberCheckbox];
    return self;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (commandSelector != @selector(insertNewline:)) {
        return NO;
    }
    if (control == self.usernameField) {
        [self.window makeFirstResponder:self.passwordField];
        return YES;
    }
    if (control == self.passwordField && self.hostAlert) {
        NSButton *loginButton = self.hostAlert.buttons.firstObject;
        [loginButton performClick:nil];
        return YES;
    }
    return NO;
}

@end

@implementation BrowserHTTPAuthPrompt

+ (NSString *)hostDisplayForProtectionSpace:(NSURLProtectionSpace *)space {
    NSString *host = space.host.length > 0 ? space.host : @"此站点";
    NSInteger port = space.port;
    BOOL showPort = port > 0;
    if ([space.protocol.lowercaseString isEqualToString:@"http"] && port == 80) {
        showPort = NO;
    } else if ([space.protocol.lowercaseString isEqualToString:@"https"] && port == 443) {
        showPort = NO;
    }
    if (showPort) {
        return [NSString stringWithFormat:@"%@:%ld", host, (long)port];
    }
    return host;
}

+ (void)presentForChallenge:(NSURLAuthenticationChallenge *)challenge
                   inWindow:(NSWindow *)window
          completionHandler:(void (^)(BrowserHTTPAuthPromptResult * _Nullable result))completionHandler {
    NSParameterAssert(challenge);
    NSParameterAssert(window);
    NSParameterAssert(completionHandler);

    NSURLProtectionSpace *space = challenge.protectionSpace;
    NSString *hostDisplay = [self hostDisplayForProtectionSpace:space];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"登录 “%@”", hostDisplay];
    if (!space.receivesCredentialSecurely) {
        alert.informativeText = @"你的密码将不加密发送。";
        alert.alertStyle = NSAlertStyleWarning;
    } else if (challenge.previousFailureCount > 0) {
        alert.informativeText = @"用户名或密码不正确，请重试。";
        alert.alertStyle = NSAlertStyleWarning;
    } else if (space.realm.length > 0) {
        alert.informativeText = [NSString stringWithFormat:@"需要登录才能访问 “%@”。", space.realm];
    } else {
        alert.informativeText = @"需要登录才能访问此站点。";
    }

    BrowserHTTPAuthPromptAccessoryView *accessory =
        [[BrowserHTTPAuthPromptAccessoryView alloc] initWithFrame:NSMakeRect(0, 0, 280, 80)];
    accessory.hostAlert = alert;

    NSURLCredential *proposed = challenge.proposedCredential;
    if (proposed.user.length > 0) {
        accessory.usernameField.stringValue = proposed.user;
    } else {
        NSURLCredential *stored =
            [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        if (stored.user.length > 0) {
            accessory.usernameField.stringValue = stored.user;
            if (challenge.previousFailureCount == 0 && stored.hasPassword) {
                accessory.passwordField.stringValue = stored.password ?: @"";
            }
        }
    }

    alert.accessoryView = accessory;
    [alert addButtonWithTitle:@"登录"];
    [alert addButtonWithTitle:@"取消"];

    [alert layout];
    dispatch_async(dispatch_get_main_queue(), ^{
        [window makeFirstResponder:accessory.usernameField];
    });

    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) {
            completionHandler(nil);
            return;
        }
        BrowserHTTPAuthPromptResult *result = [[BrowserHTTPAuthPromptResult alloc] init];
        result.username = accessory.usernameField.stringValue ?: @"";
        result.password = accessory.passwordField.stringValue ?: @"";
        result.rememberPassword = (accessory.rememberCheckbox.state == NSControlStateValueOn);
        completionHandler(result);
    }];
}

@end
