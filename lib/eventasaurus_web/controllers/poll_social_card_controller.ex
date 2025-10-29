defmodule EventasaurusWeb.PollSocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.Events
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
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

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    with {:event, event} when not is_nil(event) <- {:event, Events.get_event_by_slug(slug)},
         {:number, {poll_number, ""}} <- {:number, Integer.parse(number)},
         {:poll, poll} when not is_nil(poll) <-
           {:poll, get_poll_with_options_by_number(poll_number, event.id)},
         {:poll_belongs_to_event, true} <- {:poll_belongs_to_event, poll.event_id == event.id} do
      # Validate that the hash matches current poll data
      if SocialCardHelpers.validate_hash(poll, final_hash, :poll) do
        Logger.info("Hash validated for poll ##{poll_number}: #{poll.title}")

        # Preload event association for theme
        poll_with_event = %{poll | event: event}

        # Render SVG template with poll data
        svg_content = render_poll_card_svg(poll_with_event)

        # Generate PNG and serve response
        case SocialCardHelpers.generate_png(svg_content, "poll_#{poll.id}", poll_with_event) do
          {:ok, png_data} ->
            SocialCardHelpers.send_png_response(conn, png_data, final_hash)

          {:error, error} ->
            SocialCardHelpers.send_error_response(conn, error)
        end
      else
        expected_hash = HashGenerator.generate_hash(poll, :poll)
        SocialCardHelpers.send_hash_mismatch_redirect(conn, poll, "poll_#{poll.id}", expected_hash, final_hash, :poll)
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

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    with {:event, event} when not is_nil(event) <- {:event, Events.get_event_by_slug(slug)},
         {:poll, poll} when not is_nil(poll) <- {:poll, Events.get_poll_with_options(poll_id)},
         {:poll_belongs_to_event, true} <- {:poll_belongs_to_event, poll.event_id == event.id} do
      # Validate that the hash matches current poll data
      if SocialCardHelpers.validate_hash(poll, final_hash, :poll) do
        Logger.info("Hash validated for poll #{poll_id}: #{poll.title}")

        # Preload event association for theme
        poll_with_event = %{poll | event: event}

        # Render SVG template with poll data
        svg_content = render_poll_card_svg(poll_with_event)

        # Generate PNG and serve response
        case SocialCardHelpers.generate_png(svg_content, "poll_#{poll.id}", poll_with_event) do
          {:ok, png_data} ->
            SocialCardHelpers.send_png_response(conn, png_data, final_hash)

          {:error, error} ->
            SocialCardHelpers.send_error_response(conn, error)
        end
      else
        expected_hash = HashGenerator.generate_hash(poll, :poll)
        SocialCardHelpers.send_hash_mismatch_redirect(conn, poll, "poll_#{poll.id}", expected_hash, final_hash, :poll)
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
