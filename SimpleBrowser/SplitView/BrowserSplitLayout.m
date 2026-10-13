#import "BrowserSplitLayout.h"

@implementation BrowserSplitLayout

+ (NSInteger)paneCountForLayout:(BrowserSplitLayoutID)layout {
    switch (layout) {
        case BrowserSplitLayoutSingle: return 1;
        case BrowserSplitLayoutLR: return 2;
        case BrowserSplitLayoutUD: return 2;
        case BrowserSplitLayoutLCR: return 3;
        case BrowserSplitLayoutUMD: return 3;
        case BrowserSplitLayoutQuad: return 4;
        case BrowserSplitLayoutNine: return 9;
    }
    return 1;
}

+ (BOOL)isHorizontalSplit:(BrowserSplitLayoutID)layout {
    switch (layout) {
        case BrowserSplitLayoutLR:
        case BrowserSplitLayoutLCR: return YES;
        default: return NO;
    }
}

+ (NSString *)nameForLayout:(BrowserSplitLayoutID)layout {
    switch (layout) {
        case BrowserSplitLayoutSingle: return @"单栏";
        case BrowserSplitLayoutLR: return @"左右";
        case BrowserSplitLayoutUD: return @"上下";
        case BrowserSplitLayoutLCR: return @"左中右";
        case BrowserSplitLayoutUMD: return @"上中下";
        case BrowserSplitLayoutQuad: return @"四方格";
        case BrowserSplitLayoutNine: return @"九宫格";
    }
    return @"";
}

+ (NSArray<NSNumber *> *)defaultWeightsForLayout:(BrowserSplitLayoutID)layout {
    NSInteger n = [self paneCountForLayout:layout];
    if (layout == BrowserSplitLayoutQuad || layout == BrowserSplitLayoutNine) {
        NSMutableArray *a = [NSMutableArray array];
        NSInteger rows = (layout == BrowserSplitLayoutQuad) ? 2 : 3;
        for (NSInteger i = 0; i < rows; i++) [a addObject:@(1.0 / rows)];
        return a;
    }
    NSMutableArray *a = [NSMutableArray array];
    for (NSInteger i = 0; i < n; i++) [a addObject:@(1.0 / n)];
    return a;
}

+ (NSRect)frameForPaneAtIndex:(NSInteger)index
                    ofLayout:(BrowserSplitLayoutID)layout
                     weights:(NSArray<NSNumber *> *)weights
                      inBounds:(NSRect)bounds {
    if (layout == BrowserSplitLayoutSingle) return bounds;
    if (layout == BrowserSplitLayoutQuad) {
        CGFloat w0 = weights.count > 0 ? weights[0].doubleValue : 0.5;
        CGFloat h0 = weights.count > 1 ? weights[1].doubleValue : 0.5;
        w0 = fmin(fmax(w0, 0.15), 0.85); h0 = fmin(fmax(h0, 0.15), 0.85);
        CGFloat w = NSWidth(bounds), h = NSHeight(bounds);
        CGFloat x0 = NSMinX(bounds), y0 = NSMinY(bounds);
        // AppKit origin bottom-left; index 0=top-left,1=top-right,2=bottom-left,3=bottom-right
        CGFloat colW[2] = { w * w0, w * (1 - w0) };
        CGFloat rowH[2] = { h * (1 - h0), h * h0 };
        NSInteger col = index % 2, row = index / 2; // row0=top
        CGFloat x = x0 + (col == 0 ? 0 : colW[0]);
        CGFloat y = y0 + (row == 0 ? rowH[1] : 0);
        return NSMakeRect(x, y, colW[col], rowH[row]);
    }
    if (layout == BrowserSplitLayoutNine) {
        CGFloat cw = weights.count > 0 ? weights[0].doubleValue : 1.0/3;
        CGFloat ch = weights.count > 1 ? weights[1].doubleValue : 1.0/3;
        cw = fmin(fmax(cw, 0.1), 0.8); ch = fmin(fmax(ch, 0.1), 0.8);
        CGFloat w = NSWidth(bounds), h = NSHeight(bounds);
        CGFloat colW[3] = { w * cw, w * cw, w * (1 - 2 * cw) };
        // guard against negative when cw large
        if (colW[2] < w * 0.1) { colW[0] = colW[1] = colW[2] = w / 3; }
        CGFloat rowH[3] = { h * ch, h * ch, h * (1 - 2 * ch) };
        if (rowH[2] < h * 0.1) { rowH[0] = rowH[1] = rowH[2] = h / 3; }
        NSInteger col = index % 3, row = index / 3; // row0=top
        CGFloat x = NSMinX(bounds) + colW[0] * (col > 0) + (col == 2 ? colW[1] : 0);
        // y from bottom
        CGFloat y = NSMinY(bounds);
        if (row == 0) y += rowH[1] + rowH[2];
        else if (row == 1) y += rowH[2];
        return NSMakeRect(x, y, colW[col], rowH[row]);
    }
    BOOL horiz = [self isHorizontalSplit:layout];
    NSInteger n = [self paneCountForLayout:layout];
    double total = 0; for (NSNumber *wgt in weights) total += wgt.doubleValue;
    if (total <= 0) total = n;
    double offset = 0;
    for (NSInteger i = 0; i < n; i++) {
        double wgt = (i < weights.count ? weights[i].doubleValue : 1.0 / n) / total;
        if (i == index) {
            if (horiz) {
                CGFloat x = NSMinX(bounds) + NSWidth(bounds) * offset;
                return NSMakeRect(x, NSMinY(bounds), NSWidth(bounds) * wgt, NSHeight(bounds));
            } else {
                // index0 = top
                CGFloat y = NSMinY(bounds) + NSHeight(bounds) * (1 - offset - wgt);
                return NSMakeRect(NSMinX(bounds), y, NSWidth(bounds), NSHeight(bounds) * wgt);
            }
        }
        offset += wgt;
    }
    return bounds;
}

@end
