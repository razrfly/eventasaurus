defmodule Eventasaurus.Jobs.DeadlineReminderNotificationJob do
  @moduledoc """
  Background job for sending deadline reminder notification emails to event organizers.

  This job is triggered 24 hours before an event's threshold/polling deadline.
  It sends a reminder email to all organizers of the event.
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:event_id, :notification_type],
      # 24 hours - only send once per event
      period: 86_400
    ]

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id, "notification_type" => "deadline_reminder"}}) do
    with {:ok, event} <- get_event_with_venue(event_id),
         :ok <- validate_deadline_still_valid(event),
         organizers when organizers != [] <- Events.list_event_organizers(event) do
      send_notifications_to_organizers(organizers, event)
    else
      {:error, :event_not_found} ->
        Logger.warning("DeadlineReminderNotificationJob: Event #{event_id} not found")
        {:error, :event_not_found}

      {:error, :deadline_passed} ->
        Logger.info("DeadlineReminderNotificationJob: Deadline already passed for event #{event_id}")
        :ok

      {:error, :event_confirmed} ->
        Logger.info("DeadlineReminderNotificationJob: Event #{event_id} already confirmed, skipping reminder")
        :ok

      [] ->
        Logger.warning("DeadlineReminderNotificationJob: No organizers found for event #{event_id}")
        {:error, :no_organizers}
    end
  end

  defp get_event_with_venue(event_id) do
    case Events.get_event_with_venue(event_id) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  # Check if the deadline is still relevant (not passed, event not confirmed/canceled)
  defp validate_deadline_still_valid(%Event{status: :confirmed}), do: {:error, :event_confirmed}
  defp validate_deadline_still_valid(%Event{status: :canceled}), do: {:error, :event_confirmed}
  defp validate_deadline_still_valid(%Event{polling_deadline: nil}), do: {:error, :deadline_passed}

  defp validate_deadline_still_valid(%Event{polling_deadline: deadline}) do
    if DateTime.compare(DateTime.utc_now(), deadline) == :lt do
      :ok
    else
      {:error, :deadline_passed}
    end
  end

  defp send_notifications_to_organizers(organizers, event) do
    results =
      Enum.map(organizers, fn organizer ->
        # Add small delay to respect Resend's rate limit
        Process.sleep(600)

        case Eventasaurus.Emails.send_deadline_reminder_notification(organizer, event) do
          {:ok, _response} ->
            Logger.info("Deadline reminder sent to #{organizer.email} for event #{event.id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to send deadline reminder to #{organizer.email}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end)

    # Return :ok if at least one email was sent successfully
    if Enum.any?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, :all_emails_failed}
    end
  end

  @doc """
  Enqueues a deadline reminder notification job for an event.

  ## Parameters
  - `event`: The event struct or event ID

  ## Returns
  - `{:ok, job}` on success
  - `{:error, changeset}` on failure
  """
  def enqueue(%Event{id: event_id}), do: enqueue(event_id)

  def enqueue(event_id) when is_binary(event_id) or is_integer(event_id) do
    %{event_id: event_id, notification_type: "deadline_reminder"}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedules a deadline reminder notification job for an event to run 24 hours before deadline.

  ## Parameters
  - `event`: The event struct with polling_deadline set

  ## Returns
  - `{:ok, job}` on success
  - `{:error, reason}` if deadline is too soon or missing
  """
  def schedule_for_deadline(%Event{polling_deadline: nil}), do: {:error, :no_deadline}

  def schedule_for_deadline(%Event{id: event_id, polling_deadline: deadline}) do
    # Calculate 24 hours before deadline
    scheduled_at = DateTime.add(deadline, -24, :hour)
    now = DateTime.utc_now()

    cond do
      # If deadline is less than 24 hours away, send immediately
      DateTime.compare(scheduled_at, now) == :lt ->
        enqueue(event_id)

      # Otherwise, schedule for 24 hours before deadline
      true ->
        %{event_id: event_id, notification_type: "deadline_reminder"}
        |> __MODULE__.new(scheduled_at: scheduled_at)
        |> Oban.insert()
    end
  end
end
