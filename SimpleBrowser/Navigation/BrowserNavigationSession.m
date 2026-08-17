#import "BrowserNavigationSession.h"

@interface BrowserNavigationSession ()
@property (nonatomic, assign, readwrite) NSInteger generation;
@property (nonatomic, copy, readwrite, nullable) NSUUID *tabID;
@property (nonatomic, copy, readwrite, nullable) NSURL *URL;
@property (nonatomic, assign, readwrite) NSTimeInterval startTime;
@end

@implementation BrowserNavigationSession

+ (instancetype)sessionWithGeneration:(NSInteger)generation
                                tabID:(NSUUID *)tabID
                                  URL:(NSURL *)URL {
    BrowserNavigationSession *session = [[self alloc] init];
    session.generation = generation;
    session.tabID = tabID;
    session.URL = URL;
    session.phase = BrowserNavigationSessionPhaseLoading;
    session.startTime = [NSDate date].timeIntervalSince1970;
    return session;
}

@end
