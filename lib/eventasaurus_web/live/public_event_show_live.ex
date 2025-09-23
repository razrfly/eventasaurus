defmodule EventasaurusWeb.PublicEventShowLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # Get language from connect params if connected; default to English
    params = get_connect_params(socket) || %{}
    language = params["locale"] || "en"

    socket =
      socket
      |> assign(:language, language)
      |> assign(:event, nil)
      |> assign(:loading, true)
      |> assign(:selected_occurrence, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
    socket =
      socket
      |> fetch_event(slug)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  defp fetch_event(socket, slug) do
    language = socket.assigns.language

    event =
      from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        where: pe.slug == ^slug,
        preload: [:venue, :categories, :performers, sources: :source]
      )
      |> Repo.one()

    case event do
      nil ->
        socket
        |> put_flash(:error, gettext("Event not found"))
        |> push_navigate(to: ~p"/activities")

      event ->
        # Enrich with display fields
        enriched_event =
          event
          |> Map.put(:display_title, get_localized_title(event, language))
          |> Map.put(:display_description, get_localized_description(event, language))
          |> Map.put(:cover_image_url, get_cover_image_url(event))
          |> Map.put(:occurrence_list, parse_occurrences(event))

        socket
        |> assign(:event, enriched_event)
        |> assign(:selected_occurrence, select_default_occurrence(enriched_event))
    end
  end

  defp get_localized_title(event, language) do
    case event.title_translations do
      nil -> event.title
      translations when is_map(translations) ->
        translations[language] || translations["en"] || event.title
      _ -> event.title
    end
  end

  defp get_localized_description(event, language) do
    # Sort sources by priority and take the first one's description
    sorted_sources = event.sources
    |> Enum.sort_by(fn source ->
      priority = case source.metadata do
        %{"priority" => p} when is_integer(p) -> p
        %{"priority" => p} when is_binary(p) ->
          case Integer.parse(p) do
            {num, _} -> num
            _ -> 10
          end
        _ -> 10
      end

      # Newer timestamps first (negative for descending sort)
      ts = case source.last_seen_at do
        %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
        _ -> 9_223_372_036_854_775_807
      end

      {priority, ts}
    end)

    case sorted_sources do
      [source | _] ->
        case source.description_translations do
          nil -> nil
          translations when is_map(translations) ->
            translations[language] || translations["en"] || nil
          _ -> nil
        end
      _ -> nil
    end
  end

  defp get_cover_image_url(event) do
    # Sort sources by priority and try to get the first available image
    sorted_sources = event.sources
    |> Enum.sort_by(fn source ->
      priority = case source.metadata do
        %{"priority" => p} when is_integer(p) -> p
        %{"priority" => p} when is_binary(p) ->
          case Integer.parse(p) do
            {num, _} -> num
            _ -> 10
          end
        _ -> 10
      end

      # Newer timestamps first (negative for descending sort)
      ts = case source.last_seen_at do
        %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
        _ -> 9_223_372_036_854_775_807
      end

      {priority, ts}
    end)

    # Try to extract image from sources with URL sanitization
    Enum.find_value(sorted_sources, fn source ->
      url = source.image_url || extract_image_from_metadata(source.metadata)
      normalize_http_url(url)
    end)
  end

  defp extract_image_from_metadata(nil), do: nil
  defp extract_image_from_metadata(metadata) do
    cond do
      # Ticketmaster stores images in an array
      images = get_in(metadata, ["ticketmaster_data", "images"]) ->
        case images do
          [%{"url" => url} | _] when is_binary(url) -> url
          _ -> nil
        end

      # Bandsintown and Karnet store in image_url
      url = metadata["image_url"] ->
        url

      true ->
        nil
    end
  end

  @impl true
  def handle_event("select_occurrence", %{"index" => index}, socket) do
    occurrence_index = String.to_integer(index)
    occurrence_list = socket.assigns.event.occurrence_list || []

    selected = Enum.at(occurrence_list, occurrence_index)

    {:noreply, assign(socket, :selected_occurrence, selected)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @loading do %>
        <div class="flex justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>
      <% else %>
        <%= if @event do %>
          <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <!-- Breadcrumb -->
            <div class="mb-6">
              <nav class="flex items-center space-x-2 text-sm">
                <.link navigate={~p"/activities"} class="text-blue-600 hover:text-blue-800">
                  <%= gettext("All Activities") %>
                </.link>
                <span class="text-gray-500">/</span>
                <%= if @event.categories && @event.categories != [] do %>
                  <% category = List.first(@event.categories) %>
                  <.link
                    navigate={~p"/activities/category/#{String.downcase(category.name)}"}
                    class="text-blue-600 hover:text-blue-800"
                  >
                    <%= category.name %>
                  </.link>
                  <span class="text-gray-500">/</span>
                <% end %>
                <span class="text-gray-700"><%= @event.display_title %></span>
              </nav>
            </div>

            <!-- Event Header -->
            <div class="bg-white rounded-lg shadow-lg overflow-hidden">
              <!-- Cover Image -->
              <%= if @event.cover_image_url do %>
                <div class="h-96 relative">
                  <img
                    src={@event.cover_image_url}
                    alt={@event.display_title}
                    class="w-full h-full object-cover"
                  />
                </div>
              <% end %>

              <div class="p-8">
                <!-- Categories -->
                <%= if @event.categories && @event.categories != [] do %>
                  <div class="mb-4 flex flex-wrap gap-2">
                    <%= for category <- @event.categories do %>
                      <span
                        class="px-3 py-1 rounded-full text-sm font-medium text-white"
                        style={"background-color: #{category.color || "#6B7280"}"}
                      >
                        <%= category.name %>
                      </span>
                    <% end %>
                  </div>
                <% end %>

                <!-- Title -->
                <h1 class="text-4xl font-bold text-gray-900 mb-6">
                  <%= @event.display_title %>
                </h1>

                <!-- Key Details Grid -->
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                  <!-- Date & Time -->
                  <div>
                    <div class="flex items-center text-gray-600 mb-1">
                      <Heroicons.calendar class="w-5 h-5 mr-2" />
                      <span class="font-medium"><%= gettext("Date & Time") %></span>
                    </div>
                    <p class="text-gray-900">
                      <%= if @selected_occurrence do %>
                        <%= format_occurrence_datetime(@selected_occurrence) %>
                      <% else %>
                        <%= format_event_datetime(@event.starts_at) %>
                        <%= if @event.ends_at do %>
                          <br />
                          <span class="text-sm text-gray-600">
                            <%= gettext("Until") %> <%= format_event_datetime(@event.ends_at) %>
                          </span>
                        <% end %>
                      <% end %>
                    </p>
                  </div>

                  <!-- Venue -->
                  <div>
                    <div class="flex items-center text-gray-600 mb-1">
                      <Heroicons.map_pin class="w-5 h-5 mr-2" />
                      <span class="font-medium"><%= gettext("Venue") %></span>
                    </div>
                    <p class="text-gray-900">
                      <%= @event.venue.name %>
                      <%= if @event.venue.address do %>
                        <br />
                        <span class="text-sm text-gray-600">
                          <%= @event.venue.address %>
                        </span>
                      <% end %>
                    </p>
                  </div>

                  <!-- Price -->
                  <div>
                    <div class="flex items-center text-gray-600 mb-1">
                      <Heroicons.currency_dollar class="w-5 h-5 mr-2" />
                      <span class="font-medium"><%= gettext("Price") %></span>
                    </div>
                    <p class="text-gray-900">
                      <%= format_price_range(@event) %>
                    </p>
                  </div>

                  <!-- Ticket Link -->
                  <%= if @event.ticket_url do %>
                    <div>
                      <a
                        href={@event.ticket_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
                      >
                        <Heroicons.ticket class="w-5 h-5 mr-2" />
                        <%= gettext("Get Tickets") %>
                      </a>
                    </div>
                  <% end %>
                </div>

                <!-- Multiple Occurrences Selection -->
                <%= if @event.occurrence_list && length(@event.occurrence_list) > 1 do %>
                  <div class="mb-8 p-6 bg-gray-50 rounded-lg">
                    <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
                      <Heroicons.calendar_days class="w-5 h-5 mr-2" />
                      <%= case occurrence_display_type(@event.occurrence_list) do %>
                        <% :daily_show -> %>
                          <%= gettext("Daily Shows Available") %>
                        <% :same_day_multiple -> %>
                          <%= gettext("Select a Time") %>
                        <% :multi_day -> %>
                          <%= gettext("Multiple Dates Available") %>
                        <% _ -> %>
                          <%= gettext("Select Date & Time") %>
                      <% end %>
                    </h3>

                    <%= case occurrence_display_type(@event.occurrence_list) do %>
                      <% :daily_show -> %>
                        <!-- Calendar-like view for events with many dates -->
                        <div class="mb-4">
                          <p class="text-sm text-gray-600 mb-4">
                            <%= gettext("%{count} shows from %{start} to %{end}",
                                count: length(@event.occurrence_list),
                                start: format_date_only(List.first(@event.occurrence_list).datetime),
                                end: format_date_only(List.last(@event.occurrence_list).datetime)) %>
                          </p>
                          <div class="grid grid-cols-7 gap-2 max-h-96 overflow-y-auto">
                            <%= for {occurrence, index} <- Enum.with_index(@event.occurrence_list) do %>
                              <button
                                phx-click="select_occurrence"
                                phx-value-index={index}
                                class={"px-3 py-2 text-sm rounded-lg transition #{if @selected_occurrence == occurrence, do: "bg-blue-600 text-white", else: "bg-white border border-gray-200 hover:bg-gray-50"}"}
                              >
                                <%= format_short_date(occurrence.datetime) %>
                              </button>
                            <% end %>
                          </div>
                        </div>

                      <% :same_day_multiple -> %>
                        <!-- Time selection for same day events -->
                        <div class="space-y-2">
                          <%= for {occurrence, index} <- Enum.with_index(@event.occurrence_list) do %>
                            <button
                              phx-click="select_occurrence"
                              phx-value-index={index}
                              class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected_occurrence == occurrence, do: "border-blue-600 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
                            >
                              <span class="font-medium"><%= format_time_only(occurrence.datetime) %></span>
                              <%= if occurrence.label do %>
                                <span class="ml-2 text-sm text-gray-600"><%= occurrence.label %></span>
                              <% end %>
                            </button>
                          <% end %>
                        </div>

                      <% _ -> %>
                        <!-- List view for small number of dates -->
                        <div class="space-y-2">
                          <%= for {occurrence, index} <- Enum.with_index(@event.occurrence_list) do %>
                            <button
                              phx-click="select_occurrence"
                              phx-value-index={index}
                              class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected_occurrence == occurrence, do: "border-blue-600 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
                            >
                              <span class="font-medium"><%= format_occurrence_datetime(occurrence) %></span>
                              <%= if occurrence.label do %>
                                <span class="ml-2 text-sm text-gray-600"><%= occurrence.label %></span>
                              <% end %>
                            </button>
                          <% end %>
                        </div>
                    <% end %>

                    <div class="mt-4 p-3 bg-blue-50 rounded-lg">
                      <p class="text-sm text-blue-900">
                        <span class="font-medium"><%= gettext("Selected:") %></span>
                        <%= format_occurrence_datetime(@selected_occurrence || List.first(@event.occurrence_list)) %>
                      </p>
                    </div>
                  </div>
                <% end %>

                <!-- Description -->
                <%= if @event.display_description do %>
                  <div class="mb-8">
                    <h2 class="text-2xl font-semibold text-gray-900 mb-4">
                      <%= gettext("About This Event") %>
                    </h2>
                    <div class="prose max-w-none text-gray-700">
                      <%= format_description(@event.display_description) %>
                    </div>
                  </div>
                <% end %>

                <!-- Performers -->
                <%= if @event.performers && @event.performers != [] do %>
                  <div class="mb-8">
                    <h2 class="text-2xl font-semibold text-gray-900 mb-4">
                      <%= gettext("Performers") %>
                    </h2>
                    <div class="flex flex-wrap gap-3">
                      <%= for performer <- @event.performers do %>
                        <span class="px-4 py-2 bg-gray-100 rounded-lg text-gray-800 font-medium">
                          <%= performer.name %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- Sources -->
                <div class="mt-12 pt-8 border-t border-gray-200">
                  <h3 class="text-sm font-medium text-gray-500 mb-3">
                    <%= gettext("Event Sources") %>
                  </h3>
                  <div class="flex flex-wrap gap-4">
                    <%= for source <- @event.sources do %>
                      <% source_url = get_source_url(source) %>
                      <% source_name = get_source_name(source) %>
                      <div class="text-sm">
                        <%= if source_url do %>
                          <a href={source_url} target="_blank" rel="noopener noreferrer" class="font-medium text-blue-600 hover:text-blue-800">
                            <%= source_name %>
                            <Heroicons.arrow_top_right_on_square class="w-3 h-3 inline ml-1" />
                          </a>
                        <% else %>
                          <span class="font-medium text-gray-700">
                            <%= source_name %>
                          </span>
                        <% end %>
                        <span class="text-gray-500 ml-2">
                          <%= gettext("Last updated") %> <%= format_relative_time(source.last_seen_at) %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <!-- Related Events -->
            <div class="mt-8">
              <h2 class="text-2xl font-semibold text-gray-900 mb-6">
                <%= gettext("More Activities") %>
              </h2>
              <div class="text-center py-8 bg-white rounded-lg">
                <p class="text-gray-500">
                  <%= gettext("Related events coming soon") %>
                </p>
                <.link
                  navigate={~p"/activities"}
                  class="mt-4 inline-flex items-center text-blue-600 hover:text-blue-800"
                >
                  <%= gettext("Browse all activities") %>
                  <Heroicons.arrow_right class="w-4 h-4 ml-1" />
                </.link>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Helper Functions
  defp format_event_datetime(nil), do: gettext("TBD")
  defp format_event_datetime(datetime) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  defp format_price_range(event) do
    symbol = currency_symbol(event.currency)
    cond do
      event.min_price && event.max_price && event.min_price == event.max_price ->
        "#{symbol}#{event.min_price}"
      event.min_price && event.max_price ->
        "#{symbol}#{event.min_price} - #{symbol}#{event.max_price}"
      event.min_price ->
        gettext("From %{price}", price: "#{symbol}#{event.min_price}")
      event.max_price ->
        gettext("Up to %{price}", price: "#{symbol}#{event.max_price}")
      true ->
        gettext("See details")
    end
  end

  defp currency_symbol(nil), do: "$"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("PLN"), do: "zł"
  defp currency_symbol(_), do: "$"

  defp format_description(nil), do: Phoenix.HTML.raw("")
  defp format_description(description) do
    # Escapes HTML and converts newlines to <br>, returning Safe HTML
    Phoenix.HTML.Format.text_to_html(description, escape: true)
  end

  defp get_source_url(source) do
    # Guard against nil metadata and sanitize URLs
    md = source.metadata || %{}
    url =
      cond do
        # Ticketmaster stores URL in ticketmaster_data.url
        url = get_in(md, ["ticketmaster_data", "url"]) -> url
        # Bandsintown might have it in event_url or url
        url = md["event_url"] -> url
        url = md["url"] -> url
        # Karnet might have it in a different location
        url = md["link"] -> url
        # Fallback to source_url if it exists
        source.source_url -> source.source_url
        true -> nil
      end

    normalize_http_url(url)
  end

  defp normalize_http_url(nil), do: nil
  defp normalize_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} = uri when scheme in ["http", "https"] -> URI.to_string(uri)
      _ -> nil
    end
  end

  defp get_source_name(source) do
    # Use the associated source name if available
    if source.source do
      source.source.name
    else
      "Unknown"
    end
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 3600 -> gettext("%{count} minutes ago", count: div(diff, 60))
      diff < 86400 -> gettext("%{count} hours ago", count: div(diff, 3600))
      diff < 604800 -> gettext("%{count} days ago", count: div(diff, 86400))
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  # Occurrence helper functions
  defp parse_occurrences(%{occurrences: nil}), do: nil
  defp parse_occurrences(%{occurrences: %{"dates" => dates}}) when is_list(dates) do
    dates
    |> Enum.map(fn date_info ->
      with {:ok, date} <- Date.from_iso8601(date_info["date"]),
           {:ok, time} <- parse_time(date_info["time"]) do
        datetime = DateTime.new!(date, time, "Etc/UTC")

        %{
          datetime: datetime,
          date: date,
          time: time,
          external_id: date_info["external_id"],
          label: date_info["label"]
        }
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.datetime, DateTime)
  end
  defp parse_occurrences(_), do: nil

  defp parse_time(nil), do: {:ok, ~T[20:00:00]}
  defp parse_time(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [h, m] -> Time.new(String.to_integer(h), String.to_integer(m), 0)
      [h, m, s] -> Time.new(String.to_integer(h), String.to_integer(m), String.to_integer(s))
      _ -> {:ok, ~T[20:00:00]}
    end
  end
  defp parse_time(_), do: {:ok, ~T[20:00:00]}

  defp select_default_occurrence(%{occurrence_list: nil}), do: nil
  defp select_default_occurrence(%{occurrence_list: []}), do: nil
  defp select_default_occurrence(%{occurrence_list: occurrences}) do
    now = DateTime.utc_now()
    # Find the next upcoming occurrence, or the first if all are in the past
    Enum.find(occurrences, List.first(occurrences), fn occ ->
      DateTime.compare(occ.datetime, now) == :gt
    end)
  end

  defp occurrence_display_type(nil), do: :none
  defp occurrence_display_type([]), do: :none
  defp occurrence_display_type(occurrences) do
    cond do
      # More than 20 dates - daily show
      length(occurrences) > 20 ->
        :daily_show

      # All on same day - time selection
      all_same_day?(occurrences) ->
        :same_day_multiple

      # Default - multi day
      true ->
        :multi_day
    end
  end

  defp all_same_day?(occurrences) do
    dates = Enum.map(occurrences, & &1.date) |> Enum.uniq()
    length(dates) == 1
  end

  defp format_occurrence_datetime(nil), do: gettext("Select a date")
  defp format_occurrence_datetime(%{datetime: datetime}) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  defp format_date_only(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp format_time_only(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp format_short_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d")
  end
end