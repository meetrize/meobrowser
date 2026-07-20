#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserFindMode) {
    BrowserFindModeLiteral = 0,
    BrowserFindModeWildcard = 1,
};

/// 每个标签页的查找会话状态（高亮在页面侧；此处保留查询与索引）。
@interface BrowserFindSession : NSObject

@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) BrowserFindMode mode;
@property (nonatomic, assign) BOOL caseSensitive;
@property (nonatomic, assign) NSInteger currentIndex; // 1-based；0 表示无匹配
@property (nonatomic, assign) NSInteger matchCount;
@property (nonatomic, assign) BOOL truncated;

- (void)resetHighlightsKeepingQuery;

@end

NS_ASSUME_NONNULL_END
