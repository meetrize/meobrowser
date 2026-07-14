#import "BrowserLoadingProgressView.h"
#import <QuartzCore/QuartzCore.h>

const CGFloat BrowserLoadingProgressHeight = 2.0;

static const NSTimeInterval kCompleteHoldDuration = 0.18;
static const NSTimeInterval kFadeOutDuration = 0.22;
static const CGFloat kMinimumVisibleProgress = 0.02;

@interface BrowserLoadingProgressView ()
@property (nonatomic, strong) CALayer *fillLayer;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) NSInteger hideGeneration;
@end

@implementation BrowserLoadingProgressView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;

        _fillLayer = [CALayer layer];
        _fillLayer.anchorPoint = CGPointZero;
        [self.layer addSublayer:_fillLayer];
        [self updateFillColor];

        self.hidden = YES;
        self.alphaValue = 0.0;
        self.progress = 0.0;
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateFillColor];
}

- (void)updateFillColor {
    self.fillLayer.backgroundColor = NSColor.controlAccentColor.CGColor;
}

- (void)layout {
    [super layout];
    [self updateFillFrameAnimated:NO];
}

- (CGFloat)visualProgress {
    if (!self.active) {
        return 0.0;
    }
    return MAX(kMinimumVisibleProgress, MIN(1.0, self.progress));
}

- (void)updateFillFrameAnimated:(BOOL)animated {
    CGFloat width = NSWidth(self.bounds) * (CGFloat)[self visualProgress];
    CGRect frame = CGRectMake(0.0, 0.0, width, NSHeight(self.bounds));
    [CATransaction begin];
    if (animated) {
        [CATransaction setAnimationDuration:0.12];
        [CATransaction setAnimationTimingFunction:
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    } else {
        [CATransaction setDisableActions:YES];
    }
    self.fillLayer.frame = frame;
    [CATransaction commit];
}

- (void)beginLoading {
    self.hideGeneration += 1;
    self.active = YES;
    self.progress = 0.0;
    self.hidden = NO;
    self.alphaValue = 1.0;
    [self updateFillFrameAnimated:NO];
}

- (void)setProgress:(double)progress animated:(BOOL)animated {
    double clamped = MAX(0.0, MIN(1.0, progress));
    if (!self.active) {
        if (clamped <= 0.0 || clamped >= 1.0) {
            return;
        }
        [self beginLoading];
    }

    self.progress = clamped;
    [self updateFillFrameAnimated:animated];

    if (clamped >= 1.0) {
        [self completeIfVisible];
    }
}

- (void)completeIfVisible {
    if (!self.active && self.hidden) {
        return;
    }

    self.active = YES;
    self.progress = 1.0;
    self.hidden = NO;
    self.alphaValue = 1.0;
    [self updateFillFrameAnimated:YES];

    NSInteger generation = ++self.hideGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCompleteHoldDuration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BrowserLoadingProgressView *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.hideGeneration != generation) {
            return;
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = kFadeOutDuration;
            strongSelf.animator.alphaValue = 0.0;
        } completionHandler:^{
            BrowserLoadingProgressView *finished = weakSelf;
            if (!finished || finished.hideGeneration != generation) {
                return;
            }
            [finished resetHidden];
        }];
    });
}

- (void)resetHidden {
    self.hideGeneration += 1;
    self.active = NO;
    self.progress = 0.0;
    self.alphaValue = 0.0;
    self.hidden = YES;
    [self updateFillFrameAnimated:NO];
}

@end
