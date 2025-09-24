defmodule Eventasaurus.Emails do
  @moduledoc """
  Email templates for guest invitations using Swoosh.
  """

  import Swoosh.Email
  require Logger

  @from_email {"Eventasaurus", "invitations@eventasaur.us"}

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
                <h1>🎉 You're Invited!</h1>
                <p>#{html_escape(get_organizer_name(organizer))} has invited you to an event</p>
            </div>

            <div class="content">
                <p>Hi #{html_escape(guest_name || "there")},</p>

                #{render_personal_message(invitation_message)}

                <p>You've been invited to join:</p>

                <div class="event-details">
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

                <p>We're excited to have you join us!</p>

                <p>Best regards,<br>
                #{html_escape(get_organizer_name(organizer))}<br>
                <strong>The Eventasaurus Team</strong></p>
            </div>

            <div class="footer">
                <p>This invitation was sent via <a href="https://eventasaur.us">Eventasaurus</a></p>
                <p>Can't attend? Just ignore this email.</p>
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

    We're excited to have you join us!

    Best regards,
    #{get_organizer_name(organizer)}
    The Eventasaurus Team

    ---
    This invitation was sent via Eventasaurus (https://eventasaur.us)
    Can't attend? Just ignore this email.
    """
  end

  # Helper functions for content rendering

  defp get_organizer_name(organizer) do
    organizer.name || organizer.username || "Event Organizer"
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

  defp render_event_description(event) do
    if event.description && event.description != "" do
      "<p>#{html_escape(event.description)}</p>"
    else
      ""
    end
  end

  defp render_event_description_text(event) do
    if event.description && event.description != "" do
      "#{event.description}\n"
    else
      ""
    end
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
      _ -> "https://eventasaur.us"
    end
  end
end
