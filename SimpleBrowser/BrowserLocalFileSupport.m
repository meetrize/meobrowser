#import "BrowserLocalFileSupport.h"
#import <WebKit/WebKit.h>

@implementation BrowserLocalFileSupport

+ (NSSet<NSString *> *)previewablePathExtensions {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithObjects:@"html", @"htm", @"xhtml", nil];
    });
    return extensions;
}

+ (BOOL)isPreviewablePathExtension:(NSString *)extension {
    if (extension.length == 0) {
        return NO;
    }
    return [[self previewablePathExtensions] containsObject:extension.lowercaseString];
}

+ (BOOL)isPreviewableFileURL:(NSURL *)url {
    if (!url.isFileURL) {
        return NO;
    }
    // Finder 双击有时给 file reference URL（无常规扩展名），先转成 path URL。
    NSURL *pathURL = url.filePathURL ?: url;
    if ([self isPreviewablePathExtension:pathURL.pathExtension]) {
        return YES;
    }
    NSString *path = pathURL.path;
    if (path.length == 0) {
        return NO;
    }
    return [self isPreviewablePathExtension:path.pathExtension];
}

/// 将外部传入的 file URL 规范为可加载的 path-based file URL。
+ (nullable NSURL *)normalizedPreviewableFileURL:(NSURL *)url {
    if (!url.isFileURL) {
        return nil;
    }
    NSURL *pathURL = url.filePathURL ?: url;
    if (![self isPreviewableFileURL:pathURL]) {
        return nil;
    }
    NSString *path = pathURL.path;
    if (path.length == 0) {
        return nil;
    }
    return [NSURL fileURLWithPath:path isDirectory:NO];
}

+ (BOOL)isPreviewableFileAtPath:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
        return NO;
    }
    return [self isPreviewablePathExtension:path.pathExtension];
}

+ (nullable NSString *)expandedLocalPathFromUserInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    // 去掉一层包裹引号，便于粘贴 Finder「按住 Option 复制路径」。
    if (trimmed.length >= 2) {
        unichar first = [trimmed characterAtIndex:0];
        unichar last = [trimmed characterAtIndex:trimmed.length - 1];
        if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
            trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *lower = trimmed.lowercaseString;
    if ([lower hasPrefix:@"file:"]) {
        NSURL *fileURL = [NSURL URLWithString:trimmed];
        if (fileURL.isFileURL && fileURL.path.length > 0) {
            return fileURL.path;
        }
        // 含未编码空格时 URLWithString 可能失败：剥掉 file:// 前缀再当路径。
        NSString *pathPart = trimmed;
        if ([lower hasPrefix:@"file://"]) {
            pathPart = [trimmed substringFromIndex:7];
            if ([pathPart.lowercaseString hasPrefix:@"localhost"]) {
                pathPart = [pathPart substringFromIndex:9];
            }
        } else if ([lower hasPrefix:@"file:"]) {
            pathPart = [trimmed substringFromIndex:5];
        }
        pathPart = pathPart.stringByRemovingPercentEncoding ?: pathPart;
        if ([pathPart hasPrefix:@"/"] || [pathPart hasPrefix:@"~/"]) {
            return [self expandedLocalPathFromUserInput:pathPart];
        }
        return nil;
    }

    if ([trimmed hasPrefix:@"~/"] || [trimmed isEqualToString:@"~"]) {
        NSString *home = NSHomeDirectory() ?: @"";
        if ([trimmed isEqualToString:@"~"]) {
            return home;
        }
        return [home stringByAppendingPathComponent:[trimmed substringFromIndex:2]];
    }

    if ([trimmed hasPrefix:@"/"]) {
        return trimmed;
    }

    return nil;
}

+ (nullable NSURL *)previewableFileURLFromUserInput:(NSString *)input {
    NSString *path = [self expandedLocalPathFromUserInput:input];
    if (path.length == 0) {
        return nil;
    }
    if (![self isPreviewableFileAtPath:path]) {
        return nil;
    }
    return [NSURL fileURLWithPath:path isDirectory:NO];
}

+ (BOOL)loadFileURL:(NSURL *)url inWebView:(id)webView {
    if (![url isKindOfClass:[NSURL class]] || !url.isFileURL) {
        return NO;
    }
    if (![webView isKindOfClass:[WKWebView class]]) {
        return NO;
    }
    NSURL *directory = url.URLByDeletingLastPathComponent;
    if (!directory) {
        directory = url;
    }
    [(WKWebView *)webView loadFileURL:url allowingReadAccessToURL:directory];
    return YES;
}

@end
