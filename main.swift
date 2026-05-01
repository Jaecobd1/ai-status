import Cocoa
import Combine
import Foundation
import SwiftUI

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
        case "none":                   return .operational
        case "minor",
             "degraded_performance":   return .degraded
        case "major", "partial_outage": return .partial
        case "critical", "major_outage": return .major
        case "UP":                     return .operational   // Instatus
        case "HASISSUES":              return .degraded
        case "UNDERMAINTENANCE":       return .degraded
        default:                       return .unknown
        }
    }

    static func fromComponent(_ status: String) -> Health {
        switch status {
        case "operational":            return .operational
        case "degraded_performance":   return .degraded
        case "partial_outage":         return .partial
        case "major_outage":           return .major
        default:                       return .unknown
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

    enum CodingKeys: String, CodingKey { case status, components, incidents }

    init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        status     = try  c.decode(PageStatus.self,   forKey: .status)
        components = (try? c.decode([SPComponent].self, forKey: .components)) ?? []
        incidents  = (try? c.decode([SPIncident].self,  forKey: .incidents))  ?? []
    }
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

    // group / only_show_if_degraded absent in some providers (OpenAI, Groq, Cohere)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name               = try  c.decode(String.self, forKey: .name)
        status             = try  c.decode(String.self, forKey: .status)
        group              = (try? c.decode(Bool.self,  forKey: .group))              ?? false
        onlyShowIfDegraded = (try? c.decode(Bool.self,  forKey: .onlyShowIfDegraded)) ?? false
    }
}

struct SPIncident: Decodable { let name: String }

// MARK: - Instatus JSON (Perplexity)

struct InstatusResponse: Decodable {
    let page: InstatusPage
}
struct InstatusPage: Decodable {
    let name: String
    let status: String
}

// MARK: - Provider Models

struct ComponentHealth { let name: String; let health: Health }

struct ProviderResult {
    let health: Health
    let summary: String
    let components: [ComponentHealth]
    let incidents: [String]
}

enum FetchState { case loading, error, success(ProviderResult) }

enum ProviderKind {
    case statuspage(apiURL: URL, pageURL: URL)
    case instatus(apiURL: URL, pageURL: URL)
    case ollama(baseURL: URL)
}

struct Provider {
    let id: String
    let name: String
    let kind: ProviderKind
    let isLocal: Bool
    var state: FetchState = .loading
}

// MARK: - Built-in Definitions

struct BuiltInDef { let id: String; let name: String; let kind: ProviderKind; let isLocal: Bool }

let builtInDefs: [BuiltInDef] = [
    BuiltInDef(id: "claude", name: "Claude",
               kind: .statuspage(apiURL: URL(string: "https://status.claude.com/api/v2/summary.json")!,
                                 pageURL: URL(string: "https://status.claude.com")!), isLocal: false),
    BuiltInDef(id: "openai", name: "OpenAI",
               kind: .statuspage(apiURL: URL(string: "https://status.openai.com/api/v2/summary.json")!,
                                 pageURL: URL(string: "https://status.openai.com")!), isLocal: false),
    BuiltInDef(id: "groq", name: "Groq",
               kind: .statuspage(apiURL: URL(string: "https://groqstatus.com/api/v2/summary.json")!,
                                 pageURL: URL(string: "https://groqstatus.com")!), isLocal: false),
    BuiltInDef(id: "cohere", name: "Cohere",
               kind: .statuspage(apiURL: URL(string: "https://status.cohere.com/api/v2/summary.json")!,
                                 pageURL: URL(string: "https://status.cohere.com")!), isLocal: false),
    BuiltInDef(id: "perplexity", name: "Perplexity",
               kind: .instatus(apiURL: URL(string: "https://status.perplexity.com/api/v2/summary.json")!,
                               pageURL: URL(string: "https://status.perplexity.com")!), isLocal: false),
    BuiltInDef(id: "ollama", name: "Ollama",
               kind: .ollama(baseURL: URL(string: "http://localhost:11434")!), isLocal: true),
]

// MARK: - Custom Provider

enum CustomProviderType: String, Codable, CaseIterable {
    case statuspage = "statuspage"
    case ollama     = "ollama"
    var label: String { self == .statuspage ? "Status Page" : "Ollama" }
}

struct CustomProviderDef: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var type: CustomProviderType
    var url: String

    var providerKind: ProviderKind? {
        let trimmed = url.trimmingCharacters(in: .init(charactersIn: "/"))
        switch type {
        case .statuspage:
            guard let pageURL = URL(string: trimmed),
                  let apiURL  = URL(string: "\(trimmed)/api/v2/summary.json") else { return nil }
            return .statuspage(apiURL: apiURL, pageURL: pageURL)
        case .ollama:
            guard let base = URL(string: trimmed) else { return nil }
            return .ollama(baseURL: base)
        }
    }
}

