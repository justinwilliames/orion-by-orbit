import AppKit
import Foundation
import SwiftUI

// Local versions of selected Orbit web tools (get-orbit/app/apps/*)
// chosen for a small panel form-factor:
//
//   - Sample size calculator (A/B test pre-launch math)
//   - A/B significance calculator (post-launch readout)
//   - Email size checker (Gmail 102KB clip check)
//   - Percentage calculator (X% of Y / X is what % of Y / change %)
//
// Each is a self-contained SwiftUI view hosted in its own NSPanel so
// they can be open simultaneously. Calculation logic ported directly
// from the TypeScript versions on get-orbit so results match the web
// tool to the rounding digit.

// MARK: - Generic panel host

private final class OrbitAppPanel<Content: View>: NSObject, NSWindowDelegate {
    var panel: NSPanel?

    func show(title: String, size: CGSize, content: Content) {
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.titlebarAppearsTransparent = true
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.delegate = self
        p.contentView = NSHostingView(rootView: content)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - size.width / 2
            let y = frame.midY - size.height / 2
            p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        self.panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel = nil
        return true
    }
}


// MARK: - Sample size calculator

private struct SampleSizeView: View {
    @State private var baselineRate: String = "3.5"
    @State private var mde: String = "10"
    @State private var confidence: Double = 95
    @State private var power: Double = 80
    @State private var dailyVolume: String = "10000"

    private var zAlpha: Double {
        switch Int(confidence) {
        case 90: return 1.645
        case 95: return 1.960
        case 99: return 2.576
        default: return 1.960
        }
    }

    private var zBeta: Double {
        switch Int(power) {
        case 80: return 0.842
        case 90: return 1.282
        default: return 0.842
        }
    }

