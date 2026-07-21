APP_NAME := SimpleWindow
BROWSER_DISPLAY_NAME := MeoBrowser
BROWSER_EXECUTABLE := MeoBrowser
BROWSER_BUNDLE_NAME := MeoBrowser
BUILD_DIR := build
SRC_DIR := SimpleWindow
BROWSER_SRC_DIR := SimpleBrowser
SBKIT_DIR := SBKit
RES_DIR := $(BUILD_DIR)/$(APP_NAME).app/Contents/Resources
BROWSER_RES_DIR := $(BUILD_DIR)/$(BROWSER_BUNDLE_NAME).app/Contents/Resources
BROWSER_ICON_SRC := $(BROWSER_SRC_DIR)/Resources/AppIcon.icns
BROWSER_ICON_NAME := AppIcon

SOURCES := $(SRC_DIR)/main.m $(SRC_DIR)/AppDelegate.m $(SRC_DIR)/MainWindowController.m
BROWSER_SOURCES := $(BROWSER_SRC_DIR)/main.m \
                   $(BROWSER_SRC_DIR)/AppDelegate.m \
                   $(BROWSER_SRC_DIR)/BrowserAppInfo.m \
                   $(BROWSER_SRC_DIR)/BrowserWindowController.m \
                   $(BROWSER_SRC_DIR)/BrowserLoadingProgressView.m \
                   $(BROWSER_SRC_DIR)/BrowsingPreferences.m \
                   $(BROWSER_SRC_DIR)/BrowserUserAgent.m \
                   $(BROWSER_SRC_DIR)/BrowserRiskHostPolicy.m \
                   $(BROWSER_SRC_DIR)/BrowserMenus.m \
                   $(BROWSER_SRC_DIR)/BrowserSettingsWindowController.m \
                   $(BROWSER_SRC_DIR)/BrowserTransientToast.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTab.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserWebView.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabController.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabStripView.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabItemView.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabDragGhostController.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabDropPlaceholderView.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutItem.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutStore.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutCellView.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutEditorSheet.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserLaunchpadView.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutFolderOverlay.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserLaunchpadAppearance.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserLaunchpadAppearancePanel.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserWallpaperStore.m \
                   $(BROWSER_SRC_DIR)/Favicon/BrowserFaviconUtil.m \
                   $(BROWSER_SRC_DIR)/Favicon/BrowserFaviconCache.m \
                   $(BROWSER_SRC_DIR)/Favicon/BrowserFaviconHTMLParser.m \
                   $(BROWSER_SRC_DIR)/Favicon/BrowserFaviconService.m \
                   $(BROWSER_SRC_DIR)/AddressBar/BrowserAddressBarAutocompleteController.m \
                   $(BROWSER_SRC_DIR)/AddressBar/BrowserAddressBarActionGroup.m \
                   $(BROWSER_SRC_DIR)/AddressBar/BrowserAddressBarRowView.m \
                   $(BROWSER_SRC_DIR)/AddressBar/BrowserShortcutSuggestionPanel.m \
                   $(BROWSER_SRC_DIR)/AddressBar/BrowserURLInputClassifier.m \
                   $(BROWSER_SRC_DIR)/Security/BrowserSSLExceptionStore.m \
                   $(BROWSER_SRC_DIR)/Security/BrowserCertificateWarningView.m \
                   $(BROWSER_SRC_DIR)/Security/BrowserHTTPAuthPrompt.m \
                   $(BROWSER_SRC_DIR)/Feed/BrowserFeedItem.m \
                   $(BROWSER_SRC_DIR)/Feed/BrowserFeedDetector.m \
                   $(BROWSER_SRC_DIR)/Feed/BrowserFeedReader.m \
                   $(BROWSER_SRC_DIR)/Feed/BrowserFeedURLSchemeHandler.m \
                   $(BROWSER_SRC_DIR)/Feed/BrowserFeedAssistController.m \
                   $(BROWSER_SRC_DIR)/Downloads/BrowserDownloadItem.m \
                   $(BROWSER_SRC_DIR)/Downloads/BrowserDownloadManager.m \
                   $(BROWSER_SRC_DIR)/Downloads/BrowserDownloadPanel.m \
                   $(BROWSER_SRC_DIR)/Downloads/BrowserDownloadProgressRingView.m \
                   $(BROWSER_SRC_DIR)/FindInPage/BrowserFindSession.m \
                   $(BROWSER_SRC_DIR)/FindInPage/BrowserFindEngine.m \
                   $(BROWSER_SRC_DIR)/FindInPage/BrowserFindBarView.m \
                   $(BROWSER_SRC_DIR)/FindInPage/BrowserFindBarController.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginRecipe.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginRecipeStore.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginCredentialStore.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginRunner.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/OTPInbox.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionPairingStore.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionBonjourServer.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionChannel.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionLinkUI.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/PhoneNotificationSettings.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/PhoneNotificationPresenter.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CallAlertSettings.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CallAlertPresenter.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CallAlertBannerController.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/PhoneRuleClassifier.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/PhonePolicyStore.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/PhonePolicyPanelController.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionSyncSettings.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionShortcutSync.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/Companion/CompanionBrowseSyncStore.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginAssistScriptMessageProxy.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginElementPicker.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginAssistController.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/BrowserLoginAssistSettingsWindowController.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginFormDetector.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/LoginAssistPreferences.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/SystemPasswordBridge.m \
                   $(BROWSER_SRC_DIR)/LoginAssist/SaveRecipePromptCoordinator.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaDetection.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaAssistPreferences.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaDetector.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaCaptureService.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaSessionLog.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaAssistPanel.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaAssistController.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaHelperBridge.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/MathCaptchaAdapter.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/OCRCaptchaAdapter.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaActor.m \
                   $(BROWSER_SRC_DIR)/CaptchaAssist/CaptchaPipeline.m \
                   $(SBKIT_DIR)/SBApplicationMenus.m \
                   $(SBKIT_DIR)/SBTextInputConfiguration.m \
                   $(SBKIT_DIR)/SBTextField.m \
                   $(SBKIT_DIR)/SBSecureTextField.m \
                   $(SBKIT_DIR)/SBTextView.m
