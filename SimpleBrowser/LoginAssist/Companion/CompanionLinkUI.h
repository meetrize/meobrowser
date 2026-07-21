#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "CompanionChannel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompanionLinkUIState) {
    CompanionLinkUIStateDisconnected = 0,
    CompanionLinkUIStateWaiting,
    CompanionLinkUIStateConnected,
};

/// 工具栏圆点与设置页状态卡片共用的互联 UI 三态。
@interface CompanionLinkUI : NSObject

+ (CompanionLinkUIState)stateFromChannel:(CompanionChannel *)channel;
+ (NSString *)titleForState:(CompanionLinkUIState)state;
+ (NSColor *)dotColorForState:(CompanionLinkUIState)state;
+ (NSColor *)iconBackgroundColorForState:(CompanionLinkUIState)state;

@end

NS_ASSUME_NONNULL_END
