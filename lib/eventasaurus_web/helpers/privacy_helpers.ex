defmodule EventasaurusWeb.Helpers.PrivacyHelpers do
  @moduledoc """
  Helper functions for handling privacy settings and social proof display.
  """

  @doc """
  Filters contributor data based on privacy settings.
  
  Returns the appropriate display name based on privacy settings and preferences.
  """
  def filter_contributor_name(order, event_privacy_settings) do
    # Check if contributor has their own privacy preference
    privacy_preference = Map.get(order, :privacy_preference, "default")
    
    # Check event default settings
    name_visibility = Map.get(event_privacy_settings, "contributor_name_visibility", "full")
    
    # If contributor chose anonymous, always respect that
    if privacy_preference == "anonymous" or order.is_anonymous do
      "Anonymous"
    else
      case name_visibility do
        "organizer_only" -> "Anonymous"
        "anonymous" -> "Anonymous"
        "first_name" -> get_first_name(order.user)
        "full" -> get_full_name(order.user)
        _ -> get_full_name(order.user)
      end
    end
  end

  @doc """
  Filters contribution amount based on privacy settings.
  
  Returns the amount or nil based on visibility settings.
  """
  def filter_contribution_amount(order, event_privacy_settings, is_organizer \\ false) do
    amount_visibility = Map.get(event_privacy_settings, "amount_visibility", "visible")
    
    case amount_visibility do
      "hidden" -> nil
      "organizer_only" -> if is_organizer, do: order.contribution_amount_cents || order.total_cents, else: nil
      "visible" -> order.contribution_amount_cents || order.total_cents
      _ -> order.contribution_amount_cents || order.total_cents
    end
  end

  @doc """
  Formats the total raised based on privacy settings.
  
  Returns a formatted string based on visibility settings.
  """
  def format_total_raised(total_cents, goal_cents, event_privacy_settings, currency \\ "usd") do
    total_visibility = Map.get(event_privacy_settings, "total_visibility", "exact")
    
    case total_visibility do
      "hidden" -> 
        nil
        
      "exact" -> 
        EventasaurusWeb.Helpers.CurrencyHelpers.format_currency(total_cents, currency)
        
      "percentage" when not is_nil(goal_cents) and goal_cents > 0 -> 
        percentage = round(total_cents / goal_cents * 100)
        "#{percentage}% of goal"
        
      "milestones" -> 
        format_milestone(total_cents, currency)
        
      _ -> 
        EventasaurusWeb.Helpers.CurrencyHelpers.format_currency(total_cents, currency)
    end
  end

  @doc """
  Determines if recent contributions should be shown.
  """
  def show_recent_contributions?(event_privacy_settings) do
    Map.get(event_privacy_settings, "recent_contributions_enabled", true) == true
  end

  @doc """
  Determines if contributors can override privacy settings.
  """
  def allow_contributor_override?(event_privacy_settings) do
    Map.get(event_privacy_settings, "allow_contributor_override", true) == true
  end

  @doc """
  Gets recent contributions filtered by privacy settings.
  
  Returns a list of filtered contribution data suitable for public display.
  """
  def get_filtered_recent_contributions(orders, event_privacy_settings, limit \\ 10) do
    if show_recent_contributions?(event_privacy_settings) do
      orders
      |> Enum.filter(&(&1.status == "confirmed"))
      |> Enum.sort_by(&(&1.confirmed_at), {:desc, DateTime})
      |> Enum.take(limit)
      |> Enum.map(fn order ->
        %{
          name: filter_contributor_name(order, event_privacy_settings),
          amount: filter_contribution_amount(order, event_privacy_settings),
          timestamp: order.confirmed_at,
          message: Map.get(order, :contribution_message)
        }
      end)
    else
      []
    end
  end

  # Private helper functions
  
  defp get_full_name(nil), do: "Anonymous"
  defp get_full_name(user) do
    user.name || "Anonymous"
  end
  
  defp get_first_name(nil), do: "Anonymous"
  defp get_first_name(user) do
    case user.name do
      nil -> "Anonymous"
      name ->
        name
        |> String.split(" ")
        |> List.first()
        |> Kernel.||("Anonymous")
    end
  end
  
  defp format_milestone(amount_cents, _currency) do
    amount = amount_cents / 100
    
    cond do
      amount < 100 -> "Getting started"
      amount < 500 -> "Over $100"
      amount < 1000 -> "Over $500"
      amount < 5000 -> "Over $1,000"
      amount < 10000 -> "Over $5,000"
      amount < 25000 -> "Over $10,000"
      amount < 50000 -> "Over $25,000"
      amount < 100000 -> "Over $50,000"
      true -> "Over $100,000"
    end
  end
end