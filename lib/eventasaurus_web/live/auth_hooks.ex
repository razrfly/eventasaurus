defmodule EventasaurusWeb.Live.AuthHooks do
  @moduledoc """
  LiveView hooks for authentication and user session management.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias EventasaurusApp.Auth

  @doc """
  Hooks for LiveView authentication.

  Two hooks are provided:
  - `:assign_current_user`: Assigns the current user but doesn't enforce authentication
  - `:require_authenticated_user`: Requires authentication or redirects to login page

  Usage examples:
  ```
  on_mount {EventasaurusWeb.Live.AuthHooks, :assign_current_user}
  # or
  on_mount {EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}
  ```
  """
  def on_mount(:assign_current_user, _params, session, socket) do
    socket = assign_current_user(session, socket)
    {:cont, socket}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:assign_current_user_and_theme, params, session, socket) do
    socket = assign_current_user(session, socket)
    socket = assign_theme_from_event(params, socket)
    {:cont, socket}
  end

  # Internal function to assign the current user into the LiveView socket.
  defp assign_current_user(session, socket) do
    assign_new(socket, :current_user, fn ->
      case session do
        %{"access_token" => token} ->
          case Auth.Client.get_user(token) do
            {:ok, user} -> user
            _ -> nil
          end
        _ -> nil
      end
    end)
  end

  # Internal function to assign theme information from event slug
  defp assign_theme_from_event(%{"slug" => slug}, socket) do
    case EventasaurusApp.Events.get_event_by_slug(slug) do
      nil ->
        # No event found, use minimal theme (no styling)
        socket
        |> assign(:theme, :minimal)
        |> assign(:theme_class, nil)
        |> assign(:css_variables, nil)

      event ->
        # Get theme and customizations
        theme = try do
          case event.theme do
            theme when is_atom(theme) -> theme
            theme when is_binary(theme) -> String.to_existing_atom(theme)
            nil -> :minimal
          end
        rescue
          ArgumentError -> :minimal
        end

        theme_customizations = event.theme_customizations || %{}

        # For minimal theme, don't apply any theme class or CSS variables
        # This allows the Radiant layout to show through unchanged
        if theme == :minimal do
          socket
          |> assign(:theme, theme)
          |> assign(:theme_class, nil)
          |> assign(:css_variables, nil)
        else
          # Get CSS class for non-minimal themes
          theme_class = EventasaurusApp.Themes.get_theme_css_class(theme)

          # Generate CSS variables for customizations
          css_variables = generate_css_variables(theme, theme_customizations)

          socket
          |> assign(:theme, theme)
          |> assign(:theme_class, theme_class)
          |> assign(:css_variables, css_variables)
        end
    end
  end

  defp assign_theme_from_event(_, socket) do
    # No slug parameter, use minimal theme (no styling)
    socket
    |> assign(:theme, :minimal)
    |> assign(:theme_class, nil)
    |> assign(:css_variables, nil)
  end

  # Generate CSS custom properties from theme customizations
  defp generate_css_variables(theme, customizations) do
    # Validate customizations first to prevent injection
    case EventasaurusApp.Themes.validate_customizations(customizations || %{}) do
      {:ok, validated_customizations} ->
        # Merge default theme customizations with validated user customizations
        merged = EventasaurusApp.Themes.merge_customizations(theme, validated_customizations)

        # Use the sanitized function from ThemeHelpers
        EventasaurusWeb.ThemeHelpers.theme_css_variables(merged)

      {:error, _} ->
        # Fall back to default theme only if validation fails
        EventasaurusWeb.ThemeHelpers.theme_css_variables(%{})
    end
  end
end
