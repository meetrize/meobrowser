#import "CaptchaHelperBridge.h"

static const NSTimeInterval kHelperTimeoutSeconds = 12.0;

@implementation CaptchaHelperBridge

+ (NSURL *)helperScriptURL {
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *inBundle = [bundle URLForResource:@"captcha_helper" withExtension:@"py" subdirectory:@"CaptchaAssist/helpers"];
    if (inBundle && [[NSFileManager defaultManager] fileExistsAtPath:inBundle.path]) {
        return inBundle;
    }
    // 开发：Makefile 未拷贝时从源码相对路径查找
    NSString *exe = bundle.executablePath;
    if (exe.length > 0) {
        NSString *dev = [[exe stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"../../../SimpleBrowser/CaptchaAssist/helpers/captcha_helper.py"];
        dev = [dev stringByStandardizingPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dev]) {
            return [NSURL fileURLWithPath:dev];
        }
    }
    return nil;
}

+ (BOOL)isHelperAvailable:(NSError **)outError {
    NSURL *script = [self helperScriptURL];
    if (!script) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"CaptchaHelper"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"找不到 captcha_helper.py"}];
        }
        return NO;
    }
    NSString *python = [self python3Path];
    if (!python) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"CaptchaHelper"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"未找到 python3"}];
        }
        return NO;
    }
    return YES;
}

+ (NSString *)python3Path {
    NSArray<NSString *> *candidates = @[
        @"/usr/bin/python3",
        @"/opt/homebrew/bin/python3",
        @"/usr/local/bin/python3",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

+ (void)recognizeTextInImageAtPath:(NSString *)imagePath
                        completion:(void (^)(NSString *, NSError *))completion {
    [self runCommand:@"ocr" argument:imagePath completion:completion];
}

+ (void)evaluateMathExpression:(NSString *)expression
                    completion:(void (^)(NSString *, NSError *))completion {
    [self runCommand:@"math" argument:expression completion:completion];
}

+ (void)runCommand:(NSString *)command
          argument:(NSString *)argument
        completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    if (!completion) {
        return;
    }
    NSError *availError = nil;
    if (![self isHelperAvailable:&availError]) {
        completion(nil, availError);
        return;
    }
    NSURL *script = [self helperScriptURL];
    NSString *python = [self python3Path];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:python];
    task.arguments = @[script.path, command, argument];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            [task launch];
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"CaptchaHelper"
                                                    code:3
                                                userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"启动 Helper 失败"}]);
            });
            return;
        }

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [task waitUntilExit];
            dispatch_semaphore_signal(sem);
        });
        long wait = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHelperTimeoutSeconds * NSEC_PER_SEC)));
        if (wait != 0) {
            [task terminate];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"CaptchaHelper"
                                                    code:4
                                                userInfo:@{NSLocalizedDescriptionKey: @"Helper 执行超时"}]);
            });
            return;
        }

        NSData *outData = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];
        NSData *errData = [[task.standardError fileHandleForReading] readDataToEndOfFile];
        NSString *out = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *err = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";

        dispatch_async(dispatch_get_main_queue(), ^{
            [self parseJSONOutput:out stderr:err exitCode:task.terminationStatus completion:completion];
        });
    });
}

+ (void)parseJSONOutput:(NSString *)output
                stderr:(NSString *)stderrText
              exitCode:(int)exitCode
            completion:(void (^)(NSString *, NSError *))completion {
    NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        NSString *msg = stderrText.length > 0 ? stderrText : [NSString stringWithFormat:@"Helper 退出码 %d", exitCode];
        completion(nil, [NSError errorWithDomain:@"CaptchaHelper" code:5 userInfo:@{NSLocalizedDescriptionKey: msg}]);
        return;
    }
    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        completion(nil, [NSError errorWithDomain:@"CaptchaHelper"
                                            code:6
                                        userInfo:@{NSLocalizedDescriptionKey: @"Helper 返回非 JSON"}]);
        return;
    }
    NSDictionary *dict = (NSDictionary *)json;
    if ([dict[@"ok"] boolValue]) {
        NSString *text = [dict[@"text"] isKindOfClass:[NSString class]] ? dict[@"text"] : @"";
        completion(text, nil);
        return;
    }
    NSString *err = [dict[@"error"] isKindOfClass:[NSString class]] ? dict[@"error"] : @"求解失败";
    completion(nil, [NSError errorWithDomain:@"CaptchaHelper" code:7 userInfo:@{NSLocalizedDescriptionKey: err}]);
}

@end
