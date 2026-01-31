.PHONY: build run install uninstall clean bundle

VERSION ?= 0.1.0
BINARY_NAME = SlackMentionNotifier
BUILD_DIR = .build/release
INSTALL_DIR = $(HOME)/.local/bin
LAUNCH_AGENT_DIR = $(HOME)/Library/LaunchAgents
PLIST_NAME = cz.orany.smn.plist

build: inject-secrets
	swift build -c release

run: build
	$(BUILD_DIR)/$(BINARY_NAME)

# Inject secrets from environment for local dev (CI does this in the workflow)
inject-secrets:
	@if [ -n "$$SLACK_APP_TOKEN" ] && [ -n "$$SLACK_CLIENT_ID" ] && [ -n "$$SLACK_CLIENT_SECRET" ]; then \
		echo "🔐 Injecting secrets from environment..."; \
		printf 'enum Secrets {\n    static let slackAppToken = "%s"\n    static let slackClientId = "%s"\n    static let slackClientSecret = "%s"\n}\n' \
			"$$SLACK_APP_TOKEN" "$$SLACK_CLIENT_ID" "$$SLACK_CLIENT_SECRET" \
			> Sources/SlackMentionNotifier/Secrets.swift; \
	elif [ -f .env.local ]; then \
		echo "🔐 Injecting secrets from .env.local..."; \
		. ./.env.local && \
		printf 'enum Secrets {\n    static let slackAppToken = "%s"\n    static let slackClientId = "%s"\n    static let slackClientSecret = "%s"\n}\n' \
			"$$SLACK_APP_TOKEN" "$$SLACK_CLIENT_ID" "$$SLACK_CLIENT_SECRET" \
			> Sources/SlackMentionNotifier/Secrets.swift; \
	else \
		echo "ℹ️  No secrets found (set env vars or create .env.local). Using empty Secrets.swift."; \
	fi

bundle:
	./scripts/bundle-app.sh $(VERSION)

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
	rm -rf .build dist
