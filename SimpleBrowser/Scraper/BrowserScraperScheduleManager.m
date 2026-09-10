#import "BrowserScraperScheduleManager.h"
#import <AppKit/AppKit.h>

@implementation BrowserScraperScheduleManager

+ (instancetype)sharedManager {
    static BrowserScraperScheduleManager *mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[self alloc] init];
    });
    return mgr;
}

+ (NSString *)runnerExecutablePath {
    NSString *inBundle = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Contents/MacOS/MeoScrapeRunner"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:inBundle]) {
        return inBundle;
    }
    // 开发期回退：用主程序 + 参数
    return [NSBundle mainBundle].executablePath ?: @"";
}

+ (NSString *)agentsDirectory {
    NSString *home = NSHomeDirectory();
    NSString *dir = [home stringByAppendingPathComponent:@"Library/LaunchAgents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)plistPathForLabel:(NSString *)label {
    return [[[self class] agentsDirectory] stringByAppendingPathComponent:[label stringByAppendingPathExtension:@"plist"]];
}

- (BOOL)unloadScheduleForRecipeID:(NSString *)recipeID label:(NSString *)label error:(NSError **)error {
    (void)recipeID;
    NSString *lab = label.length > 0 ? label : [NSString stringWithFormat:@"com.example.MeoBrowser.scrape.%@", recipeID];
    NSString *plist = [self plistPathForLabel:lab];
    NSTask *bootout = [[NSTask alloc] init];
    bootout.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    bootout.arguments = @[ @"bootout", [NSString stringWithFormat:@"gui/%d/%@", getuid(), lab] ];
    bootout.standardOutput = [NSPipe pipe];
    bootout.standardError = [NSPipe pipe];
    [bootout launchAndReturnError:nil];
    [bootout waitUntilExit];
    [[NSFileManager defaultManager] removeItemAtPath:plist error:nil];
    return YES;
}

- (BOOL)applyScheduleForRecipe:(BrowserScraperRecipe *)recipe error:(NSError **)error {
    NSString *label = recipe.schedule.launchAgentLabel;
    if (label.length == 0) {
        label = [NSString stringWithFormat:@"com.example.MeoBrowser.scrape.%@", recipe.recipeID];
        recipe.schedule.launchAgentLabel = label;
    }
    if (!recipe.schedule.enabled) {
        return [self unloadScheduleForRecipeID:recipe.recipeID label:label error:error];
    }
    NSString *runner = [[self class] runnerExecutablePath];
    if (runner.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"BrowserScraper" code:40 userInfo:@{NSLocalizedDescriptionKey:@"找不到 MeoScrapeRunner"}];
        return NO;
    }
    NSInteger interval = MAX(60, recipe.schedule.intervalMinutes * 60);
    BOOL isHelper = [runner.lastPathComponent isEqualToString:@"MeoScrapeRunner"];
    NSArray *programArgs = isHelper
        ? @[ runner, [NSString stringWithFormat:@"--recipe-id=%@", recipe.recipeID] ]
        : @[ runner, [NSString stringWithFormat:@"--scrape-recipe-id=%@", recipe.recipeID] ];

    NSDictionary *plist = @{
        @"Label": label,
        @"ProgramArguments": programArgs,
        @"StartInterval": @(interval),
        @"RunAtLoad": @NO,
        @"StandardOutPath": [NSTemporaryDirectory() stringByAppendingPathComponent:[label stringByAppendingString:@".out.log"]],
        @"StandardErrorPath": [NSTemporaryDirectory() stringByAppendingPathComponent:[label stringByAppendingString:@".err.log"]],
    };
    NSString *plistPath = [self plistPathForLabel:label];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    if (![data writeToFile:plistPath options:NSDataWritingAtomic error:error]) return NO;

    // bootout then bootstrap
    [self unloadScheduleForRecipeID:recipe.recipeID label:label error:nil];
    NSTask *bootstrap = [[NSTask alloc] init];
    bootstrap.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    bootstrap.arguments = @[ @"bootstrap", [NSString stringWithFormat:@"gui/%d", getuid()], plistPath ];
    bootstrap.standardOutput = [NSPipe pipe];
    bootstrap.standardError = [NSPipe pipe];
    if (![bootstrap launchAndReturnError:error]) return NO;
    [bootstrap waitUntilExit];
    if (bootstrap.terminationStatus != 0) {
        // 兼容旧 launchctl load
        NSTask *load = [[NSTask alloc] init];
        load.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
        load.arguments = @[ @"load", @"-w", plistPath ];
        [load launchAndReturnError:nil];
        [load waitUntilExit];
    }
    return YES;
}

@end
