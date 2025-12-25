defmodule EventasaurusWeb.Live.LanguageHooks do
  @moduledoc """
  LiveView hooks for language switching functionality.

  Provides shared language switching logic across all LiveViews that support
  multi-language content. This hook:

  1. Attaches a handler for the "change_language" event
  2. Updates the @language assign
  3. Pushes the "set_language_cookie" event to persist the preference
  4. Sends a `{:language_changed, language}` message to the LiveView

  ## Usage

  Add to your LiveView module:

      on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  Then use the language_switcher component in your template:

      <.language_switcher
        available_languages={@available_languages}
        current_language={@language}
      />

  ## Handling Language Changes

  The hook sends a `{:language_changed, language}` message after updating
  the language. Your LiveView can optionally implement a handler to perform
  additional actions (e.g., reload data):

      def handle_info({:language_changed, _language}, socket) do
        # Reload data with new language
        {:noreply, reload_events(socket)}
      end

  If you don't need to reload data, you can implement a no-op handler:

      def handle_info({:language_changed, _language}, socket) do
        {:noreply, socket}
      end

  Note: If your LiveView doesn't implement a handler, the message will be
  ignored by the default Phoenix LiveView behavior, but you may see warnings
  in development. It's recommended to always implement the handler.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, connected?: 1]

  @type mount_result :: {:cont | :halt, Phoenix.LiveView.Socket.t()}

  @doc """
  Attaches the language change event handler to the socket.

  This hook handles language switching by:
  - Updating the `:language` assign when a "change_language" event is received
  - Persisting the preference via the "set_language_cookie" JavaScript event
  - Notifying the LiveView via `{:language_changed, language}` message

  ## Example

      defmodule MyAppWeb.MyLive do
        use MyAppWeb, :live_view

        on_mount {MyAppWeb.Live.LanguageHooks, :attach_language_handler}

        def handle_info({:language_changed, _language}, socket) do
          # Optional: reload data for new language
          {:noreply, socket}
        end
      end
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) :: mount_result()
  def on_mount(:attach_language_handler, _params, _session, socket) do
    {:cont, attach_language_event_handler(socket)}
  end

  # Private helper that attaches the language change event handler
  defp attach_language_event_handler(socket) do
    attach_hook(socket, :language_handler, :handle_event, fn
      "change_language", %{"language" => language}, socket ->
        socket =
          socket
          |> assign(:language, language)
          |> push_event("set_language_cookie", %{language: language})

        # Notify the LiveView if it wants to handle the change
        if connected?(socket) do
          send(self(), {:language_changed, language})
        end

        {:halt, socket}

      _event, _params, socket ->
        {:cont, socket}
    end)
  end
end
