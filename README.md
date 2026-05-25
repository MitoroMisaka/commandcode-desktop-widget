# Command Code Desktop Widget

> A native macOS floating widget for monitoring your Command Code API usage in real time.

Built with SwiftUI, inspired by Apple Screen Time's clean aesthetics. Glass-morphism, per-model bar charts, zero Xcode required.

![screenshot](screenshot.jpg)

## Features

- **Usage at a glance** — Total Cost / Tokens / Runs / Success Rate
- **Per-model breakdown** — DeepSeek-V4-Pro, DeepSeek-V4-Flash, K2.5, K2.6, MiniMax, each with a distinct color
- **Hover tooltips** — See per-model detail per hour by hovering over a bar
- **Glass materials** — ultraThinMaterial (when idle) / regularMaterial (when focused)
- **Drag snapping** — 24px grid alignment with a white highlight border during drag
- **Right-click menu** — Refresh data / Quit
- **Auto refresh** — Every 30 minutes + on returning to desktop
- **Credit indicator** — Green/orange dot shows if monthly credits are above/below $1

## Requirements

- macOS 26+
- Firefox (logged into [commandcode.ai](https://commandcode.ai))
- Xcode Command Line Tools (`swiftc`)

## Quick Start

```bash
# Clone
git clone https://github.com/MitoroMisaka/commandcode-desktop-widget.git
cd commandcode-desktop-widget

# Build
./build.sh

# Launch
open .build/CC.app
```

## Build

No Xcode GUI needed — pure `swiftc`:

```bash
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macos26.0 \
  -framework SwiftUI -framework AppKit -framework Combine -framework Foundation \
  -O \
  -o .build/CommandCodeWidget \
  Sources/Models.swift \
  Sources/TokenExtractor.swift \
  Sources/DataFetcher.swift \
  Sources/App.swift
```

## How It Works

### Data Source

The widget pulls from Command Code's internal API — the same endpoints used by [commandcode.ai/studio](https://commandcode.ai/studio):

| Endpoint | What |
|----------|------|
| `/internal/usage/summary` | Aggregate usage (cost, tokens, runs, success rate) |
| `/internal/usage/charts` | Per-hour, per-model usage buckets |
| `/internal/billing/credits` | Monthly credit balance |

### Authentication

The widget reads your session token from Firefox's cookie database. Make sure Firefox is logged into `commandcode.ai`.

The default Firefox profile is `7wpm1h7n.default-release` — update `dbPath` in `Sources/TokenExtractor.swift` if yours differs:

```swift
static let dbPath = NSHomeDirectory() + "/Library/Application Support/Firefox/Profiles/<your-profile>/cookies.sqlite"
```

### Display Logic

- UTC timestamps from the API are converted to JST (Asia/Tokyo) for display
- The bar chart shows the 10 most recent hours
- Bars are stacked by model, colored accordingly — hover for details

## Similar Projects

| Project | Platform | Service |
|---------|----------|---------|
| `chillikai/claude-usage-widget` | macOS Menubar | Claude API |
| `croustibat/ClaudeWidget` | macOS Desktop | Claude API |
| `lkltxwd001/deepseek-desktop-widget` | macOS Desktop | DeepSeek API |
| **This project** | macOS Desktop | **Command Code** |

This is the first desktop usage monitor for Command Code.

## License

MIT
