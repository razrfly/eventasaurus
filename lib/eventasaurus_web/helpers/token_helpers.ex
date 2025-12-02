defmodule EventasaurusWeb.TokenHelpers do
  @moduledoc """
  Helper functions for managing authentication tokens.

  Note: With the migration to Clerk authentication and R2 for image storage,
  this module is now deprecated. It's kept for backwards compatibility
  but the token refresh logic has been removed.
  """

  @doc """
  Get the current valid access token from session.

  This function previously handled Supabase token refresh but now simply
  returns the access token from session (if any). With Clerk authentication
  and R2 for storage, token refresh is no longer needed.

  Returns nil if no token is present, which is expected behavior with Clerk.
  """
  def get_current_valid_token(session) do
    session["access_token"]
  end
end
