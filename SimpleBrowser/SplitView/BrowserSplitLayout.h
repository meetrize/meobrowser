#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserSplitLayoutID) {
    BrowserSplitLayoutSingle = 0,
    BrowserSplitLayoutLR = 1,    // 左右2栏
    BrowserSplitLayoutUD = 2,    // 上下2栏
    BrowserSplitLayoutLCR = 3,   // 左中右3栏
    BrowserSplitLayoutUMD = 4,   // 上中下3栏
    BrowserSplitLayoutQuad = 5,  // 田字4栏
    BrowserSplitLayoutNine = 6,  // 九宫格
};

@interface BrowserSplitLayout : NSObject

+ (NSInteger)paneCountForLayout:(BrowserSplitLayoutID)layout;
+ (BOOL)isHorizontalSplit:(BrowserSplitLayoutID)layout; // YES=左右排列, NO=上下排列(仅2/3栏有意义)
+ (NSString *)nameForLayout:(BrowserSplitLayoutID)layout;
+ (NSArray<NSNumber *> *)defaultWeightsForLayout:(BrowserSplitLayoutID)layout;
+ (NSRect)frameForPaneAtIndex:(NSInteger)index
                    ofLayout:(BrowserSplitLayoutID)layout
                     weights:(NSArray<NSNumber *> *)weights
                      inBounds:(NSRect)bounds;

@end

NS_ASSUME_NONNULL_END
