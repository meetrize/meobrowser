#import "MeoContextMenuLocalizer.h"

static BOOL MeoStringLooksChinese(NSString *title) {
    if (title.length == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < title.length; i++) {
        unichar c = [title characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) {
            return YES;
        }
    }
    return NO;
}

@implementation MeoContextMenuLocalizer

+ (NSDictionary<NSString *, NSString *> *)identifierTitleMap {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"WKMenuItemIdentifierGoBack": @"后退",
            @"WKMenuItemIdentifierGoForward": @"前进",
            @"WKMenuItemIdentifierReload": @"重新载入",
            @"WKMenuItemIdentifierCopy": @"拷贝",
            @"WKMenuItemIdentifierPaste": @"粘贴",
            @"WKMenuItemIdentifierCopyImage": @"拷贝图像",
            @"WKMenuItemIdentifierCopyLink": @"拷贝链接",
            @"WKMenuItemIdentifierCopyMediaLink": @"拷贝媒体链接",
            @"WKMenuItemIdentifierCopyLinkWithHighlight": @"拷贝带高亮的链接",
            @"WKMenuItemIdentifierCopySubject": @"拷贝主题",
            @"WKMenuItemIdentifierDownloadImage": @"下载图像",
            @"WKMenuItemIdentifierDownloadMedia": @"下载媒体",
            @"WKMenuItemIdentifierDownloadLinkedFile": @"下载链接文件",
            @"WKMenuItemIdentifierOpenLink": @"打开链接",
            @"WKMenuItemIdentifierOpenLinkInNewWindow": @"在新窗口中打开链接",
            @"WKMenuItemIdentifierOpenImageInNewWindow": @"在新窗口中打开图像",
            @"WKMenuItemIdentifierOpenMediaInNewWindow": @"在新窗口中打开媒体",
            @"WKMenuItemIdentifierOpenFrameInNewWindow": @"在新窗口中打开框架",
            @"WKMenuItemIdentifierRevealImage": @"在 Finder 中显示",
            @"WKMenuItemIdentifierInspectElement": @"检查元素",
            @"WKMenuItemIdentifierTranslate": @"翻译…",
            @"WKMenuItemIdentifierWritingTools": @"写作工具",
            @"WKMenuItemIdentifierProofread": @"校对",
            @"WKMenuItemIdentifierRewrite": @"改写",
            @"WKMenuItemIdentifierSummarize": @"摘要",
            @"WKMenuItemIdentifierShowHideMediaStats": @"显示/隐藏媒体统计",
            @"WKMenuItemIdentifierTogglePictureInPicture": @"画中画",
            @"WKMenuItemIdentifierToggleVideoViewer": @"切换视频查看器",
            @"WKMenuItemIdentifierAddHighlightToCurrentQuickNote": @"添加到当前快速备忘录",
            @"WKMenuItemIdentifierAddHighlightToNewQuickNote": @"添加到新快速备忘录",
            @"WKMenuItemIdentifierSpellingMenu": @"拼写与语法",
            @"WKMenuItemIdentifierShowSpellingPanel": @"显示拼写面板",
            @"WKMenuItemIdentifierCheckSpelling": @"检查拼写",
            @"WKMenuItemIdentifierCheckSpellingWhileTyping": @"键入时检查拼写",
            @"WKMenuItemIdentifierCheckGrammarWithSpelling": @"检查语法",
            @"WKMenuItemIdentifierSpeechMenu": @"语音",
            @"WKMenuItemIdentifierShareMenu": @"共享",
            @"WKMenuItemIdentifierPlayAnimation": @"播放动画",
            @"WKMenuItemIdentifierPauseAnimation": @"暂停动画",
            @"WKMenuItemIdentifierPlayAllAnimations": @"播放全部动画",
            @"WKMenuItemIdentifierPauseAllAnimations": @"暂停全部动画",
        };
    });
    return map;
}

+ (NSString *)displayTitleForItem:(NSMenuItem *)item {
    NSString *title = item.title ?: @"";
    if (title.length > 0) {
        return title;
    }
    NSAttributedString *attributed = item.attributedTitle;
    if (attributed.length > 0) {
        return attributed.string ?: @"";
    }
    return @"";
}

