defmodule EventasaurusWeb.Helpers.EventStatusHelpers do
  @moduledoc """
  Helper functions for generating user-friendly event status messages and contextual information.
  
  Converts technical event status values into meaningful, user-friendly messages
  and provides contextual information based on event data.
  """

  @doc """
  Returns a user-friendly status message for an event.
  
  ## Parameters
  - `event` - The event struct with status and related data
  - `format` - The display format (:badge, :compact, :detailed)
  
  ## Examples
  
      iex> event = %{status: :confirmed, is_ticketed: true}
      iex> friendly_status_message(event, :badge)
      "Open for Registration"
      
      iex> event = %{status: :polling}
      iex> friendly_status_message(event, :compact)
      "Collecting Votes"
  """
  def friendly_status_message(event, format \\ :compact)

  def friendly_status_message(%{status: :confirmed} = event, format) do
    cond do
      is_ticketed_event?(event) && format == :badge -> "Open for Registration"
      is_ticketed_event?(event) && format == :compact -> "Registration Open"
      is_ticketed_event?(event) && format == :detailed -> "Event confirmed and open for registration"
      format == :badge -> "Ready to Go"
      format == :compact -> "Event Ready"
      format == :detailed -> "Event confirmed and ready to attend"
      true -> "Ready to Go"
    end
  end

  def friendly_status_message(%{status: :polling} = event, format) do
    cond do
      has_date_polling?(event) && has_venue_polling?(event) && format == :detailed -> 
        "Collecting votes on date and location"
      has_date_polling?(event) && format == :detailed -> 
        "Collecting votes on event date"
      has_venue_polling?(event) && format == :detailed -> 
        "Collecting votes on event location"
      format == :badge -> "Getting Feedback"
      format == :compact -> "Collecting Votes"
      format == :detailed -> "Collecting feedback from attendees"
      true -> "Collecting Votes"
    end
  end

  def friendly_status_message(%{status: :threshold} = event, format) do
    cond do
      is_crowdfunding?(event) && format == :badge -> "Crowdfunding Active"
      is_crowdfunding?(event) && format == :compact -> "Funding in Progress"
      is_crowdfunding?(event) && format == :detailed -> "Crowdfunding campaign in progress"
      is_interest_validation?(event) && format == :badge -> "Validating Interest"
      is_interest_validation?(event) && format == :compact -> "Checking Interest"
      is_interest_validation?(event) && format == :detailed -> "Collecting interest from potential attendees"
      format == :badge -> "Building Momentum"
      format == :compact -> "Pre-Launch"
      format == :detailed -> "Building momentum before launch"
      true -> "Building Momentum"
    end
  end

  def friendly_status_message(%{status: :draft}, format) do
    cond do
      format == :badge -> "In Planning"
      format == :compact -> "Planning Stage"
      format == :detailed -> "Event is still being planned"
      true -> "Planning Stage"
    end
  end

  def friendly_status_message(%{status: :canceled}, format) do
    cond do
      format == :badge -> "Canceled"
      format == :compact -> "Event Canceled"
      format == :detailed -> "This event has been canceled"
      true -> "Canceled"
    end
  end

  def friendly_status_message(_event, _format), do: "Status Unknown"

  @doc """
  Returns contextual information about the event based on its current state.
  
  ## Examples
  
      iex> event = %{status: :threshold, threshold_count: 50, participant_count: 35}
      iex> contextual_info(event)
      "Waiting for 15 more people to sign up"
      
      iex> event = %{status: :polling, polling_deadline: ~U[2024-12-01 18:00:00Z]}
      iex> contextual_info(event)
      "Polling closes in 3 days"
  """
  def contextual_info(event, options \\ [])

  def contextual_info(%{status: :threshold} = event, _options) do
    cond do
      is_crowdfunding?(event) -> crowdfunding_progress(event)
      is_interest_validation?(event) -> interest_progress(event)
      true -> threshold_progress(event)
    end
  end

  def contextual_info(%{status: :polling} = event, _options) do
    cond do
      Map.get(event, :polling_deadline) -> polling_deadline_info(Map.get(event, :polling_deadline))
      true -> "Polling in progress"
    end
  end

  def contextual_info(%{status: :confirmed} = event, _options) do
    cond do
      is_ticketed_event?(event) && has_available_tickets?(event) -> 
        "#{available_tickets_count(event)} tickets remaining"
      is_ticketed_event?(event) -> 
        "Registration required"
      Map.get(event, :participant_count) && Map.get(event, :participant_count) > 0 -> 
        count = Map.get(event, :participant_count)
        "#{count} #{pluralize("people", count, "person")} attending"
      true -> nil
    end
  end

  def contextual_info(%{status: :draft}, _options) do
    "Details being finalized"
  end

  def contextual_info(%{status: :canceled}, _options) do
    "Event will not take place"
  end

  def contextual_info(_event, _options), do: nil

  @doc """
  Returns a complete status display combining friendly message and contextual info.
  
  ## Examples
  
      iex> event = %{status: :threshold, threshold_count: 50, participant_count: 35}
      iex> complete_status_display(event, :compact)
      %{primary: "Validating Interest", secondary: "Waiting for 15 more people to sign up"}
  """
  def complete_status_display(event, format \\ :compact) do
    primary = friendly_status_message(event, format)
    secondary = contextual_info(event)
    
    %{
      primary: primary,
      secondary: secondary,
      has_context: not is_nil(secondary),
      css_class: status_css_class(event),
      icon: status_icon(event)
    }
  end

  @doc """
  Returns appropriate CSS classes for styling status displays.
  """
  def status_css_class(%{status: :confirmed}), do: "bg-green-100 text-green-800"
  def status_css_class(%{status: :polling}), do: "bg-blue-100 text-blue-800"
  def status_css_class(%{status: :threshold} = event) do
    if is_crowdfunding?(event) do
      "bg-purple-100 text-purple-800"
    else
      "bg-yellow-100 text-yellow-800"
    end
  end
  def status_css_class(%{status: :draft}), do: "bg-gray-100 text-gray-800"
  def status_css_class(%{status: :canceled}), do: "bg-red-100 text-red-800"
  def status_css_class(_), do: "bg-gray-100 text-gray-800"

  @doc """
  Returns appropriate icons for different status types.
  """
  def status_icon(%{status: :confirmed}), do: "✓"
  def status_icon(%{status: :polling}), do: "📊"
  def status_icon(%{status: :threshold} = event) do
    if is_crowdfunding?(event), do: "💰", else: "🎯"
  end
  def status_icon(%{status: :draft}), do: "📝"
  def status_icon(%{status: :canceled}), do: "❌"
  def status_icon(_), do: "❓"

  # Private helper functions

  defp is_ticketed_event?(event) do
    # Check if event is ticketed based on taxation_type or is_ticketed field
    # Handle both atom and string keys for compatibility
    is_ticketed = Map.get(event, :is_ticketed) || Map.get(event, "is_ticketed") || false
    taxation_type = Map.get(event, :taxation_type) || Map.get(event, "taxation_type")
    
    is_ticketed == true || taxation_type == "ticketed_event"
  end

  defp is_crowdfunding?(event) do
    threshold_type = Map.get(event, :threshold_type) || Map.get(event, "threshold_type")
    threshold_type == "revenue" && is_ticketed_event?(event)
  end

  defp is_interest_validation?(event) do
    threshold_type = Map.get(event, :threshold_type) || Map.get(event, "threshold_type")
    threshold_type == "attendee_count"
  end

  defp has_date_polling?(_event) do
    # This would need to be determined based on polling data
    # For now, assume false unless specifically indicated
    false
  end

  defp has_venue_polling?(_event) do
    # This would need to be determined based on polling data
    # For now, assume false unless specifically indicated
    false
  end

  defp crowdfunding_progress(event) do
    cond do
      Map.get(event, :threshold_revenue_cents) && Map.get(event, :current_revenue_cents) ->
        goal_cents = Map.get(event, :threshold_revenue_cents)
        current_cents = Map.get(event, :current_revenue_cents)
        goal = format_currency(goal_cents)
        current = format_currency(current_cents)
        remaining = goal_cents - current_cents
        
        if remaining > 0 do
          remaining_formatted = format_currency(remaining)
          "Raised #{current} of #{goal} goal (#{remaining_formatted} to go)"
        else
          "Goal reached! Raised #{current} of #{goal}"
        end
      
      Map.get(event, :threshold_revenue_cents) ->
        goal = format_currency(Map.get(event, :threshold_revenue_cents))
        "Funding goal: #{goal}"
      
      true ->
        "Crowdfunding in progress"
    end
  end

  defp interest_progress(event) do
    threshold_count = Map.get(event, :threshold_count)
    participant_count = Map.get(event, :participant_count)
    
    cond do
      threshold_count && participant_count ->
        remaining = threshold_count - participant_count
        
        if remaining > 0 do
          "Waiting for #{remaining} more #{pluralize("people", remaining, "person")} to sign up"
        else
          "Interest goal reached! #{participant_count} #{pluralize("people", participant_count, "person")} signed up"
        end
      
      threshold_count ->
        "Need #{threshold_count} #{pluralize("people", threshold_count, "person")} to confirm"
      
      participant_count && participant_count > 0 ->
        "#{participant_count} #{pluralize("people", participant_count, "person")} interested so far"
      
      true ->
        "Collecting interest from potential attendees"
    end
  end

  defp threshold_progress(event) do
    cond do
      Map.get(event, :threshold_count) && Map.get(event, :participant_count) ->
        remaining = Map.get(event, :threshold_count) - Map.get(event, :participant_count)
        
        if remaining > 0 do
          "Need #{remaining} more #{pluralize("person", remaining)}"
        else
          "Threshold reached!"
        end
      
      true ->
        "Building momentum"
    end
  end

  defp polling_deadline_info(deadline) when is_binary(deadline) do
    case DateTime.from_iso8601(deadline) do
      {:ok, datetime, _} -> polling_deadline_info(datetime)
      _ -> "Polling deadline soon"
    end
  end

  defp polling_deadline_info(%DateTime{} = deadline) do
    now = DateTime.utc_now()
    diff = DateTime.diff(deadline, now, :second)
    
    cond do
      diff <= 0 ->
        "Polling has ended"
      
      diff < 3600 ->
        minutes = div(diff, 60)
        "Polling closes in #{minutes} #{pluralize("minute", minutes)}"
      
      diff < 86400 ->
        hours = div(diff, 3600)
        "Polling closes in #{hours} #{pluralize("hour", hours)}"
      
      true ->
        days = div(diff, 86400)
        "Polling closes in #{days} #{pluralize("day", days)}"
    end
  end

  defp polling_deadline_info(_), do: "Polling in progress"

  defp has_available_tickets?(event) do
    Map.get(event, :available_tickets, 0) > 0
  end

  defp available_tickets_count(event) do
    Map.get(event, :available_tickets, 0)
  end

  defp format_currency(amount_cents) when is_integer(amount_cents) and amount_cents >= 0 do
    dollars = div(amount_cents, 100)
    "$#{dollars}"
  end

  defp format_currency(amount_cents) when is_integer(amount_cents) and amount_cents < 0 do
    dollars = div(-amount_cents, 100)
    "-$#{dollars}"
  end

  defp format_currency(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {cents, ""} -> format_currency(cents)
      _ -> "$0"
    end
  end

  defp format_currency(_), do: "$0"

  defp pluralize("people", 1, singular), do: singular
  defp pluralize("people", _, _), do: "people"
  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"
end