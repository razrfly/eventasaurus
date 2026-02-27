defmodule EventasaurusWeb.Services.CinegraphClient do
  @moduledoc """
  HTTP client for the Cinegraph GraphQL API.

  Fetches rich movie data including multi-source ratings (TMDB, IMDb, Rotten Tomatoes,
  Metacritic), full cast/crew with profiles, awards data, and canonical list membership.

  Data is cached at the DB level (cinegraph_data column on movies), so this client
  is only called by CinegraphSyncWorker — never directly from LiveView.

  Note: criScore/criBreakdown are intentionally excluded — pending Cinegraph migration.
  """

  require Logger

  @graphql_query """
  query GetMovie($tmdbId: Int!) {
    movie(tmdbId: $tmdbId) {
      title
      slug
      ratings {
        tmdb
        tmdbVotes
        imdb
        imdbVotes
        rottenTomatoes
        metacritic
      }
      awards {
        summary
        oscarWins
        totalWins
        totalNominations
      }
      canonicalSources
      cast {
        character
        castOrder
        person {
          name
          profilePath
          slug
        }
      }
      crew {
        job
        department
        person {
          name
          profilePath
          slug
        }
      }
    }
  }
  """

  @doc """
  Fetch movie data from Cinegraph by TMDB ID.

  Returns `{:ok, data_map}` on success or `{:error, reason}` on failure.
  The data_map contains camelCase keys as returned by GraphQL.
  """
  @spec get_movie(integer()) :: {:ok, map()} | {:error, term()}
  def get_movie(tmdb_id) when is_integer(tmdb_id) do
    config = Application.get_env(:eventasaurus, :cinegraph, [])
    base_url = Keyword.get(config, :base_url, "http://cinegraph.org")
    api_key = Keyword.get(config, :api_key, "")

    url = "#{base_url}/api/graphql"

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]

    body =
      Jason.encode!(%{
        query: @graphql_query,
        variables: %{tmdbId: tmdb_id}
      })

    options = [recv_timeout: 15_000, timeout: 15_000]

    case HTTPoison.post(url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        parse_response(response_body, tmdb_id)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.warning("CinegraphClient: HTTP #{status_code} for tmdb_id=#{tmdb_id}")
        {:error, {:http_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("CinegraphClient: request failed for tmdb_id=#{tmdb_id}: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_response(body, tmdb_id) do
    case Jason.decode(body) do
      {:ok, %{"data" => %{"movie" => movie}}} when not is_nil(movie) ->
        {:ok, movie}

      {:ok, %{"data" => %{"movie" => nil}}} ->
        Logger.info("CinegraphClient: movie not found for tmdb_id=#{tmdb_id}")
        {:error, :not_found}

      {:ok, %{"errors" => errors}} ->
        Logger.warning("CinegraphClient: GraphQL errors for tmdb_id=#{tmdb_id}: #{inspect(errors)}")
        {:error, {:graphql_errors, errors}}

      {:ok, unexpected} ->
        Logger.warning("CinegraphClient: unexpected response shape for tmdb_id=#{tmdb_id}: #{inspect(unexpected)}")
        {:error, :unexpected_response}

      {:error, decode_error} ->
        Logger.warning("CinegraphClient: JSON decode error for tmdb_id=#{tmdb_id}: #{inspect(decode_error)}")
        {:error, {:json_decode_error, decode_error}}
    end
  end
end
