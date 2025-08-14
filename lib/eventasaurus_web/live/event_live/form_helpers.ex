defmodule EventasaurusWeb.EventLive.FormHelpers do
  @moduledoc """
  Helper functions for mapping intent-based form answers to event attributes.
  
  Translates user-friendly dropdown selections from the three-question flow
  into the appropriate database fields for event creation.
  """

  @doc """
  Maps date_certainty to event status.
  
  Maps the user's answer about date knowledge to appropriate event status:
  - "confirmed" → "confirmed" (user has specific date)
  - "polling" → "polling" (let attendees vote on date)  
  - "planning" → "draft" (still planning, date TBD)
  """
  def map_date_certainty_to_status(base_attrs \\ %{}, date_certainty)

  def map_date_certainty_to_status(base_attrs, "confirmed") do
    Map.put(base_attrs, "status", "confirmed")
  end

  def map_date_certainty_to_status(base_attrs, "polling") do
    base_attrs
    |> Map.put("status", "polling")
    # polling_deadline will be set by the specific polling fields
  end

  def map_date_certainty_to_status(base_attrs, "planning") do
    Map.put(base_attrs, "status", "draft")
  end

  def map_date_certainty_to_status(base_attrs, _) do
    # Default to confirmed for unknown values
    Map.put(base_attrs, "status", "confirmed")
  end

  @doc """
  Maps venue_certainty to appropriate venue-related fields.
  
  Maps the user's answer about venue knowledge to appropriate fields:
  - "confirmed" → Standard venue selection (current behavior)
  - "virtual" → Virtual event with is_virtual: true
  - "polling" → Creates venue/location poll  
  - "tbd" → Location to be determined
  """
  def map_venue_certainty_to_fields(base_attrs \\ %{}, venue_certainty)

  def map_venue_certainty_to_fields(base_attrs, "confirmed") do
    # Standard venue selection - no additional mapping needed
    # Venue fields will be handled by existing venue selection logic
    base_attrs
  end

  def map_venue_certainty_to_fields(base_attrs, "virtual") do
    base_attrs
    |> Map.put("is_virtual", true)
    # Clear any physical venue data
    |> Map.put("venue_id", nil)
  end

  def map_venue_certainty_to_fields(base_attrs, "polling") do
    # Create location poll - if not already polling for date, set status to polling
    current_status = Map.get(base_attrs, "status", "confirmed")
    if to_string(current_status) != "polling" do
      Map.put(base_attrs, "status", "polling")
    else
      base_attrs
    end
  end

  def map_venue_certainty_to_fields(base_attrs, "tbd") do
    # Location TBD - clear venue data but don't change status
    base_attrs
    |> Map.put("venue_id", nil)
    |> Map.put("is_virtual", false)
  end

  def map_venue_certainty_to_fields(base_attrs, _) do
    # Default to confirmed venue behavior
    base_attrs
  end

  @doc """
  Maps participation_type to relevant event fields.
  
  Maps the user's answer about participation method to appropriate fields:
  - "free" → is_ticketed: false, taxation_type: "ticketless" 
  - "ticketed" → is_ticketed: true, taxation_type: "ticketed_event"
  - "contribution" → is_ticketed: false, taxation_type: "contribution_collection"
  - "crowdfunding" → status: :threshold, is_ticketed: true, threshold_type: "revenue"
  - "interest" → status: :threshold, threshold_type: "attendee_count"
  """
  def map_participation_type_to_fields(base_attrs \\ %{}, participation_type)

  def map_participation_type_to_fields(base_attrs, "free") do
    base_attrs
    |> Map.put(:is_ticketed, false)
    |> Map.put(:taxation_type, "ticketless")
  end

  def map_participation_type_to_fields(base_attrs, "ticketed") do
    base_attrs
    |> Map.put(:is_ticketed, true)
    |> Map.put(:taxation_type, "ticketed_event")
  end

  def map_participation_type_to_fields(base_attrs, "contribution") do
    base_attrs
    |> Map.put(:is_ticketed, false)
    |> Map.put(:taxation_type, "contribution_collection")
  end

  def map_participation_type_to_fields(base_attrs, "crowdfunding") do
    base_attrs
    |> Map.put("status", "threshold")
    |> Map.put(:is_ticketed, true)
    |> Map.put(:taxation_type, "ticketed_event")
    |> Map.put(:threshold_type, "revenue")
    # threshold_revenue_cents will be set by specific crowdfunding fields
  end

  def map_participation_type_to_fields(base_attrs, "interest") do
    base_attrs
    |> Map.put("status", "threshold")
    |> Map.put(:threshold_type, "attendee_count")
    # threshold_count will be set by specific interest validation fields
  end

  def map_participation_type_to_fields(base_attrs, _) do
    # Default to free event behavior
    base_attrs
    |> Map.put(:is_ticketed, false)
    |> Map.put(:taxation_type, "ticketless")
  end

  @doc """
  Main function that resolves form parameters into event attributes.
  
  Takes form parameters and combines the individual mapping functions
  to produce a complete set of event attributes based on the three-question answers.
  
  Handles edge cases like multiple uncertainties and resolves conflicts.
  """
  def resolve_event_attributes(params) do
    base_attrs = %{}
    
    # Extract the three main answers
    date_certainty = Map.get(params, "date_certainty", "confirmed")
    venue_certainty = Map.get(params, "venue_certainty", "confirmed") 
    participation_type = Map.get(params, "participation_type", "free")
    
    # Apply mappings in sequence, each building on the previous
    attrs = base_attrs
    |> map_date_certainty_to_status(date_certainty)
    |> map_venue_certainty_to_fields(venue_certainty)
    |> map_participation_type_to_fields(participation_type)
    |> resolve_status_conflicts(date_certainty, venue_certainty, participation_type)
    |> set_defaults()
    
    # Convert all atom keys to strings to avoid mixed keys error in changeset
    attrs
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Private helper to resolve conflicts when multiple factors affect status
  defp resolve_status_conflicts(attrs, date_certainty, venue_certainty, _participation_type) do
    # Explicit priority resolution - highest priority status wins
    threshold_type = Map.get(attrs, :threshold_type)
    
    cond do
      threshold_type in ["revenue", "attendee_count"] -> 
        Map.put(attrs, "status", "threshold")
      date_certainty == "polling" or venue_certainty == "polling" ->
        Map.put(attrs, "status", "polling")  
      date_certainty == "planning" ->
        Map.put(attrs, "status", "draft")
      true ->
        Map.put(attrs, "status", "confirmed")
    end
  end

  # Private helper to set sensible defaults for missing fields
  defp set_defaults(attrs) do
    attrs
    |> Map.put_new("status", "confirmed")
    |> Map.put_new(:is_ticketed, false)
    |> Map.put_new(:taxation_type, "ticketless")
    |> Map.put_new("is_virtual", false)
  end
end