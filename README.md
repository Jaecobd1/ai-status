# AI Status

macOS menu bar app that polls the status pages of major AI providers and shows a health indicator at a glance.

![AI Status menu bar app](screenshot.png)

## Providers

| Provider | Status Page |
|---|---|
| Claude | status.claude.com |
| OpenAI | status.openai.com |
| Groq | groqstatus.com |
| Cohere | status.cohere.com |
| Perplexity | status.perplexity.com |
| Ollama | localhost:11434 (auto-detected) |

## Status Indicator

The menu bar dot reflects the worst status across all cloud providers:

- 🟢 All Systems Operational
- 🟡 Degraded Performance
- 🟠 Partial Outage
- 🔴 Major Outage
- ⚪️ Unknown / loading
- ⚫️ Not running (Ollama only — does not affect the overall dot)

Click any provider to see per-component status and active incidents. Polls every 60 seconds.

## Adding a Custom Provider

Edit the `allProviders` array in `main.swift`. Any service using [Statuspage](https://www.atlassian.com/software/statuspage) or [Instatus](https://instatus.com) works out of the box:

```swift
Provider(id: "myprovider", name: "My Provider",
         kind: .statuspage(
            apiURL: URL(string: "https://status.example.com/api/v2/summary.json")!,
            pageURL: URL(string: "https://status.example.com")!),
         isLocal: false),
```

For a local Ollama instance on a custom port:

```swift
Provider(id: "ollama2", name: "Ollama (8080)",
         kind: .ollama(baseURL: URL(string: "http://localhost:8080")!),
         isLocal: true),
```

## Requirements

- macOS 13+
- Xcode Command Line Tools — `xcode-select --install`

## Build & Run

```bash
./build.sh
open build/AIStatus.app
```

## Install

```bash
cp -r build/AIStatus.app ~/Applications/
```

To auto-start at login: **System Settings → General → Login Items → +** → select `AIStatus.app`.
