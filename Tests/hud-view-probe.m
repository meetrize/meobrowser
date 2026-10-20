#import <Cocoa/Cocoa.h>

/// 验证：作为 contentView 子视图、isFlipped=YES、hitTest 穿透的 HUD 能否真实绘制。
@interface ProbeView : NSView
@property (nonatomic, copy) NSString *titleText;
@end

@implementation ProbeView
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)p { (void)p; return nil; }
- (void)drawRect:(NSRect)d {
    [[NSColor colorWithCalibratedWhite:0.12 alpha:0.96] setFill];
    NSRectFill(d);
    [self.titleText drawAtPoint:NSMakePoint(10, 10) withAttributes:@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor] }];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *win = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 800, 600)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered defer:NO];
        [win makeKeyAndOrderFront:nil];

        ProbeView *back = [[ProbeView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        back.wantsLayer = YES;
        back.layer.backgroundColor = [NSColor greenColor].CGColor;
        [win.contentView addSubview:back];

        ProbeView *hud = [[ProbeView alloc] initWithFrame:NSMakeRect(100, 100, 200, 120)];
        hud.wantsLayer = YES;
        hud.layer.cornerRadius = 8.0;
        hud.hidden = NO;
        hud.titleText = @"DOMHUD-PROBE";
        [win.contentView addSubview:hud positioned:NSWindowAbove relativeTo:nil];

        printf("superview==contentView ? %s\n",
               hud.superview == win.contentView ? "YES" : "NO");
        printf("index=%lu of %lu\n",
               (unsigned long)[win.contentView.subviews indexOfObject:hud],
               (unsigned long)win.contentView.subviews.count);
        printf("hidden=%d alpha=%.2f frame=%s\n",
               (int)hud.hidden, hud.alphaValue,
               NSStringFromRect(hud.frame).UTF8String);

        NSBitmapImageRep *rep = [win.contentView bitmapImageRepForCachingDisplayInRect:hud.bounds];
        [win.contentView cacheDisplayInRect:hud.bounds toBitmapImageRep:rep];
        unsigned long dark = 0;
        for (int y = 0; y < rep.pixelsHigh; y++) {
            for (int x = 0; x < rep.pixelsWide; x++) {
                if ([[rep colorAtX:x y:y] brightnessComponent] < 0.4) dark++;
            }
        }
        printf("dark pixels: %lu / %d -> %s\n", dark, rep.pixelsWide * rep.pixelsHigh,
               dark > 100 ? "RENDERS" : "BLANK");

        NSView *hit = [win.contentView hitTest:NSMakePoint(150, 150)];
        printf("hitTest@center -> %s\n",
               hit == back ? "back (passes through, ok)" : (hit == hud ? "hud (BLOCKS)" : "other"));
        return 0;
    }
}
