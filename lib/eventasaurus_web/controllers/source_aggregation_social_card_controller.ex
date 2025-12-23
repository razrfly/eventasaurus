defmodule EventasaurusWeb.SourceAggregationSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for source aggregation pages.

  This controller generates social cards with Wombie branding for source aggregation pages,
  which show events from a specific source (e.g., PubQuiz Poland, Restaurant Week) in a city.

  Route: GET /social-cards/source/:city_slug/:content_type/:identifier/:hash/*rest
  """
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Sources.SourceStore
  alias EventasaurusDiscovery.AggregationTypeSlug
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for a source aggregation page with hash validation.
  Provides cache busting through hash-based URLs.

  Route: GET /social-cards/source/:city_slug/:content_type/:identifier/:hash/*rest
  """
  def generate_card(
        conn,
        %{
          "city_slug" => city_slug,
          "content_type" => content_type_slug,
          "identifier" => identifier,
          "hash" => hash,
          "rest" => rest
        }
      ) do
    Logger.info(
      "Source aggregation social card requested for #{city_slug}/#{content_type_slug}/#{identifier}, hash: #{hash}"
    )

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    # Look up city
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        Logger.warning("City not found for slug: #{city_slug}")
        send_resp(conn, 404, "City not found")

      city ->
        # Convert URL slug to schema.org type
        content_type = AggregationTypeSlug.from_slug(content_type_slug)

        # Fetch aggregation data
        aggregation_data = fetch_aggregation_data(city, content_type, identifier)

        # Validate that the hash matches current aggregation data
        if SocialCardHelpers.validate_hash(aggregation_data, final_hash, :source_aggregation) do
          Logger.info(
            "Hash validated for source aggregation #{city_slug}/#{content_type_slug}/#{identifier}"
          )

          # Sanitize data before rendering
          sanitized_data = sanitize_source_aggregation(aggregation_data)

          # Render SVG template with sanitized data
          svg_content = render_source_aggregation_card_svg(sanitized_data)

          # Generate PNG and serve response
          slug = "#{city_slug}_#{content_type_slug}_#{identifier}"

          case SocialCardHelpers.generate_png(svg_content, slug, sanitized_data) do
            {:ok, png_data} ->
              SocialCardHelpers.send_png_response(conn, png_data, final_hash)

            {:error, error} ->
              SocialCardHelpers.send_error_response(conn, error)
          end
        else
          expected_hash = HashGenerator.generate_hash(aggregation_data, :source_aggregation)

          Logger.warning(
            "Hash mismatch for source aggregation #{city_slug}/#{content_type_slug}/#{identifier}. Expected: #{expected_hash}, Got: #{final_hash}"
          )

          # Build redirect URL
          current_url =
            HashGenerator.generate_url_path(aggregation_data, :source_aggregation)

          conn
          |> put_resp_header("location", current_url)
          |> send_resp(301, "Social card URL has been updated")
        end
    end
  end

  # Fetch aggregation data needed for the social card
  defp fetch_aggregation_data(city, content_type, identifier) do
    # Get city coordinates for radius filtering
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
