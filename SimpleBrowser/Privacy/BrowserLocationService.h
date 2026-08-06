#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

/// macOS 系统定位授权检测与跳转系统设置。
@interface BrowserLocationService : NSObject

+ (instancetype)sharedService;

+ (BOOL)isSystemLocationAuthorized;
+ (NSString *)systemAuthorizationStatusDescription;

/// 尚未授权时弹出系统定位授权对话框；已授权或已拒绝则立即回调。completion 在主线程。
+ (void)ensureSystemAuthorizationWithCompletion:(void (^)(BOOL granted))completion;

/// 获取当前坐标；watchRequestId 非空时持续回调同一 requestId（watchPosition）。
+ (void)fetchCurrentLocationWithHighAccuracy:(BOOL)highAccuracy
                                     timeout:(NSTimeInterval)timeout
                              watchRequestId:(nullable NSString *)watchRequestId
                                     webView:(WKWebView *)webView
                                  completion:(void (^)(CLLocation * _Nullable location, NSError * _Nullable error))completion;

+ (void)cancelWatchRequestId:(NSString *)watchRequestId;

+ (void)openSystemLocationSettings;

@end

NS_ASSUME_NONNULL_END
