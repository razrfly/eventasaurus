defmodule Eventasaurus.Jobs.EmailInvitationJob do
  @moduledoc """
  Background job for sending event invitation emails with rate limiting.
  Respects Resend's 2 requests/second rate limit.
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 3,
    unique: [
      fields: [:args], 
      keys: [:user_id, :event_id], 
      period: 300  # 5 minutes
    ]

  alias EventasaurusApp.{Events, Accounts}
  alias EventasaurusApp.Events.EventParticipant
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
    args: %{
      "user_id" => user_id,
      "event_id" => event_id,
      "invitation_message" => invitation_message,
      "organizer_id" => organizer_id
    }
  }) do
    with {:ok, user} <- get_user(user_id),
         {:ok, event} <- get_event_with_venue(event_id),
         {:ok, organizer} <- get_user(organizer_id),
         {:ok, participant} <- get_participant(event, user) do
      
      send_invitation_email(user, event, invitation_message, organizer, participant)
    else
      {:error, reason} ->
        Logger.error("Email invitation job failed", 
          user_id: user_id, 
          event_id: event_id, 
          reason: inspect(reason)
        )
        {:error, reason}
    end
  end

  # Private functions for fetching data and sending emails
  defp get_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_event_with_venue(event_id) do
    case Events.get_event_with_venue(event_id) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp get_participant(event, user) do
    case Events.get_event_participant_by_event_and_user(event, user) do
      nil -> {:error, :participant_not_found}
      participant -> {:ok, participant}
    end
  end

  defp send_invitation_email(user, event, invitation_message, organizer, participant) do
    # Mark email as being sent
    updated_participant = EventParticipant.update_email_status(participant, "sending")
    Events.update_event_participant(participant, %{metadata: updated_participant.metadata})

    # Add small delay to respect Resend's 2/second rate limit
    # With max 2 concurrent jobs, this ensures we stay under the limit
    Process.sleep(600)  # 0.6 seconds

    guest_name = Events.get_user_display_name(user)

    case Eventasaurus.Emails.send_guest_invitation(
      user.email,
      guest_name,
      event,
      invitation_message,
      organizer
    ) do
      {:ok, response} ->
        Logger.info("Email invitation sent successfully",
          user_id: user.id,
          event_id: event.id,
          organizer_id: organizer.id
        )

        # Mark email as sent successfully
        delivery_id = extract_delivery_id(response)
        sent_participant = EventParticipant.mark_email_sent(participant, delivery_id)
        Events.update_event_participant(participant, %{metadata: sent_participant.metadata})
        :ok

      {:error, reason} ->
        Logger.error("Failed to send invitation email",
          user_id: user.id,
          event_id: event.id,
          organizer_id: organizer.id,
          reason: inspect(reason)
        )

        # Mark email as failed
        error_message = Events.format_email_error(reason)
        failed_participant = EventParticipant.mark_email_failed(participant, error_message)
        Events.update_event_participant(participant, %{metadata: failed_participant.metadata})
        
        {:error, reason}
    end
  end

  defp extract_delivery_id(response) do
    # Extract delivery ID from Resend response
    case response do
      %{"id" => id} -> id
      _ -> nil
    end
  end
end