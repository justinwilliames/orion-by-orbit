import AppKit
import Foundation
import SwiftUI

// In-popover toolbox overlay. Surfaces all of Orion's productivity
// tools and the Orbit apps catalogue inside the chat popover (no
// floating panels, no right-click menu navigation). Web tools open
// in the browser; everything else has a SwiftUI detail view that
// fills the popover content area.
//
// Architecture:
//   - `ToolboxRootView` owns the picker / detail state machine.
//   - `ToolboxHost` is the AppKit-side controller that wraps the
//     SwiftUI hierarchy in an NSHostingView and adds it to the
//     popover container.
//
// Visual style mirrors get-orbit/app/apps/*: card-based layout,
// rounded surfaces, monospaced numbers in accent colours, secondary
// labels in a muted tone.

// MARK: - Tool identity

enum ToolID: Hashable, Identifiable {
    case pomodoro
    case quickNote
    case viewNotes
    case sampleSize
    case significance
    case emailSize
    case percentage
    /// Web-only tools — clicking the card opens yourorbit.team
    /// rather than navigating to a detail view.
    case web(slug: String, title: String)

    var id: String {
        switch self {
        case .pomodoro:        return "pomodoro"
        case .quickNote:       return "quickNote"
        case .viewNotes:       return "viewNotes"
        case .sampleSize:      return "sampleSize"
        case .significance:    return "significance"
        case .emailSize:       return "emailSize"
        case .percentage:      return "percentage"
        case .web(let s, _):   return "web:\(s)"
        }
    }

    var title: String {
        switch self {
        case .pomodoro:        return "Pomodoro"
        case .quickNote:       return "Quick note"
        case .viewNotes:       return "Past notes"
        case .sampleSize:      return "Sample size"
        case .significance:    return "A/B significance"
        case .emailSize:       return "Email size"
        case .percentage:      return "Percentage"
        case .web(_, let t):   return t
        }
    }

    var icon: String {
        switch self {
        case .pomodoro:        return "timer"
        case .quickNote:       return "square.and.pencil"
        case .viewNotes:       return "tray.full"
        case .sampleSize:      return "chart.bar.xaxis"
        case .significance:    return "checkmark.seal"
        case .emailSize:       return "envelope"
        case .percentage:      return "percent"
        case .web:             return "arrow.up.right.square"
        }
    }

    var subtitle: String {
        switch self {
        case .pomodoro:        return "25 / 5 focus + break cycle"
        case .quickNote:       return "Capture a thought to today's note"
        case .viewNotes:       return "Browse + edit daily notes"
        case .sampleSize:      return "A/B test pre-launch math"
        case .significance:    return "Read a test for significance"
        case .emailSize:       return "Gmail 102KB clip check"
        case .percentage:      return "Three-mode % calculator"
        case .web:             return "Opens in browser"
        }
    }

    var isExternal: Bool {
        if case .web = self { return true }
        return false
    }
}


// MARK: - Root view (state machine)

struct ToolboxRootView: View {
    @State private var selection: ToolID? = nil
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if selection != nil {
                Button {
                    selection = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Tools")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(selection?.title ?? "Toolbox")
                .font(.headline)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let sel = selection {
            detail(for: sel)
        } else {
            ToolPickerView { picked in
                if picked.isExternal, case .web(let slug, _) = picked {
                    WebToolOpener.open(slug: slug)
                } else {
                    selection = picked
                }
            }
        }
    }

    @ViewBuilder
    private func detail(for id: ToolID) -> some View {
        switch id {
        case .pomodoro:        PomodoroToolView()
        case .quickNote:       QuickNoteToolView()
        case .viewNotes:       NotesToolView()
        case .sampleSize:      SampleSizeToolView()
        case .significance:    SignificanceToolView()
        case .emailSize:       EmailSizeToolView()
        case .percentage:      PercentageToolView()
        case .web:             EmptyView()
        }
    }
}


// MARK: - Picker

private struct ToolPickerView: View {
    var onSelect: (ToolID) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Productivity", tools: [.pomodoro, .quickNote, .viewNotes])
                section("Calculators", tools: [.sampleSize, .significance, .emailSize, .percentage])
                webSection
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(_ title: String, tools: [ToolID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(tools, id: \.self) { tool in
                    ToolCardButton(tool: tool, action: { onSelect(tool) })
                }
            }
        }
    }

