#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 气泡内容视图。
/// - 悬停：整体穿透，仅复制按钮与洋葱导航可点；
/// - 钉住 / 点复制后：整块可点，正文可选中，带复制/关闭图标按钮。
@interface BrowserDOMInspectorHUDView : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
@property (nonatomic, copy) NSArray<NSString *> *attributeRows;
/// 洋葱导航标签文案（从 body 到当前）。
@property (nonatomic, copy) NSArray<NSString *> *onionLabels;
@property (nonatomic, assign) NSInteger selectedOnionIndex;
@property (nonatomic, assign, getter=isPinnedAppearance) BOOL pinnedAppearance;
@property (nonatomic, copy, nullable) void (^onCopySelector)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) void (^onRequestInteractiveLock)(void);
@property (nonatomic, copy, nullable) void (^onSelectOnionIndex)(NSInteger index);
- (void)reloadPinnedContent;
- (void)layoutChrome;
- (void)rebuildOnionButtons;
@end

/// DOM 探针悬停气泡。
@interface BrowserDOMInspectorHUD : NSObject

- (void)showSnapshot:(NSDictionary *)snapshot
   geometryInContent:(NSRect)geometry
     webViewInContent:(NSRect)webViewRect
            inWindow:(NSWindow *)window
              pinned:(BOOL)pinned;

- (void)lockInteractiveWithCurrentSnapshot;

@property (nonatomic, copy, nullable) void (^onCopySelector)(NSString *selector);
@property (nonatomic, copy, nullable) void (^onClosePinned)(void);
@property (nonatomic, copy, nullable) void (^onInteractiveLockFromCopy)(void);

- (void)hide;

@end

NS_ASSUME_NONNULL_END
