#import "BrowserLaunchpadAppearancePanel.h"
#import "BrowserLaunchpadAppearance.h"
#import "BrowserWallpaperStore.h"

@interface BrowserLaunchpadAppearancePanel ()
@property (nonatomic, strong) NSSegmentedControl *presetControl;
@property (nonatomic, strong) NSSlider *iconSizeSlider;
@property (nonatomic, strong) NSSlider *horizontalSpacingSlider;
@property (nonatomic, strong) NSSlider *verticalSpacingSlider;
@property (nonatomic, strong) NSTextField *iconSizeValueLabel;
@property (nonatomic, strong) NSTextField *horizontalSpacingValueLabel;
@property (nonatomic, strong) NSTextField *verticalSpacingValueLabel;
@property (nonatomic, strong) NSButton *wallpaperEnabledCheckbox;
@property (nonatomic, strong) NSButton *chooseWallpaperButton;
@property (nonatomic, strong) NSButton *clearWallpaperButton;
@property (nonatomic, strong) NSTextField *wallpaperFileLabel;
@property (nonatomic, strong) NSSlider *scrimSlider;
@property (nonatomic, strong) NSTextField *scrimValueLabel;
@property (nonatomic, assign) BOOL updatingUI;
@property (nonatomic, assign) BOOL didBuildUI;
@end

@implementation BrowserLaunchpadAppearancePanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSSize size = [[self class] preferredPanelSize];
    if (NSIsEmptyRect(frameRect) || frameRect.size.width < 1 || frameRect.size.height < 1) {
        frameRect = NSMakeRect(0, 0, size.width, size.height);
    }
    self = [super initWithFrame:frameRect];
    if (self) {
        [self buildUI];
        [self reloadFromAppearance];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(wallpaperDidChange:)
                                                     name:BrowserWallpaperDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self buildUI];
        [self reloadFromAppearance];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(wallpaperDidChange:)
                                                     name:BrowserWallpaperDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSSize)preferredPanelSize {
    return NSMakeSize(288, 392);
}

- (NSSize)preferredContentSize {
    return [[self class] preferredPanelSize];
}

- (NSTextField *)makeCaption:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    label.textColor = NSColor.secondaryLabelColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSTextField *)makeValueLabel {
    NSTextField *label = [NSTextField labelWithString:@"0"];
    label.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    label.textColor = NSColor.secondaryLabelColor;
    label.alignment = NSTextAlignmentRight;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label.widthAnchor constraintGreaterThanOrEqualToConstant:36].active = YES;
    return label;
}

- (NSSlider *)makeSliderMin:(CGFloat)minValue max:(CGFloat)maxValue action:(SEL)action {
    NSSlider *slider = [NSSlider sliderWithValue:minValue
                                        minValue:minValue
                                        maxValue:maxValue
                                          target:self
                                          action:action];
    slider.continuous = YES;
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    return slider;
}

