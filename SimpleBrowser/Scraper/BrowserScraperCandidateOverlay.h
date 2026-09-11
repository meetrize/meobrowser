#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 智能检测候选数据区的页内标注（边框 + 序号），与 ElementPicker 生命周期分离。
@interface BrowserScraperCandidateOverlay : NSObject

/// candidates 项需含 containerPath；可选 recommended / type / score / estimatedRows / title。
/// selectedIndex / adoptedIndex：0-based，&lt;0 表示无。
/// completion 返回未能 querySelector 命中的候选下标（主线程回调）。
+ (void)showCandidates:(NSArray<NSDictionary *> *)candidates
             inWebView:(nullable WKWebView *)webView
         selectedIndex:(NSInteger)selectedIndex
          adoptedIndex:(NSInteger)adoptedIndex
          onlySelected:(BOOL)onlySelected
            completion:(void (^ _Nullable)(NSArray<NSNumber *> *missingIndexes))completion;

+ (void)setSelectedIndex:(NSInteger)selectedIndex inWebView:(nullable WKWebView *)webView;
+ (void)setAdoptedIndex:(NSInteger)adoptedIndex inWebView:(nullable WKWebView *)webView;
+ (void)setOnlySelected:(BOOL)onlySelected inWebView:(nullable WKWebView *)webView;
+ (void)setVisible:(BOOL)visible inWebView:(nullable WKWebView *)webView;
+ (void)clearInWebView:(nullable WKWebView *)webView;

/// MessageHub 转发：selectCandidate / clearCandidateOverlay。
+ (BOOL)isSelectCandidateMessage:(id)body;
+ (NSInteger)indexFromSelectCandidateMessage:(id)body;

@end

NS_ASSUME_NONNULL_END
