#import "CloudSyncCapability.h"
#import "CloudSyncSettings.h"
#import <Security/Security.h>

@implementation CloudSyncCapability

+ (NSDictionary *)signingEntitlements {
    static NSDictionary *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SecCodeRef code = NULL;
        OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &code);
        if (status != errSecSuccess || !code) {
            cached = @{};
            return;
        }
        CFDictionaryRef info = NULL;
        status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
        CFRelease(code);
        if (status != errSecSuccess || !info) {
            cached = @{};
            return;
        }
        NSDictionary *dict = CFBridgingRelease(info);
        id entitlements = dict[(__bridge NSString *)kSecCodeInfoEntitlementsDict];
        if ([entitlements isKindOfClass:[NSDictionary class]]) {
            cached = entitlements;
        } else {
            cached = @{};
        }
    });
    return cached;
}

+ (BOOL)isCloudKitEntitled {
    if (@available(macOS 14.0, *)) {
        // continue
    } else {
        return NO;
    }
    NSDictionary *ent = [self signingEntitlements];
    id services = ent[@"com.apple.developer.icloud-services"];
    BOOL hasCloudKitService = NO;
    if ([services isKindOfClass:[NSArray class]]) {
        hasCloudKitService = [services containsObject:@"CloudKit"];
    } else if ([services isKindOfClass:[NSString class]]) {
        hasCloudKitService = [services isEqualToString:@"CloudKit"];
    }
    if (!hasCloudKitService) {
        return NO;
    }
    id containers = ent[@"com.apple.developer.icloud-container-identifiers"];
    if (![containers isKindOfClass:[NSArray class]]) {
        return NO;
    }
    return [containers containsObject:CloudSyncContainerIdentifier];
}

+ (NSString *)unavailableReason {
    if (@available(macOS 14.0, *)) {
        // ok
    } else {
        return @"iCloud 同步需要 macOS 14 或更高版本";
    }
    if ([self isCloudKitEntitled]) {
        return @"";
    }
    return @"当前构建未启用 CloudKit 签名（本地 adhoc 常见）。"
           @"请用开发者证书签名并配置容器 iCloud.com.example.MeoBrowser 后再同步。";
}

@end
