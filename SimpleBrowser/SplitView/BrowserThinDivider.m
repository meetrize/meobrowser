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
    _dragging = YES; _dragStartLoc = [self convertPoint:e.locationInWindow fromView:nil];
    [[NSCursor resizeLeftRightCursor] set];
}

- (void)mouseDragged:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    CGFloat d = self.vertical ? (p.x - _dragStartLoc.x) : (_dragStartLoc.y - p.y);
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
