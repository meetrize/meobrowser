#import "LoginRecipe.h"
#import "MeoSiteMatch.h"

@implementation LoginRecipeExtraField

+ (instancetype)fieldWithLabel:(NSString *)label selector:(NSString *)selector value:(NSString *)value {
    LoginRecipeExtraField *field = [[self alloc] init];
    field.label = label.length > 0 ? label : @"字段";
    field.selector = selector ?: @"";
    field.value = value ?: @"";
    return field;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fieldID = [[NSUUID UUID] UUIDString];
        _label = @"";
        _selector = @"";
        _value = @"";
        _enabled = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    LoginRecipeExtraField *copy = [[LoginRecipeExtraField alloc] init];
    copy.fieldID = self.fieldID;
    copy.label = self.label;
    copy.selector = self.selector;
    copy.value = self.value;
    copy.enabled = self.enabled;
    return copy;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"fieldID": self.fieldID ?: @"",
        @"label": self.label ?: @"",
        @"selector": self.selector ?: @"",
        @"value": self.value ?: @"",
        @"enabled": @(self.enabled),
    };
}

+ (instancetype)fieldWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *fieldID = dictionary[@"fieldID"];
    if (![fieldID isKindOfClass:[NSString class]] || fieldID.length == 0) {
        fieldID = [[NSUUID UUID] UUIDString];
    }
    LoginRecipeExtraField *field = [[self alloc] init];
    field.fieldID = fieldID;
    NSString *label = dictionary[@"label"];
    field.label = [label isKindOfClass:[NSString class]] ? label : @"";
    NSString *selector = dictionary[@"selector"];
    field.selector = [selector isKindOfClass:[NSString class]] ? selector : @"";
    NSString *value = dictionary[@"value"];
    field.value = [value isKindOfClass:[NSString class]] ? value : @"";
    if (dictionary[@"enabled"] != nil) {
        field.enabled = [dictionary[@"enabled"] boolValue];
    } else {
        field.enabled = YES;
    }
    return field;
}

@end

@implementation LoginRecipe

+ (instancetype)recipeWithHost:(NSString *)host title:(NSString *)title {
    LoginRecipe *recipe = [[self alloc] init];
    recipe.recipeID = [[NSUUID UUID] UUIDString];
    recipe.title = title.length > 0 ? title : host;
    recipe.host = host.lowercaseString ?: @"";
    recipe.autoLogin = NO;
    recipe.isDefault = NO;
    recipe.submitByEnter = YES;
    recipe.waitTimeoutMs = 8000;
    recipe.extraFields = @[];
    recipe.updatedAt = [NSDate date].timeIntervalSince1970;
    return recipe;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recipeID = [[NSUUID UUID] UUIDString];
        _title = @"";
        _host = @"";
        _submitByEnter = YES;
        _waitTimeoutMs = 8000;
        _extraFields = @[];
        _updatedAt = [NSDate date].timeIntervalSince1970;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    LoginRecipe *copy = [[LoginRecipe alloc] init];
    copy.recipeID = self.recipeID;
    copy.title = self.title;
    copy.host = self.host;
    copy.port = self.port;
    copy.pathPrefix = self.pathPrefix;
    copy.pathMatchMode = self.pathMatchMode;
    copy.autoLogin = self.autoLogin;
    copy.isDefault = self.isDefault;
    copy.usernameSelector = self.usernameSelector;
    copy.passwordSelector = self.passwordSelector;
    copy.submitSelector = self.submitSelector;
    copy.submitByEnter = self.submitByEnter;
    copy.successJSPredicate = self.successJSPredicate;
    copy.waitTimeoutMs = self.waitTimeoutMs;
    copy.updatedAt = self.updatedAt;
    NSMutableArray<LoginRecipeExtraField *> *fields = [NSMutableArray arrayWithCapacity:self.extraFields.count];
    for (LoginRecipeExtraField *field in self.extraFields) {
        [fields addObject:[field copy]];
    }
    copy.extraFields = fields;
    return copy;
}

- (NSArray<LoginRecipeExtraField *> *)enabledExtraFields {
    NSMutableArray<LoginRecipeExtraField *> *enabled = [NSMutableArray array];
    for (LoginRecipeExtraField *field in self.extraFields) {
        if (field.enabled && field.selector.length > 0) {
            [enabled addObject:field];
        }
    }
    return enabled;
}

- (BOOL)matchesURL:(NSURL *)url {
    return [MeoSiteMatch matchesURL:url
                               host:self.host
                               port:self.port
                        pathPattern:self.pathPrefix
                               mode:self.pathMatchMode];
}

