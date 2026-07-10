#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserShortcutItem : NSObject

@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, assign) NSInteger sortOrder;

+ (instancetype)itemWithTitle:(NSString *)title
                    urlString:(NSString *)urlString
                    sortOrder:(NSInteger)sortOrder;

@end

NS_ASSUME_NONNULL_END
