defmodule EventasaurusWeb.Services.MusicBrainzServiceBehaviour do
  @moduledoc """
  Behaviour for MusicBrainz service implementations.
  
  Defines the contract for interacting with the MusicBrainz API,
  following the same patterns as TmdbServiceBehaviour.
  """

  @doc """
  Search for music content (artists, recordings, releases) using MusicBrainz search API.
  
  ## Parameters
  
  - `query`: Search term
  - `entity`: Entity type (:artist, :recording, :release, :release_group)
  - `page`: Page number for pagination (optional, defaults to 1)
  
  ## Returns
  
  - `{:ok, [result]}`: List of search results
  - `{:error, reason}`: Error with reason
  """
  @callback search_multi(query :: String.t(), entity :: atom(), page :: integer()) ::
    {:ok, list()} | {:error, any()}

  @doc """
  Get detailed artist information including releases and recordings.
  """
  @callback get_artist_details(artist_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get detailed recording information including artist and release data.
  """
  @callback get_recording_details(recording_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get detailed release information including track listing and artist data.
  """
  @callback get_release_details(release_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get detailed release group information (album-level data).
  """
  @callback get_release_group_details(release_group_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get cached artist details or fetch from API if not cached.
  This is the recommended way to get artist details for performance.
  """
  @callback get_cached_artist_details(artist_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get cached recording details or fetch from API if not cached.
  This is the recommended way to get recording details for performance.
  """
  @callback get_cached_recording_details(recording_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get cached release details or fetch from API if not cached.
  This is the recommended way to get release details for performance.
  """
  @callback get_cached_release_details(release_id :: String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get cached release group details or fetch from API if not cached.
  This is the recommended way to get release group details for performance.
  """
  @callback get_cached_release_group_details(release_group_id :: String.t()) ::
    {:ok, map()} | {:error, any()}
end