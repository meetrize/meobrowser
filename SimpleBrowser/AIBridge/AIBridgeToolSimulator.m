#import "AIBridgeToolSimulator.h"

@implementation AIBridgeToolSimResult
@end

@implementation AIBridgeToolSimulator

+ (NSUInteger)maxPromptChars {
    // 网页对话窗口上下文远小于真 API；压紧后把额度留给代码附件。
    return 28000;
}

/// messages（含代码文件）至少保留的字符预算
+ (NSUInteger)minMessagesBudget {
    return 18000;
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

+ (BOOL)messagesEndWithToolResult:(NSArray *)messages {
    for (NSInteger i = (NSInteger)messages.count - 1; i >= 0; i--) {
        id m = messages[(NSUInteger)i];
        if (![m isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *role = ((NSDictionary *)m)[@"role"];
        if ([role isEqualToString:@"tool"]) {
            return YES;
        }
        if ([role isEqualToString:@"user"] || [role isEqualToString:@"assistant"]) {
            return NO;
        }
    }
    return NO;
}

+ (NSString *)instructionBlockRequiringTools:(BOOL)require
                              forcedFunction:(NSString *)forcedName
                            afterToolResults:(BOOL)afterToolResults {
    // 尽量短：网页上下文昂贵；细则靠 tools schema + 最新任务。
    NSMutableString *s = [NSMutableString string];
    [s appendString:
     @"Coding agent. Output ONE JSON only (no markdown).\n"
     @"A:{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"N\",\"arguments\":{...}}]}\n"
     @"B:{\"mode\":\"message\",\"content\":\"Done.\"}\n"
     @"In JSON strings: escape \" as \\\", put real newlines as \\n (never raw line breaks). Prefer print('...').\n"
     @"Paths: project-relative (test/hello.py), never /Volumes/...\n"
     @"Example:{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"edit_file\",\"arguments\":{\"path\":\"test/hello.py\",\"edits\":[{\"old_text\":\"print('Hello, World!')\",\"new_text\":\"print('你好，世界！')\"}]}}]}\n"];
    if (require) {
        [s appendString:@"Must use mode=tool_calls.\n"];
    } else if (afterToolResults) {
        // 第二轮及以后：工具已跑完时优先收尾，避免再写一遍文件
        [s appendString:
         @"Tool results follow. If the task is already done: mode=message with ONE short plain sentence "
         @"(no markdown, no ```, no code dump). Only mode=tool_calls if another tool is still needed.\n"];
    } else {
        [s appendString:@"File/code tasks => mode=tool_calls (not prose).\n"];
    }
    if (forcedName.length) {
        [s appendFormat:@"Must call \"%@\".\n", forcedName];
    }
    return s;
}

+ (NSString *)instructionBlockRequiringTools:(BOOL)require
                              forcedFunction:(NSString *)forcedName {
    return [self instructionBlockRequiringTools:require
                                  forcedFunction:forcedName
                                afterToolResults:NO];
}

#pragma mark - Message filter / path rewrite

/// 去掉 IDE 附件套话，保留用户意图与 <files> 代码。
+ (NSString *)compactUserFacingContent:(NSString *)content {
    if (content.length == 0) {
        return @"";
    }
    NSMutableString *s = [content mutableCopy];
    NSArray *noise = @[
        @"The following items were attached by the user. They are up-to-date and don't need to be re-read.\n\n",
        @"The following items were attached by the user. They are up-to-date and don't need to be re-read.\n",
        @"<context>\n",
        @"</context>",
    ];
    for (NSString *n in noise) {
        [s replaceOccurrencesOfString:n withString:@"" options:0 range:NSMakeRange(0, s.length)];
    }
    // [@name](file:///abs) → @name — 绝对路径由 Bridge 改写，提示里省字符
    NSRegularExpression *link = [NSRegularExpression
        regularExpressionWithPattern:@"\\[@?([^\\]]+)\\]\\(file://[^\\)]+\\)"
                             options:0 error:nil];
    s = [[link stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length)
                                   withTemplate:@"@$1"] mutableCopy];
    return s;
}

/// 不用 IDE 长 system；只注入项目根名（路径规则够用）。
+ (NSDictionary *)syntheticSystemMessageWithRoots:(NSArray<NSString *> *)roots {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *r in roots) {
        NSString *n = r.lastPathComponent ?: r;
        if (n.length && ![names containsObject:n]) {
            [names addObject:n];
        }
    }
    NSString *rootsLine = names.count ? [names componentsJoinedByString:@", "] : @"project";
    NSString *example = names.count ? [NSString stringWithFormat:@"%@/file", names.firstObject] : @"root/file";
    NSString *content = [NSString stringWithFormat:
                         @"Project roots: %@. Paths like %@. Use listed tools.",
                         rootsLine, example];
    return @{@"role": @"system", @"content": content};
}

/// 丢掉 IDE 长 system / 散文 assistant；压缩 user；只留最近几轮 tool 轨迹。
+ (NSArray *)filterMessagesForAgent:(NSArray *)messages {
    return [self filterMessagesForAgent:messages roots:@[]];
}

+ (NSArray *)filterMessagesForAgent:(NSArray *)messages roots:(NSArray<NSString *> *)roots {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *body = [NSMutableArray array];
    for (id raw in messages) {
        if (![raw isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *c = [self compactMessage:(NSDictionary *)raw];
        NSString *role = c[@"role"] ?: @"";
        if ([role isEqualToString:@"system"]) {
            continue; // 用 syntheticSystemMessage 替代
        }
        if ([role isEqualToString:@"assistant"]) {
            id tcs = c[@"tool_calls"];
            BOOL hasTools = [tcs isKindOfClass:[NSArray class]] && [(NSArray *)tcs count] > 0;
            if (!hasTools) {
                continue;
            }
        }
        if ([role isEqualToString:@"user"] || [role isEqualToString:@"tool"]) {
            NSMutableDictionary *m = [c mutableCopy];
            if ([m[@"content"] isKindOfClass:[NSString class]]) {
                m[@"content"] = [self compactUserFacingContent:m[@"content"]];
            }
            // tool 结果过长时截断，优先留错误摘要
            NSString *tc = m[@"content"];
            if ([role isEqualToString:@"tool"] && tc.length > 4000) {
                m[@"content"] = [[tc substringToIndex:3000]
                    stringByAppendingFormat:@"\n…[tool result truncated %lu chars]…\n%@",
                    (unsigned long)(tc.length - 3500),
                    [tc substringFromIndex:tc.length - 500]];
            }
            [body addObject:m];
            continue;
        }
        [body addObject:c];
    }
    // 网页多轮贵：只留最近 4 条 body（通常够 1～2 轮 tool 往返）
    NSUInteger keep = 4;
    if (body.count > keep) {
        body = [[body subarrayWithRange:NSMakeRange(body.count - keep, keep)] mutableCopy];
    }
    [out addObject:[self syntheticSystemMessageWithRoots:roots]];
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

/// 修复字符串内的裸换行/制表符（DeepSeek 写 mode=message 时常见），转成 \\n / \\r / \\t。
+ (NSString *)repairControlCharsInJSONStrings:(NSString *)input {
    if (input.length == 0) {
        return input;
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:input.length + 32];
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
            inString = NO;
            [out appendFormat:@"%C", c];
            continue;
        }
        if (c == '\n') {
            [out appendString:@"\\n"];
            continue;
        }
        if (c == '\r') {
            [out appendString:@"\\r"];
            continue;
        }
        if (c == '\t') {
            [out appendString:@"\\t"];
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
    // 先修裸换行，再修未转义引号（第二轮 mode=message 常见）
    NSArray *candidates = @[
        [self repairControlCharsInJSONStrings:jsonStr],
        [self repairUnescapedQuotesInJSON:jsonStr],
        [self repairUnescapedQuotesInJSON:[self repairControlCharsInJSONStrings:jsonStr]],
        [self repairControlCharsInJSONStrings:[self repairUnescapedQuotesInJSON:jsonStr]],
    ];
    for (NSString *candidate in candidates) {
        if ([candidate isEqualToString:jsonStr]) {
            continue;
        }
        NSData *d2 = [candidate dataUsingEncoding:NSUTF8StringEncoding];
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

+ (NSArray *)prioritizeCodingTools:(NSArray *)rawTools {
    static NSArray *coreOrder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        coreOrder = @[
            @"edit_file", @"write_file", @"read_file", @"grep", @"find_path",
            @"list_directory", @"diagnostics", @"terminal", @"delete_path",
            @"create_directory", @"copy_path", @"move_path"
        ];
    });
    NSMutableArray *core = [NSMutableArray array];
    NSMutableArray *rest = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *want in coreOrder) {
        for (id t in rawTools) {
            if (![t isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *tool = (NSDictionary *)t;
            NSString *name = nil;
            if ([tool[@"function"] isKindOfClass:[NSDictionary class]]) {
                name = tool[@"function"][@"name"];
            } else {
                name = tool[@"name"];
            }
            if ([name isEqualToString:want] && ![seen containsObject:name]) {
                [core addObject:t];
                [seen addObject:name];
            }
        }
    }
    for (id t in rawTools) {
        if (![t isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *tool = (NSDictionary *)t;
        NSString *name = nil;
        if ([tool[@"function"] isKindOfClass:[NSDictionary class]]) {
            name = tool[@"function"][@"name"];
        } else {
            name = tool[@"name"];
        }
        if (name.length && ![seen containsObject:name]) {
            [rest addObject:t];
            [seen addObject:name];
        }
    }
    NSMutableArray *out = [NSMutableArray arrayWithArray:core];
    [out addObjectsFromArray:rest];
    return out;
}

/// 核心工具带精简 parameters；其余仅 name（大幅省字符）。
+ (NSArray *)hybridToolsForPrompt:(NSArray *)rawTools {
    NSArray *ordered = [self prioritizeCodingTools:rawTools];
    NSSet *fullSchema = [NSSet setWithArray:@[
        @"edit_file", @"write_file", @"read_file", @"grep", @"find_path",
        @"list_directory", @"diagnostics", @"terminal", @"delete_path",
        @"create_directory", @"copy_path", @"move_path"
    ]];
    NSMutableArray *out = [NSMutableArray array];
    for (id t in ordered) {
        if (![t isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *tool = (NSDictionary *)t;
        NSString *name = nil;
        NSDictionary *fnSrc = nil;
        if ([tool[@"function"] isKindOfClass:[NSDictionary class]]) {
            fnSrc = tool[@"function"];
            name = fnSrc[@"name"];
        } else if ([tool[@"name"] isKindOfClass:[NSString class]]) {
            fnSrc = tool;
            name = tool[@"name"];
        }
        if (!name.length) continue;
        if ([fullSchema containsObject:name]) {
            NSMutableDictionary *f = [NSMutableDictionary dictionary];
            f[@"name"] = name;
            if (fnSrc[@"parameters"]) {
                f[@"parameters"] = [self slimJSONSchema:fnSrc[@"parameters"] depth:0];
            }
            [out addObject:@{@"type": @"function", @"function": f}];
        } else {
            [out addObject:@{@"name": name}];
        }
    }
    return out;
}

+ (NSString *)fitToolsJSON:(NSArray *)tools rawTools:(NSArray *)rawTools maxChars:(NSUInteger)maxChars {
    if (maxChars < 32) {
        return @"[]";
    }
    (void)tools;
    NSArray *ordered = [self prioritizeCodingTools:rawTools];
    // 默认就不带 description；逐步降级
    NSArray *levels = @[
        [self hybridToolsForPrompt:ordered],
        [self compactToolsForPrompt:ordered includeDescriptions:NO includeParameters:YES],
        [self minimalToolNamesOnly:ordered]
    ];
    for (NSArray *level in levels) {
        NSString *s = [self jsonString:level pretty:NO];
        if (s.length <= maxChars) {
            return s;
        }
    }
    NSArray *namesOnly = [self minimalToolNamesOnly:ordered];
    NSMutableArray *kept = [NSMutableArray array];
    for (id item in namesOnly) {
        [kept addObject:item];
        NSString *s = [self jsonString:kept pretty:NO];
        if (s.length > maxChars) {
            [kept removeLastObject];
            break;
        }
    }
    return [self jsonString:kept.count ? kept : @[@{@"name": @"edit_file"}] pretty:NO];
}

+ (NSString *)buildWebpagePromptFromRequest:(NSDictionary *)json {
    BOOL require = [self requiresToolCallsForRequest:json];
    NSString *forced = [self forcedFunctionNameFromRequest:json];
    NSUInteger budget = [self maxPromptChars];

    id rawTools = json[@"tools"];
    NSArray *toolArr = [rawTools isKindOfClass:[NSArray class]] ? (NSArray *)rawTools : @[];
    id messages = json[@"messages"];
    NSArray *rawMsgs = [messages isKindOfClass:[NSArray class]] ? (NSArray *)messages : @[];

    // 先抽 roots，再合成极短 system（丢弃 IDE 长 system）
    NSArray<NSString *> *roots = [self projectRootsFromRequest:json];
    NSArray *msgArr = [self filterMessagesForAgent:rawMsgs roots:roots];
    BOOL afterTools = [self messagesEndWithToolResult:msgArr];
    NSString *instructions = [self instructionBlockRequiringTools:require
                                                   forcedFunction:forced
                                                 afterToolResults:afterTools];
    NSString *footer = afterTools
        ? @"\n\n## Reply\nONE JSON. If done: {\"mode\":\"message\",\"content\":\"...\"} with \\n escapes, no markdown.\n"
        : @"\n\n## Reply\nONE JSON now. Escape \\\". Relative paths only.\n";

    // tools 硬顶：给代码附件留额度（网页上下文紧）
    const NSUInteger kToolsHardCap = 3500;

    NSUInteger overhead = instructions.length + footer.length + 48;
    NSUInteger remaining = budget > overhead ? budget - overhead : budget / 2;
    NSUInteger toolsBudget = MIN(kToolsHardCap, MAX(256, remaining / 5));
    NSUInteger msgBudget = remaining > toolsBudget + 64 ? remaining - toolsBudget - 64 : remaining / 2;
    if (msgBudget < [self minMessagesBudget] && remaining > [self minMessagesBudget] + 512) {
        msgBudget = [self minMessagesBudget];
        toolsBudget = MIN(kToolsHardCap, remaining - msgBudget - 64);
    }

    NSArray *truncatedMsgs = [self truncateMessages:msgArr maxChars:msgBudget];
    NSString *messagesJSON = [self jsonString:truncatedMsgs pretty:NO];
    if (messagesJSON.length > msgBudget && truncatedMsgs.count > 0) {
        NSMutableArray *clipped = [truncatedMsgs mutableCopy];
        for (NSInteger i = (NSInteger)clipped.count - 1; i >= 0; i--) {
            NSMutableDictionary *m = [clipped[(NSUInteger)i] mutableCopy];
            NSString *c = [m[@"content"] isKindOfClass:[NSString class]] ? m[@"content"] : @"";
            if (c.length > 12000) {
                NSUInteger keepHead = 8000;
                NSUInteger keepTail = 3000;
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
        if (messagesJSON.length > msgBudget) {
            truncatedMsgs = [self truncateMessages:clipped maxChars:msgBudget];
            messagesJSON = [self jsonString:truncatedMsgs pretty:NO];
        }
    }

    NSString *toolsJSON = [self fitToolsJSON:nil rawTools:toolArr maxChars:toolsBudget];

    // Messages 在前（代码优先）；不重复粘贴 Latest task（已在 Messages 里）
    NSMutableString *prompt = [NSMutableString string];
    [prompt appendString:instructions];
    [prompt appendString:@"\n## Messages\n"];
    [prompt appendString:messagesJSON];
    [prompt appendString:@"\n\n## Tools\n"];
    [prompt appendString:toolsJSON];
    [prompt appendString:footer];

    if (prompt.length > budget) {
        NSString *marker = @"\n\n## Tools\n";
        NSRange r = [prompt rangeOfString:marker];
        if (r.location != NSNotFound) {
            NSUInteger keepPrefix = r.location + r.length;
            NSUInteger room = budget > keepPrefix + footer.length + 16
                ? budget - keepPrefix - footer.length - 16
                : 64;
            NSString *slimTools = [self fitToolsJSON:nil rawTools:toolArr maxChars:room];
            NSMutableString *rebuilt = [NSMutableString string];
            [rebuilt appendString:[prompt substringToIndex:keepPrefix]];
            [rebuilt appendString:slimTools];
            [rebuilt appendString:footer];
            if (rebuilt.length <= budget) {
                return rebuilt;
            }
            NSArray *names = [self allowedToolNamesFromRequest:json];
            rebuilt = [NSMutableString string];
            [rebuilt appendString:[prompt substringToIndex:keepPrefix]];
            [rebuilt appendString:[self jsonString:names pretty:NO]];
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
    id messages = json[@"messages"];
    NSArray *rawMsgs = [messages isKindOfClass:[NSArray class]] ? (NSArray *)messages : @[];
    BOOL afterTools = [self messagesEndWithToolResult:rawMsgs];
    NSString *prev = previousText ?: @"";
    BOOL prevLooksMessage =
        [prev rangeOfString:@"\"mode\":\"message\""].location != NSNotFound
        || [prev rangeOfString:@"\"mode\": \"message\""].location != NSNotFound;

    NSMutableString *prompt = [NSMutableString string];
    [prompt appendString:
     @"Your previous reply was NOT valid JSON "
     @"(often raw newlines inside strings, or \" not escaped as \\\"). "
     @"Reply again with ONLY one valid JSON object. No markdown.\n"
     @"上一轮 JSON 非法（常见：字符串里直接换行，或 \" 未写成 \\\"）。请只输出一个合法 JSON。\n\n"];
    if (prevLooksMessage && !require) {
        // 上一轮其实是在收尾，不要用 tool_calls 示例把模型带回写文件
        [prompt appendString:
         @"You were close: use mode=message. Put newlines as \\n. Example:\n"
         @"{\"mode\":\"message\",\"content\":\"Done. Updated test/hello.py.\"}\n"
         @"Do NOT call write_file/edit_file again unless a tool is still needed.\n\n"];
    } else {
        [prompt appendString:
         @"VALID tool_calls:\n"
         @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"edit_file\",\"arguments\":{\"path\":\"test/hello.py\",\"edits\":[{\"old_text\":\"print('Hello')\",\"new_text\":\"print('你好')\"}]}}]}\n"
         @"VALID message:\n"
         @"{\"mode\":\"message\",\"content\":\"Done.\"}\n\n"];
    }
    [prompt appendString:[self instructionBlockRequiringTools:require
                                                forcedFunction:forced
                                              afterToolResults:afterTools || prevLooksMessage]];
    NSArray *names = [self allowedToolNamesFromRequest:json];
    [prompt appendFormat:@"Allowed tool names: %@\n\n", [self jsonString:names pretty:NO]];
    // 收尾 repair：只给极短任务摘要，避免再贴整份文件诱发重复 write
    if (!(prevLooksMessage && afterTools && !require)) {
        for (NSInteger i = (NSInteger)rawMsgs.count - 1; i >= 0; i--) {
            id m = rawMsgs[(NSUInteger)i];
            if ([m isKindOfClass:[NSDictionary class]] && [m[@"role"] isEqualToString:@"user"]) {
                NSString *u = [self stringifyContent:m[@"content"]];
                if (u.length > 800) {
                    u = [[u substringToIndex:800] stringByAppendingString:@"…"];
                }
                [prompt appendFormat:@"Latest user task:\n%@\n\n", u];
                break;
            }
        }
    } else {
        [prompt appendString:@"Context: prior tool call already succeeded; finish with mode=message.\n\n"];
    }
    if (prev.length > 1200) {
        prev = [[prev substringToIndex:1200] stringByAppendingString:@"…"];
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
