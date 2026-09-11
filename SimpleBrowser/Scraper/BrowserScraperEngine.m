#import "BrowserScraperEngine.h"
#import "BrowserScraperDetector.h"
#import "BrowserScraperValueTransform.h"
#import "BrowserScraperPaginationDriver.h"
#import "BrowserScraperRecipeStore.h"
#import "BrowserScraperSettings.h"
#import "BrowserScraperExcelWriter.h"
#import "BrowserScraperMySQLWriter.h"

@interface BrowserScraperEngine ()
@property (nonatomic, assign, readwrite) BOOL running;
@property (nonatomic, assign, readwrite) BOOL paused;
@property (nonatomic, assign, readwrite) BOOL trialMode;
@property (nonatomic, copy, readwrite, nullable) NSString *currentRunDirectory;
@property (nonatomic, strong) BrowserScraperRecipe *recipe;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, assign) BOOL cancelRequested;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mutablePreview;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenKeys;
@property (nonatomic, assign) NSInteger totalRows;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, copy) NSString *ndjsonPath;
@property (nonatomic, copy) NSString *logPath;
@end

static NSString *MeoScraperStringify(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return @"";
}

@implementation BrowserScraperEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutablePreview = [NSMutableArray array];
        _seenKeys = [NSMutableSet set];
    }
    return self;
}

- (NSArray<NSDictionary *> *)previewRows {
    return [self.mutablePreview copy];
}

