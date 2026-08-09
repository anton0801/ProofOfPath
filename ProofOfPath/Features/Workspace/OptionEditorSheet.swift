//
//  OptionEditorSheet.swift
//  ProofOfPath
//

import SwiftUI
import PhotosUI

struct OptionEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let existing: DecisionOption?

    @State private var name = ""
    @State private var provider = ""
    @State private var costText = ""
    @State private var recurringText = ""
    @State private var recurringPeriod: CostPeriod = .monthly
    @State private var website = ""
    @State private var contact = ""
    @State private var availability = ""
    @State private var keyDetails = ""
    @State private var status: OptionStatus = .researching
    @State private var imageFileName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingImage = false
    @State private var attachmentError: String?
    @State private var showValidation = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var currency: String { decision?.currencyCode ?? "USD" }

    private var cost: Double? { POPFormat.parseNumber(costText) }
    private var recurring: Double? { POPFormat.parseNumber(recurringText) }

    private var nameError: String? {
        guard showValidation else { return nil }
        return name.popIsBlank ? "The option needs a name." : nil
    }

    private var duplicateWarning: String? {
        guard let decision, !name.popIsBlank else { return nil }
        let duplicate = decision.options.contains {
            $0.id != existing?.id && $0.name.popNormalizedForCompare == name.popNormalizedForCompare
        }
        return duplicate ? "An option with this name already exists in this decision." : nil
    }

    private var costError: String? {
        guard !costText.popIsBlank else { return nil }
        guard let cost else { return "Cost must be a number." }
        return cost < 0 ? "Cost cannot be negative." : nil
    }

    private var recurringError: String? {
        guard !recurringText.popIsBlank else { return nil }
        guard let recurring else { return "Recurring cost must be a number." }
        return recurring < 0 ? "Recurring cost cannot be negative." : nil
    }

    private var isValid: Bool {
        !name.popIsBlank && costError == nil && recurringError == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    imageSection

                    POPTextField(
                        label: "Option Name",
                        text: $name,
                        placeholder: "e.g. Bosch Serie 6 KGN39",
                        isRequired: true,
                        errorText: nameError,
                        characterLimit: 80
                    )

                    if let duplicateWarning {
                        POPBanner(kind: .warning, message: duplicateWarning,
                                  detail: "You can still save it — just make sure you can tell them apart.")
                    }

                    POPTextField(label: "Provider or Brand", text: $provider,
                                 placeholder: "Who supplies it?", characterLimit: 60)

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Cost", icon: "banknote")
                        POPNumberField(
                            label: "Estimated Cost",
                            text: $costText,
                            hint: budgetHint,
                            errorText: costError,
                            prefix: POPFormat.currencySymbol(for: currency)
                        )
                        HStack(alignment: .top, spacing: 10) {
                            POPNumberField(
                                label: "Recurring Cost",
                                text: $recurringText,
                                errorText: recurringError,
                                prefix: POPFormat.currencySymbol(for: currency)
                            )
                            POPMenuPicker(
                                label: "Period",
                                options: CostPeriod.allCases,
                                selection: $recurringPeriod,
                                titleFor: { $0.title }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Where to Find It", icon: "link")
                        POPTextField(label: "Website", text: $website,
                                     placeholder: "https://",
                                     hint: "Stored as you type it. The app never opens or checks links by itself.",
                                     keyboard: .URL, capitalization: .never, autocorrect: false)
                        POPTextField(label: "Contact Details", text: $contact,
                                     placeholder: "Phone, email or shop", characterLimit: 120)
                        POPTextField(label: "Availability", text: $availability,
                                     placeholder: "e.g. In stock, 3 week lead time", characterLimit: 120)
                    }

                    POPTextEditor(
                        label: "Key Details",
                        text: $keyDetails,
                        placeholder: "Specs, conditions, anything you keep re-checking.",
                        characterLimit: 1000,
                        minHeight: 100
                    )

                    POPSegmentedPicker(
                        label: "Current Status",
                        options: OptionStatus.allCases.filter { $0 != .selected || existing?.status == .selected },
                        selection: $status,
                        titleFor: { $0.title },
                        iconFor: { $0.icon },
                        columns: 2
                    )

                    if existing == nil, let decision, !decision.criteria.isEmpty {
                        POPInlineNote(text: "This option will start as Not Evaluated on all \(decision.criteria.count) criteria.")
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add Option" : "Edit Option")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save Option") { save() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(isValid ? POPColor.brandOrange : POPColor.inkTertiary)
                }
            }
        }
        .onAppear(perform: hydrate)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            loadPhoto(newItem)
        }
    }

    private var budgetHint: String? {
        guard let decision, let cost else { return nil }
        switch CostEngine.budgetFit(for: previewOption(cost: cost), decision: decision) {
        case .above: return "Above your budget range."
        case .below: return "Below your budget range."
        case .inside: return "Inside your budget range."
        case .unknown, .noBudgetSet: return nil
        }
    }

    private func previewOption(cost: Double) -> DecisionOption {
        var option = existing ?? DecisionOption()
        option.estimatedCost = cost
        return option
    }

    // MARK: Image

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            POPFieldShell(label: "Image", hint: "Optional. Stored on this device only.") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(POPColor.surfaceSunk)
                        if isLoadingImage {
                            ProgressView().tint(POPColor.brandOrange)
                        } else if let image = store.image(named: imageFileName) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(POPColor.inkTertiary)
                        }
                    }
                    .frame(width: 78, height: 78)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(POPColor.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle").font(.system(size: 12, weight: .semibold))
                                Text(imageFileName == nil ? "Choose Photo" : "Replace Photo")
                                    .font(POPFont.captionMedium)
                            }
                            .foregroundStyle(POPColor.graphite)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Capsule().fill(POPColor.brandYellow))
                        }
                        if imageFileName != nil {
                            POPTextButton(title: "Remove photo", icon: "trash", tint: POPColor.danger) {
                                imageFileName = nil
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if let attachmentError {
                POPInlineNote(text: attachmentError, icon: "exclamationmark.circle.fill", tint: POPColor.danger)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingImage = true
        attachmentError = nil
        Task {
            defer { isLoadingImage = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    attachmentError = "That photo could not be read. Everything else you typed is still here."
                    return
                }
                switch store.importImageData(data, name: "Option photo") {
                case .success(let attachment):
                    imageFileName = attachment.fileName
                case .failure(let error):
                    attachmentError = error.localizedDescription
                }
            } catch {
                attachmentError = "That photo could not be read. Everything else you typed is still here."
            }
        }
    }

    // MARK: Persistence

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name
        provider = existing.providerOrBrand
        costText = POPFormat.editableNumber(existing.estimatedCost)
        recurringText = POPFormat.editableNumber(existing.cost.recurringCost)
        recurringPeriod = existing.cost.recurringPeriod
        website = existing.website
        contact = existing.contactDetails
        availability = existing.availability
        keyDetails = existing.keyDetails
        status = existing.status
        imageFileName = existing.imageFileName
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        var option = existing ?? DecisionOption()
        option.name = name.popTrimmed
        option.providerOrBrand = provider.popTrimmed
        option.estimatedCost = cost
        option.cost.recurringCost = recurring
        option.cost.recurringPeriod = recurringPeriod
        option.website = website.popTrimmed
        option.contactDetails = contact.popTrimmed
        option.availability = availability.popTrimmed
        option.keyDetails = keyDetails.popTrimmed
        option.status = status
        option.imageFileName = imageFileName

        if existing == nil {
            store.send(.addOption(decisionID: decisionID, option: option))
        } else {
            store.send(.updateOption(decisionID: decisionID, option: option))
        }
        dismiss()
    }
}
