defmodule EventasaurusDiscovery.Sources.Repertuary.TmdbMatcher do
  @moduledoc """
  DEPRECATED: Use `EventasaurusDiscovery.Movies.TmdbMatcher` instead.

  This module is kept for backwards compatibility with existing code.
  All functionality has been moved to the universal TmdbMatcher in the Movies context.
  """

  # Delegate all functions to the new universal location
  defdelegate match_movie(movie_data), to: EventasaurusDiscovery.Movies.TmdbMatcher
  defdelegate find_or_create_movie(tmdb_id), to: EventasaurusDiscovery.Movies.TmdbMatcher
end
