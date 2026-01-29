defmodule Mix.Tasks.Mappings.MigrateYaml do
  @moduledoc """
  Migrates category mappings from YAML files to the database.

  This task reads all YAML files from `priv/category_mappings/` and imports
  them into the `category_mappings` table.

  ## Usage

      # Dry run - show what would be imported
      mix mappings.migrate_yaml --dry-run

      # Import all YAML files
      mix mappings.migrate_yaml

      # Import a specific source only
      mix mappings.migrate_yaml --source bandsintown

      # Clear existing mappings for a source before importing
      mix mappings.migrate_yaml --source bandsintown --clear

      # Clear ALL mappings and re-import everything
      mix mappings.migrate_yaml --clear-all

  ## Options

      --dry-run      Show what would be imported without making changes
      --source NAME  Only import the specified source
      --clear        Clear existing mappings for the source before importing
      --clear-all    Clear ALL existing mappings before importing
      --verbose      Show detailed output for each mapping
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Categories.CategoryMappings

  @shortdoc "Migrate category mappings from YAML to database"

  @defaults_file "_defaults.yml"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          dry_run: :boolean,
          source: :string,
          clear: :boolean,
          clear_all: :boolean,
          verbose: :boolean
        ],
        aliases: [d: :dry_run, s: :source, c: :clear, v: :verbose]
      )

    dry_run? = Keyword.get(opts, :dry_run, false)
    source_filter = Keyword.get(opts, :source)
    clear? = Keyword.get(opts, :clear, false)
    clear_all? = Keyword.get(opts, :clear_all, false)
    verbose? = Keyword.get(opts, :verbose, false)

    # Start application for DB access
    Mix.Task.run("app.start")

    IO.puts("\n#{IO.ANSI.cyan()}📦 YAML to Database Migration#{IO.ANSI.reset()}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    if dry_run? do
      IO.puts("#{IO.ANSI.yellow()}🔍 DRY RUN MODE - No changes will be made#{IO.ANSI.reset()}\n")
    end

    # Load YAML files first to validate before any destructive operations
    yaml_files = load_yaml_files(source_filter)

    if Enum.empty?(yaml_files) do
      IO.puts("#{IO.ANSI.yellow()}⚠️  No YAML files found#{IO.ANSI.reset()}")
      System.halt(1)
    end

    # Clear existing mappings if requested (only after validating YAML files exist)
    if clear_all? and not dry_run? do
      IO.puts("#{IO.ANSI.red()}🗑️  Clearing ALL existing mappings...#{IO.ANSI.reset()}")
      clear_all_mappings()
      IO.puts("")
    end

    # Process each file
    results =
      Enum.map(yaml_files, fn {source, file_path} ->
        process_file(source, file_path, %{
          dry_run: dry_run?,
          clear: clear?,
          verbose: verbose?
        })
      end)

    # Print summary
    print_summary(results, dry_run?)
  end

  defp load_yaml_files(source_filter) do
    priv_dir = :code.priv_dir(:eventasaurus)
    config_path = Path.join(priv_dir, "category_mappings")

    if File.dir?(config_path) do
      config_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yml"))
      |> Enum.map(fn file ->
        source_key = get_source_key(file)
        {source_key, Path.join(config_path, file)}
      end)
      |> Enum.filter(fn {source, _path} ->
        is_nil(source_filter) or source == source_filter
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

  defp process_file(source, file_path, opts) do
    IO.puts("#{IO.ANSI.bright()}📁 Processing: #{source}#{IO.ANSI.reset()}")
    IO.puts("   File: #{file_path}")

    case YamlElixir.read_from_file(file_path) do
      {:ok, %{"mappings" => mappings} = data} ->
        patterns = data["patterns"] || []

        # Clear if requested
        if opts.clear and not opts.dry_run do
          IO.puts("   #{IO.ANSI.yellow()}Clearing existing mappings...#{IO.ANSI.reset()}")
          {:ok, cleared} = CategoryMappings.delete_all_by_source(source)
          IO.puts("   Cleared #{cleared} existing mappings")
        end

        # Build mapping attributes
        direct_attrs = build_direct_attrs(source, mappings)
        pattern_attrs = build_pattern_attrs(source, patterns)
        all_attrs = direct_attrs ++ pattern_attrs

        if opts.verbose do
          IO.puts("\n   Direct mappings:")

          Enum.take(direct_attrs, 5)
          |> Enum.each(fn attrs ->
            IO.puts("     #{attrs.external_term} → #{attrs.category_slug}")
          end)

          if length(direct_attrs) > 5 do
            IO.puts("     ... and #{length(direct_attrs) - 5} more")
          end

          IO.puts("\n   Pattern mappings:")

          Enum.take(pattern_attrs, 3)
          |> Enum.each(fn attrs ->
            IO.puts("     /#{attrs.external_term}/ → #{attrs.category_slug}")
          end)

          if length(pattern_attrs) > 3 do
            IO.puts("     ... and #{length(pattern_attrs) - 3} more")
          end
        end

        # Import or dry run
        result =
          if opts.dry_run do
            %{
              source: source,
              direct: length(direct_attrs),
              patterns: length(pattern_attrs),
              status: :dry_run
            }
          else
            {:ok, import_result} = CategoryMappings.import_mappings(all_attrs)

            %{
              source: source,
              direct: length(direct_attrs),
              patterns: length(pattern_attrs),
              imported: import_result.inserted,
              errors: import_result.errors,
              status: if(Enum.empty?(import_result.errors), do: :success, else: :partial)
            }
          end

        status_icon =
          case result.status do
            :dry_run -> "📋"
            :success -> "✅"
            :partial -> "⚠️"
          end

        IO.puts(
          "   #{status_icon} Direct: #{result.direct}, Patterns: #{result.patterns}" <>
            if(result[:imported], do: ", Imported: #{result.imported}", else: "")
        )

        if result[:errors] && not Enum.empty?(result.errors) do
          IO.puts("   #{IO.ANSI.red()}Errors:#{IO.ANSI.reset()}")

          Enum.take(result.errors, 3)
          |> Enum.each(fn {attrs, msg} ->
            IO.puts("     - #{attrs[:external_term]}: #{msg}")
          end)
        end

        IO.puts("")
        result

      {:ok, _} ->
        IO.puts("   #{IO.ANSI.red()}❌ Invalid YAML structure (missing 'mappings' key)#{IO.ANSI.reset()}\n")
        %{source: source, status: :error, error: "Invalid YAML structure"}

      {:error, reason} ->
        IO.puts("   #{IO.ANSI.red()}❌ Failed to read: #{inspect(reason)}#{IO.ANSI.reset()}\n")
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
        metadata: %{imported_from: "yaml", imported_at: DateTime.utc_now() |> DateTime.to_iso8601()}
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
          metadata: %{imported_from: "yaml", imported_at: DateTime.utc_now() |> DateTime.to_iso8601()}
        }
      end)
    end)
  end

  defp build_pattern_attrs(_source, _), do: []

  defp clear_all_mappings do
    import Ecto.Query
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Categories.CategoryMapping

    {count, _} = Repo.delete_all(from(m in CategoryMapping))
    IO.puts("   Cleared #{count} total mappings")
  end

  defp print_summary(results, dry_run?) do
    IO.puts("#{IO.ANSI.bright()}📊 Summary#{IO.ANSI.reset()}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    successful = Enum.filter(results, &(&1.status in [:success, :dry_run]))
    partial = Enum.filter(results, &(&1.status == :partial))
    errors = Enum.filter(results, &(&1.status == :error))

    total_direct = Enum.map(successful ++ partial, & &1.direct) |> Enum.sum()
    total_patterns = Enum.map(successful ++ partial, & &1.patterns) |> Enum.sum()

    IO.puts("  Sources processed: #{length(results)}")
    IO.puts("  Successful: #{length(successful)}")

    if not Enum.empty?(partial) do
      IO.puts("  #{IO.ANSI.yellow()}Partial (with errors): #{length(partial)}#{IO.ANSI.reset()}")
    end

    if not Enum.empty?(errors) do
      IO.puts("  #{IO.ANSI.red()}Failed: #{length(errors)}#{IO.ANSI.reset()}")
    end

    IO.puts("")
    IO.puts("  Total mappings: #{total_direct + total_patterns}")
    IO.puts("    Direct: #{total_direct}")
    IO.puts("    Patterns: #{total_patterns}")

    if dry_run? do
      IO.puts("\n#{IO.ANSI.yellow()}Run without --dry-run to import these mappings#{IO.ANSI.reset()}")
    else
      IO.puts("\n#{IO.ANSI.green()}✅ Migration complete!#{IO.ANSI.reset()}")

      # Show current DB stats
      stats = CategoryMappings.get_stats()
      IO.puts("\nDatabase now contains:")
      IO.puts("  Total: #{stats.total} mappings (#{stats.total_direct} direct, #{stats.total_patterns} patterns)")
    end

    IO.puts("")
  end
end
