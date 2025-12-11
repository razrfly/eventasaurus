defmodule Eventasaurus.Jobs.ThresholdMetNotificationJob do
  @moduledoc """
  Background job for sending threshold met notification emails to event organizers.

  This job is triggered when an event reaches its threshold goal (attendee count or revenue).
  It sends a congratulatory email to all organizers of the event.
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
  def perform(%Oban.Job{args: %{"event_id" => event_id, "notification_type" => "threshold_met"}}) do
    with {:ok, event} <- get_event_with_venue(event_id),
         organizers when organizers != [] <- Events.list_event_organizers(event) do
      send_notifications_to_organizers(organizers, event)
    else
      {:error, :event_not_found} ->
        Logger.warning("ThresholdMetNotificationJob: Event #{event_id} not found")
        {:error, :event_not_found}

      [] ->
        Logger.warning("ThresholdMetNotificationJob: No organizers found for event #{event_id}")
        {:error, :no_organizers}
    end
  end

  defp get_event_with_venue(event_id) do
    case Events.get_event_with_venue(event_id) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp send_notifications_to_organizers(organizers, event) do
    results =
      Enum.map(organizers, fn organizer ->
        # Add small delay to respect Resend's rate limit
        Process.sleep(600)

        case Eventasaurus.Emails.send_threshold_met_notification(organizer, event) do
          {:ok, _response} ->
            Logger.info("Threshold met notification sent to #{organizer.email} for event #{event.id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to send threshold met notification to #{organizer.email}: #{inspect(reason)}"
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
  Enqueues a threshold met notification job for an event.

  ## Parameters
  - `event`: The event struct or event ID

  ## Returns
  - `{:ok, job}` on success
  - `{:error, changeset}` on failure
  """
  def enqueue(%Event{id: event_id}), do: enqueue(event_id)

  def enqueue(event_id) when is_binary(event_id) or is_integer(event_id) do
    %{event_id: event_id, notification_type: "threshold_met"}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
