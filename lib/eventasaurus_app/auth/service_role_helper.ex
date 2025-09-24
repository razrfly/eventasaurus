defmodule EventasaurusApp.Auth.ServiceRoleHelper do
  @moduledoc """
  Helper module for managing Supabase service role key access.
  Provides utilities for checking key availability and guiding setup.
  """

  @doc """
  Gets the service role key from environment.
  Returns the key if available, nil otherwise.
  """
  def get_service_role_key do
    System.get_env("SUPABASE_SERVICE_ROLE_KEY") ||
      System.get_env("SUPABASE_SERVICE_ROLE_KEY_LOCAL")
  end

  @doc """
  Checks if service role key is available.
  """
  def service_role_key_available? do
    get_service_role_key() != nil
  end

  @doc """
  Returns a helpful message for setting up the service role key.
  """
  def setup_instructions do
    """

    ⚠️  SUPABASE SERVICE ROLE KEY NOT FOUND

    To enable authenticated user creation in seeds:

    1. Get the service role key:
       $ supabase status | grep "service_role key"

    2. Export it for your current session:
       $ export SUPABASE_SERVICE_ROLE_KEY_LOCAL="<your-key>"

    3. Or add to your .env file:
       SUPABASE_SERVICE_ROLE_KEY_LOCAL=<your-key>

    4. Run seeds again:
       $ mix run priv/repo/seeds.exs
       $ mix seed.dev

    Without the service role key, seeded users cannot log in.
    """
  end

  @doc """
  Logs setup instructions if key is not available.
  Returns true if key is available, false otherwise.
  """
  def ensure_available do
    if service_role_key_available?() do
      true
    else
      IO.puts(setup_instructions())
      false
    end
  end

  @doc """
  Gets the service role key or raises an error with setup instructions.
  """
  def get_service_role_key! do
    case get_service_role_key() do
      nil ->
        raise """
        #{setup_instructions()}

        Cannot proceed without service role key.
        """

      key ->
        key
    end
  end
end
