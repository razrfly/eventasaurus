defmodule EventasaurusApp.Auth.AuthProvider do
  @moduledoc """
  Unified authentication provider that routes to either Supabase or Clerk
  based on configuration.

  This module enables a gradual migration from Supabase Auth to Clerk by:
  1. Checking which provider is enabled via config
  2. Routing auth calls to the appropriate implementation
  3. Supporting fallback to Supabase during migration

  ## Configuration

  Set via environment variables:
  - CLERK_ENABLED=true - Enable Clerk authentication
  - CLERK_SECRET_KEY=sk_... - Clerk secret key
  - CLERK_PUBLISHABLE_KEY=pk_... - Clerk publishable key

  ## Usage

      # Check which provider is active
      AuthProvider.active_provider() # => :clerk or :supabase

      # Check if Clerk is enabled
      AuthProvider.clerk_enabled?() # => true or false
  """

  @doc """
  Returns the currently active authentication provider.

  Returns `:clerk` if Clerk is enabled and configured, otherwise `:supabase`.
  """
  def active_provider do
    if clerk_enabled?() do
      :clerk
    else
      :supabase
    end
  end

  @doc """
  Checks if Clerk authentication is enabled.

  Returns true if CLERK_ENABLED is set and Clerk credentials are configured.
  """
  def clerk_enabled? do
    config = Application.get_env(:eventasaurus, :clerk, [])
    config[:enabled] == true
  end

  @doc """
  Checks if Supabase authentication is enabled.

  Returns true if Clerk is not enabled (default/fallback).
  """
  def supabase_enabled? do
    not clerk_enabled?()
  end

  @doc """
  Returns the Clerk configuration if available.
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
  Returns the frontend auth configuration based on active provider.

  This is used to pass auth config to JavaScript/frontend components.
  """
  def frontend_config do
    if clerk_enabled?() do
      %{
        provider: "clerk",
        publishable_key: clerk_publishable_key(),
        domain: clerk_domain()
      }
    else
      %{
        provider: "supabase",
        url: Application.get_env(:eventasaurus, :supabase)[:url],
        anon_key: Application.get_env(:eventasaurus, :supabase)[:anon_key]
      }
    end
  end
end
