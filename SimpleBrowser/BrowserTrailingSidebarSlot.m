#import "BrowserTrailingSidebarSlot.h"
#import "PhoneNotificationSidebarController.h"
#import "AssistSidebarController.h"
#import "BrowserHistorySidebarController.h"
#import "PagePackSidebarController.h"

@implementation BrowserTrailingSidebarSlot

- (BrowserTrailingSidebarKind)activeKind {
    if (self.notificationSidebar.visible) {
        return BrowserTrailingSidebarKindNotification;
    }
    if (self.assistSidebar.visible) {
        return BrowserTrailingSidebarKindAssist;
    }
    if (self.historySidebar.visible) {
        return BrowserTrailingSidebarKindHistory;
    }
    if (self.pagePackSidebar.visible) {
        return BrowserTrailingSidebarKindPagePack;
    }
    return BrowserTrailingSidebarKindNone;
}

- (void)hideOthersExcept:(BrowserTrailingSidebarKind)kind animated:(BOOL)animated {
    if (kind != BrowserTrailingSidebarKindNotification && self.notificationSidebar.visible) {
        [self.notificationSidebar setVisible:NO animated:animated];
    }
    if (kind != BrowserTrailingSidebarKindAssist && self.assistSidebar.visible) {
        [self.assistSidebar setVisible:NO animated:animated];
    }
    if (kind != BrowserTrailingSidebarKindHistory && self.historySidebar.visible) {
        [self.historySidebar setVisible:NO animated:animated];
    }
    if (kind != BrowserTrailingSidebarKindPagePack && self.pagePackSidebar.visible) {
        [self.pagePackSidebar setVisible:NO animated:animated];
    }
}

- (void)setNotificationVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) {
        [self hideOthersExcept:BrowserTrailingSidebarKindNotification animated:animated];
        [self.notificationSidebar setVisible:YES animated:animated];
    } else {
        [self.notificationSidebar setVisible:NO animated:animated];
    }
}

- (void)setAssistVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) {
        [self hideOthersExcept:BrowserTrailingSidebarKindAssist animated:animated];
        [self.assistSidebar setVisible:YES animated:animated];
    } else {
        [self.assistSidebar setVisible:NO animated:animated];
    }
}

- (void)setHistoryVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) {
        [self hideOthersExcept:BrowserTrailingSidebarKindHistory animated:animated];
        [self.historySidebar setVisible:YES animated:animated];
    } else {
        [self.historySidebar setVisible:NO animated:animated];
    }
}

- (void)setPagePackVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) {
        [self hideOthersExcept:BrowserTrailingSidebarKindPagePack animated:animated];
        [self.pagePackSidebar setVisible:YES animated:animated];
    } else {
        [self.pagePackSidebar setVisible:NO animated:animated];
    }
}

- (void)hideAllAnimated:(BOOL)animated {
    if (self.notificationSidebar.visible) {
        [self.notificationSidebar setVisible:NO animated:animated];
    }
    if (self.assistSidebar.visible) {
        [self.assistSidebar setVisible:NO animated:animated];
    }
    if (self.historySidebar.visible) {
        [self.historySidebar setVisible:NO animated:animated];
    }
    if (self.pagePackSidebar.visible) {
        [self.pagePackSidebar setVisible:NO animated:animated];
    }
}

@end
