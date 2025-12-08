defmodule Eventasaurus.Sanity.Changelog do
  @moduledoc """
  Service module for changelog operations.
  Transforms Sanity data to component format and handles caching.
  """

  require Logger

  alias Eventasaurus.Sanity.Client

  @cache_table :sanity_changelog_cache
  @cache_ttl_ms :timer.minutes(5)
  @new_entry_days 30
  @default_page_size 10

  @doc """
  Gets all changelog entries, with caching.
  Returns entries formatted for ChangelogComponents.

  ## Options

  - `:page` - Page number (1-indexed, default: 1)
  - `:page_size` - Entries per page (default: 10)

  ## Returns

  - `{:ok, entries, pagination}` - List of formatted changelog entries with pagination metadata
  - `{:error, reason}` - Error with reason

  ## Pagination Metadata

      %{
        page: 1,
        page_size: 10,
        total_entries: 12,
        total_pages: 2,
        has_next: true,
        has_prev: false
      }
  """
  @spec list_entries(keyword()) :: {:ok, list(map()), map()} | {:error, atom() | tuple()}
  def list_entries(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, @default_page_size)

    case get_cached_entries() do
      {:ok, entries} ->
        Logger.debug("Changelog cache hit")
        {:ok, paginated, pagination} = paginate_entries(entries, page, page_size)
        {:ok, paginated, pagination}

      :miss ->
        Logger.debug("Changelog cache miss - fetching from Sanity")
        fetch_and_cache_entries(page, page_size)
    end
  end

  @doc """
  Gets all changelog entries without pagination.
  Useful for RSS feeds, exports, etc.
  """
  @spec list_all_entries() :: {:ok, list(map())} | {:error, atom() | tuple()}
  def list_all_entries do
    case get_cached_entries() do
      {:ok, entries} ->
        {:ok, entries}

      :miss ->
        case Client.list_changelog_entries() do
          {:ok, raw_entries} ->
            entries = Enum.map(raw_entries, &transform_entry/1)
            cache_entries(entries)
            {:ok, entries}

          error ->
            error
        end
    end
  end

  @doc """
  Clears the changelog cache.
  Useful for forcing a refresh after updates.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    try do
      :ets.delete(@cache_table, :entries)
      :ok
    rescue
      ArgumentError -> :ok
    end
  end

  defp fetch_and_cache_entries(page, page_size) do
    case Client.list_changelog_entries() do
      {:ok, raw_entries} ->
        entries = Enum.map(raw_entries, &transform_entry/1)
        cache_entries(entries)
        {:ok, paginated, pagination} = paginate_entries(entries, page, page_size)
        {:ok, paginated, pagination}

      error ->
        error
    end
  end

  defp paginate_entries(entries, page, page_size) do
    total_entries = length(entries)
    total_pages = ceil(total_entries / page_size)
    offset = (page - 1) * page_size

    paginated =
      entries
      |> Enum.drop(offset)
      |> Enum.take(page_size)

    pagination = %{
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      has_next: page < total_pages,
      has_prev: page > 1
    }

    {:ok, paginated, pagination}
  end

  @doc """
  Transforms a Sanity entry to component format.

  ## Sanity Format (input)

      %{
        "_id" => "2HiJPd1Jr2ND3Bhnmi5oBk",
        "title" => "Smart Date Polling",
        "slug" => "smart-date-polling",
        "date" => "2024-10-15",
        "summary" => "Let your group vote...",
        "changes" => [%{"type" => "added", "description" => "..."}],
        "tags" => ["polling", "scheduling"],
        "image" => %{"asset" => %{"url" => "https://..."}}
      }

  ## Component Format (output)

      %{
        id: "2HiJPd1Jr2ND3Bhnmi5oBk",
        date: "October 15, 2024",
        iso_date: "2024-10-15",
        title: "Smart Date Polling",
        summary: "Let your group vote...",
        changes: [%{type: "added", description: "..."}],
        image: "https://...",
        is_new: true  # true if entry is less than 30 days old
      }
  """
  @spec transform_entry(map()) :: map()
  def transform_entry(entry) do
    %{
      id: entry["_id"],
      date: format_date(entry["date"]),
      iso_date: entry["date"],
      title: entry["title"],
      summary: entry["summary"],
      changes: transform_changes(entry["changes"] || []),
      tags: entry["tags"] || [],
      image: get_image_url(entry["image"]),
      is_new: is_new_entry?(entry["date"])
    }
  end

  defp is_new_entry?(nil), do: false

  defp is_new_entry?(iso_date) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} ->
        days_ago = Date.diff(Date.utc_today(), date)
        days_ago <= @new_entry_days

      _ ->
        false
    end
  end

  defp format_date(nil), do: "Unknown date"

  defp format_date(iso_date) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} -> Calendar.strftime(date, "%B %-d, %Y")
      _ -> iso_date
    end
  end

  defp transform_changes(changes) when is_list(changes) do
    Enum.map(changes, fn change ->
      %{
        type: change["type"],
        description: change["description"]
      }
    end)
  end

  defp transform_changes(_), do: []

  defp get_image_url(nil), do: nil
  defp get_image_url(%{"asset" => %{"url" => url}}), do: url
  defp get_image_url(_), do: nil

  # ETS-based caching

  defp get_cached_entries do
    ensure_cache_table_exists()

    case :ets.lookup(@cache_table, :entries) do
      [{:entries, entries, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          {:ok, entries}
        else
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_entries(entries) do
    ensure_cache_table_exists()
    :ets.insert(@cache_table, {:entries, entries, System.monotonic_time(:millisecond)})
  rescue
    ArgumentError ->
      Logger.warning("Failed to cache changelog entries")
  end

  defp ensure_cache_table_exists do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:named_table, :public, :set])

      _ref ->
        :ok
    end
  rescue
    ArgumentError ->
      # Table already exists, race condition - that's fine
      :ok
  end
end
