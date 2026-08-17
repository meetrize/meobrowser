#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserNavigationSessionPhase) {
    BrowserNavigationSessionPhaseIdle = 0,
    BrowserNavigationSessionPhaseLoading,
    BrowserNavigationSessionPhaseProvisional,
    BrowserNavigationSessionPhaseCommitted,
};

/// 一次主文档导航的代际与阶段。超时回调须校验 generation，避免误杀新导航。
@interface BrowserNavigationSession : NSObject

@property (nonatomic, assign, readonly) NSInteger generation;
@property (nonatomic, copy, readonly, nullable) NSUUID *tabID;
@property (nonatomic, copy, readonly, nullable) NSURL *URL;
@property (nonatomic, assign) BrowserNavigationSessionPhase phase;
@property (nonatomic, assign, readonly) NSTimeInterval startTime;
/// hash/`__meo_hf` 恢复导航：T2 用短宽限，避免误 stop 页面脚本。
@property (nonatomic, assign) BOOL usesShortDocumentLoadGrace;

+ (instancetype)sessionWithGeneration:(NSInteger)generation
                                tabID:(nullable NSUUID *)tabID
                                  URL:(nullable NSURL *)URL;

@end

NS_ASSUME_NONNULL_END
