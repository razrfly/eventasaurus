defmodule EventasaurusWeb.EventHTML do
  use EventasaurusWeb, :html

  embed_templates "event_html/*"

  # No need for explicit render functions as Phoenix 1.7+ handles this automatically
  # when using embed_templates

  # Helper function to format datetime with timezone conversion
  def format_datetime(dt, timezone \\ nil)

  def format_datetime(%DateTime{} = dt, timezone) do
    converted_dt =
      if timezone do
        EventasaurusWeb.TimezoneHelpers.convert_to_timezone(dt, timezone)
      else
        dt
      end

    Calendar.strftime(converted_dt, "%A, %B %d · %H:%M")
  end

  def format_datetime(_, _), do: "Date not set"

  # Helper function to format time only
  def format_time(dt, timezone \\ nil)

  def format_time(%DateTime{} = dt, timezone) do
    converted_dt =
      if timezone do
        EventasaurusWeb.TimezoneHelpers.convert_to_timezone(dt, timezone)
      else
        dt
      end

    Calendar.strftime(converted_dt, "%H:%M")
  end

  def format_time(_, _), do: ""

  # Helper function to format date only
  def format_date(dt, timezone \\ nil)

  def format_date(%DateTime{} = dt, timezone) do
    converted_dt =
      if timezone do
        EventasaurusWeb.TimezoneHelpers.convert_to_timezone(dt, timezone)
      else
        dt
      end

    Calendar.strftime(converted_dt, "%A, %B %d")
  end

  def format_date(_, _), do: ""

  def format_event_datetime(event) do
    assigns = %{event: event}

    ~H"""
    <p class="text-gray-700">
      <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%A, %B %d, %Y") %>
    </p>
    <p class="text-gray-600 text-sm">
      <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%H:%M") %>
      <%= if @event.ends_at do %>
        - <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.ends_at, @event.timezone) |> Calendar.strftime("%H:%M") %>
      <% end %>
      <%= if @event.timezone do %>(<%= @event.timezone %>)<% end %>
    </p>
    """
  end

  # Rich data display component for controller templates
  # Supports two data formats:
  # 1. Full TMDB API structure: metadata.title, media.images.posters[], cast[]
  # 2. Simple Movie model structure: title, poster_url, release_date, runtime (flat)
  def movie_rich_data_display(assigns) do
    # Normalize the data structure to handle both formats
    assigns = normalize_movie_rich_data(assigns)

    ~H"""
    <div class="movie-rich-data-display space-y-6">
      <%= if @rich_data do %>
        <!-- Movie Header -->
        <div class="flex gap-6">
          <%= if @poster_url do %>
            <div class="flex-shrink-0">
              <img
                src={@poster_url}
                alt={@title || "Movie poster"}
                class="w-32 h-48 object-cover rounded-lg shadow-md"
              />
            </div>
          <% end %>

          <div class="flex-1">
            <h2 class="text-2xl font-bold text-gray-900 mb-2">
              <%= @title %>
              <%= if @release_year do %>
                <span class="text-gray-600 font-normal">(<%= @release_year %>)</span>
              <% end %>
            </h2>

            <%= if @tagline && @tagline != "" do %>
              <p class="text-lg text-gray-600 italic mb-4"><%= @tagline %></p>
            <% end %>

            <%= if @overview do %>
              <p class="text-gray-700 mb-4"><%= @overview %></p>
            <% end %>

            <div class="grid grid-cols-2 gap-4 text-sm">
              <%= if @runtime do %>
                <div>
                  <span class="font-medium text-gray-900">Runtime:</span>
                  <span class="text-gray-700"><%= @runtime %> minutes</span>
                </div>
              <% end %>

              <%= if @genres && length(@genres) > 0 do %>
                <div>
                  <span class="font-medium text-gray-900">Genres:</span>
                  <span class="text-gray-700"><%= Enum.join(@genres, ", ") %></span>
                </div>
              <% end %>

              <%= if @vote_average do %>
                <div>
                  <span class="font-medium text-gray-900">Rating:</span>
                  <span class="text-gray-700"><%= @vote_average %>/10</span>
                </div>
              <% end %>

              <%= if @budget && @budget > 0 do %>
                <div>
                  <span class="font-medium text-gray-900">Budget:</span>
                  <span class="text-gray-700">$<%= @budget %></span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Cast Section -->
        <%= if is_list(@cast) && length(@cast) > 0 do %>
          <div class="border-t border-gray-200 pt-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Cast</h3>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
              <%= for actor <- Enum.take(@cast, 8) do %>
                <%= if is_map(actor) do %>
                  <div class="text-center">
                    <%= if actor["profile_path"] do %>
                      <img
                        src={tmdb_image_url(actor["profile_path"], "w185")}
                        alt={actor["name"] || "Actor"}
                        class="w-16 h-16 rounded-full object-cover mx-auto mb-2"
                      />
                    <% else %>
                      <div class="w-16 h-16 bg-gray-300 rounded-full mx-auto mb-2 flex items-center justify-center">
                        <span class="text-gray-500 text-xs">No Photo</span>
                      </div>
                    <% end %>
                    <p class="font-medium text-sm text-gray-900"><%= actor["name"] || "Unknown" %></p>
                    <p class="text-xs text-gray-600"><%= actor["character"] || "" %></p>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- External Link -->
        <%= if @imdb_id do %>
          <div class="border-t border-gray-200 pt-6">
            <a
              href={"https://www.imdb.com/title/#{@imdb_id}"}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-yellow-600 hover:bg-yellow-700"
            >
              View on IMDb
            </a>
          </div>
        <% end %>

        <!-- TMDB Link for simple format -->
        <%= if @tmdb_id && !@imdb_id do %>
          <div class="border-t border-gray-200 pt-6">
            <a
              href={"https://www.themoviedb.org/movie/#{@tmdb_id}"}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
            >
              View on TMDB
            </a>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Normalize movie rich data to a consistent format
  # Handles both full TMDB API structure and simple Movie model structure
  defp normalize_movie_rich_data(assigns) do
    rich_data = assigns.rich_data

    if rich_data do
      # Check if this is the full TMDB structure (has metadata key) or simple structure
      if rich_data["metadata"] do
        # Full TMDB API structure
        metadata = rich_data["metadata"] || %{}
        media = rich_data["media"] || %{}
        images = media["images"] || %{}
        posters = images["posters"] || []

        poster_url =
          case posters do
            [%{"file_path" => file_path} | _] when is_binary(file_path) ->
              tmdb_image_url(file_path, "w300")

            _ ->
              nil
          end

        release_year = extract_year(metadata["release_date"])

        genres =
          (metadata["genres"] || [])
          |> Enum.map(fn
            genre when is_binary(genre) -> genre
            genre when is_map(genre) -> genre["name"] || ""
            _ -> ""
          end)
          |> Enum.filter(&(&1 != ""))

        vote_average =
          case metadata["vote_average"] do
            avg when is_number(avg) -> Float.round(avg, 1)
            _ -> nil
          end

        assigns
        |> Map.put(:title, metadata["title"])
        |> Map.put(:poster_url, poster_url)
        |> Map.put(:release_year, release_year)
        |> Map.put(:tagline, metadata["tagline"])
        |> Map.put(:overview, metadata["overview"])
        |> Map.put(:runtime, metadata["runtime"])
        |> Map.put(:genres, genres)
        |> Map.put(:vote_average, vote_average)
        |> Map.put(:budget, metadata["budget"])
        |> Map.put(:cast, rich_data["cast"] || [])
        |> Map.put(:imdb_id, metadata["imdb_id"])
        |> Map.put(:tmdb_id, metadata["tmdb_id"] || rich_data["tmdb_id"])
      else
        # Simple Movie model structure (flat keys)
        release_year = extract_year(rich_data["release_date"])

        assigns
        |> Map.put(:title, rich_data["title"])
        |> Map.put(:poster_url, rich_data["poster_url"])
        |> Map.put(:release_year, release_year)
        |> Map.put(:tagline, nil)
        |> Map.put(:overview, nil)
        |> Map.put(:runtime, rich_data["runtime"])
        |> Map.put(:genres, [])
        |> Map.put(:vote_average, nil)
        |> Map.put(:budget, nil)
        |> Map.put(:cast, [])
        |> Map.put(:imdb_id, nil)
        |> Map.put(:tmdb_id, rich_data["tmdb_id"])
      end
    else
      assigns
      |> Map.put(:title, nil)
      |> Map.put(:poster_url, nil)
      |> Map.put(:release_year, nil)
      |> Map.put(:tagline, nil)
      |> Map.put(:overview, nil)
      |> Map.put(:runtime, nil)
      |> Map.put(:genres, [])
      |> Map.put(:vote_average, nil)
      |> Map.put(:budget, nil)
      |> Map.put(:cast, [])
      |> Map.put(:imdb_id, nil)
      |> Map.put(:tmdb_id, nil)
    end
  end

  # Extract year from release_date string
  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil

  defp extract_year(date) when is_binary(date) and byte_size(date) >= 4 do
    String.slice(date, 0, 4)
  end

  defp extract_year(_), do: nil

  # Helper function to generate TMDB image URLs using centralized utility
  defp tmdb_image_url(path, size) do
    EventasaurusWeb.Live.Components.RichDataDisplayComponent.tmdb_image_url(path, size)
  end
end
