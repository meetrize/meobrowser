#import "FormMemoPageSaveCoordinator.h"
#import "BrowserWindowController.h"
#import "FormMemo.h"
#import "FormMemoStore.h"
#import "FormMemoPreferences.h"
#import "BrowserTransientToast.h"
#import "BrowserRiskHostPolicy.h"

@interface FormMemoPageSaveCoordinator ()
@property (nonatomic, weak) BrowserWindowController *windowController;
@property (nonatomic, assign) BOOL promptVisible;
@end

@implementation FormMemoPageSaveCoordinator

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
    }
    return self;
}

- (NSString *)hostKeyForURL:(NSURL *)url {
    if (!url) {
        return @"";
    }
    if (url.isFileURL) {
        return @"file";
    }
    return url.host.lowercaseString ?: @"";
}

- (nullable NSString *)pathPrefixForURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    if (url.isFileURL) {
        NSString *last = url.lastPathComponent;
        return last.length > 0 ? last : nil;
    }
    NSString *path = url.path ?: @"";
    if (path.length == 0 || [path isEqualToString:@"/"]) {
        return nil;
    }
    return path;
}

- (BOOL)valueLooksSensitive:(NSString *)value label:(NSString *)label {
    if (value.length > 500) {
        return YES;
    }
    NSString *blob = [[NSString stringWithFormat:@"%@ %@", label ?: @"", value ?: @""] lowercaseString];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"身份证|password|密码|银行卡|credit.?card|社保号"
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    if (!re) {
        return NO;
    }
    return [re numberOfMatchesInString:blob options:0 range:NSMakeRange(0, blob.length)] > 0;
}

- (void)handleSaveFieldMessage:(NSDictionary *)body fromWebView:(WKWebView *)webView {
    if (![FormMemoPreferences inlineSaveEnabled]) {
        return;
    }
    if (self.promptVisible) {
        return;
    }

    NSURL *url = webView.URL;
    if (!url && [body[@"href"] isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)body[@"href"]];
    }
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        return;
    }

    NSString *selector = body[@"selector"];
    NSString *label = body[@"label"];
    NSString *value = body[@"value"];
    if (![selector isKindOfClass:[NSString class]] || selector.length == 0) {
        return;
    }
    if (![value isKindOfClass:[NSString class]]) {
        value = @"";
    }
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        return;
    }
    if (![label isKindOfClass:[NSString class]] || label.length == 0) {
        label = @"字段";
    }

    NSString *host = [self hostKeyForURL:url];
    if (host.length == 0) {
        [BrowserTransientToast showMessage:@"无法保存：缺少主机"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        return;
    }

    BOOL needsConfirm = ![FormMemoPreferences hasCompletedInlineSaveOnce]
        || [self valueLooksSensitive:value label:label];

    if (needsConfirm) {
        [self confirmAndSaveSelector:selector
                               label:label
                               value:value
                                host:host
                                 url:url
                       isFirstDevice:![FormMemoPreferences hasCompletedInlineSaveOnce]];
    } else {
        [self commitSelector:selector label:label value:value host:host url:url];
    }
}

- (void)confirmAndSaveSelector:(NSString *)selector
                         label:(NSString *)label
                         value:(NSString *)value
                          host:(NSString *)host
                           url:(NSURL *)url
                 isFirstDevice:(BOOL)isFirstDevice {
    NSWindow *window = self.windowController.window;
    if (!window) {
        return;
    }
    self.promptVisible = YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"保存到站点备忘？";
    if (isFirstDevice) {
        alert.informativeText = [NSString stringWithFormat:
                                 @"将「%@」保存为明文本地备忘（不会上传）。\n密码请使用登录助手，勿写入站点备忘。",
                                 label];
    } else {
        alert.informativeText = [NSString stringWithFormat:
                                 @"「%@」的内容较长或可能含敏感信息，确认以明文保存到本地站点备忘？",
                                 label];
    }
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.promptVisible = NO;
        if (returnCode != NSAlertFirstButtonReturn) {
            return;
        }
        [strongSelf commitSelector:selector label:label value:value host:host url:url];
    }];
}

- (void)commitSelector:(NSString *)selector
                 label:(NSString *)label
                 value:(NSString *)value
                  host:(NSString *)host
                   url:(NSURL *)url {
    FormMemoStore *store = [FormMemoStore sharedStore];
    FormMemo *memo = [store defaultMemoMatchingURL:url];
    if (!memo) {
        NSArray<FormMemo *> *matched = [store memosMatchingURL:url];
        memo = matched.firstObject;
    }

    BOOL created = NO;
    if (!memo) {
        created = YES;
        NSString *title = [NSString stringWithFormat:@"%@ 备忘", host];
        memo = [FormMemo memoWithHost:host title:title];
        memo.pathPrefix = [self pathPrefixForURL:url];
        memo.isDefault = YES;
        memo.fields = @[];
    } else {
        memo = [memo copy];
    }

    NSMutableArray<FormMemoField *> *fields = [NSMutableArray arrayWithCapacity:memo.fields.count + 1];
    BOOL updatedExisting = NO;
    for (FormMemoField *existing in memo.fields) {
        FormMemoField *copy = [existing copy];
        if (!updatedExisting && [copy.selector isEqualToString:selector]) {
            copy.value = value;
            if (label.length > 0) {
                copy.label = label;
            }
            copy.enabled = YES;
            updatedExisting = YES;
        }
        [fields addObject:copy];
    }
    if (!updatedExisting) {
        [fields addObject:[FormMemoField fieldWithLabel:label selector:selector value:value]];
    }
    memo.fields = fields;
    memo.updatedAt = [NSDate date].timeIntervalSince1970;

    NSError *error = nil;
    if (![store upsertMemo:memo error:&error]) {
        [BrowserTransientToast showMessage:error.localizedDescription ?: @"保存失败"
                                  inWindow:self.windowController.window
                                  duration:2.5];
        return;
    }
    if (created || memo.isDefault) {
        [store setDefaultMemoID:memo.memoID error:nil];
    }
    [FormMemoPreferences setHasCompletedInlineSaveOnce:YES];

    NSString *toast = updatedExisting ? @"已更新站点备忘字段" : @"已保存到站点备忘";
    [BrowserTransientToast showMessage:toast
                              inWindow:self.windowController.window
                              duration:2.0];
}

@end
