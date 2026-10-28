#import "AIAssistantCitation.h"

@interface AIAssistantCitation ()
@property (nonatomic, copy, readwrite) NSString *citationId;
@property (nonatomic, assign, readwrite) AIAssistantCitationKind kind;
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *body;
@property (nonatomic, copy, readwrite, nullable) NSURL *url;
@property (nonatomic, copy, readwrite, nullable) NSURL *sourcePageURL;
@property (nonatomic, copy, readwrite, nullable) NSString *sourcePageTitle;
@end

@implementation AIAssistantCitation

+ (NSSet<NSString *> *)imageExtensions {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"jpg", @"jpeg", @"png", @"gif", @"webp", @"svg", @"bmp", @"avif", @"ico", @"heic", @"tif", @"tiff"
        ]];
    });
    return s;
}

+ (NSSet<NSString *> *)fileExtensions {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"pdf", @"zip", @"rar", @"7z", @"tar", @"gz",
            @"doc", @"docx", @"xls", @"xlsx", @"ppt", @"pptx", @"pages", @"numbers", @"key",
            @"csv", @"tsv", @"json", @"xml", @"txt", @"md", @"rtf",
            @"dmg", @"pkg", @"ipa", @"apk",
            @"mp3", @"wav", @"aac", @"flac", @"m4a",
            @"mp4", @"mov", @"mkv", @"webm", @"avi",
            @"psd", @"ai", @"sketch", @"fig"
        ]];
    });
    return s;
}

+ (AIAssistantCitationKind)kindForURL:(NSURL *)url hint:(NSString *)hint {
    NSString *h = hint.lowercaseString ?: @"";
    if ([h isEqualToString:@"image"]) return AIAssistantCitationKindImage;
    if ([h isEqualToString:@"file"]) return AIAssistantCitationKindFile;
    if ([h isEqualToString:@"text"]) return AIAssistantCitationKindText;
    if ([h isEqualToString:@"url"]) return AIAssistantCitationKindURL;

    NSString *ext = url.pathExtension.lowercaseString ?: @"";
    // 去掉 query 干扰：pathExtension 通常已干净
    if ([[self imageExtensions] containsObject:ext]) {
        return AIAssistantCitationKindImage;
    }
    if ([[self fileExtensions] containsObject:ext]) {
        return AIAssistantCitationKindFile;
    }
    if ([h isEqualToString:@"link"]) {
        return AIAssistantCitationKindLink;
    }
    return AIAssistantCitationKindURL;
}

+ (instancetype)citationWithKind:(AIAssistantCitationKind)kind
                           title:(NSString *)title
                            body:(NSString *)body
                             url:(NSURL *)url {
    AIAssistantCitation *c = [[AIAssistantCitation alloc] init];
    c.citationId = [[NSUUID UUID] UUIDString];
    c.kind = kind;
    c.title = title.length ? title : @"";
    c.body = body.length ? body : (url.absoluteString ?: @"");
    c.url = url;
    return c;
}

+ (instancetype)textCitation:(NSString *)text {
    return [self textCitation:text sourceURL:nil pageTitle:nil];
}

