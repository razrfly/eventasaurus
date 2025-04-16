defmodule EventasaurusWeb.Auth.AuthHTML do
  use EventasaurusWeb, :html

  embed_templates "auth_html/*"

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
      <.flash_messages flash={@flash} />

      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          Sign in to account
          <:subtitle>
            Don't have an account?
            <.link navigate={~p"/register"} class="font-semibold text-brand hover:underline">
              Sign up
            </.link>
            for an account now.
          </:subtitle>
        </.header>

        <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/login"}>
          <.input field={f[:email]} type="email" label="Email" required />
          <.input field={f[:password]} type="password" label="Password" required />

          <:actions :let={f}>
            <.input field={f[:remember_me]} type="checkbox" label="Keep me logged in" />
            <.link href={~p"/reset-password"} class="text-sm font-semibold">
              Forgot your password?
            </.link>
          </:actions>
          <:actions>
            <.button phx-disable-with="Signing in..." class="w-full">
              Sign in <span aria-hidden="true">→</span>
            </.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def register(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.flash_messages flash={@flash} />

      <.header class="text-center">
        Register for an account
        <:subtitle>
          Already have an account?
          <.link navigate={~p"/login"} class="font-semibold text-brand hover:underline">
            Sign in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/register"}>
        <.input field={f[:name]} type="text" label="Name" required />
        <.input field={f[:email]} type="email" label="Email" required />
        <.input field={f[:password]} type="password" label="Password" required />
        <.input field={f[:password_confirmation]} type="password" label="Confirm password" required />

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
      <.flash_messages flash={@flash} />

      <.header class="text-center">
        Forgot your password?
        <:subtitle>We'll send a password reset link to your inbox</:subtitle>
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/reset-password"}>
        <.input field={f[:email]} type="email" label="Email" required />

        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">
            Send password reset instructions
          </.button>
        </:actions>
        <:actions>
          <.link href={~p"/login"} class="text-sm font-semibold">
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
      <.flash_messages flash={@flash} />

      <.header class="text-center">
        Reset Password
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/reset-password/#{@token}"}>
        <.input field={f[:password]} type="password" label="New password" required />
        <.input field={f[:password_confirmation]} type="password" label="Confirm new password" required />
        <:actions>
          <.button phx-disable-with="Resetting..." class="w-full">
            Reset password
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
