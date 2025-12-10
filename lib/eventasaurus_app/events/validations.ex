defmodule EventasaurusApp.Events.Validations do
  @moduledoc """
  Centralized validation module for Event changesets.

  This module provides context-specific validation functions that can be applied
  based on the current stage of event creation/editing. It works alongside
  the base `Event.changeset/2` which handles field casting and basic validations.

  ## Validation Contexts

  - `validate_for_draft/1` - Minimal validations for saving drafts (skip start_at requirements)
  - `validate_for_publish/1` - Full validations required to publish an event
  - `validate_for_threshold/1` - Additional validations for threshold/crowdfunding events

  ## Conditional Validations

  The module also provides individual validation functions that enforce requirements
  based on the values of date_certainty, venue_certainty, and participation_type:

  - `validate_date_certainty_requirements/1`
  - `validate_venue_certainty_requirements/1`
  - `validate_participation_requirements/1`

  ## Usage

      # For draft saves (minimal validation)
      changeset
      |> Validations.validate_for_draft()

      # For publishing (full validation)
      changeset
      |> Event.changeset(params)
      |> Validations.validate_for_publish()

      # For individual conditional validations
      changeset
      |> Event.changeset(params)
      |> Validations.validate_date_certainty_requirements()

  ## Design Philosophy

  This module complements the base Event.changeset/2 by adding context-specific
  validations. The base changeset handles:
  - Field casting
  - Basic field validations (length, format, inclusion)
  - Status-based validations via maybe_validate_start_at/1

  This module adds:
  - Conditional validations based on date_certainty, venue_certainty, participation_type
  - Context-aware validation bundles (draft vs publish vs threshold)
  """

  import Ecto.Changeset
  alias EventasaurusApp.Events.Event

  # Re-export valid value lists from Event schema for convenience
  defdelegate valid_date_certainties, to: Event
  defdelegate valid_venue_certainties, to: Event
  defdelegate valid_participation_types, to: Event

  @doc """
  Minimal validations for draft events.

  Only validates title so users can save work-in-progress events.
  Explicitly does NOT require start_at, venue, or other publish-time fields.

  Note: This should be used with a minimal changeset, not the full Event.changeset
  which already has some required validations built in.

  ## Examples

      iex> changeset = Ecto.Changeset.cast(%Event{}, %{title: "My Event"}, [:title, :timezone])
      iex> Validations.validate_for_draft(changeset)
      #=> valid changeset
  """
  @spec validate_for_draft(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_for_draft(changeset) do
    changeset
    |> validate_required([:title], message: "is required to save a draft")
    |> validate_length(:title, min: 3, max: 100)
  end

  @doc """
  Full validations for publishing an event.

  Applies conditional validations based on the event's configuration:
  - Date-specific validations based on date_certainty
  - Venue-specific validations based on venue_certainty
  - Participation-specific validations based on participation_type

  Note: Base requirements (title, timezone, visibility) are already validated
  by Event.changeset/2, so this function focuses on the conditional validations.

  ## Examples

      iex> changeset = Event.changeset(%Event{}, %{
      ...>   title: "My Event",
      ...>   timezone: "UTC",
      ...>   date_certainty: "confirmed",
      ...>   start_at: ~U[2025-01-01 10:00:00Z]
      ...> })
      iex> Validations.validate_for_publish(changeset)
      #=> validates based on date_certainty, venue_certainty, participation_type
  """
  @spec validate_for_publish(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_for_publish(changeset) do
    changeset
    |> validate_date_certainty_requirements()
    |> validate_venue_certainty_requirements()
    |> validate_participation_requirements()
  end

  @doc """
  Validations for threshold/crowdfunding events.

  Applies publish validations plus additional requirements for
  events that need to meet a threshold before being confirmed.

  ## Examples

      iex> changeset = Event.changeset(%Event{}, %{
      ...>   title: "My Crowdfunded Event",
      ...>   participation_type: "crowdfunding",
      ...>   threshold_type: "revenue",
      ...>   threshold_revenue_cents: 100000
      ...> })
      iex> Validations.validate_for_threshold(changeset)
      #=> validates threshold fields are present and valid
  """
  @spec validate_for_threshold(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_for_threshold(changeset) do
    changeset
    |> validate_for_publish()
    |> validate_required([:threshold_type])
    |> validate_threshold_fields()
  end

  # ===========================================================================
  # Date Certainty Validations
  # ===========================================================================

  @doc """
  Validates fields required based on date_certainty selection.

  - "confirmed" -> requires start_at
  - "polling" -> requires polling_deadline
  - "planning" -> no date requirements (TBD)
  """
  @spec validate_date_certainty_requirements(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_date_certainty_requirements(changeset) do
    case get_field(changeset, :date_certainty) do
      "confirmed" ->
        changeset
        |> validate_required([:start_at], message: "is required when date is confirmed")
        |> validate_start_at_future()

      "polling" ->
        changeset
        |> validate_required([:polling_deadline], message: "is required for date polling")
        |> validate_polling_deadline_future()

      "planning" ->
        # No date requirements for planning/TBD events
        changeset

      nil ->
        # Default to confirmed behavior if not set
        changeset
        |> validate_required([:start_at], message: "is required when date is confirmed")

      _other ->
        # Invalid date_certainty value - the schema validation will catch this
        changeset
    end
  end

  # ===========================================================================
  # Venue Certainty Validations
  # ===========================================================================

  @doc """
  Validates fields required based on venue_certainty selection.

  - "confirmed" -> requires venue information
  - "virtual" -> requires virtual_venue_url
  - "polling" -> no venue requirements (attendees will vote)
  - "tbd" -> no venue requirements
  """
  @spec validate_venue_certainty_requirements(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_venue_certainty_requirements(changeset) do
    case get_field(changeset, :venue_certainty) do
      "confirmed" ->
        # Venue should be set - check either venue_id or we could add a custom validation
        # For now, we don't require venue_id as some events may not have a formal venue
        changeset

      "virtual" ->
        changeset
        |> validate_required([:virtual_venue_url], message: "is required for virtual events")
        |> validate_virtual_venue_url_format()

      "polling" ->
        # No venue requirements when polling
        changeset

      "tbd" ->
        # No venue requirements for TBD
        changeset

      nil ->
        # Default behavior - no strict requirement
        changeset

      _other ->
        # Invalid venue_certainty value - schema validation will catch this
        changeset
    end
  end

  # ===========================================================================
  # Participation Type Validations
  # ===========================================================================

  @doc """
  Validates fields required based on participation_type selection.

  - "free" -> no additional requirements
  - "ticketed" -> validates ticketing setup
  - "contribution" -> validates contribution setup
  - "crowdfunding" -> validates funding goal
  - "interest" -> validates threshold for interest gauge
  """
  @spec validate_participation_requirements(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_participation_requirements(changeset) do
    case get_field(changeset, :participation_type) do
      "free" ->
        changeset

      "ticketed" ->
        changeset
        |> validate_ticketed_event()

      "contribution" ->
        # Optional contributions don't require specific validation
        changeset

      "crowdfunding" ->
        changeset
        |> validate_crowdfunding_event()

      "interest" ->
        changeset
        |> validate_interest_event()

      nil ->
        # Default to free behavior
        changeset

      _other ->
        # Invalid participation_type - schema validation will catch this
        changeset
    end
  end

  # ===========================================================================
  # Threshold Validations
  # ===========================================================================

  defp validate_threshold_fields(changeset) do
    threshold_type = get_field(changeset, :threshold_type)

    case threshold_type do
      "attendee_count" ->
        changeset
        |> validate_required([:threshold_count], message: "is required for attendee threshold")
        |> validate_number(:threshold_count, greater_than: 0)

      "revenue" ->
        changeset
        |> validate_required([:threshold_revenue_cents],
          message: "is required for revenue threshold"
        )
        |> validate_number(:threshold_revenue_cents, greater_than: 0)

      "both" ->
        changeset
        |> validate_required([:threshold_count, :threshold_revenue_cents],
          message: "is required for combined threshold"
        )
        |> validate_number(:threshold_count, greater_than: 0)
        |> validate_number(:threshold_revenue_cents, greater_than: 0)

      _ ->
        changeset
    end
  end

  # ===========================================================================
  # Helper Validations
  # ===========================================================================

  defp validate_start_at_future(changeset) do
    validate_change(changeset, :start_at, fn :start_at, start_at ->
      if DateTime.compare(start_at, DateTime.utc_now()) == :gt do
        []
      else
        [start_at: "must be in the future"]
      end
    end)
  end

  defp validate_polling_deadline_future(changeset) do
    validate_change(changeset, :polling_deadline, fn :polling_deadline, deadline ->
      if DateTime.compare(deadline, DateTime.utc_now()) == :gt do
        []
      else
        [polling_deadline: "must be in the future"]
      end
    end)
  end

  defp validate_virtual_venue_url_format(changeset) do
    validate_change(changeset, :virtual_venue_url, fn :virtual_venue_url, url ->
      if valid_url?(url) do
        []
      else
        [virtual_venue_url: "must be a valid URL"]
      end
    end)
  end

  defp valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_), do: false

  defp validate_ticketed_event(changeset) do
    # Ticketed events should have taxation_type set appropriately
    changeset
    |> validate_inclusion(:taxation_type, ["ticketed_event", "contribution_collection"],
      message: "must be set for ticketed events"
    )
  end

  defp validate_crowdfunding_event(changeset) do
    # Crowdfunding events need a funding goal (threshold)
    changeset
    |> validate_required([:threshold_revenue_cents], message: "funding goal is required")
    |> validate_number(:threshold_revenue_cents, greater_than: 0)
  end

  defp validate_interest_event(changeset) do
    # Interest-gauge events need an attendee threshold
    changeset
    |> validate_required([:threshold_count], message: "minimum interest count is required")
    |> validate_number(:threshold_count, greater_than: 0)
  end
end
