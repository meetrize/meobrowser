#import "BrowserTrailingSidebarSlot.h"
#import "PhoneNotificationSidebarController.h"
#import "AssistSidebarController.h"

@implementation BrowserTrailingSidebarSlot

- (BrowserTrailingSidebarKind)activeKind {
    if (self.notificationSidebar.visible) {
        return BrowserTrailingSidebarKindNotification;
    }
    if (self.assistSidebar.visible) {
        return BrowserTrailingSidebarKindAssist;
    }
    return BrowserTrailingSidebarKindNone;
}

- (void)setNotificationVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) {
        if (self.assistSidebar.visible) {
            [self.assistSidebar setVisible:NO animated:animated];
        }
        [self.notificationSidebar setVisible:YES animated:animated];
    } else {
        [self.notificationSidebar setVisible:NO animated:animated];
    }
}

- (void)setAssistVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) {
        if (self.notificationSidebar.visible) {
            [self.notificationSidebar setVisible:NO animated:animated];
        }
        [self.assistSidebar setVisible:YES animated:animated];
    } else {
        [self.assistSidebar setVisible:NO animated:animated];
    }
}

- (void)hideAllAnimated:(BOOL)animated {
    if (self.notificationSidebar.visible) {
        [self.notificationSidebar setVisible:NO animated:animated];
    }
    if (self.assistSidebar.visible) {
        [self.assistSidebar setVisible:NO animated:animated];
    }
}

@end
