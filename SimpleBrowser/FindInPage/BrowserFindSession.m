#import "BrowserFindSession.h"

@implementation BrowserFindSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _query = @"";
        _mode = BrowserFindModeLiteral;
        _caseSensitive = NO;
        _currentIndex = 0;
        _matchCount = 0;
        _truncated = NO;
    }
    return self;
}

- (void)resetHighlightsKeepingQuery {
    self.currentIndex = 0;
    self.matchCount = 0;
    self.truncated = NO;
}

@end
