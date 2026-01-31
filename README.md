# Slack Mention Notifier

A lightweight macOS menu bar app that monitors Slack mentions via **Socket Mode** (WebSocket) and:

- 👀 Reacts to the message
- 📱 Sends a Telegram notification
- ✅ Creates an Apple Reminder
- 🔔 Shows a macOS notification

**Zero server infrastructure.** Runs entirely on your Mac — connects directly to Slack via WebSocket.

## Prerequisites

1. **macOS 13+** with Xcode Command Line Tools
2. A **Slack App** with Socket Mode enabled:
   - Go to [api.slack.com/apps](https://api.slack.com/apps)
   - Create a new app (or use existing)
   - **Socket Mode**: Enable it, generate an App-Level Token (`xapp-...`) with `connections:write` scope
   - **Event Subscriptions**: Enable, subscribe to `message.channels` and `message.groups`
   - **Bot Token Scopes**: `reactions:write`, `channels:history`, `groups:history`, `users:read`, `channels:read`, `groups:read`, `chat:write`
   - Install the app to your workspace
   - Copy the Bot Token (`xoxb-...`)

## Setup

### 1. Create config file

```bash
cat > ~/.slack-mention-notifier.env << 'EOF'
SLACK_APP_TOKEN=xapp-1-...          # Socket Mode app-level token
SLACK_BOT_TOKEN=xoxb-...            # Bot token
SLACK_TRACKED_USER_ID=U...          # Your Slack user ID

# Optional: Telegram notifications
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...

# Optional: Target Apple Reminders list (default: "Reminders")
APPLE_REMINDERS_LIST=Připomínky
EOF
```

### 2. Build and run

```bash
# Clone
git clone https://github.com/musketyr/slack-mention-notifier.git
cd slack-mention-notifier

# Build
make build

# Run (foreground, for testing)
make run
```

On first run, macOS will prompt for **Reminders access** — click OK.

### 3. Install as auto-start service

```bash
make autostart
```

This installs the binary to `~/.local/bin/` and creates a LaunchAgent that starts on login and restarts if it crashes.

## Usage

Once running, you'll see a 🔔 bell icon in the menu bar. That's it — mentions are handled automatically.

### Commands

| Command | Description |
|---------|-------------|
| `make build` | Build release binary |
| `make run` | Build and run in foreground |
| `make install` | Install binary to ~/.local/bin |
| `make autostart` | Install + enable auto-start on login |
| `make stop` | Stop the service |
| `make uninstall` | Remove binary + auto-start |

### Logs

```bash
tail -f /tmp/slack-mention-notifier.log
```

### Open in Xcode

```bash
open Package.swift
```

## Architecture

```
Slack (WebSocket) ──Socket Mode──▶ SlackSocketMode
                                        │
                                        ▼
                                  MentionHandler
                                   │   │   │
                          ┌────────┘   │   └────────┐
                          ▼            ▼             ▼
                     SlackAPI    TelegramNotifier  ReminderService
                   (react 👀)   (send message)    (EventKit VTODO)
                                                       │
                                                       ▼
                                                 Apple Reminders
```

## Slack App Setup Details

### Socket Mode

Socket Mode lets the app receive events via WebSocket instead of requiring a public HTTP endpoint. No server, no ngrok, no tunnel.

1. Go to your Slack App → **Socket Mode** → Enable
2. Generate an **App-Level Token** with `connections:write` scope
3. This gives you the `xapp-...` token

### Event Subscriptions

Subscribe to these bot events:
- `message.channels` — messages in public channels
- `message.groups` — messages in private channels
- `message.im` — direct messages (optional)
- `message.mpim` — group DMs (optional)

### Required Bot Token Scopes

- `reactions:write` — react to messages
- `channels:history` — read public channel messages
- `groups:history` — read private channel messages
- `users:read` — get user display names
- `channels:read` — get channel names
- `groups:read` — get private channel names
- `chat:write` — for getPermalink

## License

MIT
