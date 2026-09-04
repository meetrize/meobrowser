#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString *MeoSitePathMatchMode NS_TYPED_EXTENSIBLE_ENUM;
/// 路径前缀匹配（默认，兼容旧 pathPrefix）。
FOUNDATION_EXPORT MeoSitePathMatchMode const MeoSitePathMatchModePrefix;
/// 通配：`*` 任意字符，`?` 单字符。
FOUNDATION_EXPORT MeoSitePathMatchMode const MeoSitePathMatchModeWildcard;

/// 登录助手 / 表单备忘共用：host + 可选 port + 路径模式。
@interface MeoSiteMatch : NSObject

+ (nullable NSString *)normalizedHostForURL:(NSURL *)url;
/// 非默认端口返回 NSNumber；http/80、https/443、无端口返回 nil。file 返回 nil。
+ (nullable NSNumber *)portNumberForURL:(NSURL *)url;
/// 当前页完整 path；`/` 或空 → nil。file → lastPathComponent。
+ (nullable NSString *)pathPatternForURL:(NSURL *)url;
/// 展示用「host:port」或 host。
+ (NSString *)scopeDisplayStringForHost:(NSString *)host port:(nullable NSNumber *)port;
/// 合成可编辑匹配串：`host[:port][/path]`（path 可含通配）。
+ (NSString *)sitePatternForHost:(NSString *)host
                            port:(nullable NSNumber *)port
                     pathPattern:(nullable NSString *)pathPattern;
/// 解析匹配串；支持可选 `http(s)://`；`?` 视为路径通配而非 query。
+ (BOOL)parseSitePattern:(NSString *)pattern
                    host:(NSString * _Nullable * _Nonnull)outHost
                    port:(NSNumber * _Nullable * _Nonnull)outPort
             pathPattern:(NSString * _Nullable * _Nonnull)outPathPattern;
/// 含 `*`/`?` → wildcard，否则 prefix。
+ (MeoSitePathMatchMode)inferredPathMatchModeForPattern:(nullable NSString *)pathPattern;

+ (BOOL)matchesURL:(NSURL *)url
              host:(NSString *)host
              port:(nullable NSNumber *)port
       pathPattern:(nullable NSString *)pathPattern
              mode:(nullable MeoSitePathMatchMode)mode;

/// 表单保存：是否复用已有条目（同 host+port+精确 path；不把「整站/任意端口」条目当成当前页专用）。
+ (BOOL)shouldReuseHost:(NSString *)host
                   port:(nullable NSNumber *)port
            pathPattern:(nullable NSString *)pathPattern
                   mode:(nullable MeoSitePathMatchMode)mode
           forSavingURL:(NSURL *)url;

/// 具体度：越大越优先（有 port、更长 path、通配略低于等长前缀）。
+ (NSInteger)specificityScoreForHost:(NSString *)host
                                port:(nullable NSNumber *)port
                         pathPattern:(nullable NSString *)pathPattern
                                mode:(nullable MeoSitePathMatchMode)mode;

@end

NS_ASSUME_NONNULL_END
