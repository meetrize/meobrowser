#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BrowserChromeActionAfkModeID;
FOUNDATION_EXPORT NSString * const BrowserChromeActionTransparentModeID;
FOUNDATION_EXPORT NSString * const BrowserChromeActionCompactModeID;
FOUNDATION_EXPORT NSString * const BrowserChromeActionAlwaysOnTopID;
FOUNDATION_EXPORT NSString * const BrowserChromeActionMoreMenuID;

@interface BrowserChromeActionItem : NSObject

@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy, nullable) NSString *onSymbolName;
@property (nonatomic, copy) NSString *toolTip;
@property (nonatomic, copy, nullable) NSString *onToolTip;
@property (nonatomic, assign) BOOL toggles;

+ (instancetype)itemWithID:(NSString *)itemID
                symbolName:(NSString *)symbolName
              onSymbolName:(nullable NSString *)onSymbolName
                   toolTip:(NSString *)toolTip
                 onToolTip:(nullable NSString *)onToolTip
                   toggles:(BOOL)toggles;

@end

NS_ASSUME_NONNULL_END
