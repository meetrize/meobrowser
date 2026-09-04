#import "PagePackSeedInstaller.h"
#import "PagePackModels.h"
#import "PagePackStore.h"

static NSString * const kMapsOverlaySeedName = @"maps-overlay-calibration";

@implementation PagePackSeedInstaller

+ (NSURL *)bundledSeedsRootURL {
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:@"BundledPacks" withExtension:nil];
    if (url) {
        return url;
    }
    // 开发态：从源码树旁路读取（未拷进 Resources 时）
    NSString *exe = bundle.executablePath;
    if (exe.length == 0) {
        return nil;
    }
    // …/MeoBrowser.app/Contents/MacOS/MeoBrowser → 不保证旁路；仅 Bundle 路径为准
    return nil;
}

+ (NSURL *)seedDirectoryURLNamed:(NSString *)seedFolderName {
    if (seedFolderName.length == 0) {
        return nil;
    }
    NSURL *root = [self bundledSeedsRootURL];
    if (!root) {
        return nil;
    }
    return [root URLByAppendingPathComponent:seedFolderName isDirectory:YES];
}

+ (void)installBundledSeedsIfNeeded {
    NSError *error = nil;
    if (![self installSeedNamed:kMapsOverlaySeedName force:NO error:&error]) {
        if (error) {
            NSLog(@"[PagePackSeed] install %@ failed: %@", kMapsOverlaySeedName, error);
        }
    }
}

+ (BOOL)installSeedNamed:(NSString *)seedFolderName force:(BOOL)force error:(NSError **)error {
    NSURL *dirURL = [self seedDirectoryURLNamed:seedFolderName];
    if (!dirURL) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"未找到内置种子目录 BundledPacks"}];
        }
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dirURL.path isDirectory:&isDir] || !isDir) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"种子目录不存在"}];
        }
        return NO;
    }

    NSURL *manifestURL = [dirURL URLByAppendingPathComponent:@"manifest.json"];
    NSData *manifestData = [NSData dataWithContentsOfURL:manifestURL options:0 error:error];
    if (!manifestData) {
        return NO;
    }
    id json = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"种子 manifest 无效"}];
        }
        return NO;
    }

    PagePack *pack = [PagePack packWithDictionary:json];
    if (!pack || pack.packID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法解析种子 Pack"}];
        }
        return NO;
    }

    PagePackStore *store = [PagePackStore sharedStore];
    PagePack *existing = [store packWithID:pack.packID];
    if (existing && !force) {
        BOOL isBundledSeed = [existing.sourceURL hasPrefix:@"bundle://"] ||
                             [pack.sourceURL hasPrefix:@"bundle://"];
        BOOL versionNewer = NO;
        if (isBundledSeed && pack.version.length > 0) {
            NSString *oldVer = existing.version.length > 0 ? existing.version : @"0";
            versionNewer = [pack.version compare:oldVer options:NSNumericSearch] == NSOrderedDescending;
        }
        if (!versionNewer) {
            // 已安装且非升级：不覆盖用户修改
            return YES;
        }
        NSLog(@"[PagePackSeed] upgrading %@ %@ → %@", pack.packID, existing.version ?: @"?", pack.version);
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (!existing) {
        pack.createdAt = pack.createdAt > 0 ? pack.createdAt : now;
    } else {
        pack.createdAt = existing.createdAt > 0 ? existing.createdAt : now;
        // 升级时保留用户启停
        pack.enabled = existing.enabled;
    }
    pack.updatedAt = now;
    if (pack.sourceURL.length == 0) {
        pack.sourceURL = [NSString stringWithFormat:@"bundle://%@", seedFolderName];
    }
    if (pack.author.length == 0) {
        pack.author = @"MeoBrowser";
    }

    if (![store upsertPack:pack error:error]) {
        return NO;
    }

    for (PagePackFile *file in pack.files) {
        NSURL *fileURL = [dirURL URLByAppendingPathComponent:file.name];
        NSString *content = [NSString stringWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:nil];
        if (!content) {
            content = @"";
        }
        if (![store writeContent:content fileName:file.name inPack:pack.packID error:error]) {
            return NO;
        }
    }
    NSLog(@"[PagePackSeed] %@ %@", force ? @"restored" : @"installed", pack.packID);
    return YES;
}

@end