- (NSInteger)matchSpecificityScore {
    return [MeoSiteMatch specificityScoreForHost:self.host
                                            port:self.port
                                     pathPattern:self.pathPrefix
                                            mode:self.pathMatchMode];
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"id": self.recipeID ?: @"",
        @"title": self.title ?: @"",
        @"host": self.host ?: @"",
        // 兼容旧客户端：始终写 password。
        @"mode": @"password",
        @"autoLogin": @(self.autoLogin),
        @"isDefault": @(self.isDefault),
        @"submitByEnter": @(self.submitByEnter),
        @"waitTimeoutMs": @(self.waitTimeoutMs > 0 ? self.waitTimeoutMs : 8000),
        @"updatedAt": @(self.updatedAt),
    } mutableCopy];
    if (self.port != nil) {
        dict[@"port"] = self.port;
    }
    if (self.pathPrefix.length > 0) {
        dict[@"pathPrefix"] = self.pathPrefix;
    }
    MeoSitePathMatchMode mode =
        self.pathMatchMode.length > 0
            ? self.pathMatchMode
            : [MeoSiteMatch inferredPathMatchModeForPattern:self.pathPrefix];
    if (self.pathPrefix.length > 0 && ![mode isEqualToString:MeoSitePathMatchModePrefix]) {
        dict[@"pathMatchMode"] = mode;
    } else if (self.pathMatchMode.length > 0) {
        dict[@"pathMatchMode"] = self.pathMatchMode;
    }
    if (self.usernameSelector.length > 0) {
        dict[@"usernameSelector"] = self.usernameSelector;
    }
    if (self.passwordSelector.length > 0) {
        dict[@"passwordSelector"] = self.passwordSelector;
    }
    if (self.submitSelector.length > 0) {
        dict[@"submitSelector"] = self.submitSelector;
    }
    if (self.successJSPredicate.length > 0) {
        dict[@"successJSPredicate"] = self.successJSPredicate;
    }
    if (self.extraFields.count > 0) {
        NSMutableArray *encoded = [NSMutableArray arrayWithCapacity:self.extraFields.count];
        for (LoginRecipeExtraField *field in self.extraFields) {
            [encoded addObject:[field dictionaryRepresentation]];
        }
        dict[@"extraFields"] = encoded;
    }
    return dict;
}

+ (instancetype)recipeWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *recipeID = dictionary[@"id"];
    NSString *host = dictionary[@"host"];
    if (![recipeID isKindOfClass:[NSString class]] || recipeID.length == 0) {
        return nil;
    }
    if (![host isKindOfClass:[NSString class]] || host.length == 0) {
        return nil;
    }

    LoginRecipe *recipe = [[self alloc] init];
    recipe.recipeID = recipeID;
    recipe.host = host.lowercaseString;
    NSString *title = dictionary[@"title"];
    recipe.title = [title isKindOfClass:[NSString class]] && title.length > 0 ? title : host;
    recipe.autoLogin = [dictionary[@"autoLogin"] boolValue];
    recipe.isDefault = [dictionary[@"isDefault"] boolValue];
    if (dictionary[@"submitByEnter"] != nil) {
        recipe.submitByEnter = [dictionary[@"submitByEnter"] boolValue];
    }
    NSInteger timeout = [dictionary[@"waitTimeoutMs"] integerValue];
    recipe.waitTimeoutMs = timeout > 0 ? timeout : 8000;
    recipe.updatedAt = [dictionary[@"updatedAt"] doubleValue];
    if (recipe.updatedAt <= 0) {
        recipe.updatedAt = [NSDate date].timeIntervalSince1970;
    }

    NSString *pathPrefix = dictionary[@"pathPrefix"];
    recipe.pathPrefix = [pathPrefix isKindOfClass:[NSString class]] ? pathPrefix : nil;
    id portValue = dictionary[@"port"];
    if ([portValue isKindOfClass:[NSNumber class]]) {
        recipe.port = (NSNumber *)portValue;
    } else {
        recipe.port = nil;
    }
    NSString *pathMode = dictionary[@"pathMatchMode"];
    recipe.pathMatchMode = [pathMode isKindOfClass:[NSString class]] ? pathMode : nil;
    NSString *userSel = dictionary[@"usernameSelector"];
    recipe.usernameSelector = [userSel isKindOfClass:[NSString class]] ? userSel : nil;
    NSString *passSel = dictionary[@"passwordSelector"];
    recipe.passwordSelector = [passSel isKindOfClass:[NSString class]] ? passSel : nil;
    NSString *submitSel = dictionary[@"submitSelector"];
    recipe.submitSelector = [submitSel isKindOfClass:[NSString class]] ? submitSel : nil;
    NSString *predicate = dictionary[@"successJSPredicate"];
    recipe.successJSPredicate = [predicate isKindOfClass:[NSString class]] ? predicate : nil;

    NSArray *rawFields = dictionary[@"extraFields"];
    NSMutableArray<LoginRecipeExtraField *> *fields = [NSMutableArray array];
    if ([rawFields isKindOfClass:[NSArray class]]) {
        for (id item in rawFields) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            LoginRecipeExtraField *field = [LoginRecipeExtraField fieldWithDictionary:item];
            if (field) {
                [fields addObject:field];
            }
        }
    }
    recipe.extraFields = fields;
    return recipe;
}

@end
