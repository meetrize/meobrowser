#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DomSegmentKind) {
    /// 普通原文片段
    DomSegmentKindLiteral = 0,
    /// 标识符，如 row
    DomSegmentKindIdentifier,
    /// 方括号键，如 [price]
    DomSegmentKindBracketKey,
    /// JSON 树中的一个叶子
    DomSegmentKindJSONLeaf,
};

/// 一个可复制的分段。
@interface DomValueSegment : NSObject

@property (nonatomic, readonly) DomSegmentKind kind;
/// 该段原文（点击即复制它）。
@property (nonatomic, readonly, copy) NSString *text;
/// 复制完整路径时使用，如 "data-row → row → price"。rootPath 为所属属性名。
@property (nonatomic, readonly, copy) NSString *fullPath;
/// 缩进层级，用于树形渲染。
@property (nonatomic, readonly) NSUInteger depth;

- (instancetype)initWithKind:(DomSegmentKind)kind
                         text:(NSString *)text
                    fullPath:(NSString *)fullPath
                       depth:(NSUInteger)depth NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// 属性值分段器。规则优先级：R6 括号键值 → R1 JSON → R2 标识符[] → R3 分隔符 → R5 超长截断。
@interface BrowserDOMValueSegmenter : NSObject

/// 对单个值分段。rootPath 一般传属性名（如 data-row），用于「复制完整路径」。
+ (NSArray<DomValueSegment *> *)segmentsForValue:(nullable NSString *)value
                                         rootPath:(nullable NSString *)rootPath;

/// 该值是否需要分段展示（否则按单段处理）。
+ (BOOL)shouldSegmentValue:(nullable NSString *)value;

@end

NS_ASSUME_NONNULL_END
