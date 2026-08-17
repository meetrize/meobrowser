#import "BrowserNavigationDiagnostics.h"

static NSString * const kMeoNavigationDiagnosticsKey = @"MeoBrowserNavigationDiagnostics";

BOOL BrowserNavigationDiagnosticsEnabled(void) {
#if DEBUG
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kMeoNavigationDiagnosticsKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kMeoNavigationDiagnosticsKey];
#else
    return [NSUserDefaults.standardUserDefaults boolForKey:kMeoNavigationDiagnosticsKey];
#endif
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
}
