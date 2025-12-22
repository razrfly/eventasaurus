defmodule EventasaurusDiscovery.PostHog.ViewCountQuery do
  @moduledoc """
  Queries PostHog for pageview counts by URL path.

  Used by PostHogPopularitySyncWorker to fetch view counts for events,
  which are then synced to the database for fast popularity sorting.

  ## Configuration

  Requires the following environment variables:
  - `POSTHOG_PRIVATE_API_KEY` - Personal API key for HogQL queries
  - `POSTHOG_PROJECT_ID` - PostHog project ID

  ## Example

      iex> ViewCountQuery.get_event_view_counts(7)
      {:ok, [
        {"/e/jazz-concert-krakow", 150},
        {"/c/krakow/e/classical-night", 85},
        ...
      ]}

  """

  require Logger

  @api_base "https://eu.i.posthog.com/api"
  # 30 second timeout for potentially slow HogQL queries
  @default_timeout 30_000

  @doc """
  Query unique visitors per page path from PostHog for event pages.

  Returns pageview counts for URLs matching `/e/{slug}` or `/c/{city}/e/{slug}`.

  ## Parameters

  - `days` - Number of days to look back (default: 7)
  - `opts` - Optional keyword list:
    - `:timeout` - Request timeout in ms (default: 30000)
    - `:limit` - Max results to return (default: 10000)

  ## Returns

  - `{:ok, [{path, unique_visitors}, ...]}` - List of path/count tuples
  - `{:error, reason}` - Error with reason atom or tuple

  """
  @spec get_event_view_counts(integer(), keyword()) ::
          {:ok, [{String.t(), integer()}]} | {:error, any()}
  def get_event_view_counts(days \\ 7, opts \\ []) do
    api_key = get_private_api_key()
    project_id = get_project_id()

    cond do
      !api_key ->
        Logger.warning("PostHog private API key not configured for view count queries")
        {:error, :no_api_key}

      !project_id ->
        Logger.warning("PostHog project ID not configured for view count queries")
        {:error, :no_project_id}

      true ->
        timeout = Keyword.get(opts, :timeout, @default_timeout)
        limit = Keyword.get(opts, :limit, 10_000)
        execute_view_count_query(days, limit, api_key, project_id, timeout)
    end
  end

  @doc """
  Query unique visitors for all page types (events, movies, venues, performers).

  This is a more comprehensive query for future use when we add view_count
  to movies, venues, and performers tables.

  ## Parameters

  - `days` - Number of days to look back (default: 7)

  ## Returns

  - `{:ok, [{path, unique_visitors}, ...]}` - List of path/count tuples
  - `{:error, reason}` - Error with reason atom or tuple

  """
  @spec get_all_view_counts(integer(), keyword()) ::
          {:ok, [{String.t(), integer()}]} | {:error, any()}
  def get_all_view_counts(days \\ 7, opts \\ []) do
    api_key = get_private_api_key()
    project_id = get_project_id()

    cond do
      !api_key ->
        {:error, :no_api_key}

      !project_id ->
        {:error, :no_project_id}

      true ->
        timeout = Keyword.get(opts, :timeout, @default_timeout)
        limit = Keyword.get(opts, :limit, 10_000)
        execute_all_paths_query(days, limit, api_key, project_id, timeout)
    end
  end

  # Execute query for event pages only
  defp execute_view_count_query(days, limit, api_key, project_id, timeout) do
    date_from = days_ago(days)
    date_to = current_time_string()

    # HogQL query for event page views
    # Matches /e/{slug} and /c/{city}/e/{slug} patterns
    query = """
    SELECT
      properties.$pathname as path,
      count(DISTINCT person_id) as unique_visitors
    FROM events
    WHERE event = '$pageview'
      AND (
        match(properties.$pathname, '^/e/[^/]+$')
        OR match(properties.$pathname, '^/c/[^/]+/e/[^/]+$')
      )
      AND timestamp >= '#{date_from}'
      AND timestamp <= '#{date_to}'
    GROUP BY path
    ORDER BY unique_visitors DESC
    LIMIT #{limit}
    """

    execute_hogql_query(query, api_key, project_id, timeout)
  end

  # Execute query for all detail page types
  defp execute_all_paths_query(days, limit, api_key, project_id, timeout) do
    date_from = days_ago(days)
    date_to = current_time_string()

    # HogQL query for all detail pages
    query = """
    SELECT
      properties.$pathname as path,
      count(DISTINCT person_id) as unique_visitors
    FROM events
    WHERE event = '$pageview'
      AND (
        match(properties.$pathname, '^/e/[^/]+$')
        OR match(properties.$pathname, '^/c/[^/]+/e/[^/]+$')
        OR match(properties.$pathname, '^/m/[^/]+$')
        OR match(properties.$pathname, '^/c/[^/]+/m/[^/]+$')
        OR match(properties.$pathname, '^/v/[^/]+$')
        OR match(properties.$pathname, '^/p/[^/]+$')
      )
      AND timestamp >= '#{date_from}'
      AND timestamp <= '#{date_to}'
    GROUP BY path
    ORDER BY unique_visitors DESC
    LIMIT #{limit}
    """

    execute_hogql_query(query, api_key, project_id, timeout)
  end

  defp execute_hogql_query(query, api_key, project_id, timeout) do
    url = "#{@api_base}/projects/#{project_id}/query/"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "query" => %{
          "kind" => "HogQLQuery",
          "query" => query
        }
      })

    Logger.debug("Executing PostHog HogQL query for view counts")

    case HTTPoison.post(url, body, headers, timeout: timeout, recv_timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        parse_view_count_response(response_body)

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("PostHog view count query failed with status #{status_code}: #{response_body}")
        {:error, {:api_error, status_code}}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("PostHog view count query timed out after #{timeout}ms")
        {:error, :timeout}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("PostHog view count query request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_view_count_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"results" => results}} when is_list(results) ->
        # Results format: [[path1, count1], [path2, count2], ...]
        view_counts =
          results
          |> Enum.map(fn
            [path, count] when is_binary(path) and is_integer(count) ->
              {path, count}

            [path, count] when is_binary(path) and is_float(count) ->
              # Handle float counts from PostHog
              {path, trunc(count)}

            [path, nil] when is_binary(path) ->
              # Handle nil counts
              {path, 0}

            _ ->
              nil
          end)
          |> Enum.reject(&is_nil/1)

        Logger.info("PostHog view count query returned #{length(view_counts)} results")
        {:ok, view_counts}

      {:ok, %{"results" => []}} ->
        Logger.info("PostHog view count query returned no results")
        {:ok, []}

      {:ok, response} ->
        Logger.error("Unexpected PostHog response format: #{inspect(response)}")
        {:error, :invalid_response_format}

      {:error, reason} ->
        Logger.error("Failed to parse PostHog response: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  defp days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp current_time_string do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp get_private_api_key do
    System.get_env("POSTHOG_PRIVATE_API_KEY") || System.get_env("POSTHOG_PERSONAL_API_KEY")
  end

  defp get_project_id do
    System.get_env("POSTHOG_PROJECT_ID")
  end
end
