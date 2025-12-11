defmodule Eventasaurus.Jobs.ThresholdAnnouncementJob do
  @moduledoc """
  Background job for sending "We Made It!" announcement emails to event attendees.

  This job is ORGANIZER-TRIGGERED (not automatic) when an event reaches its threshold goal.
  Following the Kickstarter pattern, organizers control when supporters receive the
  "we made it" announcement, rather than sending it automatically at potentially
  inappropriate times (e.g., 2am).

  The job sends emails to all registered attendees for the event, respecting
  Resend's rate limits.
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:event_id, :notification_type],
      # 24 hours - only send once per event to prevent duplicate announcements
      period: 86_400
    ]

  alias EventasaurusApp.{Events, Accounts}
  alias EventasaurusApp.Events.Event
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "event_id" => event_id,
          "organizer_id" => organizer_id,
          "notification_type" => "threshold_announcement"
        }
      }) do
    with {:ok, event} <- get_event_with_venue(event_id),
         {:ok, organizer} <- get_user(organizer_id),
         attendees when attendees != [] <- get_attendees(event) do
      send_announcements_to_attendees(attendees, event, organizer)
    else
      {:error, :event_not_found} ->
        Logger.warning("ThresholdAnnouncementJob: Event #{event_id} not found")
        {:error, :event_not_found}

      {:error, :user_not_found} ->
        Logger.warning("ThresholdAnnouncementJob: Organizer #{organizer_id} not found")
        {:error, :organizer_not_found}

      [] ->
        Logger.info("ThresholdAnnouncementJob: No attendees found for event #{event_id}")
        # Return :ok since no attendees is not an error - the announcement was successful,
        # there's just no one to notify
        :ok
    end
  end

  defp get_event_with_venue(event_id) do
    case Events.get_event_with_venue(event_id) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp get_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_attendees(event) do
    # Get all participants who are attending (going/interested)
    # This includes both free RSVPs and paid ticket holders
    Events.list_participants_by_status(event, :going) ++
      Events.list_participants_by_status(event, :interested)
  end

  defp send_announcements_to_attendees(attendees, event, organizer) do
    # Deduplicate by user_id in case someone is in multiple lists
    unique_attendees =
      attendees
      |> Enum.uniq_by(& &1.user_id)
      |> Enum.map(fn participant ->
        # Load the user for the participant
        Accounts.get_user(participant.user_id)
      end)
      |> Enum.reject(&is_nil/1)

    Logger.info(
      "ThresholdAnnouncementJob: Sending announcements to #{length(unique_attendees)} attendees for event #{event.id}"
    )

    results =
      Enum.map(unique_attendees, fn attendee ->
        # Add delay to respect Resend's 2/second rate limit
        # 600ms ensures we stay well under the limit
        Process.sleep(600)

        case Eventasaurus.Emails.send_threshold_announcement(attendee, event, organizer) do
          {:ok, _response} ->
            Logger.info("Threshold announcement sent to #{attendee.email} for event #{event.id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to send threshold announcement to #{attendee.email}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end)

    # Return :ok if at least one email was sent successfully
    successful_count = Enum.count(results, &(&1 == :ok))
    failed_count = length(results) - successful_count

    Logger.info(
      "ThresholdAnnouncementJob: Completed for event #{event.id}. " <>
        "Sent: #{successful_count}, Failed: #{failed_count}"
    )

    if successful_count > 0 do
      :ok
    else
      {:error, :all_emails_failed}
    end
  end

  @doc """
  Enqueues a threshold announcement job for an event.

  This should be called when an organizer clicks "Announce to Attendees"
  after their event has reached its threshold goal.

  ## Parameters
  - `event`: The event struct or event ID
  - `organizer`: The organizer user struct or user ID

  ## Returns
  - `{:ok, job}` on success
  - `{:error, changeset}` on failure
  """
  def enqueue(%Event{id: event_id}, organizer), do: enqueue(event_id, organizer)

  def enqueue(event_id, %{id: organizer_id}), do: enqueue(event_id, organizer_id)

  def enqueue(event_id, organizer_id)
      when (is_binary(event_id) or is_integer(event_id)) and
             (is_binary(organizer_id) or is_integer(organizer_id)) do
    %{
      event_id: event_id,
      organizer_id: organizer_id,
      notification_type: "threshold_announcement"
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
