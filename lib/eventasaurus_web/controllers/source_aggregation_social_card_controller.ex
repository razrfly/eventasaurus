defmodule EventasaurusWeb.SourceAggregationSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for source aggregation pages.

  This controller generates social cards with Wombie branding for source aggregation pages,
  which show events from a specific source (e.g., PubQuiz Poland, Restaurant Week) in a city.

  Route: GET /social-cards/source/:city_slug/:content_type/:identifier/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :source_aggregation

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Sources.SourceStore
  alias EventasaurusDiscovery.AggregationTypeSlug

  import EventasaurusWeb.SocialCardView,
    only: [sanitize_source_aggregation: 1, render_source_aggregation_card_svg: 1]

  @impl true
  def lookup_entity(%{"city_slug" => city_slug} = params) do
    case Locations.get_city_by_slug(city_slug) do
      nil -> {:error, :not_found, "City not found for slug: #{city_slug}"}
      city -> {:ok, {city, params}}
    end
  end

  @impl true
  def build_card_data({city, %{"content_type" => content_type_slug, "identifier" => identifier}}) do
    content_type = AggregationTypeSlug.from_slug(content_type_slug)
    fetch_aggregation_data(city, content_type, identifier)
  end

  @impl true
  def build_slug(
        %{
          "city_slug" => city_slug,
          "content_type" => content_type_slug,
          "identifier" => identifier
        },
        _data
      ) do
    "#{city_slug}_#{content_type_slug}_#{identifier}"
  end

  @impl true
  def sanitize(data), do: sanitize_source_aggregation(data)

  @impl true
  def render_svg(data), do: render_source_aggregation_card_svg(data)

  # Fetch aggregation data needed for the social card
  defp fetch_aggregation_data(city, content_type, identifier) do
    center_lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    center_lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Get aggregation stats using database-level COUNT/GROUP BY
    stats =
      PublicEventsEnhanced.get_source_aggregation_stats(%{
        source_slug: identifier,
        center_lat: center_lat,
        center_lng: center_lng,
        radius_km: 50
      })

    total_event_count = stats.total_count

    # Get one event per venue within radius (for location count and hero image)
    events =
      PublicEventsEnhanced.list_events_grouped_by_venue(%{
        source_slug: identifier,
        center_lat: center_lat,
        center_lng: center_lng,
        radius_km: 50,
        browsing_city_id: city.id
      })

    location_count = length(events)

    # Extract hero image from first event with an image
    hero_image =
      events
      |> Enum.find_value(fn event ->
        Map.get(event, :cover_image_url)
      end)

    # Get source name from SourceStore
    source_name = get_source_name(identifier)

    %{
      city: city,
      content_type: content_type,
      identifier: identifier,
      source_name: source_name,
      total_event_count: total_event_count,
      location_count: location_count,
      hero_image: hero_image
    }
  end

  # Get display name for a source
  defp get_source_name(identifier) do
    case SourceStore.get_source_by_slug(identifier) do
      %{name: name} when is_binary(name) and name != "" ->
        name

      _ ->
        # Fallback: convert identifier to title case
        identifier
        |> String.replace(["-", "_"], " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end
end
