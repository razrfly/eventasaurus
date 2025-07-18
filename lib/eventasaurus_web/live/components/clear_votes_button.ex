defmodule EventasaurusWeb.ClearVotesButton do
  @moduledoc """
  A standardized component for clearing votes across all poll types.
  
  Provides consistent labeling, styling, and confirmation dialogs for
  the "Clear All Votes" functionality throughout the polling system.
  
  ## Attributes:
  - id: Unique identifier for the button (required)
  - target: Phoenix LiveView target for the click event (required)
  - has_votes: Boolean indicating if user has any votes (required)
  - loading: Whether a clear operation is in progress (default: false)
  - anonymous_mode: Whether in anonymous voting mode (default: false)
  - variant: Button style variant - "text" or "button" (default: "text")
  - class: Additional CSS classes (optional)
  
  ## Usage:
      <.clear_votes_button
        id="clear-votes-poll-123"
        target={@myself}
        has_votes={has_votes?(@vote_state)}
        loading={@loading}
        anonymous_mode={@anonymous_mode}
      />
  """
  
  use Phoenix.Component
  
  @doc """
  Renders a standardized clear votes button with confirmation dialog.
  """
  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :has_votes, :boolean, required: true
  attr :loading, :boolean, default: false
  attr :anonymous_mode, :boolean, default: false
  attr :variant, :string, default: "text", values: ["text", "button"]
  attr :class, :string, default: ""
  
  def clear_votes_button(assigns) do
    ~H"""
    <%= if @has_votes and not @loading do %>
      <button
        id={@id}
        type="button"
        phx-click="clear_all_votes"
        phx-target={@target}
        data-confirm={confirmation_message(@anonymous_mode)}
        class={button_classes(@variant, @class)}
        disabled={@loading}
      >
        <%= if @variant == "button" do %>
          <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        <% end %>
        <%= button_label(@anonymous_mode) %>
      </button>
    <% end %>
    """
  end
  
  @doc """
  Renders an inline clear votes link for compact displays.
  """
  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :has_votes, :boolean, required: true
  attr :loading, :boolean, default: false
  attr :anonymous_mode, :boolean, default: false
  attr :class, :string, default: ""
  
  def clear_votes_link(assigns) do
    ~H"""
    <%= if @has_votes and not @loading do %>
      <a
        id={@id}
        href="#"
        phx-click="clear_all_votes"
        phx-target={@target}
        data-confirm={confirmation_message(@anonymous_mode)}
        class={["text-sm hover:underline", @class]}
      >
        <%= button_label(@anonymous_mode) %>
      </a>
    <% end %>
    """
  end
  
  # Private helpers
  
  defp button_classes("text", custom_class) do
    [
      "text-sm text-red-600 hover:text-red-900 font-medium transition-colors",
      custom_class
    ]
  end
  
  defp button_classes("button", custom_class) do
    [
      "inline-flex items-center px-3 py-2 border border-gray-300",
      "text-sm leading-4 font-medium rounded-md text-gray-700",
      "bg-white hover:bg-gray-50 focus:outline-none",
      "focus:ring-2 focus:ring-offset-2 focus:ring-red-500",
      "transition-colors",
      custom_class
    ]
  end
  
  defp button_label(true = _anonymous_mode), do: "Clear Temporary Votes"
  defp button_label(false = _anonymous_mode), do: "Clear All Votes"
  
  defp confirmation_message(true = _anonymous_mode) do
    "Are you sure you want to clear all your temporary votes? This action cannot be undone."
  end
  
  defp confirmation_message(false = _anonymous_mode) do
    "Are you sure you want to clear all your votes? This action cannot be undone."
  end
end