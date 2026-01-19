defmodule EventasaurusWeb.MovieSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for movie screenings pages.

  This controller generates social cards with Wombie branding for movie pages,
  showing movie title, poster/backdrop, year, runtime, and rating.

  Route: GET /social-cards/movie/:city_slug/:movie_slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :movie

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.Movies.MovieStore
  alias EventasaurusApp.Images.MovieImages

  import EventasaurusWeb.SocialCardView, only: [sanitize_movie: 1, render_movie_card_svg: 1]

  @impl true
  def lookup_entity(%{"city_slug" => city_slug, "movie_slug" => movie_slug}) do
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:error, :not_found, "City not found for slug: #{city_slug}"}

      city ->
        case MovieStore.get_movie_by_slug(movie_slug) do
          nil ->
            {:error, :not_found, "Movie not found for slug: #{movie_slug}"}

          movie ->
            {:ok, {movie, city}}
        end
    end
  end

  @impl true
  def build_card_data({movie, city}) do
    # Count total showtimes for this movie in this city
    total_showtimes = MovieStore.count_showtimes_in_city(movie.id, city.id)

    # Get next upcoming screening dates (up to 3)
    screening_dates = MovieStore.get_upcoming_screening_dates(movie.id, city.id, limit: 3)

    # Use cached image URLs with fallback to original
    poster_url = MovieImages.get_poster_url(movie.id, movie.poster_url)
    backdrop_url = MovieImages.get_backdrop_url(movie.id, movie.backdrop_url)

    %{
      title: movie.title,
      slug: movie.slug,
      city: %{
        name: city.name,
        slug: city.slug
      },
      poster_url: poster_url,
      backdrop_url: backdrop_url,
      release_date: movie.release_date,
      runtime: movie.runtime,
      overview: movie.overview,
      metadata: movie.metadata,
      total_showtimes: total_showtimes,
      screening_dates: screening_dates,
      updated_at: movie.updated_at
    }
  end

  @impl true
  def build_slug(%{"city_slug" => city_slug, "movie_slug" => movie_slug}, _data) do
    "#{city_slug}_#{movie_slug}"
  end

  @impl true
  def sanitize(data), do: sanitize_movie(data)

  @impl true
  def render_svg(data), do: render_movie_card_svg(data)
end
