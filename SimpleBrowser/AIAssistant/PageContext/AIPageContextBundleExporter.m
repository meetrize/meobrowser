#import "AIPageContextBundleExporter.h"
#import "AIPageContextBundle.h"
#import "AIPageContextResource.h"
#import <AppKit/AppKit.h>

@implementation AIPageContextBundleExporter

+ (NSDictionary *)dictionaryFromBundle:(AIPageContextBundle *)bundle
                     includeResources:(BOOL)includeResources
                        includeBodies:(BOOL)includeBodies {
    if (!bundle) return @{};
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"bundleId"] = bundle.bundleId ?: @"";
    d[@"url"] = bundle.urlString ?: @"";
    d[@"title"] = bundle.title ?: @"";
    d[@"capturedAt"] = @((NSInteger)[bundle.capturedAt timeIntervalSince1970]);
    d[@"stale"] = @(bundle.stale);
    d[@"meta"] = @{
        @"description": bundle.metaDescription ?: @"",
        @"lang": bundle.metaLanguage ?: @"",
        @"canonical": bundle.canonicalURL ?: @"",
    };
    if (includeBodies) {
        d[@"article"] = @{
            @"text": bundle.articleText ?: @"",
            @"quality": bundle.articleQuality == AIPageContextArticleQualityHigh ? @"high" :
                        (bundle.articleQuality == AIPageContextArticleQualityLow ? @"low" : @"unknown"),
            @"warning": bundle.articleWarning ?: @"",
        };
        d[@"outline"] = @{ @"text": bundle.outlineText ?: @"" };
        d[@"html"] = @{ @"text": bundle.htmlText ?: @"", @"truncated": @(bundle.htmlTruncated) };
        d[@"markdown"] = @{ @"text": bundle.markdownText ?: @"" };
        d[@"visibleText"] = bundle.visibleText ?: @"";
    } else {
        d[@"article"] = @{ @"charCount": @([bundle effectiveArticleText].length) };
        d[@"outline"] = @{ @"charCount": @(bundle.outlineText.length) };
        d[@"html"] = @{ @"charCount": @(bundle.htmlText.length), @"truncated": @(bundle.htmlTruncated) };
        d[@"markdown"] = @{ @"charCount": @(bundle.markdownText.length) };
    }
    if (includeResources) {
        NSMutableArray *arr = [NSMutableArray array];
        for (AIPageContextResource *r in bundle.resources) {
            NSMutableDictionary *rd = [@{
                @"id": r.resourceId ?: @"",
                @"kind": r.kindDisplayName.lowercaseString ?: @"other",
                @"url": r.urlString ?: @"",
                @"label": r.label ?: @"",
                @"inline": @(r.inlineContent),
                @"size": @(r.reportedSize),
            } mutableCopy];
            if (includeBodies && r.text.length) {
                rd[@"text"] = r.text;
            }
            [arr addObject:rd];
        }
        d[@"resources"] = arr;
    }
    return d;
}

+ (NSData *)JSONDataFromBundle:(AIPageContextBundle *)bundle
             includeResources:(BOOL)includeResources
                includeBodies:(BOOL)includeBodies
                        error:(NSError **)error {
    NSDictionary *dict = [self dictionaryFromBundle:bundle
                                  includeResources:includeResources
                                     includeBodies:includeBodies];
    return [NSJSONSerialization dataWithJSONObject:dict
                                           options:NSJSONWritingPrettyPrinted
                                             error:error];
}

+ (NSString *)exportBundle:(AIPageContextBundle *)bundle
               toDirectory:(NSString *)directory
                     error:(NSError **)error {
    if (!bundle || directory.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AIPageContextExport" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"无效参数"}];
        return nil;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *host = [NSURL URLWithString:bundle.urlString].host ?: @"page";
    host = [[host componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]
            componentsJoinedByString:@"-"];
    NSString *name = [NSString stringWithFormat:@"meo-page-context-%@-%ld.json",
                      host.length ? host : @"page",
                      (long)[[NSDate date] timeIntervalSince1970]];
    NSString *path = [directory stringByAppendingPathComponent:name];
    NSData *data = [self JSONDataFromBundle:bundle includeResources:YES includeBodies:YES error:error];
    if (!data) return nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
    return path;
}

+ (void)copyBundleJSONToPasteboard:(AIPageContextBundle *)bundle {
    NSData *data = [self JSONDataFromBundle:bundle includeResources:YES includeBodies:NO error:nil];
    if (!data) return;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s.length) return;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:s forType:NSPasteboardTypeString];
}

@end
