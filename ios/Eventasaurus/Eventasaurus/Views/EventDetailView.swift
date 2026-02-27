import SwiftUI

struct EventDetailView: View {
    let slug: String
    @State private var event: Event?
    @State private var isLoading = true
    @State private var error: Error?

    // RSVP state
    @State private var rsvpStatus: RsvpStatus?
    @State private var attendeeCount: Int = 0
    @State private var isUpdatingStatus = false
    @State private var isOrganizer = false

    // Plan with Friends state
    @State private var existingPlan: GQLPlan?
    @State private var planSheetEvent: Event?

    @Environment(\.tabBarSafeAreaInset) private var tabBarSafeAreaInset

    // Polls state
    @State private var polls: [EventPoll] = []
    @State private var pollRefreshID = UUID()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let event {
                eventContent(event)
            } else if let error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: error.localizedDescription
                )
            }
        }
        .fullBleedNavigation {
            if let event, let shareURL = URL.event(slug: slug) {
                ShareLink(
                    item: shareURL,
                    subject: Text(event.title),
                    message: Text(event.description ?? event.title)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                }
                .buttonStyle(GlassIconButtonStyle())
            }
        }
        .task { await loadEvent() }
        .sheet(item: $planSheetEvent) { event in
            PlanWithFriendsSheet(event: event) { (plan: GQLPlan) in
                existingPlan = plan
            }
        }
    }

    private func eventContent(_ event: Event) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Hero with overlaid title/date/venue
                if event.coverImageUrl != nil {
                    DramaticHero(imageURL: AppConfig.resolvedImageURL(event.coverImageUrl)) {
                        HeroOverlayCard {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                Text(event.title)
                                    .font(DS.Typography.title)
                                    .foregroundStyle(.white)

                                if let date = event.startsAt {
                                    Label {
                                        Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                                    } icon: {
                                        Image(systemName: "calendar")
                                    }
                                    .font(DS.Typography.body)
                                    .foregroundStyle(.white.opacity(0.9))
                                }

                                if let venue = event.venue {
                                    Label {
                                        Text(venue.displayName)
                                    } icon: {
                                        Image(systemName: "mappin.and.ellipse")
                                    }
                                    .font(DS.Typography.body)
                                    .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                    }
                } else {
                    // No-image fallback: inline title
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(event.title)
                            .font(DS.Typography.title)

                        if let date = event.startsAt {
                            Label {
                                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                            } icon: {
                                Image(systemName: "calendar")
                            }
                            .font(DS.Typography.body)
                        }

                        if let venue = event.venue {
                            Label(venue.displayName, systemImage: "mappin.and.ellipse")
                                .font(DS.Typography.body)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.top, DS.Spacing.fullBleedNavClearance)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Venue row (tap to navigate)
                    if let venue = event.venue {
                        venueRow(venue)
                    }

                    // Screening schedule (movie screening events)
                    if let dates = event.occurrences?.dates, !dates.isEmpty {
                        ScreeningScheduleSection(
                            showtimes: dates,
                            venueName: event.venue?.displayName
                        )
                    }

                    // See All Screenings (movie screening events)
                    if let movieSlug = event.movieGroupSlug {
                        NavigationLink(value: EventDestination.movieGroup(slug: movieSlug, cityId: event.movieCityId)) {
                            Label("See All Screenings", systemImage: "film.stack")
                                .font(DS.Typography.bodyMedium)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassSecondary)
                    }

                    // RSVP indicator (internal events with existing RSVP)
                    if event.isInternalEvent, let status = rsvpStatus {
                        if event.isUpcoming {
                            compactRsvpIndicator(status: status)
                        } else {
                            pastRsvpIndicator(status: status)
                        }
                    }

                    // Plan with Friends (inline — only for public events with existing plan)
                    if !event.isInternalEvent, existingPlan != nil {
                        planWithFriendsSection(for: event)
                    }

                    // Categories
                    if let categories = event.categories, !categories.isEmpty {
                        HStack(spacing: DS.Spacing.md) {
                            ForEach(categories, id: \.slug) { category in
                                HStack(spacing: DS.Spacing.xxs) {
                                    if let icon = category.icon {
                                        Text(icon)
                                            .font(DS.Typography.micro)
                                    }
                                    Text(category.name)
                                }
                                .font(DS.Typography.caption)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(category.resolvedColor.opacity(DS.Opacity.tintedBackground))
                                .clipShape(Capsule())
                            }
                        }
                    }

                    Divider()

                    // Description
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(DS.Typography.prose)
                    }

                    // Polls section
                    if !polls.isEmpty {
                        Divider()
                        pollsSection
                    }

                    // Ticket link (buried inline — not a primary CTA)
                    if let ticketUrl = event.ticketUrl, let url = URL(string: ticketUrl) {
                        ExternalLinkButton(title: "Get Tickets", url: url, icon: "ticket")
                    }

                    // Venue map
                    if let venue = event.venue, let lat = venue.lat, let lng = venue.lng {
                        VenueMapCard(name: venue.displayName, address: venue.address, lat: lat, lng: lng)
                    }

                    // Source attribution
                    if let sources = event.sources, !sources.isEmpty {
                        Divider()
                        SourceAttributionSection(sources: sources)
                    }

                    // Nearby events
                    if let nearbyEvents = event.nearbyEvents, !nearbyEvents.isEmpty {
                        Divider()
                        NearbyEventsSection(events: nearbyEvents)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if event.isInternalEvent && isOrganizer {
                // Organiser — show Manage banner instead of RSVP bar
                organizerManageBanner
                    .padding(.bottom, tabBarSafeAreaInset)
            } else if event.isInternalEvent && !isOrganizer && rsvpStatus == nil && event.isUpcoming {
                // Internal event, no RSVP yet — show Going/Interested
                rsvpActionBar
                    .padding(.bottom, tabBarSafeAreaInset)
            } else if !event.isInternalEvent && event.isUpcoming && existingPlan == nil {
                // Public event, no plan yet — show Plan with Friends
                publicEventActionBar
                    .padding(.bottom, tabBarSafeAreaInset)
            }
        }
    }

    // MARK: - Venue Row

    @ViewBuilder
    private func venueRow(_ venue: Venue) -> some View {
        if let venueSlug = venue.slug {
            NavigationLink(value: EventDestination.venue(slug: venueSlug)) {
                Label {
                    VStack(alignment: .leading) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(venue.displayName)
                                .font(DS.Typography.body)
                            Image(systemName: "chevron.right")
                                .font(DS.Typography.micro)
                                .foregroundStyle(.secondary)
                        }
                        if let address = venue.address {
                            Text(address)
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
            }
            .buttonStyle(.plain)
        } else {
            Label {
                VStack(alignment: .leading) {
                    Text(venue.displayName)
                        .font(DS.Typography.body)
                    if let address = venue.address {
                        Text(address)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
    }

    // MARK: - Plan with Friends

    private func planWithFriendsSection(for event: Event) -> some View {
        Group {
            if let plan = existingPlan {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(DS.Colors.plan)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("You have a plan!")
                            .font(DS.Typography.bodyMedium)
                        if plan.inviteCount > 0 {
                            Text("\(plan.inviteCount) friends invited")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    NavigationLink {
                        EventManageView(slug: plan.slug)
                    } label: {
                        Text("View")
                            .font(DS.Typography.captionMedium)
                    }
                    .buttonStyle(.glassTinted(DS.Colors.plan, isActive: true))
                }
                .padding(DS.Spacing.lg)
                .glassBackground(cornerRadius: DS.Radius.md)
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    planSheetEvent = event
                } label: {
                    Label("Plan with Friends", systemImage: "person.2.badge.plus")
                        .font(DS.Typography.bodyMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassTinted(DS.Colors.plan, isActive: false))
                .accessibilityHint("Opens sheet to invite friends")
            }
        }
    }

    // MARK: - Action Bars

    private var rsvpActionBar: some View {
        GlassActionBar {
            HStack(spacing: DS.Spacing.lg) {
                Button {
                    Task { await toggleStatus(.going) }
                } label: {
                    Label("Going", systemImage: "checkmark.circle")
                        .font(DS.Typography.bodyMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassTinted(DS.Colors.going, isActive: false))
                .disabled(isUpdatingStatus)

                Button {
                    Task { await toggleStatus(.interested) }
                } label: {
                    Label("Interested", systemImage: "star")
                        .font(DS.Typography.bodyMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassTinted(DS.Colors.interested, isActive: false))
                .disabled(isUpdatingStatus)
            }
        }
    }

    private var publicEventActionBar: some View {
        GlassActionBar {
            Button {
                if let event { planSheetEvent = event }
            } label: {
                Label("Plan with Friends", systemImage: "person.2.badge.plus")
                    .font(DS.Typography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassTinted(DS.Colors.plan, isActive: false))
        }
    }

    private var organizerManageBanner: some View {
        GlassActionBar {
            NavigationLink {
                EventManageView(slug: slug)
            } label: {
                HStack {
                    Label("You organised this", systemImage: "gearshape")
                        .font(DS.Typography.bodyMedium)
                    Spacer()
                    HStack(spacing: DS.Spacing.xs) {
                        Text("Manage")
                            .font(DS.Typography.captionMedium)
                        Image(systemName: "chevron.right")
                            .font(DS.Typography.micro)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - RSVP Indicators

    private func compactRsvpIndicator(status: RsvpStatus) -> some View {
        HStack {
            Image(systemName: status == .going ? "checkmark.circle.fill" : "star.fill")
                .foregroundStyle(status == .going ? DS.Colors.going : DS.Colors.interested)
            Text(status == .going ? "You're going" : "You're interested")
                .font(DS.Typography.bodyMedium)
            Spacer()
            Menu {
                Button { Task { await toggleStatus(.going) } } label: {
                    Label("Going", systemImage: "checkmark.circle")
                }
                Button { Task { await toggleStatus(.interested) } } label: {
                    Label("Interested", systemImage: "star")
                }
                Button(role: .destructive) { Task { await toggleStatus(status) } } label: {
                    Label("Remove RSVP", systemImage: "xmark.circle")
                }
            } label: {
                Text("Change")
                    .font(DS.Typography.captionMedium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.lg)
        .glassBackground(cornerRadius: DS.Radius.md)
    }

    private func pastRsvpIndicator(status: RsvpStatus) -> some View {
        HStack {
            Image(systemName: status == .going ? "checkmark.circle.fill" : "star.fill")
                .foregroundStyle(status == .going ? DS.Colors.going : DS.Colors.interested)
            Text(status == .going ? "You went" : "You were interested")
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.lg)
        .glassBackground(cornerRadius: DS.Radius.md)
    }

    // MARK: - Polls Section

    private var pollsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Polls")
                    .font(DS.Typography.bodyBold)
                Spacer()
                Text("\(polls.count)")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xxs)
                    .glassBackground(cornerRadius: DS.Radius.full)
            }

            ForEach(polls) { poll in
                NavigationLink {
                    PollDetailView(poll: poll, slug: slug)
                        .onDisappear { pollRefreshID = UUID() }
                } label: {
                    PollCardView(poll: poll, slug: slug)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: pollRefreshID) {
            guard !isLoading else { return }
            do {
                polls = try await GraphQLClient.shared.fetchEventPolls(slug: slug)
            } catch {
                // Keep existing polls on refresh failure
            }
        }
    }

    // MARK: - Data Loading

    private func loadEvent() async {
        defer { isLoading = false }
        do {
            let loaded = try await APIClient.shared.fetchEventDetail(slug: slug)
            event = loaded
            attendeeCount = loaded.attendeeCount ?? 0

            // For internal events, get RSVP status from GraphQL (REST doesn't have it)
            if loaded.isInternalEvent {
                do {
                    let userEvent = try await GraphQLClient.shared.fetchEventAsAttendee(slug: slug)
                    rsvpStatus = userEvent.myRsvpStatus
                    attendeeCount = userEvent.participantCount
                    isOrganizer = userEvent.isOrganizer
                } catch {
                    // Non-fatal: event loaded from REST, just missing RSVP status
                    if let status = loaded.attendanceStatus {
                        rsvpStatus = RsvpStatus(restStatus: status)
                        isOrganizer = (status == "organizer")
                    }
                    #if DEBUG
                    print("[EventDetailView] GraphQL RSVP fetch failed for \(slug): \(error)")
                    #endif
                }
            }

            // Load plan and polls in parallel (both non-fatal)
            async let planTask = GraphQLClient.shared.fetchMyPlan(slug: slug)
            async let pollsTask = GraphQLClient.shared.fetchEventPolls(slug: slug)
            existingPlan = try? await planTask
            polls = (try? await pollsTask) ?? []
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }

    private func toggleStatus(_ status: RsvpStatus) async {
        let previousStatus = rsvpStatus
        let previousCount = attendeeCount

        isUpdatingStatus = true
        defer { isUpdatingStatus = false }
        withAnimation(DS.Animation.spring) {
            if rsvpStatus == status {
                rsvpStatus = nil
                if status == .going { attendeeCount = max(0, attendeeCount - 1) }
            } else {
                if previousStatus == .going { attendeeCount = max(0, attendeeCount - 1) }
                rsvpStatus = status
                if status == .going { attendeeCount += 1 }
            }
        }

        do {
            if previousStatus == status {
                // Cancel RSVP
                try await GraphQLClient.shared.cancelRsvp(slug: slug)
            } else {
                // Set RSVP — returns updated event with participant count
                let updatedEvent = try await GraphQLClient.shared.rsvp(slug: slug, status: status)
                attendeeCount = updatedEvent.participantCount
            }
        } catch {
            withAnimation(DS.Animation.spring) {
                rsvpStatus = previousStatus
                attendeeCount = previousCount
            }
        }
    }

}
