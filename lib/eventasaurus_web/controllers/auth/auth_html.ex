defmodule EventasaurusWeb.Auth.AuthHTML do
  use EventasaurusWeb, :html

  # Note: Template files were removed as they're replaced by function components below

  # Define the required flash attribute for the flash_messages function
  attr :flash, :map, required: true

  def flash_messages(assigns) do
    ~H"""
    <%= if info = @flash["info"] do %>
      <div class="alert alert-info" role="alert" phx-click="lv:clear-flash" phx-value-key="info">
        <%= info %>
      </div>
    <% end %>

    <%= if error = @flash["error"] do %>
      <div class="alert alert-danger" role="alert" phx-click="lv:clear-flash" phx-value-key="error">
        <%= error %>
      </div>
    <% end %>
    """
  end

  def login(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          Sign in to account
          <:subtitle>
            Don't have an account?
            <.link navigate={~p"/auth/register"} class="font-semibold text-brand hover:underline">
              Sign up
            </.link>
            for an account now.
          </:subtitle>
        </.header>

        <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/auth/login"}>
          <.input field={f[:email]} type="email" label="Email" required />
          <.input field={f[:password]} type="password" label="Password" required />

          <:actions :let={f}>
            <.input field={f[:remember_me]} type="checkbox" label="Keep me logged in" checked={true} />
            <.link href={~p"/auth/forgot-password"} class="text-sm font-semibold">
              Forgot your password?
            </.link>
          </:actions>
          <:actions>
            <.button phx-disable-with="Signing in..." class="w-full">
              Sign in <span aria-hidden="true">→</span>
            </.button>
          </:actions>
        </.simple_form>

        <div class="mt-6">
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-gray-300"></div>
            </div>
            <div class="relative flex justify-center text-sm">
              <span class="bg-white px-2 text-gray-500">Or continue with</span>
            </div>
          </div>

          <div class="mt-6">
            <.link
              href={~p"/auth/facebook"}
              class="flex w-full justify-center items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
            >
              <svg class="w-5 h-5 mr-3" viewBox="0 0 24 24" fill="currentColor">
                <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
              </svg>
              Continue with Facebook
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def register(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Register for an account
        <:subtitle>
          Already have an account?
          <.link navigate={~p"/auth/login"} class="font-semibold text-brand hover:underline">
            Sign in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/auth/register"}>
        <.input field={f[:name]} type="text" label="Name" required />
        <.input field={f[:email]} type="email" label="Email" required />
        <.input field={f[:password]} type="password" label="Password" required />
        <.input field={f[:password_confirmation]} type="password" label="Confirm password" required />

        <!-- Cloudflare Turnstile Widget -->
        <% turnstile_config = Application.get_env(:eventasaurus, :turnstile, []) %>
        <%= if turnstile_config[:site_key] do %>
          <div class="flex justify-center my-4">
            <div 
              class="cf-turnstile" 
              data-sitekey={turnstile_config[:site_key]}
              data-theme={turnstile_config[:theme] || "light"}
              data-appearance={turnstile_config[:appearance] || "always"}
              data-size={turnstile_config[:size] || "normal"}
            ></div>
          </div>
        <% end %>

        <:actions>
          <.button phx-disable-with="Creating account..." class="w-full">
            Create an account <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def forgot_password(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Forgot your password?
        <:subtitle>We'll send a password reset link to your inbox</:subtitle>
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/auth/forgot-password"}>
        <.input field={f[:email]} type="email" label="Email" required />

        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">
            Send password reset instructions
          </.button>
        </:actions>
        <:actions>
          <.link href={~p"/auth/login"} class="text-sm font-semibold">
            <span aria-hidden="true">&larr;</span> Back to sign in
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def reset_password(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Reset Password
        <:subtitle>Enter your new password below</:subtitle>
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/auth/reset-password"}>
        <%= if assigns[:token] do %>
          <input type="hidden" name="token" value={@token} />
        <% end %>

        <.input field={f[:password]} type="password" label="New password" required />
        <.input field={f[:password_confirmation]} type="password" label="Confirm new password" required />

        <:actions>
          <.button phx-disable-with="Resetting..." class="w-full">
            Reset password
          </.button>
        </:actions>

        <:actions>
          <.link href={~p"/auth/login"} class="text-sm font-semibold">
            <span aria-hidden="true">&larr;</span> Back to sign in
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