- (void)log:(NSString *)line {
    NSString *stamp = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    if (self.logPath.length > 0) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
        if (!fh) {
            [@"" writeToFile:self.logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
        }
        [fh seekToEndOfFile];
        [fh writeData:[stamp dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    if ([self.delegate respondsToSelector:@selector(scraperEngine:didLog:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate scraperEngine:self didLog:line];
        });
    }
}

- (void)startWithRecipe:(BrowserScraperRecipe *)recipe webView:(WKWebView *)webView {
    [self startWithRecipe:recipe webView:webView trialMode:NO];
}

- (void)startTrialWithRecipe:(BrowserScraperRecipe *)recipe webView:(WKWebView *)webView {
    [self startWithRecipe:recipe webView:webView trialMode:YES];
}

- (void)startWithRecipe:(BrowserScraperRecipe *)recipe webView:(WKWebView *)webView trialMode:(BOOL)trialMode {
    if (self.running) {
        [self cancel];
    }
    BrowserScraperRecipe *runRecipe = [recipe copy];
    self.trialMode = trialMode;
    if (trialMode) {
        NSInteger pages = runRecipe.pagination.maxPages;
        if (pages < 1) pages = 10;
        runRecipe.pagination.maxPages = MIN(10, pages);
    }
    self.recipe = runRecipe;
    self.webView = webView;
    self.cancelRequested = NO;
    self.paused = NO;
    self.running = YES;
    self.totalRows = 0;
    self.pageIndex = 0;
    [self.mutablePreview removeAllObjects];
    [self.seenKeys removeAllObjects];

    NSString *runId = [[NSUUID UUID] UUIDString];
    NSString *runDir = [[BrowserScraperRecipeStore runsRootDirectory] stringByAppendingPathComponent:runId];
    [[NSFileManager defaultManager] createDirectoryAtPath:runDir withIntermediateDirectories:YES attributes:nil error:nil];
    self.currentRunDirectory = runDir;
    self.ndjsonPath = [runDir stringByAppendingPathComponent:@"rows.ndjson"];
    self.logPath = [runDir stringByAppendingPathComponent:@"log.txt"];
    [@"" writeToFile:self.ndjsonPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"" writeToFile:self.logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSDictionary *meta = @{
        @"runId": runId,
        @"recipeId": recipe.recipeID ?: @"",
        @"startedAt": @([NSDate date].timeIntervalSince1970),
        @"status": @"running",
        @"trial": @(trialMode),
    };
    NSData *metaData = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted error:nil];
    [metaData writeToFile:[runDir stringByAppendingPathComponent:@"meta.json"] atomically:YES];

    if (trialMode) {
        [self log:[NSString stringWithFormat:@"试运行开始（最多 %ld 页，结果追加到预览）",
                   (long)runRecipe.pagination.maxPages]];
    } else {
        [self log:@"开始爬取"];
    }
    [self runPageLoop];
}

- (void)pause {
    self.paused = YES;
    [self log:@"已暂停"];
}

- (void)resume {
    if (!self.running || !self.paused) return;
    self.paused = NO;
    [self log:@"继续"];
    [self runPageLoop];
}

- (void)cancel {
    self.cancelRequested = YES;
    self.paused = NO;
    [self log:@"取消中…"];
}

- (void)runPageLoop {
    if (!self.running) return;
    if (self.cancelRequested) {
        [self finishWithError:[NSError errorWithDomain:@"BrowserScraper" code:20 userInfo:@{NSLocalizedDescriptionKey:@"已停止"}]];
        return;
    }
    if (self.paused) return;

    WKWebView *webView = self.webView;
    BrowserScraperRecipe *recipe = self.recipe;
    if (!webView || !recipe) {
        [self finishWithError:[NSError errorWithDomain:@"BrowserScraper" code:21 userInfo:@{NSLocalizedDescriptionKey:@"缺少 WebView 或配方"}]];
        return;
    }

    if (recipe.pagination.waitForSelector.length > 0) {
        NSString *waitJS = [BrowserScraperDetector waitForSelectorJavaScript:recipe.pagination.waitForSelector
                                                                   timeoutMs:recipe.pagination.waitTimeoutMs];
        [webView evaluateJavaScript:waitJS completionHandler:^(id result, NSError *error) {
            (void)result; (void)error;
            [self extractCurrentPage];
        }];
    } else {
        [self extractCurrentPage];
    }
}

- (NSArray<NSDictionary *> *)fieldDictionaries {
    NSMutableArray *arr = [NSMutableArray array];
    for (BrowserScraperField *f in self.recipe.fields) {
        [arr addObject:[f dictionaryRepresentation]];
    }
    return arr;
}

- (NSString *)dedupeKeyForRow:(NSDictionary *)row {
    if (self.recipe.dedupeKeyFieldIds.count > 0) {
        NSMutableArray *parts = [NSMutableArray array];
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (BrowserScraperField *f in self.recipe.fields) {
            map[f.fieldID] = f.name ?: f.fieldID;
        }
        for (NSString *fid in self.recipe.dedupeKeyFieldIds) {
            NSString *name = map[fid] ?: fid;
            [parts addObject:[NSString stringWithFormat:@"%@=%@", name, row[name] ?: @""]];
        }
        return [parts componentsJoinedByString:@"|"];
    }
    // 无限滚动会反复抽到「已加载的全部行」，无显式去重键时按行内容指纹去重
    if (self.recipe.pagination.type == BrowserScraperPaginationTypeInfiniteScroll ||
        self.recipe.pagination.type == BrowserScraperPaginationTypeLoadMore) {
        NSArray *keys = [[row allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray *parts = [NSMutableArray array];
        for (id k in keys) {
            if (![k isKindOfClass:[NSString class]]) continue;
            [parts addObject:[NSString stringWithFormat:@"%@=%@", k, MeoScraperStringify(row[k])]];
        }
        return [parts componentsJoinedByString:@"\n"];
    }
    return nil;
}

- (void)extractCurrentPage {
    BrowserScraperRecipe *recipe = self.recipe;
    NSInteger remaining = recipe.pagination.maxRows - self.totalRows;
    if (remaining <= 0) {
        [self finishWithError:nil];
        return;
    }
    NSString *mode = [BrowserScraperRecipe stringFromMode:recipe.mode];
    [BrowserScraperDetector extractRowsInWebView:self.webView
                                            mode:mode
                                   containerPath:recipe.containerPath
                                         rowPath:recipe.rowPath
                                          fields:[self fieldDictionaries]
                                   absoluteURLs:recipe.absoluteURLs
                                         maxRows:MIN(500, remaining)
                                      completion:^(NSArray<NSDictionary *> *rows, NSError *error) {
        if (error) {
            [self log:error.localizedDescription ?: @"抽取失败"];
            [self finishWithError:error];
            return;
        }
        NSMutableArray *accepted = [NSMutableArray array];
        BrowserScraperTransformContext *txCtx = [BrowserScraperTransformContext defaultContext];
        NSURL *pageURL = self.webView.URL;
        if (pageURL.absoluteString.length > 0) txCtx.baseURL = pageURL.absoluteString;
        for (NSDictionary *row in rows) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *norm = [BrowserScraperValueTransform normalizeRow:row
                                                                    fields:recipe.fields
                                                                   context:txCtx];
            if (recipe.dropEmptyRows) {
                BOOL empty = YES;
                for (id v in norm.allValues) {
                    if ([MeoScraperStringify(v) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0) {
                        empty = NO;
                        break;
                    }
                }
                if (empty) continue;
            }
            NSString *key = [self dedupeKeyForRow:norm];
            if (key.length > 0) {
                if ([self.seenKeys containsObject:key]) continue;
                [self.seenKeys addObject:key];
            }
            [accepted addObject:norm];
            // 正式运行不缓存预览行，节约内存；试运行由侧栏自行追加
            if (self.trialMode && self.mutablePreview.count < 500) {
                [self.mutablePreview addObject:norm];
            }
            if (self.totalRows + (NSInteger)accepted.count >= recipe.pagination.maxRows) break;
        }
        [self appendRowsToSpill:accepted];
        self.totalRows += accepted.count;
        self.pageIndex += 1;
        [self log:[NSString stringWithFormat:@"第 %ld 页 +%lu 行，合计 %ld",
                   (long)self.pageIndex, (unsigned long)accepted.count, (long)self.totalRows]];
        if ([self.delegate respondsToSelector:@selector(scraperEngine:didAppendRows:totalRows:page:)]) {
            [self.delegate scraperEngine:self didAppendRows:accepted totalRows:self.totalRows page:self.pageIndex];
        }

        if (self.totalRows >= recipe.pagination.maxRows ||
            recipe.pagination.type == BrowserScraperPaginationTypeNone ||
            self.pageIndex >= recipe.pagination.maxPages) {
            [self finishWithError:nil];
            return;
        }

        NSInteger delay = recipe.pagination.pageDelayMs;
        if (recipe.pagination.type == BrowserScraperPaginationTypeInfiniteScroll) {
            delay = MAX(delay, 400);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if (self.cancelRequested) {
                [self finishWithError:[NSError errorWithDomain:@"BrowserScraper" code:20 userInfo:@{NSLocalizedDescriptionKey:@"已停止"}]];
                return;
            }
            if (self.paused) return;
            [self advancePaginationAllowingRetry:YES];
        });
    }];
}

- (void)advancePaginationAllowingRetry:(BOOL)allowRetry {
    BrowserScraperRecipe *recipe = self.recipe;
    [BrowserScraperPaginationDriver advanceInWebView:self.webView
                                          pagination:recipe.pagination
                                          completion:^(BOOL advanced, NSError *pageError) {
        if (pageError) {
            [self log:pageError.localizedDescription ?: @"翻页失败"];
            [self finishWithError:pageError];
            return;
        }
        if (advanced) {
            [self runPageLoop];
            return;
        }
        // 无限滚动偶发网络慢：首次失败再重试一次（更长 settle）
        if (allowRetry && recipe.pagination.type == BrowserScraperPaginationTypeInfiniteScroll) {
            [self log:@"滚动后暂无新增，再试一次…"];
            BrowserScraperPagination *retryPag = [recipe.pagination copy];
            retryPag.scrollSettleMs = MAX(2200, retryPag.scrollSettleMs + 800);
            retryPag.scrollStepPx = MAX(1200, retryPag.scrollStepPx);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                if (self.cancelRequested || self.paused) {
                    if (self.cancelRequested) {
                        [self finishWithError:[NSError errorWithDomain:@"BrowserScraper" code:20 userInfo:@{NSLocalizedDescriptionKey:@"已停止"}]];
                    }
                    return;
                }
                [BrowserScraperPaginationDriver advanceInWebView:self.webView
                                                      pagination:retryPag
                                                      completion:^(BOOL advanced2, NSError *err2) {
                    if (err2) {
                        [self log:err2.localizedDescription ?: @"翻页失败"];
                        [self finishWithError:err2];
                        return;
                    }
                    if (!advanced2) {
                        [self log:@"没有更多页"];
                        [self finishWithError:nil];
                        return;
                    }
                    [self runPageLoop];
                }];
            });
            return;
        }
        [self log:@"没有更多页"];
        [self finishWithError:nil];
    }];
}

- (void)appendRowsToSpill:(NSArray<NSDictionary *> *)rows {
    if (rows.count == 0) return;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:self.ndjsonPath];
    [fh seekToEndOfFile];
    for (NSDictionary *row in rows) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
        if (!data) continue;
        [fh writeData:data];
        [fh writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [fh closeFile];
}

- (void)finishWithError:(NSError *)error {
    if (!self.running) return;
    self.running = NO;
    self.paused = NO;
    NSString *status = error ? @"failed" : @"ok";
    if (error && error.code == 20) status = @"cancelled";
    NSDictionary *meta = @{
        @"recipeId": self.recipe.recipeID ?: @"",
        @"finishedAt": @([NSDate date].timeIntervalSince1970),
        @"status": status,
        @"rows": @(self.totalRows),
        @"error": error.localizedDescription ?: [NSNull null],
        @"runDirectory": self.currentRunDirectory ?: @"",
    };
    NSData *metaData = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted error:nil];
    [metaData writeToFile:[self.currentRunDirectory stringByAppendingPathComponent:@"meta.json"] atomically:YES];
    [self log:error ? (error.localizedDescription ?: @"失败") : (self.trialMode ? @"试运行完成" : @"完成")];

    if (!self.trialMode && (!error || error.code == 20)) {
        [self writeSink];
    }

    [self pruneOldRuns];

    NSString *runDir = self.currentRunDirectory;
    if ([self.delegate respondsToSelector:@selector(scraperEngine:didFinishWithRunDirectory:error:)]) {
        [self.delegate scraperEngine:self didFinishWithRunDirectory:runDir error:(error.code == 20 ? nil : error)];
    }
    self.trialMode = NO;
}

