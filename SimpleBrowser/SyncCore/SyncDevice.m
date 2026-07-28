#import "SyncDevice.h"

@implementation SyncDevice

+ (NSString *)deviceIdFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [root stringByAppendingPathComponent:@"MeoBrowser"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"sync-device-id.txt"];
}

+ (NSString *)deviceId {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [self deviceIdFilePath];
        NSString *existing = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        existing = [existing stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (existing.length > 0) {
            cached = existing;
        } else {
            NSString *uuid = [[NSUUID UUID] UUIDString];
            cached = [NSString stringWithFormat:@"mac-%@", uuid];
            [cached writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    });
    return cached;
}

@end
