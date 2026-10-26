#import "ServerSyncEngine.h"
#import "ServerSyncSettings.h"
#import "ServerSyncAuth.h"
#import "ServerSyncTransport.h"
#import "SyncMerger.h"
#import "SyncRecord.h"
#import "SyncKind.h"
#import "SyncShortcutBridge.h"
#import "SyncFormMemoBridge.h"
#import "BrowserShortcutStore.h"
#import "FormMemoStore.h"
#import <AppKit/AppKit.h>

@interface ServerSyncEngine ()
@property (nonatomic, assign, readwrite) ServerSyncEngineState state;
@property (nonatomic, copy, readwrite) NSString *statusText;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL applyingRemote;
@property (nonatomic, assign) BOOL syncInFlight;
/// 冷启动时刻；此前不因 DidBecomeActive 读钥匙串 token。
@property (nonatomic, assign) NSTimeInterval coldStartAt;
@end

@implementation ServerSyncEngine

+ (instancetype)sharedEngine {
    static ServerSyncEngine *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = ServerSyncEngineStateIdle;
        _statusText = @"未启用";
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(settingsDidChange:) name:ServerSyncSettingsDidChangeNotification object:nil];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:ServerSyncEngineStateDidChangeNotification object:self];
}

- (void)setState:(ServerSyncEngineState)state text:(NSString *)text {
    self.state = state;
    self.statusText = text ?: @"";
    [self postStateChange];
}

- (void)startIfNeeded {
    ServerSyncSettings *settings = ServerSyncSettings.sharedSettings;
    if (!settings.enabled) {
        [self stop];
        [self setState:ServerSyncEngineStateIdle text:@"未启用"];
        return;
    }
    // 冷启动只用 UserDefaults 的 userId 判断「可能已登录」，避免立刻读钥匙串 token 弹密码框。
    if (settings.userId.length == 0) {
        [self stop];
        [self setState:ServerSyncEngineStateUnavailable text:@"未登录"];
        return;
    }
    self.started = YES;
    if (self.coldStartAt <= 0) {
        self.coldStartAt = [NSDate date].timeIntervalSince1970;
    }
    [self setState:ServerSyncEngineStateIdle text:@"已登录"];
    // 冷启动不自动 sync：读 auth token 会弹「登录钥匙串」密码框，易与 Companion / 自动登录叠弹。
    // 本地数据变更、设置变更或稍后回到前台再同步。
}

- (void)stop {
    self.started = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncNow) object:nil];
}

- (void)settingsDidChange:(NSNotification *)note {
    (void)note;
    if (ServerSyncSettings.sharedSettings.enabled && ServerSyncAuth.sharedAuth.isLoggedIn) {
        [self startIfNeeded];
    } else {
        [self stop];
        [self setState:ServerSyncEngineStateIdle text:ServerSyncSettings.sharedSettings.enabled ? @"未登录" : @"未启用"];
    }
}

- (void)scheduleDebouncedSync {
    if (!self.started || !ServerSyncSettings.sharedSettings.enabled || self.applyingRemote) {
        return;
    }
    // 仅下载：本地改动不应触发自动同步（否则会把刚改的内容又用云端盖掉）。
    if (ServerSyncSettings.sharedSettings.syncDirection == ServerSyncDirectionDownloadOnly) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncNow) object:nil];
    [self performSelector:@selector(syncNow) withObject:nil afterDelay:3.0];
}

- (void)shortcutsDidChange:(NSNotification *)note {
    (void)note;
    if (self.applyingRemote || !ServerSyncSettings.sharedSettings.shortcutEnabled) {
        return;
    }
    [[SyncShortcutBridge sharedBridge] touchLocalRecordsForUpload];
    [self scheduleDebouncedSync];
}

- (void)formMemosDidChange:(NSNotification *)note {
    (void)note;
    if (self.applyingRemote || !ServerSyncSettings.sharedSettings.formMemoEnabled) {
        return;
    }
    [[SyncFormMemoBridge sharedBridge] touchLocalRecordsForUpload];
    [self scheduleDebouncedSync];
}

- (void)appDidBecomeActive:(NSNotification *)note {
    (void)note;
    if (!self.started || !ServerSyncSettings.sharedSettings.enabled || self.syncInFlight) {
        return;
    }
    // 冷启动后 90 秒内忽略；避免与配对校验 / 会话恢复抢钥匙串。
    NSTimeInterval sinceCold = [NSDate date].timeIntervalSince1970 - self.coldStartAt;
    if (self.coldStartAt > 0 && sinceCold < 90.0) {
        return;
    }
    [self scheduleDebouncedSync];
}

