# Slack Mention Notifier

A lightweight macOS menu bar app that monitors Slack mentions via **Socket Mode** (WebSocket) and:

- 👀 Reacts to the message (configurable emoji)
- ✅ Creates an Apple Reminder (customizable templates)
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
```

Create a `.env.local` file with your Slack app credentials:

```bash
cat > .env.local << 'EOF'
SLACK_APP_TOKEN=xapp-1-...
SLACK_CLIENT_ID=123456.789012
SLACK_CLIENT_SECRET=abc123...
EOF
```

Then build and run:

```bash
make run
```

`make run` automatically injects secrets from `.env.local` into the build. Sign in with Slack from the menu bar.

## Preferences

Open **Preferences** from the menu bar (🔔 → Preferences... or ⌘,) to configure:

| Setting | Description |
|---------|-------------|
| **Reminders list** | Choose which Apple Reminders list to use (dropdown shows all your lists) |
| **Reaction emoji** | Pick from 200+ standard emoji or your workspace's custom emoji |
| **Auto-join channels** | Automatically join all public channels (re-scans hourly for new ones) |
| **Title template** | Named presets (Default, Compact, Sender only, Channel first) or Custom |
| **Notes template** | Named presets (Default, Structured, Compact, Link only) or Custom |

Custom templates support these placeholders: `{sender}`, `{channel}`, `{message}`, `{permalink}`, `{date}`. Use `\n` for newlines. A live preview shows exactly how your reminders will look.

Changes apply immediately — no restart needed.

### Configuration file (advanced)

When building from source without OAuth, you can also configure via `~/.config/slack-mention-notifier/config.env`:

```bash
mkdir -p ~/.config/slack-mention-notifier
cat > ~/.config/slack-mention-notifier/config.env << 'EOF'
SLACK_APP_TOKEN=xapp-1-...          # Socket Mode app-level token
SLACK_BOT_TOKEN=xoxb-...            # Bot token (or use OAuth)
SLACK_TRACKED_USER_ID=U...          # Your Slack user ID (or use OAuth)

# --- Optional (also configurable in Preferences UI) ---
# APPLE_REMINDERS_LIST=Reminders
# REACTION_EMOJI=eyes
# AUTO_JOIN_CHANNELS=true
# REMINDER_TITLE_TEMPLATE=Slack: {sender} in #{channel}
# REMINDER_NOTES_TEMPLATE={message}\n\n{permalink}
EOF
```

## Usage

Once running, you'll see a 🔔 bell icon in the menu bar with these options:

- **Sign in with Slack...** — OAuth flow (opens browser, one click)
- **Launch at Login** — toggle auto-start on boot
- **Preferences...** (⌘,) — emoji, templates, reminders list, auto-join
- **Sign Out** — clear stored tokens
- **Quit**

Mentions are handled automatically — react, reminder, notification. If your Mac sleeps or loses connection, missed mentions are recovered automatically on reconnect.

### Build commands

| Command | Description |
|---------|-------------|
| `make build` | Build release binary |
| `make run` | Build and run (injects secrets from `.env.local`) |
| `make bundle` | Build universal .app bundle + DMG |
| `make install` | Install binary to ~/.local/bin |
| `make autostart` | Install + enable auto-start via LaunchAgent |
| `make stop` | Stop the LaunchAgent service |
| `make uninstall` | Remove binary + LaunchAgent |

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
        "emoji:read",
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
3. **Invite the bot** to channels: `/invite @Mention Notifier` (or enable **Auto-join channels** in Preferences)

### Required scopes explained

| Scope | Purpose |
|-------|---------|
| `channels:history` | Read public channel messages |
| `channels:join` | Auto-join public channels |
| `channels:read` | Get channel names |
| `chat:write` | Get message permalinks |
| `emoji:read` | List workspace custom emoji for Preferences |
| `groups:history` | Read private channel messages |
| `groups:read` | Get private channel names |
| `im:history` | Read direct messages |
| `im:read` | List DM conversations |
| `mpim:history` | Read group DMs |
| `mpim:read` | List group DM conversations |
| `reactions:write` | React to messages |
| `users:read` | Get user display names |

## Multi-user usage

Multiple people in the same workspace can use the app simultaneously:

1. A workspace admin installs the Slack app once (via "Add to Slack" or the manifest)
2. Each user downloads the macOS app and signs in with their own Slack account
3. Each user's app only processes mentions of **their own** user ID — other messages are silently discarded

**Limit:** Slack allows a maximum of **10 concurrent Socket Mode connections** per app-level token. This means up to 10 users can run the app at the same time. For larger teams, generate additional app-level tokens in the Slack app settings (Socket Mode → generate another token with `connections:write`).

## License

MIT
