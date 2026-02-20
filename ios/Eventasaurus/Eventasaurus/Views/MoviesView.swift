import SwiftUI

struct MoviesView: View {
    @State private var response: MoviesIndexResponse?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var searchText = ""

    private let posterColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && response == nil {
                    ProgressView("Loading movies...")
                        .transition(.opacity)
                } else if let error, response == nil {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Something went wrong",
                        message: error.localizedDescription,
                        actionTitle: "Try Again",
                        action: { Task { await loadMovies() } }
                    )
                } else if let response {
                    movieContent(response)
                        .transition(.opacity)
                } else {
                    EmptyStateView(
                        icon: "film",
                        title: "No Movies",
                        message: "No movies currently showing."
                    )
                }
            }
            .animation(DS.Animation.standard, value: isLoading)
            .navigationTitle("Movies")
            .searchable(text: $searchText, prompt: "Search movies...")
            .onSubmit(of: .search) {
                Task { await loadMovies() }
            }
            .onChange(of: searchText) {
                if searchText.isEmpty {
                    Task { await loadMovies() }
                }
            }
            .task { await loadMovies() }
            .refreshable { await loadMovies() }
            .navigationDestination(for: EventDestination.self) { destination in
                switch destination {
                case .movieGroup(let slug, let cityId):
                    MovieDetailView(slug: slug, cityId: cityId)
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Movie Content

    private func movieContent(_ data: MoviesIndexResponse) -> some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xxl) {
                // Stats header
                statsHeader(data.stats)

                // Movie poster grid
                if data.movies.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    LazyVGrid(columns: posterColumns, spacing: DS.Spacing.lg) {
                        ForEach(data.movies) { movie in
                            NavigationLink(value: EventDestination.movieGroup(slug: movie.slug, cityId: nil)) {
                                moviePosterCard(movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                }
            }
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    // MARK: - Stats Header

    private func statsHeader(_ stats: MovieStats) -> some View {
        HStack(spacing: 0) {
            statItem(value: stats.movieCount, label: "Movies")
            Divider().frame(height: 30)
            statItem(value: stats.screeningCount, label: "Screenings")
            Divider().frame(height: 30)
            statItem(value: stats.cityCount, label: "Cities")
        }
        .padding(.vertical, DS.Spacing.lg)
        .background(DS.Colors.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .padding(.horizontal, DS.Spacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.movieCount) movies, \(stats.screeningCount) screenings, \(stats.cityCount) cities")
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text("\(value)")
                .font(DS.Typography.title)
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Movie Poster Card

    private func moviePosterCard(_ movie: MovieListItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Poster image with badges
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: movie.posterUrl.flatMap { URL(string: $0) },
                    height: DS.ImageSize.cardCover,
                    placeholderIcon: "film"
                )
                .aspectRatio(2/3, contentMode: .fill)

                // Rating badge (top-left)
                if let rating = movie.voteAverage, rating > 0 {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "star.fill")
                        Text(String(format: "%.1f", rating))
                    }
                    .badgeStyle(backgroundColor: .black.opacity(DS.Opacity.darkOverlay), foregroundColor: DS.Colors.ratingFill)
                    .padding(DS.Spacing.sm)
                }

                // City count badge (top-right)
                VStack {
                    HStack {
                        Spacer()
                        if movie.cityCount > 1 {
                            Text("\(movie.cityCount) cities")
                                .glassBadgeStyle()
                                .padding(DS.Spacing.sm)
                        }
                    }
                    Spacer()
                    // Screening count badge (bottom-right)
                    HStack {
                        Spacer()
                        HStack(spacing: DS.Spacing.xxs) {
                            Image(systemName: "ticket")
                            Text("\(movie.screeningCount)")
                        }
                        .badgeStyle(backgroundColor: .black.opacity(DS.Opacity.darkOverlay))
                        .padding(DS.Spacing.sm)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            // Title
            Text(movie.title)
                .font(DS.Typography.captionBold)
                .lineLimit(2)

            // Year + runtime
            HStack(spacing: DS.Spacing.xs) {
                if let year = movie.releaseDate {
                    Text(year)
                }
                if let runtime = movie.runtime, runtime > 0 {
                    Text("\(runtime)m")
                }
            }
            .font(DS.Typography.micro)
            .foregroundStyle(.secondary)

            // Genre pills
            if let genres = movie.genres, !genres.isEmpty {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(genres.prefix(2), id: \.self) { genre in
                        Text(genre)
                            .font(DS.Typography.micro)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, DS.Spacing.xxs)
                            .background(DS.Colors.fillSecondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Data Loading

    private func loadMovies() async {
        isLoading = true
        error = nil

        do {
            response = try await APIClient.shared.fetchMoviesIndex(
                search: searchText.isEmpty ? nil : searchText
            )
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
