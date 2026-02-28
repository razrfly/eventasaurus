import SwiftUI

struct CinegraphDetailView: View {
    let movie: MovieInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                heroImage(movie)

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    ratingsGrid(movie)

                    // Runtime + genres + director
                    HStack(spacing: DS.Spacing.lg) {
                        if let runtime = movie.runtime {
                            Label("\(runtime) min", systemImage: "clock")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }

                        if !movie.genres.isEmpty {
                            Text(movie.genres.joined(separator: ", "))
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }

                        if let director = movie.cinegraph?.director {
                            Label(director, systemImage: "video.fill")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Tagline
                    if let tagline = movie.tagline {
                        Text(tagline)
                            .font(DS.Typography.bodyItalic)
                            .foregroundStyle(.secondary)
                    }

                    // Awards
                    if let awards = movie.cinegraph?.awards {
                        let hasOscars = (awards.oscarWins ?? 0) > 0
                        let hasSummary = !(awards.summary ?? "").isEmpty
                        let hasWins = (awards.totalWins ?? 0) > 0
                        let hasNoms = (awards.totalNominations ?? 0) > 0
                        if hasOscars || hasSummary || hasWins || hasNoms {
                            AwardsRowView(awards: awards)
                        }
                    }

                    // Overview
                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(DS.Typography.prose)
                    }

                    // Cast
                    if let cast = movie.cast, !cast.isEmpty {
                        CastCarousel(cast: cast)
                    }

                    // Footer link
                    cinegraphFooterLink(movie)
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
        .fullBleedNavigation()
    }

    // MARK: - Hero Image

    private func heroImage(_ movie: MovieInfo) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let backdropUrl = movie.backdropUrl {
                CachedImage(
                    url: URL(string: backdropUrl),
                    height: DS.ImageSize.heroMovie,
                    cornerRadius: 0,
                    placeholderIcon: "film"
                )
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.2), .black.opacity(DS.Opacity.heroGradient)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: DS.ImageSize.heroMovie * 3 / 4)
                }

                HStack(alignment: .bottom, spacing: DS.Spacing.lg) {
                    if let posterUrl = movie.posterUrl {
                        CachedImage(
                            url: URL(string: posterUrl),
                            height: DS.ImageSize.posterOverlaySize.height,
                            cornerRadius: DS.Radius.md,
                            placeholderIcon: "film"
                        )
                        .frame(width: DS.ImageSize.posterOverlaySize.width)
                        .padding(DS.Spacing.xs)
                        .glassBackground(cornerRadius: DS.Radius.lg)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(movie.title)
                            .font(DS.Typography.title)
                            .foregroundStyle(.white)

                        if let releaseDate = movie.releaseDate,
                           let year = releaseDate.split(separator: "-").first {
                            Text("(\(year))")
                                .font(DS.Typography.titleSecondary)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.lg)
            } else if let posterUrl = movie.posterUrl {
                CachedImage(
                    url: URL(string: posterUrl),
                    height: DS.ImageSize.heroMovie,
                    cornerRadius: 0,
                    placeholderIcon: "film"
                )
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Ratings Grid

    @ViewBuilder
    private func ratingsGrid(_ movie: MovieInfo) -> some View {
        if let ratings = movie.cinegraph?.ratings {
            let cards = ratingCards(from: ratings)
            if !cards.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: DS.Spacing.md
                ) {
                    ForEach(cards, id: \.label) { card in
                        ratingCard(score: card.score, label: card.label, color: card.color)
                    }
                }
            }
        } else if let rating = movie.voteAverage {
            ratingCard(
                score: String(format: "%.1f", rating),
                label: "TMDB",
                color: .blue
            )
            .frame(maxWidth: .infinity)
        }
    }

    private struct RatingCardData {
        let score: String
        let label: String
        let color: Color
    }

    private func ratingCards(from ratings: CinegraphRatings) -> [RatingCardData] {
        var cards: [RatingCardData] = []
        if let tmdb = ratings.tmdb {
            cards.append(RatingCardData(
                score: String(format: "%.1f", tmdb),
                label: "TMDB",
                color: .blue
            ))
        }
        if let imdb = ratings.imdb {
            cards.append(RatingCardData(
                score: String(format: "%.1f", imdb),
                label: "IMDb",
                color: Color(red: 0.5, green: 0.35, blue: 0.0)
            ))
        }
        if let rt = ratings.rottenTomatoes {
            cards.append(RatingCardData(
                score: "\(rt)%",
                label: "Rotten Tomatoes",
                color: rtBadgeColor(rt)
            ))
        }
        if let mc = ratings.metacritic {
            cards.append(RatingCardData(
                score: "\(mc)",
                label: "Metacritic",
                color: metacriticBadgeColor(mc)
            ))
        }
        return cards
    }

    private func ratingCard(score: String, label: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Text(score)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(DS.Typography.captionBold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
        .glassBackground(cornerRadius: DS.Radius.lg)
    }

    // MARK: - Footer Link

    @ViewBuilder
    private func cinegraphFooterLink(_ movie: MovieInfo) -> some View {
        let url: URL? = {
            if let slug = movie.cinegraph?.cinegraphSlug,
               !slug.isEmpty,
               let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                return URL(string: "https://cinegraph.org/movies/\(encoded)")
            }
            return movie.tmdbId.flatMap { URL(string: "https://cinegraph.org/movies/tmdb/\($0)") }
        }()

        if let url {
            ExternalLinkButton(title: "View on cinegraph.org", url: url, icon: "safari")
        }
    }

    // MARK: - Color Helpers

    private func rtBadgeColor(_ score: Int) -> Color {
        if score >= 75 { return .green }
        if score >= 60 { return Color(red: 0.6, green: 0.8, blue: 0.0) }
        return .red
    }

    private func metacriticBadgeColor(_ score: Int) -> Color {
        if score >= 61 { return .green }
        if score >= 40 { return .orange }
        return .red
    }
}
