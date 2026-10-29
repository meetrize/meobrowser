#import <Foundation/Foundation.h>

@class AIPageContextBundle;

NS_ASSUME_NONNULL_BEGIN

@interface AIPageContextStore : NSObject

@property (class, readonly, strong) AIPageContextStore *sharedStore;

- (void)setBundle:(AIPageContextBundle *)bundle forTabID:(NSUUID *)tabID;
- (nullable AIPageContextBundle *)bundleForTabID:(NSUUID *)tabID;
- (void)markStaleForTabID:(NSUUID *)tabID;
- (void)removeBundleForTabID:(NSUUID *)tabID;

@end

NS_ASSUME_NONNULL_END
