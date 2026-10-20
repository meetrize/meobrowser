#import <Cocoa/Cocoa.h>

static NSRect place(NSRect content, NSRect webViewRect, NSRect geometry, NSSize size) {
    CGFloat minX = webViewRect.size.width > 0 ? NSMinX(webViewRect) : 0;
    CGFloat minY = webViewRect.size.height > 0 ? NSMinY(webViewRect) : 0;
    CGFloat maxX = webViewRect.size.width > 0 ? NSMaxX(webViewRect) : NSMaxX(content);
    CGFloat maxY = webViewRect.size.height > 0 ? NSMaxY(webViewRect) : NSMaxY(content);
    if (maxX - minX < size.width) { minX = NSMinX(content); maxX = NSMaxX(content); }
    if (maxY - minY < size.height) { minY = NSMinY(content); maxY = NSMaxY(content); }
    CGFloat x = NSMinX(geometry);
    CGFloat yTop = maxY - NSMaxY(geometry);
    const CGFloat gap = 14.0;
    CGFloat y = yTop + gap;
    if (y + size.height > maxY - minY) y = yTop - gap - size.height;
    if (y < minY) y = minY;
    if (x < minX) x = minX;
    if (x + size.width > maxX) x = maxX - size.width;
    return NSMakeRect(x, NSHeight(content) - (y - minY) - size.height, size.width, size.height);
}

int main(void) { @autoreleasepool {
    NSRect content = NSMakeRect(0, 0, 1920, 1010);
    NSRect web = NSMakeRect(0, 130, 1920, 880);
    NSSize size = NSMakeSize(340, 214);
    NSArray *cases = @[@"表格中部", @"表单输入框", @"页面最顶端", @"页面最底端", @"右上角", @"右下角"];
    NSArray *geos = @[@"{300,500,400,30}", @"{600,700,200,24}", @"{200,995,300,12}",
                      @"{200,5,300,12}", @"{1600,980,300,20}", @"{1600,10,300,20}"];
    for (NSUInteger i = 0; i < cases.count; i++) {
        NSRect geo = NSRectFromString(geos[i]);
        NSRect f = place(content, web, geo, size);
        BOOL inside = NSEqualRects(NSIntersectionRect(web, f), f);
        printf("%-14s geo=%-24s frame=%-24s inWeb=%s\n", [cases[i] UTF8String],
               NSStringFromRect(geo).UTF8String, NSStringFromRect(f).UTF8String,
               inside ? "YES" : "NO");
    }
    return 0;
} }
