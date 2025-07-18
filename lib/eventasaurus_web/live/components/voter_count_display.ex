defmodule EventasaurusWeb.VoterCountDisplay do
  @moduledoc """
  A standardized component for displaying voter counts across all poll types.
  
  This ensures consistent formatting and placement of voter count information
  throughout the polling system.
  
  ## Attributes:
  - poll_stats: Poll statistics containing total_unique_voters (required)
  - poll_phase: Current poll phase to determine visibility (required)
  - class: Additional CSS classes for styling (optional)
  - compact: Use compact display format (default: false)
  
  ## Usage:
      <.voter_count
        poll_stats={@poll_stats}
        poll_phase={@poll.phase}
        class="mt-1"
      />
  """
  
  use Phoenix.Component
  
  @doc """
  Displays the voter count in a standardized format.
  
  Only shows during voting phases when there are voters.
  """
  attr :poll_stats, :map, required: true
  attr :poll_phase, :string, required: true
  attr :class, :string, default: ""
  attr :compact, :boolean, default: false
  
  def voter_count(assigns) do
    ~H"""
    <%= if show_voter_count?(@poll_phase, @poll_stats) do %>
      <p class={["text-sm text-gray-600", @class]}>
        <%= format_voter_count(@poll_stats.total_unique_voters, @compact) %>
      </p>
    <% end %>
    """
  end
  
  @doc """
  Returns a span element with voter count for inline display.
  """
  attr :poll_stats, :map, required: true
  attr :poll_phase, :string, required: true
  attr :class, :string, default: ""
  
  def voter_count_inline(assigns) do
    ~H"""
    <%= if show_voter_count?(@poll_phase, @poll_stats) do %>
      <span class={["text-sm text-gray-600", @class]}>
        <%= format_voter_count(@poll_stats.total_unique_voters, true) %>
      </span>
    <% end %>
    """
  end
  
  # Private helpers
  
  defp show_voter_count?(phase, poll_stats) do
    phase in ["voting", "voting_with_suggestions", "voting_only", "closed"] and
    Map.get(poll_stats, :total_unique_voters, 0) > 0
  end
  
  defp format_voter_count(count, compact) when is_integer(count) do
    if compact do
      if count == 1, do: "(1 voter)", else: "(#{count} voters)"
    else
      if count == 1, do: "1 voter", else: "#{count} voters"
    end
  end
  
  defp format_voter_count(_, compact) do
    if compact, do: "(0 voters)", else: "0 voters"
  end
end