XIB_SRC := $(SRC_DIR)/MainWindow.xib
NIB_OUT := $(RES_DIR)/MainWindow.nib
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
BROWSER_BUNDLE := $(BUILD_DIR)/$(BROWSER_BUNDLE_NAME).app
BROWSER_ENTITLEMENTS := $(BROWSER_SRC_DIR)/MeoBrowser.entitlements
BINARY := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
BROWSER_BINARY := $(BROWSER_BUNDLE)/Contents/MacOS/$(BROWSER_EXECUTABLE)

SDK_PATH := $(shell xcrun --show-sdk-path 2>/dev/null)
CC := clang
CFLAGS := -Wall -Wextra -O2 -fobjc-arc -I$(SRC_DIR)
BROWSER_CFLAGS := -Wall -Wextra -O2 -fobjc-arc -I$(BROWSER_SRC_DIR) -I$(BROWSER_SRC_DIR)/Tabs -I$(BROWSER_SRC_DIR)/NewTab -I$(BROWSER_SRC_DIR)/AddressBar -I$(BROWSER_SRC_DIR)/Downloads -I$(BROWSER_SRC_DIR)/FindInPage -I$(BROWSER_SRC_DIR)/Favicon -I$(BROWSER_SRC_DIR)/LoginAssist -I$(BROWSER_SRC_DIR)/LoginAssist/Companion -I$(BROWSER_SRC_DIR)/CaptchaAssist -I$(BROWSER_SRC_DIR)/Security -I$(BROWSER_SRC_DIR)/Feed -I$(SBKIT_DIR)
LDFLAGS := -framework Cocoa -framework Foundation
BROWSER_LDFLAGS := -framework Cocoa -framework Foundation -framework WebKit -framework QuartzCore -framework ImageIO -framework Security -framework AuthenticationServices -framework Network -framework UserNotifications

# Open-source ibtool (works without full Xcode); Apple ibtool preferred if available
IBTOOL_PY := tools/ibtool
IBTOOL_APP := $(shell xcrun --find ibtool 2>/dev/null || true)

