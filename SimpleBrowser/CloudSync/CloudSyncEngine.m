#import "CloudSyncEngine.h"
#import "CloudSyncSettings.h"
#import "CloudSyncAccountObserver.h"
#import "CloudSyncCapability.h"
#import "CloudSyncTransport.h"
#import "CloudSyncShortcutBridge.h"
#import "CloudSyncFormMemoBridge.h"
#import "SyncMerger.h"
#import "SyncRecord.h"
#import "SyncKind.h"
#import "BrowserShortcutStore.h"
#import "FormMemoStore.h"
#import <AppKit/AppKit.h>

@interface CloudSyncEngine ()
@property (nonatomic, assign, readwrite) CloudSyncEngineState state;
@property (nonatomic, copy, readwrite) NSString *statusText;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL applyingRemote;
@property (nonatomic, assign) BOOL syncInFlight;
@end

@implementation CloudSyncEngine

+ (instancetype)sharedEngine {
    static CloudSyncEngine *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = CloudSyncEngineStateIdle;
        _statusText = @"未启用";
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(settingsDidChange:) name:CloudSyncSettingsDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(shortcutsDidChange:) name:BrowserShortcutStoreDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(formMemosDidChange:) name:FormMemoStoreDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(appDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)postStateChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:CloudSyncEngineStateDidChangeNotification object:self];
}

- (void)setState:(CloudSyncEngineState)state text:(NSString *)text {
    self.state = state;
    self.statusText = text ?: @"";
    [self postStateChange];
}

- (void)startIfNeeded {
    CloudSyncSettings *settings = CloudSyncSettings.sharedSettings;
    if (!settings.enabled) {
        [self stop];
        return;
    }
    self.started = YES;
    [self refreshAccountStatus];
}

- (void)stop {
    self.started = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncNow) object:nil];
    if (!CloudSyncSettings.sharedSettings.enabled) {
        [self setState:CloudSyncEngineStateIdle text:@"未启用"];
    }
}

- (void)refreshAccountStatus {
    __weak typeof(self) weakSelf = self;
    [[CloudSyncAccountObserver sharedObserver] refreshWithCompletion:^(CloudSyncAccountStatus status, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (!CloudSyncSettings.sharedSettings.enabled) {
            [self setState:CloudSyncEngineStateIdle text:@"未启用"];
            return;
        }
        if (status != CloudSyncAccountStatusAvailable) {
            CloudSyncSettings.sharedSettings.lastErrorMessage = message;
            [self setState:CloudSyncEngineStateUnavailable text:message];
            return;
        }
        CloudSyncSettings.sharedSettings.lastErrorMessage = nil;
        if (self.state != CloudSyncEngineStateSyncing) {
            [self setState:CloudSyncEngineStateIdle text:message];
        }
        if (self.started) {
            [self syncNow];
        }
    }];
}

- (void)settingsDidChange:(NSNotification *)note {
    (void)note;
    if (CloudSyncSettings.sharedSettings.enabled) {
        [self startIfNeeded];
    } else {
        [self stop];
    }
}

- (void)scheduleDebouncedSync {
    if (!self.started || !CloudSyncSettings.sharedSettings.enabled || self.applyingRemote) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncNow) object:nil];
    [self performSelector:@selector(syncNow) withObject:nil afterDelay:3.0];
}

- (void)shortcutsDidChange:(NSNotification *)note {
    (void)note;
    if (self.applyingRemote || !CloudSyncSettings.sharedSettings.shortcutEnabled) {
        return;
    }
    [[CloudSyncShortcutBridge sharedBridge] touchLocalRecordsForUpload];
    [self scheduleDebouncedSync];
}

- (void)formMemosDidChange:(NSNotification *)note {
    (void)note;
    if (self.applyingRemote || !CloudSyncSettings.sharedSettings.formMemoEnabled) {
        return;
    }
    [[CloudSyncFormMemoBridge sharedBridge] touchLocalRecordsForUpload];
    [self scheduleDebouncedSync];
}

- (void)appDidBecomeActive:(NSNotification *)note {
    (void)note;
    if (self.started && CloudSyncSettings.sharedSettings.enabled) {
        [self syncNow];
    }
}

