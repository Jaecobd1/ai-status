import Cocoa
import Foundation

// MARK: - Health

enum Health: Int, Comparable {
    case operational = 0
    case degraded    = 1
    case partial     = 2
    case major       = 3
    case unknown     = 4
    case unreachable = 5  // local provider not running

    static func < (lhs: Health, rhs: Health) -> Bool { lhs.rawValue < rhs.rawValue }

    static func from(_ indicator: String) -> Health {
        switch indicator {
        case "none":                  return .operational
        case "minor",
             "degraded_performance":  return .degraded
        case "major", "partial_outage": return .partial
        case "critical", "major_outage": return .major
        // Instatus values (e.g. Perplexity)
        case "UP":                    return .operational
        case "HASISSUES":             return .degraded
        case "UNDERMAINTENANCE":      return .degraded
        default:                      return .unknown
        }
    }

    static func fromComponent(_ status: String) -> Health {
        switch status {
        case "operational":           return .operational
        case "degraded_performance":  return .degraded
        case "partial_outage":        return .partial
        case "major_outage":          return .major
        default:                      return .unknown
        }
    }

    var emoji: String {
        switch self {
        case .operational:  return "🟢"
        case .degraded:     return "🟡"
        case .partial:      return "🟠"
        case .major:        return "🔴"
        case .unknown:      return "⚪️"
        case .unreachable:  return "⚫️"
        }
    }

    var dotColor: NSColor {
        switch self {
        case .operational:  return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .degraded:     return NSColor(red: 1.00, green: 0.75, blue: 0.00, alpha: 1)
        case .partial:      return NSColor(red: 1.00, green: 0.45, blue: 0.00, alpha: 1)
        case .major:        return NSColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
        case .unknown:      return .secondaryLabelColor
        case .unreachable:  return .tertiaryLabelColor
        }
    }
}

// MARK: - Statuspage JSON

struct StatuspageResponse: Decodable {
    let status: PageStatus
    let components: [SPComponent]
    let incidents: [SPIncident]
}

struct PageStatus: Decodable {
    let indicator: String
    let description: String
}

struct SPComponent: Decodable {
    let name: String
    let status: String
    let group: Bool
    let onlyShowIfDegraded: Bool

    enum CodingKeys: String, CodingKey {
        case name, status, group
        case onlyShowIfDegraded = "only_show_if_degraded"
    }
}

struct SPIncident: Decodable {
    let name: String
}

// MARK: - Provider Model

struct ComponentHealth {
    let name: String
    let health: Health
}

struct ProviderResult {
    let health: Health
    let summary: String
    let components: [ComponentHealth]
    let incidents: [String]
}

enum FetchState {
    case loading
    case success(ProviderResult)
    case error
}

enum ProviderKind {
    case statuspage(apiURL: URL, pageURL: URL)
    case ollama(baseURL: URL)
    // ── Adding a custom provider ─────────────────────────────────────────────
    // Statuspage-compatible (includes Instatus):
    //   .statuspage(
    //       apiURL: URL(string: "https://status.example.com/api/v2/summary.json")!,
    //       pageURL: URL(string: "https://status.example.com")!)
    // Local Ollama on a non-default port:
    //   .ollama(baseURL: URL(string: "http://localhost:8080")!)
    // ─────────────────────────────────────────────────────────────────────────
}

struct Provider {
    let id: String
    let name: String
    let kind: ProviderKind
    let isLocal: Bool       // true = excluded from the overall dot color
    var state: FetchState = .loading
}

// MARK: - Provider Registry
// Add, remove, or reorder providers here.

