defmodule EventasaurusWeb.EventSocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.Events
  alias Eventasaurus.Services.SvgConverter
  alias Eventasaurus.SocialCards.HashGenerator
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for an event by slug with hash validation.
  Provides cache busting through hash-based URLs.
  """
  def generate_card_by_slug(conn, %{"slug" => slug, "hash" => hash, "rest" => rest}) do
    Logger.info(
      "Social card requested for event slug: #{slug}, hash: #{hash}, rest: #{inspect(rest)}"
    )

    # The hash should be clean now, but check if rest contains .png
    final_hash =
      if rest == ["png"] do
        # Hash is clean, rest contains the extension
        hash
      else
        # Fallback: extract hash from combined parameter
        combined =
          if is_list(rest) and length(rest) > 0 do
            "#{hash}.#{Enum.join(rest, ".")}"
          else
            hash
          end

        String.replace_suffix(combined, ".png", "")
      end

    case Events.get_event_by_slug(slug) do
      nil ->
        Logger.warning("Event not found for slug: #{slug}")
        send_resp(conn, 404, "Event not found")

      event ->
        # Validate that the hash matches current event data
        case HashGenerator.validate_hash(event, final_hash) do
          true ->
            Logger.info("Hash validated for event #{slug}: #{event.title}")

            # Check for system dependencies first
            case SvgConverter.verify_rsvg_available() do
              :ok ->
                # Sanitize event data before rendering
                sanitized_event = sanitize_event(event)

                # Render SVG template with sanitized event data
                svg_content = render_svg_template(sanitized_event)

                # Convert SVG to PNG
                case SvgConverter.svg_to_png(svg_content, event.slug, sanitized_event) do
                  {:ok, png_path} ->
                    # Read the PNG file and serve it
                    case File.read(png_path) do
                      {:ok, png_data} ->
                        Logger.info(
                          "Successfully generated social card PNG for slug #{slug} (#{byte_size(png_data)} bytes)"
                        )

                        # Clean up the temporary file
                        SvgConverter.cleanup_temp_file(png_path)

                        conn
                        |> put_resp_content_type("image/png")
                        # Cache for 1 year since hash ensures freshness
                        |> put_resp_header("cache-control", "public, max-age=31536000")
                        |> put_resp_header("etag", "\"#{final_hash}\"")
                        |> send_resp(200, png_data)

                      {:error, reason} ->
                        Logger.error(
                          "Failed to read PNG file for slug #{slug}: #{inspect(reason)}"
                        )

                        SvgConverter.cleanup_temp_file(png_path)
                        send_resp(conn, 500, "Failed to generate social card")
                    end

                  {:error, reason} ->
                    Logger.error(
                      "Failed to convert SVG to PNG for slug #{slug}: #{inspect(reason)}"
                    )

                    send_resp(conn, 500, "Failed to generate social card")
                end

              {:error, :command_not_found} ->
                Logger.error(
                  "rsvg-convert command not found - social card generation unavailable. Install librsvg2-bin package."
                )

                conn
                |> put_resp_content_type("text/plain")
                |> send_resp(
                  503,
                  "Social card generation temporarily unavailable - missing system dependency"
                )
            end

          false ->
            Logger.warning(
              "Hash mismatch for event #{slug}. Expected: #{HashGenerator.generate_hash(event)}, Got: #{final_hash}"
            )

            # Redirect to current URL with correct hash
            current_url = HashGenerator.generate_url_path(event)

            conn
            |> put_resp_header("location", current_url)
            |> send_resp(301, "Social card URL has been updated")
        end
    end
  end

  # Private helper to render SVG template with proper context
  defp render_svg_template(event) do
    # Use the public function from SocialCardView
    EventasaurusWeb.SocialCardView.render_social_card_svg(event)
  end
end