+ (NSString *)normalizedMenuTitleKey:(NSString *)title {
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"";
    }
    NSMutableString *normalized = [trimmed.lowercaseString mutableCopy];
    // 统一省略号与空白，便于匹配 Translate… / Look Up …
    [normalized replaceOccurrencesOfString:@"…"
                                withString:@""
                                   options:0
                                     range:NSMakeRange(0, normalized.length)];
    while ([normalized hasSuffix:@"."]) {
        [normalized deleteCharactersInRange:NSMakeRange(normalized.length - 1, 1)];
    }
    [normalized replaceOccurrencesOfString:@"\u00a0"
                                withString:@" "
                                   options:0
                                     range:NSMakeRange(0, normalized.length)];
    while ([normalized rangeOfString:@"  "].location != NSNotFound) {
        [normalized replaceOccurrencesOfString:@"  "
                                    withString:@" "
                                       options:0
                                         range:NSMakeRange(0, normalized.length)];
    }
    return [normalized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (BOOL)titleNeedsEnglishLocalization:(NSString *)title {
    if (title.length == 0) {
        return YES; // 允许仅靠 identifier / action 翻译
    }
    NSString *lower = title.lowercaseString;
    // Look Up “中文” 标题含汉字，但仍需把英文前缀翻成「查询」
    if ([lower hasPrefix:@"look up"] ||
        [lower hasPrefix:@"lookup"] ||
        [lower hasPrefix:@"translate"] ||
        [lower hasPrefix:@"quick look"] ||
        [lower hasPrefix:@"look up in"] ||
        [lower hasPrefix:@"select text in"]) {
        return YES;
    }
    return !MeoStringLooksChinese(title);
}

+ (nullable NSString *)chineseTitleForItem:(NSMenuItem *)item {
    NSString *identifier = item.identifier ?: @"";
    NSString *title = [self displayTitleForItem:item];
    NSString *lower = title.lowercaseString ?: @"";
    NSString *actionName = item.action ? NSStringFromSelector(item.action) : @"";

    if ([identifier isEqualToString:@"WKMenuItemIdentifierToggleFullScreen"]) {
        if ([lower containsString:@"exit"] || [lower containsString:@"leave"]) {
            return @"退出全屏";
        }
        return @"进入全屏";
    }
    if ([identifier isEqualToString:@"WKMenuItemIdentifierShowHideMediaControls"]) {
        if ([lower containsString:@"hide"]) {
            return @"隐藏媒体控制";
        }
        return @"显示媒体控制";
    }
    if ([identifier isEqualToString:@"WKMenuItemIdentifierLookUp"] ||
        [actionName containsString:@"lookUp"] ||
        [actionName containsString:@"LookUp"] ||
        [actionName isEqualToString:@"showDefinitionFromRemoteDictionary:"]) {
        return [self chineseLookUpTitleFromEnglish:title];
    }
    if ([identifier isEqualToString:@"WKMenuItemIdentifierTranslate"] ||
        [actionName containsString:@"translate"] ||
        [actionName containsString:@"Translate"]) {
        return @"翻译…";
    }

    if (identifier.length > 0) {
        NSString *mapped = [self identifierTitleMap][identifier];
        if (mapped.length > 0) {
            return mapped;
        }
    }
    return [self chineseTitleFromEnglishTitle:title];
}

+ (nullable NSString *)chineseLookUpTitleFromEnglish:(NSString *)title {
    if (title.length == 0) {
        return @"查询";
    }
    // “…” / "..." / ‘…’ / 「…」 等多种引号；也兼容 Look Up …
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"[\"“”‘’「」『』](.+?)[\"“”‘’「」『』]"
                                                  options:0
                                                    error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:title
                                                    options:0
                                                      range:NSMakeRange(0, title.length)];
    if (match.numberOfRanges > 1) {
        NSString *term = [title substringWithRange:[match rangeAtIndex:1]];
        if (term.length > 0) {
            return [NSString stringWithFormat:@"查询「%@」", term];
        }
    }
    return @"查询";
}

