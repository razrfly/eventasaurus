defmodule EventasaurusApp.Auth.AuthProvider do
  @moduledoc """
  Authentication provider configuration for Clerk.

  This module provides Clerk configuration for the application.
  Clerk is the sole authentication provider - Supabase auth has been removed.

  ## Configuration

  Set via environment variables:
  - CLERK_SECRET_KEY=sk_... - Clerk secret key
  - CLERK_PUBLISHABLE_KEY=pk_... - Clerk publishable key

  ## Usage

      # Get the active provider (always :clerk)
      AuthProvider.active_provider() # => :clerk

      # Check if Clerk is enabled (always true)
      AuthProvider.clerk_enabled?() # => true
  """

  @doc """
  Returns the currently active authentication provider.

  Always returns `:clerk` as it is the sole authentication provider.
  """
  def active_provider, do: :clerk

  @doc """
  Checks if Clerk authentication is enabled.

  Always returns true as Clerk is the sole authentication provider.
  """
  def clerk_enabled?, do: true

  @doc """
  Checks if Supabase authentication is enabled.

  Always returns false as Supabase auth has been removed.
  """
  def supabase_enabled?, do: false

  @doc """
  Returns the Clerk configuration.
  """
  def clerk_config do
    Application.get_env(:eventasaurus, :clerk, [])
  end

  @doc """
  Returns the Clerk publishable key for frontend use.
  """
  def clerk_publishable_key do
    clerk_config()[:publishable_key]
  end

  @doc """
  Returns the Clerk domain for frontend configuration.
  """
  def clerk_domain do
    clerk_config()[:domain]
  end

  @doc """
  Returns the frontend auth configuration for Clerk.

  This is used to pass auth config to JavaScript/frontend components.
  """
  def frontend_config do
    %{
      provider: "clerk",
      publishable_key: clerk_publishable_key(),
      domain: clerk_domain()
    }
  end
end
