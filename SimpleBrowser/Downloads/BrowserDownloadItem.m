#import "BrowserDownloadItem.h"

@implementation BrowserDownloadItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemID = [NSUUID UUID];
        _filename = @"下载中";
        _state = BrowserDownloadStatePending;
        _createdAt = [NSDate date];
        _unread = NO;
    }
    return self;
}

- (NSString *)statusDescription {
    switch (self.state) {
        case BrowserDownloadStatePending:
            return @"准备中…";
        case BrowserDownloadStateDownloading: {
            if (self.hasKnownTotalUnitCount && self.totalUnitCount > 0) {
                NSByteCountFormatter *fmt = [[NSByteCountFormatter alloc] init];
                fmt.countStyle = NSByteCountFormatterCountStyleFile;
                NSString *done = [fmt stringFromByteCount:self.completedUnitCount];
                NSString *total = [fmt stringFromByteCount:self.totalUnitCount];
                NSInteger pct = (NSInteger)llround(self.progress * 100.0);
                return [NSString stringWithFormat:@"%@ / %@ · %ld%%", done, total, (long)pct];
            }
            if (self.completedUnitCount > 0) {
                NSByteCountFormatter *fmt = [[NSByteCountFormatter alloc] init];
                fmt.countStyle = NSByteCountFormatterCountStyleFile;
                return [NSString stringWithFormat:@"已下载 %@", [fmt stringFromByteCount:self.completedUnitCount]];
            }
            return @"下载中…";
        }
        case BrowserDownloadStateCompleted:
            return @"完成";
        case BrowserDownloadStateFailed:
            return self.errorMessage.length > 0 ? self.errorMessage : @"失败";
        case BrowserDownloadStateCancelled:
            return @"已取消";
    }
    return @"";
}

@end
