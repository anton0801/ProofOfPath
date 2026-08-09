//
//  POPFields.swift
//  ProofOfPath
//
//  Form controls with validation states baked in.
//

import SwiftUI

// MARK: - Field shell

struct POPFieldShell<Content: View>: View {
    let label: String
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var counter: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
                if isRequired {
                    Text("Required")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(POPColor.brandOrange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(POPColor.warningSoft))
                }
                Spacer(minLength: 0)
                if let counter {
                    Text(counter)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(POPColor.inkTertiary)
                }
            }

            content()

            if let errorText, !errorText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10, weight: .bold))
                    Text(errorText).font(POPFont.caption)
                }
                .foregroundStyle(POPColor.danger)
                .fixedSize(horizontal: false, vertical: true)
            } else if let hint, !hint.isEmpty {
                Text(hint)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Text field

struct POPTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var characterLimit: Int?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true
    var submitLabel: SubmitLabel = .done

    private var hasError: Bool { !(errorText ?? "").isEmpty }

    var body: some View {
        POPFieldShell(
            label: label,
            isRequired: isRequired,
            hint: hint,
            errorText: errorText,
            counter: characterLimit.map { "\(text.count)/\($0)" }
        ) {
            TextField(placeholder, text: Binding(
                get: { text },
                set: { newValue in
                    if let limit = characterLimit, newValue.count > limit {
                        text = String(newValue.prefix(limit))
                    } else {
                        text = newValue
                    }
                }
            ))
            .font(POPFont.body)
            .foregroundStyle(POPColor.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(!autocorrect)
            .submitLabel(submitLabel)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(hasError ? POPColor.danger : POPColor.hairline, lineWidth: hasError ? 1.4 : 1)
            )
        }
    }
}

// MARK: - Multi-line text

struct POPTextEditor: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var characterLimit: Int? = 1200
    var minHeight: CGFloat = 96

    private var hasError: Bool { !(errorText ?? "").isEmpty }

    var body: some View {
        POPFieldShell(
            label: label,
            isRequired: isRequired,
            hint: hint,
            errorText: errorText,
            counter: characterLimit.map { "\(text.count)/\($0)" }
        ) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(POPFont.body)
                        .foregroundStyle(POPColor.inkTertiary)
                        .padding(.horizontal, 13)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { text },
                    set: { newValue in
                        if let limit = characterLimit, newValue.count > limit {
                            text = String(newValue.prefix(limit))
                        } else {
                            text = newValue
                        }
                    }
                ))
                .font(POPFont.body)
                .foregroundStyle(POPColor.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minHeight: minHeight)
            }
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(hasError ? POPColor.danger : POPColor.hairline, lineWidth: hasError ? 1.4 : 1)
            )
        }
    }
}

// MARK: - Numeric field

struct POPNumberField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = "0"
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var prefix: String?
    var suffix: String?
    var allowsDecimal: Bool = true

    private var hasError: Bool { !(errorText ?? "").isEmpty }

    var body: some View {
        POPFieldShell(label: label, isRequired: isRequired, hint: hint, errorText: errorText) {
            HStack(spacing: 6) {
                if let prefix {
                    Text(prefix)
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.inkSecondary)
                }
                TextField(placeholder, text: $text)
                    .font(POPFont.body)
                    .foregroundStyle(POPColor.ink)
                    .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                    .autocorrectionDisabled()
                if let suffix {
                    Text(suffix)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(hasError ? POPColor.danger : POPColor.hairline, lineWidth: hasError ? 1.4 : 1)
            )
        }
    }
}

// MARK: - Segmented option picker

struct POPSegmentedPicker<T: Hashable & Identifiable>: View {
    let label: String
    let options: [T]
    @Binding var selection: T
    let titleFor: (T) -> String
    var iconFor: ((T) -> String?)?
    var hint: String?
    var columns: Int = 2

    var body: some View {
        POPFieldShell(label: label, hint: hint) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button(action: {
                        Haptics.selection()
                        selection = option
                    }) {
                        HStack(spacing: 6) {
                            if let iconFor, let icon = iconFor(option) {
                                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                            }
                            Text(titleFor(option))
                                .font(POPFont.calloutMedium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(isSelected ? POPColor.graphite : POPColor.inkSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                                .fill(isSelected ? POPColor.brandYellow : POPColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                                .strokeBorder(isSelected ? POPColor.brandOrange.opacity(0.5) : POPColor.hairline, lineWidth: isSelected ? 1.4 : 1)
                        )
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
        }
    }
}

// MARK: - Inline segmented control (3 items max)

struct POPInlineSegments<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let titleFor: (T) -> String
    var tintFor: ((T) -> Color)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                let tint = tintFor?(option) ?? POPColor.brandOrange
                Button(action: {
                    Haptics.selection()
                    selection = option
                }) {
                    Text(titleFor(option))
                        .font(POPFont.captionMedium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? POPColor.graphite : POPColor.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? tint.opacity(0.22) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1.2)
                        )
                }
                .buttonStyle(POPPressStyle())
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surfaceMuted))
    }
}

// MARK: - Optional date field

struct POPDateField: View {
    let label: String
    @Binding var date: Date?
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var range: PartialRangeFrom<Date>?
    var clearTitle: String = "No date"

    @State private var isEditing = false

