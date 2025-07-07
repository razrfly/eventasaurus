defmodule EventasaurusWeb.Live.Components.MovieDetailsComponent do
  @moduledoc """
  Details section component for movie/TV show display.

  Displays additional information like release date, runtime,
  budget, revenue, production companies, and external links.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg p-6 space-y-6">
      <!-- Main Details -->
      <div>
        <h2 class="text-2xl font-bold text-gray-900 mb-4">Details</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <!-- Left Column -->
          <div class="space-y-4">
            <%= if @release_date do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Release Date</dt>
                <dd class="text-sm text-gray-900"><%= format_date(@release_date) %></dd>
              </div>
            <% end %>

            <%= if @runtime do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Runtime</dt>
                <dd class="text-sm text-gray-900"><%= format_runtime(@runtime) %></dd>
              </div>
            <% end %>

            <%= if @genres && length(@genres) > 0 do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Genres</dt>
                <dd class="text-sm text-gray-900">
                  <div class="flex flex-wrap gap-2 mt-1">
                    <%= for genre <- @genres do %>
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                        <%= genre["name"] %>
                      </span>
                    <% end %>
                  </div>
                </dd>
              </div>
            <% end %>

            <%= if @spoken_languages && length(@spoken_languages) > 0 do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Languages</dt>
                <dd class="text-sm text-gray-900">
                  <%= @spoken_languages |> Enum.map(& &1["english_name"]) |> Enum.join(", ") %>
                </dd>
              </div>
            <% end %>
          </div>

          <!-- Right Column -->
          <div class="space-y-4">
            <%= if @status do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Status</dt>
                <dd class="text-sm text-gray-900"><%= @status %></dd>
              </div>
            <% end %>

            <%= if @budget && @budget > 0 do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Budget</dt>
                <dd class="text-sm text-gray-900"><%= format_currency(@budget) %></dd>
              </div>
            <% end %>

            <%= if @revenue && @revenue > 0 do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Revenue</dt>
                <dd class="text-sm text-gray-900"><%= format_currency(@revenue) %></dd>
              </div>
            <% end %>

            <%= if @vote_average do %>
              <div>
                <dt class="text-sm font-medium text-gray-500">User Score</dt>
                <dd class="text-sm text-gray-900">
                  <div class="flex items-center">
                    <span class="text-lg font-semibold"><%= round(@vote_average * 10) %>%</span>
                    <span class="ml-2 text-gray-500">(<%= @vote_count || 0 %> votes)</span>
                  </div>
                </dd>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Production Companies -->
      <%= if @production_companies && length(@production_companies) > 0 do %>
        <div>
          <h3 class="text-lg font-semibold text-gray-900 mb-3">Production Companies</h3>
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            <%= for company <- Enum.take(@production_companies, 8) do %>
              <div class="text-center">
                <%= if company["logo_path"] do %>
                  <img
                    src={RichDataDisplayComponent.tmdb_image_url(company["logo_path"], "w200")}
                    alt={company["name"]}
                    class="h-12 w-auto mx-auto mb-2 object-contain"
                    loading="lazy"
                  />
                <% else %>
                  <div class="h-12 w-full bg-gray-100 rounded-lg flex items-center justify-center mb-2">
                    <.icon name="hero-building-office" class="h-6 w-6 text-gray-400" />
                  </div>
                <% end %>
                <p class="text-xs text-gray-600 line-clamp-2"><%= company["name"] %></p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- External Links -->
      <%= if @external_ids && has_external_links?(@external_ids) do %>
        <div>
          <h3 class="text-lg font-semibold text-gray-900 mb-3">External Links</h3>
          <div class="flex flex-wrap gap-3">
            <%= if @external_ids["imdb_id"] do %>
              <a
                href={"https://www.imdb.com/title/#{@external_ids["imdb_id"]}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200 transition-colors"
              >
                <.icon name="hero-film" class="w-4 h-4 mr-2" />
                IMDb
              </a>
            <% end %>

            <%= if @external_ids["facebook_id"] do %>
              <a
                href={"https://www.facebook.com/#{@external_ids["facebook_id"]}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 transition-colors"
              >
                Facebook
              </a>
            <% end %>

            <%= if @external_ids["twitter_id"] do %>
              <a
                href={"https://twitter.com/#{@external_ids["twitter_id"]}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-white bg-blue-400 rounded-md hover:bg-blue-500 transition-colors"
              >
                Twitter
              </a>
            <% end %>

            <%= if @external_ids["instagram_id"] do %>
              <a
                href={"https://www.instagram.com/#{@external_ids["instagram_id"]}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-white bg-pink-600 rounded-md hover:bg-pink-700 transition-colors"
              >
                Instagram
              </a>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data || %{}

    socket
    |> assign(:release_date, rich_data["release_date"])
    |> assign(:runtime, rich_data["runtime"])
    |> assign(:status, rich_data["status"])
    |> assign(:budget, rich_data["budget"])
    |> assign(:revenue, rich_data["revenue"])
    |> assign(:vote_average, rich_data["vote_average"])
    |> assign(:vote_count, rich_data["vote_count"])
    |> assign(:genres, rich_data["genres"] || [])
    |> assign(:spoken_languages, rich_data["spoken_languages"] || [])
    |> assign(:production_companies, rich_data["production_companies"] || [])
    |> assign(:external_ids, rich_data["external_ids"] || %{})
  end

  defp format_date(nil), do: "Unknown"
  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end

  defp format_runtime(nil), do: "Unknown"
  defp format_runtime(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 && mins > 0 -> "#{hours}h #{mins}m"
      hours > 0 -> "#{hours}h"
      mins > 0 -> "#{mins}m"
      true -> "Unknown"
    end
  end
  defp format_runtime(_), do: "Unknown"

  defp format_currency(nil), do: "Unknown"
  defp format_currency(amount) when is_integer(amount) and amount > 0 do
    # Format as millions for readability
    cond do
      amount >= 1_000_000_000 ->
        "$#{Float.round(amount / 1_000_000_000, 1)}B"
      amount >= 1_000_000 ->
        "$#{Float.round(amount / 1_000_000, 1)}M"
      amount >= 1_000 ->
        "$#{trunc(amount / 1_000)}K"
      true ->
        "$#{amount}"
    end
  end
  defp format_currency(_), do: "Unknown"

  defp has_external_links?(external_ids) when is_map(external_ids) do
    external_ids["imdb_id"] ||
    external_ids["facebook_id"] ||
    external_ids["twitter_id"] ||
    external_ids["instagram_id"]
  end
  defp has_external_links?(_), do: false
end