define WRITE_INFO_PLIST
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(1)/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(1)/Contents/Info.plist
	@echo '<plist version="1.0"><dict>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleExecutable</key><string>$(2)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleIdentifier</key><string>com.example.$(2)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleName</key><string>$(2)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundlePackageType</key><string>APPL</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleShortVersionString</key><string>1.0</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>LSMinimumSystemVersion</key><string>11.0</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSHighResolutionCapable</key><true/>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSMainNibFile</key><string></string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSPrincipalClass</key><string>NSApplication</string>' >> $(1)/Contents/Info.plist
	@echo '</dict></plist>' >> $(1)/Contents/Info.plist
endef

define WRITE_BROWSER_INFO_PLIST
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(1)/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(1)/Contents/Info.plist
	@echo '<plist version="1.0"><dict>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleExecutable</key><string>$(2)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleIdentifier</key><string>com.example.MeoBrowser</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleName</key><string>$(3)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleDisplayName</key><string>$(3)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleIconFile</key><string>$(BROWSER_ICON_NAME)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundlePackageType</key><string>APPL</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleShortVersionString</key><string>1.0</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>LSMinimumSystemVersion</key><string>11.0</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSHighResolutionCapable</key><true/>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSMainNibFile</key><string></string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSPrincipalClass</key><string>NSApplication</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleURLTypes</key>' >> $(1)/Contents/Info.plist
	@echo '  <array>' >> $(1)/Contents/Info.plist
	@echo '    <dict>' >> $(1)/Contents/Info.plist
	@echo '      <key>CFBundleTypeRole</key><string>Viewer</string>' >> $(1)/Contents/Info.plist
	@echo '      <key>CFBundleURLName</key><string>Web site URL</string>' >> $(1)/Contents/Info.plist
	@echo '      <key>CFBundleURLSchemes</key>' >> $(1)/Contents/Info.plist
	@echo '      <array><string>http</string><string>https</string></array>' >> $(1)/Contents/Info.plist
	@echo '    </dict>' >> $(1)/Contents/Info.plist
	@echo '  </array>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSAppTransportSecurity</key>' >> $(1)/Contents/Info.plist
	@echo '  <dict>' >> $(1)/Contents/Info.plist
	@echo '    <key>NSAllowsArbitraryLoadsInWebContent</key><true/>' >> $(1)/Contents/Info.plist
	@echo '  </dict>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSLocalNetworkUsageDescription</key>' >> $(1)/Contents/Info.plist
	@echo '  <string>登录助手通过局域网与手机 Companion 配对，以自动填入短信验证码。</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSBonjourServices</key>' >> $(1)/Contents/Info.plist
	@echo '  <array><string>_meologin._tcp</string></array>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSCameraUsageDescription</key>' >> $(1)/Contents/Info.plist
	@echo '  <string>网页可请求使用摄像头进行视频通话或拍照。</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSMicrophoneUsageDescription</key>' >> $(1)/Contents/Info.plist
	@echo '  <string>网页可请求使用麦克风进行语音通话或录音。</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSLocationWhenInUseUsageDescription</key>' >> $(1)/Contents/Info.plist
	@echo '  <string>网页可请求在使用期间访问你的位置。</string>' >> $(1)/Contents/Info.plist
	@echo '</dict></plist>' >> $(1)/Contents/Info.plist
endef

.PHONY: all browser clean run run-browser stats stats-browser stats-all verify setup-tools

all: $(BINARY) $(NIB_OUT)

$(BINARY): $(SOURCES) | $(BUILD_DIR)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(CFLAGS) -isysroot $(SDK_PATH) $(SOURCES) $(LDFLAGS) -o $(BINARY)
	$(call WRITE_INFO_PLIST,$(APP_BUNDLE),$(APP_NAME))

browser: $(BROWSER_BINARY)

