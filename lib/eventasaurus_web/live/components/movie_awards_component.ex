defmodule EventasaurusWeb.Live.Components.MovieAwardsComponent do
  @moduledoc """
  Awards and canonical membership badges for movies.

  Renders:
  - Oscar wins badge (when oscarWins > 0)
  - Canonical source badges (1001 Movies, Criterion, Sight & Sound, etc.)
  - Awards summary text (e.g., "11 wins & 38 nominations")

  Hidden entirely when cinegraph_data is nil or no notable awards/sources exist.

  This is a function component — render directly in templates.

  ## Usage

      <EventasaurusWeb.Live.Components.MovieAwardsComponent.awards_badges
        cinegraph_data={@movie.cinegraph_data}
      />
  """

  use Phoenix.Component

  attr :cinegraph_data, :map, default: nil

  def awards_badges(assigns) do
    awards = get_in(assigns.cinegraph_data || %{}, ["awards"]) || %{}
    canonical = get_in(assigns.cinegraph_data || %{}, ["canonicalSources"]) || %{}

    oscar_wins = awards["oscarWins"] || 0
    total_wins = awards["totalWins"] || 0
    total_nominations = awards["totalNominations"] || 0
    summary = awards["summary"]

    canonical_badges = build_canonical_badges(canonical)
    has_content = oscar_wins > 0 || canonical_badges != [] || total_wins > 0 || total_nominations > 0

    assigns =
      assign(assigns,
        oscar_wins: oscar_wins,
        total_wins: total_wins,
        total_nominations: total_nominations,
        summary: summary,
        canonical_badges: canonical_badges,
        has_content: has_content
      )

    ~H"""
    <%= if @has_content do %>
      <div class="flex flex-wrap items-center gap-2 py-2">
        <%= if @oscar_wins > 0 do %>
          <span class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-amber-50 border border-amber-200 text-sm font-semibold text-amber-800">
            🏆
            <%= if @oscar_wins == 1 do %>
              1 Oscar Win
            <% else %>
              <%= @oscar_wins %> Oscar Wins
            <% end %>
          </span>
        <% end %>

        <%= for badge <- @canonical_badges do %>
          <span class={"inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-medium #{badge.classes}"}>
            <%= badge.icon %> <%= badge.label %>
          </span>
        <% end %>

        <%= if @total_wins > 0 || @total_nominations > 0 do %>
          <span class="text-sm text-gray-500">
            <%= awards_summary(@oscar_wins, @total_wins, @total_nominations, @summary) %>
          </span>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp build_canonical_badges(canonical) when is_map(canonical) do
    canonical
    |> Enum.flat_map(fn {key, value} ->
      if value do
        case badge_for_source(key) do
          nil -> []
          badge -> [badge]
        end
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.priority)
  end

  defp build_canonical_badges(_), do: []

  defp badge_for_source("1001_movies"),
    do: %{label: "1001 Movies", icon: "📚", classes: "bg-indigo-50 border-indigo-200 text-indigo-700", priority: 1}

  defp badge_for_source("criterion"),
    do: %{label: "Criterion", icon: "🎞", classes: "bg-gray-50 border-gray-300 text-gray-700", priority: 2}

  defp badge_for_source("sight_and_sound"),
    do: %{label: "Sight & Sound", icon: "👁", classes: "bg-purple-50 border-purple-200 text-purple-700", priority: 3}

  defp badge_for_source("bfi"),
    do: %{label: "BFI", icon: "🎭", classes: "bg-blue-50 border-blue-200 text-blue-700", priority: 4}

  defp badge_for_source("afi"),
    do: %{label: "AFI", icon: "🎥", classes: "bg-red-50 border-red-200 text-red-700", priority: 5}

  defp badge_for_source(_), do: nil

  defp awards_summary(_oscar_wins, _total_wins, _total_nominations, summary) when is_binary(summary) and summary != "" do
    summary
  end

  defp awards_summary(_oscar_wins, total_wins, total_nominations, _summary) do
    cond do
      total_wins > 0 && total_nominations > 0 ->
        "#{total_wins} wins & #{total_nominations} nominations"

      total_wins > 0 ->
        "#{total_wins} wins"

      total_nominations > 0 ->
        "#{total_nominations} nominations"

      true ->
        nil
    end
  end
end
