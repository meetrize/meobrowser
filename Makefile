APP_NAME := SimpleWindow
BROWSER_NAME := SimpleBrowser
BUILD_DIR := build
SRC_DIR := SimpleWindow
BROWSER_SRC_DIR := SimpleBrowser
SBKIT_DIR := SBKit
RES_DIR := $(BUILD_DIR)/$(APP_NAME).app/Contents/Resources

SOURCES := $(SRC_DIR)/main.m $(SRC_DIR)/AppDelegate.m $(SRC_DIR)/MainWindowController.m
BROWSER_SOURCES := $(BROWSER_SRC_DIR)/main.m \
                   $(BROWSER_SRC_DIR)/AppDelegate.m \
                   $(BROWSER_SRC_DIR)/BrowserWindowController.m \
                   $(BROWSER_SRC_DIR)/BrowsingPreferences.m \
                   $(BROWSER_SRC_DIR)/BrowserMenus.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTab.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabController.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabStripView.m \
                   $(BROWSER_SRC_DIR)/Tabs/BrowserTabItemView.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutItem.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutStore.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutCellView.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserShortcutEditorSheet.m \
                   $(BROWSER_SRC_DIR)/NewTab/BrowserLaunchpadView.m \
                   $(SBKIT_DIR)/SBApplicationMenus.m \
                   $(SBKIT_DIR)/SBTextInputConfiguration.m \
                   $(SBKIT_DIR)/SBTextField.m \
                   $(SBKIT_DIR)/SBSecureTextField.m \
                   $(SBKIT_DIR)/SBTextView.m
XIB_SRC := $(SRC_DIR)/MainWindow.xib
NIB_OUT := $(RES_DIR)/MainWindow.nib
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
BROWSER_BUNDLE := $(BUILD_DIR)/$(BROWSER_NAME).app
BINARY := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
BROWSER_BINARY := $(BROWSER_BUNDLE)/Contents/MacOS/$(BROWSER_NAME)

SDK_PATH := $(shell xcrun --show-sdk-path 2>/dev/null)
CC := clang
CFLAGS := -Wall -Wextra -O2 -fobjc-arc -I$(SRC_DIR)
BROWSER_CFLAGS := -Wall -Wextra -O2 -fobjc-arc -I$(BROWSER_SRC_DIR) -I$(BROWSER_SRC_DIR)/Tabs -I$(BROWSER_SRC_DIR)/NewTab -I$(SBKIT_DIR)
LDFLAGS := -framework Cocoa -framework Foundation
BROWSER_LDFLAGS := -framework Cocoa -framework Foundation -framework WebKit -framework QuartzCore

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
	@echo '  <key>CFBundleIdentifier</key><string>com.example.$(2)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleName</key><string>$(2)</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundlePackageType</key><string>APPL</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>CFBundleShortVersionString</key><string>1.0</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>LSMinimumSystemVersion</key><string>11.0</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSHighResolutionCapable</key><true/>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSMainNibFile</key><string></string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSPrincipalClass</key><string>NSApplication</string>' >> $(1)/Contents/Info.plist
	@echo '  <key>NSAppTransportSecurity</key>' >> $(1)/Contents/Info.plist
	@echo '  <dict>' >> $(1)/Contents/Info.plist
	@echo '    <key>NSAllowsArbitraryLoadsInWebContent</key><true/>' >> $(1)/Contents/Info.plist
	@echo '  </dict>' >> $(1)/Contents/Info.plist
	@echo '</dict></plist>' >> $(1)/Contents/Info.plist
endef

.PHONY: all browser clean run run-browser stats stats-browser stats-all verify setup-tools

all: $(BINARY) $(NIB_OUT)

$(BINARY): $(SOURCES) | $(BUILD_DIR)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(CFLAGS) -isysroot $(SDK_PATH) $(SOURCES) $(LDFLAGS) -o $(BINARY)
	$(call WRITE_INFO_PLIST,$(APP_BUNDLE),$(APP_NAME))

browser: $(BROWSER_BINARY)

$(BROWSER_BINARY): $(BROWSER_SOURCES) Makefile | $(BUILD_DIR)
	mkdir -p $(BROWSER_BUNDLE)/Contents/MacOS
	$(CC) $(BROWSER_CFLAGS) -isysroot $(SDK_PATH) $(BROWSER_SOURCES) $(BROWSER_LDFLAGS) -o $(BROWSER_BINARY)
	$(call WRITE_BROWSER_INFO_PLIST,$(BROWSER_BUNDLE),$(BROWSER_NAME))

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
	@echo "Launching $(BROWSER_NAME) and sampling memory..."
	@open $(BROWSER_BUNDLE)
	@sleep 3
	@PID=$$(pgrep -n $(BROWSER_NAME) 2>/dev/null); \
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
	@echo "verify OK: SimpleWindow + SimpleBrowser binaries and Info.plist"

clean:
	rm -rf $(BUILD_DIR)
