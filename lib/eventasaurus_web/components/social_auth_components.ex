defmodule EventasaurusWeb.SocialAuthComponents do
  @moduledoc """
  Social authentication components with anti-social theming.

  These components provide Facebook and Twitter authentication options
  with a playful "anti-social" UI theme that contrasts mainstream social
  platforms with our genuinely social event platform.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  import EventasaurusWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders social authentication buttons with anti-social theming.

  ## Examples

      <.social_auth_buttons />
      <.social_auth_buttons redirect_to="/events" />
      <.social_auth_buttons show_anti_social_copy={false} />

  """
  attr :redirect_to, :string, default: "/dashboard"
  attr :class, :string, default: ""
  attr :show_anti_social_copy, :boolean, default: true

  def social_auth_buttons(assigns) do
    ~H"""
    <div class={["social-auth-container", @class]}>
      <%= if @show_anti_social_copy do %>
        <div class="anti-social-intro mb-6">
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-gray-300/50"></div>
            </div>
            <div class="relative flex justify-center text-sm">
              <span class="bg-white/60 px-4 text-gray-500 backdrop-blur-sm">
                Or if you want to be anti-social...
              </span>
            </div>
          </div>

          <div class="flex items-center justify-center mt-3 mb-4">
            <.icon name="hero-arrow-down" class="w-4 h-4 text-gray-400 mr-2" />
            <span class="text-xs text-gray-500 italic">
              (We're the social ones, they're not)
            </span>
          </div>
        </div>
      <% end %>

      <div id="social-auth-buttons" class="social-buttons-grid space-y-3" phx-hook="SocialAuth">
        <.facebook_auth_button redirect_to={@redirect_to} />
        <.twitter_auth_button redirect_to={@redirect_to} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a Facebook authentication button.

  ## Examples

      <.facebook_auth_button />
      <.facebook_auth_button redirect_to="/events" />

  """
  attr :redirect_to, :string, default: "/dashboard"
  attr :class, :string, default: ""

  def facebook_auth_button(assigns) do
    ~H"""
    <button
      type="button"
      data-provider="facebook"
      data-redirect-to={@redirect_to}
      class={[
        "facebook-auth-btn group relative w-full flex justify-center items-center",
        "rounded-xl border border-transparent bg-blue-600 px-4 py-3",
        "text-sm font-semibold text-white shadow-lg",
        "hover:bg-blue-500 focus-visible:outline focus-visible:outline-2",
        "focus-visible:outline-offset-2 focus-visible:outline-blue-600",
        "transition-all duration-200 hover:shadow-xl hover:-translate-y-0.5",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0",
        @class
      ]}
      disabled={false}
    >
      <!-- Facebook Icon SVG -->
      <svg class="w-5 h-5 mr-3" viewBox="0 0 24 24" fill="currentColor">
        <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
      </svg>
      <span class="loading-text">Continue with Facebook</span>
      <span class="loading-spinner hidden ml-2">
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
      </span>
    </button>
    """
  end

  @doc """
  Renders a Twitter authentication button.

  ## Examples

      <.twitter_auth_button />
      <.twitter_auth_button redirect_to="/events" />

  """
  attr :redirect_to, :string, default: "/dashboard"
  attr :class, :string, default: ""

  def twitter_auth_button(assigns) do
    ~H"""
    <button
      type="button"
      data-provider="twitter"
      data-redirect-to={@redirect_to}
      class={[
        "twitter-auth-btn group relative w-full flex justify-center items-center",
        "rounded-xl border border-transparent bg-sky-500 px-4 py-3",
        "text-sm font-semibold text-white shadow-lg",
        "hover:bg-sky-400 focus-visible:outline focus-visible:outline-2",
        "focus-visible:outline-offset-2 focus-visible:outline-sky-500",
        "transition-all duration-200 hover:shadow-xl hover:-translate-y-0.5",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0",
        @class
      ]}
      disabled={false}
    >
      <!-- Twitter/X Icon SVG -->
      <svg class="w-5 h-5 mr-3" viewBox="0 0 24 24" fill="currentColor">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
      </svg>
      <span class="loading-text">Continue with Twitter</span>
      <span class="loading-spinner hidden ml-2">
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
      </span>
    </button>
    """
  end

  @doc """
  Renders a generic social provider authentication button.

  ## Examples

      <.social_provider_button provider="google" />
      <.social_provider_button provider="github" class="bg-gray-800" />

  """
  attr :provider, :string, required: true
  attr :redirect_to, :string, default: "/dashboard"
  attr :class, :string, default: ""
  attr :label, :string, default: nil

  def social_provider_button(assigns) do
    assigns = assign_new(assigns, :label, fn -> "Continue with #{String.capitalize(assigns.provider)}" end)

    ~H"""
    <button
      type="button"
      data-provider={@provider}
      data-redirect-to={@redirect_to}
      class={[
        "social-provider-btn group relative w-full flex justify-center items-center",
        "rounded-xl border border-gray-300 bg-white px-4 py-3",
        "text-sm font-semibold text-gray-700 shadow-lg",
        "hover:bg-gray-50 focus-visible:outline focus-visible:outline-2",
        "focus-visible:outline-offset-2 focus-visible:outline-gray-500",
        "transition-all duration-200 hover:shadow-xl hover:-translate-y-0.5",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0",
        @class
      ]}
      disabled={false}
    >
      <!-- Generic provider icon placeholder -->
      <div class="w-5 h-5 mr-3 bg-gray-400 rounded flex items-center justify-center text-white text-xs font-bold">
        <%= String.first(@provider) |> String.upcase() %>
      </div>
      <span class="loading-text"><%= @label %></span>
      <span class="loading-spinner hidden ml-2">
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
      </span>
    </button>
    """
  end

  @doc """
  Renders a compact horizontal layout for social auth buttons.

  ## Examples

      <.social_auth_buttons_compact />
      <.social_auth_buttons_compact show_anti_social_copy={false} />

  """
  attr :redirect_to, :string, default: "/dashboard"
  attr :class, :string, default: ""
  attr :show_anti_social_copy, :boolean, default: true

  def social_auth_buttons_compact(assigns) do
    ~H"""
    <div class={["social-auth-container-compact", @class]}>
      <%= if @show_anti_social_copy do %>
        <div class="anti-social-intro-compact text-center mb-4">
          <p class="text-gray-600 text-sm mb-1">
            Or be anti-social with:
          </p>
          <p class="text-xs text-gray-500 italic">
            (We're social, they're not 😉)
          </p>
        </div>
      <% end %>

      <div id="social-auth-buttons-compact" class="social-buttons-grid-compact grid grid-cols-2 gap-3" phx-hook="SocialAuth">
        <.facebook_auth_button redirect_to={@redirect_to} class="text-xs py-2" />
        <.twitter_auth_button redirect_to={@redirect_to} class="text-xs py-2" />
      </div>
    </div>
    """
  end

  @doc """
  Renders a social authentication error display with retry functionality.

  ## Examples

      <.social_auth_error error={@auth_error} retry_event="retry_social_auth" />
      <.social_auth_error error={@auth_error} retry_event="retry_social_auth" class="mt-4" />

  """
  attr :error, :map, required: true
  attr :retry_event, :string, default: "retry_social_auth"
  attr :class, :string, default: ""

  def social_auth_error(assigns) do
    ~H"""
    <div class={[
      "social-auth-error bg-red-50/80 backdrop-blur-sm border border-red-200/60",
      "rounded-xl shadow-lg p-4 mt-4 transition-all duration-300",
      @class
    ]}>
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-red-500" />
        </div>
        <div class="ml-3 flex-1">
          <h3 class="text-sm font-medium text-red-800">
            Authentication Failed
          </h3>
          <p class="mt-1 text-sm text-red-700">
            <%= get_error_message(@error) %>
          </p>
          <div class="mt-3 flex">
            <button
              phx-click={@retry_event}
              type="button"
              class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-lg text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 transition-colors duration-200"
            >
              <.icon name="hero-arrow-path" class="w-4 h-4 mr-2" />
              Try Again
            </button>
          </div>
        </div>
        <div class="ml-4 flex-shrink-0">
          <button
            phx-click="dismiss_auth_error"
            type="button"
            class="inline-flex text-red-400 hover:text-red-600 focus:outline-none focus:text-red-600 transition-colors duration-200"
          >
            <span class="sr-only">Dismiss</span>
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact social authentication error display.

  ## Examples

      <.social_auth_error_compact error={@auth_error} />

  """
  attr :error, :map, required: true
  attr :retry_event, :string, default: "retry_social_auth"
  attr :class, :string, default: ""

  def social_auth_error_compact(assigns) do
    ~H"""
    <div class={[
      "social-auth-error-compact bg-red-50 border-l-4 border-red-400 p-3 mt-3",
      "rounded-r-lg transition-all duration-300",
      @class
    ]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-red-500 mr-2" />
          <p class="text-sm text-red-700">
            <%= get_error_message(@error) %>
          </p>
        </div>
        <button
          phx-click={@retry_event}
          type="button"
          class="ml-3 text-xs bg-red-100 hover:bg-red-200 text-red-800 px-2 py-1 rounded transition-colors duration-200"
        >
          Retry
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders social authentication buttons with integrated error handling.

  ## Examples

      <.social_auth_buttons_with_error />
      <.social_auth_buttons_with_error auth_error={@auth_error} />

  """
  attr :redirect_to, :string, default: "/dashboard"
  attr :class, :string, default: ""
  attr :show_anti_social_copy, :boolean, default: true
  attr :auth_error, :map, default: nil
  attr :last_attempted_provider, :string, default: nil

  def social_auth_buttons_with_error(assigns) do
    ~H"""
    <div class={["social-auth-container-with-error", @class]}>
      <!-- Social Auth Buttons -->
      <.social_auth_buttons
        redirect_to={@redirect_to}
        show_anti_social_copy={@show_anti_social_copy}
      />

      <!-- Error Display -->
      <%= if @auth_error do %>
        <.social_auth_error
          error={@auth_error}
          retry_event={if @last_attempted_provider, do: "retry_#{@last_attempted_provider}_auth", else: "retry_social_auth"}
        />
      <% end %>
    </div>
    """
  end

  # Private helper function to generate user-friendly error messages
  defp get_error_message(%{"reason" => reason, "provider" => provider}) when is_binary(reason) do
    provider_name = String.capitalize(provider || "social")

    cond do
      reason =~ "popup_closed" or reason =~ "closed" ->
        "Looks like you closed the #{provider_name} window. Want to try again?"

      reason =~ "network" or reason =~ "timeout" ->
        "Network issue detected. Check your connection and try again."

      reason =~ "invalid_request" or reason =~ "invalid_grant" ->
        "There was an issue with the #{provider_name} authentication. Please try again."

      reason =~ "access_denied" or reason =~ "user_denied" ->
        "#{provider_name} authentication was cancelled. You can try again if you'd like."

      reason =~ "server_error" or reason =~ "temporarily_unavailable" ->
        "#{provider_name} is temporarily unavailable. Please try again in a moment."

      reason =~ "unsupported_response_type" or reason =~ "invalid_scope" ->
        "There's a configuration issue with #{provider_name} authentication. Please contact support."

      true ->
        "Something went wrong with #{provider_name} authentication. Please try again."
    end
  end

  defp get_error_message(%{"reason" => reason}) when is_binary(reason) do
    get_error_message(%{"reason" => reason, "provider" => "social"})
  end

  defp get_error_message(%{reason: reason, provider: provider}) do
    get_error_message(%{"reason" => to_string(reason), "provider" => to_string(provider)})
  end

  defp get_error_message(%{reason: reason}) do
    get_error_message(%{"reason" => to_string(reason), "provider" => "social"})
  end

  defp get_error_message(_error) do
    "Something went wrong with social authentication. Please try again."
  end
end