    private var perArm: Int? {
        guard let p1Pct = Double(baselineRate),
              let mdePct = Double(mde),
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
        Form {
            Section("Inputs") {
                HStack {
                    Text("Baseline rate")
                    Spacer()
                    TextField("3.5", text: $baselineRate).frame(width: 100).multilineTextAlignment(.trailing)
                    Text("%").foregroundStyle(.secondary)
                }
                HStack {
                    Text("MDE (relative)")
                    Spacer()
                    TextField("10", text: $mde).frame(width: 100).multilineTextAlignment(.trailing)
                    Text("%").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Confidence")
                    Spacer()
                    Picker("", selection: $confidence) {
                        Text("90%").tag(90.0)
                        Text("95%").tag(95.0)
                        Text("99%").tag(99.0)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                }
                HStack {
                    Text("Power")
                    Spacer()
                    Picker("", selection: $power) {
                        Text("80%").tag(80.0)
                        Text("90%").tag(90.0)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                }
                HStack {
                    Text("Daily volume per arm")
                    Spacer()
                    TextField("10000", text: $dailyVolume).frame(width: 100).multilineTextAlignment(.trailing)
                }
            }
            Section("Result") {
                resultRow("Per arm", value: perArm.map { String($0.formatted(.number)) } ?? "—")
                resultRow("Total sample", value: totalSize.map { String($0.formatted(.number)) } ?? "—")
                resultRow("Duration", value: durationDays.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "—")
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
        .frame(minWidth: 380, minHeight: 420)
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
        }
    }
}

final class SampleSizeController {
    static let shared = SampleSizeController()
    private let panel = OrbitAppPanel<SampleSizeView>()
    private init() {}
    func show() {
        panel.show(title: "Sample size", size: CGSize(width: 420, height: 460), content: SampleSizeView())
    }
}


// MARK: - A/B significance

private struct SignificanceView: View {
    @State private var aVisitors: String = ""
    @State private var aConv: String = ""
    @State private var bVisitors: String = ""
    @State private var bConv: String = ""

    private struct Result {
        let rateA: Double
        let rateB: Double
        let lift: Double
        let z: Double
        let pValue: Double
        let confidence: Double
        let significant: Bool
    }

    private var result: Result? {
        guard let vA = Double(aVisitors), vA > 0,
              let cA = Double(aConv), cA >= 0,
              let vB = Double(bVisitors), vB > 0,
              let cB = Double(bConv), cB >= 0 else { return nil }
        let rateA = cA / vA
        let rateB = cB / vB
        let seA = sqrt((rateA * (1 - rateA)) / vA)
        let seB = sqrt((rateB * (1 - rateB)) / vB)
        let seDiff = sqrt(seA * seA + seB * seB)
        guard seDiff > 0 else { return nil }
        let z = (rateB - rateA) / seDiff
        let p = 2 * (1 - Self.normalCDF(abs(z)))
        let confidence = (1 - p) * 100
        let lift = rateA > 0 ? ((rateB - rateA) / rateA) * 100 : 0
        return Result(rateA: rateA, rateB: rateB, lift: lift, z: z, pValue: p,
                      confidence: confidence, significant: p < 0.05)
    }

    /// Standard normal CDF via the error function.
    static func normalCDF(_ x: Double) -> Double {
        return 0.5 * (1 + erf(x / sqrt(2)))
    }

    var body: some View {
        Form {
            Section("Control (A)") {
                pair($aVisitors, $aConv)
            }
            Section("Variant (B)") {
                pair($bVisitors, $bConv)
            }
            Section("Result") {
                if let r = result {
                    resultRow("Rate A", value: String(format: "%.2f%%", r.rateA * 100))
                    resultRow("Rate B", value: String(format: "%.2f%%", r.rateB * 100))
                    resultRow("Lift", value: String(format: "%+.2f%%", r.lift))
                    resultRow("Z", value: String(format: "%.2f", r.z))
                    resultRow("p-value", value: String(format: "%.4f", r.pValue))
                    resultRow("Confidence", value: String(format: "%.1f%%", r.confidence))
                    HStack {
                        Text("Verdict").foregroundStyle(.secondary)
                        Spacer()
                        Text(r.significant ? "Significant" : "Not significant")
                            .foregroundStyle(r.significant ? .green : .orange)
                            .fontWeight(.semibold)
                    }
                } else {
                    Text("Enter visitor + conversion counts for both arms.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 480)
    }

    @ViewBuilder
    private func pair(_ visitors: Binding<String>, _ conversions: Binding<String>) -> some View {
        HStack {
            Text("Visitors")
            Spacer()
            TextField("0", text: visitors).frame(width: 120).multilineTextAlignment(.trailing)
        }
        HStack {
            Text("Conversions")
            Spacer()
            TextField("0", text: conversions).frame(width: 120).multilineTextAlignment(.trailing)
        }
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}

final class SignificanceController {
    static let shared = SignificanceController()
    private let panel = OrbitAppPanel<SignificanceView>()
    private init() {}
    func show() {
        panel.show(title: "A/B significance", size: CGSize(width: 420, height: 520), content: SignificanceView())
    }
}


// MARK: - Email size

private struct EmailSizeView: View {
    @State private var html: String = ""

    private static let gmailClipLimit: Int = 102 * 1024

    private struct Stats {
        let bytes: Int
        let kb: Double
        let pct: Double
        let clipped: Bool
        let imageCount: Int
        let imagesMissingAlt: Int
        let stylePct: Double
        let commentBytes: Int
        let inlineDataUriCount: Int
    }

    private var stats: Stats {
        let data = html.data(using: .utf8) ?? Data()
        let bytes = data.count
        let kb = Double(bytes) / 1024.0
        let pct = min(Double(bytes) / Double(Self.gmailClipLimit) * 100.0, 100.0)
        let clipped = bytes > Self.gmailClipLimit

        // NSRegularExpression keeps the source rules portable (this code
        // can't be compile-checked locally on iCloud, so prefer the
        // bulletproof Foundation API over Swift regex literals).
        let styleBytes = bytesOfMatches(in: html, pattern: "(?is)<style[\\s\\S]*?</style>")
        let stylePct = bytes > 0 ? Double(styleBytes) / Double(bytes) * 100.0 : 0

        let commentBytes = bytesOfMatches(in: html, pattern: "<!--[\\s\\S]*?-->")
        let dataUris = countMatches(in: html, pattern: "data:image/[^\"']+")
        let imageCount = countMatches(in: html, pattern: "(?i)<img[^>]*>")
        let imagesWithAlt = countMatches(in: html, pattern: "(?i)<img[^>]*alt=[\"'][^\"']+[\"'][^>]*>")
        let imagesMissingAlt = max(0, imageCount - imagesWithAlt)

        return Stats(
            bytes: bytes, kb: kb, pct: pct, clipped: clipped,
            imageCount: imageCount, imagesMissingAlt: imagesMissingAlt,
            stylePct: stylePct, commentBytes: commentBytes,
            inlineDataUriCount: dataUris
        )
    }

    private func countMatches(in source: String, pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(source.startIndex..., in: source)
        return re.numberOfMatches(in: source, range: range)
    }

    private func bytesOfMatches(in source: String, pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(source.startIndex..., in: source)
        var total = 0
        re.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: source) else { return }
            total += source[r].utf8.count
        }
        return total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste your email HTML below. Sized against Gmail's 102KB clip threshold.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $html)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.2))

            let s = stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size:").foregroundStyle(.secondary)
                    Text(String(format: "%.1f KB", s.kb)).font(.system(.body, design: .monospaced))
                    Text("·").foregroundStyle(.secondary)
                    Text(String(format: "%.0f%% of 102KB clip limit", s.pct))
                        .foregroundStyle(s.clipped ? .red : (s.pct > 80 ? .orange : .secondary))
                }

                ProgressView(value: s.pct, total: 100)
                    .tint(s.clipped ? .red : (s.pct > 80 ? .orange : .green))

                if s.clipped {
                    Label("Gmail will clip this email. Users see a 'View entire message' link most won't click.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
                if s.stylePct > 40 {
                    Label(String(format: "CSS is %.0f%% of file. Inline critical styles, drop unused rules.", s.stylePct),
                          systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange).font(.caption)
                }
                if s.commentBytes > 1024 {
                    Label(String(format: "%.1f KB of HTML comments. Strip before sending.", Double(s.commentBytes) / 1024),
                          systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange).font(.caption)
                }
                if s.inlineDataUriCount > 0 {
                    Label("\(s.inlineDataUriCount) inline data: URI image(s). Use hosted URLs.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.caption)
                }
                if s.imagesMissingAlt > 0 {
                    Label("\(s.imagesMissingAlt) image(s) missing alt text.", systemImage: "info.circle")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 480)
    }
}

final class EmailSizeController {
    static let shared = EmailSizeController()
    private let panel = OrbitAppPanel<EmailSizeView>()
    private init() {}
    func show() {
        panel.show(title: "Email size", size: CGSize(width: 560, height: 520), content: EmailSizeView())
    }
}


// MARK: - Percentage calculator

private struct PercentageView: View {
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
            return formatPercent((xv / yv) * 100)
        case .changeFromXToY:
            guard xv != 0 else { return "—" }
            return formatPercent(((yv - xv) / abs(xv)) * 100)
        }
    }

    private var xLabel: String {
        switch mode {
        case .xOfY: return "Percentage (X)"
        case .xIsWhatPctOfY: return "Part (X)"
        case .changeFromXToY: return "From (X)"
        }
    }
    private var yLabel: String {
        switch mode {
        case .xOfY: return "Of (Y)"
        case .xIsWhatPctOfY: return "Whole (Y)"
        case .changeFromXToY: return "To (Y)"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }.pickerStyle(.menu).labelsHidden()
            }
            Section("Inputs") {
                HStack {
                    Text(xLabel)
                    Spacer()
                    TextField("0", text: $x).frame(width: 140).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text(yLabel)
                    Spacer()
                    TextField("0", text: $y).frame(width: 140).multilineTextAlignment(.trailing)
                }
            }
            Section("Result") {
                HStack {
                    Text("Answer").foregroundStyle(.secondary)
                    Spacer()
                    Text(output).font(.system(.title3, design: .monospaced)).fontWeight(.medium)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 320)
    }

    private func formatNumber(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "—"
    }
    private func formatPercent(_ v: Double) -> String {
        return String(format: "%.2f%%", v)
    }
}

final class PercentageController {
    static let shared = PercentageController()
    private let panel = OrbitAppPanel<PercentageView>()
    private init() {}
    func show() {
        panel.show(title: "Percentage", size: CGSize(width: 420, height: 360), content: PercentageView())
    }
}


// MARK: - Web tool launcher

/// The remaining Orbit web apps that are too big or too UI-heavy to
/// port cleanly into a small floating panel. Surfaced in the menu as
/// "open in browser" entries (with the ↗ suffix) so the toolbox
/// doesn't pretend the local set is the whole list. Each opens
/// `https://get.yourorbit.team/apps/<slug>` in the user's default
/// browser.
enum OrbitWebTools {
    /// Display name → slug. Order is the menu order.
    static let entries: [(name: String, slug: String)] = [
        ("Subject line scorer", "subject-line"),
        ("Slop detector", "slop-detector"),
        ("Push notification preview", "push-preview"),
        ("IP warmup planner", "ip-warmup"),
        ("LTV / payback calculator", "ltv-payback"),
        ("Deliverability check", "deliverability"),
        ("Liquid template builder", "liquid-builder"),
        ("Liquid date helpers", "liquid-dates"),
        ("Braze name generator", "namer"),
    ]

    static func open(slug: String) {
        guard let url = URL(string: "https://get.yourorbit.team/apps/\(slug)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAppsIndex() {
        guard let url = URL(string: "https://get.yourorbit.team/apps") else { return }
        NSWorkspace.shared.open(url)
    }
}