- (NSView *)rowWithCaption:(NSString *)caption
                    slider:(NSSlider *)slider
                valueLabel:(NSTextField *)valueLabel {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [self makeCaption:caption];
    [row addSubview:title];
    [row addSubview:valueLabel];
    [row addSubview:slider];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:row.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],

        [valueLabel.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8],

        [slider.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [slider.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [slider.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [slider.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (void)buildUI {
    if (self.didBuildUI) {
        return;
    }
    self.didBuildUI = YES;
    self.wantsLayer = YES;

    self.presetControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.presetControl.segmentCount = 3;
    self.presetControl.segmentStyle = NSSegmentStyleRounded;
    self.presetControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    [self.presetControl setLabel:@"紧凑" forSegment:0];
    [self.presetControl setLabel:@"舒适" forSegment:1];
    [self.presetControl setLabel:@"宽松" forSegment:2];
    for (NSInteger i = 0; i < 3; i++) {
        [self.presetControl setWidth:0 forSegment:i];
    }
    self.presetControl.target = self;
    self.presetControl.action = @selector(presetChanged:);
    self.presetControl.translatesAutoresizingMaskIntoConstraints = NO;

    self.iconSizeSlider = [self makeSliderMin:[BrowserLaunchpadAppearance minIconSize]
                                          max:[BrowserLaunchpadAppearance maxIconSize]
                                       action:@selector(iconSizeChanged:)];
    self.horizontalSpacingSlider = [self makeSliderMin:[BrowserLaunchpadAppearance minHorizontalSpacing]
                                                   max:[BrowserLaunchpadAppearance maxHorizontalSpacing]
                                                action:@selector(horizontalSpacingChanged:)];
    self.verticalSpacingSlider = [self makeSliderMin:[BrowserLaunchpadAppearance minVerticalSpacing]
                                                 max:[BrowserLaunchpadAppearance maxVerticalSpacing]
                                              action:@selector(verticalSpacingChanged:)];

    self.iconSizeValueLabel = [self makeValueLabel];
    self.horizontalSpacingValueLabel = [self makeValueLabel];
    self.verticalSpacingValueLabel = [self makeValueLabel];

    NSView *iconRow = [self rowWithCaption:@"图标大小"
                                    slider:self.iconSizeSlider
                                valueLabel:self.iconSizeValueLabel];
    NSView *hRow = [self rowWithCaption:@"左右间距"
                                 slider:self.horizontalSpacingSlider
                             valueLabel:self.horizontalSpacingValueLabel];
    NSView *vRow = [self rowWithCaption:@"上下间距"
                                 slider:self.verticalSpacingSlider
                             valueLabel:self.verticalSpacingValueLabel];

    NSButton *resetButton = [NSButton buttonWithTitle:@"恢复默认" target:self action:@selector(resetDefaults:)];
    resetButton.bezelStyle = NSBezelStyleInline;
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *backgroundCaption = [self makeCaption:@"背景"];

    self.wallpaperEnabledCheckbox = [NSButton checkboxWithTitle:@"使用背景图片"
                                                         target:self
                                                         action:@selector(wallpaperEnabledChanged:)];
    self.wallpaperEnabledCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    self.wallpaperEnabledCheckbox.font = [NSFont systemFontOfSize:13];

    self.chooseWallpaperButton = [NSButton buttonWithTitle:@"选择图片…"
                                                    target:self
                                                    action:@selector(chooseWallpaper:)];
    self.chooseWallpaperButton.bezelStyle = NSBezelStyleRounded;
    self.chooseWallpaperButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.clearWallpaperButton = [NSButton buttonWithTitle:@"清除"
                                                   target:self
                                                   action:@selector(clearWallpaper:)];
    self.clearWallpaperButton.bezelStyle = NSBezelStyleRounded;
    self.clearWallpaperButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.wallpaperFileLabel = [NSTextField labelWithString:@"未选择图片"];
    self.wallpaperFileLabel.font = [NSFont systemFontOfSize:11];
    self.wallpaperFileLabel.textColor = NSColor.tertiaryLabelColor;
    self.wallpaperFileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.wallpaperFileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.wallpaperFileLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.scrimSlider = [self makeSliderMin:0 max:70 action:@selector(scrimChanged:)];
    self.scrimValueLabel = [self makeValueLabel];
    NSView *scrimRow = [self rowWithCaption:@"压暗"
                                     slider:self.scrimSlider
                                 valueLabel:self.scrimValueLabel];

    NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    [content addSubview:self.presetControl];
    [content addSubview:iconRow];
    [content addSubview:hRow];
    [content addSubview:vRow];
    [content addSubview:resetButton];
    [content addSubview:backgroundCaption];
    [content addSubview:self.wallpaperEnabledCheckbox];
    [content addSubview:self.chooseWallpaperButton];
    [content addSubview:self.clearWallpaperButton];
    [content addSubview:self.wallpaperFileLabel];
    [content addSubview:scrimRow];

    static const CGFloat kInset = 16.0;
    static const CGFloat kGap = 14.0;

    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:[self preferredContentSize].width],
        [self.heightAnchor constraintEqualToConstant:[self preferredContentSize].height],

        [content.topAnchor constraintEqualToAnchor:self.topAnchor constant:kInset],
        [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kInset],
        [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kInset],
        [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-kInset],

        [self.presetControl.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.presetControl.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.presetControl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [iconRow.topAnchor constraintEqualToAnchor:self.presetControl.bottomAnchor constant:kGap],
        [iconRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [iconRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [hRow.topAnchor constraintEqualToAnchor:iconRow.bottomAnchor constant:kGap],
        [hRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [hRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [vRow.topAnchor constraintEqualToAnchor:hRow.bottomAnchor constant:kGap],
        [vRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [vRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [resetButton.topAnchor constraintEqualToAnchor:vRow.bottomAnchor constant:kGap],
        [resetButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],

        [backgroundCaption.topAnchor constraintEqualToAnchor:resetButton.bottomAnchor constant:kGap + 2],
        [backgroundCaption.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],

        [self.wallpaperEnabledCheckbox.topAnchor constraintEqualToAnchor:backgroundCaption.bottomAnchor constant:6],
        [self.wallpaperEnabledCheckbox.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],

        [self.chooseWallpaperButton.topAnchor constraintEqualToAnchor:self.wallpaperEnabledCheckbox.bottomAnchor constant:8],
        [self.chooseWallpaperButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],

        [self.clearWallpaperButton.centerYAnchor constraintEqualToAnchor:self.chooseWallpaperButton.centerYAnchor],
        [self.clearWallpaperButton.leadingAnchor constraintEqualToAnchor:self.chooseWallpaperButton.trailingAnchor constant:8],

        [self.wallpaperFileLabel.topAnchor constraintEqualToAnchor:self.chooseWallpaperButton.bottomAnchor constant:6],
        [self.wallpaperFileLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.wallpaperFileLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [scrimRow.topAnchor constraintEqualToAnchor:self.wallpaperFileLabel.bottomAnchor constant:10],
        [scrimRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scrimRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scrimRow.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor],
    ]];
}

- (void)wallpaperDidChange:(NSNotification *)notification {
    // 压暗拖动时面板已自行更新滑杆；再 reload 会与 continuous slider 打架。
    NSString *reason = notification.userInfo[BrowserWallpaperChangeReasonKey];
    if ([reason isEqualToString:@"scrim"]) {
        return;
    }
    [self reloadWallpaperControls];
}

- (void)reloadFromAppearance {
    if (!self.didBuildUI) {
        return;
    }
    BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
    self.updatingUI = YES;
    self.iconSizeSlider.doubleValue = appearance.iconSize;
    self.horizontalSpacingSlider.doubleValue = appearance.horizontalSpacing;
    self.verticalSpacingSlider.doubleValue = appearance.verticalSpacing;
    [self updateValueLabels];
    [self updatePresetSelection];
    self.updatingUI = NO;
    [self reloadWallpaperControls];
}

- (void)reloadWallpaperControls {
    if (!self.didBuildUI) {
        return;
    }
    BrowserWallpaperStore *store = [BrowserWallpaperStore sharedStore];
    self.updatingUI = YES;
    BOOL hasFile = store.hasDisplayFile;
    self.wallpaperEnabledCheckbox.state = (hasFile && store.enabledFlag) ? NSControlStateValueOn : NSControlStateValueOff;
    self.clearWallpaperButton.enabled = hasFile;
    self.scrimSlider.enabled = hasFile;
    self.scrimSlider.doubleValue = store.scrimAlpha * 100.0;
    self.scrimValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", store.scrimAlpha * 100.0];
    if (hasFile && store.sourceFileName.length > 0) {
        self.wallpaperFileLabel.stringValue = store.sourceFileName;
    } else if (hasFile) {
        self.wallpaperFileLabel.stringValue = @"已设置背景";
    } else {
        self.wallpaperFileLabel.stringValue = @"未选择图片";
    }
    self.updatingUI = NO;
}

- (void)updateValueLabels {
    self.iconSizeValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", self.iconSizeSlider.doubleValue];
    self.horizontalSpacingValueLabel.stringValue =
        [NSString stringWithFormat:@"%.0f", self.horizontalSpacingSlider.doubleValue];
    self.verticalSpacingValueLabel.stringValue =
        [NSString stringWithFormat:@"%.0f", self.verticalSpacingSlider.doubleValue];
}

- (void)updatePresetSelection {
    BrowserLaunchpadAppearance *appearance = [BrowserLaunchpadAppearance current];
    NSInteger selected = -1;
    if (fabs(appearance.iconSize - 52) < 0.5
        && fabs(appearance.horizontalSpacing - 16) < 0.5
        && fabs(appearance.verticalSpacing - 16) < 0.5) {
        selected = 0;
    } else if (fabs(appearance.iconSize - [BrowserLaunchpadAppearance defaultIconSize]) < 0.5
               && fabs(appearance.horizontalSpacing - [BrowserLaunchpadAppearance defaultHorizontalSpacing]) < 0.5
               && fabs(appearance.verticalSpacing - [BrowserLaunchpadAppearance defaultVerticalSpacing]) < 0.5) {
        selected = 1;
    } else if (fabs(appearance.iconSize - 72) < 0.5
               && fabs(appearance.horizontalSpacing - 48) < 0.5
               && fabs(appearance.verticalSpacing - 40) < 0.5) {
        selected = 2;
    }
    self.presetControl.selectedSegment = selected;
}

- (void)iconSizeChanged:(NSSlider *)sender {
    if (self.updatingUI) {
        return;
    }
    [BrowserLaunchpadAppearance setIconSize:sender.doubleValue];
    [self updateValueLabels];
    [self updatePresetSelection];
}

- (void)horizontalSpacingChanged:(NSSlider *)sender {
    if (self.updatingUI) {
        return;
    }
    [BrowserLaunchpadAppearance setHorizontalSpacing:sender.doubleValue];
    [self updateValueLabels];
    [self updatePresetSelection];
}

- (void)verticalSpacingChanged:(NSSlider *)sender {
    if (self.updatingUI) {
        return;
    }
    [BrowserLaunchpadAppearance setVerticalSpacing:sender.doubleValue];
    [self updateValueLabels];
    [self updatePresetSelection];
}

- (void)presetChanged:(NSSegmentedControl *)sender {
    if (self.updatingUI) {
        return;
    }
    BrowserLaunchpadAppearancePreset preset = BrowserLaunchpadAppearancePresetComfortable;
    switch (sender.selectedSegment) {
        case 0:
            preset = BrowserLaunchpadAppearancePresetCompact;
            break;
        case 2:
            preset = BrowserLaunchpadAppearancePresetSpacious;
            break;
        case 1:
        default:
            preset = BrowserLaunchpadAppearancePresetComfortable;
            break;
    }
    [BrowserLaunchpadAppearance applyPreset:preset];
    [self reloadFromAppearance];
}

- (void)resetDefaults:(id)sender {
    (void)sender;
    [BrowserLaunchpadAppearance resetToDefaults];
    [self reloadFromAppearance];
}

- (void)wallpaperEnabledChanged:(NSButton *)sender {
    if (self.updatingUI) {
        return;
    }
    BrowserWallpaperStore *store = [BrowserWallpaperStore sharedStore];
    if (sender.state == NSControlStateValueOn) {
        if (!store.hasDisplayFile) {
            sender.state = NSControlStateValueOff;
            [self chooseWallpaper:nil];
            return;
        }
        [store setWallpaperEnabled:YES];
    } else {
        [store setWallpaperEnabled:NO];
    }
}

- (void)chooseWallpaper:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = [NSImage imageTypes];
#pragma clang diagnostic pop
    panel.message = @"选择新标签页背景图片";

    NSWindow *hostWindow = self.window;
    void (^handle)(NSModalResponse) = ^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        __weak typeof(self) weakSelf = self;
        [[BrowserWallpaperStore sharedStore] importImageFromURL:panel.URL
                                                     completion:^(NSError *error) {
            if (error == nil) {
                [weakSelf reloadWallpaperControls];
                return;
            }
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"无法设置背景图片";
            alert.informativeText = error.localizedDescription ?: @"";
            NSWindow *window = weakSelf.window ?: hostWindow;
            if (window != nil) {
                [alert beginSheetModalForWindow:window completionHandler:nil];
            } else {
                [alert runModal];
            }
        }];
    };

    if (hostWindow != nil) {
        [panel beginSheetModalForWindow:hostWindow completionHandler:handle];
    } else {
        handle([panel runModal]);
    }
}

- (void)clearWallpaper:(id)sender {
    (void)sender;
    [[BrowserWallpaperStore sharedStore] clearWallpaper];
    [self reloadWallpaperControls];
}

- (void)scrimChanged:(NSSlider *)sender {
    if (self.updatingUI) {
        return;
    }
    CGFloat alpha = sender.doubleValue / 100.0;
    self.scrimValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", sender.doubleValue];
    [[BrowserWallpaperStore sharedStore] setScrimAlpha:alpha];
}

@end
