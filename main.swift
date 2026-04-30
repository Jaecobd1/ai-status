import Cocoa
import Foundation

// MARK: - Models

struct StatusResponse: Decodable {
    let status: OverallStatus
    let components: [Component]
    let incidents: [Incident]
}

struct OverallStatus: Decodable {
    let indicator: String
    let description: String
}

struct Component: Decodable {
    let id: String
    let name: String
    let status: String
    let group: Bool
    let onlyShowIfDegraded: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, status, group
        case onlyShowIfDegraded = "only_show_if_degraded"
    }
}

struct Incident: Decodable {
    let id: String
    let name: String
    let status: String
    let impact: String?
}

// MARK: - Helpers

func dotColor(for indicator: String) -> NSColor {
    switch indicator {
    case "none":                 return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    case "minor",
         "degraded_performance": return NSColor(red: 1.00, green: 0.75, blue: 0.00, alpha: 1)
    case "major",
         "partial_outage":       return NSColor(red: 1.00, green: 0.45, blue: 0.00, alpha: 1)
    case "critical",
         "major_outage":         return NSColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
    default:                     return .secondaryLabelColor
    }
}

func statusEmoji(for status: String) -> String {
    switch status {
    case "operational":          return "🟢"
    case "degraded_performance": return "🟡"
    case "partial_outage":       return "🟠"
    case "major_outage":         return "🔴"
    default:                     return "⚪️"
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lastStatus: StatusResponse?
    private var lastUpdated: Date?
    private var fetchError = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

        updateButton(indicator: nil)
        fetchStatus()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchStatus()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func updateButton(indicator: String?) {
        guard let button = statusItem?.button else { return }

        let color: NSColor = indicator.map { dotColor(for: $0) } ?? .secondaryLabelColor

        let dot = NSMutableAttributedString(string: "●")
        dot.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: 1))
        dot.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 1))

        let label = NSAttributedString(string: " Claude", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ])

        let title = NSMutableAttributedString()
        title.append(dot)
        title.append(label)
        button.attributedTitle = title
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if fetchError {
            addItem("⚠️  Unable to fetch status", enabled: false, to: menu)
        } else if let s = lastStatus {
            let overallEmoji = statusEmoji(for: s.status.indicator == "none" ? "operational" : s.status.indicator)
            addItem("\(overallEmoji)  \(s.status.description)", enabled: false, to: menu)
            menu.addItem(NSMenuItem.separator())

            let visible = s.components.filter {
                !$0.group && (!$0.onlyShowIfDegraded || $0.status != "operational")
            }
            for c in visible {
                addItem("\(statusEmoji(for: c.status))  \(c.name)", enabled: false, to: menu)
            }

            if !s.incidents.isEmpty {
                menu.addItem(NSMenuItem.separator())
                addItem("Active Incidents", enabled: false, to: menu)
                for i in s.incidents {
                    addItem("   ⚠️  \(i.name)", enabled: false, to: menu)
                }
            }
        } else {
            addItem("Fetching status…", enabled: false, to: menu)
        }

        menu.addItem(NSMenuItem.separator())

        if let updated = lastUpdated {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .abbreviated
            addItem("Updated \(fmt.localizedString(for: updated, relativeTo: Date()))", enabled: false, to: menu)
        }

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openItem = NSMenuItem(title: "Open Status Page", action: #selector(openStatusPage), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Claude Status", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @discardableResult
    private func addItem(_ title: String, enabled: Bool, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc func manualRefresh() { fetchStatus() }

    @objc func openStatusPage() {
        NSWorkspace.shared.open(URL(string: "https://status.claude.com")!)
    }

    // MARK: - Networking

    private func fetchStatus() {
        guard let url = URL(string: "https://status.claude.com/api/v2/summary.json") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let response = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                    self.lastStatus = response
                    self.lastUpdated = Date()
                    self.fetchError = false
                    self.updateButton(indicator: response.status.indicator)
                } else {
                    self.fetchError = true
                    self.updateButton(indicator: nil)
                }
            }
        }.resume()
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
