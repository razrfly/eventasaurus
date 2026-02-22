import SwiftUI
import PhotosUI

struct EventCreateView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var tagline = ""
    @State private var description = ""
    @State private var startsAt = Date().addingTimeInterval(3600) // 1 hour from now
    @State private var endsAt = Date().addingTimeInterval(7200)   // 2 hours from now
    @State private var hasEndDate = false
    @State private var visibility: EventVisibility = .public
    @State private var isVirtual = false
    @State private var virtualVenueUrl = ""
    @State private var theme: EventTheme = .minimal

    // Venue
    @State private var selectedVenue: UserEventVenue?
    @State private var showVenueSheet = false

    // Cover image
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?
    @State private var uploadedImageUrl: String?
    @State private var isUploadingImage = false

    // Submission
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var fieldErrors: [String: String] = [:]

    var onCreated: ((UserEvent) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
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

                // Error + Submit
                Section {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await createEvent() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .padding(.trailing, DS.Spacing.sm)
                            }
                            Text(isSaving ? "Creating..." : "Create Event")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createEvent() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Creating event...")
                                .padding(DS.Spacing.xxl)
                                .glassBackground(cornerRadius: DS.Radius.xl)
                        }
                }
            }
            .sheet(isPresented: $showVenueSheet) {
                VenueSearchSheet(selectedVenue: selectedVenue) { venue in
                    selectedVenue = venue
                }
            }
        }
    }

    // MARK: - Sections

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
            DatePicker("Starts", selection: $startsAt, in: Date()...)
                .font(DS.Typography.body)

            Toggle("Add end time", isOn: $hasEndDate.animation())

            if hasEndDate {
                DatePicker("Ends", selection: $endsAt, in: startsAt...)
                    .font(DS.Typography.body)
            }
        } header: {
            Text("Date & Time")
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
                            self.uploadedImageUrl = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .padding(DS.Spacing.md)
                    }

                if isUploadingImage {
                    HStack {
                        ProgressView()
                        Text("Uploading...")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if uploadedImageUrl != nil {
                    Label("Uploaded", systemImage: "checkmark.circle.fill")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.green)
                }
            }

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images
            ) {
                Label(
                    coverImageData == nil ? "Add Cover Photo" : "Change Photo",
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

    // MARK: - Actions

    private func loadAndUploadImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        coverImageData = data
        uploadedImageUrl = nil
        isUploadingImage = true

        do {
            let url = try await GraphQLClient.shared.uploadImage(
                data: data,
                filename: "cover.jpg",
                mimeType: "image/jpeg"
            )
            uploadedImageUrl = url
        } catch {
            errorMessage = "Failed to upload image: \(error.localizedDescription)"
        }
        isUploadingImage = false
    }

    private func createEvent() async {
        isSaving = true
        errorMessage = nil
        fieldErrors = [:]

        let input = CreateEventInput(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            tagline: tagline.isEmpty ? nil : tagline,
            startsAt: startsAt,
            endsAt: hasEndDate ? endsAt : nil,
            timezone: TimeZone.current.identifier,
            visibility: visibility,
            theme: theme,
            coverImageUrl: uploadedImageUrl,
            isVirtual: isVirtual,
            virtualVenueUrl: isVirtual && !virtualVenueUrl.isEmpty ? virtualVenueUrl : nil,
            venueId: isVirtual ? nil : selectedVenue?.id
        )

        do {
            let result = try await GraphQLClient.shared.createEvent(input: input)
            onCreated?(result.data)
            dismiss()
        } catch let error as GraphQLMutationError {
            fieldErrors = error.fieldErrors
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    EventCreateView()
}
