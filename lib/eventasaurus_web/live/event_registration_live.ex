defmodule EventasaurusWeb.EventRegistrationComponent do
  @moduledoc """
  A LiveView component that handles event registration for anonymous users.

  This is now a wrapper around the UnifiedAuthModal for backward compatibility.

  ## Attributes:
  - event: Event struct (required)
  - show: Whether to show the modal
  - intended_status: :accepted | :interested (defaults to :accepted)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.EventRegistrationComponent}
        id="registration-modal"
        event={@event}
        show={@show_registration_modal}
        intended_status={:accepted}
      />
  """

  use EventasaurusWeb.UnifiedAuthModalWrapper

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={UnifiedAuthModal}
        id={"#{@id}-unified"}
        mode={:registration}
        event={@event}
        show={Map.get(assigns, :show, false)}
        intended_status={Map.get(assigns, :intended_status, :accepted)}
        on_close="close_registration_modal"
      />
    </div>
    """
  end
end
