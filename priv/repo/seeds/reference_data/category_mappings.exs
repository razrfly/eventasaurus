# Category mappings seeds for EventasaurusDiscovery
#
# This imports category mappings from the archived YAML files.
# Must run AFTER categories.exs since mappings reference category slugs.
#
# The YAML files are located at: priv/category_mappings_archived/

alias EventasaurusDiscovery.Categories.CategoryMappings

defmodule CategoryMappingsSeeder do
  @moduledoc false

  @defaults_file "_defaults.yml"

  def seed do
    yaml_files = load_yaml_files()

    if Enum.empty?(yaml_files) do
      IO.puts("⚠️  No YAML files found in priv/category_mappings_archived/")
      :ok
    else
      results =
        Enum.map(yaml_files, fn {source, file_path} ->
          process_file(source, file_path)
        end)

      print_summary(results)
    end
  end

  defp load_yaml_files do
    priv_dir = :code.priv_dir(:eventasaurus)
    config_path = Path.join(priv_dir, "category_mappings_archived")

    if File.dir?(config_path) do
      config_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yml"))
      |> Enum.map(fn file ->
        source_key = get_source_key(file)
        {source_key, Path.join(config_path, file)}
      end)
      |> Enum.sort_by(fn {source, _} ->
        # Process _defaults first
        if source == "_defaults", do: "", else: source
      end)
    else
      []
    end
  end

  defp get_source_key(filename) do
    case filename do
      @defaults_file -> "_defaults"
      other -> Path.basename(other, ".yml")
    end
  end

  defp process_file(source, file_path) do
    case YamlElixir.read_from_file(file_path) do
      {:ok, %{"mappings" => mappings} = data} ->
        patterns = data["patterns"] || []

        direct_attrs = build_direct_attrs(source, mappings)
        pattern_attrs = build_pattern_attrs(source, patterns)
        all_attrs = direct_attrs ++ pattern_attrs

        case CategoryMappings.import_mappings(all_attrs) do
          {:ok, result} ->
            %{
              source: source,
              direct: length(direct_attrs),
              patterns: length(pattern_attrs),
              imported: result.inserted,
              errors: result.errors,
              status: if(Enum.empty?(result.errors), do: :success, else: :partial)
            }

          {:error, reason} ->
            %{source: source, status: :error, error: reason}
        end

      {:ok, _} ->
        %{source: source, status: :error, error: "Invalid YAML structure (missing 'mappings' key)"}

      {:error, reason} ->
        %{source: source, status: :error, error: reason}
    end
  end

  defp build_direct_attrs(source, mappings) when is_map(mappings) do
    Enum.map(mappings, fn {term, category_slug} ->
      %{
        source: source,
        external_term: String.downcase(to_string(term)),
        mapping_type: "direct",
        category_slug: to_string(category_slug),
        priority: 0,
        is_active: true,
        metadata: %{imported_from: "yaml_seed", imported_at: DateTime.utc_now() |> DateTime.to_iso8601()}
      }
    end)
  end

  defp build_direct_attrs(_source, _), do: []

  defp build_pattern_attrs(source, patterns) when is_list(patterns) do
    patterns
    |> Enum.with_index()
    |> Enum.flat_map(fn {pattern, index} ->
      match_pattern = pattern["match"]
      categories = pattern["categories"] || []

      # Higher index = lower priority (first patterns in file are higher priority)
      priority = 100 - index

      Enum.map(categories, fn category_slug ->
        %{
          source: source,
          external_term: match_pattern,
          mapping_type: "pattern",
          category_slug: to_string(category_slug),
          priority: priority,
          is_active: true,
          metadata: %{imported_from: "yaml_seed", imported_at: DateTime.utc_now() |> DateTime.to_iso8601()}
        }
      end)
    end)
  end

  defp build_pattern_attrs(_source, _), do: []

  defp print_summary(results) do
    successful = Enum.filter(results, &(&1.status in [:success]))
    partial = Enum.filter(results, &(&1.status == :partial))
    errors = Enum.filter(results, &(&1.status == :error))

    total_direct = Enum.map(successful ++ partial, &Map.get(&1, :direct, 0)) |> Enum.sum()
    total_patterns = Enum.map(successful ++ partial, &Map.get(&1, :patterns, 0)) |> Enum.sum()
    total_imported = Enum.map(successful ++ partial, &Map.get(&1, :imported, 0)) |> Enum.sum()

    IO.puts("   Sources: #{length(results)} (#{length(successful)} success, #{length(partial)} partial, #{length(errors)} errors)")
    IO.puts("   Mappings: #{total_imported} imported (#{total_direct} direct, #{total_patterns} patterns)")

    if not Enum.empty?(errors) do
      Enum.each(errors, fn result ->
        IO.puts("   ❌ #{result.source}: #{inspect(result.error)}")
      end)
    end

    :ok
  end
end

CategoryMappingsSeeder.seed()

IO.puts("✅ Category mappings seeded successfully!")
