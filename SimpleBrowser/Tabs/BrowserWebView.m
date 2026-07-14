#import "BrowserWebView.h"
#import "BrowsingPreferences.h"

@implementation BrowserWebView

- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    [super willOpenMenu:menu withEvent:event];

    NSString *engineName = [BrowsingPreferences displayNameForSearchEngineID:[BrowsingPreferences defaultSearchEngineID]];
    NSString *searchTitle = [NSString stringWithFormat:@"使用「%@」搜索", engineName];

    for (NSMenuItem *item in menu.itemArray) {
        if (![self isSearchWebMenuItem:item]) {
            continue;
        }
        item.title = searchTitle;
        item.target = self;
        item.action = @selector(meo_searchSelectionWithDefaultEngine:);
        break;
    }
}

- (BOOL)isSearchWebMenuItem:(NSMenuItem *)item {
    NSString *identifier = item.identifier;
    if ([identifier isEqualToString:@"WKMenuItemIdentifierSearchWeb"]) {
        return YES;
    }

    NSString *title = item.title ?: @"";
    if (title.length == 0) {
        return NO;
    }

    NSString *lower = title.lowercaseString;
    // 英文：Search with Google / Search DuckDuckGo…
    if ([lower containsString:@"search with "] ||
        [lower hasPrefix:@"search google"] ||
        [lower hasPrefix:@"search duckduckgo"] ||
        [lower hasPrefix:@"search bing"] ||
        [lower hasPrefix:@"search yahoo"] ||
        [lower hasPrefix:@"search ecosia"] ||
        [lower hasPrefix:@"search baidu"]) {
        return YES;
    }

    // 中文：使用「Google」搜索 / 用 Google 搜索
    BOOL looksLikeChineseSearch = [title containsString:@"搜索"] &&
        ([title containsString:@"使用"] || [title hasPrefix:@"用"]);
    if (looksLikeChineseSearch) {
        return YES;
    }

    return NO;
}

- (void)meo_searchSelectionWithDefaultEngine:(id)sender {
#pragma unused(sender)
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:@"window.getSelection().toString()"
           completionHandler:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]]) {
            return;
        }
        NSURL *url = [BrowsingPreferences searchURLForQuery:(NSString *)result];
        if (!url) {
            return;
        }
        if (strongSelf.openURLHandler) {
            strongSelf.openURLHandler(url);
        } else {
            [strongSelf loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }];
}

@end