var allProviders: [Provider] = [
    Provider(id: "claude", name: "Claude",
             kind: .statuspage(
                apiURL: URL(string: "https://status.claude.com/api/v2/summary.json")!,
                pageURL: URL(string: "https://status.claude.com")!),
             isLocal: false),

    Provider(id: "openai", name: "OpenAI",
             kind: .statuspage(
                apiURL: URL(string: "https://status.openai.com/api/v2/summary.json")!,
                pageURL: URL(string: "https://status.openai.com")!),
             isLocal: false),

    Provider(id: "groq", name: "Groq",
             kind: .statuspage(
                apiURL: URL(string: "https://groqstatus.com/api/v2/summary.json")!,
                pageURL: URL(string: "https://groqstatus.com")!),
             isLocal: false),

    Provider(id: "cohere", name: "Cohere",
             kind: .statuspage(
                apiURL: URL(string: "https://status.cohere.com/api/v2/summary.json")!,
                pageURL: URL(string: "https://status.cohere.com")!),
             isLocal: false),

    Provider(id: "perplexity", name: "Perplexity",
             kind: .statuspage(
                apiURL: URL(string: "https://status.perplexity.com/api/v2/summary.json")!,
                pageURL: URL(string: "https://status.perplexity.com")!),
             isLocal: false),

    Provider(id: "ollama", name: "Ollama",
             kind: .ollama(baseURL: URL(string: "http://localhost:11434")!),
             isLocal: true),
]

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var providers: [Provider] = allProviders
    private var lastUpdated: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

        updateButton()
        fetchAll()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchAll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: - Fetching

    private func fetchAll() {
        lastUpdated = Date()
        for i in providers.indices {
            fetchProvider(at: i)
        }
    }

    private func fetchProvider(at index: Int) {
        switch providers[index].kind {
        case .statuspage(let apiURL, _):
            fetchStatuspage(url: apiURL) { [weak self] state in
                self?.providers[index].state = state
                self?.updateButton()
            }
        case .ollama(let baseURL):
            fetchOllama(url: baseURL) { [weak self] state in
                self?.providers[index].state = state
                self?.updateButton()
            }
        }
    }

    private func fetchStatuspage(url: URL, completion: @escaping (FetchState) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let r = try? JSONDecoder().decode(StatuspageResponse.self, from: data) else {
                    completion(.error)
                    return
                }
                let health = Health.from(r.status.indicator)
                let components = r.components
                    .filter { !$0.group && (!$0.onlyShowIfDegraded || $0.status != "operational") }
                    .map { ComponentHealth(name: $0.name, health: Health.fromComponent($0.status)) }
                completion(.success(ProviderResult(
                    health: health,
                    summary: r.status.description,
                    components: components,
                    incidents: r.incidents.map(\.name)
                )))
            }
        }.resume()
    }

    private func fetchOllama(url: URL, completion: @escaping (FetchState) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                if error != nil {
                    completion(.success(ProviderResult(
                        health: .unreachable, summary: "Not running",
                        components: [], incidents: [])))
                } else {
                    let port = url.port ?? 11434
                    completion(.success(ProviderResult(
                        health: .operational,
                        summary: "Running on port \(port)",
                        components: [], incidents: [])))
                }
            }
        }.resume()
    }

    // MARK: - Button

    private func worstHealth() -> Health {
        providers
            .filter { !$0.isLocal }
            .compactMap { if case .success(let r) = $0.state { return r.health } else { return nil } }
            .max() ?? .unknown
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let health = worstHealth()

        let dot = NSMutableAttributedString(string: "●")
        dot.addAttribute(.foregroundColor, value: health.dotColor, range: NSRange(location: 0, length: 1))
        dot.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 1))

        let label = NSAttributedString(string: " AI Status", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ])

        let full = NSMutableAttributedString()
        full.append(dot)
        full.append(label)
        button.attributedTitle = full
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for provider in providers {
            menu.addItem(makeProviderItem(provider))
        }

        menu.addItem(NSMenuItem.separator())

        if let updated = lastUpdated {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .abbreviated
            let item = NSMenuItem(title: "Updated \(fmt.localizedString(for: updated, relativeTo: Date()))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AI Status", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeProviderItem(_ provider: Provider) -> NSMenuItem {
        let health: Health = {
            if case .success(let r) = provider.state { return r.health }
            return .unknown
        }()

        let item = NSMenuItem(title: "\(health.emoji)  \(provider.name)", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        switch provider.state {
        case .loading:
            sub.addItem(disabled("Loading…"))

        case .error:
            sub.addItem(disabled("Failed to fetch status"))

        case .success(let r):
            sub.addItem(disabled(r.summary))

            if !r.components.isEmpty {
                sub.addItem(NSMenuItem.separator())
                r.components.forEach { sub.addItem(disabled("\($0.health.emoji)  \($0.name)")) }
            }

            if !r.incidents.isEmpty {
                sub.addItem(NSMenuItem.separator())
                r.incidents.forEach { sub.addItem(disabled("⚠️  \($0)")) }
            }
        }

        if case .statuspage(_, let pageURL) = provider.kind {
            sub.addItem(NSMenuItem.separator())
            let open = NSMenuItem(title: "Open Status Page", action: #selector(openURL(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = pageURL
            sub.addItem(open)
        }

        item.submenu = sub
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc func manualRefresh() { fetchAll() }

    @objc func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
