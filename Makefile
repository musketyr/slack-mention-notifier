.PHONY: build run install uninstall clean

BINARY_NAME = SlackMentionNotifier
BUILD_DIR = .build/release
INSTALL_DIR = $(HOME)/.local/bin
LAUNCH_AGENT_DIR = $(HOME)/Library/LaunchAgents
PLIST_NAME = com.musketyr.slack-mention-notifier.plist

build:
	swift build -c release

run: build
	$(BUILD_DIR)/$(BINARY_NAME)

install: build
	@mkdir -p $(INSTALL_DIR)
	cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "✅ Installed to $(INSTALL_DIR)/$(BINARY_NAME)"
	@echo ""
	@echo "Run 'make autostart' to launch on login"

autostart: install
	@mkdir -p $(LAUNCH_AGENT_DIR)
	@sed 's|__BINARY__|$(INSTALL_DIR)/$(BINARY_NAME)|g' \
		scripts/launchagent.plist > $(LAUNCH_AGENT_DIR)/$(PLIST_NAME)
	launchctl unload $(LAUNCH_AGENT_DIR)/$(PLIST_NAME) 2>/dev/null || true
	launchctl load $(LAUNCH_AGENT_DIR)/$(PLIST_NAME)
	@echo "✅ Auto-start enabled. Running now."

stop:
	launchctl unload $(LAUNCH_AGENT_DIR)/$(PLIST_NAME) 2>/dev/null || true
	@echo "⏹  Stopped"

uninstall: stop
	rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	rm -f $(LAUNCH_AGENT_DIR)/$(PLIST_NAME)
	@echo "🗑  Uninstalled"

clean:
	swift package clean
	rm -rf .build
