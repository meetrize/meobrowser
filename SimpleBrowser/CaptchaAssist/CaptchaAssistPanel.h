#import <Cocoa/Cocoa.h>

@class CaptchaDetection;
@class CaptchaAssistPanel;

NS_ASSUME_NONNULL_BEGIN

@protocol CaptchaAssistPanelDelegate <NSObject>
- (void)captchaAssistPanelDidRequestClose:(CaptchaAssistPanel *)panel;
- (void)captchaAssistPanelDidRequestCapture:(CaptchaAssistPanel *)panel;
- (void)captchaAssistPanelDidRequestClear:(CaptchaAssistPanel *)panel;
- (void)captchaAssistPanelDidRequestToggleEnabled:(CaptchaAssistPanel *)panel enabled:(BOOL)enabled;
- (void)captchaAssistPanelDidRequestRevealSessions:(CaptchaAssistPanel *)panel;
- (void)captchaAssistPanelDidRequestSolve:(CaptchaAssistPanel *)panel;
@end

@interface CaptchaAssistPanel : NSPanel

@property (nonatomic, weak, nullable) id<CaptchaAssistPanelDelegate> panelDelegate;
@property (nonatomic, assign) NSRect dismissExclusionRectOnScreen;

- (void)presentAnchoredToRect:(NSRect)anchorRectOnScreen ofWindow:(nullable NSWindow *)ownerWindow;
- (void)dismissPanel;

- (void)updateWithDetections:(NSArray<CaptchaDetection *> *)detections
                   previewImage:(nullable NSImage *)image
                      enabled:(BOOL)enabled
                       status:(nullable NSString *)status
                      solving:(BOOL)solving
                 solveEnabled:(BOOL)solveEnabled;

@end

NS_ASSUME_NONNULL_END
