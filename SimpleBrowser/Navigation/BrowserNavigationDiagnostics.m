#import "BrowserNavigationDiagnostics.h"

static NSString * const kMeoNavigationDiagnosticsKey = @"MeoBrowserNavigationDiagnostics";

static FILE *sNavLogFile = NULL;

// 与 tab-ui.log 同目录，方便一起 tail -f、一起发排查：
//   tail -f ~/Library/Logs/MeoBrowser/nav.log
static void MeoNavEnsureLogFile(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MeoBrowser"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString *path = [dir stringByAppendingPathComponent:@"nav.log"];
        sNavLogFile = fopen(path.fileSystemRepresentation, "a");
        if (sNavLogFile) {
            fprintf(sNavLogFile, "--- MeoBrowser nav log started %s ---\n",
                    [[NSDate date].description UTF8String] ?: "");
            fflush(sNavLogFile);
        }
    });
}

BOOL BrowserNavigationDiagnosticsEnabled(void) {
    // 默认关；排查导航时：
    //   defaults write com.example.MeoBrowser MeoBrowserNavigationDiagnostics -bool YES
    return [NSUserDefaults.standardUserDefaults boolForKey:kMeoNavigationDiagnosticsKey];
}

void BrowserNavigationLog(NSString *format, ...) {
    if (!BrowserNavigationDiagnosticsEnabled() || format.length == 0) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[MeoNav] %@", message);
    // 落盘：响应变慢时把 ~/Library/Logs/MeoBrowser/nav.log 发回即可分析
    MeoNavEnsureLogFile();
    if (sNavLogFile) {
        NSString *line = [NSString stringWithFormat:@"%@ [MeoNav] %@\n",
                          [NSDate date], message];
        fputs(line.UTF8String, sNavLogFile);
        fflush(sNavLogFile);
    }
}
