#import "BrowserScraperMySQLWriter.h"
#import <Security/Security.h>

static NSString * const kMySQLKeychainService = @"com.example.MeoBrowser.scraper.mysql";

@implementation BrowserScraperMySQLWriter

+ (BOOL)isAvailable {
    return [[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/local/bin/mysql"]
        || [[NSFileManager defaultManager] isExecutableFileAtPath:@"/opt/homebrew/bin/mysql"]
        || [[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/mysql"];
}

+ (NSString *)mysqlBinary {
    NSArray *candidates = @[ @"/opt/homebrew/bin/mysql", @"/usr/local/bin/mysql", @"/usr/bin/mysql" ];
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    }
    return @"mysql";
}

+ (nullable NSString *)passwordForAccount:(NSString *)account {
    if (account.length == 0) return nil;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kMySQLKeychainService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)setPassword:(NSString *)password forAccount:(NSString *)account error:(NSError **)error {
    if (account.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"BrowserScraper" code:30 userInfo:@{NSLocalizedDescriptionKey:@"缺少 Keychain account"}];
        return NO;
    }
    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kMySQLKeychainService,
        (__bridge id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kMySQLKeychainService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecValueData: data,
    };
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"BrowserScraper" code:status userInfo:@{NSLocalizedDescriptionKey:@"保存密码到钥匙串失败"}];
        }
        return NO;
    }
    return YES;
}

+ (BOOL)runMySQL:(BrowserScraperMySQLConfig *)config
        password:(NSString *)password
           input:(NSString *)sql
           error:(NSError **)error {
    if (![self isAvailable]) {
        if (error) {
            *error = [NSError errorWithDomain:@"BrowserScraper" code:31
                                     userInfo:@{NSLocalizedDescriptionKey:@"未找到 mysql 客户端，请安装 MySQL 客户端或通过 Homebrew 安装 mysql"}];
        }
        return NO;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self mysqlBinary]];
    NSMutableArray *args = [@[
        @"-h", config.host ?: @"127.0.0.1",
        @"-P", [NSString stringWithFormat:@"%ld", (long)config.port],
        @"-u", config.user ?: @"",
        @"--protocol=TCP",
        @"-N", @"-B",
    ] mutableCopy];
    if (config.database.length > 0) {
        [args addObject:config.database];
    }
    if (password.length > 0) {
        [args addObject:[NSString stringWithFormat:@"-p%@", password]];
    }
    task.arguments = args;
    NSPipe *inPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardInput = inPipe;
    task.standardError = errPipe;
    task.standardOutput = [NSPipe pipe];
    if (![task launchAndReturnError:error]) return NO;
    [[inPipe fileHandleForWriting] writeData:[sql dataUsingEncoding:NSUTF8StringEncoding]];
    [[inPipe fileHandleForWriting] closeFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
        NSString *errText = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"mysql 失败";
        if (error) {
            *error = [NSError errorWithDomain:@"BrowserScraper" code:32 userInfo:@{NSLocalizedDescriptionKey: errText}];
        }
        return NO;
    }
    return YES;
}

+ (BOOL)testConnection:(BrowserScraperMySQLConfig *)config
              password:(NSString *)password
                 error:(NSError **)error {
    return [self runMySQL:config password:password input:@"SELECT 1;\n" error:error];
}

+ (NSString *)sqlEscape:(NSString *)value {
    NSString *s = value ?: @"";
    s = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    s = [s stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    return s;
}

+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
                   config:(BrowserScraperMySQLConfig *)config
                    error:(NSError **)error {
    if (!config || config.table.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"BrowserScraper" code:33 userInfo:@{NSLocalizedDescriptionKey:@"MySQL 表名未设置"}];
        return NO;
    }
    NSString *password = [self passwordForAccount:config.passwordKeychainAccount] ?: @"";
    NSString *text = [NSString stringWithContentsOfFile:ndjsonPath encoding:NSUTF8StringEncoding error:error];
    if (!text) return NO;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *cols = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        if (line.length == 0) return;
        id obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        [rows addObject:obj];
        for (NSString *key in [obj allKeys]) {
            if ([key isKindOfClass:[NSString class]] && ![seen containsObject:key]) {
                [seen addObject:key];
                [cols addObject:key];
            }
        }
    }];
    if (cols.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"BrowserScraper" code:34 userInfo:@{NSLocalizedDescriptionKey:@"没有可写入的行"}];
        return NO;
    }

    NSMutableString *sql = [NSMutableString string];
    [sql appendFormat:@"CREATE TABLE IF NOT EXISTS `%@` (", config.table];
    NSMutableArray *colDefs = [NSMutableArray array];
    for (NSString *c in cols) {
        [colDefs addObject:[NSString stringWithFormat:@"`%@` TEXT", c]];
    }
    if (config.writeMode == BrowserScraperMySQLWriteModeUpsert && config.upsertKeys.count > 0) {
        NSMutableArray *uniq = [NSMutableArray array];
        for (NSString *k in config.upsertKeys) {
            if ([cols containsObject:k]) [uniq addObject:[NSString stringWithFormat:@"`%@`", k]];
        }
        if (uniq.count > 0) {
            [colDefs addObject:[NSString stringWithFormat:@"UNIQUE KEY `meo_upsert` (%@)", [uniq componentsJoinedByString:@","]]];
        }
    }
    [sql appendString:[colDefs componentsJoinedByString:@","]];
    [sql appendString:@") DEFAULT CHARSET=utf8mb4;\n"];

    if (config.writeMode == BrowserScraperMySQLWriteModeReplace) {
        [sql appendFormat:@"TRUNCATE TABLE `%@`;\n", config.table];
    }

    NSInteger batch = 0;
    for (NSDictionary *row in rows) {
        NSMutableArray *values = [NSMutableArray array];
        for (NSString *c in cols) {
            id v = row[c];
            NSString *s = [v isKindOfClass:[NSString class]] ? v : ([v isKindOfClass:[NSNumber class]] ? [v stringValue] : @"");
            [values addObject:[NSString stringWithFormat:@"'%@'", [self sqlEscape:s]]];
        }
        NSMutableArray *colNames = [NSMutableArray array];
        for (NSString *c in cols) {
            [colNames addObject:[NSString stringWithFormat:@"`%@`", c]];
        }
        if (config.writeMode == BrowserScraperMySQLWriteModeUpsert && config.upsertKeys.count > 0) {
            NSMutableArray *updates = [NSMutableArray array];
            for (NSString *c in cols) {
                if ([config.upsertKeys containsObject:c]) continue;
                [updates addObject:[NSString stringWithFormat:@"`%@`=VALUES(`%@`)", c, c]];
            }
            [sql appendFormat:@"INSERT INTO `%@` (%@) VALUES (%@)", config.table,
             [colNames componentsJoinedByString:@","], [values componentsJoinedByString:@","]];
            if (updates.count > 0) {
                [sql appendFormat:@" ON DUPLICATE KEY UPDATE %@;\n", [updates componentsJoinedByString:@","]];
            } else {
                [sql appendString:@";\n"];
            }
        } else {
            [sql appendFormat:@"INSERT INTO `%@` (%@) VALUES (%@);\n", config.table,
             [colNames componentsJoinedByString:@","], [values componentsJoinedByString:@","]];
        }
        batch++;
        if (batch >= 200) {
            if (![self runMySQL:config password:password input:sql error:error]) return NO;
            [sql setString:@""];
            batch = 0;
        }
    }
    if (sql.length > 0) {
        return [self runMySQL:config password:password input:sql error:error];
    }
    return YES;
}

@end
