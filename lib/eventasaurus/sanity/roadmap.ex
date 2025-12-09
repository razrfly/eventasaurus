defmodule Eventasaurus.Sanity.Roadmap do
  @moduledoc """
  Service module for roadmap operations.
  Transforms Sanity data to roadmap component format and handles caching.

  Status mapping to columns:
  - "in_progress" → Now (currently being worked on)
  - "planned" → Next (coming soon)
  - "considering" → Later (under consideration)
  """

  require Logger

  alias Eventasaurus.Sanity.Client

  @cache_table :sanity_roadmap_cache
  @cache_ttl_ms :timer.minutes(5)

  # Status to column mapping
  @status_columns %{
    "in_progress" => :now,
    "planned" => :next,
    "considering" => :later
  }

  # Status display names for the UI
  @status_display %{
    "in_progress" => "In Progress",
    "planned" => "Planned",
    "considering" => "Considering"
  }

  @doc """
  Gets all roadmap entries grouped by column (now, next, later).
  Returns entries formatted for RoadmapFeaturesComponents.

  ## Returns

  - `{:ok, %{now: [...], next: [...], later: [...]}}` - Grouped roadmap entries
  - `{:error, reason}` - Error with reason

  ## Example

      {:ok, %{now: now_items, next: next_items, later: later_items}} = Roadmap.list_entries()
  """
  @spec list_entries() :: {:ok, map()} | {:error, atom() | tuple()}
  def list_entries do
    case get_cached_entries() do
      {:ok, grouped} ->
        Logger.debug("Roadmap cache hit")
        {:ok, grouped}

      :miss ->
        Logger.debug("Roadmap cache miss - fetching from Sanity")
        fetch_and_cache_entries()
    end
  end

  @doc """
  Clears the roadmap cache.
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

  defp fetch_and_cache_entries do
    case Client.list_roadmap_entries() do
      {:ok, raw_entries} ->
        entries = Enum.map(raw_entries, &transform_entry/1)
        grouped = group_by_column(entries)
        cache_entries(grouped)
        {:ok, grouped}

      error ->
        error
    end
  end

  defp group_by_column(entries) do
    grouped =
      entries
      |> Enum.group_by(fn entry -> entry.column end)

    %{
      now: Map.get(grouped, :now, []),
      next: Map.get(grouped, :next, []),
      later: Map.get(grouped, :later, [])
    }
  end

  @doc """
  Transforms a Sanity roadmap entry to component format.

  ## Sanity Format (input)

      %{
        "_id" => "abc123",
        "title" => "Native Mobile Apps",
        "status" => "planned",
        "summary" => "iOS and Android apps...",
        "tags" => ["mobile", "platform"],
        "image" => %{"asset" => %{"url" => "https://..."}}
      }

  ## Component Format (output)

      %{
        id: "abc123",
        title: "Native Mobile Apps",
        description: "iOS and Android apps...",
        status: "Planned",
        tags: ["Mobile", "Platform"],
        column: :next,
        image: "https://..."
      }
  """
  @spec transform_entry(map()) :: map()
  def transform_entry(entry) do
    status = entry["status"] || "considering"

    %{
      id: entry["_id"],
      title: entry["title"],
      description: entry["summary"] || "",
      status: Map.get(@status_display, status, "Considering"),
      tags: transform_tags(entry["tags"] || []),
      column: Map.get(@status_columns, status, :later),
      image: get_image_url(entry["image"])
    }
  end

  defp transform_tags(tags) when is_list(tags) do
    # Capitalize first letter of each tag for display
    Enum.map(tags, fn tag ->
      tag
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")
    end)
  end

  defp transform_tags(_), do: []

  defp get_image_url(nil), do: nil
  defp get_image_url(%{"asset" => %{"url" => url}}), do: url
  defp get_image_url(_), do: nil

  # ETS-based caching

  defp get_cached_entries do
    ensure_cache_table_exists()

    case :ets.lookup(@cache_table, :entries) do
      [{:entries, grouped, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          {:ok, grouped}
        else
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_entries(grouped) do
    ensure_cache_table_exists()
    :ets.insert(@cache_table, {:entries, grouped, System.monotonic_time(:millisecond)})
  rescue
    ArgumentError ->
      Logger.warning("Failed to cache roadmap entries")
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
