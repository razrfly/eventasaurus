defmodule EventasaurusDiscovery.Categories.CategoryMapper do
  @moduledoc """
  Maps source-specific categories to internal category system.

  Uses database-backed mappings with ETS caching for sub-millisecond lookups.
  Mappings can be managed via the admin UI at `/admin/category-mappings`.

  ## Migration History

  Prior to January 2025, this module supported YAML file-based mappings.
  YAML files have been archived to `priv/category_mappings_archived/` and
  the system now exclusively uses database-backed mappings.

  See `EventasaurusApp.ReleaseTasks.migrate_yaml_mappings/0` for the migration task.
  """

  require Logger
  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryMappings

  @doc """
  Maps source-specific categories to internal category IDs.
  Returns a list of {category_id, is_primary} tuples.

  ## Parameters
    - source: The source system (e.g., "ticketmaster", "karnet", "bandsintown")
    - source_categories: List of category strings from the source
    - category_lookup: Map of category slug => {id, is_active}

  ## Examples
    iex> map_categories("ticketmaster", ["Music", "Rock"], %{"concerts" => {1, true}})
    [{1, true}]
  """
  def map_categories(source, source_categories, category_lookup)
      when is_list(source_categories) do
    source_string = to_string(source)

    # Load mappings from database via ETS cache
    {source_mappings, defaults_mappings} = load_from_db(source_string)

    # Map each source category
    mapped_categories =
      source_categories
      |> Enum.flat_map(fn category ->
        map_single_category(category, source_mappings, defaults_mappings, category_lookup)
      end)
      # Remove duplicates by category ID
      |> Enum.uniq_by(&elem(&1, 0))
      |> mark_primary_category()

    # If no categories mapped, return empty (caller should add "other" fallback)
    mapped_categories
  end

  def map_categories(_source, _source_categories, _category_lookup), do: []

  # ============================================================================
  # Database Backend (ETS-cached)
  # ============================================================================

  defp load_from_db(source_string) do
    cached = CategoryMappings.get_cached_mappings(source_string)

    source_mappings = %{
      "direct" => cached.source.direct,
      "patterns" => cached.source.patterns
    }

    defaults_mappings = %{
      "direct" => cached.defaults.direct,
      "patterns" => cached.defaults.patterns
    }

    {source_mappings, defaults_mappings}
  end

  # ============================================================================
  # Category Mapping Logic
  # ============================================================================

  defp map_single_category(category, source_mappings, defaults_mappings, category_lookup) do
    normalized = String.downcase(String.trim(category))

    # Try direct mapping from source first
    case try_direct_mapping(normalized, source_mappings, category_lookup) do
      [] ->
        # Try pattern matching from source
        case try_pattern_mapping(normalized, source_mappings, category_lookup) do
          [] ->
            # Try direct mapping from defaults
            case try_direct_mapping(normalized, defaults_mappings, category_lookup) do
              [] ->
                # Try pattern matching from defaults
                try_pattern_mapping(normalized, defaults_mappings, category_lookup)

              result ->
                result
            end

          result ->
            result
        end

      result ->
        result
    end
  end

  defp try_direct_mapping(normalized_category, mappings, category_lookup) do
    direct_mappings = Map.get(mappings, "direct", %{})

    case Map.get(direct_mappings, normalized_category) do
      nil ->
        []

      internal_category ->
        case Map.get(category_lookup, internal_category) do
          # Will be marked as primary later
          {id, true} -> [{id, false}]
          _ -> []
        end
    end
  end

  defp try_pattern_mapping(normalized_category, mappings, category_lookup) do
    patterns = Map.get(mappings, "patterns", [])

    patterns
    |> Enum.flat_map(fn pattern_entry ->
      try_match_pattern(normalized_category, pattern_entry, category_lookup)
    end)
  end

  # Handle DB backend: {compiled_regex, category_slug} tuples
  defp try_match_pattern(normalized_category, {%Regex{} = regex, category_slug}, category_lookup) do
    if Regex.match?(regex, normalized_category) do
      case Map.get(category_lookup, category_slug) do
        {id, true} -> [{id, false}]
        _ -> []
      end
    else
      []
    end
  end

  # Fallback for unexpected pattern formats
  defp try_match_pattern(_normalized_category, _pattern_entry, _category_lookup), do: []

  # ============================================================================
  # Primary Category Selection
  # ============================================================================

  defp mark_primary_category([]), do: []

  defp mark_primary_category(categories) do
    # Get the "Other" category ID
    other_id = get_other_category_id()

    # Separate "Other" categories from real categories
    {real_categories, other_categories} =
      Enum.split_with(categories, fn {id, _} -> id != other_id end)

    case real_categories do
      [] ->
        # Only "Other" categories exist, mark the first as primary
        case other_categories do
          [{id, _} | rest] ->
            [{id, true} | Enum.map(rest, fn {id, _} -> {id, false} end)]

          [] ->
            []
        end

      [{first_id, _} | rest_real] ->
        # Real categories exist, mark the first real category as primary
        # and all others (including "Other") as secondary
        primary_and_real = [{first_id, true} | Enum.map(rest_real, fn {id, _} -> {id, false} end)]
        all_others = Enum.map(other_categories, fn {id, _} -> {id, false} end)
        primary_and_real ++ all_others
    end
  end

  defp get_other_category_id do
    # Query for the "Other" category ID
    # Using the same query pattern as in CategoryExtractor
    query =
      from(c in EventasaurusDiscovery.Categories.Category,
        where: c.slug == "other" and c.is_active == true,
        select: c.id,
        limit: 1
      )

    Repo.one(query)
  end
end
