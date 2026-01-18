defmodule Mix.Tasks.Audit.MetadataCoverage do
  @moduledoc """
  Audit metadata raw data coverage for all scrapers.

  Verifies that scrapers are properly preserving raw upstream data in metadata
  using one of the standard patterns:
  - `_raw_upstream` (standardized field)
  - `raw_data` (legacy pattern)
  - `raw_event_data` (Sortiraparis pattern)

  ## Usage

      # Check all sources (last 7 days by default)
      mix audit.metadata_coverage

      # Check specific number of days
      mix audit.metadata_coverage --days 14

      # Check specific source only
      mix audit.metadata_coverage --source cinema_city

      # Only show events after a specific date (for post-deployment validation)
      mix audit.metadata_coverage --after 2025-01-20

      # Show sample metadata for debugging
      mix audit.metadata_coverage --sample

  ## Output

  Shows per-source breakdown including:
  - Total event count
  - Events with raw data preserved
  - Coverage percentage
  - Status indicator (OK, LOW, MISSING)
  """

  use Mix.Task
  require Logger

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.SourcePatterns
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource

  @shortdoc "Audit metadata raw data coverage for all scrapers"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [days: :integer, source: :string, after: :string, sample: :boolean],
        aliases: [d: :days, s: :source, a: :after]
      )

    days = opts[:days] || 7
    source = opts[:source]
    after_date = parse_after_date(opts[:after])
    show_sample = opts[:sample] || false

    # Validate source if provided
    if source && !SourcePatterns.valid_source?(source) do
      IO.puts(IO.ANSI.red() <> "❌ Unknown source: #{source}" <> IO.ANSI.reset())
      SourcePatterns.print_available_sources()
      System.halt(1)
    end

    sources_to_check =
      if source do
        [source]
      else
        SourcePatterns.all_cli_keys()
      end

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "📊 Metadata Coverage Audit" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 75) <> IO.ANSI.reset())

    if after_date do
      IO.puts("Filter: Events created after #{Date.to_string(after_date)}")
    else
      IO.puts("Period: Last #{days} days")
    end

    IO.puts("")

    # Table header
    IO.puts(
      "  #{pad("Source", 20)} #{pad("Events", 10)} #{pad("Has Raw", 10)} #{pad("Coverage", 10)} Status"
    )

    IO.puts("  #{String.duplicate("─", 70)}")

    # Collect results
    results =
      Enum.map(sources_to_check, fn source_key ->
        result = check_source_coverage(source_key, days, after_date)
        display_source_row(source_key, result)
        result
      end)

    # Summary
    IO.puts("  #{String.duplicate("─", 70)}")
    display_summary(results)

    # Sample data if requested
    if show_sample do
      IO.puts("")
      display_sample_metadata(sources_to_check, after_date, days)
    end

    # Exit with error code if any source has <100% coverage
    has_issues = Enum.any?(results, fn r -> r.coverage < 100.0 and r.total > 0 end)

    if has_issues do
      IO.puts("")

      IO.puts(
        IO.ANSI.yellow() <>
          "⚠️  Some sources have incomplete raw data coverage" <> IO.ANSI.reset()
      )

      IO.puts("   Run with --sample to see metadata examples")
      System.halt(1)
    end
  end

  defp check_source_coverage(source_key, days, after_date) do
    # Convert CLI key (underscore) to registry slug (hyphen)
    source_slug = String.replace(source_key, "_", "-")

    case Repo.get_by(Source, slug: source_slug) do
      nil ->
        %{
          source_key: source_key,
          total: 0,
          has_raw: 0,
          coverage: 0.0,
          status: :not_found,
          avg_size: 0
        }

      source ->
        stats = fetch_coverage_stats(source.id, days, after_date)

        coverage =
          if stats.total > 0 do
            Float.round(stats.has_raw / stats.total * 100, 1)
          else
            0.0
          end

        status =
          cond do
            stats.total == 0 -> :no_data
            coverage == 100.0 -> :ok
            coverage >= 90.0 -> :good
            coverage >= 50.0 -> :low
            true -> :missing
          end

        %{
          source_key: source_key,
          total: stats.total,
          has_raw: stats.has_raw,
          coverage: coverage,
          status: status,
          avg_size: stats.avg_size
        }
    end
  end

  defp fetch_coverage_stats(source_id, days, after_date) do
    # Build date filter
    date_filter =
      if after_date do
        after_datetime = DateTime.new!(after_date, ~T[00:00:00], "Etc/UTC")
        dynamic([pes], pes.inserted_at >= ^after_datetime)
      else
        from_date = Date.add(Date.utc_today(), -days)
        from_datetime = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
        dynamic([pes], pes.inserted_at >= ^from_datetime)
      end

    # Query for total count and raw data presence
    # Check for any of the three raw data patterns:
    # - _raw_upstream (new standardized)
    # - raw_data (legacy pattern)
    # - raw_event_data (Sortiraparis)
    # Note: Using \? to escape the PostgreSQL JSONB ? operator
    query =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source_id,
        where: ^date_filter,
        select: %{
          total: count(pes.id),
          has_raw:
            count(
              fragment(
                "CASE WHEN metadata \\? '_raw_upstream' OR metadata \\? 'raw_data' OR metadata \\? 'raw_event_data' THEN 1 END"
              )
            ),
          avg_size: avg(fragment("pg_column_size(metadata)"))
        }
      )

    case Repo.replica().one(query) do
      nil ->
        %{total: 0, has_raw: 0, avg_size: 0}

      result ->
        avg_size =
          case result.avg_size do
            nil -> 0
            %Decimal{} = d -> d |> Decimal.to_float() |> round()
            n when is_number(n) -> round(n)
          end

        %{
          total: result.total || 0,
          has_raw: result.has_raw || 0,
          avg_size: avg_size
        }
    end
  end

  defp display_source_row(source_key, result) do
    display_name = SourcePatterns.get_display_name(source_key)

    {status_text, status_color} =
      case result.status do
        :ok -> {"✅ OK", IO.ANSI.green()}
        :good -> {"👍 GOOD", IO.ANSI.cyan()}
        :low -> {"⚠️ LOW", IO.ANSI.yellow()}
        :missing -> {"❌ MISSING", IO.ANSI.red()}
        :no_data -> {"📭 NO DATA", IO.ANSI.light_black()}
        :not_found -> {"❓ NOT FOUND", IO.ANSI.red()}
      end

    coverage_str =
      if result.total > 0 do
        "#{result.coverage}%"
      else
        "-"
      end

    IO.puts(
      "  #{pad(display_name, 20)} " <>
        "#{pad(format_number(result.total), 10)} " <>
        "#{pad(format_number(result.has_raw), 10)} " <>
        "#{pad(coverage_str, 10)} " <>
        status_color <> status_text <> IO.ANSI.reset()
    )
  end

  defp display_summary(results) do
    total_events = Enum.sum(Enum.map(results, & &1.total))
    total_with_raw = Enum.sum(Enum.map(results, & &1.has_raw))

    overall_coverage =
      if total_events > 0 do
        Float.round(total_with_raw / total_events * 100, 1)
      else
        0.0
      end

    sources_ok = Enum.count(results, fn r -> r.status == :ok end)
    sources_with_data = Enum.count(results, fn r -> r.total > 0 end)

    IO.puts(
      "  #{pad("TOTAL", 20)} " <>
        "#{pad(format_number(total_events), 10)} " <>
        "#{pad(format_number(total_with_raw), 10)} " <>
        "#{pad("#{overall_coverage}%", 10)} " <>
        "#{sources_ok}/#{sources_with_data} sources OK"
    )

    IO.puts("")

    if overall_coverage == 100.0 and sources_with_data > 0 do
      IO.puts(
        IO.ANSI.green() <>
          "✅ All sources have complete raw data coverage!" <> IO.ANSI.reset()
      )
    end
  end

  defp display_sample_metadata(sources_to_check, after_date, days) do
    IO.puts(IO.ANSI.cyan() <> "📝 Sample Metadata" <> IO.ANSI.reset())
    IO.puts(String.duplicate("─", 75))

    Enum.each(sources_to_check, fn source_key ->
      source_slug = String.replace(source_key, "_", "-")

      case Repo.get_by(Source, slug: source_slug) do
        nil ->
          :ok

        source ->
          display_source_sample(source, source_key, after_date, days)
      end
    end)
  end

  defp display_source_sample(source, source_key, after_date, days) do
    date_filter =
      if after_date do
        after_datetime = DateTime.new!(after_date, ~T[00:00:00], "Etc/UTC")
        dynamic([pes], pes.inserted_at >= ^after_datetime)
      else
        from_date = Date.add(Date.utc_today(), -days)
        from_datetime = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
        dynamic([pes], pes.inserted_at >= ^from_datetime)
      end

    # Get one sample with raw data
    sample_with_raw =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source.id,
        where: ^date_filter,
        where:
          fragment(
            "metadata \\? '_raw_upstream' OR metadata \\? 'raw_data' OR metadata \\? 'raw_event_data'"
          ),
        limit: 1,
        select: %{
          id: pes.id,
          external_id: pes.external_id,
          metadata: pes.metadata,
          size: fragment("pg_column_size(metadata)")
        }
      )
      |> Repo.replica().one()

    # Get one sample without raw data (if any)
    sample_without_raw =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source.id,
        where: ^date_filter,
        where:
          fragment(
            "NOT (metadata \\? '_raw_upstream' OR metadata \\? 'raw_data' OR metadata \\? 'raw_event_data')"
          ),
        limit: 1,
        select: %{
          id: pes.id,
          external_id: pes.external_id,
          metadata: pes.metadata
        }
      )
      |> Repo.replica().one()

    display_name = SourcePatterns.get_display_name(source_key)
    IO.puts("")
    IO.puts(IO.ANSI.blue() <> "#{display_name}:" <> IO.ANSI.reset())

    if sample_with_raw do
      raw_key = detect_raw_key(sample_with_raw.metadata)
      IO.puts("  ✅ Sample with raw data (ID: #{sample_with_raw.id}):")
      IO.puts("     External ID: #{sample_with_raw.external_id}")
      IO.puts("     Raw key: #{raw_key}")
      IO.puts("     Metadata size: #{sample_with_raw.size} bytes")

      # Show top-level keys in raw data
      if raw_key && sample_with_raw.metadata[raw_key] do
        raw_data = sample_with_raw.metadata[raw_key]

        keys =
          if is_map(raw_data) do
            Map.keys(raw_data) |> Enum.take(10) |> Enum.join(", ")
          else
            "(not a map)"
          end

        IO.puts("     Raw data keys: #{keys}")
      end
    else
      IO.puts("  ⚠️  No samples with raw data found")
    end

    if sample_without_raw do
      IO.puts("  ❌ Sample WITHOUT raw data (ID: #{sample_without_raw.id}):")
      IO.puts("     External ID: #{sample_without_raw.external_id}")
      keys = Map.keys(sample_without_raw.metadata) |> Enum.take(10) |> Enum.join(", ")
      IO.puts("     Metadata keys: #{keys}")
    end
  end

  defp detect_raw_key(metadata) when is_map(metadata) do
    cond do
      Map.has_key?(metadata, "_raw_upstream") -> "_raw_upstream"
      Map.has_key?(metadata, "raw_data") -> "raw_data"
      Map.has_key?(metadata, "raw_event_data") -> "raw_event_data"
      true -> nil
    end
  end

  defp detect_raw_key(_), do: nil

  defp parse_after_date(nil), do: nil

  defp parse_after_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp format_number(n) when is_integer(n) and n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(n), do: to_string(n)

  defp pad(str, width) do
    str
    |> to_string()
    |> String.pad_trailing(width)
  end
end