    private var webSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On the web")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WebToolOpener.entries, id: \.slug) { entry in
                    let id = ToolID.web(slug: entry.slug, title: entry.name)
                    ToolCardButton(tool: id, action: { onSelect(id) })
                }
                Button {
                    WebToolOpener.openIndex()
                } label: {
                    cardChrome(title: "All Orbit apps", subtitle: "View the full catalogue", icon: "square.grid.2x2", external: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cardChrome(title: String, subtitle: String, icon: String, external: Bool) -> some View {
        ToolCardChrome(title: title, subtitle: subtitle, icon: icon, external: external)
    }
}

private struct ToolCardButton: View {
    let tool: ToolID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolCardChrome(
                title: tool.title,
                subtitle: tool.subtitle,
                icon: tool.icon,
                external: tool.isExternal
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ToolCardChrome: View {
    let title: String
    let subtitle: String
    let icon: String
    let external: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if external {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}


// MARK: - Reusable result chrome

private struct ResultCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
        )
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var emphasis: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: emphasis ? 18 : 13,
                              weight: emphasis ? .semibold : .regular,
                              design: .monospaced))
                .foregroundStyle(emphasis ? Color.accentColor : .primary)
        }
    }
}


// MARK: - Pomodoro

private struct PomodoroToolView: View {
    @State private var tickToken: Int = 0
    private var pomo: PomodoroController { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Classic 25/5 cycle. Long rest every 4th focus phase. Sleeps Orion during rest; keeps him awake while focusing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                ResultCard(title: "Now") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pomo.phase == .idle ? "Idle" : pomo.menuTitle.replacingOccurrences(of: "Stop Pomodoro (", with: "").replacingOccurrences(of: ")", with: ""))
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tintColor)
                        if let endsAt = pomo.phaseEndsAt {
                            Text("Phase ends at \(timeFormatter.string(from: endsAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Click Start to begin a 25-minute focus phase.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(action: {
                    pomo.toggle()
                    tickToken &+= 1
                }) {
                    HStack {
                        Image(systemName: pomo.isRunning ? "stop.fill" : "play.fill")
                        Text(pomo.isRunning ? "Stop" : "Start focus")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(pomo.isRunning ? .red : Color.accentColor)
            }
            .padding(16)
        }
        .id(tickToken)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickToken &+= 1
        }
    }

    private var tintColor: Color {
        switch pomo.phase {
        case .focus:                       return .red
        case .shortBreak, .longBreak:      return .green
        case .idle:                        return .primary
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }
}


// MARK: - Quick note (inline)

private struct QuickNoteToolView: View {
    @State private var draft: String = ""
    @State private var savedAt: Date? = nil
    @FocusState private var editorFocused: Bool

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captured to ~/Orbit/notes/\(today).md, one timestamped line per save.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .focused($editorFocused)

            if let savedAt {
                Text("Saved at \(savedTimeString(savedAt))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button("Save") {
                    QuickNoteStorage.append(text: draft)
                    savedAt = Date()
                    draft = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .onAppear { editorFocused = true }
    }

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func savedTimeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: d)
    }
}

/// Append-only storage helper used by both QuickNoteToolView (inline)
/// and the right-click flow (legacy). Single source of truth for the
/// note-file format.
enum QuickNoteStorage {
    static func append(text raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Orbit")
            .appendingPathComponent("notes")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let day = dayFmt.string(from: Date())
        let stamp = timeFmt.string(from: Date())
        let body = text
            .components(separatedBy: "\n")
            .enumerated()
            .map { i, line in i == 0 ? line : "  \(line)" }
            .joined(separator: "\n")
        let entry = "- \(stamp) — \(body)\n"
        let file = dir.appendingPathComponent("\(day).md")

        if let data = entry.data(using: .utf8) {
            if fm.fileExists(atPath: file.path),
               let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                let header = "# Notes — \(day)\n\n".data(using: .utf8) ?? Data()
                try? (header + data).write(to: file)
            }
        }
    }
}


// MARK: - Notes browser (inline)