- (void)syncNow {
    if (!CloudSyncSettings.sharedSettings.enabled) {
        return;
    }
    if (self.syncInFlight) {
        return;
    }
    if (![CloudSyncCapability isCloudKitEntitled]) {
        NSString *reason = [CloudSyncCapability unavailableReason];
        CloudSyncSettings.sharedSettings.lastErrorMessage = reason;
        [self setState:CloudSyncEngineStateUnavailable text:reason];
        return;
    }
    if (@available(macOS 14.0, *)) {
        // continue
    } else {
        [self setState:CloudSyncEngineStateUnavailable text:@"需要 macOS 14+"];
        return;
    }
    if (CloudSyncAccountObserver.sharedObserver.status == CloudSyncAccountStatusUnsupportedOS) {
        [self setState:CloudSyncEngineStateUnavailable text:CloudSyncAccountObserver.sharedObserver.statusMessage];
        return;
    }

    self.syncInFlight = YES;
    [self setState:CloudSyncEngineStateSyncing text:@"同步中…"];

    __weak typeof(self) weakSelf = self;
    void (^finish)(NSError *) = ^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        self.syncInFlight = NO;
        if (error) {
            CloudSyncSettings.sharedSettings.lastErrorMessage = error.localizedDescription;
            [self setState:CloudSyncEngineStateError text:error.localizedDescription ?: @"同步失败"];
        } else {
            CloudSyncSettings.sharedSettings.lastErrorMessage = nil;
            CloudSyncSettings.sharedSettings.lastSyncAt = [NSDate date].timeIntervalSince1970;
            [self setState:CloudSyncEngineStateIdle text:@"已同步"];
        }
    };

    // 若账号状态未知，先刷新再同步
    if (CloudSyncAccountObserver.sharedObserver.status != CloudSyncAccountStatusAvailable) {
        [[CloudSyncAccountObserver sharedObserver] refreshWithCompletion:^(CloudSyncAccountStatus status, NSString *message) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            if (status != CloudSyncAccountStatusAvailable) {
                self.syncInFlight = NO;
                CloudSyncSettings.sharedSettings.lastErrorMessage = message;
                [self setState:CloudSyncEngineStateUnavailable text:message];
                return;
            }
            self.syncInFlight = NO;
            [self syncNow];
        }];
        return;
    }

    [[CloudSyncTransport sharedTransport] fetchAllSyncRecordsWithCompletion:^(NSArray<SyncRecord *> *remote, NSError *fetchError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (fetchError) {
            finish(fetchError);
            return;
        }

        CloudSyncSettings *settings = CloudSyncSettings.sharedSettings;
        NSMutableArray<SyncRecord *> *toUpload = [NSMutableArray array];
        long long now = (long long)[[NSDate date] timeIntervalSince1970];

        if (settings.shortcutEnabled) {
            NSArray<SyncRecord *> *local = [[CloudSyncShortcutBridge sharedBridge] exportRecords];
            NSMutableArray<SyncRecord *> *remoteShortcuts = [NSMutableArray array];
            for (SyncRecord *r in remote) {
                if ([r.kind isEqualToString:SyncKindShortcut]) {
                    [remoteShortcuts addObject:r];
                }
            }
            NSArray<SyncRecord *> *merged = [SyncMerger mergeIncoming:remoteShortcuts intoLocal:local];
            merged = [SyncMerger purgeExpiredTombstones:merged now:now];
            self.applyingRemote = YES;
            [[CloudSyncShortcutBridge sharedBridge] applyMergedRecords:merged];
            self.applyingRemote = NO;
            [toUpload addObjectsFromArray:merged];
        }

        if (settings.formMemoEnabled) {
            NSArray<SyncRecord *> *local = [[CloudSyncFormMemoBridge sharedBridge] exportRecords];
            NSMutableArray<SyncRecord *> *remoteMemos = [NSMutableArray array];
            for (SyncRecord *r in remote) {
                if ([r.kind isEqualToString:SyncKindFormMemo]) {
                    [remoteMemos addObject:r];
                }
            }
            NSArray<SyncRecord *> *merged = [SyncMerger mergeIncoming:remoteMemos intoLocal:local];
            merged = [SyncMerger purgeExpiredTombstones:merged now:now];
            self.applyingRemote = YES;
            [[CloudSyncFormMemoBridge sharedBridge] applyMergedRecords:merged];
            self.applyingRemote = NO;
            [toUpload addObjectsFromArray:merged];
        }

        // 保留对端已启用 kind 之外的远端记录，避免误删
        for (SyncRecord *r in remote) {
            BOOL keep = NO;
            if ([r.kind isEqualToString:SyncKindShortcut] && !settings.shortcutEnabled) {
                keep = YES;
            }
            if ([r.kind isEqualToString:SyncKindFormMemo] && !settings.formMemoEnabled) {
                keep = YES;
            }
            if (![r.kind isEqualToString:SyncKindShortcut] && ![r.kind isEqualToString:SyncKindFormMemo]) {
                keep = YES;
            }
            if (keep) {
                [toUpload addObject:r];
            }
        }

        [[CloudSyncTransport sharedTransport] saveSyncRecords:toUpload completion:^(NSError *saveError) {
            finish(saveError);
        }];
    }];
}

- (void)deleteCloudDataWithCompletion:(void (^)(NSError *))completion {
    [[CloudSyncTransport sharedTransport] deleteAllMeoSyncRecordsWithCompletion:^(NSError *error) {
        if (!error) {
            CloudSyncSettings.sharedSettings.lastSyncAt = 0;
            CloudSyncSettings.sharedSettings.lastErrorMessage = nil;
            [self setState:CloudSyncEngineStateIdle text:@"已清除 iCloud 同步数据"];
        }
        if (completion) {
            completion(error);
        }
    }];
}

@end
