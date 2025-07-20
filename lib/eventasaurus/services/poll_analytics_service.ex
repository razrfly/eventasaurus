defmodule Eventasaurus.Services.PollAnalyticsService do
  @moduledoc """
  Service for tracking poll-related analytics events to PostHog.
  Handles all poll engagement metrics including voting, creation, and interactions.
  """

  alias Eventasaurus.Services.PosthogService
  require Logger

  # Poll creation events
  @spec track_poll_created(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_created(user_id, poll_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    PosthogService.send_event("poll_created", user_id, properties)
  end

  # Poll voting events
  @spec track_poll_vote(String.t() | nil, String.t(), String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_vote(user_id, poll_id, option_id, voting_system, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      option_id: option_id,
      voting_system: voting_system,
      is_anonymous: is_nil(user_id),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    # Use anonymous ID if user_id is nil
    user_identifier = user_id || "anonymous_#{:rand.uniform(1_000_000)}"
    
    PosthogService.send_event("poll_vote", user_identifier, properties)
  end

  # Poll option suggestion events
  @spec track_poll_suggestion_created(String.t() | nil, String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_suggestion_created(user_id, poll_id, suggestion_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      suggestion_id: suggestion_id,
      is_anonymous: is_nil(user_id),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    user_identifier = user_id || "anonymous_#{:rand.uniform(1_000_000)}"
    
    PosthogService.send_event("poll_suggestion_created", user_identifier, properties)
  end

  # Poll suggestion approval events
  @spec track_poll_suggestion_approved(String.t(), String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_suggestion_approved(approver_id, poll_id, suggestion_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      suggestion_id: suggestion_id,
      approver_id: approver_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    PosthogService.send_event("poll_suggestion_approved", approver_id, properties)
  end

  # Poll phase transition events
  @spec track_poll_phase_changed(String.t(), String.t(), String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_phase_changed(user_id, poll_id, from_phase, to_phase, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      from_phase: from_phase,
      to_phase: to_phase,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    PosthogService.send_event("poll_phase_changed", user_id, properties)
  end

  # Poll view events
  @spec track_poll_viewed(String.t() | nil, String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_viewed(user_id, poll_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      is_anonymous: is_nil(user_id),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    user_identifier = user_id || "anonymous_#{:rand.uniform(1_000_000)}"
    
    PosthogService.send_event("poll_viewed", user_identifier, properties)
  end

  # Poll results view events
  @spec track_poll_results_viewed(String.t() | nil, String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_results_viewed(user_id, poll_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      is_anonymous: is_nil(user_id),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    user_identifier = user_id || "anonymous_#{:rand.uniform(1_000_000)}"
    
    PosthogService.send_event("poll_results_viewed", user_identifier, properties)
  end

  # Clear votes events
  @spec track_poll_votes_cleared(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_votes_cleared(user_id, poll_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    PosthogService.send_event("poll_votes_cleared", user_id, properties)
  end

  # Poll deleted events
  @spec track_poll_deleted(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_deleted(user_id, poll_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    PosthogService.send_event("poll_deleted", user_id, properties)
  end

  # Guest invitation events (for polls)
  @spec track_poll_guest_invited(String.t(), String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_poll_guest_invited(inviter_id, poll_id, event_id, metadata \\ %{}) do
    properties = Map.merge(%{
      poll_id: poll_id,
      event_id: event_id,
      invitation_method: Map.get(metadata, :invitation_method, "email"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }, metadata)

    PosthogService.send_event("poll_guest_invited", inviter_id, properties)
  end

  # Batch event tracking for performance
  @spec track_batch_events(list(map())) :: {:ok, list()} | {:error, any()}
  def track_batch_events(events) do
    results = Enum.map(events, fn event ->
      case event do
        %{event_name: "poll_created", user_id: user_id, poll_id: poll_id} = event ->
          track_poll_created(user_id, poll_id, Map.get(event, :metadata, %{}))
          
        %{event_name: "poll_vote", user_id: user_id, poll_id: poll_id, option_id: option_id, voting_system: voting_system} = event ->
          track_poll_vote(user_id, poll_id, option_id, voting_system, Map.get(event, :metadata, %{}))
          
        _ ->
          Logger.warning("Unknown batch event type: #{inspect(event)}")
          {:error, :unknown_event_type}
      end
    end)

    {:ok, results}
  end
end