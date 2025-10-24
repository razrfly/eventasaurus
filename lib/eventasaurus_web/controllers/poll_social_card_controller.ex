defmodule EventasaurusWeb.PollSocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.Events
  alias Eventasaurus.Services.SvgConverter
  alias Eventasaurus.SocialCards.PollHashGenerator
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for a poll by event slug and poll number with hash validation.
  Provides cache busting through hash-based URLs.
  """
  def generate_card_by_number(conn, %{
        "slug" => slug,
        "number" => number,
        "hash" => hash,
        "rest" => rest
      }) do
    Logger.info(
      "Poll social card requested for event slug: #{slug}, poll_number: #{number}, hash: #{hash}, rest: #{inspect(rest)}"
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

    with {:event, event} when not is_nil(event) <- {:event, Events.get_event_by_slug(slug)},
         {:number, {poll_number, ""}} <- {:number, Integer.parse(number)},
         {:poll, poll} when not is_nil(poll) <-
           {:poll, get_poll_with_options_by_number(poll_number, event.id)},
         {:poll_belongs_to_event, true} <- {:poll_belongs_to_event, poll.event_id == event.id} do
      # Validate that the hash matches current poll data
      case PollHashGenerator.validate_hash(poll, final_hash) do
        true ->
          Logger.info("Hash validated for poll ##{poll_number}: #{poll.title}")

          # Check for system dependencies first
          case SvgConverter.verify_rsvg_available() do
            :ok ->
              # Preload event association for theme
              poll_with_event = %{poll | event: event}

              # Render SVG template with poll data
              svg_content = render_poll_card_svg(poll_with_event)

              # Convert SVG to PNG
              case SvgConverter.svg_to_png(svg_content, "poll_#{poll.id}", poll_with_event) do
                {:ok, png_path} ->
                  # Read the PNG file and serve it
                  case File.read(png_path) do
                    {:ok, png_data} ->
                      Logger.info(
                        "Successfully generated poll social card PNG for poll ##{poll_number} (#{byte_size(png_data)} bytes)"
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
                        "Failed to read PNG file for poll ##{poll_number}: #{inspect(reason)}"
                      )

                      SvgConverter.cleanup_temp_file(png_path)
                      send_resp(conn, 500, "Failed to generate social card")
                  end

                {:error, reason} ->
                  Logger.error(
                    "Failed to convert SVG to PNG for poll ##{poll_number}: #{inspect(reason)}"
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
            "Hash mismatch for poll ##{poll_number}. Expected: #{PollHashGenerator.generate_hash(poll)}, Got: #{final_hash}"
          )

          # Redirect to current URL with correct hash
          current_url = PollHashGenerator.generate_url_path(poll, event)

          conn
          |> put_resp_header("location", current_url)
          |> send_resp(301, "Social card URL has been updated")
      end
    else
      {:event, nil} ->
        Logger.warning("Event not found for slug: #{slug}")
        send_resp(conn, 404, "Event not found")

      {:number, _} ->
        Logger.warning("Invalid poll number: #{number}")
        send_resp(conn, 404, "Invalid poll number")

      {:poll, nil} ->
        Logger.warning("Poll not found for poll_number: #{number}")
        send_resp(conn, 404, "Poll not found")

      {:poll_belongs_to_event, false} ->
        Logger.warning("Poll ##{number} does not belong to event #{slug}")
        send_resp(conn, 404, "Poll not found for this event")
    end
  end

  # Helper function to get poll with options by number
  # Delegates to Events context for social card optimized poll fetching
  defp get_poll_with_options_by_number(number, event_id) do
    Events.get_poll_with_options_by_number(number, event_id)
  end

  @doc """
  Generates a social card PNG for a poll by event slug and poll ID with hash validation.
  DEPRECATED: Use generate_card_by_number/2 instead. This is kept for backwards compatibility.
  """
  def generate_card_by_id(conn, %{
        "slug" => slug,
        "poll_id" => poll_id,
        "hash" => hash,
        "rest" => rest
      }) do
    Logger.info(
      "Poll social card requested for event slug: #{slug}, poll_id: #{poll_id}, hash: #{hash}, rest: #{inspect(rest)}"
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

    with {:event, event} when not is_nil(event) <- {:event, Events.get_event_by_slug(slug)},
         {:poll, poll} when not is_nil(poll) <- {:poll, Events.get_poll_with_options(poll_id)},
         {:poll_belongs_to_event, true} <- {:poll_belongs_to_event, poll.event_id == event.id} do
      # Validate that the hash matches current poll data
      case PollHashGenerator.validate_hash(poll, final_hash) do
        true ->
          Logger.info("Hash validated for poll #{poll_id}: #{poll.title}")

          # Check for system dependencies first
          case SvgConverter.verify_rsvg_available() do
            :ok ->
              # Preload event association for theme
              poll_with_event = %{poll | event: event}

              # Render SVG template with poll data
              svg_content = render_poll_card_svg(poll_with_event)

              # Convert SVG to PNG
              case SvgConverter.svg_to_png(svg_content, "poll_#{poll.id}", poll_with_event) do
                {:ok, png_path} ->
                  # Read the PNG file and serve it
                  case File.read(png_path) do
                    {:ok, png_data} ->
                      Logger.info(
                        "Successfully generated poll social card PNG for poll #{poll_id} (#{byte_size(png_data)} bytes)"
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
                        "Failed to read PNG file for poll #{poll_id}: #{inspect(reason)}"
                      )

                      SvgConverter.cleanup_temp_file(png_path)
                      send_resp(conn, 500, "Failed to generate social card")
                  end

                {:error, reason} ->
                  Logger.error(
                    "Failed to convert SVG to PNG for poll #{poll_id}: #{inspect(reason)}"
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
            "Hash mismatch for poll #{poll_id}. Expected: #{PollHashGenerator.generate_hash(poll)}, Got: #{final_hash}"
          )

          # Redirect to current URL with correct hash
          current_url = PollHashGenerator.generate_url_path(poll, event)

          conn
          |> put_resp_header("location", current_url)
          |> send_resp(301, "Social card URL has been updated")
      end
    else
      {:event, nil} ->
        Logger.warning("Event not found for slug: #{slug}")
        send_resp(conn, 404, "Event not found")

      {:poll, nil} ->
        Logger.warning("Poll not found for poll_id: #{poll_id}")
        send_resp(conn, 404, "Poll not found")

      {:poll_belongs_to_event, false} ->
        Logger.warning("Poll #{poll_id} does not belong to event #{slug}")
        send_resp(conn, 404, "Poll not found for this event")
    end
  end
end
