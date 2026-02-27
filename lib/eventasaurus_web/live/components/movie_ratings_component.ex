defmodule EventasaurusWeb.Live.Components.MovieRatingsComponent do
  @moduledoc """
  Multi-source ratings panel for movies.

  Displays score badges from TMDB, IMDb, Rotten Tomatoes, and Metacritic
  using data from Cinegraph (movie.cinegraph_data). Falls back to showing
  nothing if no ratings are available.

  This is a function component (not live_component) — render directly in templates.

  ## Usage

      <EventasaurusWeb.Live.Components.MovieRatingsComponent.ratings_panel
        cinegraph_data={@movie.cinegraph_data}
        tmdb_rating={@movie.metadata["vote_average"]}
      />
  """

  use Phoenix.Component

  attr :cinegraph_data, :map, default: nil
  attr :tmdb_rating, :any, default: nil

  def ratings_panel(assigns) do
    ratings = get_in(assigns.cinegraph_data || %{}, ["ratings"]) || %{}

    # Build list of ratings to display, falling back to TMDB metadata if no Cinegraph data
    tmdb_score = ratings["tmdb"] || assigns.tmdb_rating
    imdb_score = ratings["imdb"]
    rt_score = ratings["rottenTomatoes"]
    meta_score = ratings["metacritic"]

    assigns =
      assign(assigns,
        tmdb_score: tmdb_score,
        imdb_score: imdb_score,
        rt_score: rt_score,
        meta_score: meta_score,
        has_any_rating: !is_nil(tmdb_score) || !is_nil(imdb_score) || !is_nil(rt_score) || !is_nil(meta_score)
      )

    ~H"""
    <%= if @has_any_rating do %>
      <div class="flex flex-wrap items-center gap-3 py-3">
        <.rating_badge :if={@tmdb_score} source="TMDB" score={format_tmdb(@tmdb_score)} color="bg-blue-50 text-blue-700 border-blue-200" icon="⭐" />
        <.rating_badge :if={@imdb_score} source="IMDb" score={format_imdb(@imdb_score)} color="bg-yellow-50 text-yellow-800 border-yellow-200" icon="🎬" />
        <.rating_badge :if={@rt_score} source="RT" score={"#{@rt_score}%"} color={rt_color(@rt_score)} icon={rt_icon(@rt_score)} />
        <.rating_badge :if={@meta_score} source="Metacritic" score={"#{@meta_score}"} color={meta_color(@meta_score)} icon="📰" />
      </div>
    <% end %>
    """
  end

  defp rating_badge(assigns) do
    ~H"""
    <div class={"inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-sm font-medium #{@color}"}>
      <span><%= @icon %></span>
      <span class="font-semibold"><%= @score %></span>
      <span class="text-xs opacity-70"><%= @source %></span>
    </div>
    """
  end

  defp format_tmdb(score) when is_number(score) do
    :erlang.float_to_binary(score * 1.0, decimals: 1)
  end

  defp format_tmdb(score), do: to_string(score)

  defp format_imdb(score) when is_number(score) do
    :erlang.float_to_binary(score * 1.0, decimals: 1)
  end

  defp format_imdb(score), do: to_string(score)

  defp rt_icon(score) when is_number(score) and score >= 60, do: "🍅"
  defp rt_icon(_), do: "🦠"

  defp rt_color(score) when is_number(score) and score >= 75,
    do: "bg-green-50 text-green-700 border-green-200"

  defp rt_color(score) when is_number(score) and score >= 60,
    do: "bg-lime-50 text-lime-700 border-lime-200"

  defp rt_color(_), do: "bg-red-50 text-red-700 border-red-200"

  defp meta_color(score) when is_number(score) and score >= 61,
    do: "bg-green-50 text-green-800 border-green-200"

  defp meta_color(score) when is_number(score) and score >= 40,
    do: "bg-yellow-50 text-yellow-800 border-yellow-200"

  defp meta_color(_), do: "bg-red-50 text-red-700 border-red-200"
end
