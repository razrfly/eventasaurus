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
  def movie_rich_data_display(assigns) do
    ~H"""
    <div class="movie-rich-data-display space-y-6">
      <%= if @rich_data do %>
        <% metadata = @rich_data["metadata"] || %{} %>
        <% media = @rich_data["media"] || %{} %>
        <% images = media["images"] || %{} %>
        <% posters = images["posters"] || [] %>
        <% cast = @rich_data["cast"] || [] %>

        <!-- Movie Header -->
        <div class="flex gap-6">
          <%= if length(posters) > 0 do %>
            <% poster = List.first(posters) %>
            <%= if is_map(poster) && poster["file_path"] do %>
              <div class="flex-shrink-0">
                <img
                  src={tmdb_image_url(poster["file_path"], "w300")}
                  alt={metadata["title"] || "Movie poster"}
                  class="w-32 h-48 object-cover rounded-lg shadow-md"
                />
              </div>
            <% end %>
          <% end %>

          <div class="flex-1">
            <h2 class="text-2xl font-bold text-gray-900 mb-2">
              <%= metadata["title"] %>
              <%= if metadata["release_date"] && is_binary(metadata["release_date"]) && String.length(metadata["release_date"]) >= 4 do %>
                <span class="text-gray-600 font-normal">(<%= String.slice(metadata["release_date"], 0, 4) %>)</span>
              <% end %>
            </h2>

            <%= if metadata["tagline"] && metadata["tagline"] != "" do %>
              <p class="text-lg text-gray-600 italic mb-4"><%= metadata["tagline"] %></p>
            <% end %>

            <%= if metadata["overview"] do %>
              <p class="text-gray-700 mb-4"><%= metadata["overview"] %></p>
            <% end %>

            <div class="grid grid-cols-2 gap-4 text-sm">
              <%= if metadata["runtime"] do %>
                <div>
                  <span class="font-medium text-gray-900">Runtime:</span>
                  <span class="text-gray-700"><%= metadata["runtime"] %> minutes</span>
                </div>
              <% end %>

              <%= if metadata["genres"] && length(metadata["genres"]) > 0 do %>
                <div>
                  <span class="font-medium text-gray-900">Genres:</span>
                  <span class="text-gray-700"><%=
                    metadata["genres"]
                    |> Enum.map(fn
                      genre when is_binary(genre) -> genre
                      genre when is_map(genre) -> genre["name"] || ""
                      _ -> ""
                    end)
                    |> Enum.join(", ")
                  %></span>
                </div>
              <% end %>

              <%= if metadata["vote_average"] && is_number(metadata["vote_average"]) do %>
                <div>
                  <span class="font-medium text-gray-900">Rating:</span>
                  <span class="text-gray-700"><%= Float.round(metadata["vote_average"], 1) %>/10</span>
                </div>
              <% end %>

              <%= if metadata["budget"] && metadata["budget"] > 0 do %>
                <div>
                  <span class="font-medium text-gray-900">Budget:</span>
                  <span class="text-gray-700">$<%= metadata["budget"] %></span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Cast Section -->
        <%= if is_list(cast) && length(cast) > 0 do %>
          <div class="border-t border-gray-200 pt-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Cast</h3>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
              <%= for actor <- Enum.take(cast, 8) do %>
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
        <%= if metadata["imdb_id"] do %>
          <div class="border-t border-gray-200 pt-6">
            <a
              href={"https://www.imdb.com/title/#{metadata["imdb_id"]}"}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-yellow-600 hover:bg-yellow-700"
            >
              View on IMDb
            </a>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Helper function to generate TMDB image URLs using centralized utility
  defp tmdb_image_url(path, size) do
    EventasaurusWeb.Live.Components.RichDataDisplayComponent.tmdb_image_url(path, size)
  end
end
