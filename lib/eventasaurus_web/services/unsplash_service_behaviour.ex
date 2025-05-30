defmodule EventasaurusWeb.Services.UnsplashServiceBehaviour do
  @moduledoc """
  Behaviour for Unsplash service implementations.
  This enables mocking of the UnsplashService in tests.
  """

  @doc """
  Search for photos on Unsplash.
  """
  @callback search_photos(String.t(), integer(), integer()) ::
    {:ok, list()} | {:error, String.t()}

  @doc """
  Track a photo download for Unsplash API compliance.
  """
  @callback track_download(String.t()) ::
    :ok | {:error, String.t()}
end
