# Slack Mention Notifier

A lightweight macOS menu bar app that monitors Slack mentions via **Socket Mode** (WebSocket) and:

- 👀 Reacts to the message (configurable emoji)
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

When building from source, create a config file (see [Configuration](#configuration) below).

## Configuration

The DMG download has secrets embedded — just sign in and go. When building from source, create a config file:

```bash
mkdir -p ~/.config/slack-mention-notifier
cat > ~/.config/slack-mention-notifier/config.env << 'EOF'
SLACK_APP_TOKEN=xapp-1-...          # Socket Mode app-level token
SLACK_BOT_TOKEN=xoxb-...            # Bot token (or use OAuth below)
SLACK_TRACKED_USER_ID=U...          # Your Slack user ID (or use OAuth)

# --- OAuth (alternative to BOT_TOKEN + TRACKED_USER_ID) ---
# SLACK_CLIENT_ID=123456.789012
# SLACK_CLIENT_SECRET=abc123...

# --- Optional ---
# APPLE_REMINDERS_LIST=Reminders    # Target Reminders list (default: Reminders)
# REACTION_EMOJI=eyes               # Slack emoji name for reactions (default: eyes)
# AUTO_JOIN_CHANNELS=true            # Auto-join all public channels (default: false)
EOF
```

On first run, macOS will prompt for **Reminders access** — click OK.

## Usage

Once running, you'll see a 🔔 bell icon in the menu bar with these options:

- **Sign in with Slack...** — OAuth flow (opens browser)
- **Launch at Login** — toggle auto-start on login
- **Sign Out** — clear stored tokens
- **Quit**

Mentions are handled automatically — react, reminder, notification.

### Build commands

| Command | Description |
|---------|-------------|
| `make build` | Build release binary |
| `make run` | Build and run in foreground |
| `make bundle` | Build universal .app bundle + DMG |
| `make install` | Install binary to ~/.local/bin |
| `make autostart` | Install + enable auto-start via LaunchAgent |
| `make stop` | Stop the LaunchAgent service |
| `make uninstall` | Remove binary + LaunchAgent |

### Logs

```bash
tail -f /tmp/slack-mention-notifier.log
```

## Architecture

```
Slack (WebSocket) ──Socket Mode──▶ SlackSocketMode
                                        │
                                    onConnect
                                        │
                                        ▼
                                  MentionHandler
                                   │    │    │
                              ┌────┘    │    └────┐
                              ▼         ▼         ▼
                         SlackAPI  ReminderService  macOS
                        (react +   (EventKit)    notification
                        resolve)        │
                              │         ▼
                              │   Apple Reminders
                              ▼
                         Catch-up on
                         reconnect
```

## Slack App Setup

### Quick setup (manifest)

Go to [api.slack.com/apps](https://api.slack.com/apps) → Create New App → **From a manifest** → paste:

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
      "https://smn.orany.cz/callback/"
    ],
    "scopes": {
      "bot": [
        "channels:history",
        "channels:join",
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

After creating the app:

1. **Socket Mode** → generate an App-Level Token with `connections:write` scope → gives you `xapp-...`
2. **Install to workspace** → gives you `xoxb-...` bot token
3. **Invite the bot** to channels: `/invite @Mention Notifier` (or set `AUTO_JOIN_CHANNELS=true` for public channels)

### Required scopes explained

| Scope | Purpose |
|-------|---------|
| `channels:history` | Read public channel messages |
| `channels:join` | Auto-join public channels |
| `channels:read` | Get channel names |
| `groups:history` | Read private channel messages |
| `groups:read` | Get private channel names |
| `im:history` | Read direct messages |
| `im:read` | List DM conversations |
| `mpim:history` | Read group DMs |
| `mpim:read` | List group DM conversations |
| `reactions:write` | React to messages |
| `users:read` | Get user display names |
| `chat:write` | Get message permalinks |

## License

MIT
