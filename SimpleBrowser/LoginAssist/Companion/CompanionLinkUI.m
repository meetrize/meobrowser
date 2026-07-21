#import "CompanionLinkUI.h"

@implementation CompanionLinkUI

+ (CompanionLinkUIState)stateFromChannel:(CompanionChannel *)channel {
    if (!channel) {
        return CompanionLinkUIStateDisconnected;
    }
    switch (channel.state) {
        case CompanionChannelStateConnected:
            return CompanionLinkUIStateConnected;
        case CompanionChannelStateAdvertising:
            return CompanionLinkUIStateWaiting;
        case CompanionChannelStateStopped:
        default:
            return CompanionLinkUIStateDisconnected;
    }
}

+ (NSString *)titleForState:(CompanionLinkUIState)state {
    switch (state) {
        case CompanionLinkUIStateConnected:
            return @"已连接到手机";
        case CompanionLinkUIStateWaiting:
            return @"等待手机连接…";
        case CompanionLinkUIStateDisconnected:
        default:
            return @"未连接";
    }
}

+ (NSColor *)dotColorForState:(CompanionLinkUIState)state {
    if (@available(macOS 10.14, *)) {
        switch (state) {
            case CompanionLinkUIStateConnected:
                return [NSColor systemGreenColor];
            case CompanionLinkUIStateWaiting:
                return [NSColor systemOrangeColor];
            case CompanionLinkUIStateDisconnected:
            default:
                return [NSColor tertiaryLabelColor];
        }
    }
    switch (state) {
        case CompanionLinkUIStateConnected:
            return [NSColor colorWithCalibratedRed:0.20 green:0.78 blue:0.35 alpha:1.0];
        case CompanionLinkUIStateWaiting:
            return [NSColor colorWithCalibratedRed:1.0 green:0.62 blue:0.04 alpha:1.0];
        case CompanionLinkUIStateDisconnected:
        default:
            return [NSColor colorWithCalibratedWhite:0.56 alpha:1.0];
    }
}

+ (NSColor *)iconBackgroundColorForState:(CompanionLinkUIState)state {
    NSColor *dot = [self dotColorForState:state];
    return [dot colorWithAlphaComponent:0.14];
}

@end
