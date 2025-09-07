defmodule EventasaurusWeb.Live.Components.MusicDetailsComponent do
  @moduledoc """
  Details section component for music content display.

  Displays additional information like duration, artist info, release dates,
  discography, and external links for tracks, artists, albums, and playlists.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

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
            <%= case @content_type do %>
              <% :track -> %>
                <%= render_track_details(assigns) %>
              <% :artist -> %>
                <%= render_artist_details(assigns) %>
              <% :album -> %>
                <%= render_album_details(assigns) %>
              <% :playlist -> %>
                <%= render_playlist_details(assigns) %>
              <% _ -> %>
                <%= render_generic_details(assigns) %>
            <% end %>
          </div>

          <!-- Right Column -->
          <div class="space-y-4">
            <%= render_additional_info(assigns) %>
          </div>
        </div>
      </div>

      <!-- External Links -->
      <%= if @external_urls && has_external_links?(@external_urls) do %>
        <div>
          <h3 class="text-lg font-semibold text-gray-900 mb-3">External Links</h3>
          <div class="flex flex-wrap gap-3">
            <%= if @external_urls["musicbrainz_url"] do %>
              <a
                href={@external_urls["musicbrainz_url"]}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200 transition-colors"
              >
                <.icon name="hero-musical-note" class="w-4 h-4 mr-2" />
                MusicBrainz
              </a>
            <% end %>

            <%= if @external_urls["wikipedia_url"] do %>
              <a
                href={@external_urls["wikipedia_url"]}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-white bg-gray-800 rounded-md hover:bg-gray-900 transition-colors"
              >
                <.icon name="hero-book-open" class="w-4 h-4 mr-2" />
                Wikipedia
              </a>
            <% end %>

            <%= if @external_urls["lastfm_url"] do %>
              <a
                href={@external_urls["lastfm_url"]}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700 transition-colors"
              >
                <.icon name="hero-play" class="w-4 h-4 mr-2" />
                Last.fm
              </a>
            <% end %>

            <%= if @external_urls["spotify_url"] do %>
              <a
                href={@external_urls["spotify_url"]}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-3 py-2 text-sm font-medium text-white bg-green-600 rounded-md hover:bg-green-700 transition-colors"
              >
                <.icon name="hero-play-circle" class="w-4 h-4 mr-2" />
                Spotify
              </a>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Track-specific details
  defp render_track_details(assigns) do
    ~H"""
    <%= if @duration_formatted do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Duration</dt>
        <dd class="text-sm text-gray-900"><%= @duration_formatted %></dd>
      </div>
    <% end %>

    <%= if @artist_credit && length(@artist_credit) > 0 do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Artists</dt>
        <dd class="text-sm text-gray-900">
          <div class="flex flex-wrap gap-2 mt-1">
            <%= for artist <- @artist_credit do %>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                <%= artist["name"] || artist["artist"]["name"] %>
              </span>
            <% end %>
          </div>
        </dd>
      </div>
    <% end %>

    <%= if @releases && length(@releases) > 0 do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Featured On</dt>
        <dd class="text-sm text-gray-900">
          <%= @releases |> Enum.take(3) |> Enum.map(& &1["title"]) |> Enum.join(", ") %>
          <%= if length(@releases) > 3 do %>
            <span class="text-gray-500">and <%= length(@releases) - 3 %> more</span>
          <% end %>
        </dd>
      </div>
    <% end %>

    <%= if @isrcs && length(@isrcs) > 0 do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">ISRC</dt>
        <dd class="text-sm text-gray-900 font-mono"><%= List.first(@isrcs) %></dd>
      </div>
    <% end %>
    """
  end

  # Artist-specific details
  defp render_artist_details(assigns) do
    ~H"""
    <%= if @type_name do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Type</dt>
        <dd class="text-sm text-gray-900"><%= String.capitalize(@type_name) %></dd>
      </div>
    <% end %>

    <%= if @country do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Country</dt>
        <dd class="text-sm text-gray-900"><%= @country %></dd>
      </div>
    <% end %>

    <%= if @life_span do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Active Period</dt>
        <dd class="text-sm text-gray-900">
          <%= format_life_span(@life_span) %>
        </dd>
      </div>
    <% end %>

    <%= if @begin_area do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Origin</dt>
        <dd class="text-sm text-gray-900"><%= @begin_area["name"] %></dd>
      </div>
    <% end %>

    <%= if @gender do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Gender</dt>
        <dd class="text-sm text-gray-900"><%= String.capitalize(@gender) %></dd>
      </div>
    <% end %>
    """
  end

  # Album-specific details
  defp render_album_details(assigns) do
    ~H"""
    <%= if @first_release_date do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Release Date</dt>
        <dd class="text-sm text-gray-900"><%= format_date(@first_release_date) %></dd>
      </div>
    <% end %>

    <%= if @primary_type do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Type</dt>
        <dd class="text-sm text-gray-900"><%= String.capitalize(@primary_type) %></dd>
      </div>
    <% end %>

    <%= if @secondary_types && length(@secondary_types) > 0 do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Categories</dt>
        <dd class="text-sm text-gray-900">
          <div class="flex flex-wrap gap-2 mt-1">
            <%= for type <- @secondary_types do %>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                <%= String.capitalize(type) %>
              </span>
            <% end %>
          </div>
        </dd>
      </div>
    <% end %>

    <%= if @artist_credit && length(@artist_credit) > 0 do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Artists</dt>
        <dd class="text-sm text-gray-900">
          <div class="flex flex-wrap gap-2 mt-1">
            <%= for artist <- @artist_credit do %>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                <%= artist["name"] || artist["artist"]["name"] %>
              </span>
            <% end %>
          </div>
        </dd>
      </div>
    <% end %>

    <%= if @release_count && @release_count > 1 do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Releases</dt>
        <dd class="text-sm text-gray-900"><%= @release_count %> versions</dd>
      </div>
    <% end %>
    """
  end

  # Playlist-specific details
  defp render_playlist_details(assigns) do
    ~H"""
    <%= if @track_count do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Tracks</dt>
        <dd class="text-sm text-gray-900"><%= @track_count %> songs</dd>
      </div>
    <% end %>

    <%= if @total_duration do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Total Duration</dt>
        <dd class="text-sm text-gray-900"><%= format_duration(@total_duration) %></dd>
      </div>
    <% end %>
    """
  end

  # Generic details fallback
  defp render_generic_details(assigns) do
    ~H"""
    <%= if @musicbrainz_id do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">MusicBrainz ID</dt>
        <dd class="text-sm text-gray-900 font-mono text-xs"><%= @musicbrainz_id %></dd>
      </div>
    <% end %>
    """
  end

  # Additional info column
  defp render_additional_info(assigns) do
    ~H"""
    <%= if @disambiguation do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Disambiguation</dt>
        <dd class="text-sm text-gray-900"><%= @disambiguation %></dd>
      </div>
    <% end %>

    <%= if @sort_name && @sort_name != @title do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Sort Name</dt>
        <dd class="text-sm text-gray-900"><%= @sort_name %></dd>
      </div>
    <% end %>

    <%= if @score do %>
      <div>
        <dt class="text-sm font-medium text-gray-500">Match Score</dt>
        <dd class="text-sm text-gray-900"><%= @score %>%</dd>
      </div>
    <% end %>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    metadata = socket.assigns.metadata || %{}
    additional_data = socket.assigns.additional_data || %{}

    socket
    |> assign(:content_type, socket.assigns.type)
    |> assign(:musicbrainz_id, metadata["musicbrainz_id"])
    |> assign(:duration_formatted, metadata["duration_formatted"])
    |> assign(:artist_credit, metadata["artist_credit"] || [])
    |> assign(:releases, metadata["releases"] || additional_data["releases"] || [])
    |> assign(:isrcs, metadata["isrcs"] || [])
    |> assign(:type_name, metadata["type_name"])
    |> assign(:country, metadata["country"])
    |> assign(:life_span, metadata["life_span"] || additional_data["life_span"])
    |> assign(:begin_area, metadata["begin_area"] || additional_data["areas"]["begin"])
    |> assign(:gender, metadata["gender"])
    |> assign(:first_release_date, metadata["first_release_date"])
    |> assign(:primary_type, metadata["primary_type"] || additional_data["primary_type"])
    |> assign(:secondary_types, metadata["secondary_types"] || additional_data["secondary_types"] || [])
    |> assign(:release_count, metadata["release_count"])
    |> assign(:track_count, metadata["track_count"])
    |> assign(:total_duration, metadata["total_duration"])
    |> assign(:disambiguation, metadata["disambiguation"])
    |> assign(:sort_name, metadata["sort_name"])
    |> assign(:score, metadata["score"])
    |> assign(:title, socket.assigns.title)
    |> assign(:external_urls, socket.assigns.external_urls || %{})
  end

  defp format_date(nil), do: "Unknown"
  defp format_date(date_string) when is_binary(date_string) do
    case String.length(date_string) do
      4 -> date_string  # Just year
      7 -> date_string  # Year-month
      10 -> 
        case Date.from_iso8601(date_string) do
          {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
          _ -> date_string
        end
      _ -> date_string
    end
  end
  defp format_date(_), do: "Unknown"

  defp format_life_span(%{"begin" => begin_date, "end" => end_date}) when not is_nil(begin_date) do
    if end_date do
      "#{begin_date} - #{end_date}"
    else
      "#{begin_date} - present"
    end
  end
  defp format_life_span(%{"begin" => begin_date}) when not is_nil(begin_date) do
    "#{begin_date} - present"
  end
  defp format_life_span(_), do: "Unknown"

  defp format_duration(nil), do: "Unknown"
  defp format_duration(milliseconds) when is_integer(milliseconds) do
    seconds = div(milliseconds, 1000)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      hours > 0 -> "#{hours}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
      minutes > 0 -> "#{minutes}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
      true -> "0:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
    end
  end
  defp format_duration(_), do: "Unknown"

  defp has_external_links?(external_urls) when is_map(external_urls) do
    external_urls["musicbrainz_url"] ||
    external_urls["wikipedia_url"] ||
    external_urls["lastfm_url"] ||
    external_urls["spotify_url"]
  end
  defp has_external_links?(_), do: false
end