#import "SBTextFieldLayout.h"

const CGFloat kSBTextFieldCompactHorizontalInset = 3.0;
/// 略收紧，让 22pt 等高框文字更靠近上边缘。
const CGFloat kSBTextFieldCompactVerticalInset = 1.0;

NSRect SBTextFieldApplyCompactInsets(NSRect area) {
    return NSInsetRect(area,
                       kSBTextFieldCompactHorizontalInset,
                       kSBTextFieldCompactVerticalInset);
}

NSRect SBTextFieldTopAlignedTitleRect(NSRect area, NSFont *font, NSView *controlView) {
    if (NSIsEmptyRect(area)) {
        return area;
    }
    CGFloat lineHeight = 0;
    if (font) {
        lineHeight = ceil(font.ascender - font.descender);
        if (font.leading > 0) {
            lineHeight = ceil(lineHeight + font.leading);
        }
        CGFloat boundsHeight = ceil(font.boundingRectForFont.size.height);
        if (boundsHeight > lineHeight) {
            lineHeight = boundsHeight;
        }
    }
    if (lineHeight < 1.0) {
        return area;
    }
    lineHeight = MIN(lineHeight, NSHeight(area));
    NSRect title = area;
    title.size.height = lineHeight;
    BOOL flipped = controlView != nil && controlView.isFlipped;
    if (flipped) {
        title.origin.y = NSMinY(area);
    } else {
        title.origin.y = NSMaxY(area) - lineHeight;
    }
    return title;
}
