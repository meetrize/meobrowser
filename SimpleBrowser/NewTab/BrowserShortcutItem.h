#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserShortcutItemKind) {
    BrowserShortcutItemKindLink = 0,
    BrowserShortcutItemKindFolder = 1,
};

/// 图标样式：自动 Favicon / 自定义首字母色块。
FOUNDATION_EXPORT NSString * const BrowserShortcutIconStyleAuto;
FOUNDATION_EXPORT NSString * const BrowserShortcutIconStyleLetter;

@interface BrowserShortcutItem : NSObject

@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *iconURLString;
@property (nonatomic, assign) NSInteger sortOrder;
@property (nonatomic, assign) BrowserShortcutItemKind kind;
@property (nonatomic, copy) NSString *folderID;

/// `auto` 或 `letter`；缺省 / 未知视为 auto。
@property (nonatomic, copy) NSString *iconStyle;
/// letter 模式下展示用字母；空则运行时从 title/url 推导。
@property (nonatomic, copy) NSString *iconLetter;
/// letter 模式下色板索引 0–15。
@property (nonatomic, assign) NSInteger iconColorIndex;

/// 仅用于地址栏建议展示，不参与快捷方式持久化。
@property (nonatomic, assign, getter=isFromHistory) BOOL fromHistory;

@property (nonatomic, readonly, getter=isFolder) BOOL folder;
@property (nonatomic, readonly, getter=isTopLevel) BOOL topLevel;
/// 是否使用自定义首字母色块（仅 link 有意义）。
@property (nonatomic, readonly, getter=usesCustomLetterIcon) BOOL usesCustomLetterIcon;

+ (instancetype)itemWithTitle:(NSString *)title
                    urlString:(NSString *)urlString
                 iconURLString:(NSString *)iconURLString
                    sortOrder:(NSInteger)sortOrder;

+ (instancetype)folderWithTitle:(NSString *)title sortOrder:(NSInteger)sortOrder;

@end

NS_ASSUME_NONNULL_END
