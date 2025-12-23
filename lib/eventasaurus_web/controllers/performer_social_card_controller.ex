defmodule EventasaurusWeb.PerformerSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for performer pages.

  This controller generates social cards with Wombie branding for performer pages,
  showing performer name, event count, and performer image.

  Route: GET /social-cards/performer/:slug/:hash/*rest
  """
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusDiscovery.Performers.PerformerStore
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for a performer page with hash validation.
  Provides cache busting through hash-based URLs.

  Route: GET /social-cards/performer/:slug/:hash/*rest
  """
  def generate_card(
        conn,
        %{
          "slug" => slug,
          "hash" => hash,
          "rest" => rest
        }
      ) do
    Logger.info("Performer social card requested for #{slug}, hash: #{hash}")

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    # Look up performer by slug
    case PerformerStore.get_performer_by_slug(slug, preload_events: true) do
      nil ->
        Logger.warning("Performer not found for slug: #{slug}")
        send_resp(conn, 404, "Performer not found")

      performer ->
        # Fetch complete performer data with event count
        performer_data = fetch_performer_data(performer)

        # Validate that the hash matches current performer data
        if SocialCardHelpers.validate_hash(performer_data, final_hash, :performer) do
          Logger.info("Hash validated for performer #{slug}")

          # Sanitize data before rendering
          sanitized_data = sanitize_performer(performer_data)

          # Render SVG template with sanitized data
          svg_content = render_performer_card_svg(sanitized_data)

          # Generate PNG and serve response
          case SocialCardHelpers.generate_png(svg_content, slug, sanitized_data) do
            {:ok, png_data} ->
              SocialCardHelpers.send_png_response(conn, png_data, final_hash)

            {:error, error} ->
              SocialCardHelpers.send_error_response(conn, error)
          end
        else
          expected_hash = HashGenerator.generate_hash(performer_data, :performer)

          Logger.warning(
            "Hash mismatch for performer #{slug}. Expected: #{expected_hash}, Got: #{final_hash}"
          )

          # Build redirect URL
          current_url = HashGenerator.generate_url_path(performer_data, :performer)

          conn
          |> put_resp_header("location", current_url)
          |> send_resp(301, "Social card URL has been updated")
        end
    end
  end

  # Fetch complete performer data needed for the social card
  defp fetch_performer_data(performer) do
    # Count upcoming events for this performer
    event_count = count_upcoming_events(performer)

    %{
      name: performer.name,
      slug: performer.slug,
      event_count: event_count,
      image_url: performer.image_url,
      updated_at: performer.updated_at
    }
  end

  # Count upcoming events for a performer
  defp count_upcoming_events(performer) do
    today = Date.utc_today()

    performer.public_events
    |> Enum.count(fn event ->
      event.dates != nil and
        Enum.any?(event.dates, fn date ->
          Date.compare(date, today) != :lt
        end)
    end)
  end
end
