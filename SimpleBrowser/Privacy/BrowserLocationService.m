#import "BrowserLocationService.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@interface BrowserLocationWatch : NSObject
@property (nonatomic, copy) NSString *requestId;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, assign) BOOL highAccuracy;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy) void (^completion)(CLLocation * _Nullable, NSError * _Nullable);
@end

@implementation BrowserLocationWatch
@end

@interface BrowserLocationService () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, copy, nullable) void (^pendingAuthorizationCompletion)(BOOL granted);
@property (nonatomic, copy, nullable) void (^pendingLocationCompletion)(CLLocation * _Nullable, NSError * _Nullable);
@property (nonatomic, strong, nullable) NSTimer *locationTimeoutTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BrowserLocationWatch *> *activeWatches;
@end

@implementation BrowserLocationService

+ (instancetype)sharedService {
    static BrowserLocationService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[self alloc] init];
    });
    return service;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _activeWatches = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (CLAuthorizationStatus)currentAuthorizationStatus {
    BrowserLocationService *service = [self sharedService];
    if (@available(macOS 11.0, *)) {
        return service.locationManager.authorizationStatus;
    }
    return kCLAuthorizationStatusNotDetermined;
}

+ (BOOL)isSystemLocationAuthorized {
    CLAuthorizationStatus status = [self currentAuthorizationStatus];
    if (@available(macOS 11.0, *)) {
        return status == kCLAuthorizationStatusAuthorizedAlways;
    }
    return status == kCLAuthorizationStatusAuthorized;
}

+ (NSString *)systemAuthorizationStatusDescription {
    switch ([self currentAuthorizationStatus]) {
        case kCLAuthorizationStatusAuthorizedAlways:
            return @"系统定位：已授权";
        case kCLAuthorizationStatusDenied:
            return @"系统定位：已关闭";
        case kCLAuthorizationStatusRestricted:
            return @"系统定位：受限制";
        case kCLAuthorizationStatusNotDetermined:
        default:
            return @"系统定位：尚未授权";
    }
}

+ (void)ensureSystemAuthorizationWithCompletion:(void (^)(BOOL granted))completion {
    if ([self isSystemLocationAuthorized]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES);
            });
        }
        return;
    }
    CLAuthorizationStatus status = [self currentAuthorizationStatus];
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
        }
        return;
    }

    BrowserLocationService *service = [self sharedService];
    service.pendingAuthorizationCompletion = ^(BOOL granted) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(granted);
            });
        }
    };
    [service.locationManager requestWhenInUseAuthorization];
}

+ (void)fetchCurrentLocationWithHighAccuracy:(BOOL)highAccuracy
                                     timeout:(NSTimeInterval)timeout
                              watchRequestId:(NSString *)watchRequestId
                                     webView:(WKWebView *)webView
                                  completion:(void (^)(CLLocation * _Nullable, NSError * _Nullable))completion {
    BrowserLocationService *service = [self sharedService];
    if (watchRequestId.length > 0) {
        BrowserLocationWatch *watch = [[BrowserLocationWatch alloc] init];
        watch.requestId = watchRequestId;
        watch.webView = webView;
        watch.highAccuracy = highAccuracy;
        watch.timeout = timeout;
        watch.completion = completion;
        service.activeWatches[watchRequestId] = watch;
    } else {
        service.pendingLocationCompletion = completion;
    }
    [service beginLocationRequestWithHighAccuracy:highAccuracy timeout:timeout];
}

+ (void)cancelWatchRequestId:(NSString *)watchRequestId {
    if (watchRequestId.length == 0) {
        return;
    }
    BrowserLocationService *service = [self sharedService];
    [service.activeWatches removeObjectForKey:watchRequestId];
    if (service.activeWatches.count == 0) {
        [service.locationManager stopUpdatingLocation];
    }
}

- (void)beginLocationRequestWithHighAccuracy:(BOOL)highAccuracy timeout:(NSTimeInterval)timeout {
    [self.locationTimeoutTimer invalidate];
    self.locationTimeoutTimer = nil;

    self.locationManager.desiredAccuracy = highAccuracy
        ? kCLLocationAccuracyBest
        : kCLLocationAccuracyHundredMeters;

    if (self.activeWatches.count > 0) {
        [self.locationManager startUpdatingLocation];
    } else {
        [self.locationManager requestLocation];
    }

    __weak typeof(self) weakSelf = self;
    self.locationTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(1.0, timeout)
                                                                repeats:NO
                                                                  block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf finishLocationRequestWithLocation:nil
                                                error:[NSError errorWithDomain:@"MeoGeolocation"
                                                                          code:3
                                                                      userInfo:@{NSLocalizedDescriptionKey: @"timeout expired"}]];
    }];
}

- (void)finishLocationRequestWithLocation:(CLLocation *)location error:(NSError *)error {
    [self.locationTimeoutTimer invalidate];
    self.locationTimeoutTimer = nil;

    if (self.pendingLocationCompletion) {
        void (^completion)(CLLocation *, NSError *) = self.pendingLocationCompletion;
        self.pendingLocationCompletion = nil;
        completion(location, error);
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    (void)manager;
    if (!self.pendingAuthorizationCompletion) {
        return;
    }
    void (^completion)(BOOL) = self.pendingAuthorizationCompletion;
    self.pendingAuthorizationCompletion = nil;
    completion([[self class] isSystemLocationAuthorized]);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    (void)manager;
    CLLocation *location = locations.lastObject;
    if (!location) {
        return;
    }

    if (self.pendingLocationCompletion) {
        [self finishLocationRequestWithLocation:location error:nil];
        return;
    }

    for (BrowserLocationWatch *watch in self.activeWatches.allValues) {
        if (watch.completion) {
            watch.completion(location, nil);
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    if (self.pendingLocationCompletion) {
        [self finishLocationRequestWithLocation:nil error:error];
        return;
    }
    for (BrowserLocationWatch *watch in self.activeWatches.allValues) {
        if (watch.completion) {
            watch.completion(nil, error);
        }
    }
}

+ (void)openSystemLocationSettings {
    NSURL *url = nil;
    if (@available(macOS 13.0, *)) {
        url = [NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices"];
    }
    if (!url) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"];
    }
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

@end
