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
                } else if let error, response == nil {
                    ContentUnavailableView {
                        Label("Something went wrong", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Try Again") { Task { await loadMovies() } }
                    }
                } else if let response {
                    movieContent(response)
                } else {
                    ContentUnavailableView("No Movies", systemImage: "film", description: Text("No movies currently showing."))
                }
            }
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
            VStack(spacing: 20) {
                // Stats header
                statsHeader(data.stats)

                // Movie poster grid
                if data.movies.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    LazyVGrid(columns: posterColumns, spacing: 12) {
                        ForEach(data.movies) { movie in
                            NavigationLink(value: EventDestination.movieGroup(slug: movie.slug, cityId: nil)) {
                                moviePosterCard(movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
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
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Movie Poster Card

    private func moviePosterCard(_ movie: MovieListItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Poster image with badges
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: movie.posterUrl.flatMap { URL(string: $0) },
                    height: 180,
                    placeholderIcon: "film"
                )
                .aspectRatio(2/3, contentMode: .fill)

                // Rating badge (top-left)
                if let rating = movie.voteAverage, rating > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7))
                    .foregroundStyle(.yellow)
                    .clipShape(Capsule())
                    .padding(6)
                }

                // City count badge (top-right)
                VStack {
                    HStack {
                        Spacer()
                        if movie.cityCount > 1 {
                            Text("\(movie.cityCount) cities")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(6)
                        }
                    }
                    Spacer()
                    // Screening count badge (bottom-right)
                    HStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "ticket")
                                .font(.system(size: 8))
                            Text("\(movie.screeningCount)")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title
            Text(movie.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            // Year + runtime
            HStack(spacing: 4) {
                if let year = movie.releaseDate {
                    Text(year)
                }
                if let runtime = movie.runtime, runtime > 0 {
                    Text("\(runtime)m")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Genre pills
            if let genres = movie.genres, !genres.isEmpty {
                HStack(spacing: 4) {
                    ForEach(genres.prefix(2), id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }
            }
        }
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