// MARK: - App Settings

extension Notification.Name {
    static let settingsChanged = Notification.Name("ai-status.settingsChanged")
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var enabledIDs: Set<String>       { didSet { persist() } }
    @Published var pollInterval: Double           { didSet { persist() } }
    @Published var ollamaURL: String             { didSet { persist() } }
    @Published var customProviders: [CustomProviderDef] { didSet { persist() } }

    private let ud = UserDefaults.standard

    private init() {
        let allIDs = builtInDefs.map(\.id)
        enabledIDs      = Set(ud.stringArray(forKey: "ai-status.enabledIDs") ?? allIDs)
        pollInterval    = (ud.object(forKey: "ai-status.pollInterval") as? Double) ?? 60
        ollamaURL       = ud.string(forKey: "ai-status.ollamaURL") ?? "http://localhost:11434"
        customProviders = (ud.data(forKey: "ai-status.customProviders")
            .flatMap { try? JSONDecoder().decode([CustomProviderDef].self, from: $0) }) ?? []
    }

    private func persist() {
        ud.set(Array(enabledIDs),                                      forKey: "ai-status.enabledIDs")
        ud.set(pollInterval,                                           forKey: "ai-status.pollInterval")
        ud.set(ollamaURL,                                              forKey: "ai-status.ollamaURL")
        ud.set(try? JSONEncoder().encode(customProviders),             forKey: "ai-status.customProviders")
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    func toggleBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { self.enabledIDs.contains(id) },
            set: { if $0 { self.enabledIDs.insert(id) } else { self.enabledIDs.remove(id) } }
        )
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newName = ""
    @State private var newURL  = ""
    @State private var newType: CustomProviderType = .statuspage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                providersSection
                refreshSection
                customSection
            }
            .padding(20)
        }
        .frame(width: 480, height: 520)
    }

    // MARK: Providers

    private var providersSection: some View {
        section(title: "Providers", icon: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(builtInDefs, id: \.id) { def in
                    if def.id == "ollama" {
                        ollamaRow(def: def)
                    } else {
                        Toggle(def.name, isOn: settings.toggleBinding(for: def.id))
                    }
                }
            }
        }
    }

    private func ollamaRow(def: BuiltInDef) -> some View {
        HStack {
            Toggle(def.name, isOn: settings.toggleBinding(for: def.id))
            Spacer()
            if settings.isEnabled(def.id) {
                TextField("http://localhost:11434", text: $settings.ollamaURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: Refresh

    private var refreshSection: some View {
        section(title: "Refresh Every", icon: "clock") {
            Picker("", selection: $settings.pollInterval) {
                Text("30 seconds").tag(30.0)
                Text("1 minute").tag(60.0)
                Text("5 minutes").tag(300.0)
                Text("15 minutes").tag(900.0)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    // MARK: Custom Providers

    private var customSection: some View {
        section(title: "Custom Providers", icon: "plus.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if settings.customProviders.isEmpty {
                    Text("No custom providers yet.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                } else {
                    ForEach(settings.customProviders) { cp in
                        HStack(spacing: 8) {
                            Text(cp.name)
                                .frame(width: 100, alignment: .leading)
                                .lineLimit(1)
                            Text(cp.url)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(cp.type.label)
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .frame(width: 72, alignment: .trailing)
                            Button {
                                settings.customProviders.removeAll { $0.id == cp.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider()
                }

                HStack(spacing: 8) {
                    TextField("Name", text: $newName)
                        .frame(width: 100)
                    TextField("https://status.example.com", text: $newURL)
                    Picker("", selection: $newType) {
                        ForEach(CustomProviderType.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .frame(width: 100)
                    Button("Add") {
                        guard !newName.isEmpty, !newURL.isEmpty else { return }
                        settings.customProviders.append(
                            CustomProviderDef(name: newName, type: newType, url: newURL))
                        newName = ""
                        newURL  = ""
                    }
                    .disabled(newName.isEmpty || newURL.isEmpty)
                }
            }
        }
    }

    // MARK: Layout helper

    private func section<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            GroupBox { content().padding(8) }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var providers: [Provider] = []
    private var lastUpdated: Date?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

        NotificationCenter.default.addObserver(
            self, selector: #selector(onSettingsChanged),
            name: .settingsChanged, object: nil)

        rebuildProviders()
        startTimer()
    }

    // MARK: - Settings

    @objc private func onSettingsChanged() {
        rebuildProviders()
        restartTimer()
    }

    private func rebuildProviders() {
        let s = AppSettings.shared
        var result: [Provider] = []

        for def in builtInDefs {
            guard s.isEnabled(def.id) else { continue }
            var kind = def.kind
            if def.id == "ollama", let url = URL(string: s.ollamaURL) {
                kind = .ollama(baseURL: url)
            }
            result.append(Provider(id: def.id, name: def.name, kind: kind, isLocal: def.isLocal))
        }

        for cp in s.customProviders {
            guard let kind = cp.providerKind else { continue }
            result.append(Provider(id: cp.id, name: cp.name, kind: kind, isLocal: cp.type == .ollama))
        }

        providers = result
        updateButton()
        fetchAll()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "AI Status — Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 480, height: 520))
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
        settingsWindow = nil
    }

    // MARK: - Timer

    private func startTimer() {
        let interval = AppSettings.shared.pollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchAll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func restartTimer() {
        timer?.invalidate()
        startTimer()
    }

    // MARK: - Fetching

    private func fetchAll() {
        lastUpdated = Date()
        for i in providers.indices { fetchProvider(at: i) }
    }

    private func fetchProvider(at index: Int) {
        let done: (FetchState) -> Void = { [weak self] state in
            self?.providers[index].state = state
            self?.updateButton()
        }
        switch providers[index].kind {
        case .statuspage(let u, _): fetchStatuspage(url: u, completion: done)
        case .instatus(let u, _):   fetchInstatus(url: u,   completion: done)
        case .ollama(let u):        fetchOllama(url: u,     completion: done)
        }
    }

    private func fetchStatuspage(url: URL, completion: @escaping (FetchState) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let r = try? JSONDecoder().decode(StatuspageResponse.self, from: data) else {
                    completion(.error); return
                }
                let components = r.components
                    .filter { !$0.group && (!$0.onlyShowIfDegraded || $0.status != "operational") }
                    .map { ComponentHealth(name: $0.name, health: Health.fromComponent($0.status)) }
                completion(.success(ProviderResult(
                    health: Health.from(r.status.indicator),
                    summary: r.status.description,
                    components: components,
                    incidents: r.incidents.map(\.name))))
            }
        }.resume()
    }

    private func fetchInstatus(url: URL, completion: @escaping (FetchState) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let r = try? JSONDecoder().decode(InstatusResponse.self, from: data) else {
                    completion(.error); return
                }
                let health = Health.from(r.page.status)
                completion(.success(ProviderResult(
                    health: health,
                    summary: health == .operational ? "All Systems Operational" : r.page.status,
                    components: [], incidents: [])))
            }
        }.resume()
    }

    private func fetchOllama(url: URL, completion: @escaping (FetchState) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { _, _, error in
            DispatchQueue.main.async {
                if error != nil {
                    completion(.success(ProviderResult(
                        health: .unreachable, summary: "Not running",
                        components: [], incidents: [])))
                } else {
                    completion(.success(ProviderResult(
                        health: .operational,
                        summary: "Running on port \(url.port ?? 11434)",
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

        if providers.isEmpty {
            menu.addItem(disabled("No providers enabled"))
        } else {
            providers.forEach { menu.addItem(makeProviderItem($0)) }
        }

        menu.addItem(.separator())

        if let updated = lastUpdated {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .abbreviated
            menu.addItem(disabled("Updated \(fmt.localizedString(for: updated, relativeTo: Date()))"))
        }

        let refresh = NSMenuItem(title: "Refresh", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AI Status", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeProviderItem(_ provider: Provider) -> NSMenuItem {
        let health: Health = { if case .success(let r) = provider.state { return r.health }; return .unknown }()
        let item = NSMenuItem(title: "\(health.emoji)  \(provider.name)", action: nil, keyEquivalent: "")
        let sub  = NSMenu()

        switch provider.state {
        case .loading:           sub.addItem(disabled("Loading…"))
        case .error:             sub.addItem(disabled("Failed to fetch status"))
        case .success(let r):
            sub.addItem(disabled(r.summary))
            if !r.components.isEmpty {
                sub.addItem(.separator())
                r.components.forEach { sub.addItem(disabled("\($0.health.emoji)  \($0.name)")) }
            }
            if !r.incidents.isEmpty {
                sub.addItem(.separator())
                r.incidents.forEach { sub.addItem(disabled("⚠️  \($0)")) }
            }
        }

        let pageURL: URL? = {
            switch provider.kind {
            case .statuspage(_, let u): return u
            case .instatus(_, let u):   return u
            case .ollama:               return nil
            }
        }()
        if let pageURL {
            sub.addItem(.separator())
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
