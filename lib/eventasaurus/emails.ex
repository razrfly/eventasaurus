defmodule Eventasaurus.Emails do
  @moduledoc """
  Email templates for guest invitations using Swoosh.
  """

  import Swoosh.Email
  require Logger

  @from_email {"Wombie", "invitations@wombie.com"}

  # HTML escaping helper to prevent XSS attacks
  defp html_escape(nil), do: ""

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp html_escape(text), do: html_escape(to_string(text))

  # Email validation helper to prevent injection attacks
  defp valid_email?(email) when is_binary(email) do
    email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  end

  defp valid_email?(_), do: false

  @doc """
  Creates a guest invitation email using Swoosh.Email.

  ## Parameters
  - `to_email`: Recipient email address
  - `guest_name`: Name of the guest being invited
  - `event`: Event struct containing event details
  - `invitation_message`: Custom invitation message from the organizer
  - `organizer`: Organizer user struct

  ## Returns
  - `Swoosh.Email` struct ready to be sent
  """
  def guest_invitation_email(to_email, guest_name, event, invitation_message, organizer) do
    # Validate email format
    unless valid_email?(to_email) do
      raise ArgumentError, "Invalid email address: #{to_email}"
    end

    subject = "You're invited to #{event.title}"

    new()
    |> from(@from_email)
    |> to({guest_name, to_email})
    |> subject(subject)
    |> html_body(build_html_content(guest_name, event, invitation_message, organizer))
    |> text_body(build_text_content(guest_name, event, invitation_message, organizer))
    |> reply_to(organizer.email)
  end

  @doc """
  Sends a guest invitation email via the configured mailer.

  ## Parameters
  - `to_email`: Recipient email address
  - `guest_name`: Name of the guest being invited
  - `event`: Event struct containing event details
  - `invitation_message`: Custom invitation message from the organizer
  - `organizer`: Organizer user struct

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  def send_guest_invitation(to_email, guest_name, event, invitation_message, organizer) do
    try do
      email = guest_invitation_email(to_email, guest_name, event, invitation_message, organizer)

      case Eventasaurus.Mailer.deliver(email) do
        {:ok, response} ->
          Logger.info("Guest invitation email sent successfully to #{to_email}")
          {:ok, response}

        {:error, reason} ->
          Logger.error("Failed to send guest invitation email to #{to_email}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error creating guest invitation email: #{inspect(error)}")
        {:error, error}
    end
  end

  # Private helper functions for email content

  defp build_html_content(guest_name, event, invitation_message, organizer) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{html_escape(event.title)} - Invitation</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 600px;
                margin: 0 auto;
                padding: 20px;
                background-color: #f5f5f5;
            }
            .email-container {
                background: white;
                border-radius: 12px;
                box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
                overflow: hidden;
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 40px 30px;
                text-align: center;
            }
            .header h1 {
                margin: 0 0 10px 0;
                font-size: 28px;
                font-weight: 600;
            }
            .header p {
                margin: 0;
                font-size: 16px;
                opacity: 0.9;
            }
            .content {
                padding: 40px 30px;
            }
            .content p {
                margin: 16px 0;
                font-size: 16px;
            }
            .personal-message {
                background: #f8f9fa;
                border-left: 4px solid #667eea;
                padding: 20px;
                margin: 25px 0;
                border-radius: 6px;
                font-style: italic;
                color: #555;
            }
            .event-details {
                background: #f8f9fa;
                padding: 30px;
                border-radius: 12px;
                margin: 30px 0;
                border: 1px solid #e9ecef;
            }
            .event-image {
                width: 100%;
                max-width: 600px;
                height: auto;
                border-radius: 8px;
                margin-bottom: 20px;
                display: block;
            }
            .event-details h2 {
                margin: 0 0 20px 0;
                color: #333;
                font-size: 24px;
            }
            .event-details p {
                margin: 12px 0;
                color: #666;
            }
            .event-details strong {
                color: #333;
            }
            .cta-button {
                display: inline-block;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 16px 32px;
                text-decoration: none;
                border-radius: 8px;
                font-weight: 600;
                font-size: 16px;
                margin: 30px 0;
                transition: transform 0.2s;
            }
            .cta-button:hover {
                transform: translateY(-2px);
            }
            .footer {
                text-align: center;
                color: #666;
                font-size: 14px;
                margin-top: 40px;
                padding: 20px;
                border-top: 1px solid #e9ecef;
            }
            .footer a {
                color: #667eea;
                text-decoration: none;
            }
            @media (max-width: 600px) {
                .header, .content {
                    padding: 20px;
                }
                .event-details {
                    padding: 20px;
                }
            }
        </style>
    </head>
    <body>
        <div class="email-container">
            <div class="header">
                <img src="https://wombie.com/images/logos/general-white.png" alt="Wombie - Event Planning Made Easy" style="width: 184px; height: auto; margin: 0 auto 20px auto; display: block;" />
                <h1>You're Invited!</h1>
                <p>#{html_escape(get_organizer_name(organizer))} has invited you to an event</p>
            </div>

            <div class="content">
                <p>Hi #{html_escape(guest_name || "there")},</p>

                #{render_personal_message(invitation_message)}

                <p>You've been invited to join:</p>

                <div class="event-details">
                    #{render_event_image(event)}
                    <h2>#{html_escape(event.title)}</h2>
                    #{render_event_description(event)}

                    <p><strong>📅 Date:</strong> #{format_event_date(event)}</p>

                    #{render_event_location(event)}

                    #{render_event_price(event)}
                </div>

                <p style="text-align: center;">
                    <a href="#{build_event_url(event)}" class="cta-button">
                        View Event & RSVP
                    </a>
                </p>

                #{render_poll_section(event)}

                <p>We're excited to have you join us!</p>

                <p>Best regards,<br>
                #{html_escape(get_organizer_name(organizer))}<br>
                <strong>The Wombie Team</strong></p>
            </div>

            <div class="footer">
                <p>This invitation was sent via <a href="https://wombie.com">Wombie</a></p>
                <p>Can't attend? Just ignore this email.</p>
                <div style="margin-top: 20px;">
                    <a href="https://cirqus.co" target="_blank" rel="noopener noreferrer">
                        <img src="https://wombie.com/images/logos/cirqus-tent.png" alt="A Cirqus Production" style="width: 48px; height: auto; display: block; margin: 0 auto;" />
                    </a>
                </div>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp build_text_content(guest_name, event, invitation_message, organizer) do
    """
    🎉 You're Invited to #{event.title}!

    Hi #{guest_name || "there"},

    #{get_organizer_name(organizer)} has invited you to an event.

    #{render_personal_message_text(invitation_message)}

    EVENT DETAILS:
    #{event.title}
    #{render_event_description_text(event)}
    📅 Date: #{format_event_date(event)}
    #{render_event_location_text(event)}
    #{render_event_price_text(event)}

    View the event and RSVP here: #{build_event_url(event)}
    #{render_poll_section_text(event)}
    We're excited to have you join us!

    Best regards,
    #{get_organizer_name(organizer)}
    The Wombie Team

    ---
    This invitation was sent via Wombie (https://wombie.com)
    Can't attend? Just ignore this email.
    """
  end

  # Helper functions for content rendering

  defp get_organizer_name(organizer) do
    organizer.name || organizer.username || "Event Organizer"
  end

  # Poll-related helper functions

  # Get the first active poll for an event (phase = voting).
  # Returns nil if no active polls exist.
  defp get_active_poll(event) do
    case event.polls do
      %Ecto.Association.NotLoaded{} ->
        # Polls not preloaded, query them
        alias EventasaurusApp.Events.Poll
        alias EventasaurusApp.Repo
        require Ecto.Query

        event_id = event.id

        Poll
        |> Ecto.Query.where([p], p.event_id == ^event_id)
        |> Ecto.Query.where([p], p.phase in ^["voting_with_suggestions", "voting_only"])
        |> Ecto.Query.order_by([p], asc: p.order_index, asc: p.id)
        |> Ecto.Query.limit(1)
        |> Ecto.Query.preload([:poll_options])
        |> Repo.one()

      polls when is_list(polls) ->
        # Polls already preloaded, filter in memory
        polls
        |> Enum.filter(fn poll ->
          poll.phase in ["voting_with_suggestions", "voting_only"]
        end)
        |> Enum.sort_by(fn poll -> {poll.order_index || 0, poll.id} end)
        |> List.first()

      _ ->
        nil
    end
  end

  # Format poll options for display in email (limit to 3).
  # Returns HTML list of options with "and X more" if applicable.
  defp format_poll_options_html(poll, limit \\ 3) do
    options =
      case poll.poll_options do
        %Ecto.Association.NotLoaded{} ->
          []

        options when is_list(options) ->
          options
          |> Enum.filter(fn opt -> opt.status == "active" end)
          |> Enum.sort_by(fn opt -> {opt.order_index || 0, opt.id} end)

        _ ->
          []
      end

    total_count = length(options)

    if total_count == 0 do
      ""
    else
      displayed_options = Enum.take(options, limit)

      options_html =
        displayed_options
        |> Enum.map(fn opt ->
          "<li style=\"margin: 8px 0; color: #555;\">#{html_escape(opt.title)}</li>"
        end)
        |> Enum.join("\n")

      more_html =
        if total_count > limit do
          remaining = total_count - limit

          "<li style=\"margin: 8px 0; color: #888; font-style: italic;\">...and #{remaining} more option#{if remaining == 1, do: "", else: "s"}</li>"
        else
          ""
        end

      "<ul style=\"list-style: none; padding: 0; margin: 12px 0;\">\n#{options_html}\n#{more_html}</ul>"
    end
  end

  # Format poll options for plain text email (limit to 3).
  defp format_poll_options_text(poll, limit \\ 3) do
    options =
      case poll.poll_options do
        %Ecto.Association.NotLoaded{} ->
          []

        options when is_list(options) ->
          options
          |> Enum.filter(fn opt -> opt.status == "active" end)
          |> Enum.sort_by(fn opt -> {opt.order_index || 0, opt.id} end)

        _ ->
          []
      end

    total_count = length(options)

    if total_count == 0 do
      ""
    else
      displayed_options = Enum.take(options, limit)

      options_text =
        displayed_options
        |> Enum.map(fn opt -> "  • #{opt.title}" end)
        |> Enum.join("\n")

      more_text =
        if total_count > limit do
          remaining = total_count - limit
          "\n  ...and #{remaining} more option#{if remaining == 1, do: "", else: "s"}"
        else
          ""
        end

      "#{options_text}#{more_text}"
    end
  end

  # Render poll preview section for HTML email.
  # Returns empty string if no active polls.
  defp render_poll_section(event) do
    case get_active_poll(event) do
      nil ->
        ""

      poll ->
        alias EventasaurusApp.Events.Poll
        poll_type_display = Poll.poll_type_display(poll.poll_type)

        """
        <div style="background: #f8f9fa; padding: 25px; border-radius: 12px; margin: 25px 0; border-left: 4px solid #667eea;">
            <h3 style="margin: 0 0 15px 0; color: #333; font-size: 20px;">📊 #{html_escape(poll.title)}</h3>
            #{render_poll_description(poll)}
            <p style="margin: 12px 0 8px 0; font-weight: 600; color: #555;">Current Options:</p>
            #{format_poll_options_html(poll)}
            <p style="margin: 16px 0 0 0; color: #666; font-size: 14px;">
                <strong>Poll Type:</strong> #{html_escape(poll_type_display)} &nbsp;•&nbsp;
                <strong>Your voice matters!</strong> Vote when you RSVP.
            </p>
        </div>
        """
    end
  end

  # Render poll preview section for plain text email.
  # Returns empty string if no active polls.
  defp render_poll_section_text(event) do
    case get_active_poll(event) do
      nil ->
        ""

      poll ->
        alias EventasaurusApp.Events.Poll
        poll_type_display = Poll.poll_type_display(poll.poll_type)
        description = render_poll_description_text(poll)

        """

        📊 #{poll.title}
        #{description}
        Current Options:
        #{format_poll_options_text(poll)}

        Poll Type: #{poll_type_display} • Your voice matters! Vote when you RSVP.

        """
    end
  end

  defp render_poll_description(poll) do
    if poll.description && poll.description != "" do
      "<p style=\"margin: 8px 0; color: #666;\">#{html_escape(poll.description)}</p>"
    else
      ""
    end
  end

  defp render_poll_description_text(poll) do
    if poll.description && poll.description != "" do
      "#{poll.description}\n"
    else
      ""
    end
  end

  defp render_personal_message(message) when is_binary(message) and message != "" do
    """
    <div class="personal-message">
      #{html_escape(message)}
    </div>
    """
  end

  defp render_personal_message(_), do: ""

  defp render_personal_message_text(message) when is_binary(message) and message != "" do
    """
    Personal message: "#{message}"

    """
  end

  defp render_personal_message_text(_), do: ""

  defp render_event_image(event) do
    image_url = get_event_image_url(event)

    if image_url do
      """
      <img src="#{html_escape(image_url)}" alt="#{html_escape(event.title)}" class="event-image" />
      """
    else
      ""
    end
  end

  # Get event image URL from either cover_image_url or external_image_data
  # Wraps URLs with Cloudflare CDN transformations for email optimization
  defp get_event_image_url(event) do
    raw_url =
      cond do
        # Check for user-uploaded cover image
        event.cover_image_url && event.cover_image_url != "" ->
          event.cover_image_url

        # Check for external image data (Unsplash/TMDB)
        is_map(event.external_image_data) && Map.get(event.external_image_data, "url") ->
          Map.get(event.external_image_data, "url")

        # No image available
        true ->
          nil
      end

    # Apply CDN transformations for email optimization
    if raw_url do
      # Convert local paths to full URLs before CDN processing
      full_url = get_full_image_url(raw_url)

      Eventasaurus.CDN.url(full_url,
        width: 600,
        fit: "scale-down",
        quality: 85,
        format: "auto"
      )
    else
      nil
    end
  end

  # Convert relative/local image paths to full URLs
  defp get_full_image_url(image_url) do
    case URI.parse(image_url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Already a full URL
        image_url

      %URI{path: "/" <> _rest} ->
        # Absolute path, prepend base URL
        "#{get_base_url()}#{image_url}"

      _ ->
        # Relative path or invalid, prepend base URL
        "#{get_base_url()}/#{image_url}"
    end
  end

  defp get_base_url do
    # In production, use PHX_HOST environment variable
    # In development, use localhost
    case System.get_env("PHX_HOST") do
      nil -> "http://localhost:4000"
      host -> "https://#{host}"
    end
  end

  defp render_event_description(event) do
    if event.description && event.description != "" do
      truncated = truncate_text(event.description, 400)
      "<p>#{html_escape(truncated)}</p>"
    else
      ""
    end
  end

  defp render_event_description_text(event) do
    if event.description && event.description != "" do
      truncated = truncate_text(event.description, 400)
      "#{truncated}\n"
    else
      ""
    end
  end

  # Truncate text to specified character limit, ending at word boundary
  defp truncate_text(text, max_length) do
    Eventasaurus.Utils.Text.truncate_text(text, max_length)
  end

  defp render_event_location(event) do
    case get_venue_info(event) do
      {name, address} when is_binary(name) ->
        venue_html = "<p><strong>📍 Location:</strong> #{html_escape(name)}</p>"

        address_html =
          if address && address != "" do
            "<p style=\"margin-left: 20px; color: #666;\">#{html_escape(address)}</p>"
          else
            ""
          end

        venue_html <> address_html

      _ ->
        ""
    end
  end

  defp render_event_location_text(event) do
    case get_venue_info(event) do
      {name, address} when is_binary(name) ->
        venue_text = "📍 Location: #{name}\n"

        address_text =
          if address && address != "" do
            "   Address: #{address}\n"
          else
            ""
          end

        venue_text <> address_text

      _ ->
        ""
    end
  end

  # Helper to safely get venue info, handling both loaded and unloaded associations
  defp get_venue_info(event) do
    case event.venue do
      %Ecto.Association.NotLoaded{} -> nil
      %{name: name} = venue -> {name, Map.get(venue, :address)}
      nil -> nil
      _ -> nil
    end
  end

  defp render_event_price(event) do
    # Events don't have direct pricing - tickets do. For now, just indicate if it's ticketed
    if Map.get(event, :is_ticketed, false) do
      "<p><strong>💰 Price:</strong> See event details for ticket pricing</p>"
    else
      ""
    end
  end

  defp render_event_price_text(event) do
    # Events don't have direct pricing - tickets do. For now, just indicate if it's ticketed
    if Map.get(event, :is_ticketed, false) do
      "💰 Price: See event details for ticket pricing\n"
    else
      ""
    end
  end

  defp format_event_date(event) do
    case event.start_at do
      %DateTime{} = datetime ->
        datetime
        |> DateTime.to_date()
        |> Date.to_string()
        |> format_date_string()

      %Date{} = date ->
        date
        |> Date.to_string()
        |> format_date_string()

      _ ->
        "Date TBD"
    end
  end

  defp format_date_string(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        Calendar.strftime(date, "%B %d, %Y")

      _ ->
        date_string
    end
  end

  defp build_event_url(event) do
    base_url = Application.get_env(:eventasaurus, :base_url) || get_default_base_url()
    base = String.trim_trailing(base_url, "/")

    "#{base}/#{event.slug}"
  end

  defp get_default_base_url do
    env = Application.get_env(:eventasaurus, :environment) || :prod

    case env do
      :test -> "http://localhost:4002"
      :dev -> "http://localhost:4000"
      _ -> "https://wombie.com"
    end
  end
end
