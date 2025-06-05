defmodule EventasaurusWeb.Helpers.SupabaseHelper do
  @moduledoc """
  Helper functions for Supabase configuration in templates.
  """

  @doc """
  Gets the appropriate Supabase URL from configuration.
  """
  def supabase_url do
    Application.get_env(:eventasaurus, :supabase)[:url]
  end

  @doc """
  Gets the appropriate Supabase API key from configuration.
  """
  def supabase_api_key do
    Application.get_env(:eventasaurus, :supabase)[:api_key]
  end

  @doc """
  Gets both Supabase URL and API key as a tuple for convenience.
  """
  def supabase_credentials do
    {supabase_url(), supabase_api_key()}
  end
end
