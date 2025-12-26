defmodule EventasaurusWeb.Live.Components.VenueHeroComponent do
  @moduledoc """
  Hero section component for venue/restaurant/activity display.

  Features primary photo, title, rating, price level, and key metadata.
  Uses cached_images table (R2 storage) as the source for venue photos.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

  alias EventasaurusApp.Images.ImageCacheService
  alias EventasaurusApp.Images.CachedImage

  @impl true
  def update(assigns, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger

      Logger.debug(
        "VenueHeroComponent update called with rich_data: #{inspect(assigns[:rich_data])}"
      )
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article class="relative" role="main" aria-labelledby="venue-title">
      <%= if @has_primary_photo do %>
        <!-- Primary Photo Background -->
        <div class="relative aspect-video lg:aspect-[21/9] bg-gray-900 rounded-lg overflow-hidden">
          <img
            id={"#{@id}-primary-image"}
            src={@primary_photo_url}
            alt={"Hero image of #{@title}#{if @address, do: " in #{@address}", else: ""}"}
            class="w-full h-full object-cover transition-opacity duration-300"
            loading="lazy"
            role="img"
            aria-describedby="venue-description"
            phx-hook="LazyImage"
            data-src={@primary_photo_url}
            data-loading="lazy"
            onload="this.style.opacity='1'"
            onerror="this.style.display='none'; this.parentElement.classList.add('bg-gray-800')"
          />
          <!-- Loading placeholder -->
          <div class="absolute inset-0 bg-gray-800 animate-pulse" id="hero-loading-placeholder"></div>
          <!-- Gradient overlay -->
          <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" aria-hidden="true" />

          <!-- Hero content overlay -->
          <div class="absolute inset-0 flex items-end">
            <div class="w-full p-6 lg:p-8">
              <div class="flex flex-col lg:flex-row gap-6">
                <%= if @has_secondary_photo do %>
                  <!-- Secondary photo as "poster" -->
                  <div class="flex-shrink-0">
                    <img
                      id={"#{@id}-secondary-image-overlay"}
                      src={@secondary_photo_url}
                      alt={"Additional image of #{@title}"}
                      class="w-32 lg:w-48 h-48 lg:h-64 rounded-lg shadow-2xl object-cover transition-opacity duration-300"
                      loading="lazy"
                      role="img"
                      phx-hook="LazyImage"
                      data-src={@secondary_photo_url}
                      onload="this.style.opacity='1'"
                      onerror="this.style.display='none'"
                    />
                  </div>
                <% end %>

                <!-- Title and details -->
                <div class="flex-1 text-white">
                  <.hero_title_section
                    title={@title}
                    address={@address}
                    rating={@rating}
                    user_ratings_total={@user_ratings_total}
                    price_level={@price_level}
                    business_status={@business_status}
                    types={@types}
                    compact={@compact}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <!-- No photo fallback -->
        <div class="bg-gradient-to-br from-blue-900 to-blue-800 text-white rounded-lg p-6 lg:p-8" aria-label="Venue information card">
          <div class="flex flex-col lg:flex-row gap-6">
            <%= if @has_secondary_photo do %>
              <div class="flex-shrink-0">
                <img
                  id={"#{@id}-secondary-image-fallback"}
                  src={@secondary_photo_url}
                  alt={"Image of #{@title}"}
                  class="w-32 lg:w-48 h-48 lg:h-64 rounded-lg shadow-lg object-cover transition-opacity duration-300"
                  loading="lazy"
                  role="img"
                  phx-hook="LazyImage"
                  data-src={@secondary_photo_url}
                  onload="this.style.opacity='1'"
                  onerror="this.style.display='none'"
                />
              </div>
            <% end %>

            <div class="flex-1">
              <.hero_title_section
                title={@title}
                address={@address}
                rating={@rating}
                user_ratings_total={@user_ratings_total}
                price_level={@price_level}
                business_status={@business_status}
                types={@types}
                compact={@compact}
              />
            </div>
          </div>
        </div>
      <% end %>
          </article>
    """
  end

  # Private function components

  defp hero_title_section(assigns) do
    ~H"""
    <header class="space-y-3">
      <!-- Title -->
      <h1 id="venue-title" class={[
        "font-bold tracking-tight",
        @compact && "text-2xl lg:text-3xl" || "text-3xl lg:text-5xl"
      ]}>
        <%= @title %>
      </h1>

      <!-- Address -->
      <%= if @address do %>
        <p id="venue-description" class={[
          "text-white/90",
          @compact && "text-sm" || "text-base"
        ]} aria-label={"Located at #{@address}"}>
          <span aria-hidden="true">📍</span>
          <span class="sr-only">Located at: </span>
          <%= @address %>
        </p>
      <% end %>

      <!-- Metadata row -->
      <div class="flex flex-wrap items-center gap-4 text-sm lg:text-base" role="list" aria-label="Venue details">
        <!-- Rating -->
        <%= if @rating && @rating > 0 do %>
          <div class="flex items-center gap-1" role="listitem" aria-label={get_rating_aria_label(@rating, @user_ratings_total)}>
            <.icon name="hero-star-solid" class="h-4 w-4 text-yellow-400" />
            <span class="font-medium" aria-label={"Rating: #{format_rating(@rating)} out of 5 stars"}>
              <%= format_rating(@rating) %>
            </span>
            <%= if @user_ratings_total && @user_ratings_total > 0 do %>
              <span class="text-white/70" aria-label={"Based on #{format_ratings_count(@user_ratings_total)}"}>
                (<%= format_ratings_count(@user_ratings_total) %>)
              </span>
            <% end %>
          </div>
        <% end %>

        <!-- Price Level -->
        <%= if @price_level do %>
          <span class="text-white/80" role="listitem" aria-label={get_price_aria_label(@price_level)}>
            <%= @price_level %>
          </span>
        <% end %>

        <!-- Business Status -->
        <%= if @business_status && @business_status != "OPERATIONAL" do %>
          <span class="text-red-300 font-medium" role="listitem" aria-label={"Status: #{format_business_status(@business_status)}"}>
            <%= format_business_status(@business_status) %>
          </span>
        <% end %>
      </div>

      <!-- Types/Categories -->
      <%= if @types && length(@types) > 0 do %>
        <div class="flex flex-wrap gap-2" role="list" aria-label="Venue categories">
          <%= for type <- Enum.take(@types, 4) do %>
            <span class="px-2 py-1 bg-white/20 rounded-full text-xs font-medium" role="listitem">
              <%= format_place_type(type) %>
            </span>
          <% end %>
        </div>
      <% end %>
    </header>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    # Support both old format (for backward compatibility) and new standardized format
    title =
      case rich_data do
        %{title: title} when is_binary(title) -> title
        %{"title" => title} when is_binary(title) -> title
        _ -> "Unknown Place"
      end

    # Extract address from standardized format or fallback to old format
    address =
      case rich_data do
        %{sections: %{hero: %{subtitle: subtitle}}} -> subtitle
        %{description: description} when is_binary(description) -> description
        %{"metadata" => %{"address" => address}} -> address
        _ -> nil
      end

    # Extract rating from standardized format or fallback to old format
    rating_value =
      case rich_data do
        %{rating: %{value: value}} -> value
        %{"metadata" => %{"rating" => rating}} -> rating
        _ -> nil
      end

    # Extract user ratings total from standardized format or fallback to old format
    user_ratings_total =
      case rich_data do
        %{rating: %{count: count}} -> count
        %{"metadata" => %{"user_ratings_total" => total}} -> total
        _ -> nil
      end

    # Extract price level from standardized format or fallback to old format
    price_level =
      case rich_data do
        %{sections: %{hero: %{price_level: price_level}}} -> price_level
        %{"metadata" => %{"price_level" => price_level}} -> price_level
        _ -> nil
      end

    # Extract business status from standardized format or fallback to old format
    business_status =
      case rich_data do
        %{status: status} when is_binary(status) ->
          case status do
            "open" -> "OPERATIONAL"
            "closed" -> "CLOSED_TEMPORARILY"
            _ -> status |> String.upcase()
          end

        %{sections: %{hero: %{status: status}}} ->
          status

        %{"metadata" => %{"business_status" => status}} ->
          status

        _ ->
          nil
      end

    # Extract categories/types from standardized format or fallback to old format
    types =
      case rich_data do
        %{categories: categories} when is_list(categories) -> categories
        %{sections: %{hero: %{categories: categories}}} when is_list(categories) -> categories
        %{"metadata" => %{"types" => types}} when is_list(types) -> types
        _ -> []
      end

    # Extract images from cached_images table (R2 storage)
    # Falls back to rich_data for legacy compatibility
    venue = Map.get(socket.assigns, :venue)

    {primary_image, secondary_image} =
      cond do
        # Primary: Get from cached_images table
        venue && is_map(venue) && Map.has_key?(venue, :id) ->
          extract_hero_images_from_cached_images(venue.id)

        # Standardized format fallback
        match?(%{primary_image: %{url: _}}, rich_data) ->
          primary = %{"url" => rich_data.primary_image.url}

          secondary =
            case rich_data do
              %{secondary_image: %{url: url}} -> %{"url" => url}
              _ -> nil
            end

          {primary, secondary}

        # No images
        true ->
          {nil, nil}
      end

    _images = [primary_image, secondary_image] |> Enum.filter(& &1)

    socket
    |> assign(:title, title)
    |> assign(:address, address)
    |> assign(:rating, rating_value)
    |> assign(:user_ratings_total, user_ratings_total)
    |> assign(:price_level, format_price_level(price_level))
    |> assign(:business_status, business_status)
    |> assign(:types, filter_relevant_types(types))
    |> assign(:has_primary_photo, primary_image != nil)
    |> assign(:primary_photo_url, if(primary_image, do: primary_image["url"], else: nil))
    |> assign(:has_secondary_photo, secondary_image != nil)
    |> assign(:secondary_photo_url, if(secondary_image, do: secondary_image["url"], else: nil))
  end

  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating, decimals: 1)
  end

  defp format_rating(_), do: "N/A"

  defp format_ratings_count(count) when is_integer(count) do
    formatted_count = format_number_with_commas(count)

    cond do
      count > 1 -> "#{formatted_count}+ reviews"
      count == 1 -> "1 review"
      true -> ""
    end
  end

  defp format_ratings_count(_), do: ""

  defp format_number_with_commas(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
  end

  defp format_price_level(nil), do: nil
  defp format_price_level(0), do: "💸 Free"
  defp format_price_level(1), do: "💰 Inexpensive"
  defp format_price_level(2), do: "💰💰 Moderate"
  defp format_price_level(3), do: "💰💰💰 Expensive"
  defp format_price_level(4), do: "💰💰💰💰 Very Expensive"
  defp format_price_level(_), do: nil

  defp format_business_status("CLOSED_TEMPORARILY"), do: "Temporarily Closed"
  defp format_business_status("CLOSED_PERMANENTLY"), do: "Permanently Closed"
  defp format_business_status(status), do: String.replace(status, "_", " ") |> String.capitalize()

  defp filter_relevant_types(types) when is_list(types) do
    types
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))
    |> Enum.take(4)
  end

  defp filter_relevant_types(_), do: []

  defp format_place_type(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_place_type(_), do: ""

  defp get_rating_aria_label(rating, user_ratings_total) do
    if user_ratings_total && user_ratings_total > 0 do
      "Rating: #{rating} out of 5 stars based on #{user_ratings_total} reviews"
    else
      "Rating: #{rating} out of 5 stars"
    end
  end

  defp get_price_aria_label(price_level) do
    case price_level do
      "💸 Free" -> "Price level: Free"
      "💰 Inexpensive" -> "Price level: Inexpensive"
      "💰💰 Moderate" -> "Price level: Moderate"
      "💰💰💰 Expensive" -> "Price level: Expensive"
      "💰💰💰💰 Very Expensive" -> "Price level: Very Expensive"
      _ when is_binary(price_level) -> "Price level: #{String.replace(price_level, ~r/💰|💸/, "")}"
      _ -> "Price level"
    end
  end

  # Extract primary and secondary images from cached_images table
  defp extract_hero_images_from_cached_images(venue_id) when is_integer(venue_id) do
    # Get first two cached images by position
    cached_images =
      ImageCacheService.get_entity_images("venue", venue_id)
      |> Enum.take(2)

    case cached_images do
      [primary, secondary | _] ->
        {normalize_cached_image_for_hero(primary), normalize_cached_image_for_hero(secondary)}

      [primary] ->
        {normalize_cached_image_for_hero(primary), nil}

      [] ->
        {nil, nil}
    end
  end

  defp extract_hero_images_from_cached_images(_), do: {nil, nil}

  # Convert CachedImage struct to the map format expected by the hero component
  defp normalize_cached_image_for_hero(%CachedImage{} = cached_image) do
    %{
      "url" => CachedImage.effective_url(cached_image),
      "provider" => cached_image.original_source,
      "attribution" => get_attribution(cached_image),
      "attribution_url" => nil
    }
  end

  # Extract attribution from metadata if available
  defp get_attribution(%CachedImage{metadata: metadata}) when is_map(metadata) do
    metadata["attribution"] || metadata[:attribution]
  end

  defp get_attribution(_), do: nil
end
