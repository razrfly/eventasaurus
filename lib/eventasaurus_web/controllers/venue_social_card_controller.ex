defmodule EventasaurusWeb.VenueSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for venue pages.

  This controller generates social cards with Wombie branding for venue pages,
  showing venue name, city, event count, and venue image.

  Route: GET /social-cards/venue/:city_slug/:venue_slug/:hash/*rest
  """
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.Venues
  alias EventasaurusDiscovery.Locations
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for a venue page with hash validation.
  Provides cache busting through hash-based URLs.

  Route: GET /social-cards/venue/:city_slug/:venue_slug/:hash/*rest
  """
  def generate_card(
        conn,
        %{
          "city_slug" => city_slug,
          "venue_slug" => venue_slug,
          "hash" => hash,
          "rest" => rest
        }
      ) do
    Logger.info("Venue social card requested for #{city_slug}/#{venue_slug}, hash: #{hash}")

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    # Look up city first
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        Logger.warning("City not found for slug: #{city_slug}")
        send_resp(conn, 404, "City not found")

      city ->
        # Look up venue by slug
        case Venues.get_venue_by_slug(venue_slug) do
          nil ->
            Logger.warning("Venue not found for slug: #{venue_slug}")
            send_resp(conn, 404, "Venue not found")

          venue ->
            # Fetch complete venue data with event count
            venue_data = fetch_venue_data(venue, city)

            # Validate that the hash matches current venue data
            if SocialCardHelpers.validate_hash(venue_data, final_hash, :venue) do
              Logger.info("Hash validated for venue #{city_slug}/#{venue_slug}")

              # Sanitize data before rendering
              sanitized_data = sanitize_venue(venue_data)

              # Render SVG template with sanitized data
              svg_content = render_venue_card_svg(sanitized_data)

              # Generate PNG and serve response
              slug = "#{city_slug}_#{venue_slug}"

              case SocialCardHelpers.generate_png(svg_content, slug, sanitized_data) do
                {:ok, png_data} ->
                  SocialCardHelpers.send_png_response(conn, png_data, final_hash)

                {:error, error} ->
                  SocialCardHelpers.send_error_response(conn, error)
              end
            else
              expected_hash = HashGenerator.generate_hash(venue_data, :venue)

              Logger.warning(
                "Hash mismatch for venue #{city_slug}/#{venue_slug}. Expected: #{expected_hash}, Got: #{final_hash}"
              )

              # Build redirect URL
              current_url = HashGenerator.generate_url_path(venue_data, :venue)

              conn
              |> put_resp_header("location", current_url)
              |> send_resp(301, "Social card URL has been updated")
            end
        end
    end
  end

  # Fetch complete venue data needed for the social card
  defp fetch_venue_data(venue, city) do
    # Get event count for this venue
    event_count = Venues.count_upcoming_events(venue.id)

    # Get cover image from venue_images if available
    cover_image = get_venue_cover_image(venue)

    %{
      name: venue.name,
      slug: venue.slug,
      city_ref: %{
        name: city.name,
        slug: city.slug
      },
      address: venue.address,
      event_count: event_count,
      cover_image_url: cover_image,
      updated_at: venue.updated_at
    }
  end

  # Get cover image from venue's venue_images array
  defp get_venue_cover_image(%{venue_images: images}) when is_list(images) and length(images) > 0 do
    # Find first image with a valid URL
    images
    |> Enum.find_value(fn image ->
      case image do
        %{"url" => url} when is_binary(url) and url != "" -> url
        %{url: url} when is_binary(url) and url != "" -> url
        _ -> nil
      end
    end)
  end

  defp get_venue_cover_image(_), do: nil
end
