#import "BrowserDownloadProgressRingView.h"

@interface BrowserDownloadProgressRingView ()
@property (nonatomic, strong, nullable) NSTimer *spinTimer;
@property (nonatomic, assign) CGFloat spinPhase;
@end

@implementation BrowserDownloadProgressRingView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        _progress = 0;
        _indeterminate = NO;
        _active = NO;
        self.hidden = YES;
    }
    return self;
}

- (void)dealloc {
    [self stopSpinAnimation];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

- (void)setProgress:(double)progress {
    double clamped = MAX(0.0, MIN(1.0, progress));
    if (fabs(_progress - clamped) < 0.001) {
        return;
    }
    _progress = clamped;
    if (self.isActive && !self.indeterminate) {
        [self setNeedsDisplay:YES];
    }
}

- (void)setIndeterminate:(BOOL)indeterminate {
    if (_indeterminate == indeterminate) {
        return;
    }
    _indeterminate = indeterminate;
    [self updateSpinAnimation];
    [self setNeedsDisplay:YES];
}

- (void)setActive:(BOOL)active {
    if (_active == active) {
        return;
    }
    _active = active;
    self.hidden = !active;
    [self updateSpinAnimation];
    [self setNeedsDisplay:YES];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateSpinAnimation];
}

- (void)updateSpinAnimation {
    if (self.isActive && self.indeterminate && self.window) {
        [self startSpinAnimation];
    } else {
        [self stopSpinAnimation];
    }
}

- (void)startSpinAnimation {
    if (self.spinTimer) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.spinTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                            repeats:YES
                                              block:^(__unused NSTimer *timer) {
        BrowserDownloadProgressRingView *view = weakSelf;
        if (!view) {
            return;
        }
        view.spinPhase += (CGFloat)(M_PI * 2.0 / 30.0); // ~1 turn / sec
        if (view.spinPhase > (CGFloat)(M_PI * 2.0)) {
            view.spinPhase -= (CGFloat)(M_PI * 2.0);
        }
        [view setNeedsDisplay:YES];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.spinTimer forMode:NSRunLoopCommonModes];
}

- (void)stopSpinAnimation {
    [self.spinTimer invalidate];
    self.spinTimer = nil;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (!self.isActive) {
        return;
    }

    NSRect bounds = self.bounds;
    CGFloat lineWidth = 2.0;
    CGFloat inset = lineWidth / 2.0 + 1.5;
    NSRect ringRect = NSInsetRect(bounds, inset, inset);
    if (ringRect.size.width < 4 || ringRect.size.height < 4) {
        return;
    }

    NSColor *trackColor = [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.22];
    NSColor *progressColor = [NSColor controlAccentColor];

    NSBezierPath *track = [NSBezierPath bezierPathWithOvalInRect:ringRect];
    track.lineWidth = lineWidth;
    [trackColor setStroke];
    [track stroke];

    CGFloat startAngle;
    CGFloat endAngle;
    // 0° = east; clockwise from 12 o'clock (90°) for determinate fill.
    if (self.indeterminate) {
        CGFloat sweep = 90.0;
        CGFloat head = 90.0 - (self.spinPhase * 180.0 / (CGFloat)M_PI);
        startAngle = head;
        endAngle = head - sweep;
    } else {
        CGFloat fraction = (CGFloat)MAX(0.02, MIN(1.0, self.progress));
        startAngle = 90.0;
        endAngle = 90.0 - (fraction * 360.0);
    }

    NSBezierPath *arc = [NSBezierPath bezierPath];
    [arc appendBezierPathWithArcWithCenter:NSMakePoint(NSMidX(ringRect), NSMidY(ringRect))
                                    radius:MIN(NSWidth(ringRect), NSHeight(ringRect)) / 2.0
                                startAngle:startAngle
                                  endAngle:endAngle
                                 clockwise:YES];
    arc.lineWidth = lineWidth;
    arc.lineCapStyle = NSLineCapStyleRound;
    [progressColor setStroke];
    [arc stroke];
}

@end
