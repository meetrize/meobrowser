#import "SBTextFieldLayout.h"

const CGFloat kSBTextFieldCompactHorizontalInset = 3.0;
/// 略收紧，让 22pt 等高框文字更靠近上边缘。
const CGFloat kSBTextFieldCompactVerticalInset = 1.0;

CGFloat SBTextFieldLineHeight(NSFont *font) {
    if (!font) {
        return 0;
    }
    CGFloat lineHeight = ceil(font.ascender - font.descender);
    if (font.leading > 0) {
        lineHeight = ceil(lineHeight + font.leading);
    }
    CGFloat boundsHeight = ceil(font.boundingRectForFont.size.height);
    if (boundsHeight > lineHeight) {
        lineHeight = boundsHeight;
    }
    return lineHeight;
}

NSRect SBTextFieldApplyCompactInsets(NSRect area) {
    return NSInsetRect(area,
                       kSBTextFieldCompactHorizontalInset,
                       kSBTextFieldCompactVerticalInset);
}

NSRect SBTextFieldApplyAdditionalTopInset(NSRect area, CGFloat topInset, NSView *controlView) {
    if (topInset <= 0.0 || NSIsEmptyRect(area)) {
        return area;
    }
    CGFloat trim = MIN(topInset, MAX(0.0, NSHeight(area) - 1.0));
    if (trim <= 0.0) {
        return area;
    }
    BOOL flipped = controlView != nil && controlView.isFlipped;
    if (flipped) {
        area.origin.y += trim;
        area.size.height -= trim;
    } else {
        // 非 flipped：减小 height 即从视觉上沿让出空白。
        area.size.height -= trim;
    }
    return area;
}

NSRect SBTextFieldApplyUpwardBias(NSRect area, CGFloat upwardBias, NSView *controlView) {
    if (upwardBias <= 0.0 || NSIsEmptyRect(area) || !controlView) {
        return area;
    }
    NSRect bounds = controlView.bounds;
    BOOL flipped = controlView.isFlipped;
    if (flipped) {
        CGFloat minY = NSMinY(bounds);
        CGFloat shift = MIN(upwardBias, MAX(0.0, NSMinY(area) - minY));
        area.origin.y -= shift;
    } else {
        CGFloat maxY = NSMaxY(bounds);
        CGFloat shift = MIN(upwardBias, MAX(0.0, maxY - NSMaxY(area)));
        area.origin.y += shift;
    }
    return area;
}

NSRect SBTextFieldApplyTopInsetWithUpwardBias(NSRect area,
                                              CGFloat topInset,
                                              CGFloat upwardBias,
                                              NSView *controlView) {
    CGFloat inset = MAX(0.0, topInset);
    CGFloat bias = MAX(0.0, upwardBias);
    CGFloat effectiveInset = MAX(0.0, inset - bias);
    CGFloat extraUp = MAX(0.0, bias - inset);
    area = SBTextFieldApplyAdditionalTopInset(area, effectiveInset, controlView);
    area = SBTextFieldApplyUpwardBias(area, extraUp, controlView);
    return area;
}

NSRect SBTextFieldTopAlignedTitleRect(NSRect area, NSFont *font, NSView *controlView) {
    if (NSIsEmptyRect(area)) {
        return area;
    }
    CGFloat lineHeight = SBTextFieldLineHeight(font);
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

NSRect SBTextFieldVerticallyCenteredRect(NSRect area, CGFloat contentHeight) {
    if (NSIsEmptyRect(area) || contentHeight < 1.0) {
        return area;
    }
    CGFloat height = MIN(contentHeight, NSHeight(area));
    NSRect centered = area;
    centered.size.height = height;
    centered.origin.y = NSMinY(area) + floor((NSHeight(area) - height) / 2.0);
    return centered;
}

NSRect SBTextFieldApplyBottomExtend(NSRect area, CGFloat extend, NSView *controlView) {
    if (extend <= 0.0 || NSIsEmptyRect(area) || !controlView) {
        return area;
    }
    NSRect bounds = controlView.bounds;
    BOOL flipped = controlView.isFlipped;
    if (flipped) {
        CGFloat room = MAX(0.0, NSMaxY(bounds) - NSMaxY(area));
        CGFloat delta = MIN(extend, room);
        area.size.height += delta;
    } else {
        // 视觉下方 = 更小的 y：下扩 = 降低 origin 并增加 height。
        CGFloat room = MAX(0.0, NSMinY(area) - NSMinY(bounds));
        CGFloat delta = MIN(extend, room);
        area.origin.y -= delta;
        area.size.height += delta;
    }
    return area;
}