+ (instancetype)textCitation:(NSString *)text
                   sourceURL:(NSURL *)sourceURL
                   pageTitle:(NSString *)pageTitle {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *chipTitle = t;
    if (chipTitle.length > 28) {
        chipTitle = [[chipTitle substringToIndex:28] stringByAppendingString:@"…"];
    }
    AIAssistantCitation *c = [self citationWithKind:AIAssistantCitationKindText
                                              title:chipTitle
                                               body:t
                                                url:sourceURL];
    c.sourcePageURL = sourceURL;
    NSString *pt = [pageTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    c.sourcePageTitle = pt.length ? pt : nil;
    return c;
}

+ (instancetype)URLCitationWithURL:(NSURL *)url title:(NSString *)title {
    NSString *t = title.length ? title : (url.host ?: url.absoluteString ?: @"网页");
    return [self citationWithKind:AIAssistantCitationKindURL title:t body:url.absoluteString ?: @"" url:url];
}

+ (instancetype)imageCitationWithURL:(NSURL *)url title:(NSString *)title {
    return [self imageCitationWithURL:url title:title sourcePageURL:nil pageTitle:nil];
}

+ (instancetype)imageCitationWithURL:(NSURL *)url
                               title:(NSString *)title
                       sourcePageURL:(NSURL *)sourcePageURL
                           pageTitle:(NSString *)pageTitle {
    NSString *t = title.length ? title : (url.lastPathComponent.length ? url.lastPathComponent : @"图片");
    AIAssistantCitation *c = [self citationWithKind:AIAssistantCitationKindImage
                                              title:t
                                               body:url.absoluteString ?: @""
                                                url:url];
    c.sourcePageURL = sourcePageURL;
    NSString *pt = [pageTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    c.sourcePageTitle = pt.length ? pt : nil;
    return c;
}

+ (instancetype)fileCitationWithURL:(NSURL *)url title:(NSString *)title {
    NSString *t = title.length ? title : (url.lastPathComponent.length ? url.lastPathComponent : @"文件");
    return [self citationWithKind:AIAssistantCitationKindFile title:t body:url.absoluteString ?: @"" url:url];
}

+ (instancetype)linkCitationWithURL:(NSURL *)url title:(NSString *)title {
    NSString *t = title.length ? title : (url.host ?: url.absoluteString ?: @"链接");
    return [self citationWithKind:AIAssistantCitationKindLink title:t body:url.absoluteString ?: @"" url:url];
}

+ (instancetype)citationWithURLString:(NSString *)urlString
                                title:(NSString *)title
                                 hint:(NSString *)hint {
    return [self citationWithURLString:urlString title:title hint:hint sourcePageURL:nil sourcePageTitle:nil];
}

+ (instancetype)citationWithURLString:(NSString *)urlString
                                title:(NSString *)title
                                 hint:(NSString *)hint
                        sourcePageURL:(NSString *)sourcePageURL
                      sourcePageTitle:(NSString *)sourcePageTitle {
    NSString *raw = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (raw.length == 0) {
        return nil;
    }
    if ([hint.lowercaseString isEqualToString:@"text"]) {
        NSURL *page = sourcePageURL.length ? [NSURL URLWithString:sourcePageURL] : nil;
        return [self textCitation:raw sourceURL:page pageTitle:sourcePageTitle];
    }
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) {
        return [self textCitation:raw];
    }
    NSURL *pageURL = sourcePageURL.length ? [NSURL URLWithString:sourcePageURL] : nil;
    AIAssistantCitationKind kind = [self kindForURL:url hint:hint];
    switch (kind) {
        case AIAssistantCitationKindImage:
            return [self imageCitationWithURL:url title:title sourcePageURL:pageURL pageTitle:sourcePageTitle];
        case AIAssistantCitationKindFile:
            return [self fileCitationWithURL:url title:title];
        case AIAssistantCitationKindLink:
            return [self linkCitationWithURL:url title:title];
        case AIAssistantCitationKindText:
            return [self textCitation:raw sourceURL:pageURL pageTitle:sourcePageTitle];
        case AIAssistantCitationKindURL:
        default:
            return [self URLCitationWithURL:url title:title];
    }
}

- (NSString *)kindDisplayName {
    switch (self.kind) {
        case AIAssistantCitationKindText: return @"选中文本";
        case AIAssistantCitationKindURL: return @"网页";
        case AIAssistantCitationKindImage: return @"图片";
        case AIAssistantCitationKindFile: return @"文件";
        case AIAssistantCitationKindLink: return @"链接";
    }
    return @"引用";
}

- (NSString *)chipLabel {
    if (self.kind == AIAssistantCitationKindImage) {
        // 无缩略图时也要能看出是图片引用：显示主机名或文件名
        NSString *host = self.url.host ?: @"";
        NSString *file = self.url.lastPathComponent ?: @"";
        NSString *t = file.length ? file : (host.length ? host : (self.title.length ? self.title : @"图片"));
        t = [t stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (t.length > 28) {
            t = [[t substringToIndex:28] stringByAppendingString:@"…"];
        }
        return [NSString stringWithFormat:@"图片 · %@", t];
    }
    NSString *t = self.title.length ? self.title : self.body;
    t = [t stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (t.length > 36) {
        t = [[t substringToIndex:36] stringByAppendingString:@"…"];
    }
    return t.length ? t : [self kindDisplayName];
}

- (NSString *)promptBlock {
    switch (self.kind) {
        case AIAssistantCitationKindText: {
            NSMutableString *block = [NSMutableString stringWithString:@"【引用 · 选中文本】\n"];
            NSString *pageURL = self.url.absoluteString ?: @"";
            if (self.sourcePageTitle.length > 0 && pageURL.length > 0) {
                [block appendFormat:@"来源标题：%@\n来源网址：%@\n", self.sourcePageTitle, pageURL];
            } else if (pageURL.length > 0) {
                [block appendFormat:@"来源网址：%@\n", pageURL];
            } else if (self.sourcePageTitle.length > 0) {
                [block appendFormat:@"来源标题：%@\n", self.sourcePageTitle];
            }
            [block appendString:self.body ?: @""];
            return block;
        }
        case AIAssistantCitationKindImage: {
            NSMutableString *block = [NSMutableString stringWithString:@"【引用 · 图片】\n"];
            if (self.title.length > 0) {
                [block appendFormat:@"说明：%@\n", self.title];
            }
            NSString *imageURL = self.url.absoluteString ?: self.body ?: @"";
            if (imageURL.length > 0) {
                [block appendFormat:@"图片网址：%@\n", imageURL];
            }
            NSString *pageURL = self.sourcePageURL.absoluteString ?: @"";
            if (self.sourcePageTitle.length > 0 && pageURL.length > 0) {
                [block appendFormat:@"所在网页标题：%@\n所在网页地址：%@\n", self.sourcePageTitle, pageURL];
            } else if (pageURL.length > 0) {
                [block appendFormat:@"所在网页地址：%@\n", pageURL];
            } else if (self.sourcePageTitle.length > 0) {
                [block appendFormat:@"所在网页标题：%@\n", self.sourcePageTitle];
            }
            return block;
        }
        case AIAssistantCitationKindFile:
            return [NSString stringWithFormat:@"【引用 · 文件%@】\n%@",
                    self.title.length ? [NSString stringWithFormat:@"（%@）", self.title] : @"",
                    self.url.absoluteString ?: self.body ?: @""];
        case AIAssistantCitationKindLink:
            return [NSString stringWithFormat:@"【引用 · 链接%@】\n%@",
                    self.title.length ? [NSString stringWithFormat:@"（%@）", self.title] : @"",
                    self.url.absoluteString ?: self.body ?: @""];
        case AIAssistantCitationKindURL:
        default:
            return [NSString stringWithFormat:@"【引用 · 网页%@】\n%@",
                    self.title.length ? [NSString stringWithFormat:@"（%@）", self.title] : @"",
                    self.url.absoluteString ?: self.body ?: @""];
    }
}

@end
