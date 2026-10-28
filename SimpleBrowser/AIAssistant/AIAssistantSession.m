#import "AIAssistantSession.h"

@implementation AIAssistantMessage

+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content {
    AIAssistantMessage *m = [[AIAssistantMessage alloc] init];
    m.role = role ?: @"user";
    m.content = content ?: @"";
    m.createdAt = [NSDate date].timeIntervalSince1970;
    return m;
}

+ (instancetype)messageFromDictionary:(NSDictionary *)dict {
    AIAssistantMessage *m = [[AIAssistantMessage alloc] init];
    m.role = [dict[@"role"] isKindOfClass:[NSString class]] ? dict[@"role"] : @"user";
    m.content = [dict[@"content"] isKindOfClass:[NSString class]] ? dict[@"content"] : @"";
    m.displayContent = [dict[@"displayContent"] isKindOfClass:[NSString class]] ? dict[@"displayContent"] : nil;
    NSArray *imgs = dict[@"imageDataURLs"];
    if ([imgs isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *safe = [NSMutableArray array];
        for (id item in imgs) {
            if ([item isKindOfClass:[NSString class]] && [(NSString *)item hasPrefix:@"data:image"]) {
                [safe addObject:item];
            }
        }
        if (safe.count) m.imageDataURLs = safe;
    }
    m.createdAt = [dict[@"createdAt"] doubleValue];
    if (m.createdAt <= 0) {
        m.createdAt = [NSDate date].timeIntervalSince1970;
    }
    return m;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [@{
        @"role": self.role ?: @"user",
        @"content": self.content ?: @"",
        @"createdAt": @(self.createdAt),
    } mutableCopy];
    if (self.displayContent.length) d[@"displayContent"] = self.displayContent;
    if (self.imageDataURLs.count) d[@"imageDataURLs"] = self.imageDataURLs;
    return d;
}

@end

@implementation AIAssistantSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _messages = [NSMutableArray array];
        _connection = AIAssistantSessionConnectionReady;
        _title = @"新对话";
    }
    return self;
}

+ (instancetype)sessionFromDictionary:(NSDictionary *)dict {
    AIAssistantSession *s = [[AIAssistantSession alloc] init];
    s.sessionId = [dict[@"sessionId"] isKindOfClass:[NSString class]] ? dict[@"sessionId"] : [[NSUUID UUID] UUIDString];
    s.title = [dict[@"title"] isKindOfClass:[NSString class]] ? dict[@"title"] : @"新对话";
    s.providerId = [dict[@"providerId"] isKindOfClass:[NSString class]] ? dict[@"providerId"] : @"deepseek";
    s.bindingId = [dict[@"bindingId"] isKindOfClass:[NSString class]] ? dict[@"bindingId"] : nil;
    s.modelId = [dict[@"modelId"] isKindOfClass:[NSString class]] ? dict[@"modelId"] : nil;
    s.createdAt = [dict[@"createdAt"] doubleValue];
    s.updatedAt = [dict[@"updatedAt"] doubleValue];
    s.pinned = [dict[@"pinned"] boolValue];
    s.connection = AIAssistantSessionConnectionDetached; // 重启后需重连/检测
    NSArray *msgs = dict[@"messages"];
    if ([msgs isKindOfClass:[NSArray class]]) {
        for (id item in msgs) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                [s.messages addObject:[AIAssistantMessage messageFromDictionary:item]];
            }
        }
    }
    return s;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *msgs = [NSMutableArray arrayWithCapacity:self.messages.count];
    for (AIAssistantMessage *m in self.messages) {
        [msgs addObject:[m dictionaryRepresentation]];
    }
    NSMutableDictionary *d = [@{
        @"sessionId": self.sessionId ?: @"",
        @"title": self.title ?: @"新对话",
        @"providerId": self.providerId ?: @"",
        @"createdAt": @(self.createdAt),
        @"updatedAt": @(self.updatedAt),
        @"pinned": @(self.pinned),
        @"messages": msgs,
    } mutableCopy];
    if (self.bindingId.length) d[@"bindingId"] = self.bindingId;
    if (self.modelId.length) d[@"modelId"] = self.modelId;
    return d;
}

- (NSString *)previewText {
    for (NSInteger i = (NSInteger)self.messages.count - 1; i >= 0; i--) {
        AIAssistantMessage *m = self.messages[(NSUInteger)i];
        if (![m.role isEqualToString:@"user"]) continue;
        NSString *src = m.displayContent.length ? m.displayContent : m.content;
        if (src.length == 0 && m.imageDataURLs.count) return @"📎 图片引用";
        if (src.length == 0) continue;
        NSString *t = [src stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (t.length > 48) {
            return [[t substringToIndex:48] stringByAppendingString:@"…"];
        }
        return t;
    }
    return @"（空会话）";
}

@end
