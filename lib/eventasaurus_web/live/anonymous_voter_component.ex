defmodule EventasaurusWeb.AnonymousVoterComponent do
  @moduledoc """
  A LiveView component that handles anonymous poll voting authentication.

  This is now a wrapper around the UnifiedAuthModal for backward compatibility.

  ## Attributes:
  - poll: Poll struct (required)
  - temp_votes: Temporary votes map (required)
  - poll_options: Poll options list (required)
  - show: Whether to show the modal
  - event: Event struct (optional, for date polls)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.AnonymousVoterComponent}
        id="voting-modal"
        poll={@poll}
        temp_votes={@temp_votes}
        poll_options={@poll_options}
        show={@show_voting_modal}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusWeb.UnifiedAuthModal

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event(event, params, socket) do
    # Forward all events to the unified modal
    send_update(UnifiedAuthModal, id: "#{socket.assigns.id}-unified", event: event, params: params)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={UnifiedAuthModal}
        id={"#{@id}-unified"}
        mode={:voting}
        poll={Map.get(assigns, :poll, nil)}
        event={Map.get(assigns, :event, nil)}
        temp_votes={Map.get(assigns, :temp_votes, %{})}
        poll_options={Map.get(assigns, :poll_options, [])}
        show={Map.get(assigns, :show, false)}
        on_close="close_vote_modal"
      />
    </div>
    """
  end
end
