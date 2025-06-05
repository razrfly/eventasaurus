defmodule EventasaurusWeb.Helpers.SupabaseHelper do
  @moduledoc """
  Helper functions for Supabase configuration in templates.
  """

  @doc """
  Gets the appropriate Supabase URL from configuration.
  """
  def supabase_url do
    case Application.get_env(:eventasaurus, :supabase) do
      nil -> raise "Supabase configuration not found"
      config -> config[:url] || raise "Supabase URL not configured"
    end
  end

  @doc """
  Gets the appropriate Supabase API key from configuration.
  """
  def supabase_api_key do
    case Application.get_env(:eventasaurus, :supabase) do
      nil -> raise "Supabase configuration not found"
      config -> config[:api_key] || raise "Supabase API key not configured"
    end
  end

  @doc """
  Gets both Supabase URL and API key as a tuple for convenience.
  """
  def supabase_credentials do
    {supabase_url(), supabase_api_key()}
  end
end
