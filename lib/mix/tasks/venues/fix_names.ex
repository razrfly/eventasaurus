defmodule Mix.Tasks.Venues.FixNames do
  use Mix.Task

  @shortdoc "Fix venue names using geocoding metadata"

  @moduledoc """
  Fixes venue names in a specific city by extracting better names from geocoding metadata.

  ## Examples

      # Preview what would be fixed in Warsaw
      mix venues.fix_names warsaw --dry-run

      # Fix only severe cases (very low similarity < 0.3)
      mix venues.fix_names warsaw --severity severe

      # Fix all venue name issues in Warsaw
      mix venues.fix_names warsaw --severity all

      # Fix without confirmation prompt
      mix venues.fix_names warsaw --yes

  ## Options

      --dry-run       Preview changes without applying them
      --severity      Filter by severity: severe, moderate, or all (default: all)
      --yes           Skip confirmation prompt
  """

  alias EventasaurusApp.Venues.VenueNameFixer

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [dry_run: :boolean, severity: :string, yes: :boolean],
        aliases: [d: :dry_run, s: :severity, y: :yes]
      )

    case args do
      [city_slug] ->
        severity = parse_severity(opts[:severity])
        dry_run = opts[:dry_run] || false
        skip_confirm = opts[:yes] || false

        fix_venues(city_slug, severity, dry_run, skip_confirm)

      _ ->
        Mix.shell().error("Usage: mix venues.fix_names CITY_SLUG [OPTIONS]")
        Mix.shell().info("")
        Mix.shell().info("Examples:")
        Mix.shell().info("  mix venues.fix_names warsaw --dry-run")
        Mix.shell().info("  mix venues.fix_names warsaw --severity severe")
        exit({:shutdown, 1})
    end
  end

  defp parse_severity(nil), do: :all
  defp parse_severity("severe"), do: :severe
  defp parse_severity("moderate"), do: :moderate
  defp parse_severity("all"), do: :all

  defp parse_severity(invalid) do
    Mix.shell().error("Invalid severity: #{invalid}")
    Mix.shell().error("Must be: severe, moderate, or all")
    exit({:shutdown, 1})
  end

  defp fix_venues(city_slug, severity, dry_run, skip_confirm) do
    Mix.shell().info("#{IO.ANSI.bright()}Scanning venues in #{city_slug}...#{IO.ANSI.reset()}")
    Mix.shell().info("")

    venues = VenueNameFixer.find_venues_with_quality_issues(city_slug, severity)

    case venues do
      [] ->
        Mix.shell().info("#{IO.ANSI.green()}✓ No venue name quality issues found!#{IO.ANSI.reset()}")

      venues ->
        Mix.shell().info("Found #{length(venues)} venues with name quality issues")
        Mix.shell().info("")

        # Show severity breakdown
        severe_count = Enum.count(venues, &(&1.severity == :severe))
        moderate_count = Enum.count(venues, &(&1.severity == :moderate))

        Mix.shell().info("#{IO.ANSI.bright()}Severity breakdown:#{IO.ANSI.reset()}")
        Mix.shell().info("  #{IO.ANSI.red()}🔴 Severe (< 0.3):#{IO.ANSI.reset()}    #{severe_count} venues")
        Mix.shell().info("  #{IO.ANSI.yellow()}⚠️  Moderate (< 0.7):#{IO.ANSI.reset()}  #{moderate_count} venues")
        Mix.shell().info("")

        # Process each venue and collect results
        Mix.shell().info("#{IO.ANSI.bright()}Changes to apply (--severity #{severity}):#{IO.ANSI.reset()}")
        Mix.shell().info("")

        results =
          venues
          |> Enum.with_index(1)
          |> Enum.map(fn {assessment, index} ->
            result = VenueNameFixer.fix_venue_name(assessment, dry_run: true, check_duplicates: true)
            {assessment, result, index}
          end)

        # Display each venue
        Enum.each(results, fn {assessment, result, index} ->
          display_venue_change(assessment, result, index)
        end)

        # Show summary
        Mix.shell().info("")
        Mix.shell().info("#{IO.ANSI.bright()}Summary:#{IO.ANSI.reset()}")

        rename_count = Enum.count(results, fn {_, result, _} -> match?({:rename, _, _}, result) end)
        duplicate_count = Enum.count(results, fn {_, result, _} -> match?({:duplicate_detected, _, _}, result) end)
        skip_count = Enum.count(results, fn {_, result, _} -> match?({:skip, _}, result) end)

        Mix.shell().info("  #{IO.ANSI.green()}✅ Renames:#{IO.ANSI.reset()} #{rename_count} venues")
        Mix.shell().info("  #{IO.ANSI.yellow()}⚠️  Duplicates:#{IO.ANSI.reset()} #{duplicate_count} venues (need manual review)")
        Mix.shell().info("  #{IO.ANSI.yellow()}⏭️  Skipped:#{IO.ANSI.reset()} #{skip_count} venues")
        Mix.shell().info("")

        if dry_run do
          Mix.shell().info("#{IO.ANSI.yellow()}This was a dry run. No changes were applied.#{IO.ANSI.reset()}")
          Mix.shell().info("Run without --dry-run to apply changes.")
        else
          # Confirm before applying (only count renames, not duplicates)
          if skip_confirm || confirm_apply?(rename_count) do
            apply_fixes(results)
          else
            Mix.shell().info("Aborted.")
          end
        end
    end
  end

  defp display_venue_change(assessment, result, index) do
    venue = assessment.venue
    severity_icon = severity_icon(assessment.severity)
    similarity = format_similarity(assessment.similarity)

    Mix.shell().info("#{index}. #{IO.ANSI.bright()}Venue ##{venue.id}#{IO.ANSI.reset()}")
    Mix.shell().info("   Current:  #{IO.ANSI.yellow()}\"#{String.slice(assessment.current_name, 0..50)}\"#{IO.ANSI.reset()}")

    case result do
      {:rename, new_name, event_count} ->
        Mix.shell().info("   Geocoded: #{IO.ANSI.green()}\"#{String.slice(new_name, 0..50)}\"#{IO.ANSI.reset()}")
        Mix.shell().info("   Similarity: #{similarity} #{severity_icon}")
        Mix.shell().info("   Events: #{event_count}")
        Mix.shell().info("   Action: #{IO.ANSI.green()}Rename#{IO.ANSI.reset()}")

      {:duplicate_detected, existing_venue, event_count} ->
        Mix.shell().info("   Geocoded: #{IO.ANSI.green()}\"#{String.slice(assessment.geocoded_name, 0..50)}\"#{IO.ANSI.reset()}")
        Mix.shell().info("   Similarity: #{similarity} #{severity_icon}")
        Mix.shell().info("   #{IO.ANSI.yellow()}⚠️  Duplicate found:#{IO.ANSI.reset()} Venue ##{existing_venue.id} \"#{existing_venue.name}\"")
        Mix.shell().info("   Events: #{event_count}")
        Mix.shell().info("   Action: #{IO.ANSI.yellow()}Skip - needs manual review#{IO.ANSI.reset()}")

      {:skip, reason} ->
        Mix.shell().info("   #{IO.ANSI.faint()}Skipped: #{reason}#{IO.ANSI.reset()}")
    end

    Mix.shell().info("")
  end

  defp apply_fixes(results) do
    Mix.shell().info("#{IO.ANSI.bright()}Applying fixes...#{IO.ANSI.reset()}")
    Mix.shell().info("")

    actionable_results =
      results
      |> Enum.reject(fn {_, result, _} ->
        match?({:skip, _}, result) or match?({:duplicate_detected, _, _}, result)
      end)

    total = length(actionable_results)

    actionable_results
    |> Enum.with_index(1)
    |> Enum.each(fn {{assessment, _, _index}, progress} ->
      Mix.shell().info("[#{progress}/#{total}] Processing venue ##{assessment.venue.id}...")

      result = VenueNameFixer.fix_venue_name(assessment, dry_run: false, check_duplicates: true)

      case result do
        {:renamed, updated_venue, event_count} ->
          Mix.shell().info("  #{IO.ANSI.green()}✓ Renamed#{IO.ANSI.reset()} to \"#{updated_venue.name}\" (#{event_count} events)")

        {:duplicate_detected, existing_venue, _event_count} ->
          Mix.shell().info("  #{IO.ANSI.yellow()}⚠️  Duplicate#{IO.ANSI.reset()} of venue ##{existing_venue.id} - skipped")

        {:skip, reason} ->
          Mix.shell().info("  #{IO.ANSI.yellow()}⏭ Skipped:#{IO.ANSI.reset()} #{reason}")

        {:error, reason} ->
          Mix.shell().error("  #{IO.ANSI.red()}✗ Error:#{IO.ANSI.reset()} #{reason}")
      end
    end)

    Mix.shell().info("")
    Mix.shell().info("#{IO.ANSI.green()}✓ Done!#{IO.ANSI.reset()}")
  end

  defp confirm_apply?(count) do
    Mix.shell().info("#{IO.ANSI.yellow()}Apply #{count} changes? [y/N]#{IO.ANSI.reset()}")

    case IO.gets("") |> String.trim() |> String.downcase() do
      "y" -> true
      "yes" -> true
      _ -> false
    end
  end

  defp severity_icon(:severe), do: "#{IO.ANSI.red()}🔴#{IO.ANSI.reset()}"
  defp severity_icon(:moderate), do: "#{IO.ANSI.yellow()}⚠️#{IO.ANSI.reset()}"
  defp severity_icon(_), do: ""

  defp format_similarity(nil), do: "N/A"
  defp format_similarity(score), do: Float.round(score, 2)
end
