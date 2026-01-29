defmodule EventasaurusDiscovery.Categories.CategoryMapper do
  @moduledoc """
  Maps source-specific categories to internal category system.

  Supports two backends:
  - YAML files (legacy, default)
  - Database with ETS caching (new, via USE_DB_MAPPINGS=true)

  ## Configuration

      # Enable database-backed mappings (in config.exs or runtime.exs)
      # NOTE: Uses :eventasaurus namespace (NOT :eventasaurus_discovery)
      config :eventasaurus, :discovery,
        use_db_mappings: true

  The database backend provides sub-millisecond lookups via ETS caching
  and allows dynamic mapping updates without redeployment.
  """

  require Logger
  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryMappings

  @defaults_file "_defaults.yml"

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

    # Choose backend based on config
    {source_mappings, defaults_mappings} =
      if use_db_mappings?() do
        load_from_db(source_string)
      else
        load_from_yaml(source_string)
      end

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

  @doc """
  Returns whether database-backed mappings are enabled.
  """
  def use_db_mappings? do
    discovery_config = Application.get_env(:eventasaurus, :discovery, [])
    Keyword.get(discovery_config, :use_db_mappings, false)
  end

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
  # YAML Backend (legacy)
  # ============================================================================

  defp load_from_yaml(source_string) do
    mappings = load_all_mappings_from_yaml()

    source_mappings = Map.get(mappings, source_string, %{})
    defaults_mappings = Map.get(mappings, "defaults", %{})

    {source_mappings, defaults_mappings}
  end

  # ============================================================================
  # YAML Loading Functions
  # ============================================================================

  defp load_all_mappings_from_yaml do
    # Use priv directory for production compatibility
    priv_dir = :code.priv_dir(:eventasaurus)
    config_path = Path.join(priv_dir, "category_mappings")

    if File.dir?(config_path) do
      config_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yml"))
      |> Enum.reduce(%{}, fn file, acc ->
        source_key = get_source_key(file)
        file_path = Path.join(config_path, file)

        case load_yaml_file(file_path) do
          {:ok, mappings} ->
            Map.put(acc, source_key, mappings)

          {:error, reason} ->
            Logger.error("Failed to load #{file}: #{inspect(reason)}")
            acc
        end
      end)
    else
      Logger.warning("Category mappings directory not found: #{config_path}")
      %{}
    end
  end

  defp get_source_key(filename) do
    case filename do
      @defaults_file -> "defaults"
      other -> Path.basename(other, ".yml")
    end
  end

  defp load_yaml_file(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, %{"mappings" => mappings} = data} ->
        # Convert mappings to internal format
        processed_mappings = %{
          "direct" => process_direct_mappings(mappings),
          "patterns" => process_patterns(data["patterns"] || [])
        }

        {:ok, processed_mappings}

      {:ok, _} ->
        {:error, "Invalid YAML structure"}

      error ->
        error
    end
  end

  defp process_direct_mappings(mappings) when is_map(mappings) do
    mappings
    |> Enum.map(fn {key, value} -> {String.downcase(key), to_string(value)} end)
    |> Map.new()
  end

  defp process_direct_mappings(_), do: %{}

  defp process_patterns(patterns) when is_list(patterns) do
    Enum.map(patterns, fn pattern ->
      %{
        "match" => pattern["match"],
        "categories" => pattern["categories"] || []
      }
    end)
  end

  defp process_patterns(_), do: []

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

  # Handle YAML backend: %{"match" => pattern, "categories" => [...]} maps
  defp try_match_pattern(normalized_category, %{"match" => pattern, "categories" => categories}, category_lookup) do
    if matches_pattern?(normalized_category, pattern) do
      categories
      |> Enum.map(fn cat -> Map.get(category_lookup, cat) end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.filter(fn {_id, active} -> active end)
      |> Enum.map(fn {id, _active} -> {id, false} end)
    else
      []
    end
  end

  # Fallback for unexpected pattern formats
  defp try_match_pattern(_normalized_category, _pattern_entry, _category_lookup), do: []

  defp matches_pattern?(text, pattern) do
    # Try compiling as a regex first (for patterns like "comedy|stand.?up")
    case Regex.compile(pattern, "i") do
      {:ok, regex} ->
        Regex.match?(regex, text)

      {:error, _} ->
        # Fallback: treat as glob pattern with * and ?
        glob_pattern =
          pattern
          |> Regex.escape()
          |> String.replace(~r/\\\*/, ".*")
          |> String.replace(~r/\\\?/, ".")

        case Regex.compile(glob_pattern, "i") do
          {:ok, regex} -> Regex.match?(regex, text)
          _ -> false
        end
    end
  end

  # ============================================================================
  # Shared Logic (used by both backends)
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
