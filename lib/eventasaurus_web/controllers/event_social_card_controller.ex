defmodule EventasaurusWeb.EventSocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.Events
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for an event by slug with hash validation.
  Provides cache busting through hash-based URLs.
  """
  def generate_card_by_slug(conn, %{"slug" => slug, "hash" => hash, "rest" => rest}) do
    Logger.info(
      "Social card requested for event slug: #{slug}, hash: #{hash}, rest: #{inspect(rest)}"
    )

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    case Events.get_event_by_slug(slug) do
      nil ->
        Logger.warning("Event not found for slug: #{slug}")
        send_resp(conn, 404, "Event not found")

      event ->
        # Validate that the hash matches current event data
        if SocialCardHelpers.validate_hash(event, final_hash, :event) do
          Logger.info("Hash validated for event #{slug}: #{event.title}")

          # Sanitize event data before rendering
          sanitized_event = sanitize_event(event)

          # Render SVG template with sanitized event data
          svg_content = render_svg_template(sanitized_event)

          # Generate PNG and serve response
          case SocialCardHelpers.generate_png(svg_content, slug, sanitized_event) do
            {:ok, png_data} ->
              SocialCardHelpers.send_png_response(conn, png_data, final_hash)

            {:error, error} ->
              SocialCardHelpers.send_error_response(conn, error)
          end
        else
          expected_hash = HashGenerator.generate_hash(event)
          SocialCardHelpers.send_hash_mismatch_redirect(conn, event, slug, expected_hash, final_hash, :event)
        end
    end
  end

  # Private helper to render SVG template with proper context
  defp render_svg_template(event) do
    # Use the public function from SocialCardView
    EventasaurusWeb.SocialCardView.render_social_card_svg(event)
  end
end
