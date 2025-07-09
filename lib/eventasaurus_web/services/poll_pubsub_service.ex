defmodule EventasaurusWeb.Services.PollPubSubService do
  @moduledoc """
  Enhanced PubSub service for the polling system providing granular real-time updates.

  This service provides:
  - Granular topic structure for different types of updates
  - Live notifications for new suggestions and moderation actions
  - Real-time counter updates (suggestion count, participant count)
  - Live status updates for option visibility changes
  - Mobile-friendly notification system with structured messages
  """

  require Logger
  alias Phoenix.PubSub

  @pubsub Eventasaurus.PubSub

  # Topic patterns for different types of updates
  @poll_topic_prefix "poll"
  @event_topic_prefix "event"
  @user_topic_prefix "user"
  @moderation_topic_prefix "moderation"

  ## Broadcasting Functions

  @doc """
  Broadcasts when a new poll option is suggested.
  Provides real-time notifications to all poll participants and organizers.
  """
  def broadcast_option_suggested(poll, option, user) do
    Logger.debug("Broadcasting option suggested", %{
      poll_id: poll.id,
      option_id: option.id,
      user_id: user.id
    })

    message = %{
      type: :option_suggested,
      poll_id: poll.id,
      option: serialize_option(option),
      suggested_by: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        total_options: count_poll_options(poll),
        is_duplicate: false
      }
    }

    # Broadcast to multiple granular topics
    broadcast_to_poll_participants(poll.id, message)
    broadcast_to_poll_moderators(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)

    # Mobile notification
    send_mobile_notification(poll, :option_suggested, %{
      title: "New suggestion in #{poll.title}",
      body: "#{user.name || user.email} suggested: #{option.title}",
      data: %{poll_id: poll.id, option_id: option.id}
    })
  end

  @doc """
  Broadcasts when a duplicate option is detected during suggestion.
  """
  def broadcast_duplicate_detected(poll, suggested_option, duplicate_options, user) do
    message = %{
      type: :duplicate_detected,
      poll_id: poll.id,
      suggested_option: serialize_option(suggested_option),
      duplicate_options: Enum.map(duplicate_options, &serialize_option/1),
      detected_by: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        similarity_scores: extract_similarity_scores(duplicate_options)
      }
    }

    # Only broadcast to the user who suggested and moderators
    broadcast_to_user(user.id, message)
    broadcast_to_poll_moderators(poll.id, message)
  end

  @doc """
  Broadcasts when poll options are reordered via drag-and-drop.
  """
  def broadcast_options_reordered(poll, updated_options, user) do
    message = %{
      type: :options_reordered,
      poll_id: poll.id,
      updated_options: Enum.map(updated_options, &serialize_option_with_order/1),
      reordered_by: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        total_options: length(updated_options)
      }
    }

    broadcast_to_poll_participants(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)
  end

  @doc """
  Broadcasts when an option's visibility is changed by a moderator.
  """
  def broadcast_option_visibility_changed(poll, option, action, user) when action in [:hidden, :shown] do
    message = %{
      type: :option_visibility_changed,
      poll_id: poll.id,
      option: serialize_option(option),
      action: action,
      changed_by: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        total_visible_options: count_visible_options(poll),
        total_hidden_options: count_hidden_options(poll)
      }
    }

    # Broadcast to participants (they need to see/hide options)
    broadcast_to_poll_participants(poll.id, message)
    # Broadcast to moderators (for admin interface updates)
    broadcast_to_poll_moderators(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)
  end

  @doc """
  Broadcasts real-time counter updates for polls.
  """
  def broadcast_poll_counters_updated(poll, counters) do
    message = %{
      type: :poll_counters_updated,
      poll_id: poll.id,
      counters: counters,
      timestamp: DateTime.utc_now()
    }

    broadcast_to_poll_participants(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)
  end

  @doc """
  Broadcasts when poll phase transitions occur.
  """
  def broadcast_poll_phase_changed(poll, old_phase, new_phase, user) do
    message = %{
      type: :poll_phase_changed,
      poll_id: poll.id,
      old_phase: old_phase,
      new_phase: new_phase,
      changed_by: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        allows_suggestions: new_phase == "list_building",
        allows_voting: new_phase == "voting"
      }
    }

    broadcast_to_poll_participants(poll.id, message)
    broadcast_to_poll_moderators(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)

    # Mobile notification for phase changes
    send_mobile_notification(poll, :phase_changed, %{
      title: "#{poll.title} phase changed",
      body: "Poll is now in #{format_phase_for_notification(new_phase)} phase",
      data: %{poll_id: poll.id, new_phase: new_phase}
    })
  end

  @doc """
  Broadcasts bulk moderation actions (hide/show/delete multiple options).
  """
  def broadcast_bulk_moderation_action(poll, action, option_ids, user) do
    message = %{
      type: :bulk_moderation_action,
      poll_id: poll.id,
      action: action,
      option_ids: option_ids,
      performed_by: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        affected_count: length(option_ids),
        total_options: count_poll_options(poll)
      }
    }

    broadcast_to_poll_participants(poll.id, message)
    broadcast_to_poll_moderators(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)
  end

  @doc """
  Broadcasts when new users join a poll (for participant count updates).
  """
  def broadcast_participant_joined(poll, user) do
    message = %{
      type: :participant_joined,
      poll_id: poll.id,
      participant: serialize_user(user),
      timestamp: DateTime.utc_now(),
      metadata: %{
        total_participants: count_poll_participants(poll)
      }
    }

    broadcast_to_poll_participants(poll.id, message)
    broadcast_to_event_participants(poll.event_id, message)
  end

  ## Subscription Functions

  @doc """
  Subscribe to all updates for a specific poll.
  """
  def subscribe_to_poll(poll_id) do
    topics = [
      "#{@poll_topic_prefix}:#{poll_id}:participants",
      "#{@poll_topic_prefix}:#{poll_id}:moderators",
      "#{@poll_topic_prefix}:#{poll_id}:counters"
    ]

    Enum.each(topics, &PubSub.subscribe(@pubsub, &1))
  end

  @doc """
  Subscribe to moderation updates for a specific poll.
  """
  def subscribe_to_poll_moderation(poll_id) do
    PubSub.subscribe(@pubsub, "#{@poll_topic_prefix}:#{poll_id}:moderators")
    PubSub.subscribe(@pubsub, "#{@moderation_topic_prefix}:poll:#{poll_id}")
  end

  @doc """
  Subscribe to all poll updates for an event.
  """
  def subscribe_to_event_polls(event_id) do
    PubSub.subscribe(@pubsub, "#{@event_topic_prefix}:#{event_id}:polls")
  end

  @doc """
  Subscribe to user-specific notifications.
  """
  def subscribe_to_user_notifications(user_id) do
    PubSub.subscribe(@pubsub, "#{@user_topic_prefix}:#{user_id}:notifications")
  end

  ## Private Broadcasting Helpers

  defp broadcast_to_poll_participants(poll_id, message) do
    topic = "#{@poll_topic_prefix}:#{poll_id}:participants"
    PubSub.broadcast(@pubsub, topic, message)
  end

  defp broadcast_to_poll_moderators(poll_id, message) do
    topic = "#{@poll_topic_prefix}:#{poll_id}:moderators"
    PubSub.broadcast(@pubsub, topic, message)
  end

  defp broadcast_to_event_participants(event_id, message) do
    topic = "#{@event_topic_prefix}:#{event_id}:polls"
    PubSub.broadcast(@pubsub, topic, message)
  end

  defp broadcast_to_user(user_id, message) do
    topic = "#{@user_topic_prefix}:#{user_id}:notifications"
    PubSub.broadcast(@pubsub, topic, message)
  end

  ## Mobile Notification System

  defp send_mobile_notification(poll, type, notification_data) do
    # This would integrate with a push notification service
    # For now, we'll broadcast to a mobile-specific topic
    message = %{
      type: :mobile_notification,
      notification_type: type,
      poll_id: poll.id,
      data: notification_data,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(@pubsub, "mobile:notifications", message)
  end

  ## Serialization Helpers

  defp serialize_option(option) do
    %{
      id: option.id,
      title: option.title,
      description: option.description,
      is_visible: option_visible?(option),
      order_index: option.order_index,
      external_id: option.external_id,
      external_data: option.external_data,
      metadata: option.metadata,
      created_at: option.inserted_at
    }
  end

  defp serialize_option_with_order(option) do
    serialize_option(option)
    |> Map.put(:new_order_index, option.order_index)
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      avatar_url: EventasaurusWeb.Helpers.AvatarHelper.avatar_url(user)
    }
  end

  ## Counter Calculation Helpers

  defp count_poll_options(poll) do
    length(poll.poll_options || [])
  end

  defp count_visible_options(poll) do
    (poll.poll_options || [])
    |> Enum.count(& &1.status == "active")
  end

  defp count_hidden_options(poll) do
    (poll.poll_options || [])
    |> Enum.count(&option_hidden?/1)
  end

  defp count_poll_participants(_poll) do
    # This would need to be calculated based on actual participants
    # For now, return a placeholder
    0
  end

  ## Helper Functions

  defp option_visible?(option) do
    case option.status do
      "active" -> true
      _ -> false
    end
  end

  defp option_hidden?(option) do
    case option.status do
      "active" -> false
      nil -> false  # Consider nil status as not hidden
      _ -> true
    end
  end

  defp extract_similarity_scores(duplicate_options) do
    Enum.map(duplicate_options, fn option ->
      %{
        option_id: option.id,
        similarity_score: option.similarity_score || 0.0
      }
    end)
  end

  defp format_phase_for_notification("list_building"), do: "suggestion collection"
  defp format_phase_for_notification("voting"), do: "voting"
  defp format_phase_for_notification("closed"), do: "results"
  defp format_phase_for_notification(phase), do: phase
end
