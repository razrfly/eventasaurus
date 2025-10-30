defmodule EventasaurusWeb.CitySocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  import Ecto.Query, only: [from: 2]

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Categories
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for a city by slug with hash validation.
  Provides cache busting through hash-based URLs.
  """
  def generate_card_by_slug(conn, %{"slug" => slug, "hash" => hash, "rest" => rest}) do
    Logger.info(
      "City social card requested for slug: #{slug}, hash: #{hash}, rest: #{inspect(rest)}"
    )

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    case Locations.get_city_by_slug(slug) do
      nil ->
        Logger.warning("City not found for slug: #{slug}")
        send_resp(conn, 404, "City not found")

      city ->
        # Fetch city stats for the card
        stats = fetch_city_stats(city)
        city_with_stats = Map.put(city, :stats, stats)

        # Validate that the hash matches current city data
        if SocialCardHelpers.validate_hash(city_with_stats, final_hash, :city) do
          Logger.info("Hash validated for city #{slug}: #{city.name}")

          # Sanitize city data before rendering
          sanitized_city = sanitize_city(city)

          # Render SVG template with sanitized city data
          svg_content = render_city_card_svg(sanitized_city, stats)

          # Generate PNG and serve response
          case SocialCardHelpers.generate_png(svg_content, city.slug, sanitized_city) do
            {:ok, png_data} ->
              SocialCardHelpers.send_png_response(conn, png_data, final_hash)

            {:error, error} ->
              SocialCardHelpers.send_error_response(conn, error)
          end
        else
          expected_hash = HashGenerator.generate_hash(city_with_stats, :city)

          SocialCardHelpers.send_hash_mismatch_redirect(
            conn,
            city_with_stats,
            slug,
            expected_hash,
            final_hash,
            :city
          )
        end
    end
  end

  # Fetch city stats for the card
  defp fetch_city_stats(city) do
    # Use similar logic to CityLive.Index
    lat = city.latitude && Decimal.to_float(city.latitude)
    lng = city.longitude && Decimal.to_float(city.longitude)

    default_radius_km = 50

    events_count =
      if lat && lng do
        PublicEventsEnhanced.count_events(%{
          center_lat: lat,
          center_lng: lng,
          radius_km: default_radius_km,
          show_past: false
        })
      else
        0
      end

    venues_count =
      EventasaurusApp.Repo.aggregate(
        from(v in EventasaurusApp.Venues.Venue, where: v.city_id == ^city.id),
        :count
      )

    categories_count = length(Categories.list_categories())

    %{
      events_count: events_count,
      venues_count: venues_count,
      categories_count: categories_count
    }
  end
end
