#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class WKDownload;

typedef NS_ENUM(NSInteger, BrowserDownloadState) {
    BrowserDownloadStatePending = 0,
    BrowserDownloadStateDownloading,
    BrowserDownloadStateCompleted,
    BrowserDownloadStateFailed,
    BrowserDownloadStateCancelled,
};

@interface BrowserDownloadItem : NSObject

@property (nonatomic, strong, readonly) NSUUID *itemID;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy, nullable) NSString *sourceHost;
@property (nonatomic, strong, nullable) NSURL *sourceURL;
@property (nonatomic, strong, nullable) NSURL *destinationURL;
@property (nonatomic, assign) BrowserDownloadState state;
@property (nonatomic, assign) double progress; // 0...1；未知总长时可用 indeterminate
@property (nonatomic, assign) BOOL hasKnownTotalUnitCount;
@property (nonatomic, assign) int64_t completedUnitCount;
@property (nonatomic, assign) int64_t totalUnitCount;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *finishedAt;
@property (nonatomic, weak, nullable) WKDownload *download;
@property (nonatomic, assign) BOOL unread;

- (NSString *)statusDescription;

@end

NS_ASSUME_NONNULL_END
