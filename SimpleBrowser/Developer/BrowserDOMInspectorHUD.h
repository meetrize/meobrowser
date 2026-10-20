#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 气泡内容视图。
/// - 悬停：整体穿透，仅复制按钮与洋葱导航可点；
/// - 钉住 / 点复制后：整块可点，正文可选中，带复制/关闭图标按钮。
@interface BrowserDOMInspectorHUDView : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
/// 节点完整 HTML 预览（scrub 后的 outerHTML），显示在属性区顶部。
@property (nonatomic, copy) NSString *htmlPreview;
/// HTML 预览是否已展开（默认折叠为最多 3 行）。
@property (nonatomic, assign) BOOL htmlPreviewExpanded;
@property (nonatomic, copy) NSArray<NSString *> *attributeRows;
/// 内容高度可能变化（如展开 HTML）时通知外层重新布局。
@property (nonatomic, copy, nullable) void (^onContentSizeMayChange)(void);
/// 洋葱导航标签文案（从 body 到当前）。
@property (nonatomic, copy) NSArray<NSString *> *onionLabels;
@property (nonatomic, assign) NSInteger selectedOnionIndex;
@property (nonatomic, assign, getter=isPinnedAppearance) BOOL pinnedAppearance;
/// 用户是否已拖拽过气泡（改尺寸时保留原点）。
@property (nonatomic, assign) BOOL userRepositioned;
/// 用户是否已拖拽边缘/角调整过大小（内容刷新时保留尺寸）。
@property (nonatomic, assign) BOOL userResized;
@property (nonatomic, copy, nullable) void (^onCopySelector)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) void (^onRequestInteractiveLock)(void);
@property (nonatomic, copy, nullable) void (^onSelectOnionIndex)(NSInteger index);
/// 属性段点击复制后回调（用于 toast）。
@property (nonatomic, copy, nullable) void (^onCopiedSegment)(NSString *segment);
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
@property (nonatomic, copy, nullable) void (^onCopiedSegment)(NSString *segment);

- (void)hide;

@end

NS_ASSUME_NONNULL_END