- (void)writeSink {
    BrowserScraperSink *sink = self.recipe.sink;
    NSError *err = nil;
    NSArray<NSString *> *columnNames = [BrowserScraperField orderedColumnNamesFromFields:self.recipe.fields];
    if (sink.type == BrowserScraperSinkTypeMySQL) {
        BOOL ok = [BrowserScraperMySQLWriter writeNDJSONAtPath:self.ndjsonPath
                                                        config:sink.mysql
                                                   columnNames:columnNames
                                                         error:&err];
        [self log:ok ? @"MySQL 写入完成" : (err.localizedDescription ?: @"MySQL 失败")];
        return;
    }
    NSString *path = sink.filePath;
    if (path.length == 0) {
        NSURL *downloads = [[NSFileManager defaultManager] URLForDirectory:NSDownloadsDirectory
                                                                 inDomain:NSUserDomainMask
                                                        appropriateForURL:nil
                                                                   create:YES
                                                                    error:nil];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *ext = @"xlsx";
        if (sink.type == BrowserScraperSinkTypeCSV) ext = @"csv";
        else if (sink.type == BrowserScraperSinkTypeJSON) ext = @"json";
        NSString *safeName = [[self.recipe.name stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
                              stringByReplacingOccurrencesOfString:@":" withString:@"-"];
        path = [[downloads.path stringByAppendingPathComponent:
                 [NSString stringWithFormat:@"%@-%@", safeName, [fmt stringFromDate:[NSDate date]]]]
                stringByAppendingPathExtension:ext];
        sink.filePath = path;
    }
    BOOL ok = [BrowserScraperExcelWriter writeNDJSONAtPath:self.ndjsonPath
                                              outputPath:path
                                                sinkType:sink.type
                                             columnNames:columnNames
                                                   error:&err];
    [self log:ok ? [NSString stringWithFormat:@"已导出 %@", path] : (err.localizedDescription ?: @"导出失败")];
}

- (void)pruneOldRuns {
    NSInteger keep = [BrowserScraperSettings sharedSettings].maxRetainedRuns;
    NSString *root = [BrowserScraperRecipeStore runsRootDirectory];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil];
    if (contents.count <= (NSUInteger)keep) return;
    NSArray *sorted = [contents sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *pa = [root stringByAppendingPathComponent:a];
        NSString *pb = [root stringByAppendingPathComponent:b];
        NSDictionary *aa = [[NSFileManager defaultManager] attributesOfItemAtPath:pa error:nil];
        NSDictionary *ba = [[NSFileManager defaultManager] attributesOfItemAtPath:pb error:nil];
        return [ba[NSFileModificationDate] compare:aa[NSFileModificationDate]];
    }];
    for (NSUInteger i = (NSUInteger)keep; i < sorted.count; i++) {
        NSString *path = [root stringByAppendingPathComponent:sorted[i]];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

@end
