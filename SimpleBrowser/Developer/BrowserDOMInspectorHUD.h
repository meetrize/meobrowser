#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 气泡内容视图。
/// - 悬停：整体穿透，仅「复制」按钮可点；
/// - 钉住 / 点复制后：整块可点，正文可选中，带复制/关闭按钮。
@interface BrowserDOMInspectorHUDView : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
@property (nonatomic, copy) NSArray<NSString *> *attributeRows;
@property (nonatomic, assign, getter=isPinnedAppearance) BOOL pinnedAppearance;
@property (nonatomic, copy, nullable) void (^onCopySelector)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
/// 悬停态点「复制」后请求进入可交互锁定态（由 HUD 控制器放大并回调上层）。
@property (nonatomic, copy, nullable) void (^onRequestInteractiveLock)(void);
- (void)reloadPinnedContent;
- (void)layoutChrome;
@end

/// DOM 探针悬停气泡。
@interface BrowserDOMInspectorHUD : NSObject

- (void)showSnapshot:(NSDictionary *)snapshot
   geometryInContent:(NSRect)geometry
     webViewInContent:(NSRect)webViewRect
            inWindow:(NSWindow *)window
              pinned:(BOOL)pinned;

/// 在悬停内容上锁定为可交互（点复制后调用）。
- (void)lockInteractiveWithCurrentSnapshot;

@property (nonatomic, copy, nullable) void (^onCopySelector)(NSString *selector);
@property (nonatomic, copy, nullable) void (^onClosePinned)(void);
/// 悬停态点复制：请求上层冻结 hover（并尽量钉住页面元素）。
@property (nonatomic, copy, nullable) void (^onInteractiveLockFromCopy)(void);

- (void)hide;

@end

NS_ASSUME_NONNULL_END