$(BROWSER_BINARY): $(BROWSER_SOURCES) $(BROWSER_ENTITLEMENTS) $(BROWSER_ICON_SRC) Makefile | $(BUILD_DIR)
	mkdir -p $(BROWSER_BUNDLE)/Contents/MacOS $(BROWSER_RES_DIR)
	$(CC) $(BROWSER_CFLAGS) -isysroot $(SDK_PATH) $(BROWSER_SOURCES) $(BROWSER_LDFLAGS) -o $(BROWSER_BINARY)
	$(call WRITE_BROWSER_INFO_PLIST,$(BROWSER_BUNDLE),$(BROWSER_EXECUTABLE),$(BROWSER_DISPLAY_NAME))
	cp "$(BROWSER_ICON_SRC)" "$(BROWSER_RES_DIR)/$(BROWSER_ICON_NAME).icns"
	cp "$(BROWSER_SRC_DIR)/LoginAssist/login-assist-test.html" "$(BROWSER_RES_DIR)/login-assist-test.html"
	cp "$(BROWSER_SRC_DIR)/CaptchaAssist/captcha-assist-test.html" "$(BROWSER_RES_DIR)/captcha-assist-test.html"
	cp "$(BROWSER_SRC_DIR)/FindInPage/Resources/find-in-page.js" "$(BROWSER_RES_DIR)/find-in-page.js"
	mkdir -p "$(BROWSER_RES_DIR)/PhoneRules"
	cp "$(BROWSER_SRC_DIR)/Resources/PhoneRules/simple_rules.json" "$(BROWSER_RES_DIR)/PhoneRules/simple_rules.json"
	mkdir -p "$(BROWSER_RES_DIR)/CaptchaAssist/helpers"
	cp "$(BROWSER_SRC_DIR)/CaptchaAssist/helpers/captcha_helper.py" "$(BROWSER_RES_DIR)/CaptchaAssist/helpers/captcha_helper.py"
	@if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		echo "Signing $(BROWSER_BUNDLE) with identity: $(CODESIGN_IDENTITY)"; \
		codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(BROWSER_ENTITLEMENTS)" --timestamp "$(BROWSER_BUNDLE)"; \
	else \
		echo "Ad-hoc signing $(BROWSER_BUNDLE) without restricted entitlements (local dev)"; \
		codesign --force --sign - "$(BROWSER_BUNDLE)"; \
	fi

$(NIB_OUT): $(XIB_SRC) | $(RES_DIR)
ifeq ($(IBTOOL_APP),)
	@echo "Compiling XIB with open-source ibtool..."
	PYTHONPATH=$(IBTOOL_PY) python3 -m ibtool --compile $(NIB_OUT) $(XIB_SRC)
else
	@echo "Compiling XIB with Apple ibtool..."
	$(IBTOOL_APP) --compile $(NIB_OUT) $(XIB_SRC) --sdk $(SDK_PATH)
endif

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(RES_DIR):
	mkdir -p $(RES_DIR)

setup-tools:
	@if [ ! -d tools/ibtool/.git ]; then \
		export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890; \
		git clone --depth 1 https://github.com/viraptor/ibtool.git tools/ibtool; \
	fi

run: all
	open $(APP_BUNDLE)

run-browser: browser
	open $(BROWSER_BUNDLE)

stats: all
	@echo "Launching $(APP_NAME) and sampling memory..."
	@open $(APP_BUNDLE)
	@sleep 2
	@PID=$$(pgrep -n $(APP_NAME) 2>/dev/null); \
	if [ -n "$$PID" ]; then \
		echo "PID: $$PID"; \
		ps -o pid,rss,vsz,cpu,comm -p $$PID; \
		echo ""; \
		echo "RSS = resident memory (KB). Lower is leaner."; \
	else \
		echo "Process not found."; \
	fi

stats-browser: browser
	@echo "Launching $(BROWSER_DISPLAY_NAME) and sampling memory..."
	@open $(BROWSER_BUNDLE)
	@sleep 3
	@PID=$$(pgrep -n $(BROWSER_EXECUTABLE) 2>/dev/null); \
	if [ -n "$$PID" ]; then \
		echo "PID: $$PID"; \
		ps -o pid,rss,vsz,cpu,comm -p $$PID; \
		echo ""; \
		echo "RSS = resident memory (KB). WebKit adds overhead vs SimpleWindow."; \
	else \
		echo "Process not found."; \
	fi

stats-all: stats stats-browser
	@echo ""
	@echo "Memory baseline recorded for both apps."

verify: all browser
	@test -x $(BINARY)
	@test -x $(BROWSER_BINARY)
	@test -f $(APP_BUNDLE)/Contents/Info.plist
	@test -f $(BROWSER_BUNDLE)/Contents/Info.plist
	@test -f $(BROWSER_RES_DIR)/$(BROWSER_ICON_NAME).icns
	@echo "verify OK: SimpleWindow + MeoBrowser binaries, Info.plist, AppIcon"

clean:
	rm -rf $(BUILD_DIR)