- (void)syncNow {
    if (!ServerSyncSettings.sharedSettings.enabled) {
        return;
    }
    if (self.syncInFlight) {
        return;
    }
    if (!ServerSyncAuth.sharedAuth.isLoggedIn) {
        [self setState:ServerSyncEngineStateUnavailable text:@"未登录"];
        return;
    }
    if (!ServerSyncSettings.sharedSettings.normalizedBaseURL) {
        [self setState:ServerSyncEngineStateUnavailable text:@"请填写服务器地址"];
        return;
    }

    self.syncInFlight = YES;
    ServerSyncDirection direction = ServerSyncSettings.sharedSettings.syncDirection;
    NSString *phase = @"同步中…";
    if (direction == ServerSyncDirectionUploadOnly) {
        phase = @"上传中…";
    } else if (direction == ServerSyncDirectionDownloadOnly) {
        phase = @"下载中…";
    }
    [self setState:ServerSyncEngineStateSyncing text:phase];

    __weak typeof(self) weakSelf = self;

    void (^finishWithError)(NSError *) = ^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        self.syncInFlight = NO;
        if (error) {
            ServerSyncSettings.sharedSettings.lastErrorMessage = error.localizedDescription;
            [self setState:ServerSyncEngineStateError text:error.localizedDescription ?: @"同步失败"];
        } else {
            ServerSyncSettings.sharedSettings.lastErrorMessage = nil;
            ServerSyncSettings.sharedSettings.lastSyncAt = [NSDate date].timeIntervalSince1970;
            [self setState:ServerSyncEngineStateIdle text:@"已同步"];
        }
    };

    // 仅上传：不拉云端、不改本地，直接推本地导出。
    if (direction == ServerSyncDirectionUploadOnly) {
        ServerSyncSettings *settings = ServerSyncSettings.sharedSettings;
        NSMutableArray<SyncRecord *> *toUpload = [NSMutableArray array];
        long long now = (long long)[[NSDate date] timeIntervalSince1970];
        if (settings.shortcutEnabled) {
            NSArray<SyncRecord *> *local = [[SyncShortcutBridge sharedBridge] exportRecords];
            [toUpload addObjectsFromArray:[SyncMerger purgeExpiredTombstones:local now:now]];
        }
        if (settings.formMemoEnabled) {
            NSArray<SyncRecord *> *local = [[SyncFormMemoBridge sharedBridge] exportRecords];
            [toUpload addObjectsFromArray:[SyncMerger purgeExpiredTombstones:local now:now]];
        }
        [[ServerSyncTransport sharedTransport] upsertRecords:toUpload completion:finishWithError];
        return;
    }

    [[ServerSyncTransport sharedTransport] fetchAllRecordsWithCompletion:^(NSArray<SyncRecord *> *remote, NSError *fetchError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (fetchError) {
            finishWithError(fetchError);
            return;
        }

        ServerSyncSettings *settings = ServerSyncSettings.sharedSettings;
        NSMutableArray<SyncRecord *> *toUpload = [NSMutableArray array];
        long long now = (long long)[[NSDate date] timeIntervalSince1970];
        BOOL upload = (direction != ServerSyncDirectionDownloadOnly);

        if (settings.shortcutEnabled) {
            NSArray<SyncRecord *> *local = [[SyncShortcutBridge sharedBridge] exportRecords];
            NSMutableArray<SyncRecord *> *remoteShortcuts = [NSMutableArray array];
            for (SyncRecord *r in remote) {
                if ([r.kind isEqualToString:SyncKindShortcut]) {
                    [remoteShortcuts addObject:r];
                }
            }
            NSArray<SyncRecord *> *merged = [SyncMerger mergeIncoming:remoteShortcuts intoLocal:local];
            merged = [SyncMerger purgeExpiredTombstones:merged now:now];
            self.applyingRemote = YES;
            [[SyncShortcutBridge sharedBridge] applyMergedRecords:merged];
            self.applyingRemote = NO;
            if (upload) {
                [toUpload addObjectsFromArray:merged];
            }
        }

        if (settings.formMemoEnabled) {
            NSArray<SyncRecord *> *local = [[SyncFormMemoBridge sharedBridge] exportRecords];
            NSMutableArray<SyncRecord *> *remoteMemos = [NSMutableArray array];
            for (SyncRecord *r in remote) {
                if ([r.kind isEqualToString:SyncKindFormMemo]) {
                    [remoteMemos addObject:r];
                }
            }
            NSArray<SyncRecord *> *merged = [SyncMerger mergeIncoming:remoteMemos intoLocal:local];
            merged = [SyncMerger purgeExpiredTombstones:merged now:now];
            self.applyingRemote = YES;
            [[SyncFormMemoBridge sharedBridge] applyMergedRecords:merged];
            self.applyingRemote = NO;
            if (upload) {
                [toUpload addObjectsFromArray:merged];
            }
        }

        if (!upload) {
            finishWithError(nil);
            return;
        }
        [[ServerSyncTransport sharedTransport] upsertRecords:toUpload completion:finishWithError];
    }];
}

@end
