defmodule EventasaurusWeb.Admin.CardTypes.MovieCard do
  @moduledoc """
  Movie card type implementation for social card previews.

  Movie cards use fixed Cinema Purple brand colors.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  import EventasaurusWeb.SocialCardView, only: [render_movie_card_svg: 1]

  @impl true
  def card_type, do: :movie

  @impl true
  def generate_mock_data do
    %{
      id: 1,
      tmdb_id: 771,
      title: "Home Alone",
      slug: "home-alone-771",
      original_title: "Home Alone",
      overview:
        "Eight-year-old Kevin McCallister makes the most of the situation after his family unwittingly leaves him behind when they go on Christmas vacation.",
      poster_url: "/images/events/abstract/abstract2.png",
      backdrop_url: "/images/events/abstract/abstract2.png",
      release_date: ~D[1990-11-16],
      runtime: 103,
      metadata: %{
        vote_average: 7.4,
        vote_count: 10423,
        genres: ["Comedy", "Family"]
      },
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    render_movie_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :title, label: "Title", type: :text, path: [:title]},
      %{name: :backdrop_url, label: "Backdrop Image URL", type: :text, path: [:backdrop_url]},
      %{
        name: :year,
        label: "Year",
        type: :number,
        path: [:release_date, :year],
        min: 1900,
        max: 2100
      },
      %{name: :runtime, label: "Runtime (min)", type: :number, path: [:runtime], min: 0},
      %{
        name: :rating,
        label: "Rating (0-10)",
        type: :number,
        path: [:metadata, :vote_average],
        min: 0,
        max: 10,
        step: 0.1
      }
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    runtime = parse_int(Map.get(params, "runtime"), current.runtime)
    release_date = parse_year(Map.get(params, "year"), current.release_date)

    rating =
      parse_float(Map.get(params, "rating"), get_in(current.metadata, [:vote_average]) || 0.0)

    %{
      current
      | title: Map.get(params, "title", current.title),
        backdrop_url: Map.get(params, "backdrop_url", current.backdrop_url),
        runtime: runtime,
        release_date: release_date,
        metadata: Map.put(current.metadata, :vote_average, rating)
    }
  end

  @impl true
  def update_event_name, do: "update_mock_movie"

  @impl true
  def form_param_key, do: "movie"

  # Helper functions

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  defp parse_year(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {year, _} when year >= 1800 and year <= 2200 -> Date.new!(year, 1, 1)
      _ -> default
    end
  end

  defp parse_year(_, default), do: default

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end

  defp parse_float(_, default), do: default
end
