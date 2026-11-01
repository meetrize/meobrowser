#import "AIBridgeToolSimulator.h"

@implementation AIBridgeToolSimResult
@end

@implementation AIBridgeToolSimulator

+ (NSUInteger)maxPromptChars {
    // DeepSeek 等网页输入可吃更长文本；仍设上限防卡死。
    return 48000;
}

/// messages 至少保留的字符预算（优先于 tools 长描述）
+ (NSUInteger)minMessagesBudget {
    return 16000;
}

#pragma mark - Enable / tool_choice

+ (BOOL)shouldEnableForRequest:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    id tools = json[@"tools"];
    if (![tools isKindOfClass:[NSArray class]] || [(NSArray *)tools count] == 0) {
        return NO;
    }
    id choice = json[@"tool_choice"];
    if ([choice isKindOfClass:[NSString class]] &&
        [((NSString *)choice).lowercaseString isEqualToString:@"none"]) {
        return NO;
    }
    return YES;
}

+ (BOOL)requiresToolCallsForRequest:(NSDictionary *)json {
    id choice = json[@"tool_choice"];
    if ([choice isKindOfClass:[NSString class]]) {
        NSString *s = ((NSString *)choice).lowercaseString;
        return [s isEqualToString:@"required"];
    }
    if ([choice isKindOfClass:[NSDictionary class]]) {
        // {"type":"function","function":{"name":"..."}}
        return YES;
    }
    return NO;
}

