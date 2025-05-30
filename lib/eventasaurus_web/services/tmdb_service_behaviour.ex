defmodule EventasaurusWeb.Services.TmdbServiceBehaviour do
  @moduledoc """
  Behaviour for TMDb service implementations.
  This enables mocking of the TmdbService in tests.
  """

  @doc """
  Search for movies, TV shows, and people on TMDb.
  """
  @callback search_multi(String.t(), integer()) ::
    {:ok, list()} | {:error, any()}
end
