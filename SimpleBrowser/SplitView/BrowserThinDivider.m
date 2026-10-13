#import "BrowserThinDivider.h"

static const CGFloat kDividerThickness = 1.0;
static const CGFloat kDividerHitWidth = 7.0;

@implementation BrowserThinDivider {
    BOOL _hovered;
    BOOL _dragging;
    NSPoint _dragStartLoc;
    NSTrackingArea *_tracking;
}

+ (CGFloat)thickness { return kDividerThickness; }
+ (CGFloat)hitWidth { return kDividerHitWidth; }

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (self) { self.wantsLayer = YES; }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) { [self removeTrackingArea:_tracking]; _tracking = nil; }
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                            options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                              owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent *)e { _hovered = YES; [self setNeedsDisplay:YES]; [[NSCursor resizeLeftRightCursor] set]; }
- (void)mouseExited:(NSEvent *)e { if (!_dragging) { _hovered = NO; [self setNeedsDisplay:YES]; } }

- (void)mouseDown:(NSEvent *)e {
    _dragging = YES;
    // 用 superview(容器)坐标系记起点:本视图拖动时自身 frame 在变,
    // 若用自身坐标系算增量,分界线移动会污染 delta,形成反馈导致反向/放大。
    NSView *parent = self.superview ?: self;
    _dragStartLoc = [parent convertPoint:e.locationInWindow fromView:nil];
    [[NSCursor resizeLeftRightCursor] set];
}

- (void)mouseDragged:(NSEvent *)e {
    NSView *parent = self.superview ?: self;
    NSPoint p = [parent convertPoint:e.locationInWindow fromView:nil];
    CGFloat d = self.vertical ? (p.x - _dragStartLoc.x) : (_dragStartLoc.y - p.y);
    _dragStartLoc = p;
    if (self.dragDeltaHandler) self.dragDeltaHandler(d);
}

- (void)mouseUp:(NSEvent *)e {
    _dragging = NO; _hovered = NO; [self setNeedsDisplay:YES];
    if (self.dragDidEndHandler) self.dragDidEndHandler();
}

- (void)drawRect:(NSRect)r {
    [super drawRect:r];
    NSColor *line = _hovered || _dragging ? [NSColor controlAccentColor] : [NSColor separatorColor];
    [line setFill];
    NSRect f = self.bounds;
    NSRect bar = self.vertical
        ? NSMakeRect(NSMidX(f) - kDividerThickness / 2, 0, kDividerThickness, NSHeight(f))
        : NSMakeRect(0, NSMidY(f) - kDividerThickness / 2, NSWidth(f), kDividerThickness);
    NSRectFill(bar);
}

@end