+ (nullable NSString *)chineseTitleFromEnglishTitle:(NSString *)title {
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *lower = trimmed.lowercaseString;
    NSString *key = [self normalizedMenuTitleKey:trimmed];

    if ([lower hasPrefix:@"look up"] || [key hasPrefix:@"look up"] || [key hasPrefix:@"lookup"]) {
        return [self chineseLookUpTitleFromEnglish:trimmed];
    }
    if ([key hasPrefix:@"translate"] || [lower hasPrefix:@"translate"]) {
        return @"翻译…";
    }

    static NSDictionary<NSString *, NSString *> *exactMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exactMap = @{
            @"back": @"后退",
            @"forward": @"前进",
            @"reload": @"重新载入",
            @"reload page": @"重新载入",
            @"copy": @"拷贝",
            @"cut": @"剪切",
            @"paste": @"粘贴",
            @"delete": @"删除",
            @"select all": @"全选",
            @"open link": @"打开链接",
            @"open link in new tab": @"在新标签页中打开链接",
            @"open link in new window": @"在新窗口中打开链接",
            @"download linked file": @"下载链接文件",
            @"copy link": @"拷贝链接",
            @"copy link address": @"拷贝链接地址",
            @"copy image": @"拷贝图像",
            @"copy image address": @"拷贝图像地址",
            @"download image": @"下载图像",
            @"download image to disk": @"下载图像",
            @"download media": @"下载媒体",
            @"download media to disk": @"下载媒体",
            @"open image in new window": @"在新窗口中打开图像",
            @"open image in new tab": @"在新标签页中打开图像",
            @"open image": @"打开图像",
            @"open media in new window": @"在新窗口中打开媒体",
            @"reveal image in finder": @"在 Finder 中显示",
            @"inspect element": @"检查元素",
            @"translate": @"翻译…",
            @"writing tools": @"写作工具",
            @"proofread": @"校对",
            @"rewrite": @"改写",
            @"summarize": @"摘要",
            @"services": @"服务",
            @"share": @"共享",
            @"share...": @"共享…",
            @"speech": @"语音",
            @"start speaking": @"开始朗读",
            @"stop speaking": @"停止朗读",
            @"pause speaking": @"暂停朗读",
            @"continue speaking": @"继续朗读",
            @"spelling and grammar": @"拼写与语法",
            @"spelling": @"拼写",
            @"show spelling and grammar": @"显示拼写面板",
            @"check spelling": @"检查拼写",
            @"check spelling while typing": @"键入时检查拼写",
            @"check grammar with spelling": @"检查语法",
            @"check document now": @"立即检查文稿",
            @"correct spelling automatically": @"自动纠正拼写",
            @"substitutions": @"替换",
            @"smart copy/paste": @"智能拷贝/粘贴",
            @"smart quotes": @"智能引号",
            @"smart dashes": @"智能破折号",
            @"smart links": @"智能链接",
            @"text replacement": @"文本替换",
            @"transformations": @"转换",
            @"make upper case": @"转为大写",
            @"make lower case": @"转为小写",
            @"capitalize": @"首字母大写",
            @"enter full screen": @"进入全屏",
            @"exit full screen": @"退出全屏",
            @"enter fullscreen": @"进入全屏",
            @"exit fullscreen": @"退出全屏",
            @"start picture in picture": @"开始画中画",
            @"picture in picture": @"画中画",
            @"show media controls": @"显示媒体控制",
            @"hide media controls": @"隐藏媒体控制",
            @"show media stats": @"显示媒体统计",
            @"hide media stats": @"隐藏媒体统计",
            @"add highlight to current quick note": @"添加到当前快速备忘录",
            @"add highlight to new quick note": @"添加到新快速备忘录",
            @"copy subject": @"拷贝主题",
            @"play animation": @"播放动画",
            @"pause animation": @"暂停动画",
            @"play all animations": @"播放全部动画",
            @"pause all animations": @"暂停全部动画",
            @"quick look": @"快速查看",
            @"look up in quick look": @"在快速查看中查询",
            @"select text in quick look": @"在快速查看中选择文本",
        };
    });

    NSString *exact = exactMap[key] ?: exactMap[lower];
    if (exact.length > 0) {
        return exact;
    }

    if ([lower hasPrefix:@"search with "] ||
        [lower hasPrefix:@"search google"] ||
        [lower hasPrefix:@"search duckduckgo"] ||
        [lower hasPrefix:@"search bing"] ||
        [lower hasPrefix:@"search yahoo"] ||
        [lower hasPrefix:@"search ecosia"] ||
        [lower hasPrefix:@"search baidu"]) {
        return nil;
    }

    if ([lower hasPrefix:@"save image"]) {
        return @"存储图像为…";
    }
    if ([lower hasPrefix:@"save link"]) {
        return @"存储链接为…";
    }
    if ([lower hasPrefix:@"open "] && [lower containsString:@" in new tab"]) {
        return @"在新标签页中打开";
    }
    if ([lower hasPrefix:@"open "] && [lower containsString:@" in new window"]) {
        return @"在新窗口中打开";
    }

    return nil;
}

+ (void)localizeMenuItem:(NSMenuItem *)item {
    if (!item || item.isSeparatorItem) {
        return;
    }

    NSString *title = [self displayTitleForItem:item];
    if (title.length > 0 && ![self titleNeedsEnglishLocalization:title]) {
        if (item.submenu) {
            [self localizeMenu:item.submenu];
        }
        return;
    }

    NSString *localized = [self chineseTitleForItem:item];
    if (localized.length > 0) {
        item.title = localized;
    }

    if (item.submenu) {
        [self localizeMenu:item.submenu];
    }
}

+ (void)localizeMenu:(NSMenu *)menu {
    if (!menu) {
        return;
    }
    for (NSMenuItem *item in menu.itemArray) {
        [self localizeMenuItem:item];
    }
}

@end
