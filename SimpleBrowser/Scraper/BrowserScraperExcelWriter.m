#import "BrowserScraperExcelWriter.h"

@implementation BrowserScraperExcelWriter

+ (NSArray<NSDictionary *> *)loadRowsFromNDJSON:(NSString *)path error:(NSError **)error {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!text) return nil;
    NSMutableArray *rows = [NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        if (line.length == 0) return;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            [rows addObject:obj];
        }
    }];
    return rows;
}

+ (NSArray<NSString *> *)columnsFromRows:(NSArray<NSDictionary *> *)rows {
    NSMutableArray *cols = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *row in rows) {
        for (NSString *key in row.allKeys) {
            if (![key isKindOfClass:[NSString class]]) continue;
            if (![seen containsObject:key]) {
                [seen addObject:key];
                [cols addObject:key];
            }
        }
    }
    return cols;
}

/// 优先 preferred 顺序，再追加行中未声明键（首次出现顺序）。
+ (NSArray<NSString *> *)resolveColumns:(nullable NSArray<NSString *> *)preferred
                                   rows:(NSArray<NSDictionary *> *)rows {
    NSMutableArray *cols = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *c in preferred ?: @[]) {
        if (![c isKindOfClass:[NSString class]] || c.length == 0) continue;
        if ([seen containsObject:c]) continue;
        [seen addObject:c];
        [cols addObject:c];
    }
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *key in row.allKeys) {
            if (![key isKindOfClass:[NSString class]] || key.length == 0) continue;
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [cols addObject:key];
        }
    }
    if (cols.count == 0) return [self columnsFromRows:rows];
    return cols;
}

+ (NSString *)stringValue:(id)v {
    if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    if (v == nil || v == [NSNull null]) return @"";
    return [v description] ?: @"";
}

+ (NSString *)csvEscape:(NSString *)value {
    NSString *s = value ?: @"";
    if ([s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@",\"\n\r"]].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
        return [NSString stringWithFormat:@"\"%@\"", s];
    }
    return s;
}

+ (BOOL)writeCSVRows:(NSArray<NSDictionary *> *)rows
                path:(NSString *)path
         columnNames:(nullable NSArray<NSString *> *)columnNames
               error:(NSError **)error {
    NSArray *cols = [self resolveColumns:columnNames rows:rows];
    NSMutableString *out = [NSMutableString stringWithString:@"\uFEFF"];
    NSMutableArray *header = [NSMutableArray array];
    for (NSString *c in cols) {
        [header addObject:[self csvEscape:c]];
    }
    [out appendString:[header componentsJoinedByString:@","]];
    [out appendString:@"\n"];
    for (NSDictionary *row in rows) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSString *c in cols) {
            [cells addObject:[self csvEscape:[self stringValue:row[c]]]];
        }
        [out appendString:[cells componentsJoinedByString:@","]];
        [out appendString:@"\n"];
    }
    return [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

+ (NSString *)jsonEscape:(NSString *)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value ?: @"" options:0 error:nil];
    if (!data) return @"\"\"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"\"\"";
}

