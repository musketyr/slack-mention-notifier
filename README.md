# Slack Mention Notifier

A lightweight macOS menu bar app that monitors Slack mentions via **Socket Mode** (WebSocket) and:

- 👀 Reacts to the message
- ✅ Creates an Apple Reminder
- 🔔 Shows a macOS notification

**Zero server infrastructure.** Runs entirely on your Mac — connects directly to Slack via WebSocket.

## Install

### Download (easiest)

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/musketyr/slack-mention-notifier/releases)
2. Open the DMG and drag **Slack Mention Notifier** to Applications
3. Launch the app — click the 🔔 menu bar icon → **Sign in with Slack...**
4. Enable **Launch at Login** from the menu bar

> ⚠️ On first launch, macOS may warn about an unidentified developer. Right-click → Open to bypass, or run:
> `xattr -cr /Applications/Slack\ Mention\ Notifier.app`

### Build from source

Requires **macOS 13+** with Xcode Command Line Tools.

```bash
git clone https://github.com/musketyr/slack-mention-notifier.git
cd slack-mention-notifier
make run
```

## Prerequisites

A **Slack App** with Socket Mode enabled (see [Slack App Setup](#slack-app-setup-details) below)

## Setup

There are two ways to configure the app:

### Option A: Sign in with Slack (OAuth — recommended)

This is the easiest setup. You only need the app-level token and OAuth credentials:

```bash
mkdir -p ~/.config/slack-mention-notifier
cat > ~/.config/slack-mention-notifier/config.env << 'EOF'
SLACK_APP_TOKEN=xapp-1-...          # Socket Mode app-level token
SLACK_CLIENT_ID=123456.789012       # From Slack App → Basic Information
SLACK_CLIENT_SECRET=abc123...       # From Slack App → Basic Information

# Optional
APPLE_REMINDERS_LIST=Reminders
EOF
```

Then launch the app and click **"Sign in with Slack..."** in the menu bar. This will:
1. Open your browser to authorize the app
2. Store the bot token securely in your macOS Keychain
3. Automatically detect your Slack user ID

### Option B: Manual token configuration

For advanced users or CI/automation:

```bash
mkdir -p ~/.config/slack-mention-notifier
cat > ~/.config/slack-mention-notifier/config.env << 'EOF'
SLACK_APP_TOKEN=xapp-1-...          # Socket Mode app-level token
SLACK_BOT_TOKEN=xoxb-...            # Bot token
SLACK_TRACKED_USER_ID=U...          # Your Slack user ID

# Optional
APPLE_REMINDERS_LIST=Reminders
EOF
```

> **Note:** If you have a legacy `~/.slack-mention-notifier.env` file, it will be migrated automatically on first run.

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
                                     │     │
                                ┌────┘     └────┐
                                ▼               ▼
                           SlackAPI      ReminderService
                          (react 👀)     (EventKit)
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

### OAuth (for "Sign in with Slack")

If distributing the app to others:

1. Go to **OAuth & Permissions** → **Redirect URLs**
2. Add: `http://localhost` (the app uses a dynamic port, so just the host is needed)
3. Note the **Client ID** and **Client Secret** from **Basic Information**

The app starts a temporary local HTTP server during sign-in to receive the OAuth callback.

### Required Bot Token Scopes

- `reactions:write` — react to messages
- `channels:history` — read public channel messages
- `channels:read` — get channel names
- `groups:history` — read private channel messages
- `groups:read` — get private channel names
- `im:history` — read direct messages
- `im:read` — list DM conversations
- `mpim:history` — read group DMs
- `mpim:read` — list group DM conversations
- `users:read` — get user display names
- `chat:write` — for getPermalink

### App Manifest

```json
{
  "display_information": {
    "name": "Slack Mention Notifier",
    "description": "Monitors mentions and creates Apple Reminders",
    "background_color": "#4A154B"
  },
  "features": {
    "bot_user": {
      "display_name": "Mention Notifier",
      "always_online": true
    }
  },
  "oauth_config": {
    "redirect_urls": [
      "http://localhost"
    ],
    "scopes": {
      "bot": [
        "channels:history",
        "channels:read",
        "chat:write",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "mpim:history",
        "mpim:read",
        "reactions:write",
        "users:read"
      ]
    }
  },
  "settings": {
    "event_subscriptions": {
      "bot_events": [
        "message.channels",
        "message.groups",
        "message.im",
        "message.mpim"
      ]
    },
    "interactivity": {
      "is_enabled": false
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": true,
    "token_rotation_enabled": false
  }
}
```

## License

MIT
