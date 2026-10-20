#import <Cocoa/Cocoa.h>

@class DomValueSegment;

NS_ASSUME_NONNULL_BEGIN

/// 一条「属性名 : 值」的行。值区按分段渲染，每个分段可点击复制 / 右键复制。
@interface BrowserDOMInspectorRowView : NSView

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *rawValue;

/// 复制成功后的对外通知，用于 toast。
@property (nonatomic, copy, nullable) void (^onCopy)(NSString *description);

- (instancetype)initWithName:(NSString *)name
                        kind:(nullable NSString *)kind
                        value:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