+ (BOOL)writeJSONRows:(NSArray<NSDictionary *> *)rows
                 path:(NSString *)path
          columnNames:(nullable NSArray<NSString *> *)columnNames
                error:(NSError **)error {
    NSArray *cols = [self resolveColumns:columnNames rows:rows];
    // 手动按列序写 JSON，避免 NSDictionary 序列化打乱 key 顺序
    NSMutableString *out = [NSMutableString stringWithString:@"[\n"];
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        NSDictionary *row = rows[i];
        [out appendString:@"  {"];
        for (NSInteger c = 0; c < (NSInteger)cols.count; c++) {
            NSString *key = cols[c];
            if (c > 0) [out appendString:@", "];
            [out appendFormat:@"%@: %@", [self jsonEscape:key], [self jsonEscape:[self stringValue:row[key]]]];
        }
        [out appendString:@"}"];
        if (i + 1 < (NSInteger)rows.count) [out appendString:@","];
        [out appendString:@"\n"];
    }
    [out appendString:@"]\n"];
    return [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

+ (NSString *)xmlEscape:(NSString *)value {
    NSString *s = value ?: @"";
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return s;
}

+ (BOOL)writeXLSXRows:(NSArray<NSDictionary *> *)rows
                 path:(NSString *)path
          columnNames:(nullable NSArray<NSString *> *)columnNames
                error:(NSError **)error {
    NSArray *cols = [self resolveColumns:columnNames rows:rows];
    NSMutableString *sheet = [NSMutableString string];
    [sheet appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"];
    [sheet appendString:@"<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\n"];
    NSInteger r = 1;
    [sheet appendFormat:@"<row r=\"%ld\">", (long)r];
    for (NSInteger c = 0; c < (NSInteger)cols.count; c++) {
        NSString *ref = [self cellRefColumn:c + 1 row:r];
        [sheet appendFormat:@"<c r=\"%@\" t=\"inlineStr\"><is><t>%@</t></is></c>", ref, [self xmlEscape:cols[c]]];
    }
    [sheet appendString:@"</row>\n"];
    r++;
    for (NSDictionary *row in rows) {
        [sheet appendFormat:@"<row r=\"%ld\">", (long)r];
        for (NSInteger c = 0; c < (NSInteger)cols.count; c++) {
            NSString *s = [self stringValue:row[cols[c]]];
            NSString *ref = [self cellRefColumn:c + 1 row:r];
            [sheet appendFormat:@"<c r=\"%@\" t=\"inlineStr\"><is><t>%@</t></is></c>", ref, [self xmlEscape:s]];
        }
        [sheet appendString:@"</row>\n"];
        r++;
    }
    [sheet appendString:@"</sheetData></worksheet>"];

    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *xl = [tempRoot stringByAppendingPathComponent:@"xl"];
    NSString *xlRels = [xl stringByAppendingPathComponent:@"_rels"];
    NSString *rels = [tempRoot stringByAppendingPathComponent:@"_rels"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:xlRels withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[xl stringByAppendingPathComponent:@"worksheets"] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:rels withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *contentTypes =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
         "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
         "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
         "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
         "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
         "</Types>";
    NSString *rootRels =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
         "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
         "</Relationships>";
    NSString *workbook =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
         "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
         "<sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>";
    NSString *wbRels =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
         "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>"
         "</Relationships>";

    [contentTypes writeToFile:[tempRoot stringByAppendingPathComponent:@"[Content_Types].xml"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [rootRels writeToFile:[rels stringByAppendingPathComponent:@".rels"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [workbook writeToFile:[xl stringByAppendingPathComponent:@"workbook.xml"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [wbRels writeToFile:[xlRels stringByAppendingPathComponent:@"workbook.xml.rels"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [sheet writeToFile:[xl stringByAppendingPathComponent:@"worksheets/sheet1.xml"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/zip"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:tempRoot];
    task.arguments = @[ @"-qr", path, @"[Content_Types].xml", @"_rels", @"xl" ];
    NSPipe *pipe = [NSPipe pipe];
    task.standardError = pipe;
    BOOL launched = [task launchAndReturnError:error];
    if (!launched) {
        NSString *csvPath = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"csv"];
        BOOL ok = [self writeCSVRows:rows path:csvPath columnNames:columnNames error:error];
        [fm removeItemAtPath:tempRoot error:nil];
        return ok;
    }
    [task waitUntilExit];
    [fm removeItemAtPath:tempRoot error:nil];
    if (task.terminationStatus != 0) {
        NSString *csvPath = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"csv"];
        return [self writeCSVRows:rows path:csvPath columnNames:columnNames error:error];
    }
    return YES;
}

+ (NSString *)cellRefColumn:(NSInteger)col row:(NSInteger)row {
    NSMutableString *name = [NSMutableString string];
    NSInteger n = col;
    while (n > 0) {
        NSInteger rem = (n - 1) % 26;
        [name insertString:[NSString stringWithFormat:@"%c", (char)('A' + rem)] atIndex:0];
        n = (n - 1) / 26;
    }
    return [NSString stringWithFormat:@"%@%ld", name, (long)row];
}

+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
               outputPath:(NSString *)outputPath
                 sinkType:(BrowserScraperSinkType)sinkType
                    error:(NSError **)error {
    return [self writeNDJSONAtPath:ndjsonPath
                        outputPath:outputPath
                          sinkType:sinkType
                       columnNames:nil
                             error:error];
}

+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
               outputPath:(NSString *)outputPath
                 sinkType:(BrowserScraperSinkType)sinkType
              columnNames:(nullable NSArray<NSString *> *)columnNames
                    error:(NSError **)error {
    NSArray *rows = [self loadRowsFromNDJSON:ndjsonPath error:error];
    if (!rows) return NO;
    [[NSFileManager defaultManager] createDirectoryAtPath:[outputPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    switch (sinkType) {
        case BrowserScraperSinkTypeCSV:
            return [self writeCSVRows:rows path:outputPath columnNames:columnNames error:error];
        case BrowserScraperSinkTypeJSON:
            return [self writeJSONRows:rows path:outputPath columnNames:columnNames error:error];
        case BrowserScraperSinkTypeXLSX:
        default:
            return [self writeXLSXRows:rows path:outputPath columnNames:columnNames error:error];
    }
}

@end
