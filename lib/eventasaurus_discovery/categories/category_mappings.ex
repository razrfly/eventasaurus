defmodule EventasaurusDiscovery.Categories.CategoryMappings do
  @moduledoc """
  Context module for managing category mappings.

  Provides CRUD operations and ETS-cached lookups for category mappings.
  The ETS cache eliminates per-request database queries, providing
  sub-millisecond lookup times.

  ## Cache Architecture

  - ETS table `:category_mappings_cache` stores all active mappings
  - Cache is loaded on application start and refreshed on changes
  - Lookups are O(1) for direct mappings, O(n) for pattern matching
  - Cache invalidation is automatic on create/update/delete

  ## Usage

      # Get mappings for a source (uses ETS cache)
      mappings = CategoryMappings.get_mappings("bandsintown")

      # Create a new mapping (auto-invalidates cache)
      {:ok, mapping} = CategoryMappings.create_mapping(%{
        source: "bandsintown",
        external_term: "hip-hop",
        mapping_type: "direct",
        category_slug: "concerts"
      })
  """

  import Ecto.Query, warn: false
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryMapping

  @ets_table :category_mappings_cache
  @defaults_source "_defaults"

  # ============================================================================
  # ETS Cache Management
  # ============================================================================

  @doc """
  Initializes the ETS cache table.
  Called from application supervisor.
  """
  def init_cache do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
      Logger.info("[CategoryMappings] ETS cache table created")
    end

    refresh_cache()
  end

  @doc """
  Refreshes the ETS cache from the database.
  Returns the number of mappings loaded.
  """
  def refresh_cache do
    # Ensure table exists
    ensure_table_exists()

    mappings = load_all_from_db()
    cache_data = build_cache_data(mappings)

    # Clear and repopulate
    :ets.delete_all_objects(@ets_table)

    Enum.each(cache_data, fn {key, value} ->
      :ets.insert(@ets_table, {key, value})
    end)

    count = length(mappings)
    Logger.info("[CategoryMappings] Cache refreshed with #{count} mappings")
    count
  end

  defp ensure_table_exists do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
      Logger.info("[CategoryMappings] ETS cache table created on demand")
    end
  end

  @doc """
  Gets cached mappings for a source.
  Returns `{direct_map, patterns_list}` tuple.

  - `direct_map` is %{normalized_term => category_slug}
  - `patterns_list` is [{regex, category_slugs}] ordered by priority desc
  """
  def get_cached_mappings(source) do
    source_key = {:source, source}
    defaults_key = {:source, @defaults_source}

    source_data = get_from_cache(source_key)
    defaults_data = get_from_cache(defaults_key)

    %{
      source: source_data,
      defaults: defaults_data
    }
  end

  defp get_from_cache(key) do
    if :ets.whereis(@ets_table) == :undefined do
      %{direct: %{}, patterns: []}
    else
      case :ets.lookup(@ets_table, key) do
        [{^key, data}] -> data
        [] -> %{direct: %{}, patterns: []}
      end
    end
  end

  defp load_all_from_db do
    Repo.all(
      from(m in CategoryMapping,
        where: m.is_active == true,
        order_by: [desc: m.priority, asc: m.id]
      )
    )
  end

  defp build_cache_data(mappings) do
    # Group by source
    by_source = Enum.group_by(mappings, & &1.source)

    Enum.map(by_source, fn {source, source_mappings} ->
      # Separate direct and pattern mappings
      {direct_mappings, pattern_mappings} =
        Enum.split_with(source_mappings, &(&1.mapping_type == "direct"))

      # Build direct lookup map
      direct_map =
        direct_mappings
        |> Enum.map(fn m -> {m.external_term, m.category_slug} end)
        |> Map.new()

      # Build pattern list with compiled regexes
      patterns =
        pattern_mappings
        |> Enum.map(fn m ->
          case Regex.compile(m.external_term, "i") do
            {:ok, regex} ->
              {regex, m.category_slug}

            {:error, reason} ->
              Logger.warning(
                "[CategoryMappings] Invalid regex pattern '#{m.external_term}' for source '#{source}': #{inspect(reason)}"
              )

              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {{:source, source}, %{direct: direct_map, patterns: patterns}}
    end)
  end

  # ============================================================================
  # Query Functions
  # ============================================================================

  @doc """
  Returns all category mappings.
  """
  def list_mappings do
    Repo.all(
      from(m in CategoryMapping,
        order_by: [asc: m.source, asc: m.mapping_type, asc: m.external_term]
      )
    )
  end

  @doc """
  Returns mappings filtered by source.
  """
  def list_mappings_by_source(source) do
    Repo.all(
      from(m in CategoryMapping,
        where: m.source == ^source,
        order_by: [asc: m.mapping_type, desc: m.priority, asc: m.external_term]
      )
    )
  end

  @doc """
  Returns mappings filtered by category slug.
  """
  def list_mappings_by_category(category_slug) do
    Repo.all(
      from(m in CategoryMapping,
        where: m.category_slug == ^category_slug,
        order_by: [asc: m.source, asc: m.external_term]
      )
    )
  end

  @doc """
  Returns distinct sources.
  """
  def list_sources do
    Repo.all(
      from(m in CategoryMapping,
        distinct: true,
        select: m.source,
        order_by: [asc: m.source]
      )
    )
  end

  @doc """
  Gets a single mapping by ID.
  """
  def get_mapping(id), do: Repo.get(CategoryMapping, id)

  @doc """
  Gets a single mapping by ID, raises if not found.
  """
  def get_mapping!(id), do: Repo.get!(CategoryMapping, id)

  @doc """
  Finds a mapping by source, term, and type.
  """
  def find_mapping(source, external_term, mapping_type) do
    Repo.get_by(CategoryMapping,
      source: source,
      external_term: external_term,
      mapping_type: mapping_type
    )
  end

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  @doc """
  Creates a new category mapping.
  Automatically refreshes the ETS cache on success.
  """
  def create_mapping(attrs) do
    result =
      %CategoryMapping{}
      |> CategoryMapping.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _mapping} ->
        refresh_cache()
        result

      error ->
        error
    end
  end

  @doc """
  Updates an existing category mapping.
  Automatically refreshes the ETS cache on success.
  """
  def update_mapping(%CategoryMapping{} = mapping, attrs) do
    result =
      mapping
      |> CategoryMapping.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _mapping} ->
        refresh_cache()
        result

      error ->
        error
    end
  end

  @doc """
  Deletes a category mapping.
  Automatically refreshes the ETS cache on success.
  """
  def delete_mapping(%CategoryMapping{} = mapping) do
    result = Repo.delete(mapping)

    case result do
      {:ok, _mapping} ->
        refresh_cache()
        result

      error ->
        error
    end
  end

  @doc """
  Soft-deletes a mapping by setting is_active to false.
  """
  def deactivate_mapping(%CategoryMapping{} = mapping) do
    update_mapping(mapping, %{is_active: false})
  end

  @doc """
  Reactivates a soft-deleted mapping.
  """
  def activate_mapping(%CategoryMapping{} = mapping) do
    update_mapping(mapping, %{is_active: true})
  end

  @doc """
  Returns a changeset for tracking changes.
  """
  def change_mapping(%CategoryMapping{} = mapping, attrs \\ %{}) do
    CategoryMapping.changeset(mapping, attrs)
  end

  # ============================================================================
  # Bulk Operations (for YAML import)
  # ============================================================================

  @doc """
  Imports multiple mappings from a list of attributes.
  Uses upsert to handle duplicates gracefully.
  Returns `{:ok, %{inserted: n, updated: n, errors: []}}`.
  """
  def import_mappings(mappings_list) do
    results =
      Enum.reduce(mappings_list, %{inserted: 0, updated: 0, errors: []}, fn attrs, acc ->
        changeset = CategoryMapping.import_changeset(%CategoryMapping{}, attrs)

        case Repo.insert(changeset,
               on_conflict: {:replace, [:category_slug, :priority, :is_active, :updated_at]},
               conflict_target: [:source, :external_term, :mapping_type],
               returning: true
             ) do
          {:ok, _mapping} ->
            # Can't easily distinguish insert vs update with on_conflict, count as inserted
            %{acc | inserted: acc.inserted + 1}

          {:error, changeset} ->
            error_msg = format_changeset_errors(changeset)
            %{acc | errors: [{attrs, error_msg} | acc.errors]}
        end
      end)

    # Refresh cache after bulk import
    refresh_cache()

    {:ok, results}
  end

  @doc """
  Deletes all mappings for a specific source.
  Useful for re-importing a source's YAML file.
  """
  def delete_all_by_source(source) do
    {count, _} =
      Repo.delete_all(from(m in CategoryMapping, where: m.source == ^source))

    refresh_cache()
    {:ok, count}
  end

  @doc """
  Returns mapping statistics.
  """
  def get_stats do
    query =
      from(m in CategoryMapping,
        where: m.is_active == true,
        group_by: [m.source, m.mapping_type],
        select: %{
          source: m.source,
          mapping_type: m.mapping_type,
          count: count(m.id)
        }
      )

    stats = Repo.all(query)

    # Aggregate
    total_direct =
      stats
      |> Enum.filter(&(&1.mapping_type == "direct"))
      |> Enum.map(& &1.count)
      |> Enum.sum()

    total_patterns =
      stats
      |> Enum.filter(&(&1.mapping_type == "pattern"))
      |> Enum.map(& &1.count)
      |> Enum.sum()

    by_source =
      stats
      |> Enum.group_by(& &1.source)
      |> Enum.map(fn {source, entries} ->
        direct = Enum.find(entries, %{count: 0}, &(&1.mapping_type == "direct")).count
        patterns = Enum.find(entries, %{count: 0}, &(&1.mapping_type == "pattern")).count
        {source, %{direct: direct, patterns: patterns}}
      end)
      |> Map.new()

    %{
      total_direct: total_direct,
      total_patterns: total_patterns,
      total: total_direct + total_patterns,
      by_source: by_source
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
