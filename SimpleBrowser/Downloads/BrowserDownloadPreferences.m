#import "BrowserDownloadPreferences.h"

NSNotificationName const BrowserDownloadPreferencesDidChangeNotification =
    @"BrowserDownloadPreferencesDidChangeNotification";

static NSString * const kDownloadDirectoryPathKey = @"MeoBrowserDownloadDirectoryPath";

static BOOL MeoDirectoryIsUsable(NSURL *url) {
    if (!url.isFileURL || url.path.length == 0) {
        return NO;
    }
    BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:url.path isDirectory:&isDir] || !isDir) {
        return NO;
    }
    return [fm isWritableFileAtPath:url.path];
}

@implementation BrowserDownloadPreferences

+ (instancetype)sharedPreferences {
    static BrowserDownloadPreferences *prefs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[self alloc] init];
    });
    return prefs;
}

- (nullable NSURL *)systemDownloadsDirectoryURL {
    NSError *error = nil;
    return [NSFileManager.defaultManager URLForDirectory:NSDownloadsDirectory
                                                inDomain:NSUserDomainMask
                                       appropriateForURL:nil
                                                  create:YES
                                                   error:&error];
}

- (nullable NSURL *)customDirectoryURL {
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:kDownloadDirectoryPathKey];
    if (path.length == 0) {
        return nil;
    }
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

- (void)setCustomDirectoryURL:(NSURL *)customDirectoryURL {
    NSString *newPath = nil;
    if (customDirectoryURL.isFileURL && customDirectoryURL.path.length > 0) {
        newPath = customDirectoryURL.path;
    } else if (customDirectoryURL.path.length > 0) {
        newPath = customDirectoryURL.path;
    }
    NSString *oldPath = [NSUserDefaults.standardUserDefaults stringForKey:kDownloadDirectoryPathKey];
    BOOL bothEmpty = (newPath.length == 0 && oldPath.length == 0);
    if (bothEmpty || [newPath isEqualToString:oldPath]) {
        return;
    }
    if (newPath.length == 0) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kDownloadDirectoryPathKey];
    } else {
        [NSUserDefaults.standardUserDefaults setObject:newPath forKey:kDownloadDirectoryPathKey];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserDownloadPreferencesDidChangeNotification
                                                        object:self];
}

- (nullable NSURL *)effectiveDirectoryURL {
    NSURL *custom = self.customDirectoryURL;
    if (custom && MeoDirectoryIsUsable(custom)) {
        return custom;
    }
    return [self systemDownloadsDirectoryURL];
}

- (BOOL)usesCustomDirectory {
    return self.customDirectoryURL != nil;
}

- (BOOL)customDirectoryIsReachable {
    NSURL *custom = self.customDirectoryURL;
    return custom != nil && MeoDirectoryIsUsable(custom);
}

- (void)resetToSystemDownloadsDirectory {
    self.customDirectoryURL = nil;
}

- (NSString *)displayPath {
    NSURL *url = self.customDirectoryURL ?: [self systemDownloadsDirectoryURL];
    if (url.path.length == 0) {
        return @"~/Downloads";
    }
    return [url.path stringByAbbreviatingWithTildeInPath];
}

@end
