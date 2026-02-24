defmodule EventasaurusDiscovery.Movies.AggregatedMovieGroup do
  @moduledoc """
  Virtual struct representing a group of movie screenings on the index page.

  Used when multiple screenings of the same movie should be displayed as
  a single card linking to the aggregated movie screenings view.

  Example: 12 Interstellar screenings across 3 venues shown as one "Interstellar" card.
  """

  @type t :: %__MODULE__{
          movie_id: integer(),
          movie_slug: String.t(),
          movie_title: String.t(),
          movie_backdrop_url: String.t() | nil,
          movie_poster_url: String.t() | nil,
          movie_release_date: Date.t() | nil,
          movie_runtime: integer() | nil,
          movie_vote_average: float() | nil,
          movie_genres: list(String.t()),
          movie_tagline: String.t() | nil,
          city_id: integer(),
          city: map(),
          screening_count: integer(),
          venue_count: integer(),
          categories: list(),
          earliest_starts_at: DateTime.t() | nil
        }

  defstruct [
    :movie_id,
    :movie_slug,
    :movie_title,
    :movie_backdrop_url,
    :movie_poster_url,
    :movie_release_date,
    :movie_runtime,
    :movie_vote_average,
    :movie_tagline,
    :city_id,
    :city,
    :screening_count,
    :venue_count,
    :categories,
    :earliest_starts_at,
    movie_genres: []
  ]

  @doc """
  Returns the path to the aggregated movie screenings view for this group.
  """
  def path(%__MODULE__{} = group) do
    "/c/#{group.city.slug}/movies/#{group.movie_slug}"
  end

  @doc """
  Returns a human-readable title for the group.
  """
  def title(%__MODULE__{} = group) do
    if group.movie_release_date do
      year = Calendar.strftime(group.movie_release_date, "%Y")
      "#{group.movie_title} (#{year})"
    else
      group.movie_title
    end
  end

  @doc """
  Returns a human-readable description for the group.
  """
  def description(%__MODULE__{} = group) do
    venue_text = if group.venue_count == 1, do: "venue", else: "venues"
    screening_text = if group.screening_count == 1, do: "screening", else: "screenings"

    "#{group.screening_count} #{screening_text} across #{group.venue_count} #{venue_text}"
  end
end