private struct NotesToolView: View {
    @StateObject private var store = NotesStore()
    @State private var selectedDay: String?
    @State private var draft: String = ""
    @State private var dirty: Bool = false
    @State private var showDelete: Bool = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 140, idealWidth: 180)
            editor.frame(minWidth: 320)
        }
        .onAppear {
            if selectedDay == nil { selectedDay = store.days.first }
            loadDraft()
        }
        .onChange(of: selectedDay) { _, _ in loadDraft() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload from disk")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if store.days.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                    Text("No notes yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedDay) {
                    ForEach(store.days, id: \.self) { day in
                        Text(day)
                            .font(.system(.caption, design: .monospaced))
                            .tag(day)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let day = selectedDay {
                HStack {
                    Text(day)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                    if dirty {
                        Text("• unsaved").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Save") {
                        store.save(day: day, content: draft)
                        dirty = false
                    }
                    .keyboardShortcut("s")
                    .disabled(!dirty)
                    Button(role: .destructive) {
                        showDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider()
                TextEditor(text: $draft)
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .onChange(of: draft) { _, _ in dirty = true }
            } else {
                Text("Select a day from the sidebar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "Delete this day's notes?",
            isPresented: $showDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let day = selectedDay {
                    store.delete(day: day)
                    selectedDay = store.days.first
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func loadDraft() {
        if let d = selectedDay { draft = store.read(day: d) } else { draft = "" }
        dirty = false
    }
}


// MARK: - Sample size

private struct SampleSizeToolView: View {
    @State private var baseline: String = "3.5"
    @State private var mde: String = "10"
    @State private var confidence: Double = 95
    @State private var power: Double = 80
    @State private var dailyVolume: String = "10000"

    private var zAlpha: Double {
        switch Int(confidence) { case 90: return 1.645; case 99: return 2.576; default: return 1.96 }
    }
    private var zBeta: Double {
        Int(power) == 90 ? 1.282 : 0.842
    }

    private var perArm: Int? {
        guard let p1Pct = Double(baseline), let mdePct = Double(mde),
              p1Pct > 0, p1Pct < 100, mdePct > 0 else { return nil }
        let p1 = p1Pct / 100
        let p2 = min(0.9999, p1 * (1 + mdePct / 100))
        let num = pow(zAlpha + zBeta, 2) * (p1 * (1 - p1) + p2 * (1 - p2))
        let den = pow(p1 - p2, 2)
        guard den > 0 else { return nil }
        return Int(ceil(num / den))
    }

    private var totalSize: Int? { perArm.map { $0 * 2 } }
    private var durationDays: Int? {
        guard let total = totalSize, let daily = Double(dailyVolume), daily > 0 else { return nil }
        return Int(ceil(Double(total) / daily))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inputCard
                resultCard
            }
            .padding(16)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Inputs")
            inputRow("Baseline rate", binding: $baseline, suffix: "%")
            inputRow("MDE (relative)", binding: $mde, suffix: "%")
            HStack {
                Text("Confidence").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $confidence) {
                    Text("90%").tag(90.0); Text("95%").tag(95.0); Text("99%").tag(99.0)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
            }
            HStack {
                Text("Power").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $power) {
                    Text("80%").tag(80.0); Text("90%").tag(90.0)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
            }
            inputRow("Daily volume per arm", binding: $dailyVolume, suffix: "")
        }
    }

    private var resultCard: some View {
        ResultCard(title: "Result") {
            VStack(spacing: 8) {
                StatRow(label: "Per arm", value: perArm.map { $0.formatted(.number) } ?? "—", emphasis: true)
                StatRow(label: "Total sample", value: totalSize.map { $0.formatted(.number) } ?? "—")
                StatRow(label: "Duration", value: durationDays.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "—")
            }
        }
    }

    private func sectionHeader(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func inputRow(_ label: String, binding: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            TextField("", text: binding)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            if !suffix.isEmpty {
                Text(suffix).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - A/B Significance

private struct SignificanceToolView: View {
    @State private var aV: String = ""
    @State private var aC: String = ""
    @State private var bV: String = ""
    @State private var bC: String = ""

    private struct R {
        let rateA: Double; let rateB: Double; let lift: Double
        let z: Double; let p: Double; let conf: Double; let sig: Bool
    }

    private var r: R? {
        guard let vA = Double(aV), vA > 0,
              let cA = Double(aC), cA >= 0,
              let vB = Double(bV), vB > 0,
              let cB = Double(bC), cB >= 0 else { return nil }
        let rA = cA / vA, rB = cB / vB
        let seA = sqrt((rA * (1 - rA)) / vA), seB = sqrt((rB * (1 - rB)) / vB)
        let se = sqrt(seA * seA + seB * seB)
        guard se > 0 else { return nil }
        let z = (rB - rA) / se
        let p = 2 * (1 - 0.5 * (1 + erf(abs(z) / sqrt(2))))
        let conf = (1 - p) * 100
        let lift = rA > 0 ? ((rB - rA) / rA) * 100 : 0
        return R(rateA: rA, rateB: rB, lift: lift, z: z, p: p, conf: conf, sig: p < 0.05)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pairCard(title: "Control (A)", visitors: $aV, conversions: $aC)
                pairCard(title: "Variant (B)", visitors: $bV, conversions: $bC)
                resultBlock
            }
            .padding(16)
        }
    }

    private func pairCard(title: String, visitors: Binding<String>, conversions: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            HStack {
                Text("Visitors").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: visitors)
                    .frame(width: 130)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Conversions").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: conversions)
                    .frame(width: 130)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        ResultCard(title: "Result") {
            if let r {
                VStack(spacing: 8) {
                    StatRow(label: "Rate A", value: pct(r.rateA))
                    StatRow(label: "Rate B", value: pct(r.rateB))
                    StatRow(label: "Lift", value: signed(r.lift))
                    StatRow(label: "Z", value: String(format: "%.2f", r.z))
                    StatRow(label: "p-value", value: String(format: "%.4f", r.p))
                    StatRow(label: "Confidence", value: String(format: "%.1f%%", r.conf), emphasis: true)
                    HStack {
                        Text("Verdict").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text(r.sig ? "Significant" : "Not yet")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(r.sig ? .green : .orange)
                    }
                }
            } else {
                Text("Enter visitor + conversion counts for both arms.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pct(_ v: Double) -> String { String(format: "%.2f%%", v * 100) }
    private func signed(_ v: Double) -> String { String(format: "%+.2f%%", v) }
}


// MARK: - Email size

private struct EmailSizeToolView: View {
    @State private var html: String = ""
    private static let limit: Int = 102 * 1024

    private struct Stats {
        let bytes: Int; let kb: Double; let pct: Double; let clipped: Bool
        let imageCount: Int; let imagesMissingAlt: Int; let stylePct: Double
        let commentBytes: Int; let dataUriCount: Int
    }

    private var stats: Stats {
        let data = html.data(using: .utf8) ?? Data()
        let bytes = data.count
        let kb = Double(bytes) / 1024
        let pct = min(Double(bytes) / Double(Self.limit) * 100, 100)
        let clipped = bytes > Self.limit
        let styleBytes = matchedBytes(html, "(?is)<style[\\s\\S]*?</style>")
        let stylePct = bytes > 0 ? Double(styleBytes) / Double(bytes) * 100 : 0
        let commentBytes = matchedBytes(html, "<!--[\\s\\S]*?-->")
        let dataUris = countMatches(html, "data:image/[^\"']+")
        let imgs = countMatches(html, "(?i)<img[^>]*>")
        let imgsAlt = countMatches(html, "(?i)<img[^>]*alt=[\"'][^\"']+[\"'][^>]*>")
        return Stats(bytes: bytes, kb: kb, pct: pct, clipped: clipped,
                     imageCount: imgs, imagesMissingAlt: max(0, imgs - imgsAlt),
                     stylePct: stylePct, commentBytes: commentBytes, dataUriCount: dataUris)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste the email's HTML to size against Gmail's 102KB clip threshold.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextEditor(text: $html)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                let s = stats
                ResultCard(title: "Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        StatRow(label: "Size",
                                value: String(format: "%.1f KB", s.kb),
                                emphasis: true)
                        StatRow(label: "Of clip limit",
                                value: String(format: "%.0f%%", s.pct))
                        ProgressView(value: s.pct, total: 100)
                            .tint(s.clipped ? .red : (s.pct > 80 ? .orange : .green))
                        if s.clipped {
                            Label("Gmail will clip this email.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.red)
                        }
                        if s.stylePct > 40 {
                            Label(String(format: "CSS is %.0f%% of file.", s.stylePct), systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if s.commentBytes > 1024 {
                            Label(String(format: "%.1f KB of HTML comments.", Double(s.commentBytes) / 1024), systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if s.dataUriCount > 0 {
                            Label("\(s.dataUriCount) inline data: URI image(s).", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.red)
                        }
                        if s.imagesMissingAlt > 0 {
                            Label("\(s.imagesMissingAlt) image(s) missing alt text.", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func countMatches(_ s: String, _ p: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: p) else { return 0 }
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }
    private func matchedBytes(_ s: String, _ p: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: p) else { return 0 }
        var total = 0
        re.enumerateMatches(in: s, range: NSRange(s.startIndex..., in: s)) { m, _, _ in
            guard let m, let r = Range(m.range, in: s) else { return }
            total += s[r].utf8.count
        }
        return total
    }
}


// MARK: - Percentage

private struct PercentageToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case xOfY = "X% of Y"
        case xIsWhatPctOfY = "X is what % of Y"
        case changeFromXToY = "% change X → Y"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .xOfY
    @State private var x: String = ""
    @State private var y: String = ""

    private var output: String {
        guard let xv = Double(x), let yv = Double(y) else { return "—" }
        switch mode {
        case .xOfY:
            return formatNumber(yv * (xv / 100))
        case .xIsWhatPctOfY:
            guard yv != 0 else { return "—" }
            return String(format: "%.2f%%", (xv / yv) * 100)
        case .changeFromXToY:
            guard xv != 0 else { return "—" }
            return String(format: "%.2f%%", ((yv - xv) / abs(xv)) * 100)
        }
    }

    private var xLabel: String {
        switch mode { case .xOfY: return "Percentage (X)"; case .xIsWhatPctOfY: return "Part (X)"; case .changeFromXToY: return "From (X)" }
    }
    private var yLabel: String {
        switch mode { case .xOfY: return "Of (Y)"; case .xIsWhatPctOfY: return "Whole (Y)"; case .changeFromXToY: return "To (Y)" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Inputs").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    HStack {
                        Text(xLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        TextField("0", text: $x).frame(width: 130).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text(yLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        TextField("0", text: $y).frame(width: 130).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    }
                }

                ResultCard(title: "Answer") {
                    HStack {
                        Spacer()
                        Text(output)
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
    }

    private func formatNumber(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        return f.string(from: NSNumber(value: v)) ?? "—"
    }
}


// MARK: - Web tool opener

enum WebToolOpener {
    struct Entry {
        let name: String
        let slug: String
    }

    static let entries: [Entry] = [
        Entry(name: "Subject line scorer", slug: "subject-line"),
        Entry(name: "Slop detector", slug: "slop-detector"),
        Entry(name: "Push preview", slug: "push-preview"),
        Entry(name: "IP warmup", slug: "ip-warmup"),
        Entry(name: "LTV / payback", slug: "ltv-payback"),
        Entry(name: "Deliverability", slug: "deliverability"),
        Entry(name: "Liquid builder", slug: "liquid-builder"),
        Entry(name: "Liquid dates", slug: "liquid-dates"),
        Entry(name: "Braze namer", slug: "namer"),
    ]

    static func open(slug: String) {
        guard let url = URL(string: "https://yourorbit.team/apps/\(slug)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openIndex() {
        guard let url = URL(string: "https://yourorbit.team/apps") else { return }
        NSWorkspace.shared.open(url)
    }
}


// MARK: - AppKit host

/// Wraps `ToolboxRootView` in an NSHostingView and hands the popover
/// a single overlay subview that can be added/removed. The popover
/// keeps its existing chat scroll view + composer; we just stack the
/// hosting view on top of them when active.
@MainActor
final class ToolboxOverlay {
    let hostingView: NSHostingView<ToolboxRootView>

    init(onClose: @escaping () -> Void) {
        let root = ToolboxRootView(onClose: onClose)
        hostingView = NSHostingView(rootView: root)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
    }
}
