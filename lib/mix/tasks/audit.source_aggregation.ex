defmodule Mix.Tasks.Audit.SourceAggregation do
  @moduledoc """
  Audit source aggregation configuration across code and database.

  Compares `source_config/0` definitions in code with actual database records
  to identify mismatches in aggregation settings.

  ## Usage

      # Check all sources
      mix audit.source_aggregation

      # Fix mismatches by updating database to match code
      mix audit.source_aggregation --fix

  ## What It Checks

  For each source, compares:
  - `aggregate_on_index` - Whether events should be aggregated on index pages
  - `aggregation_type` - Schema.org event type (SocialEvent, ScreeningEvent, FoodEvent)
  - `domains` - Event domain categories

  ## Output

  Shows a table of all sources with their code config vs database values,
  highlighting any mismatches in red.
  """

  use Mix.Task
  require Logger

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source

  @shortdoc "Audit source aggregation configuration"

  # Map of source slugs to their source_config modules
  # Each module must have a source_config/0 function
  @source_configs %{
    "inquizition" => EventasaurusDiscovery.Sources.Inquizition.Jobs.SyncJob,
    "quizmeisters" => EventasaurusDiscovery.Sources.Quizmeisters.Jobs.SyncJob,
    "speed-quizzing" => EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.SyncJob,
    "question-one" => EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob,
    "geeks_who_drink" => EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob,
    "pubquiz" => EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob,
    "cinema_city" => EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob,
    "repertuary" => EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob,
    "week_pl" => EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob,
    "bandsintown" => EventasaurusDiscovery.Sources.Bandsintown.Config,
    "ticketmaster" => EventasaurusDiscovery.Sources.Ticketmaster.Config,
    "karnet" => EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob,
    "waw4free" => EventasaurusDiscovery.Sources.Waw4free.Jobs.SyncJob,
    "resident-advisor" => EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob,
    "sortiraparis" => EventasaurusDiscovery.Sources.Sortiraparis.Jobs.SyncJob
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [fix: :boolean],
        aliases: [f: :fix]
      )

    fix_mode = opts[:fix] || false

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🔍 Source Aggregation Audit" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 100) <> IO.ANSI.reset())
    IO.puts("")

    # Get all sources from database
    db_sources =
      from(s in Source, order_by: [asc: s.slug])
      |> Repo.all()
      |> Map.new(fn s -> {s.slug, s} end)

    # Audit each configured source
    results =
      @source_configs
      |> Enum.sort_by(fn {slug, _} -> slug end)
      |> Enum.map(fn {slug, module} ->
        audit_source(slug, module, db_sources)
      end)

    # Display results
    display_results(results)

    # Summary
    mismatches = Enum.filter(results, fn r -> r.status == :mismatch end)
    missing = Enum.filter(results, fn r -> r.status == :missing end)
    ok = Enum.filter(results, fn r -> r.status == :ok end)

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 100) <> IO.ANSI.reset())
    IO.puts("")

    IO.puts("Summary:")
    IO.puts("  #{IO.ANSI.green()}✅ OK: #{length(ok)}#{IO.ANSI.reset()}")
    IO.puts("  #{IO.ANSI.yellow()}⚠️  Missing from DB: #{length(missing)}#{IO.ANSI.reset()}")
    IO.puts("  #{IO.ANSI.red()}❌ Mismatched: #{length(mismatches)}#{IO.ANSI.reset()}")
    IO.puts("")

    # Fix mode
    if fix_mode && (length(mismatches) > 0 || length(missing) > 0) do
      fix_issues(mismatches ++ missing)
    else
      if length(mismatches) > 0 || length(missing) > 0 do
        IO.puts(
          IO.ANSI.blue() <>
            "💡 Run with --fix to update database to match code configuration" <> IO.ANSI.reset()
        )

        IO.puts("")
      end
    end

    # Check for sources in DB but not in code
    code_slugs = Map.keys(@source_configs) |> MapSet.new()
    db_slugs = Map.keys(db_sources) |> MapSet.new()
    orphaned = MapSet.difference(db_slugs, code_slugs) |> MapSet.to_list()

    if length(orphaned) > 0 do
      IO.puts(IO.ANSI.yellow() <> "⚠️  Sources in DB but not in audit config:" <> IO.ANSI.reset())

      Enum.each(orphaned, fn slug ->
        source = db_sources[slug]

        IO.puts(
          "  - #{slug} (aggregate: #{source.aggregate_on_index}, type: #{source.aggregation_type || "nil"})"
        )
      end)

      IO.puts("")
    end
  end

  defp audit_source(slug, module, db_sources) do
    # Get config from code
    code_config =
      try do
        config = module.source_config()

        %{
          aggregate_on_index: get_val(config, :aggregate_on_index),
          aggregation_type: get_val(config, :aggregation_type),
          domains: get_val(config, :domains)
        }
      rescue
        _ ->
          %{aggregate_on_index: nil, aggregation_type: nil, domains: nil}
      end

    # Get from database
    case Map.get(db_sources, slug) do
      nil ->
        %{
          slug: slug,
          status: :missing,
          code: code_config,
          db: nil,
          mismatches: []
        }

      db_source ->
        db_config = %{
          aggregate_on_index: db_source.aggregate_on_index,
          aggregation_type: db_source.aggregation_type,
          domains: db_source.domains
        }

        mismatches = find_mismatches(code_config, db_config)

        %{
          slug: slug,
          status: if(Enum.empty?(mismatches), do: :ok, else: :mismatch),
          code: code_config,
          db: db_config,
          mismatches: mismatches
        }
    end
  end

  defp find_mismatches(code, db) do
    []
    |> maybe_add_mismatch(:aggregate_on_index, code.aggregate_on_index, db.aggregate_on_index)
    |> maybe_add_mismatch(:aggregation_type, code.aggregation_type, db.aggregation_type)
    |> maybe_add_mismatch(:domains, code.domains, db.domains)
  end

  defp maybe_add_mismatch(acc, field, code_val, db_val) do
    # Normalize for comparison
    code_normalized = normalize_for_comparison(code_val)
    db_normalized = normalize_for_comparison(db_val)

    if code_normalized != db_normalized do
      [{field, code_val, db_val} | acc]
    else
      acc
    end
  end

  defp normalize_for_comparison(nil), do: nil
  defp normalize_for_comparison(val) when is_list(val), do: Enum.sort(val)
  defp normalize_for_comparison(val), do: val

  defp display_results(results) do
    # Header
    IO.puts(
      "  #{pad("Source", 20)} #{pad("Agg?", 6)} #{pad("Type", 18)} #{pad("Domains", 30)} Status"
    )

    IO.puts("  #{String.duplicate("─", 95)}")

    Enum.each(results, fn result ->
      display_result_row(result)
    end)
  end

  defp display_result_row(%{status: :missing} = result) do
    code = result.code

    IO.puts(
      "  #{pad(result.slug, 20)} " <>
        "#{pad(format_bool(code.aggregate_on_index), 6)} " <>
        "#{pad(code.aggregation_type || "-", 18)} " <>
        "#{pad(format_domains(code.domains), 30)} " <>
        IO.ANSI.yellow() <> "⚠️  NOT IN DB" <> IO.ANSI.reset()
    )
  end

  defp display_result_row(%{status: :ok} = result) do
    db = result.db

    IO.puts(
      "  #{pad(result.slug, 20)} " <>
        "#{pad(format_bool(db.aggregate_on_index), 6)} " <>
        "#{pad(db.aggregation_type || "-", 18)} " <>
        "#{pad(format_domains(db.domains), 30)} " <>
        IO.ANSI.green() <> "✅ OK" <> IO.ANSI.reset()
    )
  end

  defp display_result_row(%{status: :mismatch} = result) do
    code = result.code
    db = result.db

    # Show code values
    IO.puts(
      "  #{pad(result.slug, 20)} " <>
        IO.ANSI.red() <>
        "#{pad(format_bool(code.aggregate_on_index), 6)} " <>
        "#{pad(code.aggregation_type || "-", 18)} " <>
        "#{pad(format_domains(code.domains), 30)} " <>
        "❌ MISMATCH" <>
        IO.ANSI.reset()
    )

    # Show DB values for comparison
    IO.puts(
      "  #{pad("  (DB has)", 20)} " <>
        IO.ANSI.yellow() <>
        "#{pad(format_bool(db.aggregate_on_index), 6)} " <>
        "#{pad(db.aggregation_type || "-", 18)} " <>
        "#{pad(format_domains(db.domains), 30)} " <>
        IO.ANSI.reset()
    )
  end

  defp fix_issues(issues) do
    IO.puts(IO.ANSI.blue() <> "🔧 Fixing #{length(issues)} issue(s)..." <> IO.ANSI.reset())
    IO.puts("")

    Enum.each(issues, fn issue ->
      fix_issue(issue)
    end)

    IO.puts(IO.ANSI.green() <> "✅ All issues fixed!" <> IO.ANSI.reset())
    IO.puts("")
  end

  defp fix_issue(%{status: :missing, slug: slug, code: _code}) do
    IO.puts("  Creating source: #{slug}")

    module = @source_configs[slug]
    config = module.source_config()

    {:ok, _source} = EventasaurusDiscovery.Sources.SourceStore.get_or_create_source(config)
    IO.puts("    #{IO.ANSI.green()}✓ Created#{IO.ANSI.reset()}")
  end

  defp fix_issue(%{status: :mismatch, slug: slug, code: code}) do
    IO.puts("  Updating source: #{slug}")

    source = Repo.get_by!(Source, slug: slug)

    attrs = %{
      aggregate_on_index: code.aggregate_on_index,
      aggregation_type: code.aggregation_type,
      domains: code.domains
    }

    {:ok, _updated} =
      source
      |> Source.changeset(attrs)
      |> Repo.update()

    IO.puts("    #{IO.ANSI.green()}✓ Updated#{IO.ANSI.reset()}")
  end

  # Helper functions

  defp get_val(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp format_bool(true), do: "yes"
  defp format_bool(false), do: "no"
  defp format_bool(nil), do: "-"

  defp format_domains(nil), do: "-"
  defp format_domains([]), do: "-"
  defp format_domains(domains) when is_list(domains), do: Enum.join(domains, ", ")

  defp pad(str, width) do
    str
    |> to_string()
    |> String.slice(0, width)
    |> String.pad_trailing(width)
  end
end
