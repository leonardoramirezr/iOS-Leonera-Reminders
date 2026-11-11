import SwiftUI

/// The checkboxes of a reminder on a screen of their own, with nothing else: the reminder's title and, for each
/// checkbox, its box and its title. The title stays at the top while the checkboxes scroll beneath it, in portrait
/// and in landscape.
struct ChecklistFullScreenView: View {
    /// The reminder's title, already trimmed.
    let title: String
    @Binding var items: [ChecklistItem]
    /// Called after a checkbox is checked or unchecked, so the presenter can save the change.
    let onToggle: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Keeps the lines short enough to read on wide screens (landscape, iPad).
    private static let maxContentWidth: CGFloat = 700

    /// Landscape on an iPhone: a smaller title leaves more room for the checkboxes.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach($items) { $item in
                        // Checkboxes still without a title have nothing to show next to their box.
                        if !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            row(for: $item)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(maxWidth: Self.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Outside the scroll view, so it is always visible.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if title.isEmpty {
                    Text("Sin título")
                        .foregroundStyle(.secondary)
                } else {
                    Text(title)
                }
            }
            .font(isCompactHeight ? .title3.weight(.semibold) : .title2.weight(.bold))
            .lineLimit(isCompactHeight ? 2 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
        }
        .padding(.leading)
        .padding(.trailing, 4)
        .padding(.top, isCompactHeight ? 0 : 8)
        .padding(.bottom, 4)
        .frame(maxWidth: Self.maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    /// The whole row checks or unchecks the box, not only the box.
    private func row(for item: Binding<ChecklistItem>) -> some View {
        let isDone = item.wrappedValue.isDone
        return Button {
            item.wrappedValue.isDone.toggle()
            onToggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
                Text(item.wrappedValue.title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.title3)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}
