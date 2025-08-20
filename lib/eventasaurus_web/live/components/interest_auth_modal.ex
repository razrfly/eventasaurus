defmodule EventasaurusWeb.InterestAuthModal do
  @moduledoc """
  A LiveView component that handles authentication flow for anonymous users expressing interest.

  This is now a wrapper around the UnifiedAuthModal for backward compatibility.

  ## Attributes:
  - event: Event struct (required)
  - show: Whether to show the modal
  - on_close: Event to close modal
  - class: Additional CSS classes

  ## Usage:
      <.live_component
        module={EventasaurusWeb.InterestAuthModal}
        id="interest-auth-modal"
        event={@event}
        show={@show_interest_modal}
        on_close="close_interest_modal"
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
        mode={:interest}
        event={@event}
        show={@show}
        on_close={@on_close}
        class={Map.get(assigns, :class, "")}
      />
    </div>
    """
  end
end
