#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 同步输入协调器:拾取各栏表单指纹,主栏输入广播到从栏。
@interface BrowserPaneSyncCoordinator : NSObject
@property (nonatomic, assign, readonly, getter=isSyncing) BOOL syncing;
@property (nonatomic, assign, readonly, getter=isPicking) BOOL picking;
@property (nonatomic, assign) NSInteger masterPaneIndex;
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, NSDictionary *> *fingerprints;
@property (nonatomic, copy, nullable) void (^statusDidChangeHandler)(NSString *status);
- (void)startPickWithPaneCount:(NSInteger)count;
- (void)cancelAll;
- (void)setFingerprint:(nullable NSDictionary *)fp forPane:(NSInteger)index;
- (BOOL)allPairedForPaneCount:(NSInteger)count;
- (void)beginSyncWithMaster:(NSInteger)master;
- (NSString *)applyValueJS:(NSString *)value fp:(nullable NSDictionary *)fp;
- (NSString *)submitJS:(nullable NSDictionary *)fp;
- (NSString *)statusTextForPaneCount:(NSInteger)count;
@end

NS_ASSUME_NONNULL_END
