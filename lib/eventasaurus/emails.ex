defmodule Eventasaurus.Emails do
  @moduledoc """
  Email templates for guest invitations using Swoosh.
  """

  import Swoosh.Email
  require Logger

  alias EventasaurusWeb.UrlHelper

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
        # Absolute path, use UrlHelper to build full URL
        UrlHelper.build_url(image_url)

      _ ->
        # Relative path or invalid, prepend base URL
        UrlHelper.build_url("/#{image_url}")
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

  # ============================================================================
  # Threshold Event Notification Emails
  # ============================================================================

  @doc """
  Creates a threshold met notification email for the event organizer.

  Sent when an event reaches its threshold goal (attendee count or revenue).

  ## Parameters
  - `organizer`: The event organizer user struct
  - `event`: The event struct with threshold data

  ## Returns
  - `Swoosh.Email` struct ready to be sent
  """
  def threshold_met_email(organizer, event) do
    unless valid_email?(organizer.email) do
      raise ArgumentError, "Invalid email address: #{organizer.email}"
    end

    subject = "🎉 Great news! \"#{event.title}\" has reached its goal!"

    new()
    |> from({"Wombie", "notifications@wombie.com"})
    |> to({get_organizer_name(organizer), organizer.email})
    |> subject(subject)
    |> html_body(build_threshold_met_html(organizer, event))
    |> text_body(build_threshold_met_text(organizer, event))
  end

  @doc """
  Sends a threshold met notification email.

  ## Parameters
  - `organizer`: The event organizer user struct
  - `event`: The event struct

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  def send_threshold_met_notification(organizer, event) do
    try do
      email = threshold_met_email(organizer, event)

      case Eventasaurus.Mailer.deliver(email) do
        {:ok, response} ->
          Logger.info(
            "Threshold met email sent successfully to #{organizer.email} for event #{event.id}"
          )

          {:ok, response}

        {:error, reason} ->
          Logger.error(
            "Failed to send threshold met email to #{organizer.email}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error creating threshold met email: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a deadline reminder email for the event organizer.

  Sent 24 hours before the threshold/polling deadline.

  ## Parameters
  - `organizer`: The event organizer user struct
  - `event`: The event struct with deadline data

  ## Returns
  - `Swoosh.Email` struct ready to be sent
  """
  def deadline_reminder_email(organizer, event) do
    unless valid_email?(organizer.email) do
      raise ArgumentError, "Invalid email address: #{organizer.email}"
    end

    subject = "⏰ 24 hours left: \"#{event.title}\" deadline approaching"

    new()
    |> from({"Wombie", "notifications@wombie.com"})
    |> to({get_organizer_name(organizer), organizer.email})
    |> subject(subject)
    |> html_body(build_deadline_reminder_html(organizer, event))
    |> text_body(build_deadline_reminder_text(organizer, event))
  end

  @doc """
  Sends a deadline reminder notification email.

  ## Parameters
  - `organizer`: The event organizer user struct
  - `event`: The event struct

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  def send_deadline_reminder_notification(organizer, event) do
    try do
      email = deadline_reminder_email(organizer, event)

      case Eventasaurus.Mailer.deliver(email) do
        {:ok, response} ->
          Logger.info(
            "Deadline reminder email sent successfully to #{organizer.email} for event #{event.id}"
          )

          {:ok, response}

        {:error, reason} ->
          Logger.error(
            "Failed to send deadline reminder email to #{organizer.email}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error creating deadline reminder email: #{inspect(error)}")
        {:error, error}
    end
  end

  # Private helpers for threshold met email

  defp build_threshold_met_html(organizer, event) do
    manage_url = build_manage_event_url(event)
    threshold_info = format_threshold_info_html(event)

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Threshold Met - #{html_escape(event.title)}</title>
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
                background: linear-gradient(135deg, #10B981 0%, #059669 100%);
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
            .success-box {
                background: linear-gradient(135deg, #ECFDF5 0%, #D1FAE5 100%);
                border: 1px solid #10B981;
                border-radius: 12px;
                padding: 25px;
                margin: 25px 0;
                text-align: center;
            }
            .success-box h2 {
                margin: 0 0 10px 0;
                color: #059669;
                font-size: 24px;
            }
            .success-box p {
                margin: 8px 0;
                color: #047857;
                font-size: 16px;
            }
            .event-details {
                background: #f8f9fa;
                padding: 25px;
                border-radius: 12px;
                margin: 25px 0;
            }
            .event-details h3 {
                margin: 0 0 15px 0;
                color: #333;
            }
            .event-details p {
                margin: 8px 0;
                color: #666;
            }
            .cta-button {
                display: inline-block;
                background: linear-gradient(135deg, #10B981 0%, #059669 100%);
                color: white;
                padding: 16px 32px;
                text-decoration: none;
                border-radius: 8px;
                font-weight: 600;
                font-size: 16px;
                margin: 20px 0;
            }
            .next-steps {
                background: #FEF3C7;
                border-left: 4px solid #F59E0B;
                padding: 20px;
                margin: 25px 0;
                border-radius: 6px;
            }
            .next-steps h3 {
                margin: 0 0 12px 0;
                color: #92400E;
            }
            .next-steps ul {
                margin: 0;
                padding-left: 20px;
                color: #92400E;
            }
            .footer {
                text-align: center;
                color: #666;
                font-size: 14px;
                margin-top: 40px;
                padding: 20px;
                border-top: 1px solid #e9ecef;
            }
        </style>
    </head>
    <body>
        <div class="email-container">
            <div class="header">
                <img src="https://wombie.com/images/logos/general-white.png" alt="Wombie" style="width: 184px; height: auto; margin: 0 auto 20px auto; display: block;" />
                <h1>🎉 Goal Reached!</h1>
                <p>Your event has met its threshold</p>
            </div>

            <div class="content">
                <p>Hi #{html_escape(get_organizer_name(organizer))},</p>

                <p>Fantastic news! Your event has reached its goal:</p>

                <div class="success-box">
                    <h2>#{html_escape(event.title)}</h2>
                    #{threshold_info}
                </div>

                <div class="event-details">
                    <h3>Event Details</h3>
                    <p><strong>📅 Date:</strong> #{format_event_date(event)}</p>
                    #{render_event_location(event)}
                </div>

                <div class="next-steps">
                    <h3>What's Next?</h3>
                    <ul>
                        <li>Review your event details and confirm everything is ready</li>
                        <li>Click "Confirm Event" to finalize and notify attendees</li>
                        <li>Consider sending a thank-you message to early supporters</li>
                    </ul>
                </div>

                <p style="text-align: center;">
                    <a href="#{html_escape(manage_url)}" class="cta-button">
                        Manage Your Event
                    </a>
                </p>

                <p>Congratulations on reaching this milestone!</p>

                <p>Best regards,<br>
                <strong>The Wombie Team</strong></p>
            </div>

            <div class="footer">
                <p>This notification was sent via <a href="https://wombie.com">Wombie</a></p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp build_threshold_met_text(organizer, event) do
    manage_url = build_manage_event_url(event)
    threshold_info = format_threshold_info_text(event)

    """
    🎉 GOAL REACHED!

    Hi #{get_organizer_name(organizer)},

    Fantastic news! Your event has reached its goal:

    #{event.title}
    #{threshold_info}

    EVENT DETAILS:
    📅 Date: #{format_event_date(event)}
    #{render_event_location_text(event)}

    WHAT'S NEXT:
    • Review your event details and confirm everything is ready
    • Click "Confirm Event" to finalize and notify attendees
    • Consider sending a thank-you message to early supporters

    Manage your event: #{manage_url}

    Congratulations on reaching this milestone!

    Best regards,
    The Wombie Team

    ---
    This notification was sent via Wombie (https://wombie.com)
    """
  end

  # Private helpers for deadline reminder email

  defp build_deadline_reminder_html(organizer, event) do
    manage_url = build_manage_event_url(event)
    progress_info = format_progress_info_html(event)

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Deadline Reminder - #{html_escape(event.title)}</title>
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
                background: linear-gradient(135deg, #F59E0B 0%, #D97706 100%);
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
            .countdown-box {
                background: linear-gradient(135deg, #FEF3C7 0%, #FDE68A 100%);
                border: 1px solid #F59E0B;
                border-radius: 12px;
                padding: 25px;
                margin: 25px 0;
                text-align: center;
            }
            .countdown-box h2 {
                margin: 0 0 10px 0;
                color: #92400E;
                font-size: 24px;
            }
            .countdown-box .time {
                font-size: 36px;
                font-weight: bold;
                color: #D97706;
                margin: 10px 0;
            }
            .progress-box {
                background: #f8f9fa;
                padding: 25px;
                border-radius: 12px;
                margin: 25px 0;
            }
            .progress-box h3 {
                margin: 0 0 15px 0;
                color: #333;
            }
            .progress-bar {
                background: #e9ecef;
                border-radius: 10px;
                height: 20px;
                overflow: hidden;
                margin: 15px 0;
            }
            .progress-fill {
                background: linear-gradient(135deg, #F59E0B 0%, #D97706 100%);
                height: 100%;
                border-radius: 10px;
            }
            .cta-button {
                display: inline-block;
                background: linear-gradient(135deg, #F59E0B 0%, #D97706 100%);
                color: white;
                padding: 16px 32px;
                text-decoration: none;
                border-radius: 8px;
                font-weight: 600;
                font-size: 16px;
                margin: 20px 0;
            }
            .tips {
                background: #EFF6FF;
                border-left: 4px solid #3B82F6;
                padding: 20px;
                margin: 25px 0;
                border-radius: 6px;
            }
            .tips h3 {
                margin: 0 0 12px 0;
                color: #1E40AF;
            }
            .tips ul {
                margin: 0;
                padding-left: 20px;
                color: #1E40AF;
            }
            .footer {
                text-align: center;
                color: #666;
                font-size: 14px;
                margin-top: 40px;
                padding: 20px;
                border-top: 1px solid #e9ecef;
            }
        </style>
    </head>
    <body>
        <div class="email-container">
            <div class="header">
                <img src="https://wombie.com/images/logos/general-white.png" alt="Wombie" style="width: 184px; height: auto; margin: 0 auto 20px auto; display: block;" />
                <h1>⏰ 24 Hours Left!</h1>
                <p>Your campaign deadline is approaching</p>
            </div>

            <div class="content">
                <p>Hi #{html_escape(get_organizer_name(organizer))},</p>

                <p>Just a friendly reminder that your event's deadline is in 24 hours:</p>

                <div class="countdown-box">
                    <h2>#{html_escape(event.title)}</h2>
                    <div class="time">24 HOURS</div>
                    <p>until deadline: #{format_deadline(event.polling_deadline)}</p>
                </div>

                #{progress_info}

                <div class="tips">
                    <h3>💡 Last-Minute Tips</h3>
                    <ul>
                        <li>Share on social media one more time</li>
                        <li>Send a reminder to friends who haven't signed up yet</li>
                        <li>Update your event description if needed</li>
                    </ul>
                </div>

                <p style="text-align: center;">
                    <a href="#{html_escape(manage_url)}" class="cta-button">
                        View Your Event
                    </a>
                </p>

                <p>You've got this! 💪</p>

                <p>Best regards,<br>
                <strong>The Wombie Team</strong></p>
            </div>

            <div class="footer">
                <p>This notification was sent via <a href="https://wombie.com">Wombie</a></p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp build_deadline_reminder_text(organizer, event) do
    manage_url = build_manage_event_url(event)
    progress_info = format_progress_info_text(event)

    """
    ⏰ 24 HOURS LEFT!

    Hi #{get_organizer_name(organizer)},

    Just a friendly reminder that your event's deadline is in 24 hours:

    #{event.title}
    Deadline: #{format_deadline(event.polling_deadline)}

    #{progress_info}

    LAST-MINUTE TIPS:
    • Share on social media one more time
    • Send a reminder to friends who haven't signed up yet
    • Update your event description if needed

    View your event: #{manage_url}

    You've got this! 💪

    Best regards,
    The Wombie Team

    ---
    This notification was sent via Wombie (https://wombie.com)
    """
  end

  # Helper functions for threshold emails

  defp build_manage_event_url(event) do
    base_url = Application.get_env(:eventasaurus, :base_url) || get_default_base_url()
    base = String.trim_trailing(base_url, "/")
    "#{base}/events/#{event.slug}/manage"
  end

  defp format_threshold_info_html(event) do
    case event.threshold_type do
      "attendee_count" ->
        "<p><strong>✅ #{event.threshold_count || 0} attendees reached!</strong></p>"

      "revenue" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)
        "<p><strong>✅ #{revenue_display} revenue goal reached!</strong></p>"

      "both" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)

        """
        <p><strong>✅ #{event.threshold_count || 0} attendees reached!</strong></p>
        <p><strong>✅ #{revenue_display} revenue goal reached!</strong></p>
        """

      _ ->
        "<p><strong>✅ Goal reached!</strong></p>"
    end
  end

  defp format_threshold_info_text(event) do
    case event.threshold_type do
      "attendee_count" ->
        "✅ #{event.threshold_count || 0} attendees reached!"

      "revenue" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)
        "✅ #{revenue_display} revenue goal reached!"

      "both" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)

        "✅ #{event.threshold_count || 0} attendees reached!\n✅ #{revenue_display} revenue goal reached!"

      _ ->
        "✅ Goal reached!"
    end
  end

  defp format_progress_info_html(event) do
    # Calculate progress percentage (this would need actual attendee count from context)
    # For now, show the threshold goal
    case event.threshold_type do
      "attendee_count" ->
        """
        <div class="progress-box">
            <h3>Current Progress</h3>
            <p>Goal: <strong>#{event.threshold_count || 0} attendees</strong></p>
        </div>
        """

      "revenue" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)

        """
        <div class="progress-box">
            <h3>Current Progress</h3>
            <p>Goal: <strong>#{revenue_display}</strong></p>
        </div>
        """

      "both" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)

        """
        <div class="progress-box">
            <h3>Current Progress</h3>
            <p>Attendee Goal: <strong>#{event.threshold_count || 0}</strong></p>
            <p>Revenue Goal: <strong>#{revenue_display}</strong></p>
        </div>
        """

      _ ->
        ""
    end
  end

  defp format_progress_info_text(event) do
    case event.threshold_type do
      "attendee_count" ->
        "CURRENT PROGRESS:\nGoal: #{event.threshold_count || 0} attendees"

      "revenue" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)
        "CURRENT PROGRESS:\nGoal: #{revenue_display}"

      "both" ->
        revenue_display = format_currency(event.threshold_revenue_cents || 0)

        "CURRENT PROGRESS:\nAttendee Goal: #{event.threshold_count || 0}\nRevenue Goal: #{revenue_display}"

      _ ->
        ""
    end
  end

  defp format_deadline(nil), do: "Not set"

  defp format_deadline(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %H:%M UTC")
  end

  defp format_currency(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_currency(_), do: "$0.00"

  # ============================================================================
  # Threshold Announcement Emails (Organizer-Triggered to Attendees)
  # ============================================================================

  @doc """
  Creates a "We Made It!" announcement email for an attendee.

  This is sent by the organizer to all registered attendees when the threshold
  goal is reached. Unlike automatic notifications, this is organizer-triggered
  to give them control over timing and messaging.

  ## Parameters
  - `attendee`: The attendee user struct (with email)
  - `event`: The event struct with threshold data
  - `organizer`: The organizer who triggered the announcement

  ## Returns
  - `Swoosh.Email` struct ready to be sent
  """
  def threshold_announcement_email(attendee, event, organizer) do
    unless valid_email?(attendee.email) do
      raise ArgumentError, "Invalid email address: #{attendee.email}"
    end

    attendee_name = get_attendee_name(attendee)
    subject = "🎉 Great news! \"#{event.title}\" is happening!"

    new()
    |> from({"Wombie", "notifications@wombie.com"})
    |> to({attendee_name, attendee.email})
    |> subject(subject)
    |> reply_to(organizer.email)
    |> html_body(build_threshold_announcement_html(attendee, event, organizer))
    |> text_body(build_threshold_announcement_text(attendee, event, organizer))
  end

  @doc """
  Sends a threshold announcement email to an attendee.

  ## Parameters
  - `attendee`: The attendee user struct
  - `event`: The event struct
  - `organizer`: The organizer who triggered the announcement

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  def send_threshold_announcement(attendee, event, organizer) do
    try do
      email = threshold_announcement_email(attendee, event, organizer)

      case Eventasaurus.Mailer.deliver(email) do
        {:ok, response} ->
          Logger.info("Threshold announcement sent to #{attendee.email} for event #{event.id}")
          {:ok, response}

        {:error, reason} ->
          Logger.error(
            "Failed to send threshold announcement to #{attendee.email}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error creating threshold announcement email: #{inspect(error)}")
        {:error, error}
    end
  end

  # Private helpers for threshold announcement email

  defp get_attendee_name(attendee) do
    attendee.name || attendee.username || "there"
  end

  defp build_threshold_announcement_html(attendee, event, organizer) do
    event_url = build_event_url(event)
    attendee_name = get_attendee_name(attendee)

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{html_escape(event.title)} - It's Happening!</title>
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
                background: linear-gradient(135deg, #10B981 0%, #059669 100%);
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
            .celebration {
                font-size: 48px;
                margin-bottom: 15px;
            }
            .content {
                padding: 40px 30px;
            }
            .content p {
                margin: 16px 0;
                font-size: 16px;
            }
            .success-box {
                background: linear-gradient(135deg, #ECFDF5 0%, #D1FAE5 100%);
                border: 1px solid #10B981;
                border-radius: 12px;
                padding: 25px;
                margin: 25px 0;
                text-align: center;
            }
            .success-box h2 {
                margin: 0 0 10px 0;
                color: #059669;
                font-size: 24px;
            }
            .success-box p {
                margin: 8px 0;
                color: #047857;
                font-size: 16px;
            }
            .event-details {
                background: #f8f9fa;
                padding: 25px;
                border-radius: 12px;
                margin: 25px 0;
            }
            .event-details h3 {
                margin: 0 0 15px 0;
                color: #333;
            }
            .event-details p {
                margin: 8px 0;
                color: #666;
            }
            .cta-button {
                display: inline-block;
                background: linear-gradient(135deg, #10B981 0%, #059669 100%);
                color: white;
                padding: 16px 32px;
                text-decoration: none;
                border-radius: 8px;
                font-weight: 600;
                font-size: 16px;
                margin: 20px 0;
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
                color: #10B981;
                text-decoration: none;
            }
        </style>
    </head>
    <body>
        <div class="email-container">
            <div class="header">
                <img src="https://wombie.com/images/logos/general-white.png" alt="Wombie" style="width: 184px; height: auto; margin: 0 auto 20px auto; display: block;" />
                <div class="celebration">🎉</div>
                <h1>We Made It!</h1>
                <p>Thanks to you and other supporters</p>
            </div>

            <div class="content">
                <p>Hi #{html_escape(attendee_name)},</p>

                <p>Great news! Thanks to your support and others like you, this event has reached its goal and <strong>is officially happening!</strong></p>

                <div class="success-box">
                    <h2>#{html_escape(event.title)}</h2>
                    <p>✅ Goal reached - Event confirmed!</p>
                </div>

                <div class="event-details">
                    <h3>Event Details</h3>
                    #{render_event_image(event)}
                    <p><strong>📅 Date:</strong> #{format_event_date(event)}</p>
                    #{render_event_location(event)}
                </div>

                <p>We're thrilled to have you as part of this event. Stay tuned for more details from #{html_escape(get_organizer_name(organizer))}.</p>

                <p style="text-align: center;">
                    <a href="#{html_escape(event_url)}" class="cta-button">
                        View Event Details
                    </a>
                </p>

                <p>See you there!</p>

                <p>Best regards,<br>
                #{html_escape(get_organizer_name(organizer))}<br>
                <strong>via Wombie</strong></p>
            </div>

            <div class="footer">
                <p>This announcement was sent by #{html_escape(get_organizer_name(organizer))} via <a href="https://wombie.com">Wombie</a></p>
                <p>You're receiving this because you registered for this event.</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp build_threshold_announcement_text(attendee, event, organizer) do
    event_url = build_event_url(event)
    attendee_name = get_attendee_name(attendee)

    """
    🎉 WE MADE IT!

    Hi #{attendee_name},

    Great news! Thanks to your support and others like you, this event has reached its goal and is officially happening!

    #{event.title}
    ✅ Goal reached - Event confirmed!

    EVENT DETAILS:
    📅 Date: #{format_event_date(event)}
    #{render_event_location_text(event)}

    We're thrilled to have you as part of this event. Stay tuned for more details from #{get_organizer_name(organizer)}.

    View event details: #{event_url}

    See you there!

    Best regards,
    #{get_organizer_name(organizer)}
    via Wombie

    ---
    This announcement was sent by #{get_organizer_name(organizer)} via Wombie (https://wombie.com)
    You're receiving this because you registered for this event.
    """
  end
end
