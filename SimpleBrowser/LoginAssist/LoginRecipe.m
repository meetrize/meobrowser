#import "LoginRecipe.h"

LoginRecipeMode const LoginRecipeModePassword = @"password";
LoginRecipeMode const LoginRecipeModeSMSOTP = @"sms_otp";
LoginRecipeMode const LoginRecipeModeHybrid = @"hybrid";

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
    recipe.mode = LoginRecipeModePassword;
    recipe.autoLogin = NO;
    recipe.isDefault = NO;
    recipe.submitByEnter = YES;
    recipe.waitTimeoutMs = 8000;
    recipe.otpMaxWaitMs = 120000;
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
        _mode = LoginRecipeModePassword;
        _submitByEnter = YES;
        _waitTimeoutMs = 8000;
        _otpMaxWaitMs = 120000;
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
    copy.pathPrefix = self.pathPrefix;
    copy.mode = self.mode;
    copy.autoLogin = self.autoLogin;
    copy.isDefault = self.isDefault;
    copy.usernameSelector = self.usernameSelector;
    copy.passwordSelector = self.passwordSelector;
    copy.phoneSelector = self.phoneSelector;
    copy.otpSelector = self.otpSelector;
    copy.sendCodeSelector = self.sendCodeSelector;
    copy.submitSelector = self.submitSelector;
    copy.submitByEnter = self.submitByEnter;
    copy.successJSPredicate = self.successJSPredicate;
    copy.waitTimeoutMs = self.waitTimeoutMs;
    copy.otpMaxWaitMs = self.otpMaxWaitMs;
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

- (BOOL)requiresOTPWait {
    if (self.otpSelector.length == 0) {
        return NO;
    }
    return [self.mode isEqualToString:LoginRecipeModeSMSOTP] ||
           [self.mode isEqualToString:LoginRecipeModeHybrid];
}

- (BOOL)matchesURL:(NSURL *)url {
    if (!url || self.host.length == 0) {
        return NO;
    }
    if (url.isFileURL) {
        if (![self.host isEqualToString:@"file"] && ![self.host isEqualToString:@"localhost"]) {
            return NO;
        }
        if (self.pathPrefix.length > 0) {
            NSString *path = url.path ?: @"";
            if (![path containsString:self.pathPrefix] && ![path hasPrefix:self.pathPrefix]) {
                return NO;
            }
        }
        return YES;
    }

    NSString *host = url.host.lowercaseString;
    if (host.length == 0) {
        return NO;
    }
    if (![host isEqualToString:self.host]) {
        NSString *strippedHost = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
        NSString *strippedSelf = [self.host hasPrefix:@"www."] ? [self.host substringFromIndex:4] : self.host;
        if (![strippedHost isEqualToString:strippedSelf]) {
            return NO;
        }
    }
    if (self.pathPrefix.length > 0) {
        NSString *path = url.path.length > 0 ? url.path : @"/";
        if (![path hasPrefix:self.pathPrefix]) {
            return NO;
        }
    }
    return YES;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"id": self.recipeID ?: @"",
        @"title": self.title ?: @"",
        @"host": self.host ?: @"",
        @"mode": self.mode ?: LoginRecipeModePassword,
        @"autoLogin": @(self.autoLogin),
        @"isDefault": @(self.isDefault),
        @"submitByEnter": @(self.submitByEnter),
        @"waitTimeoutMs": @(self.waitTimeoutMs > 0 ? self.waitTimeoutMs : 8000),
        @"otpMaxWaitMs": @(self.otpMaxWaitMs > 0 ? self.otpMaxWaitMs : 120000),
        @"updatedAt": @(self.updatedAt),
    } mutableCopy];
    if (self.pathPrefix.length > 0) {
        dict[@"pathPrefix"] = self.pathPrefix;
    }
    if (self.usernameSelector.length > 0) {
        dict[@"usernameSelector"] = self.usernameSelector;
    }
    if (self.passwordSelector.length > 0) {
        dict[@"passwordSelector"] = self.passwordSelector;
    }
    if (self.phoneSelector.length > 0) {
        dict[@"phoneSelector"] = self.phoneSelector;
    }
    if (self.otpSelector.length > 0) {
        dict[@"otpSelector"] = self.otpSelector;
    }
    if (self.sendCodeSelector.length > 0) {
        dict[@"sendCodeSelector"] = self.sendCodeSelector;
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
    NSString *mode = dictionary[@"mode"];
    recipe.mode = [mode isKindOfClass:[NSString class]] && mode.length > 0 ? mode : LoginRecipeModePassword;
    recipe.autoLogin = [dictionary[@"autoLogin"] boolValue];
    recipe.isDefault = [dictionary[@"isDefault"] boolValue];
    if (dictionary[@"submitByEnter"] != nil) {
        recipe.submitByEnter = [dictionary[@"submitByEnter"] boolValue];
    }
    NSInteger timeout = [dictionary[@"waitTimeoutMs"] integerValue];
    recipe.waitTimeoutMs = timeout > 0 ? timeout : 8000;
    NSInteger otpWait = [dictionary[@"otpMaxWaitMs"] integerValue];
    recipe.otpMaxWaitMs = otpWait > 0 ? otpWait : 120000;
    recipe.updatedAt = [dictionary[@"updatedAt"] doubleValue];
    if (recipe.updatedAt <= 0) {
        recipe.updatedAt = [NSDate date].timeIntervalSince1970;
    }

    NSString *pathPrefix = dictionary[@"pathPrefix"];
    recipe.pathPrefix = [pathPrefix isKindOfClass:[NSString class]] ? pathPrefix : nil;
    NSString *userSel = dictionary[@"usernameSelector"];
    recipe.usernameSelector = [userSel isKindOfClass:[NSString class]] ? userSel : nil;
    NSString *passSel = dictionary[@"passwordSelector"];
    recipe.passwordSelector = [passSel isKindOfClass:[NSString class]] ? passSel : nil;
    NSString *phoneSel = dictionary[@"phoneSelector"];
    recipe.phoneSelector = [phoneSel isKindOfClass:[NSString class]] ? phoneSel : nil;
    NSString *otpSel = dictionary[@"otpSelector"];
    recipe.otpSelector = [otpSel isKindOfClass:[NSString class]] ? otpSel : nil;
    NSString *sendSel = dictionary[@"sendCodeSelector"];
    recipe.sendCodeSelector = [sendSel isKindOfClass:[NSString class]] ? sendSel : nil;
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
