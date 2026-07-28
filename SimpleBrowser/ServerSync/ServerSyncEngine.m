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
    if (!settings.enabled || !ServerSyncAuth.sharedAuth.isLoggedIn) {
        [self stop];
        if (!settings.enabled) {
            [self setState:ServerSyncEngineStateIdle text:@"未启用"];
        } else {
            [self setState:ServerSyncEngineStateUnavailable text:@"未登录"];
        }
        return;
    }
    self.started = YES;
    [self setState:ServerSyncEngineStateIdle text:@"已登录"];
    [self syncNow];
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
    if (self.started && ServerSyncSettings.sharedSettings.enabled) {
        [self syncNow];
    }
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
    [self setState:ServerSyncEngineStateSyncing text:@"同步中…"];

    __weak typeof(self) weakSelf = self;
    [[ServerSyncTransport sharedTransport] fetchAllRecordsWithCompletion:^(NSArray<SyncRecord *> *remote, NSError *fetchError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (fetchError) {
            self.syncInFlight = NO;
            ServerSyncSettings.sharedSettings.lastErrorMessage = fetchError.localizedDescription;
            [self setState:ServerSyncEngineStateError text:fetchError.localizedDescription ?: @"同步失败"];
            return;
        }

        ServerSyncSettings *settings = ServerSyncSettings.sharedSettings;
        NSMutableArray<SyncRecord *> *toUpload = [NSMutableArray array];
        long long now = (long long)[[NSDate date] timeIntervalSince1970];

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
            [toUpload addObjectsFromArray:merged];
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
            [toUpload addObjectsFromArray:merged];
        }

        [[ServerSyncTransport sharedTransport] upsertRecords:toUpload completion:^(NSError *saveError) {
            __strong typeof(weakSelf) self2 = weakSelf;
            if (!self2) {
                return;
            }
            self2.syncInFlight = NO;
            if (saveError) {
                ServerSyncSettings.sharedSettings.lastErrorMessage = saveError.localizedDescription;
                [self2 setState:ServerSyncEngineStateError text:saveError.localizedDescription ?: @"上传失败"];
            } else {
                ServerSyncSettings.sharedSettings.lastErrorMessage = nil;
                ServerSyncSettings.sharedSettings.lastSyncAt = [NSDate date].timeIntervalSince1970;
                [self2 setState:ServerSyncEngineStateIdle text:@"已同步"];
            }
        }];
    }];
}

@end
