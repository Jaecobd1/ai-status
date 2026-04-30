# Claude Status

macOS menu bar app that polls [status.claude.com](https://status.claude.com) and shows Claude's health at a glance.

![Menu bar showing colored dot and Claude label](https://status.claude.com/favicon.ico)

## What it shows

- **●** dot color reflects overall status:
  - 🟢 Green — All Systems Operational
  - 🟡 Yellow — Degraded Performance
  - 🟠 Orange — Partial Outage
  - 🔴 Red — Major Outage
  - Gray — Loading / network error
- Per-component status in the dropdown
- Active incidents when present
- Last updated time

Polls every 60 seconds. Press `r` or click Refresh to fetch immediately.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
./build.sh
open build/ClaudeStatus.app
```

## Install

```bash
cp -r build/ClaudeStatus.app ~/Applications/
```

To auto-start at login: **System Settings → General → Login Items → +** → select `ClaudeStatus.app`.
