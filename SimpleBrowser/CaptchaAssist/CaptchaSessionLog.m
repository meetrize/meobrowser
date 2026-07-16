#import "CaptchaSessionLog.h"
#import "CaptchaDetection.h"
#import "CaptchaAssistPreferences.h"

@implementation CaptchaSessionLog

+ (NSURL *)sessionsRootDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *appSupport = [fm URLForDirectory:NSApplicationSupportDirectory
                                   inDomain:NSUserDomainMask
                          appropriateForURL:nil
                                     create:YES
                                      error:nil];
    NSURL *root = [appSupport URLByAppendingPathComponent:@"MeoBrowser/CaptchaAssist/sessions" isDirectory:YES];
    [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}

+ (NSURL *)writeSessionWithDetection:(CaptchaDetection *)detection
                               image:(NSImage *)image
                                note:(NSString *)note
                               error:(NSError **)outError {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSURL *dir = [[self sessionsRootDirectory] URLByAppendingPathComponent:uuid isDirectory:YES];
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:outError]) {
        return nil;
    }

    NSMutableDictionary *meta = [@{
        @"id": uuid,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
    } mutableCopy];
    if (detection) {
        meta[@"detection"] = [detection dictionaryRepresentation];
    }
    if (note.length > 0) {
        meta[@"note"] = note;
    }
    if (image) {
        meta[@"hasImage"] = @YES;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted error:outError];
    if (!json) {
        return nil;
    }
    NSURL *metaURL = [dir URLByAppendingPathComponent:@"meta.json"];
    if (![json writeToURL:metaURL options:NSDataWritingAtomic error:outError]) {
        return nil;
    }

    if (image) {
        NSData *png = [self PNGDataFromImage:image];
        if (png) {
            NSURL *imgURL = [dir URLByAppendingPathComponent:@"image.png"];
            [png writeToURL:imgURL options:NSDataWritingAtomic error:nil];
        }
    }

    [self pruneOldSessionsKeeping:[CaptchaAssistPreferences maxSessionCount]];
    return dir;
}

+ (NSData *)PNGDataFromImage:(NSImage *)image {
    NSRect rect = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&rect context:nil hints:nil];
    if (!cg) {
        return nil;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

+ (void)pruneOldSessionsKeeping:(NSInteger)maxCount {
    if (maxCount < 1) {
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = [self sessionsRootDirectory];
    NSArray<NSURL *> *dirs = [fm contentsOfDirectoryAtURL:root
                               includingPropertiesForKeys:@[NSURLCreationDateKey]
                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    error:nil];
    if (dirs.count <= (NSUInteger)maxCount) {
        return;
    }

    NSArray<NSURL *> *sorted = [dirs sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = nil;
        NSDate *db = nil;
        [a getResourceValue:&da forKey:NSURLCreationDateKey error:nil];
        [b getResourceValue:&db forKey:NSURLCreationDateKey error:nil];
        return [da compare:db]; // 旧 → 新
    }];

    NSInteger removeCount = (NSInteger)sorted.count - maxCount;
    for (NSInteger i = 0; i < removeCount; i++) {
        [fm removeItemAtURL:sorted[i] error:nil];
    }
}

@end
