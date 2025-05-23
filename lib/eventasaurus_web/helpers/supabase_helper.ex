defmodule EventasaurusWeb.Helpers.SupabaseHelper do
  @moduledoc """
  Helper functions for Supabase configuration in templates.
  """

  @doc """
  Gets the appropriate Supabase URL based on the current environment.
  """
  def supabase_url do
    if Application.get_env(:eventasaurus_app, :env) == :dev do
      Application.get_env(:eventasaurus_app, :supabase_url_local) ||
      System.get_env("SUPABASE_URL_LOCAL")
    else
      Application.get_env(:eventasaurus_app, :supabase_url) ||
      System.get_env("SUPABASE_URL")
    end
  end

  @doc """
  Gets the appropriate Supabase API key based on the current environment.
  """
  def supabase_api_key do
    if Application.get_env(:eventasaurus_app, :env) == :dev do
      Application.get_env(:eventasaurus_app, :supabase_api_key_local) ||
      System.get_env("SUPABASE_API_KEY_LOCAL")
    else
      Application.get_env(:eventasaurus_app, :supabase_api_key) ||
      System.get_env("SUPABASE_API_KEY")
    end
  end

  @doc """
  Gets both Supabase URL and API key as a tuple for convenience.
  """
  def supabase_credentials do
    {supabase_url(), supabase_api_key()}
  end
end
