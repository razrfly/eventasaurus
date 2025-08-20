defmodule EventasaurusWeb.UnifiedAuthModalWrapper do
  @moduledoc """
  Shared behavior for components that wrap UnifiedAuthModal.
  Provides common mount, update, and handle_event implementations.
  """
  
  defmacro __using__(_opts) do
    quote do
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
        send_update(UnifiedAuthModal, 
          id: "#{socket.assigns.id}-unified", 
          event: event, 
          params: params
        )
        {:noreply, socket}
      end

      # Make these overridable in case a wrapper needs custom behavior
      defoverridable [mount: 1, update: 2, handle_event: 3]
    end
  end
end