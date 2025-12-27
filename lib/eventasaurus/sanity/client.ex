defmodule Eventasaurus.Sanity.Client do
  @moduledoc """
  Sanity CMS API client for fetching changelog entries.

  Uses Req HTTP client following existing codebase patterns.
  """

  require Logger

  alias Eventasaurus.Sanity.Config

  @receive_timeout 10_000

  @doc """
  Fetches released changelog entries from Sanity, ordered by date descending.
  Only returns entries with status == "released" and isPublished == true.

  ## Returns

  - `{:ok, entries}` - List of changelog entry maps
  - `{:error, reason}` - Error with reason

  ## Examples

      iex> Client.list_changelog_entries()
      {:ok, [%{"_id" => "...", "title" => "...", ...}]}
  """
  @spec list_changelog_entries() :: {:ok, list(map())} | {:error, atom() | tuple()}
  def list_changelog_entries do
    query = ~s"""
    *[_type == "changelogEntry" && status == "released" && isPublished == true] | order(date desc) {
      _id,
      title,
      "slug": slug.current,
      date,
      summary,
      changes[] { type, description },
      tags,
      image {
        asset-> { url }
      }
    }
    """

    execute_query(query)
  end

  @doc """
  Fetches roadmap entries from Sanity (non-released items).
  Returns entries with status != "released" and isPublished == true.
  Ordered by status priority (in_progress first, then planned, then considering).

  ## Returns

  - `{:ok, entries}` - List of roadmap entry maps
  - `{:error, reason}` - Error with reason

  ## Examples

      iex> Client.list_roadmap_entries()
      {:ok, [%{"_id" => "...", "title" => "...", "status" => "in_progress", ...}]}
  """
  @spec list_roadmap_entries() :: {:ok, list(map())} | {:error, atom() | tuple()}
  def list_roadmap_entries do
    query = ~s"""
    *[_type == "changelogEntry" && status != "released" && isPublished == true] | order(
      select(status == "in_progress" => 0, status == "planned" => 1, status == "considering" => 2),
      title asc
    ) {
      _id,
      title,
      "slug": slug.current,
      status,
      summary,
      tags,
      image {
        asset-> { url }
      }
    }
    """

    execute_query(query)
  end

  @doc """
  Executes a GROQ query against the Sanity API.

  ## Parameters

  - `query` - GROQ query string

  ## Returns

  - `{:ok, result}` - Query result (usually a list)
  - `{:error, reason}` - Error with reason
  """
  @spec execute_query(String.t()) :: {:ok, any()} | {:error, atom() | tuple()}
  def execute_query(query) do
    unless Config.enabled?() do
      Logger.warning("Sanity not configured - returning empty result")
      {:error, :not_configured}
    else
      do_execute_query(query)
    end
  end

  defp do_execute_query(query) do
    project_id = Config.project_id()
    api_token = Config.api_token()
    dataset = Config.dataset()

    url = "https://#{project_id}.api.sanity.io/v2024-01-01/data/query/#{dataset}"

    Logger.debug("Sanity query: #{String.slice(query, 0, 100)}...")

    case Req.get(
           url,
           params: [query: query],
           headers: [{"Authorization", "Bearer #{api_token}"}],
           receive_timeout: @receive_timeout
         ) do
      {:ok, %Req.Response{status: 200, body: %{"result" => result}}} ->
        Logger.debug("Sanity returned #{length(result)} entries")
        {:ok, result}

      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.error("Sanity returned unexpected body format: #{inspect(body)}")
        {:error, :invalid_response}

      {:ok, %Req.Response{status: 401}} ->
        Logger.error("Sanity authentication failed - check SANITY_API_TOKEN")
        {:error, :authentication_failed}

      {:ok, %Req.Response{status: 403}} ->
        Logger.error("Sanity forbidden - check API token permissions")
        {:error, :forbidden}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Sanity API error (#{status}): #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, exception} ->
        Logger.error("Sanity request failed: #{inspect(exception)}")
        {:error, :request_failed}
    end
  end
end