+ (nullable NSString *)forcedFunctionNameFromRequest:(NSDictionary *)json {
    id choice = json[@"tool_choice"];
    if (![choice isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id fn = ((NSDictionary *)choice)[@"function"];
    if ([fn isKindOfClass:[NSDictionary class]]) {
        id name = ((NSDictionary *)fn)[@"name"];
        if ([name isKindOfClass:[NSString class]] && [(NSString *)name length]) {
            return name;
        }
    }
    return nil;
}

#pragma mark - Content helpers

+ (NSString *)stringifyContent:(id)content {
    if ([content isKindOfClass:[NSString class]]) {
        return (NSString *)content;
    }
    if ([content isKindOfClass:[NSArray class]]) {
        NSMutableString *acc = [NSMutableString string];
        for (id part in (NSArray *)content) {
            if (![part isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *d = part;
            NSString *type = [d[@"type"] isKindOfClass:[NSString class]] ? d[@"type"] : @"";
            if ([type isEqualToString:@"text"] && [d[@"text"] isKindOfClass:[NSString class]]) {
                [acc appendString:d[@"text"]];
            } else if ([type isEqualToString:@"image_url"]) {
                [acc appendString:@"[image]"];
            }
        }
        return acc;
    }
    if (content == nil || content == [NSNull null]) {
        return @"";
    }
    return [content description] ?: @"";
}

+ (nullable NSData *)jsonData:(id)obj {
    if (!obj || obj == [NSNull null]) {
        return nil;
    }
    if (![NSJSONSerialization isValidJSONObject:obj]) {
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

+ (NSString *)jsonString:(id)obj pretty:(BOOL)pretty {
    NSJSONWritingOptions opts = pretty ? NSJSONWritingPrettyPrinted : 0;
    if (!obj || obj == [NSNull null]) {
        return @"null";
    }
    if (![NSJSONSerialization isValidJSONObject:obj]) {
        NSString *s = [obj description] ?: @"";
        NSData *sd = [NSJSONSerialization dataWithJSONObject:s options:0 error:nil];
        return sd ? [[NSString alloc] initWithData:sd encoding:NSUTF8StringEncoding] : @"\"\"";
    }
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:opts error:nil];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null";
}

+ (NSArray<NSString *> *)allowedToolNamesFromRequest:(NSDictionary *)json {
    NSMutableArray *names = [NSMutableArray array];
    id tools = json[@"tools"];
    if (![tools isKindOfClass:[NSArray class]]) {
        return names;
    }
    for (id t in (NSArray *)tools) {
        if (![t isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id fn = ((NSDictionary *)t)[@"function"];
        if (![fn isKindOfClass:[NSDictionary class]]) {
            // some clients put name at top level
            id name = ((NSDictionary *)t)[@"name"];
            if ([name isKindOfClass:[NSString class]] && [(NSString *)name length]) {
                [names addObject:name];
            }
            continue;
        }
        id name = ((NSDictionary *)fn)[@"name"];
        if ([name isKindOfClass:[NSString class]] && [(NSString *)name length]) {
            [names addObject:name];
        }
    }
    return names;
}

/// 去掉 schema 里的 description / example 等冗长字段，只留结构。
+ (id)slimJSONSchema:(id)schema depth:(NSInteger)depth {
    if (depth > 8 || !schema || schema == [NSNull null]) {
        return schema;
    }
    if ([schema isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)schema;
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        static NSSet *keep;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            keep = [NSSet setWithArray:@[
                @"type", @"properties", @"required", @"items", @"enum",
                @"anyOf", @"oneOf", @"allOf", @"additionalProperties",
                @"minItems", @"maxItems", @"minimum", @"maximum", @"format",
                @"const", @"$ref"
            ]];
        });
        for (NSString *key in d) {
            if (![keep containsObject:key]) {
                continue; // drop description / default / examples / title …
            }
            id val = d[key];
            if ([key isEqualToString:@"properties"] && [val isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *props = [NSMutableDictionary dictionary];
                [(NSDictionary *)val enumerateKeysAndObjectsUsingBlock:^(id k, id obj, BOOL *stop) {
                    (void)stop;
                    props[k] = [self slimJSONSchema:obj depth:depth + 1];
                }];
                out[key] = props;
            } else if ([key isEqualToString:@"items"] ||
                       [key isEqualToString:@"additionalProperties"] ||
                       [key isEqualToString:@"anyOf"] ||
                       [key isEqualToString:@"oneOf"] ||
                       [key isEqualToString:@"allOf"]) {
                out[key] = [self slimJSONSchema:val depth:depth + 1];
            } else {
                out[key] = val;
            }
        }
        return out;
    }
    if ([schema isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (id item in (NSArray *)schema) {
            [arr addObject:[self slimJSONSchema:item depth:depth + 1] ?: [NSNull null]];
        }
        return arr;
    }
    return schema;
}

+ (NSString *)shortDescription:(NSString *)desc maxLen:(NSUInteger)maxLen {
    if (desc.length == 0) {
        return @"";
    }
    NSString *s = [desc stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    // 取首行 / 首句，去掉 HTML 示例块噪音
    NSRange nl = [s rangeOfString:@"\n"];
    if (nl.location != NSNotFound) {
        s = [s substringToIndex:nl.location];
    }
    NSRange ex = [s rangeOfString:@"<example>" options:NSCaseInsensitiveSearch];
    if (ex.location != NSNotFound) {
        s = [s substringToIndex:ex.location];
    }
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length > maxLen) {
        s = [[s substringToIndex:maxLen] stringByAppendingString:@"…"];
    }
    return s;
}

/// 极简：仅 name（用于预算不足时）
+ (NSArray *)minimalToolNamesOnly:(NSArray *)tools {
    NSMutableArray *out = [NSMutableArray array];
    for (id t in tools) {
        if (![t isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *tool = (NSDictionary *)t;
        NSString *name = nil;
        id fn = tool[@"function"];
        if ([fn isKindOfClass:[NSDictionary class]] && [fn[@"name"] isKindOfClass:[NSString class]]) {
            name = fn[@"name"];
        } else if ([tool[@"name"] isKindOfClass:[NSString class]]) {
            name = tool[@"name"];
        }
        if (name.length) {
            [out addObject:@{@"name": name}];
        }
    }
    return out;
}

+ (NSArray *)compactToolsForPrompt:(NSArray *)tools {
    return [self compactToolsForPrompt:tools includeDescriptions:YES includeParameters:YES];
}

+ (NSArray *)compactToolsForPrompt:(NSArray *)tools
              includeDescriptions:(BOOL)includeDescriptions
               includeParameters:(BOOL)includeParameters {
    NSMutableArray *out = [NSMutableArray array];
    for (id t in tools) {
        if (![t isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *tool = (NSDictionary *)t;
        NSDictionary *fnSrc = nil;
        if ([tool[@"function"] isKindOfClass:[NSDictionary class]]) {
            fnSrc = tool[@"function"];
        } else if ([tool[@"name"] isKindOfClass:[NSString class]]) {
            fnSrc = tool;
        }
        if (!fnSrc) {
            continue;
        }
        NSMutableDictionary *f = [NSMutableDictionary dictionary];
        if ([fnSrc[@"name"] isKindOfClass:[NSString class]]) {
            f[@"name"] = fnSrc[@"name"];
        }
        if (includeDescriptions && [fnSrc[@"description"] isKindOfClass:[NSString class]]) {
            NSString *shortDesc = [self shortDescription:fnSrc[@"description"] maxLen:120];
            if (shortDesc.length) {
                f[@"description"] = shortDesc;
            }
        }
        if (includeParameters && fnSrc[@"parameters"]) {
            f[@"parameters"] = [self slimJSONSchema:fnSrc[@"parameters"] depth:0];
        }
        [out addObject:@{@"type": @"function", @"function": f}];
    }
    return out;
}

+ (NSDictionary *)compactMessage:(NSDictionary *)m {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *role = [m[@"role"] isKindOfClass:[NSString class]] ? m[@"role"] : @"user";
    out[@"role"] = role;
    NSString *content = [self stringifyContent:m[@"content"]];
    if (content.length) {
        out[@"content"] = content;
    }
    if ([m[@"name"] isKindOfClass:[NSString class]]) {
        out[@"name"] = m[@"name"];
    }
    if ([m[@"tool_call_id"] isKindOfClass:[NSString class]]) {
        out[@"tool_call_id"] = m[@"tool_call_id"];
    }
    id tcs = m[@"tool_calls"];
    if ([tcs isKindOfClass:[NSArray class]] && [(NSArray *)tcs count]) {
        NSMutableArray *slim = [NSMutableArray array];
        for (id tc in (NSArray *)tcs) {
            if (![tc isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *d = tc;
            NSMutableDictionary *one = [NSMutableDictionary dictionary];
            if ([d[@"id"] isKindOfClass:[NSString class]]) {
                one[@"id"] = d[@"id"];
            }
            id fn = d[@"function"];
            if ([fn isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *f = [NSMutableDictionary dictionary];
                if ([fn[@"name"] isKindOfClass:[NSString class]]) {
                    f[@"name"] = fn[@"name"];
                }
                if ([fn[@"arguments"] isKindOfClass:[NSString class]]) {
                    f[@"arguments"] = fn[@"arguments"];
                } else if (fn[@"arguments"]) {
                    f[@"arguments"] = [self jsonString:fn[@"arguments"] pretty:NO];
                }
                one[@"function"] = f;
            }
            [slim addObject:one];
        }
        out[@"tool_calls"] = slim;
    }
    return out;
}

+ (NSArray *)truncateMessages:(NSArray *)messages maxChars:(NSUInteger)maxChars {
    if (messages.count == 0) {
        return @[];
    }
    NSMutableArray *compacted = [NSMutableArray arrayWithCapacity:messages.count];
    NSDictionary *firstSystem = nil;
    for (id m in messages) {
        if (![m isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *c = [self compactMessage:(NSDictionary *)m];
        if (!firstSystem && [c[@"role"] isEqualToString:@"system"]) {
            firstSystem = c;
        }
        [compacted addObject:c];
    }
    if (compacted.count == 0) {
        return @[];
    }

    // Prefer keeping first system + tail
    NSMutableArray *result = [NSMutableArray array];
    NSInteger start = 0;
    if (firstSystem) {
        [result addObject:firstSystem];
        // skip the first system occurrence in the tail walk
        for (NSUInteger i = 0; i < compacted.count; i++) {
            if (compacted[i] == firstSystem ||
                ([compacted[i][@"role"] isEqualToString:@"system"] && i == 0)) {
                start = (NSInteger)i + 1;
                break;
            }
        }
    }

    NSMutableArray *tail = [NSMutableArray array];
    for (NSInteger i = (NSInteger)compacted.count - 1; i >= start; i--) {
        [tail insertObject:compacted[(NSUInteger)i] atIndex:0];
        NSMutableArray *candidate = [NSMutableArray array];
        [candidate addObjectsFromArray:result];
        if (result.count && tail.count && start < (NSInteger)compacted.count - (NSInteger)tail.count) {
            // will add truncation marker later
        }
        [candidate addObjectsFromArray:tail];
        NSString *probe = [self jsonString:candidate pretty:NO];
        if (probe.length > maxChars && tail.count > 1) {
            [tail removeObjectAtIndex:0];
            break;
        }
        if (probe.length > maxChars && tail.count == 1) {
            break;
        }
    }

    NSMutableArray *final = [NSMutableArray array];
    [final addObjectsFromArray:result];
    NSInteger keptFrom = (NSInteger)compacted.count - (NSInteger)tail.count;
    if (keptFrom > start) {
        [final addObject:@{
            @"role": @"system",
            @"content": [NSString stringWithFormat:@"[truncated %ld earlier messages]",
                         (long)(keptFrom - start)]
        }];
    }
    [final addObjectsFromArray:tail];

    // Final hard clip on JSON size of messages alone
    while (final.count > 1) {
        NSString *s = [self jsonString:final pretty:NO];
        if (s.length <= maxChars) {
            break;
        }
        // drop earliest non-first
        if (final.count > 2 && [final[1][@"content"] isKindOfClass:[NSString class]] &&
            [final[1][@"content"] hasPrefix:@"[truncated"]) {
            [final removeObjectAtIndex:2];
        } else if (final.count > 1) {
            [final removeObjectAtIndex:1];
        } else {
            break;
        }
    }
    return final;
}

#pragma mark - Prompt build

+ (NSString *)instructionBlockRequiringTools:(BOOL)require
                              forcedFunction:(NSString *)forcedName {
    NSMutableString *s = [NSMutableString string];
    [s appendString:
     @"You are a coding agent API. Solve ONLY the latest programming task with tools.\n"
     @"你是编程 Agent API：只用工具解决「最新」的编程任务；忽略历史里跑题的闲聊。\n\n"
     @"Reply with ONE JSON object only. No markdown. No prose outside JSON.\n"
     @"只输出一个 JSON 对象；不要 markdown；JSON 外不要写字。\n\n"
     @"Schema A:\n"
     @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"TOOL_NAME\",\"arguments\":{...}}]}\n\n"
     @"Schema B:\n"
     @"{\"mode\":\"message\",\"content\":\"...\"}\n\n"
     @"CRITICAL — valid JSON string escaping:\n"
     @"Inside any JSON string, every double-quote MUST be written as \\\" .\n"
     @"VALID example (edit a Python file):\n"
     @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"edit_file\",\"arguments\":{\"path\":\"test/hello.py\",\"edits\":[{\"old_text\":\"print(\\\"Hello, World!\\\")\",\"new_text\":\"print(\\\"你好，世界！\\\")\"}]}}]}\n"
     @"INVALID (never do this — breaks JSON):\n"
     @"{\"old_text\":\"print(\"Hello, World!\")\"}\n"
     @"Tip: when possible use single quotes in code snippets inside JSON, e.g. print('你好，世界！').\n\n"
     @"Paths: use project-relative paths required by tools (e.g. test/hello.py). "
     @"Do NOT use absolute paths like /Volumes/... unless a tool explicitly requires them.\n"
     @"路径必须用工具要求的项目相对路径（如 test/hello.py），不要用 /Volumes/... 绝对路径。\n\n"];
    if (require) {
        [s appendString:@"You MUST use Schema A (mode=tool_calls). Do not use Schema B.\n"];
        [s appendString:@"必须使用 Schema A（mode=tool_calls），禁止 Schema B。\n"];
    } else {
        [s appendString:@"If the user asks to create/edit/read/search code or files, you MUST use Schema A.\n"];
        [s appendString:@"用户要求读写改文件或搜索代码时，必须用 Schema A 调用工具，不要只用文字描述怎么改。\n"];
    }
    if (forcedName.length) {
        [s appendFormat:@"You MUST call the function named \"%@\".\n", forcedName];
        [s appendFormat:@"必须调用名为 \"%@\" 的工具。\n", forcedName];
    }
    return s;
}

#pragma mark - Message filter / path rewrite

+ (NSString *)truncateSystemContent:(NSString *)content maxLen:(NSUInteger)maxLen {
    if (content.length <= maxLen) {
        return content ?: @"";
    }
    // Prefer keeping project roots / path rules from the tail of system prompts
    NSUInteger keepHead = maxLen / 3;
    NSUInteger keepTail = maxLen - keepHead - 40;
    return [NSString stringWithFormat:@"%@\n…[system truncated]…\n%@",
            [content substringToIndex:keepHead],
            [content substringFromIndex:content.length - keepTail]];
}

/// 丢掉历史散文 assistant（含跑题内容），只保留 system / user / tool / 带 tool_calls 的 assistant。
+ (NSArray *)filterMessagesForAgent:(NSArray *)messages {
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *systemMsg = nil;
    NSMutableArray *body = [NSMutableArray array];
    for (id raw in messages) {
        if (![raw isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *c = [self compactMessage:(NSDictionary *)raw];
        NSString *role = c[@"role"] ?: @"";
        if ([role isEqualToString:@"system"]) {
            if (!systemMsg) {
                NSMutableDictionary *s = [c mutableCopy];
                s[@"content"] = [self truncateSystemContent:s[@"content"] ?: @"" maxLen:2800];
                systemMsg = s;
            }
            continue;
        }
        if ([role isEqualToString:@"assistant"]) {
            id tcs = c[@"tool_calls"];
            BOOL hasTools = [tcs isKindOfClass:[NSArray class]] && [(NSArray *)tcs count] > 0;
            if (!hasTools) {
                continue; // drop prose / polluted history
            }
        }
        [body addObject:c];
    }
    // Keep last few body messages; always include the final user turn
    NSUInteger keep = 8;
    if (body.count > keep) {
        NSArray *tail = [body subarrayWithRange:NSMakeRange(body.count - keep, keep)];
        [body removeAllObjects];
        [body addObjectsFromArray:tail];
    }
    if (systemMsg) {
        [out addObject:systemMsg];
    }
    [out addObjectsFromArray:body];
    return out;
}

+ (NSArray<NSString *> *)projectRootsFromRequest:(NSDictionary *)json {
    NSMutableArray *roots = [NSMutableArray array];
    void (^addRoot)(NSString *) = ^(NSString *r) {
        NSString *t = [r stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) return;
        if ([t hasPrefix:@"file://"]) {
            NSURL *u = [NSURL URLWithString:t];
            t = u.path.length ? u.path : t;
        }
        while ([t hasSuffix:@"/"] && t.length > 1) {
            t = [t substringToIndex:t.length - 1];
        }
        if (t.length && ![roots containsObject:t]) {
            [roots addObject:t];
        }
    };
    id messages = json[@"messages"];
    if ([messages isKindOfClass:[NSArray class]]) {
        for (id m in (NSArray *)messages) {
            if (![m isKindOfClass:[NSDictionary class]]) continue;
            NSString *content = [self stringifyContent:((NSDictionary *)m)[@"content"]];
            if (!content.length) continue;
            // `- `/abs/path`` or `- /abs/path`
            NSRegularExpression *re = [NSRegularExpression
                regularExpressionWithPattern:@"(?m)^\\s*-\\s*`?(/[^\\s`]+)`?"
                                     options:0 error:nil];
            [re enumerateMatchesInString:content options:0 range:NSMakeRange(0, content.length)
                              usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                (void)flags; (void)stop;
                if (result.numberOfRanges >= 2) {
                    addRoot([content substringWithRange:[result rangeAtIndex:1]]);
                }
            }];
            // file:///.../hello.py → 取父目录作为 root，避免把文件路径当成 root
            NSRegularExpression *fileRe = [NSRegularExpression
                regularExpressionWithPattern:@"file://(/[^\\s\\)]+)"
                                     options:0 error:nil];
            [fileRe enumerateMatchesInString:content options:0 range:NSMakeRange(0, content.length)
                                  usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                (void)flags; (void)stop;
                if (result.numberOfRanges >= 2) {
                    NSString *p = [content substringWithRange:[result rangeAtIndex:1]];
                    NSString *dir = p.stringByDeletingLastPathComponent;
                    addRoot(dir.length ? dir : p);
                }
            }];
            // ```lang /abs/path
            NSRegularExpression *fenceRe = [NSRegularExpression
                regularExpressionWithPattern:@"```[a-zA-Z0-9_+-]*\\s+(/[^\\n`]+)"
                                     options:0 error:nil];
            [fenceRe enumerateMatchesInString:content options:0 range:NSMakeRange(0, content.length)
                                   usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                (void)flags; (void)stop;
                if (result.numberOfRanges >= 2) {
                    NSString *p = [content substringWithRange:[result rangeAtIndex:1]];
                    addRoot([p stringByDeletingLastPathComponent]);
                }
            }];
        }
    }
    return roots;
}

+ (NSString *)rewriteAbsolutePath:(NSString *)path roots:(NSArray<NSString *> *)roots {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        return path;
    }
    NSString *p = path;
    if ([p hasPrefix:@"file://"]) {
        NSURL *u = [NSURL URLWithString:p];
        if (u.path.length) {
            p = u.path;
        }
    }
    if (![p hasPrefix:@"/"]) {
        return path; // already relative
    }
    NSString *bestRoot = nil;
    for (NSString *root in roots) {
        if ([p isEqualToString:root] || [p hasPrefix:[root stringByAppendingString:@"/"]]) {
            if (!bestRoot || root.length > bestRoot.length) {
                bestRoot = root;
            }
        }
    }
    if (!bestRoot.length) {
        return path;
    }
    NSString *rootName = bestRoot.lastPathComponent ?: bestRoot;
    if ([p isEqualToString:bestRoot]) {
        return rootName;
    }
    NSString *rel = [p substringFromIndex:bestRoot.length];
    while ([rel hasPrefix:@"/"]) {
        rel = [rel substringFromIndex:1];
    }
    return rel.length ? [NSString stringWithFormat:@"%@/%@", rootName, rel] : rootName;
}

+ (id)rewritePathsInJSON:(id)obj roots:(NSArray<NSString *> *)roots {
    if (roots.count == 0 || !obj || obj == [NSNull null]) {
        return obj;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            (void)stop;
            NSString *k = [key isKindOfClass:[NSString class]] ? key : [key description];
            if ([val isKindOfClass:[NSString class]] &&
                ([k isEqualToString:@"path"] ||
                 [k isEqualToString:@"source_path"] ||
                 [k isEqualToString:@"destination_path"] ||
                 [k hasSuffix:@"_path"])) {
                out[key] = [self rewriteAbsolutePath:(NSString *)val roots:roots];
            } else {
                out[key] = [self rewritePathsInJSON:val roots:roots];
            }
        }];
        return out;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (id item in (NSArray *)obj) {
            [arr addObject:[self rewritePathsInJSON:item roots:roots] ?: [NSNull null]];
        }
        return arr;
    }
    return obj;
}

/// 修复 LLM 常见的「字符串内未转义双引号」导致的非法 JSON。
+ (NSString *)repairUnescapedQuotesInJSON:(NSString *)input {
    if (input.length == 0) {
        return input;
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:input.length + 16];
    BOOL inString = NO;
    BOOL escape = NO;
    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];
        if (!inString) {
            [out appendFormat:@"%C", c];
            if (c == '"') {
                inString = YES;
            }
            continue;
        }
        if (escape) {
            [out appendFormat:@"%C", c];
            escape = NO;
            continue;
        }
        if (c == '\\') {
            [out appendFormat:@"%C", c];
            escape = YES;
            continue;
        }
        if (c == '"') {
            NSUInteger j = i + 1;
            while (j < input.length &&
                   [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[input characterAtIndex:j]]) {
                j++;
            }
            unichar next = (j < input.length) ? [input characterAtIndex:j] : 0;
            // 合法字符串结束：后面是 , } ] : 或结束
            if (next == ',' || next == '}' || next == ']' || next == ':' || next == 0) {
                inString = NO;
                [out appendFormat:@"%C", c];
            } else {
                // 字符串内部的裸引号 → 转义
                [out appendString:@"\\\""];
            }
            continue;
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

+ (nullable id)parseJSONObjectString:(NSString *)jsonStr error:(NSString **)outError {
    if (!jsonStr.length) {
        if (outError) *outError = @"empty json";
        return nil;
    }
    NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
        return obj;
    }
    NSString *repaired = [self repairUnescapedQuotesInJSON:jsonStr];
    if (![repaired isEqualToString:jsonStr]) {
        NSData *d2 = [repaired dataUsingEncoding:NSUTF8StringEncoding];
        obj = [NSJSONSerialization JSONObjectWithData:d2 options:0 error:&err];
        if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
            return obj;
        }
    }
    if (outError) {
        *outError = err.localizedDescription ?: @"invalid json";
    }
    return nil;
}

+ (NSString *)fitToolsJSON:(NSArray *)tools rawTools:(NSArray *)rawTools maxChars:(NSUInteger)maxChars {
    if (maxChars < 32) {
        return @"[]";
    }
    // 逐步降级：带描述+参数 → 无描述+参数 → 仅 name
    NSArray *levels = @[
        [self compactToolsForPrompt:rawTools includeDescriptions:YES includeParameters:YES],
        [self compactToolsForPrompt:rawTools includeDescriptions:NO includeParameters:YES],
        [self minimalToolNamesOnly:rawTools]
    ];
    (void)tools;
    for (NSArray *level in levels) {
        NSString *s = [self jsonString:level pretty:NO];
        if (s.length <= maxChars) {
            return s;
        }
    }
    // 仍超长：截断 name 列表
    NSArray *namesOnly = [self minimalToolNamesOnly:rawTools];
    NSMutableArray *kept = [NSMutableArray array];
    for (id item in namesOnly) {
        [kept addObject:item];
        NSString *s = [self jsonString:kept pretty:NO];
        if (s.length > maxChars) {
            [kept removeLastObject];
            break;
        }
    }
    return [self jsonString:kept.count ? kept : @[@{@"name": @"read_file"}] pretty:NO];
}

+ (NSString *)buildWebpagePromptFromRequest:(NSDictionary *)json {
    BOOL require = [self requiresToolCallsForRequest:json];
    NSString *forced = [self forcedFunctionNameFromRequest:json];
    NSUInteger budget = [self maxPromptChars];

    NSString *instructions = [self instructionBlockRequiringTools:require forcedFunction:forced];
    NSString *footer =
        @"\n\n## Your reply\n"
        @"Output ONE valid JSON object now (Schema A for file edits).\n"
        @"Remember: escape every \" inside strings as \\\" .\n"
        @"Use project-relative paths (e.g. test/hello.py), not /Volumes/... absolute paths.\n";

    id rawTools = json[@"tools"];
    NSArray *toolArr = [rawTools isKindOfClass:[NSArray class]] ? (NSArray *)rawTools : @[];
    id messages = json[@"messages"];
    NSArray *rawMsgs = [messages isKindOfClass:[NSArray class]] ? (NSArray *)messages : @[];
    // 过滤跑题的历史 prose，只留编程相关上下文
    NSArray *msgArr = [self filterMessagesForAgent:rawMsgs];

    // 提取最新 user 任务，放在末尾强化（避免被长 system/历史淹没）
    NSString *latestUser = @"";
    for (NSInteger i = (NSInteger)rawMsgs.count - 1; i >= 0; i--) {
        id m = rawMsgs[(NSUInteger)i];
        if (![m isKindOfClass:[NSDictionary class]]) continue;
        if ([m[@"role"] isEqualToString:@"user"]) {
            latestUser = [self stringifyContent:m[@"content"]];
            break;
        }
    }
    if (latestUser.length > 6000) {
        latestUser = [[latestUser substringToIndex:5000]
            stringByAppendingFormat:@"\n…[latest task truncated]…\n%@",
            [latestUser substringFromIndex:latestUser.length - 800]];
    }
    NSString *latestSection = latestUser.length
        ? [NSString stringWithFormat:@"\n\n## Latest user task (do this)\n%@\n", latestUser]
        : @"";

    // 1) 先给 messages 留足预算（引用文件必须进网页），tools 吃剩余
    NSUInteger overhead = instructions.length + footer.length + latestSection.length + 64;
    NSUInteger remaining = budget > overhead ? budget - overhead : budget / 2;
    NSUInteger msgBudget = MAX([self minMessagesBudget], remaining * 2 / 3);
    if (msgBudget + 512 > remaining) {
        msgBudget = remaining > 1024 ? remaining - 512 : remaining / 2;
    }

    NSArray *truncatedMsgs = [self truncateMessages:msgArr maxChars:msgBudget];
    // 紧凑 JSON，省字符
    NSString *messagesJSON = [self jsonString:truncatedMsgs pretty:NO];
    // 单条超长 user（大文件上下文）：硬截断内容但仍保留尾部任务句
    if (messagesJSON.length > msgBudget && truncatedMsgs.count > 0) {
        NSMutableArray *clipped = [truncatedMsgs mutableCopy];
        for (NSInteger i = (NSInteger)clipped.count - 1; i >= 0; i--) {
            NSMutableDictionary *m = [clipped[(NSUInteger)i] mutableCopy];
            NSString *c = [m[@"content"] isKindOfClass:[NSString class]] ? m[@"content"] : @"";
            if (c.length > 8000) {
                NSUInteger keepHead = 5000;
                NSUInteger keepTail = 2500;
                if (c.length > keepHead + keepTail) {
                    NSString *mid = [NSString stringWithFormat:@"\n…[content truncated %lu chars]…\n",
                                     (unsigned long)(c.length - keepHead - keepTail)];
                    m[@"content"] = [NSString stringWithFormat:@"%@%@%@",
                                     [c substringToIndex:keepHead], mid,
                                     [c substringFromIndex:c.length - keepTail]];
                    clipped[(NSUInteger)i] = m;
                }
            }
            messagesJSON = [self jsonString:clipped pretty:NO];
            if (messagesJSON.length <= msgBudget) {
                break;
            }
        }
        // 仍超：再跑 truncateMessages
        if (messagesJSON.length > msgBudget) {
            truncatedMsgs = [self truncateMessages:clipped maxChars:msgBudget];
            messagesJSON = [self jsonString:truncatedMsgs pretty:NO];
        }
    }

    NSUInteger toolsBudget = remaining > messagesJSON.length + 64
        ? remaining - messagesJSON.length - 64
        : 256;
    NSString *toolsJSON = [self fitToolsJSON:nil rawTools:toolArr maxChars:toolsBudget];

    // 2) Messages 在前，Tools 在后 —— 即便再截断也优先保住任务与附件上下文
    NSMutableString *prompt = [NSMutableString string];
    [prompt appendString:instructions];
    [prompt appendString:@"\n## Messages\n"];
    [prompt appendString:messagesJSON];
    [prompt appendString:@"\n\n## Available tools (compact)\n"];
    [prompt appendString:toolsJSON];
    [prompt appendString:latestSection];
    [prompt appendString:footer];

    if (prompt.length > budget) {
        // 只砍 tools 段：保留 messages + latest task
        NSString *marker = @"\n\n## Available tools (compact)\n";
        NSRange r = [prompt rangeOfString:marker];
        if (r.location != NSNotFound) {
            NSUInteger keepPrefix = r.location + r.length;
            NSUInteger tailLen = latestSection.length + footer.length + 32;
            NSUInteger room = budget > keepPrefix + tailLen ? budget - keepPrefix - tailLen : 64;
            NSString *slimTools = [self fitToolsJSON:nil rawTools:toolArr maxChars:room];
            NSMutableString *rebuilt = [NSMutableString string];
            [rebuilt appendString:[prompt substringToIndex:keepPrefix]];
            [rebuilt appendString:slimTools];
            [rebuilt appendString:latestSection];
            [rebuilt appendString:footer];
            if (rebuilt.length <= budget) {
                return rebuilt;
            }
            NSArray *names = [self allowedToolNamesFromRequest:json];
            rebuilt = [NSMutableString string];
            [rebuilt appendString:[prompt substringToIndex:keepPrefix]];
            [rebuilt appendString:[self jsonString:names pretty:NO]];
            [rebuilt appendString:latestSection];
            [rebuilt appendString:footer];
            if (rebuilt.length <= budget) {
                return rebuilt;
            }
        }
        return [[prompt substringToIndex:budget] stringByAppendingString:@"\n…[prompt truncated]\n"];
    }
    return prompt;
}

+ (NSString *)buildRepairPromptFromRequest:(NSDictionary *)json
                              previousText:(NSString *)previousText {
    BOOL require = [self requiresToolCallsForRequest:json];
    NSString *forced = [self forcedFunctionNameFromRequest:json];
    NSMutableString *prompt = [NSMutableString string];
    [prompt appendString:
     @"Your previous reply was NOT valid JSON (often because \" inside strings was not escaped as \\\"). "
     @"Reply again with ONLY one valid JSON object. No markdown.\n"
     @"上一轮 JSON 非法（常见原因：字符串里的 \" 未写成 \\\"）。请只输出一个合法 JSON。\n\n"
     @"VALID:\n"
     @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"edit_file\",\"arguments\":{\"path\":\"test/hello.py\",\"edits\":[{\"old_text\":\"print(\\\"Hello, World!\\\")\",\"new_text\":\"print(\\\"你好，世界！\\\")\"}]}}]}\n\n"];
    [prompt appendString:[self instructionBlockRequiringTools:require forcedFunction:forced]];
    NSArray *names = [self allowedToolNamesFromRequest:json];
    [prompt appendFormat:@"Allowed tool names: %@\n\n", [self jsonString:names pretty:NO]];
    // 带上最新用户任务，避免 repair 轮丢掉上下文
    id messages = json[@"messages"];
    if ([messages isKindOfClass:[NSArray class]]) {
        for (NSInteger i = (NSInteger)((NSArray *)messages).count - 1; i >= 0; i--) {
            id m = ((NSArray *)messages)[(NSUInteger)i];
            if ([m isKindOfClass:[NSDictionary class]] && [m[@"role"] isEqualToString:@"user"]) {
                NSString *u = [self stringifyContent:m[@"content"]];
                if (u.length > 2500) {
                    u = [[u substringToIndex:2500] stringByAppendingString:@"…"];
                }
                [prompt appendFormat:@"Latest user task:\n%@\n\n", u];
                break;
            }
        }
    }
    NSString *prev = previousText ?: @"";
    if (prev.length > 2500) {
        prev = [[prev substringToIndex:2500] stringByAppendingString:@"…"];
    }
    [prompt appendString:@"Previous invalid reply:\n"];
    [prompt appendString:prev];
    [prompt appendString:@"\n\nOutput valid JSON now.\n"];
    NSUInteger budget = [self maxPromptChars];
    if (prompt.length > budget) {
        return [[prompt substringToIndex:budget] stringByAppendingString:@"\n…[prompt truncated]\n"];
    }
    return prompt;
}

#pragma mark - Parse

+ (nullable NSString *)extractJSONObjectString:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    // Direct
    if ([trimmed hasPrefix:@"{"]) {
        NSString *balanced = [self firstBalancedJSONObject:trimmed];
        if (balanced) {
            return balanced;
        }
    }

    // Fenced ```json ... ```
    NSRegularExpression *fence = [NSRegularExpression
        regularExpressionWithPattern:@"```(?:json)?\\s*([\\s\\S]*?)```"
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
    NSTextCheckingResult *m = [fence firstMatchInString:trimmed
                                                options:0
                                                  range:NSMakeRange(0, trimmed.length)];
    if (m && m.numberOfRanges >= 2) {
        NSString *inner = [[trimmed substringWithRange:[m rangeAtIndex:1]]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *balanced = [self firstBalancedJSONObject:inner];
        if (balanced) {
            return balanced;
        }
    }

    // Scan first {
    NSRange brace = [trimmed rangeOfString:@"{"];
    if (brace.location != NSNotFound) {
        NSString *from = [trimmed substringFromIndex:brace.location];
        return [self firstBalancedJSONObject:from];
    }
    return nil;
}

+ (nullable NSString *)firstBalancedJSONObject:(NSString *)s {
    if (s.length == 0 || [s characterAtIndex:0] != '{') {
        return nil;
    }
    NSInteger depth = 0;
    BOOL inString = NO;
    BOOL escape = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (inString) {
            if (escape) {
                escape = NO;
            } else if (c == '\\') {
                escape = YES;
            } else if (c == '"') {
                inString = NO;
            }
            continue;
        }
        if (c == '"') {
            inString = YES;
            continue;
        }
        if (c == '{') {
            depth++;
        } else if (c == '}') {
            depth--;
            if (depth == 0) {
                return [s substringToIndex:i + 1];
            }
        }
    }
    return nil;
}

+ (NSString *)argumentsJSONString:(id)arguments {
    if ([arguments isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)arguments;
        // validate it's JSON; if not, wrap as JSON string value's content still returned as-is if parseable object elsewhere
        NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
        id obj = d.length ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if (obj) {
            return s;
        }
        // stringify as JSON string
        return [self jsonString:s pretty:NO];
    }
    if (arguments == nil || arguments == [NSNull null]) {
        return @"{}";
    }
    if ([arguments isKindOfClass:[NSDictionary class]] || [arguments isKindOfClass:[NSArray class]]) {
        return [self jsonString:arguments pretty:NO];
    }
    return [self jsonString:[arguments description] ?: @"" pretty:NO];
}

+ (AIBridgeToolSimResult *)parseWebpageText:(NSString *)text
                                 forRequest:(NSDictionary *)json {
    AIBridgeToolSimResult *result = [[AIBridgeToolSimResult alloc] init];
    NSString *jsonStr = [self extractJSONObjectString:text ?: @""];
    if (!jsonStr.length) {
        result.parseError = @"no JSON object found in reply";
        return result;
    }
    NSString *parseErr = nil;
    id obj = [self parseJSONObjectString:jsonStr error:&parseErr];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        result.parseError = parseErr ?: @"JSON root must be object";
        return result;
    }
    NSDictionary *root = (NSDictionary *)obj;
    NSArray<NSString *> *roots = [self projectRootsFromRequest:json];
    NSString *mode = [root[@"mode"] isKindOfClass:[NSString class]] ? root[@"mode"] : nil;
    if (!mode.length) {
        // Tolerate OpenAI-ish shapes without mode
        if ([root[@"tool_calls"] isKindOfClass:[NSArray class]]) {
            mode = @"tool_calls";
        } else if (root[@"content"] != nil) {
            mode = @"message";
        } else {
            result.parseError = @"missing mode";
            return result;
        }
    }

    BOOL require = [self requiresToolCallsForRequest:json];
    NSString *forced = [self forcedFunctionNameFromRequest:json];
    NSSet *allowed = [NSSet setWithArray:[self allowedToolNamesFromRequest:json]];

    if ([mode isEqualToString:@"message"]) {
        if (require) {
            result.parseError = @"tool_choice requires tool_calls but got mode=message";
            return result;
        }
        result.kind = AIBridgeToolSimKindMessage;
        result.content = [self stringifyContent:root[@"content"]];
        return result;
    }

    if (![mode isEqualToString:@"tool_calls"]) {
        result.parseError = [NSString stringWithFormat:@"unknown mode: %@", mode];
        return result;
    }

    id tcs = root[@"tool_calls"];
    if (![tcs isKindOfClass:[NSArray class]] || [(NSArray *)tcs count] == 0) {
        result.parseError = @"tool_calls empty";
        return result;
    }

    NSMutableArray *out = [NSMutableArray array];
    for (id item in (NSArray *)tcs) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            result.parseError = @"tool_calls item must be object";
            return result;
        }
        NSDictionary *tc = (NSDictionary *)item;
        NSString *name = nil;
        id arguments = nil;
        if ([tc[@"function"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *fn = tc[@"function"];
            name = [fn[@"name"] isKindOfClass:[NSString class]] ? fn[@"name"] : nil;
            arguments = fn[@"arguments"];
        } else {
            name = [tc[@"name"] isKindOfClass:[NSString class]] ? tc[@"name"] : nil;
            arguments = tc[@"arguments"];
        }
        if (!name.length) {
            result.parseError = @"tool call missing name";
            return result;
        }
        if (allowed.count && ![allowed containsObject:name]) {
            result.parseError = [NSString stringWithFormat:@"tool name not allowed: %@", name];
            return result;
        }
        if (forced.length && ![name isEqualToString:forced]) {
            result.parseError = [NSString stringWithFormat:@"tool_choice forced %@ but got %@", forced, name];
            return result;
        }
        NSString *callId = [tc[@"id"] isKindOfClass:[NSString class]] && [tc[@"id"] length]
            ? tc[@"id"]
            : [NSString stringWithFormat:@"call_%@", [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
        // shorten id a bit
        if (callId.length > 40) {
            callId = [callId substringToIndex:40];
        }
        // 绝对路径 → 项目相对路径（IDE 工具通常要求）
        if ([arguments isKindOfClass:[NSDictionary class]] || [arguments isKindOfClass:[NSArray class]]) {
            arguments = [self rewritePathsInJSON:arguments roots:roots];
        } else if ([arguments isKindOfClass:[NSString class]]) {
            NSString *innerErr = nil;
            id parsedArgs = [self parseJSONObjectString:(NSString *)arguments error:&innerErr];
            if (parsedArgs) {
                parsedArgs = [self rewritePathsInJSON:parsedArgs roots:roots];
                arguments = parsedArgs;
            }
        }
        NSString *argsStr = [self argumentsJSONString:arguments];
        // 最终校验：arguments 必须是可被 IDE 再 parse 的 JSON 文本
        if (argsStr.length) {
            NSData *ad = [argsStr dataUsingEncoding:NSUTF8StringEncoding];
            id acheck = ad.length ? [NSJSONSerialization JSONObjectWithData:ad options:0 error:nil] : nil;
            if (!acheck) {
                result.parseError = [NSString stringWithFormat:
                                     @"tool %@ arguments is not valid JSON after encode", name];
                return result;
            }
        }
        [out addObject:@{
            @"id": callId,
            @"type": @"function",
            @"function": @{
                @"name": name,
                @"arguments": argsStr ?: @"{}"
            }
        }];
    }

    result.kind = AIBridgeToolSimKindToolCalls;
    result.toolCalls = out;
    return result;
}

@end
