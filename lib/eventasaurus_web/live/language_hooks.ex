defmodule EventasaurusWeb.Live.LanguageHooks do
  @moduledoc """
  LiveView hooks for language switching functionality.

  Provides shared language switching logic across all LiveViews that support
  multi-language content. This hook:

  1. Attaches a handler for the "change_language" event
  2. Updates the @language assign
  3. Pushes the "set_language_cookie" event to persist the preference

  ## Usage

  Add to your LiveView module:

      on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  Then use the language_switcher component in your template:

      <.language_switcher
        available_languages={@available_languages}
        current_language={@language}
      />

  ## Custom Behavior

  If your LiveView needs to perform additional actions after language changes
  (e.g., reload data), implement a callback in your LiveView:

      def handle_info({:language_changed, language}, socket) do
        # Reload data with new language
        {:noreply, reload_events(socket)}
      end

  The hook will send this message after updating the language.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, connected?: 1]

  @doc """
  Attaches the language change event handler to the socket.

  This is the default hook that handles language switching for most pages.
  It updates the language assign and persists the cookie.
  """
  def on_mount(:attach_language_handler, _params, _session, socket) do
    socket =
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

    {:cont, socket}
  end

  # Attaches the language handler with data reload capability.
  # Use this variant when the LiveView needs to reload data after language changes.
  # It sets a loading flag and sends a message to trigger the reload.
  #
  # Example:
  #     on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler_with_reload}
  #
  #     def handle_info({:language_changed, _language}, socket) do
  #       send(self(), :load_filtered_events)
  #       {:noreply, assign(socket, :events_loading, true)}
  #     end
  def on_mount(:attach_language_handler_with_reload, _params, _session, socket) do
    socket =
      attach_hook(socket, :language_handler, :handle_event, fn
        "change_language", %{"language" => language}, socket ->
          socket =
            socket
            |> assign(:language, language)
            |> push_event("set_language_cookie", %{language: language})

          # Notify the LiveView to reload data
          if connected?(socket) do
            send(self(), {:language_changed, language})
          end

          {:halt, socket}

        _event, _params, socket ->
          {:cont, socket}
      end)

    {:cont, socket}
  end
end