    var body: some View {
        POPFieldShell(label: label, isRequired: isRequired, hint: hint, errorText: errorText) {
            VStack(spacing: 8) {
                Button(action: {
                    Haptics.tap()
                    if date == nil {
                        date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
                        isEditing = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                        Text(date.map { POPFormat.date($0) } ?? clearTitle)
                            .font(POPFont.body)
                            .foregroundStyle(date == nil ? POPColor.inkTertiary : POPColor.ink)
                        Spacer(minLength: 0)
                        if date != nil {
                            Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(POPColor.inkTertiary)
                        } else {
                            Text("Set")
                                .font(POPFont.captionMedium)
                                .foregroundStyle(POPColor.brandOrange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                            .strokeBorder(!(errorText ?? "").isEmpty ? POPColor.danger : POPColor.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(POPPressStyle())

                if isEditing, date != nil {
                    VStack(spacing: 8) {
                        if let range {
                            DatePicker("", selection: Binding(
                                get: { date ?? Date() },
                                set: { date = $0 }
                            ), in: range, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(POPColor.brandOrange)
                        } else {
                            DatePicker("", selection: Binding(
                                get: { date ?? Date() },
                                set: { date = $0 }
                            ), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(POPColor.brandOrange)
                        }

                        HStack {
                            POPTextButton(title: "Clear date", icon: "xmark.circle", tint: POPColor.danger) {
                                date = nil
                                isEditing = false
                            }
                            Spacer()
                            POPTextButton(title: "Done", icon: "checkmark") {
                                withAnimation(.easeInOut(duration: 0.18)) { isEditing = false }
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Rating picker

struct POPRatingPicker: View {
    @Binding var rating: Int?
    let scaleMax: Int
    var allowsClear: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...max(2, scaleMax), id: \.self) { value in
                    Button(action: {
                        Haptics.selection()
                        rating = (rating == value && allowsClear) ? nil : value
                    }) {
                        Text("\(value)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle((rating ?? 0) >= value ? POPColor.graphite : POPColor.inkTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill((rating ?? 0) >= value ? POPColor.brandYellow : POPColor.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(rating == value ? POPColor.brandOrange : POPColor.hairline,
                                                  lineWidth: rating == value ? 2 : 1)
                            )
                    }
                    .buttonStyle(POPPressStyle())
                    .accessibilityLabel(Text("Rate \(value) of \(scaleMax)"))
                }
            }
            HStack {
                Text("Worst")
                    .font(.system(size: 10.5))
                    .foregroundStyle(POPColor.inkTertiary)
                Spacer()
                if rating != nil && allowsClear {
                    Button(action: {
                        Haptics.tap()
                        rating = nil
                    }) {
                        Text("Clear rating")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                    }
                }
                Spacer()
                Text("Best")
                    .font(.system(size: 10.5))
                    .foregroundStyle(POPColor.inkTertiary)
            }
        }
    }
}

// MARK: - Yes / No picker

struct POPYesNoPicker: View {
    @Binding var value: Bool?

    var body: some View {
        HStack(spacing: 8) {
            picker(title: "Yes", isOn: value == true, tint: POPColor.success) {
                value = (value == true) ? nil : true
            }
            picker(title: "No", isOn: value == false, tint: POPColor.danger) {
                value = (value == false) ? nil : false
            }
        }
    }

    private func picker(title: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(title).font(POPFont.bodyMedium)
            }
            .foregroundStyle(isOn ? tint : POPColor.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                .fill(isOn ? tint.opacity(0.1) : POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                .strokeBorder(isOn ? tint.opacity(0.5) : POPColor.hairline, lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(POPPressStyle())
    }
}

// MARK: - Toggle row

struct POPToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(POPColor.warningSoft))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(POPFont.bodyMedium)
                    .foregroundStyle(POPColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(POPColor.brandOrange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Navigation-style row

struct POPActionRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconTint: Color = POPColor.brandOrange
    var iconBackground: Color = POPColor.warningSoft
    var value: String?
    var showsChevron: Bool = true
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isDestructive ? POPColor.danger : iconTint)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDestructive ? POPColor.dangerSoft : iconBackground))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(isDestructive ? POPColor.danger : POPColor.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.inkSecondary)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(POPPressStyle())
    }
}

// MARK: - Menu-style picker row

struct POPMenuPicker<T: Hashable & Identifiable>: View {
    let label: String
    let options: [T]
    @Binding var selection: T
    let titleFor: (T) -> String
    var hint: String?
    var iconFor: ((T) -> String?)?

    var body: some View {
        POPFieldShell(label: label, hint: hint) {
            Menu {
                ForEach(options) { option in
                    Button(action: {
                        Haptics.selection()
                        selection = option
                    }) {
                        if selection == option {
                            Label(titleFor(option), systemImage: "checkmark")
                        } else {
                            Text(titleFor(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let iconFor, let icon = iconFor(selection) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                    }
                    Text(titleFor(selection))
                        .font(POPFont.body)
                        .foregroundStyle(POPColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(POPColor.hairline, lineWidth: 1))
            }
        }
    }
}

// MARK: - Search field

struct POPSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(POPColor.inkTertiary)
            TextField(placeholder, text: $text)
                .font(POPFont.body)
                .foregroundStyle(POPColor.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button(action: {
                    Haptics.tap()
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(POPColor.inkTertiary)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
            .strokeBorder(POPColor.hairline, lineWidth: 1))
    }
}
