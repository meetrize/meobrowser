#import "BrowserFaviconUtil.h"
#import <ImageIO/ImageIO.h>

NSString * _Nullable BrowserFaviconHostFromURLString(NSString * _Nullable urlString) {
    if (urlString.length == 0) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url.host.length == 0) {
        NSString *trimmed = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed containsString:@"://"]) {
            url = [NSURL URLWithString:[@"https://" stringByAppendingString:trimmed]];
        }
    }
    NSString *host = url.host;
    if (host.length == 0) {
        return nil;
    }
    return host.lowercaseString;
}

NSImage * _Nullable BrowserFaviconImageFromData(NSData * _Nullable data) {
    if (data.length == 0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (image == nil || image.size.width <= 0 || image.size.height <= 0) {
        return nil;
    }

    // 多帧 ICO 默认可能挑到 16×16；显式选用像素面积最大的一帧。
    NSImageRep *bestRep = nil;
    NSInteger bestArea = 0;
    for (NSImageRep *rep in image.representations) {
        NSInteger w = rep.pixelsWide > 0 ? rep.pixelsWide : (NSInteger)ceil(rep.size.width);
        NSInteger h = rep.pixelsHigh > 0 ? rep.pixelsHigh : (NSInteger)ceil(rep.size.height);
        NSInteger area = w * h;
        if (area > bestArea) {
            bestArea = area;
            bestRep = rep;
        }
    }
    if (bestRep != nil && image.representations.count > 1) {
        NSInteger w = bestRep.pixelsWide > 0 ? bestRep.pixelsWide : (NSInteger)ceil(bestRep.size.width);
        NSInteger h = bestRep.pixelsHigh > 0 ? bestRep.pixelsHigh : (NSInteger)ceil(bestRep.size.height);
        if (w > 0 && h > 0) {
            NSImage *selected = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
            [selected addRepresentation:bestRep];
            return selected;
        }
    }
    return image;
}

NSUInteger BrowserFaviconMaxPixelEdge(NSImage * _Nullable image) {
    if (image == nil) {
        return 0;
    }
    NSUInteger maxEdge = 0;
    for (NSImageRep *rep in image.representations) {
        NSInteger w = rep.pixelsWide > 0 ? rep.pixelsWide : (NSInteger)ceil(rep.size.width);
        NSInteger h = rep.pixelsHigh > 0 ? rep.pixelsHigh : (NSInteger)ceil(rep.size.height);
        if (w > 0) {
            maxEdge = MAX(maxEdge, (NSUInteger)w);
        }
        if (h > 0) {
            maxEdge = MAX(maxEdge, (NSUInteger)h);
        }
    }
    if (maxEdge == 0) {
        maxEdge = (NSUInteger)ceil(MAX(image.size.width, image.size.height));
    }
    return maxEdge;
}

static BOOL BrowserFaviconRenderSample(NSImage *image,
                                       NSInteger maxEdge,
                                       UInt8 **outBytes,
                                       NSInteger *outWidth,
                                       NSInteger *outHeight,
                                       NSInteger *outBytesPerRow,
                                       CGContextRef *outCtx) {
    if (outBytes == NULL || outWidth == NULL || outHeight == NULL || outBytesPerRow == NULL || outCtx == NULL) {
        return NO;
    }
    *outBytes = NULL;
    *outCtx = NULL;
    NSSize size = image.size;
    if (size.width <= 0 || size.height <= 0) {
        return NO;
    }
    CGFloat scale = MIN(1.0, (CGFloat)maxEdge / MAX(size.width, size.height));
    NSInteger width = MAX(16, (NSInteger)ceil(size.width * scale));
    NSInteger height = MAX(16, (NSInteger)ceil(size.height * scale));

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (space == NULL) {
        space = CGColorSpaceCreateDeviceRGB();
    }
    CGContextRef ctx = CGBitmapContextCreate(NULL,
                                             (size_t)width,
                                             (size_t)height,
                                             8,
                                             0,
                                             space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (ctx == NULL) {
        return NO;
    }
    CGContextClearRect(ctx, CGRectMake(0, 0, width, height));
    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext setCurrentContext:nsCtx];
    [image drawInRect:NSMakeRect(0, 0, width, height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    [NSGraphicsContext setCurrentContext:previous];

    UInt8 *data = CGBitmapContextGetData(ctx);
    if (data == NULL) {
        CGContextRelease(ctx);
        return NO;
    }
    *outBytes = data;
    *outWidth = width;
    *outHeight = height;
    *outBytesPerRow = (NSInteger)CGBitmapContextGetBytesPerRow(ctx);
    *outCtx = ctx;
    return YES;
}

static BOOL BrowserFaviconPixelIsForeground(const UInt8 *p, const UInt8 *bg, BOOL bgClear) {
    UInt8 a = p[3];
    if (bgClear) {
        return a > 40;
    }
    if (a < 24) {
        return NO;
    }
    // 预乘近似：与背景色差足够大才算前景（去掉白底上的彩色圆角块）
    int dr = (int)p[0] - (int)bg[0];
    int dg = (int)p[1] - (int)bg[1];
    int db = (int)p[2] - (int)bg[2];
    int da = (int)a - (int)bg[3];
    return (dr * dr + dg * dg + db * db + da * da) > (32 * 32);
}

static CGFloat BrowserFaviconForegroundRatioInRect(const UInt8 *data,
                                                   NSInteger width,
                                                   NSInteger height,
                                                   NSInteger bytesPerRow,
                                                   const UInt8 *bg,
                                                   BOOL bgClear,
                                                   NSInteger x0,
                                                   NSInteger y0,
                                                   NSInteger x1,
                                                   NSInteger y1) {
    x0 = MAX(0, MIN(x0, width));
    x1 = MAX(0, MIN(x1, width));
    y0 = MAX(0, MIN(y0, height));
    y1 = MAX(0, MIN(y1, height));
    if (x1 <= x0 || y1 <= y0) {
        return 0;
    }
    NSInteger fg = 0;
    NSInteger total = 0;
    for (NSInteger y = y0; y < y1; y++) {
        const UInt8 *row = data + y * bytesPerRow;
        for (NSInteger x = x0; x < x1; x++) {
            total++;
            if (BrowserFaviconPixelIsForeground(row + x * 4, bg, bgClear)) {
                fg++;
            }
        }
    }
    return total > 0 ? (CGFloat)fg / (CGFloat)total : 0;
}

static void BrowserFaviconRGBToHSL(CGFloat r, CGFloat g, CGFloat b,
                                   CGFloat *outH, CGFloat *outS, CGFloat *outL) {
    CGFloat maxc = MAX(r, MAX(g, b));
    CGFloat minc = MIN(r, MIN(g, b));
    CGFloat l = (maxc + minc) * 0.5;
    CGFloat s = 0;
    CGFloat h = 0;
    if (maxc > minc + 1e-6) {
        CGFloat d = maxc - minc;
        s = (l > 0.5) ? (d / (2.0 - maxc - minc)) : (d / (maxc + minc));
        if (maxc == r) {
            h = (g - b) / d + (g < b ? 6.0 : 0.0);
        } else if (maxc == g) {
            h = (b - r) / d + 2.0;
        } else {
            h = (r - g) / d + 4.0;
        }
        h /= 6.0;
    }
    if (outH) {
        *outH = h;
    }
    if (outS) {
        *outS = s;
    }
    if (outL) {
        *outL = l;
    }
}

BrowserFaviconIconFitStyle BrowserFaviconAnalyzeIconForDisplay(NSImage *image,
                                                               NSImage * _Nullable * _Nullable outDisplayImage) {
    if (outDisplayImage) {
        *outDisplayImage = image;
    }
    if (image == nil) {
        return BrowserFaviconIconFitInset;
    }

    UInt8 *bytes = NULL;
    NSInteger width = 0;
    NSInteger height = 0;
    NSInteger bytesPerRow = 0;
    CGContextRef ctx = NULL;
    if (!BrowserFaviconRenderSample(image, 96, &bytes, &width, &height, &bytesPerRow, &ctx)) {
        return BrowserFaviconIconFitInset;
    }

    NSInteger cornerPts[4][2] = {{1, 1}, {width - 2, 1}, {1, height - 2}, {width - 2, height - 2}};
    CGFloat cornerAlphaSum = 0;
    UInt8 cornerBG[4] = {0, 0, 0, 0};
    NSInteger sumR = 0, sumG = 0, sumB = 0, sumA = 0;
    for (NSInteger i = 0; i < 4; i++) {
        const UInt8 *p = bytes + cornerPts[i][1] * bytesPerRow + cornerPts[i][0] * 4;
        sumR += p[0];
        sumG += p[1];
        sumB += p[2];
        sumA += p[3];
        cornerAlphaSum += p[3] / 255.0;
    }
    cornerBG[0] = (UInt8)(sumR / 4);
    cornerBG[1] = (UInt8)(sumG / 4);
    cornerBG[2] = (UInt8)(sumB / 4);
    cornerBG[3] = (UInt8)(sumA / 4);
    CGFloat cornerAlphaAvg = cornerAlphaSum / 4.0;
    BOOL cornersTransparent = cornerAlphaAvg < 0.20;

    BrowserFaviconIconFitStyle style = BrowserFaviconIconFitInset;

    if (!cornersTransparent) {
        // —— 不透明四角：满幅色块徽章（知乎/HN）vs 浅色底上的 Logo（Bilibili）——
        CGFloat cr = cornerBG[0] / 255.0;
        CGFloat cg = cornerBG[1] / 255.0;
        CGFloat cb = cornerBG[2] / 255.0;
        CGFloat h = 0, s = 0, l = 0;
        BrowserFaviconRGBToHSL(cr, cg, cb, &h, &s, &l);

        // 统计「与四角色差大」的前景，看内容包围盒占画面比例
        NSInteger minX = width, minY = height, maxX = -1, maxY = -1;
        NSInteger fgCount = 0;
        for (NSInteger y = 0; y < height; y++) {
            const UInt8 *row = bytes + y * bytesPerRow;
            for (NSInteger x = 0; x < width; x++) {
                if (!BrowserFaviconPixelIsForeground(row + x * 4, cornerBG, NO)) {
                    continue;
                }
                fgCount++;
                minX = MIN(minX, x);
                maxX = MAX(maxX, x);
                minY = MIN(minY, y);
                maxY = MAX(maxY, y);
            }
        }

        CGFloat contentCoverage = 0;
        if (fgCount > 16 && maxX >= minX && maxY >= minY) {
            NSInteger bw = maxX - minX + 1;
            NSInteger bh = maxY - minY + 1;
            contentCoverage = (CGFloat)(bw * bh) / (CGFloat)(width * height);
        }

        // 彩色/深色铺满四角 → 当作圆角矩形徽章，直接铺满（知乎蓝、HN 橙）
        BOOL vividOrDarkBadge = (s >= 0.18) || (l <= 0.45);
        // 浅色底且中间另有图案（内容盒明显小于整图）→ 留白（Bilibili）
        BOOL lightCanvasLogo = (l >= 0.82 && s <= 0.25 && contentCoverage > 0.05 && contentCoverage < 0.88);

        if (vividOrDarkBadge && !lightCanvasLogo) {
            style = BrowserFaviconIconFitFillRoundedRect;
        } else if (!lightCanvasLogo && contentCoverage >= 0.90 && fgCount > 16) {
            // 几乎铺满的近直角块
            style = BrowserFaviconIconFitFillRoundedRect;
        } else {
            style = BrowserFaviconIconFitInset;
        }
    } else {
        // —— 透明四角：圆标 / 圆角矩形抠图 / 异形 ——
        UInt8 clearBG[4] = {0, 0, 0, 0};
        NSInteger minX = width, minY = height, maxX = -1, maxY = -1;
        NSInteger fgCount = 0;
        for (NSInteger y = 0; y < height; y++) {
            const UInt8 *row = bytes + y * bytesPerRow;
            for (NSInteger x = 0; x < width; x++) {
                if (!BrowserFaviconPixelIsForeground(row + x * 4, clearBG, YES)) {
                    continue;
                }
                fgCount++;
                minX = MIN(minX, x);
                maxX = MAX(maxX, x);
                minY = MIN(minY, y);
                maxY = MAX(maxY, y);
            }
        }

        if (fgCount >= 16 && maxX >= minX && maxY >= minY) {
            NSInteger bw = maxX - minX + 1;
            NSInteger bh = maxY - minY + 1;
            CGFloat fillRatio = (CGFloat)fgCount / (CGFloat)(bw * bh);
            CGFloat aspect = (CGFloat)bw / (CGFloat)MAX(bh, 1);
            if (aspect < 1.0) {
                aspect = 1.0 / aspect;
            }
            NSInteger corner = MAX(2, MIN(bw, bh) / 6);
            CGFloat cTL = BrowserFaviconForegroundRatioInRect(bytes, width, height, bytesPerRow, clearBG, YES,
                                                              minX, minY, minX + corner, minY + corner);
            CGFloat cTR = BrowserFaviconForegroundRatioInRect(bytes, width, height, bytesPerRow, clearBG, YES,
                                                              maxX - corner + 1, minY, maxX + 1, minY + corner);
            CGFloat cBL = BrowserFaviconForegroundRatioInRect(bytes, width, height, bytesPerRow, clearBG, YES,
                                                              minX, maxY - corner + 1, minX + corner, maxY + 1);
            CGFloat cBR = BrowserFaviconForegroundRatioInRect(bytes, width, height, bytesPerRow, clearBG, YES,
                                                              maxX - corner + 1, maxY - corner + 1, maxX + 1, maxY + 1);
            CGFloat cornerFG = (cTL + cTR + cBL + cBR) / 4.0;

            // 圆：填充率约 π/4，四角很空。
            BOOL looksCircle = (fillRatio >= 0.68 && fillRatio <= 0.84 && cornerFG < 0.35 && aspect <= 1.2);
            // 圆角矩形（含浅圆角）：整体几乎铺满包围盒即可。
            // 注意：小圆角时 corner 采样区仍大量实色（如知乎 favicon cornerFG≈0.8），
            // 不能用过严的 cornerFG 上限，否则会被错判成 INSET。
            BOOL looksRoundedRect = (fillRatio >= 0.90 && aspect <= 1.25 && !looksCircle);

            if (looksRoundedRect) {
                style = BrowserFaviconIconFitFillRoundedRect;
                if (outDisplayImage) {
                    NSInteger pad = MAX(1, (NSInteger)lround(MIN(bw, bh) * 0.02));
                    NSInteger cx0 = MAX(0, minX - pad);
                    NSInteger cy0 = MAX(0, minY - pad);
                    NSInteger cx1 = MIN(width, maxX + 1 + pad);
                    NSInteger cy1 = MIN(height, maxY + 1 + pad);
                    CGImageRef full = CGBitmapContextCreateImage(ctx);
                    if (full != NULL) {
                        CGImageRef sub = CGImageCreateWithImageInRect(full, CGRectMake(cx0, cy0, cx1 - cx0, cy1 - cy0));
                        CGImageRelease(full);
                        if (sub != NULL) {
                            *outDisplayImage = [[NSImage alloc] initWithCGImage:sub size:NSZeroSize];
                            CGImageRelease(sub);
                        }
                    }
                }
            } else {
                style = BrowserFaviconIconFitInset; // Apple 圆标、异形透明底
            }
        }
    }

    CGContextRelease(ctx);
    return style;
}

BOOL BrowserFaviconImageLooksPreRounded(NSImage * _Nullable image) {
    return BrowserFaviconAnalyzeIconForDisplay(image, NULL) == BrowserFaviconIconFitFillRoundedRect;
}

BOOL BrowserFaviconIsDecodableImageData(NSData * _Nullable data) {
    return BrowserFaviconImageFromData(data) != nil;
}

NSData * _Nullable BrowserFaviconPNGDataByScalingImage(NSImage *image, NSUInteger maxPixelEdge) {
    if (image == nil || maxPixelEdge == 0) {
        return nil;
    }

    NSData *tiff = image.TIFFRepresentation;
    if (tiff.length == 0) {
        return nil;
    }

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)tiff, NULL);
    if (source == NULL) {
        return nil;
    }

    NSDictionary *options = @{
        (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelEdge),
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge id)kCGImageSourceShouldCacheImmediately: @NO,
    };
    CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (cgImage == NULL) {
        return nil;
    }

    NSMutableData *pngData = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)pngData,
                                                                  (__bridge CFStringRef)@"public.png",
                                                                  1,
                                                                  NULL);
    if (dest == NULL) {
        CGImageRelease(cgImage);
        return nil;
    }
    CGImageDestinationAddImage(dest, cgImage, NULL);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CGImageRelease(cgImage);
    if (!ok || pngData.length == 0) {
        return nil;
    }
    return pngData;
}
