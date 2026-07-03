import AppKit
import SwiftUI

// MARK: - Sidebar row

struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: pane.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.headline)
                    Text(pane.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header

struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Section card container

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .settingsCaption()
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Info row

struct SettingsInfoRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(text)
                .settingsCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status pill

struct SettingsStatusPill: View {
    enum Tone {
        case accent
        case warning
        case neutral
    }

    let title: String
    let systemImage: String
    let tone: Tone

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor, in: Capsule(style: .continuous))
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent: return .accentColor.opacity(0.12)
        case .warning: return Color.orange.opacity(0.14)
        case .neutral: return Color.primary.opacity(0.06)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent: return .accentColor
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }
}

// MARK: - Model picker row

struct LabeledModelPicker: View {
    let title: String
    @Binding var selection: String
    let options: [(label: String, value: String)]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 110, alignment: .leading)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Text modifier

extension Text {
    func settingsCaption() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
