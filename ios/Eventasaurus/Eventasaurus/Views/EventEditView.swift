import SwiftUI
import PhotosUI

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss

    let event: UserEvent

    @State private var title: String
    @State private var tagline: String
    @State private var description: String
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var hasEndDate: Bool
    @State private var visibility: EventVisibility
    @State private var isVirtual: Bool
    @State private var virtualVenueUrl: String
    @State private var theme: EventTheme

    // Venue
    @State private var selectedVenue: UserEventVenue?
    @State private var showVenueSheet = false
    @State private var venueChanged = false

    // Cover image
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?
    @State private var coverImageUrl: String?
    @State private var isUploadingImage = false

    // Submission
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var fieldErrors: [String: String] = [:]
    @State private var showDeleteConfirmation = false

    var onUpdated: ((UserEvent) -> Void)?
    var onDeleted: (() -> Void)?

    init(event: UserEvent, onUpdated: ((UserEvent) -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        self.event = event
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _title = State(initialValue: event.title)
        _tagline = State(initialValue: event.tagline ?? "")
        _description = State(initialValue: event.description ?? "")
        _startsAt = State(initialValue: (event.startsAt ?? Date()).snappedToNearest30Minutes())
        _endsAt = State(initialValue: (event.endsAt ?? Date().addingTimeInterval(3600)).snappedToNearest30Minutes())
        _hasEndDate = State(initialValue: event.endsAt != nil)
        _visibility = State(initialValue: event.visibility)
        _isVirtual = State(initialValue: event.isVirtual)
        _virtualVenueUrl = State(initialValue: event.virtualVenueUrl ?? "")
        _theme = State(initialValue: event.theme ?? .minimal)
        _coverImageUrl = State(initialValue: event.coverImageUrl)
        _selectedVenue = State(initialValue: event.venue)
    }

    var body: some View {
        NavigationStack {
            Form {
                statusBanner
                detailsSection
                if !isVirtual {
                    venueSection
                }
                dateTimeSection
                coverImageSection
                settingsSection
                if isVirtual {
                    virtualSection
                }
                dangerZone
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveEvent() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete Event", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task { await deleteEvent() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(event.title)\". This cannot be undone.")
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Saving...")
                                .padding(DS.Spacing.xxl)
                                .glassBackground(cornerRadius: DS.Radius.xl)
                        }
                }
            }
            .sheet(isPresented: $showVenueSheet) {
                VenueSearchSheet(selectedVenue: selectedVenue) { venue in
                    selectedVenue = venue
                    venueChanged = true
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusBanner: some View {
        if event.status == .draft {
            Section {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                    Text("This event is a draft. Publish it to make it visible.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Publish") {
                        Task { await publishEvent() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        } else if event.status == .canceled {
            Section {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("This event has been canceled.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Event Title", text: $title)
                .font(DS.Typography.title)
            if let error = fieldErrors["title"] {
                Text(error).font(DS.Typography.caption).foregroundStyle(.red)
            }

            TextField("Tagline (optional)", text: $tagline)
                .font(DS.Typography.body)

            TextEditor(text: $description)
                .frame(minHeight: 80)
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Description (optional)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("Details")
        }
    }

    private var venueSection: some View {
        Section {
            if let venue = selectedVenue {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(venue.name)
                            .font(DS.Typography.bodyMedium)
                        if let address = venue.address {
                            Text(address)
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        showVenueSheet = true
                    } label: {
                        Text("Change")
                            .font(DS.Typography.caption)
                    }
                }
            } else {
                Button {
                    showVenueSheet = true
                } label: {
                    Label("Add Venue", systemImage: "mappin.circle")
                }
            }
        } header: {
            Text("Venue")
        }
    }

    private var dateTimeSection: some View {
        Section {
            DatePicker30MinRow(label: "Starts", selection: $startsAt)

            Toggle("Add end time", isOn: $hasEndDate.animation())

            if hasEndDate {
                DatePicker30MinRow(label: "Ends", selection: $endsAt, minimumDate: startsAt)
            }
        } header: {
            Text("Date & Time")
        }
        .onChange(of: startsAt) { oldValue, newValue in
            let gap = max(endsAt.timeIntervalSince(oldValue), 1800) // minimum 30 min
            endsAt = newValue.addingTimeInterval(gap)
        }
    }

    private var coverImageSection: some View {
        Section {
            if let coverImageData, let uiImage = UIImage(data: coverImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.coverImageData = nil
                            self.selectedPhoto = nil
                            self.coverImageUrl = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .padding(DS.Spacing.md)
                    }
            } else if let coverImageUrl {
                AsyncImage(url: URL(string: coverImageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .foregroundStyle(.quaternary)
                        .overlay { ProgressView() }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                .overlay(alignment: .topTrailing) {
                    Button {
                        self.coverImageUrl = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .padding(DS.Spacing.md)
                }
            }

            if isUploadingImage {
                HStack {
                    ProgressView()
                    Text("Uploading...")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images
            ) {
                Label(
                    coverImageUrl == nil && coverImageData == nil ? "Add Cover Photo" : "Change Photo",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadAndUploadImage(newValue) }
            }
        } header: {
            Text("Cover Image")
        }
    }

    private var settingsSection: some View {
        Section {
            Picker("Visibility", selection: $visibility) {
                ForEach(EventVisibility.allCases, id: \.self) { vis in
                    Label(vis.displayName, systemImage: vis.icon)
                        .tag(vis)
                }
            }

            Toggle(isOn: $isVirtual) {
                Label("Virtual Event", systemImage: "video")
            }

            Picker("Theme", selection: $theme) {
                ForEach(EventTheme.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
        } header: {
            Text("Settings")
        }
    }

    private var virtualSection: some View {
        Section {
            TextField("Meeting URL", text: $virtualVenueUrl)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
        } header: {
            Text("Virtual Event")
        }
    }

    private var dangerZone: some View {
        Section {
            if event.status != .canceled {
                Button(role: .destructive) {
                    Task { await cancelEventAction() }
                } label: {
                    Label("Cancel Event", systemImage: "xmark.circle")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Event", systemImage: "trash")
            }
        } header: {
            Text("Danger Zone")
        }
    }

    // MARK: - Actions

    private func loadAndUploadImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        coverImageData = data
        coverImageUrl = nil
        isUploadingImage = true

        do {
            let url = try await GraphQLClient.shared.uploadImage(
                data: data,
                filename: "cover.jpg",
                mimeType: "image/jpeg"
            )
            coverImageUrl = url
        } catch {
            errorMessage = "Failed to upload image: \(error.localizedDescription)"
        }
        isUploadingImage = false
    }

    private func saveEvent() async {
        isSaving = true
        errorMessage = nil
        fieldErrors = [:]

        var input = UpdateEventInput(
            title: title.trimmingCharacters(in: .whitespaces) != event.title ? title.trimmingCharacters(in: .whitespaces) : nil,
            description: description != (event.description ?? "") ? (description.isEmpty ? nil : description) : nil,
            tagline: tagline != (event.tagline ?? "") ? (tagline.isEmpty ? nil : tagline) : nil,
            startsAt: startsAt != event.startsAt ? startsAt : nil,
            endsAt: hasEndDate ? (endsAt != event.endsAt ? endsAt : nil) : nil,
            timezone: TimeZone.current.identifier,
            visibility: visibility != event.visibility ? visibility : nil,
            theme: theme != event.theme ? theme : nil,
            coverImageUrl: coverImageUrl != event.coverImageUrl ? coverImageUrl : nil,
            isVirtual: isVirtual != event.isVirtual ? isVirtual : nil,
            virtualVenueUrl: isVirtual && !virtualVenueUrl.isEmpty ? virtualVenueUrl : nil
        )

        if venueChanged {
            if let venue = selectedVenue {
                input.venueId = venue.id
            } else {
                input.clearVenue = true
            }
        }

        do {
            let result = try await GraphQLClient.shared.updateEvent(slug: event.slug, input: input)
            onUpdated?(result.data)
            dismiss()
        } catch let error as GraphQLMutationError {
            fieldErrors = error.fieldErrors
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func publishEvent() async {
        isSaving = true
        do {
            let updated = try await GraphQLClient.shared.publishEvent(slug: event.slug)
            onUpdated?(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func cancelEventAction() async {
        isSaving = true
        do {
            let updated = try await GraphQLClient.shared.cancelEvent(slug: event.slug)
            onUpdated?(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteEvent() async {
        isSaving = true
        do {
            try await GraphQLClient.shared.deleteEvent(slug: event.slug)
            onDeleted?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
