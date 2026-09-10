#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <unistd.h>
#import <fcntl.h>
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperEngine.h"
#import "BrowserScraperModels.h"

@interface MeoScrapeRunnerDelegate : NSObject <BrowserScraperEngineDelegate, WKNavigationDelegate>
@property (nonatomic, copy) NSString *lockPath;
@property (nonatomic, strong) BrowserScraperEngine *engine;
@property (nonatomic, strong) BrowserScraperRecipe *recipe;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) int exitCode;
@property (nonatomic, assign) BOOL started;
@end

@implementation MeoScrapeRunnerDelegate

- (void)finishWithCode:(int)code {
    if (self.lockPath.length > 0) {
        unlink(self.lockPath.fileSystemRepresentation);
    }
    self.exitCode = code;
    [NSApp stop:nil];
    // stop 可能不够，再抛个事件
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView; (void)navigation;
    if (self.started) return;
    self.started = YES;
    [self.engine startWithRecipe:self.recipe webView:self.webView];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    fprintf(stderr, "navigation failed: %s\n", error.localizedDescription.UTF8String ?: "");
    [self finishWithCode:1];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    fprintf(stderr, "provisional failed: %s\n", error.localizedDescription.UTF8String ?: "");
    [self finishWithCode:1];
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didLog:(NSString *)line {
    (void)engine;
    fprintf(stderr, "%s\n", line.UTF8String ?: "");
}

- (void)scraperEngine:(BrowserScraperEngine *)engine didFinishWithRunDirectory:(NSString *)runDirectory error:(NSError *)error {
    (void)engine; (void)runDirectory;
    if (error) {
        fprintf(stderr, "failed: %s\n", error.localizedDescription.UTF8String ?: "");
        [self finishWithCode:1];
    } else {
        [self finishWithCode:0];
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *recipeID = nil;
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg hasPrefix:@"--recipe-id="]) {
                recipeID = [arg substringFromIndex:@"--recipe-id=".length];
            }
        }
        if (recipeID.length == 0) {
            fprintf(stderr, "usage: MeoScrapeRunner --recipe-id=<id>\n");
            return 2;
        }

        NSString *lockPath = [[BrowserScraperRecipeStore runsRootDirectory]
                              stringByAppendingPathComponent:[NSString stringWithFormat:@".lock-%@", recipeID]];
        int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0644);
        if (fd < 0) {
            fprintf(stderr, "recipe already running\n");
            return 3;
        }
        close(fd);

        BrowserScraperRecipe *recipe = [[BrowserScraperRecipeStore sharedStore] recipeWithID:recipeID];
        if (!recipe || recipe.startURL.length == 0) {
            unlink(lockPath.fileSystemRepresentation);
            fprintf(stderr, "recipe not found or missing startURL\n");
            return 4;
        }

        [NSApplication sharedApplication];
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.websiteDataStore = (recipe.session == BrowserScraperSessionEphemeral)
            ? [WKWebsiteDataStore nonPersistentDataStore]
            : [WKWebsiteDataStore defaultDataStore];

        MeoScrapeRunnerDelegate *delegate = [[MeoScrapeRunnerDelegate alloc] init];
        delegate.lockPath = lockPath;
        delegate.recipe = recipe;
        delegate.engine = [[BrowserScraperEngine alloc] init];
        delegate.engine.delegate = delegate;

        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 900) configuration:config];
        webView.navigationDelegate = delegate;
        delegate.webView = webView;

        NSURL *url = [NSURL URLWithString:recipe.startURL];
        [webView loadRequest:[NSURLRequest requestWithURL:url]];

        // 超时兜底
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!delegate.started) {
                delegate.started = YES;
                [delegate.engine startWithRecipe:recipe webView:webView];
            }
        });

        [NSApp run];
        return delegate.exitCode;
    }
}
