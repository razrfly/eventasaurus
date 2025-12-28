defmodule EventasaurusWeb.Components.NearbyEventsComponent do
  @moduledoc """
  Component for displaying nearby events on activity pages.
  Shows geographically nearby upcoming activities with graceful fallbacks.
  """
  use EventasaurusWeb, :live_component
  require Logger

  alias Eventasaurus.CDN
  alias EventasaurusApp.Images.MovieImages

  def render(assigns) do
    ~H"""
    <div class="mt-8">
      <h2 class="text-2xl font-semibold text-gray-900 mb-6">
        <%= if @events && @events != [] do %>
          <%= gettext("Nearby Activities") %>
        <% else %>
          <%= gettext("More Activities") %>
        <% end %>
      </h2>

      <div :if={@events && @events != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <.event_card :for={event <- @events} event={event} language={@language} />
      </div>

      <div :if={!@events || @events == []} class="text-center py-8 bg-white rounded-lg">
        <p class="text-gray-500">
          <%= gettext("No nearby events at this time") %>
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
    """
  end

  # Event card component
  attr :event, :map, required: true
  attr :language, :string, default: "en"

  defp event_card(assigns) do
    # Calculate distance if venue has coordinates
    distance_text = format_distance(assigns.event)

    # Get localized title and description
    display_title = get_localized_title(assigns.event, assigns.language)

    # Format date
    formatted_date = format_event_date(assigns.event)

    # Get venue name
    venue_name = get_venue_name(assigns.event)

    # Get price display
    price_display = format_price(assigns.event)

    # Get event image URL
    image_url = get_event_image_url(assigns.event)

    assigns =
      assigns
      |> assign(:distance_text, distance_text)
      |> assign(:display_title, display_title)
      |> assign(:formatted_date, formatted_date)
      |> assign(:venue_name, venue_name)
      |> assign(:price_display, price_display)
      |> assign(:image_url, image_url)

    ~H"""
    <.link
      navigate={~p"/activities/#{@event.slug}"}
      class="group block bg-white rounded-lg shadow-sm hover:shadow-md transition-shadow overflow-hidden"
    >
      <div class="aspect-w-16 aspect-h-9 bg-gray-200">
        <%= if @image_url do %>
          <img
            src={CDN.url(@image_url, width: 400, height: 300, fit: "cover", quality: 85)}
            alt={@display_title}
            class="w-full h-48 object-cover group-hover:opacity-95 transition-opacity"
            loading="lazy"
          />
        <% else %>
          <div class="w-full h-48 bg-gray-100 flex items-center justify-center">
            <Heroicons.calendar_days class="w-12 h-12 text-gray-400" />
          </div>
        <% end %>
      </div>

      <div class="p-4">
        <h3 class="font-semibold text-gray-900 group-hover:text-blue-600 transition-colors line-clamp-2">
          <%= @display_title %>
        </h3>

        <div class="mt-2 space-y-1 text-sm text-gray-600">
          <div class="flex items-center">
            <Heroicons.calendar class="w-4 h-4 mr-1 flex-shrink-0" />
            <span class="truncate"><%= @formatted_date %></span>
          </div>

          <div class="flex items-center">
            <Heroicons.map_pin class="w-4 h-4 mr-1 flex-shrink-0" />
            <span class="truncate">
              <%= @venue_name %>
              <%= if @distance_text do %>
                <span class="text-gray-500">• <%= @distance_text %></span>
              <% end %>
            </span>
          </div>

          <%= if @price_display do %>
            <div class="flex items-center">
              <Heroicons.ticket class="w-4 h-4 mr-1 flex-shrink-0" />
              <span><%= @price_display %></span>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # Helper functions

  defp format_distance(_event) do
    # TODO: Calculate actual distance when we have the current venue coordinates
    # For now, return nil
    nil
  end

  defp get_localized_title(event, language) do
    case event.title_translations do
      nil ->
        event.title

      translations when is_map(translations) ->
        translations[language] || translations["en"] || event.title

      _ ->
        event.title
    end
  end

  defp format_event_date(event) do
    case event.starts_at do
      nil ->
        gettext("Date TBD")

      date ->
        # Format as "Dec 25, 2024 at 7:00 PM"
        # Note: %I is 12-hour format with leading zeros, we'll trim them
        formatted = Calendar.strftime(date, "%b %d, %Y at %I:%M %p")
        # Remove leading zero from hour if present
        String.replace(formatted, ~r/at 0(\d)/, "at \\1")
    end
  end

  defp get_venue_name(event) do
    case event.venue do
      %{name: name} when is_binary(name) -> name
      _ -> gettext("Venue TBD")
    end
  end

  defp get_primary_source(event) do
    # Get primary source based on priority and last_seen_at, similar to PublicEventShowLive
    case event.sources do
      [] ->
        nil

      sources when is_list(sources) ->
        sources
        |> Enum.sort_by(fn source ->
          priority =
            case source.metadata do
              %{"priority" => p} when is_integer(p) ->
                p

              %{"priority" => p} when is_binary(p) ->
                case Integer.parse(p) do
                  {num, _} -> num
                  _ -> 10
                end

              _ ->
                10
            end

          # Newer timestamps first (negative for descending sort)
          ts =
            case source.last_seen_at do
              %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
              _ -> 9_223_372_036_854_775_807
            end

          {priority, ts}
        end)
        |> List.first()

      _ ->
        nil
    end
  end

  defp format_price(event) do
    # Get pricing from the primary source instead of removed fields
    primary_source = get_primary_source(event)

    min = primary_source && primary_source.min_price
    max = primary_source && primary_source.max_price
    curr = primary_source && primary_source.currency
    is_free = (primary_source && primary_source.is_free) || (is_zero?(min) and is_zero?(max))

    cond do
      is_free ->
        gettext("Free")

      is_nil(min) and is_nil(max) ->
        nil

      not is_nil(min) and (is_nil(max) or amounts_equal?(min, max)) ->
        case format_currency(min, curr) do
          nil -> nil
          one -> one
        end

      not is_nil(min) and not is_nil(max) ->
        with a when is_binary(a) <- format_currency(min, curr),
             b when is_binary(b) <- format_currency(max, curr) do
          "#{a} - #{b}"
        else
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp format_currency(amount, currency) when is_nil(amount) or is_nil(currency), do: nil

  defp format_currency(amount, currency) do
    dec = to_decimal(amount)
    num = Decimal.to_string(dec, :normal)

    case String.upcase(currency) do
      "USD" -> "$" <> num
      "EUR" -> "€" <> num
      "GBP" -> "£" <> num
      "PLN" -> num <> " zł"
      code when is_binary(code) and byte_size(code) > 0 -> num <> " " <> code
      _ -> num
    end
  end

  defp is_zero?(nil), do: false
  defp is_zero?(%Decimal{} = d), do: Decimal.compare(d, 0) == :eq
  defp is_zero?(n) when is_integer(n), do: n == 0
  defp is_zero?(n) when is_float(n), do: n == 0.0

  defp is_zero?(s) when is_binary(s) do
    case Decimal.new(s) do
      %Decimal{} = d -> Decimal.compare(d, 0) == :eq
      _ -> false
    end
  rescue
    _ -> false
  end

  defp amounts_equal?(a, b) do
    with %Decimal{} = da <- to_decimal(a),
         %Decimal{} = db <- to_decimal(b) do
      Decimal.compare(da, db) == :eq
    else
      _ -> false
    end
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(nil), do: nil
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)

  defp to_decimal(s) when is_binary(s) do
    Decimal.new(s)
  rescue
    _ -> nil
  end

  defp get_event_image_url(event) do
    # Check if cover_image_url was added by enrichment (Phase 2)
    # This field is dynamically added by PublicEventsEnhanced.enrich_event_images/2
    cover_url = Map.get(event, :cover_image_url)

    Logger.info(
      "🖼️  NearbyEventsComponent - Event #{event.id}, cover_image_url: #{inspect(cover_url)}"
    )

    case cover_url do
      nil ->
        Logger.info("⚠️  No cover_image_url, checking movie/source images")
        # Not enriched yet, use legacy image selection logic
        # For movie events, prioritize movie poster/backdrop from TMDb
        # This ensures we show correct movie images instead of potentially wrong scraper data
        case get_movie_image(event) do
          nil ->
            # Fall back to source image if no movie image available
            result = get_image_from_source(event)
            Logger.info("📸 Legacy image result: #{inspect(result)}")
            result

          image_url ->
            Logger.info("🎬 Using movie image: #{String.slice(image_url, 0, 50)}...")
            image_url
        end

      url when is_binary(url) ->
        Logger.info("✅ Using enriched URL: #{String.slice(url, 0, 50)}...")
        # Use enriched URL (includes Unsplash fallback if needed)
        url
    end
  end

  defp get_movie_image(event) do
    case event.movies do
      [movie | _] when not is_nil(movie) ->
        # Prefer backdrop, fall back to poster - use cached URLs with fallback to original
        backdrop = MovieImages.get_backdrop_url(movie.id, movie.backdrop_url)
        poster = MovieImages.get_poster_url(movie.id, movie.poster_url)

        cond do
          is_binary(backdrop) and backdrop != "" -> backdrop
          is_binary(poster) and poster != "" -> poster
          true -> nil
        end

      _ ->
        nil
    end
  end

  defp get_image_from_source(event) do
    # Use primary source (sorted by priority and last_seen_at) to get image
    # This ensures we show the most authoritative/recent image
    primary_source = get_primary_source(event)

    case primary_source do
      nil ->
        nil

      source ->
        # Try direct image_url field first (most common)
        case source do
          %{image_url: url} when is_binary(url) and url != "" ->
            url

          _ ->
            # Check metadata for image URLs
            case source.metadata do
              %{"image_url" => url} when is_binary(url) and url != "" -> url
              %{"images" => [%{"url" => url} | _]} when is_binary(url) and url != "" -> url
              %{"image" => url} when is_binary(url) and url != "" -> url
              _ -> nil
            end
        end
    end
  end
end
