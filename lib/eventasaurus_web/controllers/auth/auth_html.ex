defmodule EventasaurusWeb.Auth.AuthHTML do
  @moduledoc """
  This module contains pages rendered by AuthController.

  See the `auth_html` directory for all templates.
  """
  use EventasaurusWeb, :html
  import Phoenix.Controller, only: [get_csrf_token: 0]
  import EventasaurusWeb.SocialAuthComponents

  embed_templates "auth_html/*"

  # Define the required flash attribute for the flash_messages function
  attr :flash, :map, required: true

  @doc """
  Helper function to handle social authentication errors in templates.

  This can be used in templates to add error handling state to forms.
  """
    def social_auth_assigns(conn) do
    flash = Map.get(conn.assigns, :flash, %{})
    auth_error = Phoenix.Flash.get(flash, :auth_error)
    last_attempted_provider = Phoenix.Flash.get(flash, :last_attempted_provider)

    %{
      auth_error: if(auth_error, do: %{"reason" => auth_error, "provider" => last_attempted_provider}),
      last_attempted_provider: last_attempted_provider
    }
  end

  @doc """
  Creates a JavaScript configuration for social authentication.

  This provides the Supabase configuration to the frontend JavaScript.
  """
  def social_auth_config(_conn) do
    supabase_url = Application.get_env(:eventasaurus, :supabase)[:url]
    supabase_anon_key = Application.get_env(:eventasaurus, :supabase)[:anon_key]

    %{
      "data-supabase-url" => supabase_url,
      "data-supabase-api-key" => supabase_anon_key
    }
  end

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
            <.input field={f[:remember_me]} type="checkbox" label="Keep me logged in" />
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
      </div>
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
      </.header>

      <.simple_form :let={f} for={@conn.params["user"] || %{}} as={:user} action={~p"/auth/reset-password"}>
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
