import AppKit
import Combine
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case models
    case businessContext
    case memory
    case about
    case developer

    static var allCases: [SettingsPane] { [.models, .businessContext, .memory, .about, .developer] }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: return "Models"
        case .businessContext: return "Business context"
        case .memory: return "Memory"
        case .about: return "About"
        case .developer: return "Developer"
        }
    }

    var subtitle: String {
        switch self {
        case .models: return "Runtime and model choices"
        case .businessContext: return "Tell me about your program"
        case .memory: return "What I remember about you"
        case .about: return "Credits and release notes"
        case .developer: return "Logs and preview states"
        }
    }

    var icon: String {
        switch self {
        case .models: return "cpu.fill"
        case .businessContext: return "building.2.crop.circle.fill"
        case .memory: return "brain"
        case .about: return "person.text.rectangle.fill"
        case .developer: return "wrench.and.screwdriver.fill"
        }
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.preferredTransportKey) var preferredTransport = AppSettings.PreferredTransport.automatic.rawValue
    @AppStorage(AppSettings.openAIAPIKeyKey) var openAIAPIKey = ""
    @AppStorage(AppSettings.debugLoggingEnabledKey) var debugLoggingEnabled = true
    @AppStorage(AppSettings.preferredClaudeModelKey) var preferredClaudeModel = AppSettings.ClaudeModel.default.rawValue
    @AppStorage(AppSettings.preferredCodexModelKey) var preferredCodexModel = AppSettings.CodexModel.default.rawValue
    @AppStorage(AppSettings.preferredOpenAIModelKey) var preferredOpenAIModel = AppSettings.OpenAIModel.gpt5Nano.rawValue
    @AppStorage(AppSettings.launchAtLoginKey) var launchAtLogin: Bool = true
    @AppStorage(AppSettings.useAmbientLLMKey) var useAmbientLLM: Bool = true
    @AppStorage(AppSettings.suggestOrbitMCPEnabledKey) var suggestOrbitMCP: Bool = true

    @State var selectedPane: SettingsPane = .models
    @State var showResetConfirmation = false
    @State var resetErrorMessage: String?
    @State var sourcePaneStatusMessage: String?
    @State var sourcePaneErrorMessage: String?
    @State var mcpSyncResultMessage: String?
    @State var detectionRefreshID = UUID()
    // Async detection results — nil means "still checking"
    @State var detectedClaudeAvailable: Bool? = nil
    @State var detectedCodexAvailable: Bool? = nil

    let officialArchiveURL = URL(string: "https://yourorbit.team") ?? URL(fileURLWithPath: "/")

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                ForEach(visiblePanes) { pane in
                    SettingsSidebarRow(
                        pane: pane,
                        isSelected: selectedPane == pane,
                        action: { selectedPane = pane }
                    )
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 250)
        } detail: {
            ScrollView(.vertical, showsIndicators: false) {
                currentPaneView
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("Settings")
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 840, idealWidth: 920, minHeight: 620, idealHeight: 700)
        .onAppear {
            refreshDetectionStateAndDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDetectionStateAndDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liLJustinOpenSettingsPane)) { note in
            // Deep-link from the welcome panel "Tell me about your program"
            // card and any future settings shortcuts. Object is the
            // `SettingsPane.rawValue` to route to.
            if let raw = note.object as? String, let pane = SettingsPane(rawValue: raw), visiblePanes.contains(pane) {
                selectedPane = pane
            }
        }
        .onChange(of: debugLoggingEnabled) { _, enabled in
            if !enabled && selectedPane == .developer {
                selectedPane = .models
            }
        }
        .alert("Reset Orbit data?", isPresented: $showResetConfirmation) {
            Button("Reset All Data", role: .destructive) {
                do {
                    try AppSettings.resetAllData()
                    refreshDetectionStateAndDefaults()
                } catch {
                    resetErrorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears Orbit's saved token, API keys, model/runtime settings, onboarding state, and removes the archive MCP config it wrote for Claude and Codex.")
        }
        .alert("Reset Failed", isPresented: Binding(
            get: { resetErrorMessage != nil },
            set: { if !$0 { resetErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetErrorMessage ?? "")
        }
        .alert("Connection Failed", isPresented: Binding(
            get: { sourcePaneErrorMessage != nil },
            set: { if !$0 { sourcePaneErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sourcePaneErrorMessage ?? "")
        }
    }

    private var visiblePanes: [SettingsPane] {
        // Lenny `.source` pane is intentionally absent — Orion doesn't
        // use the upstream archive at all.
        var panes: [SettingsPane] = [.models, .businessContext, .memory, .about]
        if AppSettings.showsDeveloperTools {
            panes.append(.developer)
        }
        return panes
    }

    @ViewBuilder
    private var currentPaneView: some View {
        switch selectedPane {
        case .models:
            modelsPane
        case .businessContext:
            businessContextPane
        case .memory:
            memoryPane
        case .about:
            aboutPane
        case .developer:
            developerPane
        }
    }

    func refreshDetectionStateAndDefaults() {
        // Reset local loading indicators immediately so the UI shows "checking".
        detectedClaudeAvailable = nil
        detectedCodexAvailable = nil

        // Repopulate all subprocess-backed caches on a background thread so the
        // view body never reads slow properties (e.g. `claude mcp list`) with empty
        // caches on the main thread — which was the source of AttributeGraph cycles.
        DispatchQueue.global(qos: .userInitiated).async {
            AppSettings.refreshAndPrefetchDetectionStateSync()
            DispatchQueue.main.async {
                detectionRefreshID = UUID()
            }
        }
    }
}
